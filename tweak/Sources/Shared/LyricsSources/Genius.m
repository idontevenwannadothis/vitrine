// Genius, reimplemented from EeveeSpotify's GeniusLyricsRepository.swift (GPL-3.0): the mobile
// API's song search, the likeliest hit's page read as plain text. Nothing is timed — Genius is
// the wide catalog of last resort's words, and a source after it that times anything still wins
// the merge. The meanings of a line come from the same site the other way (Shared/LyricsMeanings).
#import "Core/SGCore.h"
#import "LyricsSources.h"

static NSString *const kSearch = @"https://api.genius.com/search/song";
static NSString *const kSong = @"https://api.genius.com/songs/";

static NSDictionary<NSString *, NSString *> *headers(void) {
    return @{@"X-Genius-iOS-Version": @"6.21.0",
             @"X-Genius-Logged-Out": @"true",
             @"User-Agent": @"Genius/1109"};
}

// "Song (feat. X) - Remastered 2011" as Genius titles it: "Song".
static NSString *bareTitle(NSString *title) {
    NSString *bare = title ?: @"";
    NSRange dash = [bare rangeOfString:@" - "];
    if (dash.location != NSNotFound) bare = [bare substringToIndex:dash.location];
    static NSRegularExpression *brackets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        brackets = [NSRegularExpression regularExpressionWithPattern:@"\\s*[\\(\\[][^\\)\\]]*[\\)\\]]" options:0 error:nil];
    });
    bare = [brackets stringByReplacingMatchesInString:bare options:0 range:NSMakeRange(0, bare.length) withTemplate:@""];
    return [bare stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

static BOOL containsFolded(NSString *text, NSString *part) {
    return part.length && [text rangeOfString:part options:NSCaseInsensitiveSearch].location != NSNotFound;
}

// The hit whose title and artist both agree with the track, else the best titled one, else the
// first the search ranked — Genius's own ranking is better than nothing at all.
static NSDictionary *bestHit(NSArray *sections, NSString *title, NSString *artist) {
    NSMutableArray<NSDictionary *> *hits = [NSMutableArray array];
    for (NSDictionary *section in [sections isKindOfClass:NSArray.class] ? sections : @[]) {
        id list = [section isKindOfClass:NSDictionary.class] ? section[@"hits"] : nil;
        for (NSDictionary *hit in [list isKindOfClass:NSArray.class] ? list : @[]) {
            NSDictionary *song = [hit isKindOfClass:NSDictionary.class] ? hit[@"result"] : nil;
            if ([song isKindOfClass:NSDictionary.class] && [song[@"id"] isKindOfClass:NSNumber.class]) [hits addObject:song];
        }
    }
    if (!hits.count) return nil;
    NSString *wantArtist = SGLyricsLeadArtist(artist);
    NSMutableArray<NSDictionary *> *titled = [NSMutableArray array];
    for (NSDictionary *song in hits) {
        NSString *songTitle = [song[@"title"] isKindOfClass:NSString.class] ? song[@"title"] : @"";
        if (containsFolded(songTitle, title)) [titled addObject:song];
    }
    for (NSDictionary *song in titled) {
        NSString *names = [song[@"artist_names"] isKindOfClass:NSString.class] ? song[@"artist_names"] : @"";
        if (containsFolded(names, wantArtist) || containsFolded(names, artist)) return song;
    }
    return titled.count ? titled.firstObject : hits.firstObject;
}

// The page's plain text as lines: the [Chorus] headings out, the blank edges off, the empty rows
// inside kept as breaks.
static SGLyricsResult *resultFrom(NSString *plain) {
    if (![plain isKindOfClass:NSString.class] || !plain.length) return nil;
    static NSRegularExpression *heading;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        heading = [NSRegularExpression regularExpressionWithPattern:@"^\\[.*\\]$" options:0 error:nil];
    });
    NSMutableArray<NSString *> *rows = [NSMutableArray array];
    for (NSString *row in [plain componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *trimmed = [row stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([heading firstMatchInString:trimmed options:0 range:NSMakeRange(0, trimmed.length)]) continue;
        [rows addObject:trimmed];
    }
    while (rows.count && ![rows.firstObject length]) [rows removeObjectAtIndex:0];
    while (rows.count && ![rows.lastObject length]) [rows removeLastObject];
    if (!rows.count) return nil;
    NSMutableArray<NSNumber *> *starts = [NSMutableArray array];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (NSString *row in rows) {
        [starts addObject:@0];
        [texts addObject:row.length ? row : @"♪"];
    }
    SGLyricsResult *result = [SGLyricsResult new];
    result.starts = starts;
    result.texts = texts;
    result.karaokeLines = SGKaraokeStaticLines(texts);
    return result;
}

SGLyricsAsk SGGeniusAsk = ^(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) {
    NSString *title = bareTitle(query.title);
    if (!title.length || !query.artist.length) {
        SGLog(@"genius: nothing to search with for %@", query.trackID);
        done(nil);
        return;
    }
    NSString *text = [NSString stringWithFormat:@"%@ %@", title, SGLyricsLeadArtist(query.artist)];
    SGLyricsGetJSON(SGLyricsURL(kSearch, @{@"q": text}), headers(), ^(id root) {
        id response = [root isKindOfClass:NSDictionary.class] ? root[@"response"] : nil;
        NSDictionary *hit = bestHit([response isKindOfClass:NSDictionary.class] ? response[@"sections"] : nil, title, query.artist);
        if (!hit) {
            if (root) SGLog(@"genius: no hit for %@ by %@", title, query.artist);
            done(nil);
            return;
        }
        NSURL *url = SGLyricsURL([kSong stringByAppendingString:[hit[@"id"] stringValue]], @{@"text_format": @"plain"});
        SGLyricsGetJSON(url, headers(), ^(id songRoot) {
            id songResponse = [songRoot isKindOfClass:NSDictionary.class] ? songRoot[@"response"] : nil;
            id song = [songResponse isKindOfClass:NSDictionary.class] ? songResponse[@"song"] : nil;
            id lyrics = [song isKindOfClass:NSDictionary.class] ? song[@"lyrics"] : nil;
            NSString *plain = [lyrics isKindOfClass:NSDictionary.class] ? lyrics[@"plain"] : nil;
            SGLyricsResult *result = resultFrom(plain);
            SGLog(@"genius: %@ by %@ gave %@", title, query.artist,
                  result ? [NSString stringWithFormat:@"%lu untimed lines", (unsigned long)result.texts.count] : @"nothing");
            done(result);
        });
    });
};
