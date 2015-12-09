//
//  CRToast
//  Copyright (c) 2014-2015 Collin Ruffenach. All rights reserved.
//

#import "CRToastManager.h"
#import "CRToast.h"
#import "CRToastView.h"
#import "CRToastViewController.h"
#import "CRToastWindow.h"
#import "CRToastLayoutHelpers.h"

@interface CRToast (CRToastManager)
+ (void)setDefaultOptions:(NSDictionary*)defaultOptions;
+ (instancetype)notificationWithOptions:(NSDictionary*)options appearanceBlock:(void (^)(void))appearance completionBlock:(void (^)(void))completion;
@end

@interface CRToastManager () <UICollisionBehaviorDelegate>
@property (nonatomic, readonly) BOOL showingNotification;
@property (nonatomic, strong) UIWindow *notificationWindow;
//@property (nonatomic, strong) UIView *statusBarView;
//@property (nonatomic, strong) UIView *notificationView;
//@property (nonatomic, readonly) CRToast *notification;
@property (nonatomic, strong) NSMutableArray *notifications;
@property (nonatomic, copy) void (^gravityAnimationCompletionBlock)(BOOL finished);
@end

static NSString *const kCRToastManagerCollisionBoundryIdentifier = @"kCRToastManagerCollisionBoundryIdentifier";

typedef void (^CRToastAnimationCompletionBlock)(BOOL animated);
typedef void (^CRToastAnimationStepBlock)(void);

@implementation CRToastManager

+ (void)setDefaultOptions:(NSDictionary*)defaultOptions {
    [CRToast setDefaultOptions:defaultOptions];
}

+ (void)showNotificationWithMessage:(NSString*)message completionBlock:(void (^)(void))completion {
    [self showNotificationWithOptions:@{kCRToastTextKey : message}
                      completionBlock:completion];
}

+ (void)showNotificationWithOptions:(NSDictionary*)options completionBlock:(void (^)(void))completion {
    [self showNotificationWithOptions:options
                       apperanceBlock:nil
                      completionBlock:completion];
}

+ (void)showNotificationWithOptions:(NSDictionary*)options
                     apperanceBlock:(void (^)(void))appearance
                    completionBlock:(void (^)(void))completion
{
    [[CRToastManager manager] addNotification:[CRToast notificationWithOptions:options
                                                               appearanceBlock:appearance
                                                               completionBlock:completion]];
}


//+ (void)dismissNotification:(BOOL)animated {
//    [[self manager] dismissNotification:animated];
//}

+ (void)dismissAllNotifications:(BOOL)animated {
    [[self manager] dismissAllNotifications:animated];
}

//+ (void)dismissAllNotificationsWithIdentifier:(NSString *)identifer animated:(BOOL)animated {
//    [[self manager] dismissAllNotificationsWithIdentifier:identifer animated:animated];
//}

+ (NSArray *)notificationIdentifiersInQueue {
    return [[self manager] notificationIdentifiersInQueue];
}

+ (BOOL)isShowingNotification {
	return [[self manager] showingNotification];
}

+ (instancetype)manager {
    static dispatch_once_t once;
    static id sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        UIWindow *notificationWindow = [[CRToastWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        notificationWindow.backgroundColor = [UIColor clearColor];
        notificationWindow.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        notificationWindow.windowLevel = UIWindowLevelStatusBar;
        notificationWindow.rootViewController = [CRToastViewController new];
        notificationWindow.rootViewController.view.clipsToBounds = YES;
        self.notificationWindow = notificationWindow;
        
        self.notifications = [@[] mutableCopy];
    }
    return self;
}

#pragma mark - -- Notification Management --
#pragma mark - Notification Animation Blocks
#pragma mark Inward Animations
CRToastAnimationStepBlock CRToastInwardAnimationsBlock(CRToastManager *weakSelf, CRToast *weakNotification) {
    return ^void(void) {
        weakNotification.notificationView.frame = weakSelf.notificationWindow.rootViewController.view.bounds;
        weakNotification.statusBarView.frame = weakNotification.statusBarViewAnimationFrame1;
    };
}

CRToastAnimationCompletionBlock CRToastInwardAnimationsCompletionBlock(CRToastManager *weakSelf, CRToast *weakNotification, NSString *notificationUUIDString) {
    return ^void(BOOL finished) {
        if (weakNotification.timeInterval != DBL_MAX && weakNotification.state == CRToastStateEntering) {
            weakNotification.state = CRToastStateDisplaying;
            if (!weakNotification.forceUserInteraction) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(weakNotification.timeInterval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (weakNotification.state == CRToastStateDisplaying && [weakNotification.uuid.UUIDString isEqualToString:notificationUUIDString]) {
                        weakSelf.gravityAnimationCompletionBlock = NULL;
                        CRToastOutwardAnimationsSetupBlock(weakSelf, weakNotification)();
                    }
                });
            }
        }
    };
}

#pragma mark Outward Animations
CRToastAnimationCompletionBlock CRToastOutwardAnimationsCompletionBlock(CRToastManager *weakSelf, CRToast *weakNotification) {
    return ^void(BOOL completed){
        if (weakNotification.showActivityIndicator) {
            [[(CRToastView *)weakNotification activityIndicator] stopAnimating];
        }
        weakSelf.notificationWindow.rootViewController.view.gestureRecognizers = nil;
        weakNotification.state = CRToastStateCompleted;
        if (weakNotification.completion) weakNotification.completion();
        [weakSelf.notifications removeObject:weakNotification];
        [weakNotification.notificationView removeFromSuperview];
        [weakNotification.statusBarView removeFromSuperview];
        if (weakSelf.notifications.count > 0) {
//            CRToast *notification = weakSelf.notifications.firstObject;
//            weakSelf.gravityAnimationCompletionBlock = NULL;
//            [weakSelf displayNotification:notification];
        } else {
            weakSelf.notificationWindow.hidden = YES;
        }
    };
}

CRToastAnimationStepBlock CRToastOutwardAnimationsBlock(CRToastManager *weakSelf, CRToast *weakNotification) {
    return ^{
        weakNotification.state = CRToastStateExiting;
        [weakNotification.animator removeAllBehaviors];
        CGRect frame = weakNotification.notificationViewAnimationFrame2;
        if (weakNotification.shouldKeepNavigationBarBorder) {
            frame.size.height -= 1.0f;
        }
        weakNotification.notificationView.frame = frame;
        weakNotification.statusBarView.frame = weakSelf.notificationWindow.rootViewController.view.bounds;
    };
}

CRToastAnimationStepBlock CRToastOutwardAnimationsSetupBlock(CRToastManager *weakSelf, CRToast *weakNotification) {
    return ^{
        weakNotification.state = CRToastStateExiting;
        weakNotification.statusBarView.frame = weakNotification.statusBarViewAnimationFrame2;
        [weakSelf.notificationWindow.rootViewController.view.gestureRecognizers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            [(UIGestureRecognizer*)obj setEnabled:NO];
        }];
        
        switch (weakNotification.outAnimationType) {
            case CRToastAnimationTypeLinear: {
                [UIView animateWithDuration:weakNotification.animateOutTimeInterval
                                      delay:0
                                    options:0
                                 animations:CRToastOutwardAnimationsBlock(weakSelf, weakNotification)
                                 completion:CRToastOutwardAnimationsCompletionBlock(weakSelf, weakNotification)];
            } break;
            case CRToastAnimationTypeSpring: {
                [UIView animateWithDuration:weakNotification.animateOutTimeInterval
                                      delay:0
                     usingSpringWithDamping:weakNotification.animationSpringDamping
                      initialSpringVelocity:weakNotification.animationSpringInitialVelocity
                                    options:0
                                 animations:CRToastOutwardAnimationsBlock(weakSelf, weakNotification)
                                 completion:CRToastOutwardAnimationsCompletionBlock(weakSelf, weakNotification)];
            } break;
            case CRToastAnimationTypeGravity: {
                if (weakNotification.animator == nil) {
                    [weakNotification initiateAnimator:weakSelf.notificationWindow.rootViewController.view];
                }
                [weakNotification.animator removeAllBehaviors];
                UIGravityBehavior *gravity = [[UIGravityBehavior alloc]initWithItems:@[weakNotification.notificationView, weakNotification.statusBarView]];
                gravity.gravityDirection = weakNotification.outGravityDirection;
                gravity.magnitude = weakNotification.animationGravityMagnitude;
                NSMutableArray *collisionItems = [@[weakNotification.notificationView] mutableCopy];
                if (weakNotification.presentationType == CRToastPresentationTypePush) [collisionItems addObject:weakNotification.statusBarView];
                UICollisionBehavior *collision = [[UICollisionBehavior alloc] initWithItems:collisionItems];
                collision.collisionDelegate = weakSelf;
                [collision addBoundaryWithIdentifier:kCRToastManagerCollisionBoundryIdentifier
                                           fromPoint:weakNotification.outCollisionPoint1
                                             toPoint:weakNotification.outCollisionPoint2];
                UIDynamicItemBehavior *rotationLock = [[UIDynamicItemBehavior alloc] initWithItems:collisionItems];
                rotationLock.allowsRotation = NO;
                [weakNotification.animator addBehavior:gravity];
                [weakNotification.animator addBehavior:collision];
                [weakNotification.animator addBehavior:rotationLock];
                weakSelf.gravityAnimationCompletionBlock = CRToastOutwardAnimationsCompletionBlock(weakSelf, weakNotification);
            } break;
        }
    };
}

#pragma mark -

- (NSArray *)notificationIdentifiersInQueue {
    if (_notifications.count == 0) { return @[]; }
    return [[_notifications valueForKeyPath:@"options.kCRToastIdentifierKey"] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF != nil"]];
}

- (void)dismissNotification:(CRToast *)notification animated:(BOOL)animated {
    if (_notifications.count == 0) return;
    
    if (animated && (notification.state == CRToastStateEntering || notification.state == CRToastStateDisplaying)) {
        __weak __block typeof(self) weakSelf = self;
        __weak __block typeof(CRToast *) weakNotification = notification;
        CRToastOutwardAnimationsSetupBlock(weakSelf, weakNotification)();
    } else {
        __weak __block typeof(self) weakSelf = self;
        __weak __block typeof(CRToast *) weakNotification = notification;
        CRToastOutwardAnimationsCompletionBlock(weakSelf, weakNotification)(YES);
    }
}

- (void)dismissAllNotifications:(BOOL)animated {
    if (_notifications.count == 0) { return; }
    
    NSArray *notifications = [_notifications mutableCopy]; //copy to prevent crash: Array was mutated while being enumerated.
    for(CRToast *notification in notifications) {
        if (notification.state == CRToastStateDisplaying){
            [self dismissNotification:notification animated:animated];
        }
    }
    
}

//- (void)dismissAllNotificationsWithIdentifier:(NSString *)identifer animated:(BOOL)animated {
//    if (_notifications.count == 0) { return; }
//    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
//    
//    __block BOOL callDismiss = NO;
//    [self.notifications enumerateObjectsUsingBlock:^(CRToast *toast, NSUInteger idx, BOOL *stop) {
//        NSString *toastIdentifier = toast.options[kCRToastIdentifierKey];
//        if (toastIdentifier && [toastIdentifier isEqualToString:identifer]) {
//            if (idx == 0) { callDismiss = YES; }
//            else {
//                [indexes addIndex:idx];
//            }
//        }
//    }];
//    [self.notifications removeObjectsAtIndexes:indexes];
//    if (callDismiss) { [self dismissNotification:animated]; }
//}

- (void)addNotification:(CRToast*)notification {
    if(notification.queueToast){
        BOOL showingNotification = self.showingNotification;
        [_notifications addObject:notification];
        if (!showingNotification) {
            [self displayNotification:notification];
        }
    } else {
        [_notifications addObject:notification];
        [self displayNotification:notification];
    }
}

- (void)displayNotification:(CRToast*)notification {
    
    if (notification.state == CRToastStateEntering || notification.state == CRToastStateDisplaying || notification.state == CRToastStateExiting){
        return;
    }
    
    if (notification.appearance != nil) {
        notification.appearance();
    }
    
    _notificationWindow.hidden = NO;
    CGSize notificationSize = CRNotificationViewSize(notification.notificationType, notification.preferredHeight);
    if (notification.shouldKeepNavigationBarBorder) {
        notificationSize.height -= 1.0f;
    }
    
    CGRect containerFrame = CRGetNotificationContainerFrame(CRGetDeviceOrientation(), notificationSize);
    
    CRToastViewController *rootViewController = (CRToastViewController*)_notificationWindow.rootViewController;
    rootViewController.statusBarStyle = notification.statusBarStyle;
    rootViewController.autorotate = notification.autorotate;
    rootViewController.notification = notification;
    
    _notificationWindow.rootViewController.view.frame = containerFrame;
    _notificationWindow.windowLevel = notification.displayUnderStatusBar ? UIWindowLevelNormal + 1 : UIWindowLevelStatusBar;
    
    UIView *statusBarView = notification.statusBarView;
    statusBarView.frame = _notificationWindow.rootViewController.view.bounds;
    [_notificationWindow.rootViewController.view addSubview:statusBarView];
//    self.statusBarView = statusBarView;
    statusBarView.hidden = notification.presentationType == CRToastPresentationTypeCover;
    
    UIView *notificationView = notification.notificationView;
    notificationView.frame = notification.notificationViewAnimationFrame1;
    [_notificationWindow.rootViewController.view addSubview:notificationView];
//    self.notificationView = notificationView;
    rootViewController.toastView = notificationView;
//    self.statusBarView = statusBarView;
    
    for (UIView *subview in notificationView.subviews) {
        if([subview isKindOfClass:[UIButton class]]){
            
        } else {
            subview.userInteractionEnabled = NO;
        }
    }
    
    _notificationWindow.rootViewController.view.userInteractionEnabled = YES;
    _notificationWindow.rootViewController.view.gestureRecognizers = notification.gestureRecognizers;
    
    __weak __block typeof(self) weakSelf = self;
    __weak __block typeof(CRToast *) weakNotification = notification;
    CRToastAnimationStepBlock inwardAnimationsBlock = CRToastInwardAnimationsBlock(weakSelf, weakNotification);
    
    NSString *notificationUUIDString = notification.uuid.UUIDString;
    CRToastAnimationCompletionBlock inwardAnimationsCompletionBlock = CRToastInwardAnimationsCompletionBlock(weakSelf, weakNotification, notificationUUIDString);
    
    notification.state = CRToastStateEntering;
    
    [self showNotification:notification inwardAnimationBlock:inwardAnimationsBlock inwardCompletionAnimationBlock:inwardAnimationsCompletionBlock];
    
    if (notification.text.length > 0 || notification.subtitleText.length > 0) {
        // Synchronous notifications (say, tapping a button that presents a toast) cause VoiceOver to read the button immediately, which interupts the toast. A short delay (not the best solution :/) allows the toast to interupt the button.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [NSString stringWithFormat:@"Alert: %@, %@", notification.text ?: @"", notification.subtitleText ?: @""]);
        });
    }
}

- (void)showNotification:(CRToast *)notification
     inwardAnimationBlock:(CRToastAnimationStepBlock)inwardAnimationsBlock
inwardCompletionAnimationBlock:(CRToastAnimationCompletionBlock)inwardAnimationsCompletionBlock {
    
    switch (notification.inAnimationType) {
        case CRToastAnimationTypeLinear: {
            [UIView animateWithDuration:notification.animateInTimeInterval
                             animations:inwardAnimationsBlock
                             completion:inwardAnimationsCompletionBlock];
        } break;
        case CRToastAnimationTypeSpring: {
            [UIView animateWithDuration:notification.animateInTimeInterval
                                  delay:0.0
                 usingSpringWithDamping:notification.animationSpringDamping
                  initialSpringVelocity:notification.animationSpringInitialVelocity
                                options:0
                             animations:inwardAnimationsBlock
                             completion:inwardAnimationsCompletionBlock];
        } break;
        case CRToastAnimationTypeGravity: {
            UIView *notificationView = notification.notificationView;
            UIView *statusBarView = notification.statusBarView;
            
            [notification initiateAnimator:_notificationWindow.rootViewController.view];
            [notification.animator removeAllBehaviors];
            UIGravityBehavior *gravity = [[UIGravityBehavior alloc] initWithItems:@[notificationView, statusBarView]];
            gravity.gravityDirection = notification.inGravityDirection;
            gravity.magnitude = notification.animationGravityMagnitude;
            NSMutableArray *collisionItems = [@[notificationView] mutableCopy];
            if (notification.presentationType == CRToastPresentationTypePush) [collisionItems addObject:statusBarView];
            UICollisionBehavior *collision = [[UICollisionBehavior alloc] initWithItems:collisionItems];
            collision.collisionDelegate = self;
            [collision addBoundaryWithIdentifier:kCRToastManagerCollisionBoundryIdentifier
                                       fromPoint:notification.inCollisionPoint1
                                         toPoint:notification.inCollisionPoint2];
            UIDynamicItemBehavior *rotationLock = [[UIDynamicItemBehavior alloc] initWithItems:collisionItems];
            rotationLock.allowsRotation = NO;
            [notification.animator addBehavior:gravity];
            [notification.animator addBehavior:collision];
            [notification.animator addBehavior:rotationLock];
            self.gravityAnimationCompletionBlock = inwardAnimationsCompletionBlock;
        } break;
    }
}


#pragma mark - Overrides

- (BOOL)showingNotification {
    return self.notifications.count > 0;
}

//- (CRToast*)notification {
//    return _notifications.firstObject;
//}

#pragma mark - UICollisionBehaviorDelegate

- (void)collisionBehavior:(UICollisionBehavior*)behavior
      endedContactForItem:(id <UIDynamicItem>)item
   withBoundaryIdentifier:(id <NSCopying>)identifier {
    if (self.gravityAnimationCompletionBlock) {
        self.gravityAnimationCompletionBlock(YES);
    }
}

- (void)collisionBehavior:(UICollisionBehavior*)behavior
      endedContactForItem:(id <UIDynamicItem>)item1
                 withItem:(id <UIDynamicItem>)item2 {
    if (self.gravityAnimationCompletionBlock) {
        self.gravityAnimationCompletionBlock(YES);
        self.gravityAnimationCompletionBlock = NULL;
    }
}

@end
