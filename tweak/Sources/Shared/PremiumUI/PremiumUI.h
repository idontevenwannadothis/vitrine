// The parts of the app a Free account is not shown, made to show. Ported from EeveeSpotifyReincarnated's
// Sources/EeveeSpotify/Premium/ (GPL-3.0) and reimplemented for the mod: the hooks are re-derived, the
// keys are this mod's, and none of it needs Spoof Premium - these are the pieces it would otherwise
// only be able to unlock through the account state.
//
//   TrackRows    the artist page lists its top tracks with play controls instead of a collapsed card
//   LikedSongs   the artist page carries a Liked Songs row above the tracks
//   TrueShuffle  shuffle stops Smart Shuffle injecting recommended, non-playlist tracks
//   SiriRadio    "Play <artist>" from Siri plays the artist, not a radio station made from it
//
// Each is on until switched off: they are the Spotify++ defaults, and a reset (stock) turns them
// off with everything else. Works under either look: these are Spotify's own screens' behavior.
#import <UIKit/UIKit.h>
#import "Settings/SGModPage.h"

#define SGKeyTrackRows   @"spotifyglass.premiumui.trackRows"
#define SGKeyLikedSongs  @"spotifyglass.premiumui.likedSongs"
#define SGKeyTrueShuffle @"spotifyglass.premiumui.trueShuffle"
#define SGKeySiriRadio   @"spotifyglass.premiumui.siriRadio"

// PremiumUISettings.m: the section, added to the Premium, ads & privacy page.
SGModSection *SGPremiumUISection(void);
