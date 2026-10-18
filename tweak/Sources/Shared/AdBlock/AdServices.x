// The services behind every ad surface and Premium prompt, each an SPTService Spotify starts by
// sending it -load. Hooked to do nothing, the surface is never built: the brand ad on Home, the card
// under the player, the sponsored playlist header, the sponsorship on the now playing bar, the
// in-stream ad, and the sheets and cards that sell Premium. The scroll-feed and embedded pipelines
// sit one layer deeper: the elements service and ad controller that wire scrollsita's
// EmbeddedAd/ImageBrandAd payloads into renderable elements, their adapter provider, the playlist
// ad controllers, and the leavebehind element provider. The views are a fallback for a header,
// banner or card already on screen before its service was silenced. The DSA ad-transparency overlay
// is left alone: it is the legal notice on an ad, and with no ad it never appears.
#import "Core/SGCore.h"
#import "AdBlock.h"

static void takeDown(UIView *view) {
    view.hidden = YES;
    view.userInteractionEnabled = NO;
    if (view.superview) [view removeFromSuperview];
}

// ElementUI classes are not UIView on every build, so the cast waits for the check.
static void takeDownElement(id element) {
    if ([element isKindOfClass:UIView.class]) takeDown((UIView *)element);
}

%group Ads

%hook _TtC19AdsPlatform_AdsImpl14AdsServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC29AdsNowPlaying_InStreamAdsImpl18InStreamAdsService
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC29AdsNowPlaying_EmbeddedNPVImpl22EmbeddedNPVServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC36AdsStandalone_LeavebehindAdsBaseImpl25LeavebehindAdsBaseService
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC36AdsStandalone_LeavebehindAdsBaseImpl33LeavebehindAdsBaseInternalService
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC35AdsEmbedded_AdsSponsoredContextImpl30AdsSponsoredContextServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC48AdsEmbedded_AdsSponsoredContextNPBAttachmentImpl43AdsSponsoredContextNPBAttachmentServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC42AdsEmbedded_AdsSponsoredPlaylistHeaderImpl37AdsSponsoredPlaylistHeaderServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC20NativeAds_LoggerImpl26NativeAdsLoggerServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
// The leavebehind card among the player's scroll cards. It has no -load; its card is added the way
// lyrics and credits add theirs, so it is kept off the list instead.
%hook _TtC32AdsEmbedded_EmbeddedCTACardsImpl23EmbeddedCTACardsService
- (void)registerScrollProviderIn:(id)registry { SGAdBlockCountOne(@"Ad services"); }
%end

// The scroll-feed and embedded pipelines (EeveeSpotifyReincarnated's extended blocker): the
// elements service and the ad controller that wire scrollsita's EmbeddedAd/ImageBrandAd payloads
// into renderable elements, their adapter provider, the two playlist ad controllers and the
// leavebehind element provider. Class names checked against the 9.1.90 binary.
%hook _TtC35AdsEmbedded_EmbeddedCTAElementsImpl30EmbeddedCTAElementsServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC36AdsEmbedded_EmbeddedAdControllerImpl31EmbeddedAdControllerServiceImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC35AdsEmbedded_EmbeddedCTAElementsImpl32EmbeddedAdAdapterElementProvider
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC32AdsEmbedded_EmbeddedPlaylistImpl22PlaylistAdControllerV2
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC32AdsEmbedded_EmbeddedPlaylistImpl24PlaylistAdControllerImpl
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end
%hook _TtC37AdsEmbedded_EmbeddedAdPresentationKit28LeavebehindAdElementProvider
- (void)load { SGAdBlockCountOne(@"Ad services"); }
%end

%hook _TtC18AdsPlatform_ECMKit37AdsSponsoredPlaylistHeaderCentralView
- (void)didMoveToSuperview {
    %orig;
    takeDown((UIView *)self);
}
%end

// The scroll-feed ad card and the HTML brand-ad creative, rendered even with the services above
// starved on some builds.
%hook _TtC35AdsEmbedded_EmbeddedCTAElementsImpl26EmbeddedAdAdapterElementUI
- (void)didMoveToSuperview {
    %orig;
    takeDownElement(self);
}
%end
%hook _TtC22AdsPlatform_ElementKit15HtmlAdElementUI
- (void)didMoveToSuperview {
    %orig;
    takeDownElement(self);
}
%end

%end

%group Upsells

%hook _TtC19Upsells_ServiceImpl18UpsellsServiceImpl
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end
%hook _TtC31PremiumUpsell_UpsellServiceImpl17UpsellServiceImpl
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end
%hook _TtC45ReinventFree_ContextualUpsellPremiumPromoImpl39ContextualUpsellPremiumPromoServiceImpl
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end
%hook _TtC40Referrals_ReferralsUpsellCardElementImpl37ReferralsUpsellCardElementServiceImpl
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end
%hook _TtC31ReinventFree_DownloadUpsellImpl21DownloadUpsellService
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end
%hook _TtC28Jam_FreeHostedJamsUpsellImpl31FreeHostedJamsUpsellServiceImpl
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end
%hook _TtC30Jam_FreeUserSkipUpsellPageImpl29FreeUserSkipUpsellPageService
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end
%hook _TtC38Jam_FreeUserShuffleUpsellSheetPageImpl37FreeUserShuffleUpsellSheetPageService
- (void)load { SGAdBlockCountOne(@"Upsell services"); }
%end

%hook _TtC13Upsells_UIKit29SelfLoadingUpsellBannerUIView
- (void)didMoveToSuperview {
    %orig;
    takeDown((UIView *)self);
}
%end

%end

%ctor {
    if (SGHidden(SGKeyHideAds)) {
        %init(Ads);
        SGRequireClasses(@[
            @"_TtC19AdsPlatform_AdsImpl14AdsServiceImpl",
            @"_TtC29AdsNowPlaying_InStreamAdsImpl18InStreamAdsService",
            @"_TtC29AdsNowPlaying_EmbeddedNPVImpl22EmbeddedNPVServiceImpl",
            @"_TtC36AdsStandalone_LeavebehindAdsBaseImpl25LeavebehindAdsBaseService",
            @"_TtC36AdsStandalone_LeavebehindAdsBaseImpl33LeavebehindAdsBaseInternalService",
            @"_TtC35AdsEmbedded_AdsSponsoredContextImpl30AdsSponsoredContextServiceImpl",
            @"_TtC48AdsEmbedded_AdsSponsoredContextNPBAttachmentImpl43AdsSponsoredContextNPBAttachmentServiceImpl",
            @"_TtC42AdsEmbedded_AdsSponsoredPlaylistHeaderImpl37AdsSponsoredPlaylistHeaderServiceImpl",
            @"_TtC20NativeAds_LoggerImpl26NativeAdsLoggerServiceImpl",
            @"_TtC32AdsEmbedded_EmbeddedCTACardsImpl23EmbeddedCTACardsService",
            @"_TtC35AdsEmbedded_EmbeddedCTAElementsImpl30EmbeddedCTAElementsServiceImpl",
            @"_TtC36AdsEmbedded_EmbeddedAdControllerImpl31EmbeddedAdControllerServiceImpl",
            @"_TtC35AdsEmbedded_EmbeddedCTAElementsImpl32EmbeddedAdAdapterElementProvider",
            @"_TtC32AdsEmbedded_EmbeddedPlaylistImpl22PlaylistAdControllerV2",
            @"_TtC32AdsEmbedded_EmbeddedPlaylistImpl24PlaylistAdControllerImpl",
            @"_TtC37AdsEmbedded_EmbeddedAdPresentationKit28LeavebehindAdElementProvider",
            @"_TtC18AdsPlatform_ECMKit37AdsSponsoredPlaylistHeaderCentralView",
            @"_TtC35AdsEmbedded_EmbeddedCTAElementsImpl26EmbeddedAdAdapterElementUI",
            @"_TtC22AdsPlatform_ElementKit15HtmlAdElementUI",
        ]);
    }
    if (SGHidden(SGKeyHideUpsells)) {
        %init(Upsells);
        SGRequireClasses(@[
            @"_TtC19Upsells_ServiceImpl18UpsellsServiceImpl",
            @"_TtC31PremiumUpsell_UpsellServiceImpl17UpsellServiceImpl",
            @"_TtC45ReinventFree_ContextualUpsellPremiumPromoImpl39ContextualUpsellPremiumPromoServiceImpl",
            @"_TtC40Referrals_ReferralsUpsellCardElementImpl37ReferralsUpsellCardElementServiceImpl",
            @"_TtC31ReinventFree_DownloadUpsellImpl21DownloadUpsellService",
            @"_TtC28Jam_FreeHostedJamsUpsellImpl31FreeHostedJamsUpsellServiceImpl",
            @"_TtC30Jam_FreeUserSkipUpsellPageImpl29FreeUserSkipUpsellPageService",
            @"_TtC38Jam_FreeUserShuffleUpsellSheetPageImpl37FreeUserShuffleUpsellSheetPageService",
            @"_TtC13Upsells_UIKit29SelfLoadingUpsellBannerUIView",
        ]);
    }
}
