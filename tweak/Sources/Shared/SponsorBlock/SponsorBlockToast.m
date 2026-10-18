#import "Core/SGCore.h"
#import "SponsorBlockToast.h"

@implementation SGSponsorToast

static __weak UIView *sg_toast;
static dispatch_block_t sg_dismiss;

static UIWindow *keyWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (ws.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *window in ws.windows) if (window.isKeyWindow) return window;
        if (ws.windows.count) return ws.windows.firstObject;
    }
    return nil;
}

+ (void)show:(NSString *)message {
    [self show:message action:nil duration:2.2 handler:nil];
}

+ (void)show:(NSString *)message action:(NSString *)actionTitle duration:(NSTimeInterval)duration handler:(void (^)(void))handler {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = keyWindow();
        if (!window) return;

        [sg_toast removeFromSuperview];
        if (sg_dismiss) dispatch_block_cancel(sg_dismiss);

        UIView *toast = [UIView new];
        toast.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.88];
        toast.layer.cornerRadius = 14;
        toast.layer.masksToBounds = YES;
        toast.translatesAutoresizingMaskIntoConstraints = NO;
        toast.alpha = 0;

        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swiped:)];
        swipe.direction = UISwipeGestureRecognizerDirectionUp;
        [toast addGestureRecognizer:swipe];

        UILabel *label = [UILabel new];
        label.text = message;
        label.textColor = UIColor.whiteColor;
        label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        label.numberOfLines = 2;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
        [toast addSubview:label];
        [window addSubview:toast];

        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithObjects:
            [toast.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
            [toast.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:12],
            [toast.widthAnchor constraintLessThanOrEqualToAnchor:window.widthAnchor multiplier:0.94],
            [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:16],
            [label.topAnchor constraintEqualToAnchor:toast.topAnchor constant:10],
            [label.bottomAnchor constraintEqualToAnchor:toast.bottomAnchor constant:-10],
            nil];

        if (!actionTitle.length) {
            [constraints addObject:[label.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-16]];
        } else {
            UIButton *button = [UIButton new];
            button.translatesAutoresizingMaskIntoConstraints = NO;
            UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
            config.attributedTitle = [[NSAttributedString alloc] initWithString:actionTitle attributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold],
            }];
            config.baseForegroundColor = [UIColor colorWithRed:0.18 green:0.84 blue:0.45 alpha:1];
            config.contentInsets = NSDirectionalEdgeInsetsMake(6, 10, 6, 10);
            config.background.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.10];
            config.background.cornerRadius = 10;
            button.configuration = config;
            // The handler is kept on the block-based target so the toast owns no state of its caller's.
            objc_setAssociatedObject(button, "sg_handler", handler, OBJC_ASSOCIATION_COPY_NONATOMIC);
            [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [toast addSubview:button];
            [constraints addObjectsFromArray:@[
                [button.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
                [button.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-8],
                [button.centerYAnchor constraintEqualToAnchor:toast.centerYAnchor],
                [button.heightAnchor constraintGreaterThanOrEqualToConstant:34],
            ]];
        }
        [NSLayoutConstraint activateConstraints:constraints];
        sg_toast = toast;

        [UIView animateWithDuration:0.2 animations:^{ toast.alpha = 1; }];

        dispatch_block_t work = dispatch_block_create(0, ^{
            UIView *gone = sg_toast;
            if (!gone) return;
            gone.userInteractionEnabled = NO;
            [UIView animateWithDuration:0.25 animations:^{ gone.alpha = 0; }
                             completion:^(BOOL finished) { [gone removeFromSuperview]; }];
        });
        sg_dismiss = work;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)), dispatch_get_main_queue(), work);
    });
}

+ (void)tapped:(UIButton *)button {
    void (^handler)(void) = objc_getAssociatedObject(button, "sg_handler");
    if (sg_dismiss) dispatch_block_cancel(sg_dismiss);
    UIView *toast = sg_toast;
    toast.userInteractionEnabled = NO;
    [toast removeFromSuperview];
    if (handler) handler();
}

+ (void)swiped:(UISwipeGestureRecognizer *)recognizer {
    if (sg_dismiss) dispatch_block_cancel(sg_dismiss);
    UIView *toast = sg_toast;
    toast.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.18 animations:^{
        toast.alpha = 0;
        toast.transform = CGAffineTransformMakeTranslation(0, -30);
    } completion:^(BOOL finished) { [toast removeFromSuperview]; }];
}

@end
