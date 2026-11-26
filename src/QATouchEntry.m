#import <UIKit/UIKit.h>
#import "QATouchOverlayUI.h"

static dispatch_once_t sQAInitOnce;

static UIWindowScene * _Nullable FindForegroundWindowScene(void) {
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

static void StartQATouchOverlayOnce(void) {
    dispatch_once(&sQAInitOnce, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIWindowScene *scene = FindForegroundWindowScene();
            if (scene) {
                [[QATouchOverlayCoordinator shared] attachToWindowScene:scene];
            }
        });
    });
}

__attribute__((constructor))
static void QATouchRecorderEntry(void) {
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserverForName:UIApplicationDidFinishLaunchingNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification *note) {
        StartQATouchOverlayOnce();
    }];
    [nc addObserverForName:UISceneDidActivateNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(__unused NSNotification *note) {
        StartQATouchOverlayOnce();
    }];
}
