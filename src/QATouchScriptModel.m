#import "QATouchScriptModel.h"
#include <math.h>

static NSString * const kQATouchErrorDomain = @"local.qa.touchrecorder";

static double ClampDouble(double val, double minVal, double maxVal) {
    if (val < minVal) return minVal;
    if (val > maxVal) return maxVal;
    return val;
}

#pragma mark - QATouchPoint

@implementation QATouchPoint

+ (instancetype)pointWithX:(double)x y:(double)y {
    return [[self alloc] initWithX:x y:y];
}

- (instancetype)initWithX:(double)x y:(double)y {
    self = [super init];
    if (self) {
        _x = x;
        _y = y;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithX:_x y:_y];
}

- (double)distanceTo:(QATouchPoint *)other {
    if (!other) return 0.0;
    return hypot(_x - other.x, _y - other.y);
}

- (NSDictionary<NSString *, NSNumber *> *)toDictionary {
    return @{
        @"x": @(_x),
        @"y": @(_y)
    };
}

+ (nullable instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSNumber *xVal = dict[@"x"];
    NSNumber *yVal = dict[@"y"];
    if (![xVal isKindOfClass:[NSNumber class]] || ![yVal isKindOfClass:[NSNumber class]]) {
        return nil;
    }
    double x = xVal.doubleValue;
    double y = yVal.doubleValue;
    if (!isfinite(x) || !isfinite(y)) return nil;
    return [[self alloc] initWithX:x y:y];
}

@end

#pragma mark - QATouchAction

@implementation QATouchAction

- (instancetype)initWithType:(QATouchActionType)actionType
                  startPoint:(QATouchPoint *)startPoint
                    endPoint:(QATouchPoint *)endPoint
                   waypoints:(NSArray<QATouchPoint *> *)waypoints
                 delayBefore:(NSTimeInterval)delayBefore
                    duration:(NSTimeInterval)duration {
    self = [super init];
    if (self) {
        _actionType = actionType;
        _startPoint = [startPoint copy];
        _endPoint = [endPoint copy];
        _waypoints = [[NSArray alloc] initWithArray:waypoints copyItems:YES];
        _delayBefore = MAX(0.0, isfinite(delayBefore) ? delayBefore : 0.0);
        _duration = MAX(0.02, isfinite(duration) ? duration : 0.05);
    }
    return self;
}

+ (instancetype)tapAtPoint:(QATouchPoint *)point
               delayBefore:(NSTimeInterval)delayBefore
                  duration:(NSTimeInterval)duration {
    return [[self alloc] initWithType:QATouchActionTypeTap
                           startPoint:point
                             endPoint:point
                            waypoints:@[point]
                          delayBefore:delayBefore
                             duration:duration];
}

+ (instancetype)swipeFromPoint:(QATouchPoint *)startPoint
                       toPoint:(QATouchPoint *)endPoint
                     waypoints:(NSArray<QATouchPoint *> *)waypoints
                   delayBefore:(NSTimeInterval)delayBefore
                      duration:(NSTimeInterval)duration {
    NSArray<QATouchPoint *> *points = waypoints.count >= 2 ? waypoints : @[startPoint, endPoint];
    return [[self alloc] initWithType:QATouchActionTypeSwipe
                           startPoint:startPoint
                             endPoint:endPoint
                            waypoints:points
                          delayBefore:delayBefore
                             duration:MAX(0.08, duration)];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithType:_actionType
                                                startPoint:_startPoint
                                                  endPoint:_endPoint
                                                 waypoints:_waypoints
                                               delayBefore:_delayBefore
                                                  duration:_duration];
}

- (NSString *)humanReadableSummary {
    long delayMs = llround(_delayBefore * 1000.0);
    if (_actionType == QATouchActionTypeTap) {
        return [NSString stringWithFormat:@"Tap (%.0f, %.0f) · +%ldms",
                _startPoint.x, _startPoint.y, delayMs];
    }
    long durMs = llround(_duration * 1000.0);
    return [NSString stringWithFormat:@"Swipe (%.0f,%.0f)→(%.0f,%.0f) · %ldms (+%ldms)",
            _startPoint.x, _startPoint.y, _endPoint.x, _endPoint.y, durMs, delayMs];
}

- (NSDictionary<NSString *, id> *)toDictionary {
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *encodedPoints =
        [NSMutableArray arrayWithCapacity:_waypoints.count];
    for (QATouchPoint *pt in _waypoints) {
        [encodedPoints addObject:[pt toDictionary]];
    }
    return @{
        @"type": (_actionType == QATouchActionTypeTap) ? @"tap" : @"swipe",
        @"start": [_startPoint toDictionary],
        @"end": [_endPoint toDictionary],
        @"waypoints": [encodedPoints copy],
        @"delayBefore": @(_delayBefore),
        @"duration": @(_duration)
    };
}

+ (nullable instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *typeStr = dict[@"type"];
    if (![typeStr isKindOfClass:[NSString class]]) return nil;

    QATouchPoint *startPt = [QATouchPoint fromDictionary:dict[@"start"]];
    QATouchPoint *endPt = [QATouchPoint fromDictionary:dict[@"end"]];
    if (!startPt || !endPt) return nil;

    NSNumber *delayNum = dict[@"delayBefore"];
    NSNumber *durNum = dict[@"duration"];
    NSTimeInterval delayBefore = [delayNum isKindOfClass:[NSNumber class]] ? delayNum.doubleValue : 0.0;
    NSTimeInterval duration = [durNum isKindOfClass:[NSNumber class]] ? durNum.doubleValue : 0.1;

    if ([typeStr isEqualToString:@"tap"]) {
        return [self tapAtPoint:startPt delayBefore:delayBefore duration:duration];
    }
    if ([typeStr isEqualToString:@"swipe"]) {
        NSMutableArray<QATouchPoint *> *waypoints = [NSMutableArray array];
        NSArray *rawWaypoints = dict[@"waypoints"];
        if ([rawWaypoints isKindOfClass:[NSArray class]]) {
            for (id item in rawWaypoints) {
                QATouchPoint *wp = [QATouchPoint fromDictionary:item];
                if (wp) [waypoints addObject:wp];
            }
        }
        return [self swipeFromPoint:startPt
                            toPoint:endPt
                          waypoints:[waypoints copy]
                        delayBefore:delayBefore
                           duration:duration];
    }
    return nil;
}

@end

#pragma mark - QATouchScript

@interface QATouchScript ()
@property (nonatomic, strong) NSMutableArray<QATouchAction *> *mutableActions;
@end

@implementation QATouchScript

- (instancetype)initWithName:(NSString *)name
                     actions:(NSArray<QATouchAction *> *)actions
          createdAtTimestamp:(NSTimeInterval)createdAtTimestamp {
    self = [super init];
    if (self) {
        _name = [name copy];
        _mutableActions = [[NSMutableArray alloc] initWithArray:actions copyItems:YES];
        _createdAtTimestamp = createdAtTimestamp > 0.0 ? createdAtTimestamp : [[NSDate date] timeIntervalSince1970];
    }
    return self;
}

- (instancetype)initWithName:(NSString *)name {
    return [self initWithName:name
                      actions:@[]
           createdAtTimestamp:[[NSDate date] timeIntervalSince1970]];
}

- (id)copyWithZone:(NSZone *)zone {
    return [[[self class] allocWithZone:zone] initWithName:_name
                                                   actions:_mutableActions
                                        createdAtTimestamp:_createdAtTimestamp];
}

- (NSArray<QATouchAction *> *)actions {
    return [_mutableActions copy];
}

- (void)addAction:(QATouchAction *)action {
    if (!action) return;
    [_mutableActions addObject:[action copy]];
}

- (void)removeActionAtIndex:(NSUInteger)index {
    if (index >= _mutableActions.count) return;
    [_mutableActions removeObjectAtIndex:index];
}

- (void)clearActions {
    [_mutableActions removeAllObjects];
}

- (nullable NSData *)toJSONData:(NSError * _Nullable * _Nullable)error {
    NSMutableArray<NSDictionary<NSString *, id> *> *encoded =
        [NSMutableArray arrayWithCapacity:_mutableActions.count];
    for (QATouchAction *action in _mutableActions) {
        [encoded addObject:[action toDictionary]];
    }
    NSDictionary *payload = @{
        @"version": @1,
        @"name": _name ?: @"Untitled",
        @"createdAt": @(_createdAtTimestamp),
        @"actions": [encoded copy]
    };
    return [NSJSONSerialization dataWithJSONObject:payload
                                           options:NSJSONWritingPrettyPrinted
                                             error:error];
}

+ (nullable instancetype)fromJSONData:(NSData *)data error:(NSError * _Nullable * _Nullable)error {
    if (!data || data.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kQATouchErrorDomain
                                         code:1001
                                     userInfo:@{NSLocalizedDescriptionKey: @"Empty script JSON"}];
        }
        return nil;
    }
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:kQATouchErrorDomain
                                         code:1002
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid script root object"}];
        }
        return nil;
    }

    NSDictionary *root = (NSDictionary *)parsed;
    NSString *name = [root[@"name"] isKindOfClass:[NSString class]] ? root[@"name"] : @"Script";
    NSNumber *createdNum = root[@"createdAt"];
    NSTimeInterval created = [createdNum isKindOfClass:[NSNumber class]] ? createdNum.doubleValue : 0.0;

    NSArray *rawActions = root[@"actions"];
    if (![rawActions isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:kQATouchErrorDomain
                                         code:1003
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing actions array"}];
        }
        return nil;
    }

    NSMutableArray<QATouchAction *> *decodedActions = [NSMutableArray arrayWithCapacity:rawActions.count];
    for (id item in rawActions) {
        QATouchAction *action = [QATouchAction fromDictionary:item];
        if (!action) {
            if (error) {
                *error = [NSError errorWithDomain:kQATouchErrorDomain
                                             code:1004
                                         userInfo:@{NSLocalizedDescriptionKey: @"Malformed action entry"}];
            }
            return nil;
        }
        [decodedActions addObject:action];
    }

    return [[self alloc] initWithName:name actions:[decodedActions copy] createdAtTimestamp:created];
}

+ (NSString *)sanitizedFilenameForScriptName:(NSString *)name {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) trimmed = @"qa_script";
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    NSMutableString *clean = [NSMutableString stringWithCapacity:trimmed.length];
    for (NSUInteger i = 0; i < trimmed.length; i++) {
        unichar ch = [trimmed characterAtIndex:i];
        if ([allowed characterIsMember:ch]) {
            [clean appendFormat:@"%C", ch];
        } else {
            [clean appendString:@"_"];
        }
    }
    return [clean stringByAppendingString:@".json"];
}

+ (NSArray<NSString *> *)listScriptNamesInDirectory:(NSString *)directoryPath {
    NSArray<NSString *> *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPath error:nil];
    if (!entries) return @[];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *entry in entries) {
        if ([entry hasSuffix:@".json"]) {
            [names addObject:[entry stringByDeletingPathExtension]];
        }
    }
    return [names sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (BOOL)saveToDirectory:(NSString *)directoryPath error:(NSError * _Nullable * _Nullable)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }
    NSData *jsonData = [self toJSONData:error];
    if (!jsonData) return NO;
    NSString *fileName = [QATouchScript sanitizedFilenameForScriptName:self.name];
    NSString *fullPath = [directoryPath stringByAppendingPathComponent:fileName];
    return [jsonData writeToFile:fullPath options:NSDataWritingAtomic error:error];
}

+ (nullable instancetype)loadNamed:(NSString *)name
                     fromDirectory:(NSString *)directoryPath
                             error:(NSError * _Nullable * _Nullable)error {
    NSString *fileName = [self sanitizedFilenameForScriptName:name];
    NSString *fullPath = [directoryPath stringByAppendingPathComponent:fileName];
    NSData *data = [NSData dataWithContentsOfFile:fullPath options:0 error:error];
    if (!data) return nil;
    return [self fromJSONData:data error:error];
}

+ (BOOL)deleteNamed:(NSString *)name
      fromDirectory:(NSString *)directoryPath
              error:(NSError * _Nullable * _Nullable)error {
    NSString *fileName = [self sanitizedFilenameForScriptName:name];
    NSString *fullPath = [directoryPath stringByAppendingPathComponent:fileName];
    return [[NSFileManager defaultManager] removeItemAtPath:fullPath error:error];
}

@end

#pragma mark - QATouchStrokeTracker

@interface QAActiveStrokeState : NSObject
@property (nonatomic, strong) QATouchPoint *startPoint;
@property (nonatomic, strong) QATouchPoint *lastRecordedPoint;
@property (nonatomic, strong) NSMutableArray<QATouchPoint *> *waypoints;
@property (nonatomic, assign) NSTimeInterval startTimestamp;
@property (nonatomic, assign) NSTimeInterval lastWaypointTimestamp;
@property (nonatomic, assign) NSTimeInterval delayBefore;
@property (nonatomic, assign) double maxDisplacementFromStart;
@end

@implementation QAActiveStrokeState
@end

@interface QATouchStrokeTracker ()
@property (nonatomic, strong) NSMutableDictionary<id<NSCopying>, QAActiveStrokeState *> *activeStrokes;
@property (nonatomic, assign) BOOL hasLastActionEndTimestamp;
@property (nonatomic, assign) NSTimeInterval lastActionEndTimestamp;
@end

@implementation QATouchStrokeTracker

- (instancetype)init {
    self = [super init];
    if (self) {
        _swipeDistanceThreshold = 12.0;
        _minWaypointSpacing = 4.0;
        _minWaypointInterval = 0.016;
        _activeStrokes = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)resetSession {
    [_activeStrokes removeAllObjects];
    _hasLastActionEndTimestamp = NO;
    _lastActionEndTimestamp = 0.0;
}

- (void)beginTouchID:(id<NSCopying>)touchID atPoint:(QATouchPoint *)point timestamp:(NSTimeInterval)timestamp {
    if (!touchID || !point) return;
    QAActiveStrokeState *state = [[QAActiveStrokeState alloc] init];
    state.startPoint = point;
    state.lastRecordedPoint = point;
    state.waypoints = [NSMutableArray arrayWithObject:point];
    state.startTimestamp = timestamp;
    state.lastWaypointTimestamp = timestamp;
    state.delayBefore = _hasLastActionEndTimestamp ? MAX(0.0, timestamp - _lastActionEndTimestamp) : 0.0;
    state.maxDisplacementFromStart = 0.0;
    _activeStrokes[touchID] = state;
}

- (void)moveTouchID:(id<NSCopying>)touchID toPoint:(QATouchPoint *)point timestamp:(NSTimeInterval)timestamp {
    if (!touchID || !point) return;
    QAActiveStrokeState *state = _activeStrokes[touchID];
    if (!state) return;

    double distFromStart = [point distanceTo:state.startPoint];
    if (distFromStart > state.maxDisplacementFromStart) {
        state.maxDisplacementFromStart = distFromStart;
    }

    double spacing = [point distanceTo:state.lastRecordedPoint];
    NSTimeInterval dt = timestamp - state.lastWaypointTimestamp;
    if (spacing >= _minWaypointSpacing || dt >= _minWaypointInterval) {
        [state.waypoints addObject:point];
        state.lastRecordedPoint = point;
        state.lastWaypointTimestamp = timestamp;
    }
}

- (nullable QATouchAction *)endTouchID:(id<NSCopying>)touchID atPoint:(QATouchPoint *)point timestamp:(NSTimeInterval)timestamp {
    if (!touchID || !point) return nil;
    QAActiveStrokeState *state = _activeStrokes[touchID];
    [_activeStrokes removeObjectForKey:touchID];
    if (!state) return nil;

    double distFromStart = [point distanceTo:state.startPoint];
    if (distFromStart > state.maxDisplacementFromStart) {
        state.maxDisplacementFromStart = distFromStart;
    }
    if ([point distanceTo:state.lastRecordedPoint] > 0.5) {
        [state.waypoints addObject:point];
    }

    NSTimeInterval duration = MAX(0.02, timestamp - state.startTimestamp);
    _hasLastActionEndTimestamp = YES;
    _lastActionEndTimestamp = timestamp;

    if (state.maxDisplacementFromStart >= _swipeDistanceThreshold) {
        return [QATouchAction swipeFromPoint:state.startPoint
                                     toPoint:point
                                   waypoints:[state.waypoints copy]
                                 delayBefore:state.delayBefore
                                    duration:duration];
    }

    return [QATouchAction tapAtPoint:point
                         delayBefore:state.delayBefore
                            duration:duration];
}

- (void)cancelTouchID:(id<NSCopying>)touchID {
    if (!touchID) return;
    [_activeStrokes removeObjectForKey:touchID];
}

@end

#pragma mark - QATouchLoopPlanner

@implementation QATouchLoopPlanner

- (instancetype)initWithActionCount:(NSUInteger)actionCount
                        repeatLimit:(NSInteger)repeatLimit
                    speedMultiplier:(double)speedMultiplier {
    self = [super init];
    if (self) {
        _actionCount = actionCount;
        _repeatLimit = MAX(0, repeatLimit);
        _speedMultiplier = ClampDouble(isfinite(speedMultiplier) ? speedMultiplier : 1.0, 0.25, 4.0);
        _currentIteration = (actionCount > 0) ? 1 : 0;
        _currentStepIndex = 0;
        _isFinished = (actionCount == 0);
    }
    return self;
}

- (NSTimeInterval)scaledDelayForAction:(QATouchAction *)action {
    if (!action) return 0.0;
    return MAX(0.0, action.delayBefore / _speedMultiplier);
}

- (NSTimeInterval)scaledDurationForAction:(QATouchAction *)action {
    if (!action) return 0.05;
    return MAX(0.02, action.duration / _speedMultiplier);
}

- (BOOL)advanceToNextStep {
    if (_isFinished || _actionCount == 0) {
        _isFinished = YES;
        return NO;
    }
    if (_currentStepIndex + 1 < _actionCount) {
        _currentStepIndex += 1;
        return YES;
    }
    if (_repeatLimit == 0 || _currentIteration < _repeatLimit) {
        _currentIteration += 1;
        _currentStepIndex = 0;
        return YES;
    }
    _isFinished = YES;
    return NO;
}

@end
