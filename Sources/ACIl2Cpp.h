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

NS_ASSUME_NONNULL_END
