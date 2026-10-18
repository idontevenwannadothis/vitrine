// Clean shared links: the tracking Spotify adds to the open.spotify.com links it copies and shares, taken off.
// Foundation only, so it runs on whatever thread the share sheet asks on and in the Mac check
// (harness/clean-links).
//
// What goes is what says who shared the link and from where: si, nd, pt, context and every utm_. What the link
// opens stays: the path with its intl-xx/ segment, the fragment, and every other parameter in its order --
// t, above all, the second a shared episode starts at.
#import "Privacy.h"

static NSString *const kHost = @"open.spotify.com";

static BOOL isTracking(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower isEqualToString:@"si"] || [lower isEqualToString:@"nd"] || [lower isEqualToString:@"pt"] ||
           [lower isEqualToString:@"context"] || [lower hasPrefix:@"utm_"];
}

NSURL *SGCleanLinkURL(NSURL *url) {
    // The host checked before it is compared: a nil one would compare as the same.
    if (![url isKindOfClass:NSURL.class] || !url.host || [url.host caseInsensitiveCompare:kHost] != NSOrderedSame) return url;
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    // The encoded items, so what is kept goes back byte for byte as it came.
    NSArray<NSURLQueryItem *> *items = parts.percentEncodedQueryItems;
    if (!items.count) return url;
    NSMutableArray<NSURLQueryItem *> *kept = [NSMutableArray array];
    for (NSURLQueryItem *item in items) {
        if (!isTracking(item.name)) [kept addObject:item];
    }
    if (kept.count == items.count) return url;
    // nil and not an empty list: an empty one leaves the "?" behind.
    parts.percentEncodedQueryItems = kept.count ? kept : nil;
    return parts.URL ?: url;
}

NSString *SGCleanLinksInText(NSString *text) {
    if (![text isKindOfClass:NSString.class] || [text rangeOfString:kHost options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return text;
    }
    // The detector rather than a pattern of its own: it knows where a link in a sentence ends, so a full stop
    // or a closing bracket after it is not read as the end of the last parameter and taken off with it.
    static NSDataDetector *detector;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:NULL]; });
    NSArray<NSTextCheckingResult *> *matches = [detector matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    NSMutableString *cleaned = nil;
    // From the end, so the ranges still to come are where they were.
    for (NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        // The link as written, not the detector's reading of it, which puts a scheme on a bare host.
        NSString *written = [text substringWithRange:match.range];
        NSURL *url = [NSURL URLWithString:written];
        NSURL *clean = SGCleanLinkURL(url);
        if (!url || clean == url) continue;
        if (!cleaned) cleaned = [text mutableCopy];
        [cleaned replaceCharactersInRange:match.range withString:clean.absoluteString];
    }
    return cleaned ? [cleaned copy] : text;
}

id SGCleanLinkObject(id object) {
    if ([object isKindOfClass:NSURL.class]) return SGCleanLinkURL(object);
    if ([object isKindOfClass:NSString.class]) return SGCleanLinksInText(object);
    return object;
}

// A link the app opens in another app: the share sheet's direct-destination buttons (WhatsApp,
// Instagram, Telegram...) skip the pasteboard and the sheet and hand the Spotify link over inside
// a deep link instead -- whatsapp://send?text=...open.spotify.com/track/...?si=... -- so the
// tracking is taken off here, at the process boundary (EeveeSpotifyReincarnated's deep link
// cleaning, reimplemented).
NSURL *SGCleanDeepLinkURL(NSURL *url) {
    if (![url isKindOfClass:NSURL.class]) return url;
    // The link being opened is itself a Spotify share link.
    if (url.host && [url.host caseInsensitiveCompare:kHost] == NSOrderedSame) return SGCleanLinkURL(url);
    // Spotify links embedded in query values. URLComponents decodes each value, so the text
    // cleaner sees the plain https://...?si=... form; assigning back re-encodes. Only the changed
    // values rebuild, and receivers decode query strings leniently, so the re-encoding of the
    // untouched items is safe.
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSArray<NSURLQueryItem *> *items = parts.queryItems;
    if (items.count) {
        NSMutableArray<NSURLQueryItem *> *cleaned = nil;
        for (NSUInteger i = 0; i < items.count; i++) {
            NSURLQueryItem *item = items[i];
            if (!item.value) continue;
            NSString *clean = SGCleanLinksInText(item.value);
            if (clean == item.value) continue;
            if (!cleaned) cleaned = [items mutableCopy];
            cleaned[i] = [NSURLQueryItem queryItemWithName:item.name value:clean];
        }
        if (cleaned) {
            parts.queryItems = cleaned;
            if (parts.URL) return parts.URL;
        }
    }
    // A payload URLComponents cannot parse: clean any Spotify links in the raw string.
    NSString *raw = url.absoluteString;
    NSString *clean = SGCleanLinksInText(raw);
    return clean == raw ? url : [NSURL URLWithString:clean] ?: url;
}

// Pasteboard bytes that are not text: an NSURL keyed-archived under public.url. Secure coding
// only; anything else comes back as it is.
NSData *SGCleanLinkData(NSData *data) {
    if (![data isKindOfClass:NSData.class]) return data;
    NSURL *url = [NSKeyedUnarchiver unarchivedObjectOfClass:NSURL.class fromData:data error:NULL];
    if (!url) return data;
    NSURL *clean = SGCleanLinkURL(url);
    if (clean == url) return data;
    NSData *rearchived = [NSKeyedArchiver archivedDataWithRootObject:clean requiringSecureCoding:YES error:NULL];
    return rearchived ?: data;
}
