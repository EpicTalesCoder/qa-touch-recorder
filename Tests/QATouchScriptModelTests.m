#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdlib.h>
#import "QATouchScriptModel.h"

#define QA_CHECK(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "FAIL at %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        exit(1); \
    } \
} while (0)

static void TestTapClassification(void) {
    QATouchStrokeTracker *tracker = [[QATouchStrokeTracker alloc] init];
    [tracker beginTouchID:@"t1" atPoint:[QATouchPoint pointWithX:120.0 y:300.0] timestamp:10.0];
    [tracker moveTouchID:@"t1" toPoint:[QATouchPoint pointWithX:123.0 y:304.0] timestamp:10.03];
    QATouchAction *action = [tracker endTouchID:@"t1"
                                       atPoint:[QATouchPoint pointWithX:122.0 y:302.0]
                                     timestamp:10.08];
    QA_CHECK(action != nil);
    QA_CHECK(action.actionType == QATouchActionTypeTap);
    QA_CHECK(action.delayBefore == 0.0);
    QA_CHECK(action.duration >= 0.07 && action.duration <= 0.09);
}

static void TestSwipeClassificationAndDelay(void) {
    QATouchStrokeTracker *tracker = [[QATouchStrokeTracker alloc] init];
    [tracker beginTouchID:@"t1" atPoint:[QATouchPoint pointWithX:200.0 y:600.0] timestamp:1.0];
    QATouchAction *first = [tracker endTouchID:@"t1"
                                      atPoint:[QATouchPoint pointWithX:201.0 y:601.0]
                                    timestamp:1.05];
    QA_CHECK(first.actionType == QATouchActionTypeTap);

    [tracker beginTouchID:@"t2" atPoint:[QATouchPoint pointWithX:200.0 y:600.0] timestamp:1.55];
    [tracker moveTouchID:@"t2" toPoint:[QATouchPoint pointWithX:200.0 y:500.0] timestamp:1.65];
    [tracker moveTouchID:@"t2" toPoint:[QATouchPoint pointWithX:200.0 y:400.0] timestamp:1.75];
    QATouchAction *second = [tracker endTouchID:@"t2"
                                       atPoint:[QATouchPoint pointWithX:200.0 y:300.0]
                                     timestamp:1.85];
    QA_CHECK(second != nil);
    QA_CHECK(second.actionType == QATouchActionTypeSwipe);
    QA_CHECK(second.delayBefore >= 0.49 && second.delayBefore <= 0.51);
    QA_CHECK(second.waypoints.count >= 3);
    QA_CHECK(second.startPoint.y == 600.0);
    QA_CHECK(second.endPoint.y == 300.0);
}

static void TestScriptJSONAndDiskPersistence(void) {
    QATouchScript *script = [[QATouchScript alloc] initWithName:@"QA Smoke Test!"];
    [script addAction:[QATouchAction tapAtPoint:[QATouchPoint pointWithX:50.0 y:80.0]
                                    delayBefore:0.25
                                       duration:0.06]];
    [script addAction:[QATouchAction swipeFromPoint:[QATouchPoint pointWithX:100.0 y:500.0]
                                            toPoint:[QATouchPoint pointWithX:100.0 y:200.0]
                                          waypoints:@[
                                              [QATouchPoint pointWithX:100.0 y:500.0],
                                              [QATouchPoint pointWithX:100.0 y:350.0],
                                              [QATouchPoint pointWithX:100.0 y:200.0]
                                          ]
                                        delayBefore:0.40
                                           duration:0.30]];

    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [[NSUUID UUID] UUIDString]];
    NSError *err = nil;
    BOOL saved = [script saveToDirectory:tempDir error:&err];
    QA_CHECK(saved && err == nil);

    NSArray<NSString *> *listed = [QATouchScript listScriptNamesInDirectory:tempDir];
    QA_CHECK(listed.count == 1);
    QA_CHECK([listed.firstObject isEqualToString:@"QA_Smoke_Test_"]);

    QATouchScript *loaded = [QATouchScript loadNamed:@"QA Smoke Test!" fromDirectory:tempDir error:&err];
    QA_CHECK(loaded != nil && err == nil);
    QA_CHECK(loaded.actions.count == 2);
    QA_CHECK(loaded.actions[0].actionType == QATouchActionTypeTap);
    QA_CHECK(loaded.actions[1].actionType == QATouchActionTypeSwipe);
    QA_CHECK(loaded.actions[1].waypoints.count == 3);

    BOOL deleted = [QATouchScript deleteNamed:@"QA Smoke Test!" fromDirectory:tempDir error:&err];
    QA_CHECK(deleted && err == nil);
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];

    NSError *badErr = nil;
    QATouchScript *bad = [QATouchScript fromJSONData:[NSData data] error:&badErr];
    QA_CHECK(bad == nil && badErr != nil);
}

static void TestLoopPlannerFiniteAndInfinite(void) {
    QATouchLoopPlanner *finite = [[QATouchLoopPlanner alloc] initWithActionCount:2
                                                                     repeatLimit:2
                                                                 speedMultiplier:2.0];
    QA_CHECK(!finite.isFinished);
    QA_CHECK(finite.currentIteration == 1);
    QA_CHECK(finite.currentStepIndex == 0);

    QATouchAction *sample = [QATouchAction tapAtPoint:[QATouchPoint pointWithX:10 y:20]
                                          delayBefore:1.0
                                             duration:0.2];
    QA_CHECK([finite scaledDelayForAction:sample] == 0.5);
    QA_CHECK([finite scaledDurationForAction:sample] == 0.1);

    QA_CHECK([finite advanceToNextStep]);
    QA_CHECK(finite.currentIteration == 1 && finite.currentStepIndex == 1);

    QA_CHECK([finite advanceToNextStep]);
    QA_CHECK(finite.currentIteration == 2 && finite.currentStepIndex == 0);

    QA_CHECK([finite advanceToNextStep]);
    QA_CHECK(finite.currentIteration == 2 && finite.currentStepIndex == 1);

    QA_CHECK(![finite advanceToNextStep]);
    QA_CHECK(finite.isFinished);

    QATouchLoopPlanner *infinite = [[QATouchLoopPlanner alloc] initWithActionCount:1
                                                                       repeatLimit:0
                                                                   speedMultiplier:1.0];
    for (int i = 0; i < 10; i++) {
        QA_CHECK([infinite advanceToNextStep]);
        QA_CHECK(!infinite.isFinished);
    }
    QA_CHECK(infinite.currentIteration == 11);
}

int main(void) {
    @autoreleasepool {
        TestTapClassification();
        TestSwipeClassificationAndDelay();
        TestScriptJSONAndDiskPersistence();
        TestLoopPlannerFiniteAndInfinite();
        printf("PASS: All 4 QATouchScriptModel test suites passed.\n");
    }
    return 0;
}
