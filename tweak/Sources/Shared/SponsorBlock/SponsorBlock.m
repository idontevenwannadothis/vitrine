// The segment model, the categories and the switches' readers of SponsorBlock.h.
#import "Core/SGCore.h"
#import "SponsorBlock.h"

@implementation SGSponsorSegment
- (double)duration {
    return self.end - self.start;
}
- (BOOL)isSkip {
    return [self.actionType isEqualToString:@"skip"];
}
@end

BOOL SGSponsorBlockOn(void) {
    return SGFlag(SGKeySponsorBlock, NO);
}

NSArray<NSString *> *SGSponsorCategories(void) {
    return @[@"sponsor", @"selfpromo", @"interaction", @"intro", @"outro", @"preview", @"hook", @"filler", @"exclusive_access"];
}

NSString *SGSponsorCategoryName(NSString *category) {
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{@"sponsor": @"Sponsor", @"selfpromo": @"Self-Promo", @"interaction": @"Interaction",
                  @"intro": @"Intro", @"outro": @"Outro", @"preview": @"Preview", @"hook": @"Hook",
                  @"filler": @"Filler", @"exclusive_access": @"Exclusive Access"};
    });
    return names[category] ?: category;
}

NSString *SGSponsorCategoryShortName(NSString *category) {
    static NSDictionary<NSString *, NSString *> *short_;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        short_ = @{@"sponsor": @"sponsor", @"selfpromo": @"self-promo", @"interaction": @"interaction",
                   @"intro": @"intro", @"outro": @"outro", @"preview": @"preview", @"hook": @"hook",
                   @"filler": @"filler", @"exclusive_access": @"exclusive access"};
    });
    return short_[category] ?: category;
}

NSString *SGSponsorCategoryKey(NSString *category) {
    return [@"spotifyglass.sponsorblock.cat." stringByAppendingString:category];
}

SGSponsorAction SGSponsorDefaultAction(NSString *category) {
    // Sponsor, self-promo and "like and subscribe" skip themselves; the rest only ask to be shown.
    if ([@[@"sponsor", @"selfpromo", @"interaction"] containsObject:category]) return SGSponsorActionAutoSkip;
    return SGSponsorActionOff;
}

SGSponsorAction SGSponsorActionFor(NSString *category) {
    return (SGSponsorAction)SGInt(SGSponsorCategoryKey(category), SGSponsorDefaultAction(category));
}

UIColor *SGSponsorColorFor(NSString *category) {
    static NSDictionary<NSString *, NSNumber *> *colors;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        colors = @{@"sponsor": @(0x00D400), @"selfpromo": @(0xFFFF00), @"interaction": @(0xCC00FF),
                   @"intro": @(0x00FFFF), @"outro": @(0x0202ED), @"preview": @(0x008FD6),
                   @"hook": @(0x009088), @"filler": @(0x7300FF), @"exclusive_access": @(0x008A5C)};
    });
    NSNumber *rgb = colors[category];
    if (!rgb) return UIColor.grayColor;
    NSInteger v = rgb.integerValue;
    return [UIColor colorWithRed:((v & 0xFF0000) >> 16) / 255.0 green:((v & 0xFF00) >> 8) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

double SGSponsorMinDuration(void) {
    return SGInt(SGKeySponsorBlockMinTenths, 10) / 10.0;
}

BOOL SGSponsorLogOnly(void) {
    return SGFlag(SGKeySponsorBlockLogOnly, NO);
}
