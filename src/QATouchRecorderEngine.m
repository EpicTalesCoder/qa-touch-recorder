#import "QATouchRecorderEngine.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <math.h>

@interface UIWindow (QATouchCapture)
- (void)qa_sendEvent:(UIEvent *)event;
@end

@implementation UIWindow (QATouchCapture)

- (void)qa_sendEvent:(UIEvent *)event {
    [self qa_sendEvent:event];

    if (event.type != UIEventTypeTouches) return;
    if ([NSStringFromClass([self class]) isEqualToString:@"QATouchOverlayWindow"]) return;

    [[QATouchRecorderEngine shared] handleObservedTouchEvent:event inWindow:self];
}

@end

#pragma mark - Public UIKit Replay Helpers

static UIWindowScene * _Nullable QAActiveForegroundWindowScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            return (UIWindowScene *)scene;
        }
    }
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static NSArray<UIWindow *> *QATargetAppWindowsTopToBottom(void) {
    UIWindowScene *scene = QAActiveForegroundWindowScene();
    if (!scene) return @[];

    NSMutableArray<UIWindow *> *candidates = [NSMutableArray array];
    for (UIWindow *win in scene.windows) {
        if (win.hidden || win.alpha <= 0.01) continue;
        NSString *cls = NSStringFromClass([win class]);
        if ([cls isEqualToString:@"QATouchOverlayWindow"]) continue;
        if ([cls containsString:@"Keyboard"] || [cls containsString:@"TextEffects"]) continue;
        [candidates addObject:win];
    }

    [candidates sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel != b.windowLevel) {
            return (a.windowLevel > b.windowLevel) ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.isKeyWindow != b.isKeyWindow) {
            return a.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    return [candidates copy];
}

static BOOL QATriggerControlOrCellInHierarchy(UIView *hitView) {
    // Pass 1: Prefer explicit UIControl, UITextField/UITextView, or Collection/Table cells.
    UIView *cursor = hitView;
    while (cursor) {
        if ([cursor isKindOfClass:[UITextField class]]) {
            UITextField *tf = (UITextField *)cursor;
            if (tf.enabled) {
                [tf becomeFirstResponder];
                return YES;
            }
        }
        if ([cursor isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)cursor;
            if (tv.editable) {
                [tv becomeFirstResponder];
                return YES;
            }
        }
        if ([cursor isKindOfClass:[UIControl class]]) {
            UIControl *ctrl = (UIControl *)cursor;
            if (ctrl.enabled && !ctrl.hidden && ctrl.alpha > 0.01) {
                [ctrl sendActionsForControlEvents:UIControlEventTouchDown];
                [ctrl sendActionsForControlEvents:UIControlEventTouchUpInside];
                return YES;
            }
        }
        if ([cursor isKindOfClass:[UITableViewCell class]]) {
            UITableViewCell *cell = (UITableViewCell *)cursor;
            UIView *parent = cell.superview;
            while (parent && ![parent isKindOfClass:[UITableView class]]) {
                parent = parent.superview;
            }
            if ([parent isKindOfClass:[UITableView class]]) {
                UITableView *tv = (UITableView *)parent;
                NSIndexPath *ip = [tv indexPathForCell:cell];
                if (ip) {
                    [tv selectRowAtIndexPath:ip animated:YES scrollPosition:UITableViewScrollPositionNone];
                    if ([tv.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)]) {
                        [tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
                    }
                    return YES;
                }
            }
        }
        if ([cursor isKindOfClass:[UICollectionViewCell class]]) {
            UICollectionViewCell *cell = (UICollectionViewCell *)cursor;
            UIView *parent = cell.superview;
            while (parent && ![parent isKindOfClass:[UICollectionView class]]) {
                parent = parent.superview;
            }
            if ([parent isKindOfClass:[UICollectionView class]]) {
                UICollectionView *cv = (UICollectionView *)parent;
                NSIndexPath *ip = [cv indexPathForCell:cell];
                if (ip) {
                    [cv selectItemAtIndexPath:ip animated:YES scrollPosition:UICollectionViewScrollPositionNone];
                    if ([cv.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)]) {
                        [cv.delegate collectionView:cv didSelectItemAtIndexPath:ip];
                    }
                    return YES;
                }
            }
        }
        cursor = cursor.superview;
    }

    // Pass 2: Accessibility activation fallback for custom interactive views / SwiftUI controls.
    cursor = hitView;
    while (cursor) {
        if (cursor.isAccessibilityElement && [cursor accessibilityActivate]) {
            return YES;
        }
        cursor = cursor.superview;
    }
    return NO;
}

static BOOL QADispatchTapAtWindowPoint(CGPoint pt) {
    for (UIWindow *win in QATargetAppWindowsTopToBottom()) {
        CGPoint localPt = [win convertPoint:pt fromWindow:nil];
        UIView *hit = [win hitTest:localPt withEvent:nil];
        if (!hit) continue;
        if (QATriggerControlOrCellInHierarchy(hit)) {
            return YES;
        }
    }
    return NO;
}

static UIScrollView * _Nullable QAFindScrollableViewAtPoint(CGPoint pt) {
    for (UIWindow *win in QATargetAppWindowsTopToBottom()) {
        CGPoint localPt = [win convertPoint:pt fromWindow:nil];
        UIView *hit = [win hitTest:localPt withEvent:nil];
        UIView *cursor = hit;
        while (cursor) {
            if ([cursor isKindOfClass:[UIScrollView class]]) {
                UIScrollView *sv = (UIScrollView *)cursor;
                BOOL canScrollX = sv.contentSize.width > CGRectGetWidth(sv.bounds) + 1.0;
                BOOL canScrollY = sv.contentSize.height > CGRectGetHeight(sv.bounds) + 1.0;
                if (sv.scrollEnabled && (canScrollX || canScrollY)) {
                    return sv;
                }
            }
            cursor = cursor.superview;
        }
    }
    return nil;
}

static BOOL QADispatchSwipeBetweenPoints(CGPoint startPt, CGPoint endPt) {
    UIScrollView *sv = QAFindScrollableViewAtPoint(startPt);
    if (!sv) {
        sv = QAFindScrollableViewAtPoint(endPt);
    }
    if (!sv) return NO;

    CGFloat dx = startPt.x - endPt.x;
    CGFloat dy = startPt.y - endPt.y;

    if (sv.pagingEnabled && fabs(dx) > fabs(dy) && fabs(dx) >= 24.0) {
        dx = (dx > 0.0) ? CGRectGetWidth(sv.bounds) : -CGRectGetWidth(sv.bounds);
    }
    if (sv.pagingEnabled && fabs(dy) >= fabs(dx) && fabs(dy) >= 24.0) {
        dy = (dy > 0.0) ? CGRectGetHeight(sv.bounds) : -CGRectGetHeight(sv.bounds);
    }

    UIEdgeInsets inset = sv.adjustedContentInset;
    CGFloat minX = -inset.left;
    CGFloat maxX = MAX(minX, sv.contentSize.width - CGRectGetWidth(sv.bounds) + inset.right);
    CGFloat minY = -inset.top;
    CGFloat maxY = MAX(minY, sv.contentSize.height - CGRectGetHeight(sv.bounds) + inset.bottom);

    CGFloat targetX = MIN(MAX(sv.contentOffset.x + dx, minX), maxX);
    CGFloat targetY = MIN(MAX(sv.contentOffset.y + dy, minY), maxY);
    [sv setContentOffset:CGPointMake(targetX, targetY) animated:YES];
    return YES;
}

#pragma mark - QATouchRecorderEngine

@interface QATouchRecorderEngine ()
@property (nonatomic, assign, readwrite) QARecorderState state;
@property (nonatomic, strong, readwrite) QATouchScript *currentScript;
@property (nonatomic, strong) QATouchStrokeTracker *strokeTracker;
@property (nonatomic, strong, nullable) QATouchLoopPlanner *loopPlanner;
@property (nonatomic, assign) NSUInteger playbackGeneration;
@end

@implementation QATouchRecorderEngine

+ (instancetype)shared {
    static QATouchRecorderEngine *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[QATouchRecorderEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = QARecorderStateIdle;
        _currentScript = [[QATouchScript alloc] initWithName:@"QA_Script"];
        _strokeTracker = [[QATouchStrokeTracker alloc] init];
        _repeatLimit = 1;
        _speedMultiplier = 1.0;
    }
    return self;
}

- (void)installTouchObserverIfNeeded {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method original = class_getInstanceMethod([UIWindow class], @selector(sendEvent:));
        Method swizzled = class_getInstanceMethod([UIWindow class], @selector(qa_sendEvent:));
        if (original && swizzled) {
            method_exchangeImplementations(original, swizzled);
        }
    });
}

- (void)setState:(QARecorderState)state {
    _state = state;
    if ([self.delegate respondsToSelector:@selector(touchRecorderDidUpdateState:)]) {
        [self.delegate touchRecorderDidUpdateState:state];
    }
}

- (void)notifyScriptChanged {
    if ([self.delegate respondsToSelector:@selector(touchRecorderDidChangeScript:)]) {
        [self.delegate touchRecorderDidChangeScript:self.currentScript];
    }
}

- (void)startRecording {
    NSAssert([NSThread isMainThread], @"startRecording must run on main thread");
    if (self.state == QARecorderStatePlaying) {
        [self stopPlayback];
    }
    [self installTouchObserverIfNeeded];
    [self.strokeTracker resetSession];
    self.state = QARecorderStateRecording;
}

- (void)stopRecording {
    NSAssert([NSThread isMainThread], @"stopRecording must run on main thread");
    if (self.state != QARecorderStateRecording) return;
    [self.strokeTracker resetSession];
    self.state = QARecorderStateIdle;
}

- (void)startPlayback {
    NSAssert([NSThread isMainThread], @"startPlayback must run on main thread");
    if (self.state == QARecorderStateRecording) {
        [self stopRecording];
    }
    NSArray<QATouchAction *> *actions = self.currentScript.actions;
    if (actions.count == 0) return;

    self.playbackGeneration += 1;
    self.loopPlanner = [[QATouchLoopPlanner alloc] initWithActionCount:actions.count
                                                           repeatLimit:self.repeatLimit
                                                       speedMultiplier:self.speedMultiplier];
    self.state = QARecorderStatePlaying;
    [self scheduleNextPlaybackStepWithGeneration:self.playbackGeneration];
}

- (void)stopPlayback {
    NSAssert([NSThread isMainThread], @"stopPlayback must run on main thread");
    self.playbackGeneration += 1;
    self.loopPlanner = nil;
    if (self.state == QARecorderStatePlaying) {
        self.state = QARecorderStateIdle;
    }
}

- (void)scheduleNextPlaybackStepWithGeneration:(NSUInteger)generation {
    if (generation != self.playbackGeneration || self.state != QARecorderStatePlaying) return;

    QATouchLoopPlanner *planner = self.loopPlanner;
    NSArray<QATouchAction *> *actions = self.currentScript.actions;
    if (!planner || planner.isFinished || planner.currentStepIndex >= actions.count) {
        [self stopPlayback];
        return;
    }

    QATouchAction *action = actions[planner.currentStepIndex];
    if ([self.delegate respondsToSelector:@selector(touchRecorderDidAdvanceIteration:repeatLimit:stepIndex:stepCount:)]) {
        [self.delegate touchRecorderDidAdvanceIteration:planner.currentIteration
                                           repeatLimit:planner.repeatLimit
                                             stepIndex:planner.currentStepIndex
                                             stepCount:actions.count];
    }

    NSTimeInterval delay = [planner scaledDelayForAction:action];
    NSTimeInterval duration = [planner scaledDurationForAction:action];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self.playbackGeneration || self.state != QARecorderStatePlaying) return;

        [self executeSingleAction:action scaledDuration:duration];

        NSTimeInterval postStepWait = (action.actionType == QATouchActionTypeSwipe)
            ? MAX(0.35, duration + 0.12)
            : MAX(0.12, duration + 0.06);

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(postStepWait * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != self.playbackGeneration || self.state != QARecorderStatePlaying) return;
            if ([planner advanceToNextStep]) {
                [self scheduleNextPlaybackStepWithGeneration:generation];
            } else {
                [self stopPlayback];
            }
        });
    });
}

- (void)executeSingleAction:(QATouchAction *)action scaledDuration:(NSTimeInterval)duration {
    CGPoint startPt = CGPointMake(action.startPoint.x, action.startPoint.y);
    CGPoint endPt = CGPointMake(action.endPoint.x, action.endPoint.y);

    if (action.actionType == QATouchActionTypeTap) {
        if ([self.delegate respondsToSelector:@selector(touchRecorderShowVisualTapAtPoint:)]) {
            [self.delegate touchRecorderShowVisualTapAtPoint:startPt];
        }
        QADispatchTapAtWindowPoint(startPt);
        return;
    }

    if ([self.delegate respondsToSelector:@selector(touchRecorderShowVisualSwipeFromPoint:toPoint:duration:)]) {
        [self.delegate touchRecorderShowVisualSwipeFromPoint:startPt toPoint:endPt duration:duration];
    }
    QADispatchSwipeBetweenPoints(startPt, endPt);
}

#pragma mark - Touch Observation

- (void)handleObservedTouchEvent:(UIEvent *)event inWindow:(UIWindow *)window {
    if (self.state != QARecorderStateRecording) return;

    NSTimeInterval ts = (event.timestamp > 0.0) ? event.timestamp : CACurrentMediaTime();
    for (UITouch *touch in event.allTouches) {
        NSValue *touchKey = [NSValue valueWithPointer:(__bridge const void *)touch];
        CGPoint winPt = [touch locationInView:window];
        CGPoint scenePt = [window convertPoint:winPt toWindow:nil];
        QATouchPoint *qaPoint = [QATouchPoint pointWithX:scenePt.x y:scenePt.y];

        switch (touch.phase) {
            case UITouchPhaseBegan:
                [self.strokeTracker beginTouchID:touchKey atPoint:qaPoint timestamp:ts];
                break;
            case UITouchPhaseMoved:
                [self.strokeTracker moveTouchID:touchKey toPoint:qaPoint timestamp:ts];
                break;
            case UITouchPhaseEnded: {
                QATouchAction *recorded = [self.strokeTracker endTouchID:touchKey
                                                                 atPoint:qaPoint
                                                               timestamp:ts];
                if (recorded) {
                    [self.currentScript addAction:recorded];
                    [self notifyScriptChanged];
                }
                break;
            }
            case UITouchPhaseCancelled:
                [self.strokeTracker cancelTouchID:touchKey];
                break;
            default:
                break;
        }
    }
}

#pragma mark - Script Management

- (void)clearCurrentScript {
    if (self.state == QARecorderStatePlaying) [self stopPlayback];
    [self.currentScript clearActions];
    [self notifyScriptChanged];
}

- (void)removeActionAtIndex:(NSUInteger)index {
    if (self.state == QARecorderStatePlaying) [self stopPlayback];
    [self.currentScript removeActionAtIndex:index];
    [self notifyScriptChanged];
}

- (void)replaceCurrentScript:(QATouchScript *)script {
    if (self.state == QARecorderStatePlaying) [self stopPlayback];
    self.currentScript = [script copy] ?: [[QATouchScript alloc] initWithName:@"QA_Script"];
    [self notifyScriptChanged];
}

- (NSString *)scriptsDirectoryPath {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    return [docs stringByAppendingPathComponent:@"QATouchScripts"];
}

- (BOOL)saveCurrentScriptWithName:(NSString *)name error:(NSError * _Nullable * _Nullable)error {
    self.currentScript.name = name;
    return [self.currentScript saveToDirectory:[self scriptsDirectoryPath] error:error];
}

- (BOOL)loadScriptNamed:(NSString *)name error:(NSError * _Nullable * _Nullable)error {
    QATouchScript *loaded = [QATouchScript loadNamed:name
                                       fromDirectory:[self scriptsDirectoryPath]
                                               error:error];
    if (!loaded) return NO;
    [self replaceCurrentScript:loaded];
    return YES;
}

- (BOOL)deleteScriptNamed:(NSString *)name error:(NSError * _Nullable * _Nullable)error {
    return [QATouchScript deleteNamed:name fromDirectory:[self scriptsDirectoryPath] error:error];
}

- (NSArray<NSString *> *)savedScriptNames {
    return [QATouchScript listScriptNamesInDirectory:[self scriptsDirectoryPath]];
}

@end
