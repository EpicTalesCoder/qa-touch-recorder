#import <UIKit/UIKit.h>
#import "QATouchScriptModel.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QARecorderState) {
    QARecorderStateIdle = 0,
    QARecorderStateRecording,
    QARecorderStatePlaying
};

@protocol QATouchRecorderEngineDelegate <NSObject>
@optional
- (void)touchRecorderDidUpdateState:(QARecorderState)state;
- (void)touchRecorderDidChangeScript:(QATouchScript *)script;
- (void)touchRecorderDidAdvanceIteration:(NSInteger)iteration
                           repeatLimit:(NSInteger)repeatLimit
                             stepIndex:(NSUInteger)stepIndex
                             stepCount:(NSUInteger)stepCount;
- (void)touchRecorderShowVisualTapAtPoint:(CGPoint)point;
- (void)touchRecorderShowVisualSwipeFromPoint:(CGPoint)startPoint
                                    toPoint:(CGPoint)endPoint
                                   duration:(NSTimeInterval)duration;
@end

/// Coordinates UIWindow touch event observation (recording) and pure public UIKit replay.
/// Contains zero memory tampering, zero private SPI touch injection, and zero DRM/jailbreak hooks.
@interface QATouchRecorderEngine : NSObject

@property (nonatomic, weak, nullable) id<QATouchRecorderEngineDelegate> delegate;
@property (nonatomic, assign, readonly) QARecorderState state;
@property (nonatomic, strong, readonly) QATouchScript *currentScript;
@property (nonatomic, assign) NSInteger repeatLimit;     // 0 = infinite loop
@property (nonatomic, assign) double speedMultiplier;    // 0.5, 1.0, 1.5, 2.0

+ (instancetype)shared;

/// Installs the UIWindow sendEvent: observer once after UIApplication/UIScene startup.
- (void)installTouchObserverIfNeeded;

- (void)startRecording;
- (void)stopRecording;

- (void)startPlayback;
- (void)stopPlayback;

- (void)clearCurrentScript;
- (void)removeActionAtIndex:(NSUInteger)index;
- (void)replaceCurrentScript:(QATouchScript *)script;

- (NSString *)scriptsDirectoryPath;
- (BOOL)saveCurrentScriptWithName:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (BOOL)loadScriptNamed:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (BOOL)deleteScriptNamed:(NSString *)name error:(NSError * _Nullable * _Nullable)error;
- (NSArray<NSString *> *)savedScriptNames;

/// Internal entry called by swizzled UIWindow sendEvent:.
- (void)handleObservedTouchEvent:(UIEvent *)event inWindow:(UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
