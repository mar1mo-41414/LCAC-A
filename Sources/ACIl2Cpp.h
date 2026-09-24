#import <Foundation/Foundation.h>

// UnityFramework が export している il2cpp API を dlsym で引き、
// ゲーム側 (Assembly-CSharp) のメソッドを直接呼ぶための薄いラッパー。
// コード書き換え (インラインフック) は一切行わないため、JIT 無しの LiveContainer でも動く。

NS_ASSUME_NONNULL_BEGIN

/// il2cpp の初期化とゲームクラスの解決を試みる。成功したら YES。
/// 失敗しても何度でも呼び直して良い (起動直後は il2cpp が未初期化のため)。
BOOL ACIl2CppResolve(void);

/// 盤面を 1 ステップ進める。塞がれていない矢印を最大 1 本だけ
/// ゲーム自身の自動除去キュー (AutoRemoveTimer) に積む。
/// 戻り値: 積んだら YES。
BOOL ACIl2CppStep(void);

typedef struct {
    BOOL ready;            // il2cpp 解決済み && Contexts 生成済み
    BOOL levelPlaying;     // GameContext.isLevelPlaying
    BOOL levelComplete;    // GameContext.isLevelComplete
    BOOL levelFailed;      // GameContext.isLevelFailed
    BOOL startPending;     // StartLevel / TryStartLevel 要求が処理待ち
    BOOL mainMenuActive;   // UiContext.isActiveMainMenuScreen
    BOOL popupOpen;        // PopupService.HasAnyPopupOrDialogOpen()
} ACGameState;

/// 現在のゲーム状態を読む (読むだけで何も変更しない)。
ACGameState ACIl2CppQueryState(void);

/// メインメニューのプレイボタンと同じ処理 (MainMenuService.StartGame) で次のレベルを開始する。
BOOL ACIl2CppStartGame(void);

/// 開いている実績解除ポップアップ (UiEntity.isOpen && gameEntityRef → GameEntity.isAward) の数を返す。
/// close が YES なら「続ける」ボタンと同じく isOpen = false にして閉じる。
NSInteger ACIl2CppAwardPopups(BOOL close);

/// PopupService.CloseAll() (メニュー上で居座るポップアップの最終手段)。
BOOL ACIl2CppCloseAllPopups(void);

NS_ASSUME_NONNULL_END
