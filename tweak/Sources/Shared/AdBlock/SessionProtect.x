// Spoof Premium's other half. The server's answer to an account it reads as free is to tear the
// session down, and AdNetwork.x answers the endpoints behind that as if they succeeded — but Spotify
// also tears it down from the inside: the auth session's logout and destroy, the connectivity
// session's automated logout-then-login, the legacy login controller's credential wipe, and an OAuth
// token bridge whose expiry turns the session over when it passes. Those are held here while Spoof
// Premium is on. A logout the user asks for still goes through: userInitiatedLogout on the main
// thread opens a five-second window the rest of the hooks let pass. EeveeSpotifyReincarnated's
// SessionProtection, reimplemented for Logos and the mod's layers, less its Ably hooks, which it does
// not turn on for 9.1 either. Class and selector names checked against the 9.1.90 binary.
#import "Core/SGCore.h"
#import "AdBlock.h"

// Set for five seconds around a logout the user asked for; everything else stays blocked.
static BOOL sg_allowLogout;

static void SGSessionBlocked(NSString *what) {
    SGAdBlockSawOne(@"Logouts");
    SGAdBlockCountOne(@"Logouts");
    SGLog(@"premium: blocked %@", what);
}

#pragma mark - SPTAuthSessionImplementation

%group SGAuthSession
%hook SPTAuthSessionImplementation
- (void)logout {
    if (sg_allowLogout) { %orig; return; }
    SGSessionBlocked(@"SPTAuthSession logout");
}
- (void)logoutWithReason:(id)reason {
    if (!sg_allowLogout) {
        SGSessionBlocked(@"SPTAuthSession logoutWithReason:");
        return;
    }
    %orig(reason);
}
- (void)callSessionDidLogoutOnDelegateWithReason:(id)reason {
    if (!sg_allowLogout) {
        SGSessionBlocked(@"SPTAuthSession callSessionDidLogoutOnDelegateWithReason:");
        return;
    }
    %orig(reason);
}
- (void)logWillLogoutEventWithLogoutReason:(id)reason {
    if (!sg_allowLogout) {
        SGSessionBlocked(@"SPTAuthSession logWillLogoutEventWithLogoutReason:");
        return;
    }
    %orig(reason);
}
- (void)destroy {
    if (sg_allowLogout) { %orig; return; }
    SGSessionBlocked(@"SPTAuthSession destroy");
}
%end
%end

#pragma mark - SessionServiceImpl (Connectivity_SessionImpl)

%group SGSessionService
%hook _TtC24Connectivity_SessionImpl18SessionServiceImpl
- (void)automatedLogoutThenLogin {
    SGSessionBlocked(@"SessionService automatedLogoutThenLogin");
}
- (void)userInitiatedLogout {
    // A "user" logout asked for off the main thread is the server's, not the user's.
    if (!NSThread.isMainThread) {
        SGSessionBlocked(@"SessionService userInitiatedLogout off the main thread");
        return;
    }
    SGAdBlockSawOne(@"Logouts");
    SGLog(@"premium: user asked to log out, allowed");
    sg_allowLogout = YES;
    %orig;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sg_allowLogout = NO;
    });
}
- (void)sessionDidLogout:(id)session withReason:(id)reason {
    if (!sg_allowLogout) {
        SGSessionBlocked(@"SessionService sessionDidLogout:withReason:");
        return;
    }
    %orig(session, reason);
}
%end
%end

#pragma mark - SPTAuthLegacyLoginControllerImplementation

%group SGLegacyLogin
%hook SPTAuthLegacyLoginControllerImplementation
- (void)sessionDidLogout:(id)session withReason:(id)reason {
    if (!sg_allowLogout) {
        SGSessionBlocked(@"legacy login sessionDidLogout:withReason:");
        return;
    }
    %orig(session, reason);
}
- (void)destroySession {
    if (sg_allowLogout) { %orig; return; }
    SGSessionBlocked(@"legacy login destroySession");
}
- (void)forgetStoredCredentials {
    if (sg_allowLogout) { %orig; return; }
    SGSessionBlocked(@"legacy login forgetStoredCredentials");
}
- (void)invalidate {
    if (sg_allowLogout) { %orig; return; }
    SGSessionBlocked(@"legacy login invalidate");
}
%end
%end

#pragma mark - OauthAccessTokenBridge

// A private Connectivity_SessionImpl class, so its mangled name carries a per-build hash; it is found
// by suffix the way TrueShuffle finds its handler. The bridge's C++ side writes _expiresAt without
// the ObjC setter, so the property hooks alone are not enough: the ivar is set far ahead on init and
// re-set every minute until the bridge is gone, and the getter and setter only ever see the far date.
static Class SGSessionClassWithSuffix(NSString *suffix) {
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

static NSDate *SGSessionFarFuture(void) {
    return [NSDate dateWithTimeIntervalSinceNow:365 * 24 * 60 * 60];
}

static void SGSessionExtendExpiry(id bridge) {
    Ivar ivar = class_getInstanceVariable(object_getClass(bridge), "_expiresAt");
    if (ivar) object_setIvar(bridge, ivar, SGSessionFarFuture());
}

static void SGSessionKeepExtending(id bridge) {
    __weak id weakBridge = bridge;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        id strong = weakBridge;
        if (!strong) return;
        SGSessionExtendExpiry(strong);
        SGSessionKeepExtending(strong);
    });
}

static void SGSessionHookTokenBridge(Class cls) {
    SEL expiresAt = NSSelectorFromString(@"expiresAt"), setExpiresAt = NSSelectorFromString(@"setExpiresAt:");
    Method getter = class_getInstanceMethod(cls, expiresAt);
    if (getter) {
        method_setImplementation(getter, imp_implementationWithBlock(^id(id self) {
            return SGSessionFarFuture();
        }));
    }
    Method setter = class_getInstanceMethod(cls, setExpiresAt);
    if (setter) {
        IMP origSet = method_getImplementation(setter);
        method_setImplementation(setter, imp_implementationWithBlock(^void(id self, id date) {
            ((void (*)(id, SEL, id))origSet)(self, setExpiresAt, SGSessionFarFuture());
        }));
    }
    Method initMethod = class_getInstanceMethod(cls, @selector(init));
    if (!initMethod) {
        SGLog(@"premium: %s has no init, token expiry held at the property only", class_getName(cls));
        return;
    }
    // alloc/init's +1 through a cast IMP is ARC's blind spot: void * both ways, CFBridgingRelease hands
    // it to ARC once, and the caller's retain is untouched (AGENTS.md).
    IMP origInit = method_getImplementation(initMethod);
    method_setImplementation(initMethod, imp_implementationWithBlock(^id(void *raw) {
        void *result = ((void *(*)(void *, SEL))origInit)(raw, @selector(init));
        id self = CFBridgingRelease(result);
        if (self) {
            SGSessionExtendExpiry(self);
            SGSessionKeepExtending(self);
        }
        return self;
    }));
}

#pragma mark -

%ctor {
    if (!SGHidden(SGKeyFakePremium)) return;
    if (NSClassFromString(@"SPTAuthSessionImplementation")) %init(SGAuthSession);
    else SGLog(@"premium: SPTAuthSessionImplementation missing, its logout paths unheld");
    if (NSClassFromString(@"_TtC24Connectivity_SessionImpl18SessionServiceImpl")) %init(SGSessionService);
    else SGLog(@"premium: SessionServiceImpl missing, its logout paths unheld");
    if (NSClassFromString(@"SPTAuthLegacyLoginControllerImplementation")) %init(SGLegacyLogin);
    else SGLog(@"premium: SPTAuthLegacyLoginControllerImplementation missing, its logout paths unheld");
    Class bridge = SGSessionClassWithSuffix(@"OauthAccessTokenBridge");
    if (bridge) SGSessionHookTokenBridge(bridge);
    else SGLog(@"premium: OauthAccessTokenBridge missing, token expiry unheld");
}
