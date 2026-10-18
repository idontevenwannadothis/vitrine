// The SponsorBlock page: the switch, what to do with each kind of marked part, how a skip is told
// and how a seek of the user's is treated. The switch is read as Spotify starts (the skipper
// registers and the overlay hooks only then), the rest as they are used.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "SponsorBlock.h"

UIViewController *SGSponsorBlockSettingsPage(void) {
    SGModRow *master = SGOptionRow(@"SponsorBlock", @"Skip sponsors, self-promotion and other marked parts of podcast episodes", SGKeySponsorBlock);

    NSMutableArray<SGModRow *> *categories = [NSMutableArray array];
    for (NSString *category in SGSponsorCategories()) {
        SGModRow *row = SGChoiceRow(SGSponsorCategoryName(category), nil, SGSponsorCategoryKey(category),
                                    @[@"Off", @"Show on the bar", @"Ask first", @"Skip"],
                                    SGSponsorDefaultAction(category));
        row.waitsOn = SGKeySponsorBlock;
        [categories addObject:row];
    }

    SGModRow *toast = SGSwitchRow(@"Say what was skipped", @"A toast after each skip, with Undo", SGKeySponsorBlockToast);
    toast.waitsOn = SGKeySponsorBlock;
    SGModRow *overlay = SGSwitchRow(@"Mark parts on the bar", @"Colored bands on the player's progress bar", SGKeySponsorBlockOverlay);
    overlay.waitsOn = SGKeySponsorBlock;
    SGModRow *respect = SGSwitchRow(@"Respect your seeks", @"A part you sought into on purpose is left alone", SGKeySponsorBlockRespectSeek);
    respect.waitsOn = SGKeySponsorBlock;

    SGModRow *minimum = SGSliderRow(@"Shortest part to act on", nil, 0, 10, 0.5,
        ^{ return SGInt(SGKeySponsorBlockMinTenths, 10) / 10.0; },
        ^(double value) { SGSetInt(SGKeySponsorBlockMinTenths, (NSInteger)(value * 10 + 0.5)); },
        ^(double value) { return [NSString stringWithFormat:@"%.1f s", value]; });
    minimum.waitsOn = SGKeySponsorBlock;
    SGModRow *logOnly = SGOptionRow(@"Log only", @"Count and log the skips without seeking", SGKeySponsorBlockLogOnly);
    logOnly.waitsOn = SGKeySponsorBlock;

    return [[SGModPage alloc] initWithTitle:@"SponsorBlock" intro:SGRestartNote sections:@[
        SGSection(nil, @[master]),
        SGNotedSection(@"Parts", categories,
            @"What to do with each kind of marked part, as the episode reaches it. “Show on the bar” only marks it."),
        SGSection(@"A skip", @[toast, overlay, respect]),
        SGSection(@"Tuning", @[minimum, logOnly]),
        SGSection(nil, @[SGLinkRow(@"SponsorBlock", @"The crowd-sourced database these marks come from", @"https://sponsor.ajay.app")]),
    ] footer:@"Marks exist for podcast episodes only, filed by SponsorBlock's users; an episode nobody has filed plays whole. Submitting marks of your own is not in Vitrine yet."];
}
