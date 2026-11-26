#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QATouchActionType) {
    QATouchActionTypeTap = 0,
    QATouchActionTypeSwipe = 1
};

/// Pure Foundation 2D coordinate so the model compiles & tests cleanly on both macOS host and iOS.
@interface QATouchPoint : NSObject <NSCopying>

@property (nonatomic, assign, readonly) double x;
@property (nonatomic, assign, readonly) double y;

+ (instancetype)pointWithX:(double)x y:(double)y;
- (instancetype)initWithX:(double)x y:(double)y NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (double)distanceTo:(QATouchPoint *)other;
- (NSDictionary<NSString *, NSNumber *> *)toDictionary;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;

@end

/// One recorded user interaction (tap or swipe) in window point coordinates.
@interface QATouchAction : NSObject <NSCopying>

@property (nonatomic, assign, readonly) QATouchActionType actionType;
@property (nonatomic, strong, readonly) QATouchPoint *startPoint;
@property (nonatomic, strong, readonly) QATouchPoint *endPoint;
@property (nonatomic, copy, readonly) NSArray<QATouchPoint *> *waypoints;
@property (nonatomic, assign, readonly) NSTimeInterval delayBefore;
@property (nonatomic, assign, readonly) NSTimeInterval duration;

+ (instancetype)tapAtPoint:(QATouchPoint *)point
               delayBefore:(NSTimeInterval)delayBefore
                  duration:(NSTimeInterval)duration;

+ (instancetype)swipeFromPoint:(QATouchPoint *)startPoint
                       toPoint:(QATouchPoint *)endPoint
                     waypoints:(NSArray<QATouchPoint *> *)waypoints
                   delayBefore:(NSTimeInterval)delayBefore
                      duration:(NSTimeInterval)duration;

- (NSString *)humanReadableSummary;
- (NSDictionary<NSString *, id> *)toDictionary;
+ (nullable instancetype)fromDictionary:(NSDictionary *)dict;

@end

/// Named collection of recorded QA actions with JSON persistence.
@interface QATouchScript : NSObject <NSCopying>

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, readonly) NSArray<QATouchAction *> *actions;
@property (nonatomic, assign, readonly) NSTimeInterval createdAtTimestamp;

- (instancetype)initWithName:(NSString *)name
                     actions:(NSArray<QATouchAction *> *)actions
          createdAtTimestamp:(NSTimeInterval)createdAtTimestamp NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithName:(NSString *)name;
- (instancetype)init NS_UNAVAILABLE;

- (void)addAction:(QATouchAction *)action;
- (void)removeActionAtIndex:(NSUInteger)index;
- (void)clearActions;

- (nullable NSData *)toJSONData:(NSError * _Nullable * _Nullable)error;
+ (nullable instancetype)fromJSONData:(NSData *)data error:(NSError * _Nullable * _Nullable)error;

+ (NSString *)sanitizedFilenameForScriptName:(NSString *)name;
+ (NSArray<NSString *> *)listScriptNamesInDirectory:(NSString *)directoryPath;
- (BOOL)saveToDirectory:(NSString *)directoryPath error:(NSError * _Nullable * _Nullable)error;
+ (nullable instancetype)loadNamed:(NSString *)name
                     fromDirectory:(NSString *)directoryPath
                             error:(NSError * _Nullable * _Nullable)error;
+ (BOOL)deleteNamed:(NSString *)name
      fromDirectory:(NSString *)directoryPath
              error:(NSError * _Nullable * _Nullable)error;

@end

/// Tracks ongoing touch pointers, downsamples waypoints, and classifies Tap vs Swipe.
@interface QATouchStrokeTracker : NSObject

@property (nonatomic, assign) double swipeDistanceThreshold;
@property (nonatomic, assign) double minWaypointSpacing;
@property (nonatomic, assign) NSTimeInterval minWaypointInterval;

- (void)resetSession;
- (void)beginTouchID:(id<NSCopying>)touchID atPoint:(QATouchPoint *)point timestamp:(NSTimeInterval)timestamp;
- (void)moveTouchID:(id<NSCopying>)touchID toPoint:(QATouchPoint *)point timestamp:(NSTimeInterval)timestamp;
- (nullable QATouchAction *)endTouchID:(id<NSCopying>)touchID atPoint:(QATouchPoint *)point timestamp:(NSTimeInterval)timestamp;
- (void)cancelTouchID:(id<NSCopying>)touchID;

@end

/// Pure state planner for finite or infinite replay loops and speed scaling.
@interface QATouchLoopPlanner : NSObject

@property (nonatomic, assign, readonly) NSInteger repeatLimit; // 0 = infinite
@property (nonatomic, assign, readonly) double speedMultiplier;
@property (nonatomic, assign, readonly) NSInteger currentIteration; // 1-based when active
@property (nonatomic, assign, readonly) NSUInteger currentStepIndex;
@property (nonatomic, assign, readonly) NSUInteger actionCount;
@property (nonatomic, assign, readonly) BOOL isFinished;

- (instancetype)initWithActionCount:(NSUInteger)actionCount
                        repeatLimit:(NSInteger)repeatLimit
                    speedMultiplier:(double)speedMultiplier NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (NSTimeInterval)scaledDelayForAction:(QATouchAction *)action;
- (NSTimeInterval)scaledDurationForAction:(QATouchAction *)action;
- (BOOL)advanceToNextStep;

@end

NS_ASSUME_NONNULL_END
