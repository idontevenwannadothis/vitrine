// The bands of SponsorBlock.h on the native player's progress bar, reimplemented from
// EeveeSpotify's SponsorBlockOverlay.swift (GPL-3.0): over the ECMKit slider's track, one colored
// band per visible part of the episode playing. The overlay's hit test answers nil so every touch
// is the slider's; there are no gestures of its own (submitting segments is not here). The
// redesign draws its own player, where this slider is not, and shows nothing.
#import "Core/SGCore.h"
#import "SponsorBlock.h"

#define kOverlayTag @"SGSponsorOverlay"

@interface SGSponsorOverlayView : UIView
@end

@implementation SGSponsorOverlayView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

static NSHashTable<UIView *> *sg_sliders;

// The slider's own track view, the bar the bands sit on; a 3 pt line across the middle when the
// track is not found by name.
static CGRect trackFrame(UIView *slider) {
    for (UIView *sub in slider.subviews) {
        NSString *name = NSStringFromClass([sub class]);
        if ([name containsString:@"AudioView"] || [name containsString:@"ProgressTrack"]) return sub.frame;
    }
    CGFloat height = MAX(2, MIN(4, slider.bounds.size.height));
    return CGRectMake(0, (slider.bounds.size.height - height) / 2, slider.bounds.size.width, height);
}

static void draw(UIView *slider) {
    for (UIView *sub in [slider.subviews copy]) {
        if ([sub.accessibilityIdentifier isEqualToString:kOverlayTag]) [sub removeFromSuperview];
    }
    if (!SGEnabled(SGKeySponsorBlockOverlay)) return;
    double duration = SGSponsorPlayingDuration();
    if (duration <= 0) return;

    NSMutableArray<SGSponsorSegment *> *visible = [NSMutableArray array];
    for (SGSponsorSegment *segment in SGSponsorPlayingSegments()) {
        if (segment.isSkip && SGSponsorActionFor(segment.category) != SGSponsorActionOff) [visible addObject:segment];
    }
    if (!visible.count) return;

    CGRect frame = trackFrame(slider);
    if (frame.size.width <= 0) return;
    SGSponsorOverlayView *overlay = [[SGSponsorOverlayView alloc] initWithFrame:frame];
    overlay.accessibilityIdentifier = kOverlayTag;
    overlay.backgroundColor = UIColor.clearColor;
    overlay.layer.zPosition = 1;
    for (SGSponsorSegment *segment in visible) {
        CGFloat x = (segment.start / duration) * frame.size.width;
        CGFloat width = MAX(2, ((segment.end - segment.start) / duration) * frame.size.width);
        UIView *band = [[UIView alloc] initWithFrame:CGRectMake(x, 0, width, frame.size.height)];
        band.backgroundColor = [SGSponsorColorFor(segment.category) colorWithAlphaComponent:0.65];
        band.layer.cornerRadius = MIN(1, frame.size.height / 2);
        band.userInteractionEnabled = NO;
        [overlay addSubview:band];
    }
    slider.clipsToBounds = NO;
    [slider addSubview:overlay];
    [slider bringSubviewToFront:overlay];
}

static void drawAll(void) {
    for (UIView *slider in sg_sliders.allObjects) draw(slider);
}

%hook _TtCO17NowPlaying_ECMKit11ProgressBar6Slider
- (void)layoutSubviews {
    %orig;
    UIView *slider = (UIView *)self;
    [sg_sliders addObject:slider];
    draw(slider);
}
%end

%ctor {
    if (!SGFlag(SGKeySponsorBlock, NO)) return;
    sg_sliders = [NSHashTable weakObjectsHashTable];
    [NSNotificationCenter.defaultCenter addObserverForName:SGSponsorSegmentsChangedNotification object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) { drawAll(); }];
    %init;
    SGRequireClasses(@[@"_TtCO17NowPlaying_ECMKit11ProgressBar6Slider"]);
}
