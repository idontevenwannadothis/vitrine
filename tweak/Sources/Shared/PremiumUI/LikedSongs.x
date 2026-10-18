// The Liked Songs row on an artist page, which Spotify only builds for an account it thinks is Premium.
// EeveeSpotifyReincarnated's LikedSongsEnabler, reimplemented: the row is put into the artist hub's JSON
// as the builder takes it, at the head of the artist tab's list, or just above the top tracks block when
// the page has no tab container. This hooks the same HUBViewModelBuilderImplementation method as
// AdBlock/AdHubs.x; both call through, and neither's edit depends on the other's.
#import "Core/SGCore.h"
#import "PremiumUI.h"

static NSInteger SGPremiumUIIndexOfId(NSArray *components, NSString *wanted) {
    for (NSUInteger i = 0; i < components.count; i++) {
        id component = components[i];
        if ([component isKindOfClass:NSDictionary.class] && [component[@"id"] isEqual:wanted]) return (NSInteger)i;
    }
    return NSNotFound;
}

// Spotify's own "liked_songs" string when this bundle has it, an English one otherwise.
static NSDictionary *SGPremiumUILikedRow(void) {
    NSString *title = [NSBundle.mainBundle localizedStringForKey:@"liked_songs" value:@"Liked Songs" table:nil];
    return @{@"id": @"artist-entity-view-liked-tracks-row", @"text": @{@"title": title}};
}

%hook HUBViewModelBuilderImplementation
- (void)addJSONDictionary:(NSDictionary *)dictionary {
    if (![dictionary[@"id"] isEqual:@"artist-entity-view"] || ![dictionary[@"body"] isKindOfClass:NSArray.class]) {
        %orig;
        return;
    }
    NSMutableArray *components = [dictionary[@"body"] mutableCopy];
    NSInteger tab = SGPremiumUIIndexOfId(components, @"artist-entity-view-artist-tab-container");
    if (tab != NSNotFound) {
        NSDictionary *tabComponent = components[tab];
        NSArray *children = tabComponent[@"children"];
        if ([children isKindOfClass:NSArray.class] && children.count
            && [children[0] isKindOfClass:NSDictionary.class] && [children[0][@"children"] isKindOfClass:NSArray.class]) {
            NSMutableDictionary *first = [children[0] mutableCopy];
            NSMutableArray *inner = [first[@"children"] mutableCopy];
            [inner insertObject:SGPremiumUILikedRow() atIndex:0];
            first[@"children"] = inner;
            NSMutableArray *childrenCopy = [children mutableCopy];
            childrenCopy[0] = first;
            NSMutableDictionary *tabCopy = [tabComponent mutableCopy];
            tabCopy[@"children"] = childrenCopy;
            components[tab] = tabCopy;
        }
    } else {
        NSInteger top = SGPremiumUIIndexOfId(components, @"artist-entity-view-top-tracks-combined");
        if (top != NSNotFound) [components insertObject:SGPremiumUILikedRow() atIndex:top];
    }
    NSMutableDictionary *copy = [dictionary mutableCopy];
    copy[@"body"] = components;
    %orig(copy);
}
%end

%ctor {
    if (!SGEnabled(SGKeyLikedSongs)) return;
    if (!NSClassFromString(@"HUBViewModelBuilderImplementation")) {
        SGLog(@"premiumui: HUBViewModelBuilderImplementation missing, liked songs row inactive");
        return;
    }
    %init;
}
