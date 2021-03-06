/*
 This file is part of Appirater.
 
 Copyright (c) 2012, Arash Payan
 All rights reserved.
 
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 */
/*
 * Appirater.m
 * appirater
 *
 * Created by Arash Payan on 9/5/09.
 * http://arashpayan.com
 * Copyright 2012 Arash Payan. All rights reserved.
 */

#import <SystemConfiguration/SystemConfiguration.h>
#import <CFNetwork/CFNetwork.h>
#import "Appirater.h"
#include <netinet/in.h>

#if ! __has_feature(objc_arc)
#warning This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

NSString *const kAppiraterFirstUseDate				= @"kAppiraterFirstUseDate";
NSString *const kAppiraterUseCount					= @"kAppiraterUseCount";
NSString *const kAppiraterSignificantEventCount		= @"kAppiraterSignificantEventCount";
NSString *const kAppiraterCurrentVersion			= @"kAppiraterCurrentVersion";
NSString *const kAppiraterRated                     = @"kAppiraterRated";
NSString *const kAppiraterDeclinedToRate			= @"kAppiraterDeclinedToRate";
NSString *const kAppiraterReminderRequestDate		= @"kAppiraterReminderRequestDate";

NSString *templateReviewURL = @"itms-apps://ax.itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=APP_ID";
NSString *templateReviewURLiOS7 = @"itms-apps://itunes.apple.com/app/idAPP_ID";

static const NSInteger AlertButtonIndexInvalid = -1;

typedef NS_ENUM(NSInteger, PreliminaryAlertButtonIndex) {
    PreliminaryAlertButtonNo = 0,
    PreliminaryAlertButtonYes
};

typedef NS_ENUM(NSInteger, RateAlertButtonIndex) {
    RateAlertButtonIndexDontRate = 0,
    RateAlertButtonIndexRateNow,
    RateAlertButtonIndexRateLater
};

static NSString *_appId;
static BOOL _showPreliminaryMessage = NO;
static double _daysUntilPrompt = 30;
static NSInteger _usesUntilPrompt = 20;
static NSInteger _significantEventsUntilPrompt = -1;
static double _timeBeforeReminding = 1;
static BOOL _debug = NO;
#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_5_0
	static id<AppiraterDelegate> _delegate;
#else
	__weak static id<AppiraterDelegate> _delegate;
#endif
static BOOL _usesAnimation = YES;
static UIStatusBarStyle _statusBarStyle;
static BOOL _modalOpen = NO;
static BOOL _alwaysUseMainBundle = NO;

static const NSInteger kPreliminaryAlertViewTag = 1000;
static const NSInteger kRateAlertViewTag        = 1001;

@interface Appirater () {
    BOOL _shouldShowRateLaterButton;
}

@end

@implementation Appirater 

@synthesize ratingAlert;

+ (void) setAppId:(NSString *)appId {
    _appId = appId;
}

+ (void) setShowPreliminaryMessage:(BOOL)showPreliminaryMessage {
    _showPreliminaryMessage = showPreliminaryMessage;
}

+ (void) setDaysUntilPrompt:(double)value {
    _daysUntilPrompt = value;
}

+ (void) setUsesUntilPrompt:(NSInteger)value {
    _usesUntilPrompt = value;
}

+ (void) setSignificantEventsUntilPrompt:(NSInteger)value {
    _significantEventsUntilPrompt = value;
}

+ (void) setTimeBeforeReminding:(double)value {
    _timeBeforeReminding = value;
}

+ (void) setDebug:(BOOL)debug {
    _debug = debug;
}
+ (void)setDelegate:(id<AppiraterDelegate>)delegate{
	_delegate = delegate;
}
+ (void)setUsesAnimation:(BOOL)animation {
	_usesAnimation = animation;
}
+ (void)setOpenInAppStore:(BOOL)openInAppStore {
    [Appirater sharedInstance].openInAppStore = openInAppStore;
}
+ (void)setStatusBarStyle:(UIStatusBarStyle)style {
	_statusBarStyle = style;
}
+ (void)setModalOpen:(BOOL)open {
	_modalOpen = open;
}
+ (void)setAlwaysUseMainBundle:(BOOL)alwaysUseMainBundle {
    _alwaysUseMainBundle = alwaysUseMainBundle;
}

+ (NSBundle *)bundle
{
    NSBundle *bundle;

    if (_alwaysUseMainBundle) {
        bundle = [NSBundle mainBundle];
    } else {
        NSURL *appiraterBundleURL = [[NSBundle mainBundle] URLForResource:@"Appirater" withExtension:@"bundle"];

        if (appiraterBundleURL) {
            // Appirater.bundle will likely only exist when used via CocoaPods
            bundle = [NSBundle bundleWithURL:appiraterBundleURL];
        } else {
            bundle = [NSBundle mainBundle];
        }
    }

    return bundle;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)init {
    self = [super init];
    if (self) {
        if ([[UIDevice currentDevice].systemVersion floatValue] >= 7.0) {
            self.openInAppStore = YES;
        } else {
            self.openInAppStore = NO;
        }
    }
    
    return self;
}

- (BOOL)connectedToNetwork {
    // Create zero addy
    struct sockaddr_in zeroAddress;
    bzero(&zeroAddress, sizeof(zeroAddress));
    zeroAddress.sin_len = sizeof(zeroAddress);
    zeroAddress.sin_family = AF_INET;
	
    // Recover reachability flags
    SCNetworkReachabilityRef defaultRouteReachability = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&zeroAddress);
    SCNetworkReachabilityFlags flags;
	
    BOOL didRetrieveFlags = (BOOL)SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags);
    CFRelease(defaultRouteReachability);
	
    if (!didRetrieveFlags)
    {
        if (_debug) {
            NSLog(@"Error. Could not recover network reachability flags");
        }
        return NO;
    }
	
    BOOL isReachable = flags & kSCNetworkFlagsReachable;
    BOOL needsConnection = flags & kSCNetworkFlagsConnectionRequired;
	BOOL nonWiFi = flags & kSCNetworkReachabilityFlagsTransientConnection;
	
	NSURL *testURL = [NSURL URLWithString:@"http://www.apple.com/"];
	
    NSURLSessionConfiguration* sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfiguration.timeoutIntervalForRequest = 20.0;

    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration];

    NSURLSessionTask *task = [session dataTaskWithURL:testURL];
    [task resume];
    
    return ((isReachable && !needsConnection) || nonWiFi) ? ( (task.state != NSURLSessionTaskStateSuspended) ? YES : NO ) : NO;
}

+ (Appirater*)sharedInstance {
	static Appirater *appirater = nil;
	if (appirater == nil)
	{
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            appirater = [[Appirater alloc] init];
			appirater.delegate = _delegate;
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:
                UIApplicationWillResignActiveNotification object:nil];
        });
	}
	
	return appirater;
}

- (void)showRatingAlert:(BOOL)displayRateLaterButton {
    if (_showPreliminaryMessage) {
        _shouldShowRateLaterButton = displayRateLaterButton;
        [self reallyShowPreliminaryAlert];
    } else {
        [self reallyShowRatingAlert:displayRateLaterButton];
    }
}

- (void)showRatingAlert
{
    [self showRatingAlert:YES];
}

- (void)reallyShowPreliminaryAlert {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:APPIRATER_PRELIMINARY_MESSAGE_TITLE
#pragma clang diagnostic pop
                                                        message:APPIRATER_PRELIMINARY_MESSAGE
                                                       delegate:self
                                              cancelButtonTitle:APPIRATER_PRELIMINARY_MESSAGE_NO_BUTTON
                                              otherButtonTitles:APPIRATER_PRELIMINARY_MESSAGE_YES_BUTTON, nil];
    alertView.tag = kPreliminaryAlertViewTag;
    
	self.ratingAlert = alertView;
    [alertView show];
    
    id <AppiraterDelegate> delegate = _delegate;
    if (delegate && [delegate respondsToSelector:@selector(appiraterDidDisplayPreliminaryAlert:)]) {
        [delegate appiraterDidDisplayPreliminaryAlert:self];
    }
}

- (void)reallyShowRatingAlert:(BOOL)displayRateLaterButton {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIAlertView *alertView = nil;
#pragma clang diagnostic pop
    if (displayRateLaterButton) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        alertView = [[UIAlertView alloc] initWithTitle:APPIRATER_MESSAGE_TITLE
#pragma clang diagnostic pop
                                               message:APPIRATER_MESSAGE
                                              delegate:self
                                     cancelButtonTitle:APPIRATER_CANCEL_BUTTON
                                     otherButtonTitles:APPIRATER_RATE_BUTTON, APPIRATER_RATE_LATER, nil];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        alertView = [[UIAlertView alloc] initWithTitle:APPIRATER_MESSAGE_TITLE
#pragma clang diagnostic pop
                                               message:APPIRATER_MESSAGE
                                              delegate:self
                                     cancelButtonTitle:APPIRATER_CANCEL_BUTTON
                                     otherButtonTitles:APPIRATER_RATE_BUTTON, nil];
    }
    
    alertView.tag = kRateAlertViewTag;
    
	self.ratingAlert = alertView;
    [alertView show];
    
    id <AppiraterDelegate> delegate = _delegate;
    if (delegate && [delegate respondsToSelector:@selector(appiraterDidDisplayAlert:)]) {
        [delegate appiraterDidDisplayAlert:self];
    }
}

- (BOOL)ratingConditionsHaveBeenMet {
	if (_debug)
		return YES;
	
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	
	NSDate *dateOfFirstLaunch = [NSDate dateWithTimeIntervalSince1970:[userDefaults doubleForKey:kAppiraterFirstUseDate]];
	NSTimeInterval timeSinceFirstLaunch = [[NSDate date] timeIntervalSinceDate:dateOfFirstLaunch];
	NSTimeInterval timeUntilRate = 60 * 60 * 24 * _daysUntilPrompt;
	if (timeSinceFirstLaunch < timeUntilRate)
		return NO;
	
	// check if the app has been used enough
	NSInteger useCount = [userDefaults integerForKey:kAppiraterUseCount];
	if (useCount < _usesUntilPrompt)
		return NO;
	
	// check if the user has done enough significant events
	NSInteger sigEventCount = [userDefaults integerForKey:kAppiraterSignificantEventCount];
	if (sigEventCount < _significantEventsUntilPrompt)
		return NO;
	
	// has the user previously declined to rate this version of the app?
	if ([userDefaults boolForKey:kAppiraterDeclinedToRate])
		return NO;
	
	// has the user already rated the app?
	if ([self userHasRatedApp])
		return NO;
	
	// if the user wanted to be reminded later, has enough time passed?
	NSDate *reminderRequestDate = [NSDate dateWithTimeIntervalSince1970:[userDefaults doubleForKey:kAppiraterReminderRequestDate]];
	NSTimeInterval timeSinceReminderRequest = [[NSDate date] timeIntervalSinceDate:reminderRequestDate];
	NSTimeInterval timeUntilReminder = 60 * 60 * 24 * _timeBeforeReminding;
	if (timeSinceReminderRequest < timeUntilReminder)
		return NO;
	
	return YES;
}

- (void)incrementUseCount {
	// get the app's version
	NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleVersionKey];
	
	// get the version number that we've been tracking
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSString *trackingVersion = [userDefaults stringForKey:kAppiraterCurrentVersion];
	if (trackingVersion == nil)
	{
		trackingVersion = version;
		[userDefaults setObject:version forKey:kAppiraterCurrentVersion];
		[userDefaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:kAppiraterFirstUseDate];
		[userDefaults setInteger:0 forKey:kAppiraterUseCount];
		[userDefaults setInteger:0 forKey:kAppiraterSignificantEventCount];
		[userDefaults setBool:NO forKey:kAppiraterRated];
		[userDefaults setBool:NO forKey:kAppiraterDeclinedToRate];
		[userDefaults setDouble:0 forKey:kAppiraterReminderRequestDate];
	}
	
	if (_debug)
		NSLog(@"APPIRATER Tracking version: %@", trackingVersion);
	
    // check if the first use date has been set. if not, set it.
    NSTimeInterval timeInterval = [userDefaults doubleForKey:kAppiraterFirstUseDate];
    if (timeInterval == 0)
    {
        timeInterval = [[NSDate date] timeIntervalSince1970];
        [userDefaults setDouble:timeInterval forKey:kAppiraterFirstUseDate];
    }
    
    // increment the use count
    NSInteger useCount = [userDefaults integerForKey:kAppiraterUseCount];
    useCount++;
    [userDefaults setInteger:useCount forKey:kAppiraterUseCount];
    if (_debug)
        NSLog(@"APPIRATER Use count: %@", @(useCount));
	
	[userDefaults synchronize];
}

- (void)incrementSignificantEventCount {
	// get the app's version
	NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleVersionKey];
	
	// get the version number that we've been tracking
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	NSString *trackingVersion = [userDefaults stringForKey:kAppiraterCurrentVersion];
	if (trackingVersion == nil)
	{
		trackingVersion = version;
		[userDefaults setObject:version forKey:kAppiraterCurrentVersion];
		[userDefaults setDouble:0 forKey:kAppiraterFirstUseDate];
		[userDefaults setInteger:0 forKey:kAppiraterUseCount];
		[userDefaults setInteger:0 forKey:kAppiraterSignificantEventCount];
		[userDefaults setBool:NO forKey:kAppiraterRated];
		[userDefaults setBool:NO forKey:kAppiraterDeclinedToRate];
		[userDefaults setDouble:0 forKey:kAppiraterReminderRequestDate];
	}
	
	if (_debug)
		NSLog(@"APPIRATER Tracking version: %@", trackingVersion);
	
    // check if the first use date has been set. if not, set it.
    NSTimeInterval timeInterval = [userDefaults doubleForKey:kAppiraterFirstUseDate];
    if (timeInterval == 0)
    {
        timeInterval = [[NSDate date] timeIntervalSince1970];
        [userDefaults setDouble:timeInterval forKey:kAppiraterFirstUseDate];
    }
    
    // increment the significant event count
    NSInteger sigEventCount = [userDefaults integerForKey:kAppiraterSignificantEventCount];
    sigEventCount++;
    [userDefaults setInteger:sigEventCount forKey:kAppiraterSignificantEventCount];

    if (_debug)
        NSLog(@"APPIRATER Significant event count: %@", @(sigEventCount));
	
	[userDefaults synchronize];
}

- (void)incrementAndRate:(BOOL)canPromptForRating {
	[self incrementUseCount];
	
	if (canPromptForRating &&
		[self ratingConditionsHaveBeenMet] &&
		[self connectedToNetwork])
	{
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self showRatingAlert];
                       });
	}
}

- (void)incrementSignificantEventAndRate:(BOOL)canPromptForRating {
	[self incrementSignificantEventCount];
	
	if (canPromptForRating &&
		[self ratingConditionsHaveBeenMet] &&
		[self connectedToNetwork])
	{
        dispatch_async(dispatch_get_main_queue(),
                       ^{
                           [self showRatingAlert];
                       });
	}
}

- (BOOL)userHasDeclinedToRate {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAppiraterDeclinedToRate];
}

- (BOOL)userHasRatedApp {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAppiraterRated];
}

+ (void)appLaunched {
	[Appirater appLaunched:YES];
}

+ (void)appLaunched:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                   ^{
                       [[Appirater sharedInstance] incrementAndRate:canPromptForRating];
                   });
}

- (void)hideRatingAlert {
	if (self.ratingAlert.visible) {
		if (_debug)
			NSLog(@"APPIRATER Hiding Alert");
		[self.ratingAlert dismissWithClickedButtonIndex:AlertButtonIndexInvalid animated:NO];
	}	
}

+ (void)appWillResignActive {
	if (_debug)
		NSLog(@"APPIRATER appWillResignActive");
	[[Appirater sharedInstance] hideRatingAlert];
}

+ (void)appEnteredForeground:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                   ^{
                       [[Appirater sharedInstance] incrementAndRate:canPromptForRating];
                   });
}

+ (void)userDidSignificantEvent:(BOOL)canPromptForRating {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
                   ^{
                       [[Appirater sharedInstance] incrementSignificantEventAndRate:canPromptForRating];
                   });
}

+ (void)showPrompt {
  [Appirater tryToShowPrompt];
}

+ (void)tryToShowPrompt {
  [[Appirater sharedInstance] showPromptWithChecks:YES
                            displayRateLaterButton:YES];
}

+ (void)forceShowPrompt:(BOOL)displayRateLaterButton {
  [[Appirater sharedInstance] showPromptWithChecks:NO
                            displayRateLaterButton:displayRateLaterButton];
}

- (void)showPromptWithChecks:(BOOL)withChecks
      displayRateLaterButton:(BOOL)displayRateLaterButton {
  BOOL showPrompt = YES;
  if (withChecks) {
      showPrompt = ([self connectedToNetwork]
                    && ![self userHasDeclinedToRate]
                    && ![self userHasRatedApp]
                    && [self ratingConditionsHaveBeenMet]);
  }
  if (showPrompt) {
    [self showRatingAlert:displayRateLaterButton];
  }
}

+ (id)getRootViewController {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (window.windowLevel != UIWindowLevelNormal) {
        NSArray *windows = [[UIApplication sharedApplication] windows];
        for(window in windows) {
            if (window.windowLevel == UIWindowLevelNormal) {
                break;
            }
        }
    }
    
    for (UIView *subView in [window subviews])
    {
        UIResponder *responder = [subView nextResponder];
        if([responder isKindOfClass:[UIViewController class]]) {
            return [self topMostViewController: (UIViewController *) responder];
        }
    }
    
    return nil;
}

+ (UIViewController *) topMostViewController: (UIViewController *) controller {
	BOOL isPresenting = NO;
	do {
		// this path is called only on iOS 6+, so -presentedViewController is fine here.
		UIViewController *presented = [controller presentedViewController];
		isPresenting = presented != nil;
		if(presented != nil) {
			controller = presented;
		}
		
	} while (isPresenting);
	
	return controller;
}

+ (void)rateApp {
	
	NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
	[userDefaults setBool:YES forKey:kAppiraterRated];
	[userDefaults synchronize];

	//Use the in-app StoreKit view if available (iOS 6) and imported. This works in the simulator.
	if (![Appirater sharedInstance].openInAppStore && NSStringFromClass([SKStoreProductViewController class]) != nil) {
		
		SKStoreProductViewController *storeViewController = [[SKStoreProductViewController alloc] init];
		NSNumber *appId = @(_appId.integerValue);
		[storeViewController loadProductWithParameters:@{SKStoreProductParameterITunesItemIdentifier:appId} completionBlock:nil];
		storeViewController.delegate = self.sharedInstance;
        
        id <AppiraterDelegate> delegate = self.sharedInstance.delegate;
		if ([delegate respondsToSelector:@selector(appiraterWillPresentModalView:animated:)]) {
			[delegate appiraterWillPresentModalView:self.sharedInstance animated:_usesAnimation];
		}
		[[self getRootViewController] presentViewController:storeViewController animated:_usesAnimation completion:^{
			[self setModalOpen:YES];
		}];
	
	//Use the standard openUrl method if StoreKit is unavailable.
	} else {
		
		#if TARGET_IPHONE_SIMULATOR
		NSLog(@"APPIRATER NOTE: iTunes App Store is not supported on the iOS simulator. Unable to open App Store page.");
		#else
		NSString *reviewURL = [templateReviewURL stringByReplacingOccurrencesOfString:@"APP_ID" withString:[NSString stringWithFormat:@"%@", _appId]];

		// iOS 7 needs a different templateReviewURL @see https://github.com/arashpayan/appirater/issues/131
		if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0) {
			reviewURL = [templateReviewURLiOS7 stringByReplacingOccurrencesOfString:@"APP_ID" withString:[NSString stringWithFormat:@"%@", _appId]];
		}

        [UIApplication.sharedApplication openURL:[NSURL URLWithString:reviewURL]
                                         options:@{}
                               completionHandler:nil];
		#endif
	}
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
#pragma clang diagnostic push
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];

    id <AppiraterDelegate> delegate = _delegate;
    
    switch (alertView.tag) {
        case kPreliminaryAlertViewTag:
        {
            switch (buttonIndex) {
                case PreliminaryAlertButtonNo:
                    [self didDeclineToRate];
                    
                    if ([delegate respondsToSelector:@selector(appiraterDidDeclinePreliminaryAlert:)]) {
                        [delegate appiraterDidDeclinePreliminaryAlert:self];
                    }
                    
                    break;
                case PreliminaryAlertButtonYes:
                    [self reallyShowRatingAlert:_shouldShowRateLaterButton];
                    
                    if ([delegate respondsToSelector:@selector(appiraterDidAcceptPreliminaryAlert:)]) {
                        [delegate appiraterDidAcceptPreliminaryAlert:self];
                    }
                    
                    break;
            }
        }
            break;
        case kRateAlertViewTag:
        {
            switch (buttonIndex) {
                case RateAlertButtonIndexDontRate:
                {
                    [self didDeclineToRate];
                    break;
                }
                case RateAlertButtonIndexRateNow:
                {
                    [Appirater rateApp];
                    if(delegate&& [delegate respondsToSelector:@selector(appiraterDidOptToRate:)]){
                        [delegate appiraterDidOptToRate:self];
                    }
                    break;
                }
                case RateAlertButtonIndexRateLater:
                    [userDefaults setDouble:[[NSDate date] timeIntervalSince1970] forKey:kAppiraterReminderRequestDate];
                    [userDefaults synchronize];
                    if(delegate && [delegate respondsToSelector:@selector(appiraterDidOptToRemindLater:)]){
                        [delegate appiraterDidOptToRemindLater:self];
                    }
                    break;
                default:
                    break;
            }
        }
        default:
            break;
    }
}

- (void)didDeclineToRate {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    
    [userDefaults setBool:YES forKey:kAppiraterDeclinedToRate];
    [userDefaults synchronize];
    if(_delegate && [_delegate respondsToSelector:@selector(appiraterDidDeclineToRate:)]){
        [_delegate appiraterDidDeclineToRate:self];
    }
}

//Delegate call from the StoreKit view.
- (void)productViewControllerDidFinish:(SKStoreProductViewController *)viewController {
	[Appirater closeModal];
}

//Close the in-app rating (StoreKit) view and restore the previous status bar style.
+ (void)closeModal {
	if (_modalOpen) {
		BOOL usedAnimation = _usesAnimation;
		[self setModalOpen:NO];
		
		// get the top most controller (= the StoreKit Controller) and dismiss it
		UIViewController *presentingController = [UIApplication sharedApplication].keyWindow.rootViewController;
		presentingController = [self topMostViewController: presentingController];
		[presentingController dismissViewControllerAnimated:_usesAnimation completion:^{
            id <AppiraterDelegate> delegate = self.sharedInstance.delegate;
			if ([delegate respondsToSelector:@selector(appiraterDidDismissModalView:animated:)]) {
				[delegate appiraterDidDismissModalView:(Appirater *)self animated:usedAnimation];
			}
		}];
		[self.class setStatusBarStyle:(UIStatusBarStyle)nil];
	}
}

@end
