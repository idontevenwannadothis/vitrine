// Siri's "Play <artist>" reaches Spotify as an INMediaItem whose identifier carries a base64 JSON
// play-command; a Free account's is restricted to play-as-radio, so Siri starts a station instead of the
// artist. EeveeSpotifyReincarnated's SiriNoPlayAsRadio, reimplemented: the restriction is dropped and the
// context URL loses its ":station" so the same command plays the artist. The identifier is rebuilt only
// when it is a play-command, is base64 JSON, and the restriction is exactly play-as-radio.
#import "Core/SGCore.h"
#import "PremiumUI.h"
#import <Intents/Intents.h>

%hook INMediaItem
- (NSString *)identifier {
    NSString *identifier = %orig;
    if (![identifier containsString:@"play-command"]) return identifier;
    NSArray<NSString *> *parts = [identifier componentsSeparatedByString:@":"];
    if (parts.count < 3) return identifier;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:parts[2] options:0];
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![json isKindOfClass:NSDictionary.class]) return identifier;
    NSDictionary *feedback = json[@"feedback_details"];
    NSDictionary *context = json[@"context"];
    if (![feedback isKindOfClass:NSDictionary.class] || ![feedback[@"restriction"] isEqual:@"play-as-radio"]) return identifier;
    if (![context isKindOfClass:NSDictionary.class] || ![context[@"url"] isKindOfClass:NSString.class]) return identifier;

    NSMutableDictionary *copy = [json mutableCopy];
    NSMutableDictionary *contextCopy = [context mutableCopy];
    contextCopy[@"url"] = [context[@"url"] stringByReplacingOccurrencesOfString:@":station" withString:@""];
    copy[@"context"] = contextCopy;
    NSData *rebuilt = [NSJSONSerialization dataWithJSONObject:copy options:0 error:nil];
    if (!rebuilt) return identifier;

    SGLog(@"premiumui: Siri play-command left radio for %@", contextCopy[@"url"]);
    return [NSString stringWithFormat:@"spotify:play-command:%@", [rebuilt base64EncodedStringWithOptions:0]];
}
%end

%ctor {
    if (!SGHidden(SGKeySiriRadio)) return;
    %init;
    SGRequireClasses(@[@"INMediaItem"]);
}
