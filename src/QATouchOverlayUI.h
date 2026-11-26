#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Transparent passthrough overlay window hosting the floating QA menu and replay markers.
@interface QATouchOverlayWindow : UIWindow
@end

/// Manages the floating QA pill button, expanded control panel, script library, and replay visuals.
@interface QATouchOverlayCoordinator : NSObject

+ (instancetype)shared;
- (void)attachToWindowScene:(UIWindowScene *)windowScene;

@end

NS_ASSUME_NONNULL_END
