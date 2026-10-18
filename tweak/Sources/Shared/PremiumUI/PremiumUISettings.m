#import "Core/SGCore.h"
#import "PremiumUI.h"

SGModSection *SGPremiumUISection(void) {
    return SGNotedSection(@"Spotify++", @[
        SGWithSymbol(SGOptionRow(@"Track rows on artist pages", @"Top tracks as a list you can play from", SGKeyTrackRows), @"list.number"),
        SGWithSymbol(SGOptionRow(@"Liked Songs row", @"On an artist page, above the top tracks", SGKeyLikedSongs), @"heart"),
        SGWithSymbol(SGOptionRow(@"True shuffle", @"Stop Smart Shuffle adding recommended tracks", SGKeyTrueShuffle), @"shuffle"),
        SGWithSymbol(SGOptionRow(@"Siri plays songs, not radio", @"\"Play <artist>\" plays them, not a station", SGKeySiriRadio), @"waveform"),
    ], @"Parts of the app a Free account is not shown. They work with or without Spoof Premium, and apply after you restart Spotify.");
}
