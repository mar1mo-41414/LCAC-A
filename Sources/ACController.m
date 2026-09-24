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

// 自動レベル進行モード。0 = OFF, -1 = 無限, それ以外 = 残りクリア回数のプリセット。
static const NSInteger kLevelPresets[] = {0, -1, 10, 20, 50};
static const NSInteger kLevelPresetCount = sizeof(kLevelPresets) / sizeof(kLevelPresets[0]);

// メインメニューがこの秒数だけ落ち着いていたら次レベルを開始する (レベルアップ演出待ち)。
static const CFTimeInterval kMenuSettleSeconds = 1.5;
// StartGame を呼んだ後、再度呼ぶまでの最低間隔。
static const CFTimeInterval kStartCooldownSeconds = 4.0;
// 実績ポップアップが出てから閉じるまでの待ち (ボタン表示演出が終わるまで Close が効かない想定)。
static const CFTimeInterval kAwardCloseDelay = 1.5;
// メインメニュー上のポップアップをこの秒数見届けてから閉じにかかる (開く演出待ち)。
static const CFTimeInterval kMenuPopupCloseDelay = 1.5;
// メニュー上でポップアップがこれ以上居座ったら PopupService.CloseAll() する。
static const CFTimeInterval kMenuPopupGiveUpSeconds = 6.0;

@interface ACController : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, strong) UIStackView *stack;
@property (nonatomic, strong) UIButton *autoButton;
@property (nonatomic, strong) UIButton *levelButton;
@property (nonatomic) CGRect lastLayoutBounds;
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger speedIndex;
@property (nonatomic) CFTimeInterval lastStep;

@property (nonatomic) NSInteger levelPresetIndex; // kLevelPresets の添字
@property (nonatomic) NSInteger levelTarget;      // -1 = 無限
@property (nonatomic) NSInteger levelCleared;     // このモードでクリアした回数
@property (nonatomic) BOOL prevLevelComplete;
@property (nonatomic) BOOL sawLevelPlaying; // このレベルを実際にプレイ中の状態で観測したか
@property (nonatomic) CFTimeInterval menuStableSince;
@property (nonatomic) CFTimeInterval lastStartCall;
@property (nonatomic) CFTimeInterval awardSeenSince;
@property (nonatomic) CFTimeInterval lastAwardCheck;
@property (nonatomic) CFTimeInterval menuPopupSince;
@property (nonatomic) CFTimeInterval lastCloseAll;
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
        // 起動直後は常に OFF (ON/OFF・レベルモードは保存しない。速度だけ保存)。
        _enabled = NO;
        _speedIndex = MIN(MAX([NSUserDefaults.standardUserDefaults integerForKey:kSpeedKey], 0), kSpeedCount - 1);
        _levelPresetIndex = 0;
    }
    return self;
}

- (void)start {
    if (self.link) return;
    self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    ACLog(@"display link started (speed=%s)", kSpeeds[self.speedIndex].label);
}

- (BOOL)levelModeActive {
    return kLevelPresets[self.levelPresetIndex] != 0;
}

- (void)tick:(CADisplayLink *)link {
    [self ensureButtons];
    if (!self.enabled && ![self levelModeActive]) return;

    CFTimeInterval now = CACurrentMediaTime();
    ACGameState st = ACIl2CppQueryState();
    if (!st.ready) return;

    if ([self levelModeActive]) {
        [self driveLevelMode:st now:now];
    }
    self.prevLevelComplete = st.levelComplete;

    if (self.enabled && st.levelPlaying && !st.levelComplete && !st.levelFailed) {
        if (now - self.lastStep >= kSpeeds[self.speedIndex].interval && ACIl2CppStep()) {
            self.lastStep = now;
        }
    }
}

- (void)driveLevelMode:(ACGameState)st now:(CFTimeInterval)now {
    // クリア回数のカウント。isLevelComplete はメニューに戻っても立ったまま残るため、
    // 「プレイ中を見届けた後の立ち上がり」だけを数える (モード ON 直後の誤カウント防止)。
    if (st.levelPlaying && !st.levelComplete && !st.levelFailed) self.sawLevelPlaying = YES;
    if (st.levelComplete && !self.prevLevelComplete && self.sawLevelPlaying) {
        self.sawLevelPlaying = NO;
        self.levelCleared++;
        ACLog(@"level cleared (%ld / %ld)", (long)self.levelCleared, (long)self.levelTarget);
        [self refreshButtons];
    }

    BOOL reachedTarget = self.levelTarget > 0 && self.levelCleared >= self.levelTarget;
    if (reachedTarget) {
        // 目標回数に達したら次を始めずに終了。
        if (!st.levelPlaying || st.levelComplete) {
            ACLog(@"level mode finished (%ld levels)", (long)self.levelCleared);
            self.levelPresetIndex = 0;
            self.enabled = NO;
            [self refreshButtons];
        }
        return;
    }

    BOOL inPlay = st.levelPlaying && !st.levelComplete && !st.levelFailed;
    if (!inPlay) {
        [self dismissBlockingPopups:st now:now];
    }

    BOOL menuIdle = st.mainMenuActive && !st.levelPlaying && !st.startPending && !st.popupOpen;
    if (!menuIdle) {
        self.menuStableSince = 0;
        return;
    }
    if (self.menuStableSince == 0) self.menuStableSince = now;
    if (now - self.menuStableSince < kMenuSettleSeconds) return;
    if (now - self.lastStartCall < kStartCooldownSeconds) return;

    self.lastStartCall = now;
    self.menuStableSince = 0;
    ACIl2CppStartGame();
}

/// レベル間で進行を止めるポップアップを片付ける。
- (void)dismissBlockingPopups:(ACGameState)st now:(CFTimeInterval)now {
    // 実績解除 (「初挑戦で10レベルクリア…」+ 続ける) — 0.5 秒おきに確認。
    if (now - self.lastAwardCheck >= 0.5) {
        self.lastAwardCheck = now;
        if (ACIl2CppAwardPopups(NO) > 0) {
            if (self.awardSeenSince == 0) self.awardSeenSince = now;
            if (now - self.awardSeenSince >= kAwardCloseDelay) {
                ACIl2CppAwardPopups(YES);
                self.awardSeenSince = 0; // 次の実績が連続で出たらまた待つ
            }
        } else {
            self.awardSeenSince = 0;
        }
    }

    // メインメニュー上で PopupService のポップアップが居座っている場合。
    if (st.mainMenuActive && st.popupOpen) {
        if (self.menuPopupSince == 0) self.menuPopupSince = now;
        // 評価のお願い → 「閉じる」相当で閉じる。
        if (now - self.menuPopupSince >= kMenuPopupCloseDelay && ACIl2CppDismissRateUs()) {
            self.menuPopupSince = 0;
            return;
        }
        // それ以外 → 最終手段で全部閉じる。
        if (now - self.menuPopupSince >= kMenuPopupGiveUpSeconds && now - self.lastCloseAll >= kMenuPopupGiveUpSeconds) {
            self.lastCloseAll = now;
            ACIl2CppCloseAllPopups();
        }
    } else {
        self.menuPopupSince = 0;
    }
}

#pragma mark - Buttons

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

- (UIButton *)makeButtonWithAction:(SEL)tap longPress:(SEL)longPress {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.titleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightBold];
    b.layer.cornerRadius = 18;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
    [b addTarget:self action:tap forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:longPress];
    lp.minimumPressDuration = 0.5;
    [b addGestureRecognizer:lp];
    [b.heightAnchor constraintEqualToConstant:36].active = YES;
    [b.widthAnchor constraintGreaterThanOrEqualToConstant:130].active = YES;
    return b;
}

- (void)ensureButtons {
    UIWindow *window = [self hostWindow];
    if (!window) return;

    if (!self.stack) {
        self.levelButton = [self makeButtonWithAction:@selector(levelTap) longPress:@selector(levelLongPress:)];
        self.autoButton = [self makeButtonWithAction:@selector(autoTap) longPress:@selector(autoLongPress:)];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.levelButton, self.autoButton]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.alignment = UIStackViewAlignmentTrailing;
        stack.spacing = 8;
        self.stack = stack;
        [self refreshButtons];
        ACLog(@"buttons created on %@", window);
    }

    if (self.stack.superview != window) {
        [window addSubview:self.stack];
        self.lastLayoutBounds = CGRectNull;
    } else if (window.subviews.lastObject != self.stack) {
        [window bringSubviewToFront:self.stack];
    }

    // 回転などで window のサイズが変わったら右下に置き直す。
    if (!CGRectEqualToRect(self.lastLayoutBounds, window.bounds)) {
        self.lastLayoutBounds = window.bounds;
        [self layoutStackInWindow:window];
    }
}

- (void)layoutStackInWindow:(UIWindow *)window {
    CGSize size = [self.stack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    CGRect bounds = window.bounds;
    UIEdgeInsets safe = window.safeAreaInsets;
    // 右下。ゲームの # ボタンと重ならないよう少し上に置く。
    CGFloat x = bounds.size.width - safe.right - 16 - size.width;
    CGFloat y = bounds.size.height - safe.bottom - 110 - size.height;
    self.stack.frame = CGRectMake(x, y, size.width, size.height);
}

- (void)styleButton:(UIButton *)b title:(NSString *)title on:(BOOL)on {
    [b setTitle:[NSString stringWithFormat:@"  %@  ", title] forState:UIControlStateNormal];
    b.backgroundColor = on
        ? [UIColor colorWithRed:0.33 green:0.45 blue:0.98 alpha:0.9]
        : [UIColor colorWithWhite:0.25 alpha:0.85];
}

- (void)refreshButtons {
    NSString *autoTitle = self.enabled
        ? [NSString stringWithFormat:@"AUTO ON %s", kSpeeds[self.speedIndex].label]
        : @"AUTO OFF";
    [self styleButton:self.autoButton title:autoTitle on:self.enabled];

    NSString *levelTitle;
    if (![self levelModeActive]) {
        levelTitle = @"LEVEL OFF";
    } else if (self.levelTarget < 0) {
        levelTitle = [NSString stringWithFormat:@"LEVEL ∞ (%ld)", (long)self.levelCleared];
    } else {
        levelTitle = [NSString stringWithFormat:@"LEVEL %ld/%ld", (long)self.levelCleared, (long)self.levelTarget];
    }
    [self styleButton:self.levelButton title:levelTitle on:[self levelModeActive]];

    UIWindow *window = (UIWindow *)self.stack.superview;
    if (window) [self layoutStackInWindow:window];
}

- (void)autoTap {
    self.enabled = !self.enabled;
    if (!self.enabled && [self levelModeActive]) {
        // 矢印の自動クリアを止めたらレベル進行も止める。
        self.levelPresetIndex = 0;
    }
    [self refreshButtons];
    ACLog(@"auto -> %d", self.enabled);
}

- (void)autoLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    self.speedIndex = (self.speedIndex + 1) % kSpeedCount;
    [NSUserDefaults.standardUserDefaults setInteger:self.speedIndex forKey:kSpeedKey];
    [self refreshButtons];
    ACLog(@"speed -> %s", kSpeeds[self.speedIndex].label);
}

/// タップ: OFF → ∞ → 10 → 20 → 50 → OFF。選び直すとカウントは 0 から。
- (void)levelTap {
    self.levelPresetIndex = (self.levelPresetIndex + 1) % kLevelPresetCount;
    self.levelTarget = kLevelPresets[self.levelPresetIndex];
    self.levelCleared = 0;
    self.menuStableSince = 0;
    // 既にクリア画面にいる状態で ON にしても、そのクリアは数えない。
    self.prevLevelComplete = ACIl2CppQueryState().levelComplete;
    self.sawLevelPlaying = NO;
    if ([self levelModeActive]) self.enabled = YES; // レベル進行中は矢印の自動クリアも必須
    [self refreshButtons];
    ACLog(@"level mode -> %ld", (long)self.levelTarget);
}

/// 長押し: レベル進行を即停止。
- (void)levelLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    self.levelPresetIndex = 0;
    self.levelCleared = 0;
    [self refreshButtons];
    ACLog(@"level mode stopped by long press");
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
