// Smart Shuffle pulls recommended, non-playlist tracks into a shuffled playlist. Two BOOL gates on the
// shuffle handler turn that off, leaving a real shuffle. EeveeSpotifyReincarnated's TrueShuffle,
// reimplemented: the class name carries a module prefix, so it is found by suffix, and the two methods
// are replaced only when they are there.
#import "Core/SGCore.h"
#import "PremiumUI.h"
#import <objc/runtime.h>

static Class SGPremiumUIClassWithSuffix(NSString *suffix) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    Class found = Nil;
    for (unsigned int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (name && [[NSString stringWithUTF8String:name] hasSuffix:suffix]) { found = classes[i]; break; }
    }
    free(classes);
    return found;
}

static void SGPremiumUIKillBool(Class cls, NSString *selectorName, BOOL takesArgument) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(selectorName));
    if (!method) {
        SGLog(@"premiumui: %s has no %@", class_getName(cls), selectorName);
        return;
    }
    if (takesArgument) method_setImplementation(method, imp_implementationWithBlock(^BOOL(id self, id argument) { return NO; }));
    else method_setImplementation(method, imp_implementationWithBlock(^BOOL(id self) { return NO; }));
}

%ctor {
    if (!SGHidden(SGKeyTrueShuffle)) return;
    Class cls = SGPremiumUIClassWithSuffix(@"SmartShuffleHandlerImplementation");
    if (!cls) {
        SGLog(@"premiumui: SmartShuffleHandler not found, true shuffle inactive");
        return;
    }
    SGPremiumUIKillBool(cls, @"checkRecommendationsEnabled", NO);
    SGPremiumUIKillBool(cls, @"recommendationIsBeingAddedWithTrackID:", YES);
    SGLog(@"premiumui: true shuffle on %s", class_getName(cls));
}
