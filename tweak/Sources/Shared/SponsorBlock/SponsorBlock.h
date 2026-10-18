// SponsorBlock for podcasts, reimplemented from EeveeSpotify's Sources/EeveeSpotify/SponsorBlock/
// (GPL-3.0): the crowd-sourced marks of sponsor.ajay.app for the episode playing are fetched by
// SponsorBlockAPI.m, held against the player's state by SponsorBlockSkipper.m — one of
// Shared/Player's state observers, with no hook of its own — and each part whose category is set to
// skip is jumped over with the player's own seekTo:, a toast naming what was skipped and offering
// Undo (SponsorBlockToast.m). The native player's progress bar shows the parts as colored bands
// (SponsorBlockOverlay.x on the ECMKit slider; the redesign draws its own player and shows none).
//
// Only episodes: a URI that is no spotify:episode: clears everything, so a music track is never
// sought. Submitting segments to the database is not here; it is read-only for now.
#import <UIKit/UIKit.h>

#define SGKeySponsorBlock @"spotifyglass.sponsorblock"                       // off until asked for
#define SGKeySponsorBlockToast @"spotifyglass.sponsorblock.toast"            // the Undo toast, on until off
#define SGKeySponsorBlockOverlay @"spotifyglass.sponsorblock.overlay"        // the bands, on until off
#define SGKeySponsorBlockRespectSeek @"spotifyglass.sponsorblock.respectSeek" // on until off
#define SGKeySponsorBlockLogOnly @"spotifyglass.sponsorblock.logOnly"        // log instead of seeking
#define SGKeySponsorBlockMinTenths @"spotifyglass.sponsorblock.minTenths"    // shortest part to act on, 0.1 s

// What to do with a marked part, stored per category as the choice row's index.
typedef NS_ENUM(NSInteger, SGSponsorAction) {
    SGSponsorActionOff = 0,
    SGSponsorActionShowOnly,   // a band on the bar, nothing more
    SGSponsorActionAskFirst,   // a toast offering Skip as the part starts
    SGSponsorActionAutoSkip,
};

// One marked part of an episode, from the database.
@interface SGSponsorSegment : NSObject
@property (nonatomic) double start, end;              // seconds
@property (nonatomic, copy) NSString *category;       // "sponsor", "selfpromo", …
@property (nonatomic, copy) NSString *actionType;     // the database's: "skip" or something else
@property (nonatomic, copy) NSString *uuid;
@property (nonatomic) double videoDuration;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) BOOL isSkip;          // actionType is "skip"
@end

BOOL SGSponsorBlockOn(void);

// The categories in display order, their names for the page and short names for the toast.
NSArray<NSString *> *SGSponsorCategories(void);
NSString *SGSponsorCategoryName(NSString *category);
NSString *SGSponsorCategoryShortName(NSString *category);
// The choice row's key for a category, and the action stored under it (the default when unset).
NSString *SGSponsorCategoryKey(NSString *category);
SGSponsorAction SGSponsorDefaultAction(NSString *category);
SGSponsorAction SGSponsorActionFor(NSString *category);
UIColor *SGSponsorColorFor(NSString *category);

double SGSponsorMinDuration(void);
BOOL SGSponsorLogOnly(void);

// The segments of the episode playing, its length and its id (nil for a music track or none),
// for the overlay; posted changes carry SGSponsorSegmentsChangedNotification.
NSArray<SGSponsorSegment *> *SGSponsorPlayingSegments(void);
double SGSponsorPlayingDuration(void);
extern NSNotificationName const SGSponsorSegmentsChangedNotification;

UIViewController *SGSponsorBlockSettingsPage(void);
