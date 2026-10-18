// The ClientMessagingPlatform's marketing messages: the fullscreen "welcome back, Premium ends
// soon" takeover, its center modal and bottom sheet, and the Home banner. They are fetched over
// com.spotify.pendragon.v1.ClientMessageService, which AdNetwork.x blocks while Spoof Premium is
// on — but messages already in CMP's on-device store still present after that, and with Spoof
// Premium off the fetch is never blocked at all. So the containers are dismissed as they appear
// and the banner views come down on attach, the presentation-layer net EeveeSpotifyReincarnated's
// ClientMessagingPlatformBlocker adds, reimplemented. CMP carries server-driven marketing only;
// DSA transparency dialogs live in another module and are untouched. Class names checked against
// the 9.1.90 binary; UpsellBannerElementUI's mangled name carries a per-build hash, so it is found
// by suffix the way TrueShuffle finds its handler.
#import "Core/SGCore.h"
#import "AdBlock.h"

static void takeDown(id view) {
    if (![view isKindOfClass:UIView.class]) return;
    SGAdBlockSawOne(@"Message surfaces");
    SGAdBlockCountOne(@"Message surfaces");
    SGLog(@"took down %@ before it showed", NSStringFromClass([view class]));
    UIView *asView = (UIView *)view;
    asView.hidden = YES;
    asView.userInteractionEnabled = NO;
    if (asView.superview) [asView removeFromSuperview];
}

// The fullscreen takeover, center modal and bottom sheet are presented in container view
// controllers of their own; dismissed in viewWillAppear, the container never becomes visible.
// dismiss(animated:NO) keeps UIKit's presentation bookkeeping consistent. The classes are forward
// declarations to the compiler, so self is used through its UIViewController cast.
static void dismissContainer(id controller, NSString *what) {
    SGAdBlockSawOne(@"Message surfaces");
    SGAdBlockCountOne(@"Message surfaces");
    SGLog(@"dismissed the CMP %@", what);
    UIViewController *vc = (UIViewController *)controller;
    vc.view.hidden = YES;
    vc.view.userInteractionEnabled = NO;
    [vc dismissViewControllerAnimated:NO completion:nil];
}

%hook _TtC37Messaging_ClientMessagingPlatformImpl33FullscreenContainerViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dismissContainer(self, @"fullscreen container");
}
%end

%hook _TtC37Messaging_ClientMessagingPlatformImpl28ModalContainerViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dismissContainer(self, @"modal container");
}
%end

%hook _TtC37Messaging_ClientMessagingPlatformImpl52ClientMessagingPlatformBottomSheetPageViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    dismissContainer(self, @"bottom sheet");
}
%end

// The Home banner and the upsell elements rendered from Hub and queue component trees. ElementUI
// classes are not UIView on every build, so the cast waits for the isKindOfClass: in takeDown.
%hook _TtC37Messaging_ClientMessagingPlatformImpl33ClientMessagingPlatformBannerView
- (void)didMoveToSuperview {
    %orig;
    takeDown(self);
}
%end

%hook _TtC24Jam_QueueIntegrationImpl28PremiumUpsellBannerElementUI
- (void)didMoveToSuperview {
    %orig;
    takeDown(self);
}
%end

%hook _TtC19ReinventFree_ECMKit25PremiumUpsellControlPanel
- (void)didMoveToSuperview {
    %orig;
    takeDown(self);
}
%end

// Upsells_ElementKit's private UpsellBannerElementUI: hooked by hand once the suffix finds it,
// and only when it answers didMoveToSuperview at all.
static void SGAdMessagesHookUpsellBanner(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    Class found = Nil;
    for (unsigned int i = 0; i < count; i++) {
        const char *name = class_getName(classes[i]);
        if (name && [[NSString stringWithUTF8String:name] hasSuffix:@"UpsellBannerElementUI"]) { found = classes[i]; break; }
    }
    free(classes);
    if (!found) {
        SGLog(@"adblock: UpsellBannerElementUI missing, its banner unhooked");
        return;
    }
    Method method = class_getInstanceMethod(found, @selector(didMoveToSuperview));
    if (!method) {
        SGLog(@"adblock: %s has no didMoveToSuperview", class_getName(found));
        return;
    }
    IMP original = method_getImplementation(method);
    method_setImplementation(method, imp_implementationWithBlock(^void(id self) {
        ((void (*)(id, SEL))original)(self, @selector(didMoveToSuperview));
        takeDown(self);
    }));
}

%ctor {
    if (!SGEnabled(SGKeyHideUpsells)) return;
    %init;
    SGAdMessagesHookUpsellBanner();
    SGRequireClasses(@[
        @"_TtC37Messaging_ClientMessagingPlatformImpl33FullscreenContainerViewController",
        @"_TtC37Messaging_ClientMessagingPlatformImpl28ModalContainerViewController",
        @"_TtC37Messaging_ClientMessagingPlatformImpl52ClientMessagingPlatformBottomSheetPageViewController",
        @"_TtC37Messaging_ClientMessagingPlatformImpl33ClientMessagingPlatformBannerView",
        @"_TtC24Jam_QueueIntegrationImpl28PremiumUpsellBannerElementUI",
        @"_TtC19ReinventFree_ECMKit25PremiumUpsellControlPanel",
    ]);
}
