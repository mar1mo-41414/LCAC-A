# HISTORY

## 2026-09-24 初版

### 解析
- IPA: `com.ecffri.arrows` 0.21.1, Unity 6000.0.58f2, IL2CPP metadata v31.1, UnityFramework は復号済み (cryptid 0)。
- Perfare/Il2CppDumper は v31 非対応のため **Cpp2IL 2022.1.0-pre-release.21 (OSX-ARM64)** を使用。
  - Mac でそのまま実行すると SIGKILL (rc=137) → `codesign -f -s -` で ad-hoc 署名すると動く。
  - `--output-as diffable-cs` でクラス構造、`--output-as isil` でメソッドごとの逆アセンブル + 呼び出し名が出る。
- 主要クラス (すべて Assembly-CSharp, グローバル名前空間):
  - `Contexts._sharedInstance` (static) → `get_game()` → `GameContext` (Entitas `Context<GameEntity>`)
  - `GameEntity`: `hasArrowId`, `isMoving`, `isDestroyed`, `hasBlocked`, `isTryToMove`, `hasAutoRemoveTimer`, `ReplaceAutoRemoveTimer(float)`
  - `ArrowClickSystem`: PointerClick → `GetClosestArrow` → `isTryToMove = true`
  - `ArrowMoveSystem`: `isTryToMove` の矢印を、`hasBlocked` なら Mistake (ライフ -1)、そうでなければ `MoveOutStraight` + `ArrowGrid.RemoveArrow`
  - `ArrowBlockSystem`: `ArrowContainer` 追加時 / 何かが `Moving` になった時に全矢印の `Blocked`/`BlockingArrow` を再計算
  - `ArrowAutoRemoveSystem` (ArrowsFeature で**無条件に登録**): `AutoRemoveTimer` 持ちを毎フレーム減算し、
    0 以下かつ `!hasBlocked` なら `isAutoRemoving` + `isTryToMove`。レベル終了/失敗/ポップアップ表示中/カメラ段階が違う時はスキップ。
  - `ArrowAutoRemoveLevelStartSystem` / `ArrowAutoRemoveQueueSystem` は実験 113 (`AutoRemoveRedArrows`) が有効な時だけ登録される
    (ミスして赤くなった矢印を後で自動で抜く機能)。
- `GameContext.isLevelPlaying` は `LevelStartSystem` で立ち、`CleanupLevelSystem` で下ろされる。

### 実装方針
- インラインフックは JIT 無し LC では不可なので使わない。Unity iOS はメインスレッドの CADisplayLink でループしているため、
  tweak 側も CADisplayLink でフレーム間に ECS を触る (スレッド競合なし)。
- il2cpp 初期化前に `il2cpp_domain_get` 等を呼ばないよう、`il2cpp_get_corlib()` が非 NULL になるまで待つ。
- 自前で `isTryToMove` を立てるのではなく、ゲーム内蔵の `AutoRemoveTimer` 経路に乗せることで、
  ポップアップ中などのガードをゲーム側に任せる。処理待ちのタイマーが残っている間は追加しない。

### 実機確認 (2026-09-24)
- ボタン表示・il2cpp 解決 OK。レベルをミス無しでクリア。ON/OFF・速度切替・実速度変化も問題なし。

## 2026-09-24 起動時デフォルトを OFF に
- 要望により ON/OFF 状態は保存せず、起動直後は常に OFF。速度設定のみ保存を継続。
