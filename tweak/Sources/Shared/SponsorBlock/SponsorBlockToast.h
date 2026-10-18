// The toast of SponsorBlock.h, reimplemented from EeveeSpotify's SponsorBlockToast.swift (GPL-3.0):
// a pill under the notch naming what just happened, with at most one button (Skip, Undo), gone on
// its own after `duration`, on a swipe up, or at once when its button is tapped.
#import <UIKit/UIKit.h>

@interface SGSponsorToast : NSObject
// A plain message, 2.2 s.
+ (void)show:(NSString *)message;
// A message with one button; tapping it runs the action and yanks the toast.
+ (void)show:(NSString *)message action:(NSString *)actionTitle duration:(NSTimeInterval)duration handler:(void (^)(void))handler;
@end
