// Talks to the SponsorBlock community API (sponsor.ajay.app), reimplemented from EeveeSpotify's
// SponsorBlockAPI.swift / SponsorBlockHash.swift (GPL-3.0). The endpoint's shape and the Spotify
// "service" identifier follow Spot-SponsorBlock-Extension: the episode's id hashed to a 5-hex
// prefix, the segments of every episode under that prefix answered in one go.
#import "Core/SGCore.h"
#import "SponsorBlock.h"
#import "SponsorBlockAPI.h"
#import <CommonCrypto/CommonCrypto.h>

static NSString *sha256Prefix(NSString *input, NSUInteger length) {
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex substringToIndex:length];
}

static NSArray<SGSponsorSegment *> *parse(NSString *episodeID, NSArray<NSDictionary *> *json) {
    NSMutableArray<SGSponsorSegment *> *out = [NSMutableArray array];
    for (NSDictionary *obj in json) {
        if (![obj[@"videoID"] isEqualToString:episodeID]) continue;
        for (NSDictionary *s in obj[@"segments"] ?: @[]) {
            NSArray *pair = s[@"segment"];
            if (![pair isKindOfClass:NSArray.class] || pair.count != 2) continue;
            NSString *category = s[@"category"], *action = s[@"actionType"], *uuid = s[@"UUID"];
            if (!category.length || !action.length || !uuid.length) continue;
            SGSponsorSegment *segment = [SGSponsorSegment new];
            segment.start = [pair[0] doubleValue];
            segment.end = [pair[1] doubleValue];
            segment.category = category;
            segment.actionType = action;
            segment.uuid = uuid;
            segment.videoDuration = [s[@"videoDuration"] doubleValue];
            [out addObject:segment];
        }
    }
    [out sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"start" ascending:YES]]];
    return out;
}

void SGSponsorFetchSegments(NSString *episodeID, NSArray<NSString *> *categories,
                            void (^completion)(NSArray<SGSponsorSegment *> *segments, NSError *error)) {
    if (!categories.count) {
        completion(@[], nil);
        return;
    }
    NSString *server = @"https://sponsor.ajay.app";
    NSURLComponents *components = [NSURLComponents componentsWithString:server];
    components.path = [@"/api/skipSegments/" stringByAppendingString:sha256Prefix(episodeID, 5)];
    NSMutableArray<NSString *> *quoted = [NSMutableArray array];
    for (NSString *category in categories) [quoted addObject:[NSString stringWithFormat:@"\"%@\"", category]];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"service" value:@"Spotify"],
        [NSURLQueryItem queryItemWithName:@"categories" value:[NSString stringWithFormat:@"[%@]", [quoted componentsJoinedByString:@","]]],
    ];
    NSURL *url = components.URL;
    if (!url) {
        completion(nil, [NSError errorWithDomain:@"SGSponsorBlock" code:1 userInfo:nil]);
        return;
    }

    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 8;
        config.timeoutIntervalForResource = 10;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        session = [NSURLSession sessionWithConfiguration:config];
    });

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"Vitrine-SponsorBlock/1" forHTTPHeaderField:@"X-CLIENT-NAME"];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (status == 404) {   // no episode under the hash prefix
            completion(@[], nil);
            return;
        }
        if (status < 200 || status >= 300) {
            completion(nil, [NSError errorWithDomain:@"SGSponsorBlock" code:status userInfo:nil]);
            return;
        }
        NSArray *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![json isKindOfClass:NSArray.class]) {
            completion(nil, [NSError errorWithDomain:@"SGSponsorBlock" code:2 userInfo:nil]);
            return;
        }
        completion(parse(episodeID, json), nil);
    }] resume];
}
