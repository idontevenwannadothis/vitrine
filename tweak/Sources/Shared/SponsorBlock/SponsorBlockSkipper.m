// The skipper of SponsorBlock.h, reimplemented from EeveeSpotify's SponsorBlockSkipper.swift
// (GPL-3.0). It is a Shared/Player state observer — the player reports on the main thread and every
// report is moved onto the queue here, which owns all of the state below. While an episode with
// segments plays, a 250 ms timer estimates the position between reports so a part is left within a
// beat of its start; every seek is the player's own seekTo: on the main thread.
//
// A seek of ours is told apart from one of the user's: the report landing within 1.5 s of the
// target before its deadline is ours, one still reading the position we sought from is stale (the
// player answered an older state first), anything else more than 2 s off the estimate is the
// user's — and with "Respect your seeks" on, a part sought into on purpose is left alone.
#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/AdBlock/AdBlock.h"
#import "SponsorBlock.h"
#import "SponsorBlockAPI.h"
#import "SponsorBlockToast.h"

NSNotificationName const SGSponsorSegmentsChangedNotification = @"SGSponsorSegmentsChanged";

static NSString *episodeOf(NSString *uri) {
    if ([uri hasPrefix:@"spotify:episode:"]) return [uri substringFromIndex:@"spotify:episode:".length];
    NSRange range = [uri rangeOfString:@"/episode/"];
    if (range.location == NSNotFound) return nil;
    NSString *rest = [uri substringFromIndex:NSMaxRange(range)];
    return [[rest componentsSeparatedByString:@"?"] firstObject];
}

static NSTimeInterval uptime(void) {
    return NSProcessInfo.processInfo.systemUptime;
}

@interface SGSponsorSkipper : NSObject <SGPlayerStateObserver>
@end

@implementation SGSponsorSkipper {
    dispatch_queue_t _queue;
    NSString *_episodeID;
    NSArray<SGSponsorSegment *> *_segments;
    BOOL _fetchInFlight;
    NSMutableSet<NSString *> *_emptyEpisodes;
    double _lastPosition;
    NSTimeInterval _lastStamp;
    double _lastSpeed;
    BOOL _lastPlaying;
    double _lastDuration;
    NSNumber *_pendingSeek;
    NSTimeInterval _seekDeadline;
    double _preSeekPosition;
    BOOL _hasPreSeek;
    NSMutableSet<NSString *> *_dismissed;
    NSMutableSet<NSString *> *_prompted;
    // Segments Undo lets play to their end; cleared by a seek of the user's, a natural pass of the
    // end, or a new episode.
    NSMutableSet<NSString *> *_playthrough;
    dispatch_source_t _timer;
    uint64_t _lastSeekMs;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = dispatch_queue_create("com.spotifyglass.sponsorblock", DISPATCH_QUEUE_SERIAL);
    _segments = @[];
    _emptyEpisodes = [NSMutableSet set];
    _dismissed = [NSMutableSet set];
    _prompted = [NSMutableSet set];
    _playthrough = [NSMutableSet set];
    _lastSpeed = 1;
    return self;
}

// The SGPlayerStateObserver callbacks; the required one is empty because the optional one hears
// every report first, change or not.
- (void)playerStateDidChange:(SPTPlayerState *)state {
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    NSString *episodeID = episodeOf(SGURIString(state.track.URI));
    double position = state.isPaused ? state.positionAsOfTimestamp : state.position;
    double duration = state.duration;
    double speed = state.playbackSpeed > 0 ? state.playbackSpeed : 1;
    BOOL playing = state.isPlaying && !state.isPaused;
    dispatch_async(_queue, ^{
        [self processEpisode:episodeID position:position duration:duration speed:speed playing:playing];
    });
}

- (void)processEpisode:(NSString *)episodeID position:(double)position duration:(double)duration
                 speed:(double)speed playing:(BOOL)playing {
    NSTimeInterval now = uptime();
    if (!episodeID.length) {
        [self stopPolling];
        if (_episodeID || _segments.count) {
            SGLog(@"sponsorblock: moved off an episode, clearing");
            _episodeID = nil;
            _segments = @[];
            _lastDuration = 0;
            _lastPlaying = NO;
            [self clearSeekMarks];
            [self broadcast];
        }
        return;
    }

    BOOL first = ![episodeID isEqualToString:_episodeID] || _lastStamp == 0;
    double expected = _lastPosition + (now - _lastStamp) * _lastSpeed;
    double delta = position - expected;
    BOOL ownSeek = _pendingSeek && now <= _seekDeadline && fabs(position - _pendingSeek.doubleValue) < 1.5;
    BOOL stale = _hasPreSeek && _pendingSeek && now <= _seekDeadline && fabs(position - _preSeekPosition) < 1.0;
    BOOL manualSeek = !first && !ownSeek && !stale && fabs(delta) > 2.0;

    if (manualSeek) {
        if (_playthrough.count) [_playthrough removeAllObjects];
        if (_lastPlaying && SGEnabled(SGKeySponsorBlockRespectSeek)) {
            for (SGSponsorSegment *segment in _segments) {
                if (position >= segment.start && position < segment.end && ![_dismissed containsObject:segment.uuid]) {
                    [_dismissed addObject:segment.uuid];
                    SGLog(@"sponsorblock: sought into %@ (%.1f..%.1f) on purpose, left alone",
                          segment.category, segment.start, segment.end);
                }
            }
        }
    }

    if (!stale) {
        _lastPosition = position;
        _lastStamp = now;
    }
    _lastSpeed = speed;
    _lastPlaying = playing;
    if (fabs(duration - _lastDuration) > 0.5) {
        _lastDuration = duration;
        [self broadcast];
    }

    if (first) {
        _episodeID = episodeID;
        _segments = @[];
        [_dismissed removeAllObjects];
        [_prompted removeAllObjects];
        [_playthrough removeAllObjects];
        [self clearSeekMarks];
        _fetchInFlight = NO;
        [self broadcast];
        [self fetch:episodeID];
    } else if (!_segments.count && !_fetchInFlight && ![_emptyEpisodes containsObject:episodeID]) {
        [self fetch:episodeID];
    }

    if (playing && _segments.count) [self startPolling];
    else [self stopPolling];

    if (!stale && !(manualSeek && SGEnabled(SGKeySponsorBlockRespectSeek))) {
        [self checkAndSkip:position];
    }
}

- (void)clearSeekMarks {
    _pendingSeek = nil;
    _hasPreSeek = NO;
}

- (void)fetch:(NSString *)episodeID {
    if (_fetchInFlight) return;
    _fetchInFlight = YES;
    NSMutableArray<NSString *> *categories = [NSMutableArray array];
    for (NSString *category in SGSponsorCategories()) {
        if (SGSponsorActionFor(category) != SGSponsorActionOff) [categories addObject:category];
    }
    SGLog(@"sponsorblock: fetching the marks of %@", episodeID);
    SGSponsorFetchSegments(episodeID, categories, ^(NSArray<SGSponsorSegment *> *segments, NSError *error) {
        dispatch_async(_queue, ^{
            _fetchInFlight = NO;
            if (![episodeID isEqualToString:_episodeID]) return;
            if (error) {
                SGLog(@"sponsorblock: fetch of %@ failed: %@", episodeID, error);
                return;
            }
            _segments = segments;
            [self broadcast];
            if (!segments.count) {
                [_emptyEpisodes addObject:episodeID];
                SGLog(@"sponsorblock: nothing filed for %@", episodeID);
                return;
            }
            for (SGSponsorSegment *segment in segments) {
                SGLog(@"sponsorblock:   %@ %.1f..%.1f (%.1f s)", segment.category, segment.start, segment.end, segment.duration);
            }
            if (SGEnabled(SGKeySponsorBlockRespectSeek)) {
                for (SGSponsorSegment *segment in segments) {
                    if (_lastPosition >= segment.start && _lastPosition < segment.end) [_dismissed addObject:segment.uuid];
                }
            }
            if (_lastPlaying) [self startPolling];
        });
    });
}

- (void)startPolling {
    if (_timer) return;
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), 250 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);
    __weak SGSponsorSkipper *weak = self;
    dispatch_source_set_event_handler(_timer, ^{
        SGSponsorSkipper *strong = weak;
        if (!strong || !strong->_lastPlaying) return;
        double estimate = strong->_lastPosition + (uptime() - strong->_lastStamp) * strong->_lastSpeed;
        [strong checkAndSkip:estimate];
    });
    dispatch_resume(_timer);
}

- (void)stopPolling {
    if (!_timer) return;
    dispatch_source_cancel(_timer);
    _timer = nil;
}

- (void)checkAndSkip:(double)position {
    if (!_segments.count || !_episodeID) return;

    if (_playthrough.count) {
        NSMutableSet *still = [NSMutableSet set];
        for (NSString *uuid in _playthrough) {
            for (SGSponsorSegment *segment in _segments) {
                if ([segment.uuid isEqualToString:uuid] && position < segment.end) [still addObject:uuid];
            }
        }
        [_playthrough intersectSet:still];
    }

    double minimum = SGSponsorMinDuration();
    BOOL respectSeek = SGEnabled(SGKeySponsorBlockRespectSeek);
    for (SGSponsorSegment *segment in _segments) {
        if (!segment.isSkip || segment.duration < minimum) continue;
        SGSponsorAction action = SGSponsorActionFor(segment.category);
        if (action != SGSponsorActionAutoSkip && action != SGSponsorActionAskFirst) continue;
        if (respectSeek && [_dismissed containsObject:segment.uuid]) continue;
        if ([_playthrough containsObject:segment.uuid]) continue;
        if (position < segment.start || position >= segment.end - 0.25) continue;

        if (action == SGSponsorActionAskFirst) {
            if ([_prompted containsObject:segment.uuid]) continue;
            [_prompted addObject:segment.uuid];
            NSString *title = [NSString stringWithFormat:@"%@ (%d s)", SGSponsorCategoryShortName(segment.category), (int)segment.duration];
            __weak SGSponsorSkipper *weak = self;
            [SGSponsorToast show:title action:@"Skip" duration:6 handler:^{
                [weak skipToEndOf:segment];
            }];
            continue;
        }

        // The 1.2 s cooldown: the estimated poll can fire twice before the player's own report of
        // the first seek lands, and both would seek.
        uint64_t nowMs = (uint64_t)(uptime() * 1000);
        if (nowMs - _lastSeekMs < 1200) return;
        _lastSeekMs = nowMs;

        SGLog(@"sponsorblock: skipping %@ %.1f..%.1f at %.1f", segment.category, segment.start, segment.end, position);
        if (SGSponsorLogOnly()) {
            SGLog(@"sponsorblock: log only, not seeking");
            return;
        }
        [self skipToEndOf:segment];
        SGAdBlockCountOne(@"Segments skipped");
        if (SGEnabled(SGKeySponsorBlockToast)) {
            NSString *title = [NSString stringWithFormat:@"Skipped %@", SGSponsorCategoryShortName(segment.category)];
            __weak SGSponsorSkipper *weak = self;
            [SGSponsorToast show:title action:@"Undo" duration:5 handler:^{
                [weak undoSkip:segment];
            }];
        }
        return;
    }
}

- (void)skipToEndOf:(SGSponsorSegment *)segment {
    double target = segment.end + 0.05;
    dispatch_async(_queue, ^{
        [self seekTo:target];
    });
}

- (void)undoSkip:(SGSponsorSegment *)segment {
    dispatch_async(_queue, ^{
        [_playthrough addObject:segment.uuid];
        [self seekTo:MAX(0, segment.start - 0.25)];
        SGLog(@"sponsorblock: skip of %@ undone, it plays through", segment.category);
    });
}

- (void)seekTo:(double)seconds {
    _preSeekPosition = _lastPosition;
    _hasPreSeek = YES;
    _pendingSeek = @(seconds);
    _seekDeadline = uptime() + 2.5;
    _lastPosition = seconds;
    _lastStamp = uptime();
    dispatch_async(dispatch_get_main_queue(), ^{
        id player = SGPlayer();
        if ([player respondsToSelector:@selector(seekTo:)]) {
            [(id<SPTPlayer>)player seekTo:seconds];
        } else {
            SGLog(@"sponsorblock: no player to seek to %.1f", seconds);
        }
    });
}

- (void)broadcast {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:SGSponsorSegmentsChangedNotification object:nil];
    });
}

- (NSArray<SGSponsorSegment *> *)segments {
    __block NSArray<SGSponsorSegment *> *segments;
    dispatch_sync(_queue, ^{ segments = _segments; });
    return segments;
}

- (double)duration {
    __block double duration;
    dispatch_sync(_queue, ^{ duration = _lastDuration; });
    return duration;
}

@end

static SGSponsorSkipper *sg_skipper;

NSArray<SGSponsorSegment *> *SGSponsorPlayingSegments(void) {
    return [sg_skipper segments] ?: @[];
}

double SGSponsorPlayingDuration(void) {
    return [sg_skipper duration];
}

__attribute__((constructor)) static void startSponsorBlock(void) {
    if (!SGFlag(SGKeySponsorBlock, NO)) return;
    sg_skipper = [SGSponsorSkipper new];
    SGAddPlayerStateObserver(sg_skipper);
    SGLog(@"sponsorblock: on");
}
