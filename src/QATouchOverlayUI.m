#import "QATouchOverlayUI.h"
#import "QATouchRecorderEngine.h"
#import <QuartzCore/QuartzCore.h>

#pragma mark - QATouchOverlayWindow

@implementation QATouchOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}

@end

#pragma mark - QATouchOverlayViewController

@interface QATouchOverlayViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, QATouchRecorderEngineDelegate>

@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UIView *panelView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UIButton *savedListToggleButton;
@property (nonatomic, strong) UISegmentedControl *repeatControl;
@property (nonatomic, strong) UISegmentedControl *speedControl;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) BOOL showingSavedScripts;
@property (nonatomic, copy) NSArray<NSString *> *savedNames;
@property (nonatomic, strong) NSArray<NSNumber *> *repeatValues;
@property (nonatomic, strong) NSArray<NSNumber *> *speedValues;

@end

@implementation QATouchOverlayViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];

    _repeatValues = @[@1, @3, @5, @10, @0];
    _speedValues = @[@0.5, @1.0, @1.5, @2.0];
    _savedNames = @[];

    [self setupFloatingButton];
    [self setupPanelView];

    [QATouchRecorderEngine shared].delegate = self;
    [self refreshUIState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self clampFloatingButtonInsideSafeArea];
    [self layoutPanelCentered];
}

#pragma mark - Floating Pill Button

- (void)setupFloatingButton {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(16.0, 120.0, 56.0, 36.0);
    btn.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:0.90];
    btn.layer.cornerRadius = 18.0;
    btn.layer.borderWidth = 1.5;
    btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOpacity = 0.35;
    btn.layer.shadowRadius = 6.0;
    btn.layer.shadowOffset = CGSizeMake(0, 2);
    [btn setTitle:@"QA" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightBold];

    [btn addTarget:self action:@selector(togglePanelTapped) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFloatingPan:)];
    [btn addGestureRecognizer:pan];

    [self.view addSubview:btn];
    self.floatingButton = btn;
}

- (void)handleFloatingPan:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self.view];
    [pan setTranslation:CGPointZero inView:self.view];

    CGPoint center = self.floatingButton.center;
    center.x += delta.x;
    center.y += delta.y;
    self.floatingButton.center = center;
    [self clampFloatingButtonInsideSafeArea];
}

- (void)clampFloatingButtonInsideSafeArea {
    UIEdgeInsets safe = self.view.safeAreaInsets;
    CGRect bounds = self.view.bounds;
    if (CGRectIsEmpty(bounds)) return;

    CGFloat halfW = self.floatingButton.bounds.size.width * 0.5;
    CGFloat halfH = self.floatingButton.bounds.size.height * 0.5;

    CGFloat minX = safe.left + 8.0 + halfW;
    CGFloat maxX = MAX(minX, bounds.size.width - safe.right - 8.0 - halfW);
    CGFloat minY = safe.top + 8.0 + halfH;
    CGFloat maxY = MAX(minY, bounds.size.height - safe.bottom - 8.0 - halfH);

    CGPoint c = self.floatingButton.center;
    c.x = MIN(MAX(c.x, minX), maxX);
    c.y = MIN(MAX(c.y, minY), maxY);
    self.floatingButton.center = c;
}

- (void)togglePanelTapped {
    BOOL show = self.panelView.hidden;
    if (show) {
        self.savedNames = [[QATouchRecorderEngine shared] savedScriptNames];
        [self.tableView reloadData];
    }
    self.panelView.hidden = !show;
}

#pragma mark - Control Panel

- (UIButton *)makeActionButtonWithTitle:(NSString *)title color:(UIColor *)color action:(SEL)sel {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 8.0;
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    [btn addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (void)setupPanelView {
    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 326.0, 420.0)];
    panel.backgroundColor = [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:0.94];
    panel.layer.cornerRadius = 16.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    panel.layer.shadowColor = [UIColor blackColor].CGColor;
    panel.layer.shadowOpacity = 0.45;
    panel.layer.shadowRadius = 12.0;
    panel.clipsToBounds = YES;
    panel.hidden = YES;

    UILabel *titleLbl = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 12.0, 230.0, 22.0)];
    titleLbl.text = @"QA Touch Recorder";
    titleLbl.textColor = [UIColor whiteColor];
    titleLbl.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightBold];
    [panel addSubview:titleLbl];

    UIButton *closeBtn = [self makeActionButtonWithTitle:@"Đóng"
                                                   color:[UIColor colorWithWhite:1.0 alpha:0.15]
                                                  action:@selector(togglePanelTapped)];
    closeBtn.frame = CGRectMake(258.0, 10.0, 56.0, 26.0);
    [panel addSubview:closeBtn];

    UILabel *statusLbl = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 38.0, 298.0, 18.0)];
    statusLbl.textColor = [UIColor colorWithRed:0.65 green:0.78 blue:0.98 alpha:1.0];
    statusLbl.font = [UIFont monospacedSystemFontOfSize:11.5 weight:UIFontWeightMedium];
    [panel addSubview:statusLbl];
    self.statusLabel = statusLbl;

    self.recordButton = [self makeActionButtonWithTitle:@"Ghi"
                                                  color:[UIColor colorWithRed:0.85 green:0.22 blue:0.24 alpha:1.0]
                                                 action:@selector(recordButtonTapped)];
    self.recordButton.frame = CGRectMake(14.0, 64.0, 94.0, 34.0);
    [panel addSubview:self.recordButton];

    self.playButton = [self makeActionButtonWithTitle:@"Phát"
                                                color:[UIColor colorWithRed:0.16 green:0.62 blue:0.38 alpha:1.0]
                                               action:@selector(playButtonTapped)];
    self.playButton.frame = CGRectMake(116.0, 64.0, 94.0, 34.0);
    [panel addSubview:self.playButton];

    self.clearButton = [self makeActionButtonWithTitle:@"Xóa"
                                                 color:[UIColor colorWithWhite:1.0 alpha:0.18]
                                                action:@selector(clearButtonTapped)];
    self.clearButton.frame = CGRectMake(218.0, 64.0, 94.0, 34.0);
    [panel addSubview:self.clearButton];

    UILabel *repeatLbl = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 106.0, 52.0, 26.0)];
    repeatLbl.text = @"Lặp:";
    repeatLbl.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    repeatLbl.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [panel addSubview:repeatLbl];

    self.repeatControl = [[UISegmentedControl alloc] initWithItems:@[@"1x", @"3x", @"5x", @"10x", @"∞"]];
    self.repeatControl.frame = CGRectMake(68.0, 106.0, 244.0, 26.0);
    self.repeatControl.selectedSegmentIndex = 0;
    [self.repeatControl addTarget:self action:@selector(repeatChanged) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:self.repeatControl];

    UILabel *speedLbl = [[UILabel alloc] initWithFrame:CGRectMake(14.0, 138.0, 52.0, 26.0)];
    speedLbl.text = @"Tốc độ:";
    speedLbl.textColor = [UIColor colorWithWhite:0.85 alpha:1.0];
    speedLbl.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    [panel addSubview:speedLbl];

    self.speedControl = [[UISegmentedControl alloc] initWithItems:@[@"0.5x", @"1x", @"1.5x", @"2x"]];
    self.speedControl.frame = CGRectMake(68.0, 138.0, 244.0, 26.0);
    self.speedControl.selectedSegmentIndex = 1;
    [self.speedControl addTarget:self action:@selector(speedChanged) forControlEvents:UIControlEventValueChanged];
    [panel addSubview:self.speedControl];

    self.saveButton = [self makeActionButtonWithTitle:@"Lưu JSON"
                                                color:[UIColor colorWithRed:0.20 green:0.46 blue:0.85 alpha:1.0]
                                               action:@selector(saveScriptTapped)];
    self.saveButton.frame = CGRectMake(14.0, 172.0, 145.0, 30.0);
    [panel addSubview:self.saveButton];

    self.savedListToggleButton = [self makeActionButtonWithTitle:@"Script đã lưu"
                                                           color:[UIColor colorWithWhite:1.0 alpha:0.16]
                                                          action:@selector(toggleSavedListTapped)];
    self.savedListToggleButton.frame = CGRectMake(167.0, 172.0, 145.0, 30.0);
    [panel addSubview:self.savedListToggleButton];

    UITableView *tv = [[UITableView alloc] initWithFrame:CGRectMake(14.0, 210.0, 298.0, 196.0)
                                                   style:UITableViewStylePlain];
    tv.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    tv.layer.cornerRadius = 10.0;
    tv.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    tv.dataSource = self;
    tv.delegate = self;
    tv.rowHeight = 36.0;
    [panel addSubview:tv];
    self.tableView = tv;

    [self.view addSubview:panel];
    self.panelView = panel;
}

- (void)layoutPanelCentered {
    CGRect bounds = self.view.bounds;
    UIEdgeInsets safe = self.view.safeAreaInsets;
    if (CGRectIsEmpty(bounds)) return;

    CGFloat usableW = bounds.size.width - safe.left - safe.right - 24.0;
    CGFloat usableH = bounds.size.height - safe.top - safe.bottom - 24.0;
    CGFloat w = MIN(326.0, usableW);
    CGFloat h = MIN(420.0, usableH);

    CGFloat originX = safe.left + (bounds.size.width - safe.left - safe.right - w) * 0.5;
    CGFloat originY = safe.top + (bounds.size.height - safe.top - safe.bottom - h) * 0.5;
    self.panelView.frame = CGRectMake(originX, originY, w, h);
    self.tableView.frame = CGRectMake(14.0, 210.0, MAX(120.0, w - 28.0), MAX(80.0, h - 224.0));
}

#pragma mark - Button Actions

- (void)recordButtonTapped {
    QATouchRecorderEngine *engine = [QATouchRecorderEngine shared];
    if (engine.state == QARecorderStateRecording) {
        [engine stopRecording];
    } else {
        self.panelView.hidden = YES; // Collapse panel so user can tap/swipe the app directly.
        [engine startRecording];
    }
    [self refreshUIState];
}

- (void)playButtonTapped {
    QATouchRecorderEngine *engine = [QATouchRecorderEngine shared];
    if (engine.state == QARecorderStatePlaying) {
        [engine stopPlayback];
    } else {
        if (engine.currentScript.actions.count == 0) return;
        self.panelView.hidden = YES;
        [engine startPlayback];
    }
    [self refreshUIState];
}

- (void)clearButtonTapped {
    [[QATouchRecorderEngine shared] clearCurrentScript];
    [self refreshUIState];
}

- (void)repeatChanged {
    NSInteger idx = self.repeatControl.selectedSegmentIndex;
    if (idx >= 0 && idx < (NSInteger)self.repeatValues.count) {
        [QATouchRecorderEngine shared].repeatLimit = self.repeatValues[idx].integerValue;
    }
}

- (void)speedChanged {
    NSInteger idx = self.speedControl.selectedSegmentIndex;
    if (idx >= 0 && idx < (NSInteger)self.speedValues.count) {
        [QATouchRecorderEngine shared].speedMultiplier = self.speedValues[idx].doubleValue;
    }
}

- (void)saveScriptTapped {
    QATouchRecorderEngine *engine = [QATouchRecorderEngine shared];
    if (engine.currentScript.actions.count == 0) {
        self.statusLabel.text = @"Chưa có bước nào để lưu";
        return;
    }
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd_HHmmss";
    NSString *name = [NSString stringWithFormat:@"QA_%@", [fmt stringFromDate:[NSDate date]]];

    NSError *err = nil;
    if ([engine saveCurrentScriptWithName:name error:&err]) {
        self.savedNames = [engine savedScriptNames];
        self.statusLabel.text = [NSString stringWithFormat:@"Đã lưu: %@", name];
        if (self.showingSavedScripts) [self.tableView reloadData];
    } else {
        self.statusLabel.text = err.localizedDescription ?: @"Lỗi lưu JSON";
    }
}

- (void)toggleSavedListTapped {
    self.showingSavedScripts = !self.showingSavedScripts;
    self.savedNames = [[QATouchRecorderEngine shared] savedScriptNames];
    [self.savedListToggleButton setTitle:(self.showingSavedScripts ? @"Xem các bước" : @"Script đã lưu")
                                forState:UIControlStateNormal];
    [self.tableView reloadData];
}

#pragma mark - State Refresh

- (void)refreshUIState {
    QATouchRecorderEngine *engine = [QATouchRecorderEngine shared];
    NSUInteger count = engine.currentScript.actions.count;

    switch (engine.state) {
        case QARecorderStateIdle:
            [self.floatingButton setTitle:(count > 0 ? [NSString stringWithFormat:@"QA %lu", (unsigned long)count] : @"QA")
                                 forState:UIControlStateNormal];
            self.floatingButton.backgroundColor = [UIColor colorWithRed:0.10 green:0.12 blue:0.16 alpha:0.90];
            [self.recordButton setTitle:@"Ghi" forState:UIControlStateNormal];
            [self.playButton setTitle:@"Phát" forState:UIControlStateNormal];
            self.statusLabel.text = [NSString stringWithFormat:@"Sẵn sàng · %lu bước", (unsigned long)count];
            break;

        case QARecorderStateRecording:
            [self.floatingButton setTitle:[NSString stringWithFormat:@"REC %lu", (unsigned long)count]
                                 forState:UIControlStateNormal];
            self.floatingButton.backgroundColor = [UIColor colorWithRed:0.82 green:0.18 blue:0.20 alpha:0.94];
            [self.recordButton setTitle:@"Dừng ghi" forState:UIControlStateNormal];
            [self.playButton setTitle:@"Phát" forState:UIControlStateNormal];
            self.statusLabel.text = [NSString stringWithFormat:@"Đang ghi · %lu bước", (unsigned long)count];
            break;

        case QARecorderStatePlaying:
            [self.floatingButton setTitle:@"PLAY" forState:UIControlStateNormal];
            self.floatingButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.60 blue:0.35 alpha:0.94];
            [self.recordButton setTitle:@"Ghi" forState:UIControlStateNormal];
            [self.playButton setTitle:@"Dừng phát" forState:UIControlStateNormal];
            break;
    }

    [self.tableView reloadData];
}

#pragma mark - QATouchRecorderEngineDelegate

- (void)touchRecorderDidUpdateState:(__unused QARecorderState)state {
    [self refreshUIState];
}

- (void)touchRecorderDidChangeScript:(__unused QATouchScript *)script {
    [self refreshUIState];
}

- (void)touchRecorderDidAdvanceIteration:(NSInteger)iteration
                           repeatLimit:(NSInteger)repeatLimit
                             stepIndex:(NSUInteger)stepIndex
                             stepCount:(NSUInteger)stepCount {
    NSString *limitStr = (repeatLimit == 0) ? @"∞" : [NSString stringWithFormat:@"%ld", (long)repeatLimit];
    NSString *badge = [NSString stringWithFormat:@"%ld/%@", (long)iteration, limitStr];
    [self.floatingButton setTitle:badge forState:UIControlStateNormal];
    self.statusLabel.text = [NSString stringWithFormat:@"Đang phát lượt %@ · Bước %lu/%lu",
                             badge, (unsigned long)(stepIndex + 1), (unsigned long)stepCount];
}

- (CGPoint)convertScenePointToOverlayView:(CGPoint)scenePoint {
    UIWindow *overlayWin = self.view.window;
    if (!overlayWin) return scenePoint;
    CGPoint winPt = [overlayWin convertPoint:scenePoint fromWindow:nil];
    return [self.view convertPoint:winPt fromView:overlayWin];
}

- (void)touchRecorderShowVisualTapAtPoint:(CGPoint)point {
    CGPoint localPt = [self convertScenePointToOverlayView:point];
    UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 28.0, 28.0)];
    dot.center = localPt;
    dot.userInteractionEnabled = NO;
    dot.backgroundColor = [UIColor colorWithRed:0.22 green:0.78 blue:0.46 alpha:0.35];
    dot.layer.cornerRadius = 14.0;
    dot.layer.borderWidth = 2.0;
    dot.layer.borderColor = [UIColor colorWithRed:0.22 green:0.92 blue:0.54 alpha:0.95].CGColor;
    [self.view addSubview:dot];

    [UIView animateWithDuration:0.28 animations:^{
        dot.transform = CGAffineTransformMakeScale(1.6, 1.6);
        dot.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        [dot removeFromSuperview];
    }];
}

- (void)touchRecorderShowVisualSwipeFromPoint:(CGPoint)startPoint
                                    toPoint:(CGPoint)endPoint
                                   duration:(NSTimeInterval)duration {
    CGPoint p1 = [self convertScenePointToOverlayView:startPoint];
    CGPoint p2 = [self convertScenePointToOverlayView:endPoint];

    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:p1];
    [path addLineToPoint:p2];

    CAShapeLayer *line = [CAShapeLayer layer];
    line.path = path.CGPath;
    line.strokeColor = [UIColor colorWithRed:0.30 green:0.68 blue:1.0 alpha:0.85].CGColor;
    line.lineWidth = 3.0;
    line.lineCap = kCALineCapRound;
    line.fillColor = [UIColor clearColor].CGColor;
    [self.view.layer addSublayer:line];

    UIView *puck = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 18.0, 18.0)];
    puck.center = p1;
    puck.userInteractionEnabled = NO;
    puck.backgroundColor = [UIColor colorWithRed:0.30 green:0.68 blue:1.0 alpha:0.90];
    puck.layer.cornerRadius = 9.0;
    [self.view addSubview:puck];

    [UIView animateWithDuration:MAX(0.20, duration) animations:^{
        puck.center = p2;
    } completion:^(__unused BOOL finished) {
        [puck removeFromSuperview];
        [line removeFromSuperlayer];
    }];
}

#pragma mark - UITableViewDataSource & Delegate

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    if (self.showingSavedScripts) {
        return (NSInteger)self.savedNames.count;
    }
    return (NSInteger)[QATouchRecorderEngine shared].currentScript.actions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"QACell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"QACell"];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    }

    if (self.showingSavedScripts) {
        NSString *name = self.savedNames[(NSUInteger)indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"Tải: %@", name];
    } else {
        QATouchAction *action = [QATouchRecorderEngine shared].currentScript.actions[(NSUInteger)indexPath.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@",
                               (long)(indexPath.row + 1), [action humanReadableSummary]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.showingSavedScripts) return;

    NSString *name = self.savedNames[(NSUInteger)indexPath.row];
    NSError *err = nil;
    if ([[QATouchRecorderEngine shared] loadScriptNamed:name error:&err]) {
        self.showingSavedScripts = NO;
        [self.savedListToggleButton setTitle:@"Script đã lưu" forState:UIControlStateNormal];
        [self refreshUIState];
    } else {
        self.statusLabel.text = err.localizedDescription ?: @"Lỗi tải script";
    }
}

- (void)tableView:(__unused UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    QATouchRecorderEngine *engine = [QATouchRecorderEngine shared];
    if (self.showingSavedScripts) {
        NSString *name = self.savedNames[(NSUInteger)indexPath.row];
        [engine deleteScriptNamed:name error:nil];
        self.savedNames = [engine savedScriptNames];
        [self.tableView reloadData];
    } else {
        [engine removeActionAtIndex:(NSUInteger)indexPath.row];
    }
}

@end

#pragma mark - QATouchOverlayCoordinator

@interface QATouchOverlayCoordinator ()
@property (nonatomic, strong, nullable) QATouchOverlayWindow *overlayWindow;
@end

@implementation QATouchOverlayCoordinator

+ (instancetype)shared {
    static QATouchOverlayCoordinator *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[QATouchOverlayCoordinator alloc] init];
    });
    return instance;
}

- (void)attachToWindowScene:(UIWindowScene *)windowScene {
    if (!windowScene || self.overlayWindow) return;

    QATouchOverlayWindow *win = [[QATouchOverlayWindow alloc] initWithWindowScene:windowScene];
    win.windowLevel = UIWindowLevelAlert + 100.0;
    win.backgroundColor = [UIColor clearColor];
    win.rootViewController = [[QATouchOverlayViewController alloc] init];
    win.hidden = NO;
    self.overlayWindow = win;
}

@end
