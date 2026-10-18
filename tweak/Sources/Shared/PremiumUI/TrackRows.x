// The artist page builds its top tracks as a list with play controls - the Premium layout - when its
// remote URL resolver is made with trackRowsEnabled YES. EeveeSpotifyReincarnated's TrackRowsEnabler,
// reimplemented: on Spotify 9.1.x the resolver's init is on UIView (a subclass on older builds), so
// UIView is hooked, and only after the selector is confirmed to exist there so the hook is not added to
// every UIView init on a build that does something else.
#import "Core/SGCore.h"
#import "PremiumUI.h"

@interface UIView (SGPremiumUITrackRows)
- (id)initWithViewURI:(NSURL *)uri onDemandSet:(id)onDemandSet onDemandTrialService:(id)onDemandTrialService trackRowsEnabled:(BOOL)trackRowsEnabled productState:(id)productState;
@end

%hook UIView
- (id)initWithViewURI:(NSURL *)uri onDemandSet:(id)onDemandSet onDemandTrialService:(id)onDemandTrialService trackRowsEnabled:(BOOL)trackRowsEnabled productState:(id)productState {
    return %orig(uri, onDemandSet, onDemandTrialService, YES, productState);
}
%end

%ctor {
    if (!SGEnabled(SGKeyTrackRows)) return;
    SEL selector = @selector(initWithViewURI:onDemandSet:onDemandTrialService:trackRowsEnabled:productState:);
    if (![UIView instancesRespondToSelector:selector]) {
        SGLog(@"premiumui: no %@ on UIView, track rows inactive", NSStringFromSelector(selector));
        return;
    }
    %init;
}
