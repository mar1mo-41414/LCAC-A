#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "ACIl2Cpp.h"
#import "ACDebugLog.h"

// 自動クリアの ON/OFF と速度を切り替える小さなフローティングボタン +
// メインスレッドの CADisplayLink で盤面を 1 本ずつ進めるドライバ。
//
// Unity (iOS) はメインスレッドの CADisplayLink でフレームを回しているので、
// こちらの CADisplayLink も同じスレッドで「フレームとフレームの間」に走る。
// よって ECS (Entitas) のエンティティを触ってもゲーム側と競合しない。

static NSString *const kEnabledKey = @"LCAC.enabled";
static NSString *const kSpeedKey = @"LCAC.speedIndex";

typedef struct {
    const char *label;
    CFTimeInterval interval; // 1 本積むごとの最小間隔 (秒)
} ACSpeed;

static const ACSpeed kSpeeds[] = {
    {"x1", 0.25},
    {"x2", 0.12},
    {"x4", 0.05},
    {"MAX", 0.0},
};
static const NSInteger kSpeedCount = sizeof(kSpeeds) / sizeof(kSpeeds[0]);

@interface ACController : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger speedIndex;
@property (nonatomic) CFTimeInterval lastStep;
@property (nonatomic) NSUInteger removedCount;
@end

@implementation ACController

+ (instancetype)shared {
    static ACController *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [ACController new]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        _enabled = [d objectForKey:kEnabledKey] ? [d boolForKey:kEnabledKey] : YES;
        _speedIndex = MIN(MAX([d integerForKey:kSpeedKey], 0), kSpeedCount - 1);
    }
    return self;
}

- (void)start {
    if (self.link) return;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    ACLog(@"display link started (enabled=%d speed=%s)", self.enabled, kSpeeds[self.speedIndex].label);
}

- (void)tick:(CADisplayLink *)link {
    [self ensureButton];
    if (!self.enabled) return;

    CFTimeInterval now = CACurrentMediaTime();
    if (now - self.lastStep < kSpeeds[self.speedIndex].interval) return;

    if (ACIl2CppStep()) {
        self.lastStep = now;
        self.removedCount++;
    }
}

#pragma mark - Floating button

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (UIWindow *)hostWindow {
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow && w.rootViewController) return w;
    }
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.rootViewController) return w;
    }
    return nil;
}
#pragma clang diagnostic pop

- (void)ensureButton {
    UIWindow *window = [self hostWindow];
    if (!window) return;

    if (!self.button) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.titleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];
        b.layer.cornerRadius = 18;
        b.layer.borderWidth = 1;
        b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        [b addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];

        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        lp.minimumPressDuration = 0.5;
        [b addGestureRecognizer:lp];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        [b addGestureRecognizer:pan];

        self.button = b;
        [self refreshButton];

        // 左下 (右下にはゲームの # ボタンがあるため)。
        CGRect bounds = window.bounds;
        UIEdgeInsets safe = window.safeAreaInsets;
        CGSize size = b.bounds.size;
        b.center = CGPointMake(safe.left + 16 + size.width / 2,
                               bounds.size.height - safe.bottom - 40 - size.height / 2);
        ACLog(@"button created on %@", window);
    }

    if (self.button.superview != window) {
        [window addSubview:self.button];
    } else if (window.subviews.lastObject != self.button) {
        [window bringSubviewToFront:self.button];
    }
}

- (void)refreshButton {
    NSString *title = self.enabled
        ? [NSString stringWithFormat:@"AUTO ON %s", kSpeeds[self.speedIndex].label]
        : @"AUTO OFF";
    [self.button setTitle:title forState:UIControlStateNormal];
    self.button.backgroundColor = self.enabled
        ? [UIColor colorWithRed:0.33 green:0.45 blue:0.98 alpha:0.9]
        : [UIColor colorWithWhite:0.25 alpha:0.85];
    CGPoint center = self.button.center;
    [self.button sizeToFit];
    CGRect f = self.button.frame;
    f.size.height = 36;
    f.size.width = MAX(f.size.width + 28, 120);
    self.button.frame = f;
    if (self.button.superview) self.button.center = center;
}

- (void)toggle {
    self.enabled = !self.enabled;
    [NSUserDefaults.standardUserDefaults setBool:self.enabled forKey:kEnabledKey];
    [self refreshButton];
    ACLog(@"toggle -> %d", self.enabled);
}

- (void)longPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    self.speedIndex = (self.speedIndex + 1) % kSpeedCount;
    [NSUserDefaults.standardUserDefaults setInteger:self.speedIndex forKey:kSpeedKey];
    [self refreshButton];
    ACLog(@"speed -> %s", kSpeeds[self.speedIndex].label);
}

- (void)pan:(UIPanGestureRecognizer *)g {
    UIView *v = g.view;
    CGPoint t = [g translationInView:v.superview];
    v.center = CGPointMake(v.center.x + t.x, v.center.y + t.y);
    [g setTranslation:CGPointZero inView:v.superview];
}

@end

__attribute__((constructor))
static void ACEntryPoint(void) {
    ACLog(@"LC_AutoClearArrows loaded");
    // UIApplication の準備を待つため次のランループで開始。il2cpp 側の準備は
    // ACIl2CppStep 内で毎回確認し、未準備なら何もせず戻る。
    dispatch_async(dispatch_get_main_queue(), ^{
        [[ACController shared] start];
    });
}
