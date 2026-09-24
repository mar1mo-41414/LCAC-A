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

## 2026-09-24 ボタン右下固定 + レベル自動進行
- 報告: 縦横を切り替えるとボタンが消えた (固定座標のまま画面外へ行ったと思われる)。
  → ドラッグ移動を廃止し、UIStackView (LEVEL / AUTO) を window.bounds の変化を検知するたびに右下へ再配置。
- レベル完了後の流れ (ISIL から):
  `ArrowsCompleteSystem` → `isLevelComplete` → `LevelCompleteView` (広告の場合あり) → `GoToMainMenu`
  (`isCleanupLevel` + `OpenMainMenu`)。ホームの PlayButton は `HomeScreenView.StartLevel` →
  `IMainMenuService.StartGame()` → `ReplaceLevelEntry(1)` + `SetStartLevel(savegame の現在レベル)` + `CloseMainMenu`。
- 自動進行: メニュー表示中 (`UiContext.isActiveMainMenuScreen`) かつ非プレイ中・StartLevel/TryStartLevel 無し・
  ポップアップ無し (`PopupService.HasAnyPopupOrDialogOpen`) が 1.5 秒続いたら `MainMenuService.StartGame()`。
  連打防止に 4 秒のクールダウン。サービス実体は `XxxServiceComponent.Value (@0x10)` を読み、
  オブジェクト先頭の klass が期待クラスと一致する時だけ呼ぶ。
- モード: OFF / ∞ / 10 / 20 / 50。クリア回数は `isLevelComplete` の立ち上がりで数える。
- 実機確認: 右下固定・回転追従・# ボタンとの非干渉・自動進行・回数表示すべて OK。
  ただし 5/10 で実績解除ポップアップ (「初挑戦で10レベルクリアして完璧なプレイを獲得！」+ 続ける) で停止。

## 2026-09-24 実績解除ポップアップの自動クローズ
- `LevelCompleteView.GoToMainMenu` → `AwardsExtensions.TryAutoOpenAwardPopup` で出るポップアップ。
  PopupService 管理外で、メインメニューもまだ開いていないため「メニュー待機」判定に入らず止まっていた。
- 「続ける」= `AwardPopupButtonsUiView.Close()` は `_canClose (@0x51)` なら自分の UiEntity の `isOpen = false` にするだけ。
  閉じると `AwardPopupAutoOpenContinueSystem` (UiMatcher.Open の除去に反応) が次の実績 or `OpenMainMenu` を開く。
- 実装: プレイ中以外、UiContext.GetEntities() から `isOpen && hasGameEntityRef && gameEntityRef.Value.Entity.isAward`
  の UiEntity を探し、出現から 1.5 秒後に `set_isOpen(false)`。
- 保険: メインメニュー上で PopupService のポップアップが 6 秒以上居座ったら `PopupService.CloseAll()`。
- 実機未検証。

## 2026-09-24 評価のお願いポップアップ + クリア数の誤カウント
- 報告 (実績クローズ版の前のビルド): メインメニュー上の「アローズを楽しんでいますか？」(5つ星 / 1-4つ星 / 閉じる) で停止。
- `RateUsCoordinator.OpenPrompt` → `PopupService.OpenPopup` で開く `AdvancedRateUsUiView`。
  「閉じる」= `Close()`: 自分の UiEntity.isOpen = false → `RateUsCoordinator.HandleDismiss(contexts)`。
- 実装: メニュー上でポップアップが 1.5 秒続き、`RateUsCoordinator.TryGetActivePromptContext` が true なら
  `PopupService.CloseCurrentPopup()` + `HandleDismiss(contexts)`。星ボタンは押さない (レビュー画面に飛ぶため)。
  評価以外は従来通り 6 秒で `CloseAll()`。
- ログで LEVEL ON 直後に `level cleared (1 / -1)` が出ていた。`isLevelComplete` はメニューに戻っても立ったままらしく、
  prev の初期値とのズレで数えていた。→ 「プレイ中 (isLevelPlaying && !isLevelComplete) を観測した後の立ち上がり」だけ数えるよう変更。
- 実機確認: 実績・評価とも 1.5 秒後に閉じて自動進行が再開。LEVEL ON 直後の誤カウントも解消。10 回完走後に自動で OFF。
- 途中でインタースティシャル広告が出ると止まる (閉じれば再開)。広告は姉妹プロジェクト LCAB (iOS_LC_AdBlocker) で塞ぐ方針のため、本プロジェクトの対象外。

## 2026-09-24 チャレンジ (デイリー) 画面の自動進行
- 報告: チャレンジ画面で LEVEL を回すと tweak のカウントは増えるが、ゲーム側のチャレンジのクリア数が増えない。
- 原因: `MainMenuService.StartGame()` はホームのプレイボタン相当で、常に通常レベル (savegame の現在レベル) を開始していた。
  つまりチャレンジ画面にいても通常レベルを進めていた。
- チャレンジのプレイボタン = `DailyChallengeScreenView.StartDailyLevel()`: ビューの `_year (@0xA4)` / `_dayOfYear (@0xA8)` で
  `ReplaceLevelEntry` + tracking + `DailyChallengeUtils.StartDailyChallenge(contexts, year, day)`。
- 実装: `UnityEngine.Object.FindFirstObjectByType(Type)` でアクティブな DailyChallengeScreenView を探し、
  あれば `PlayButton (@0x50).IsInteractable` を確認して `StartDailyLevel()` を直接呼ぶ。無ければ従来通り StartGame。
  - `FindFirstObjectByType` は引数 1 個の候補にジェネリック `<T>(FindObjectsInactive)` もあるため、
    `il2cpp_class_get_methods` で「非ジェネリック・引数 1」を選ぶ。System.Type は `il2cpp_type_get_object(il2cpp_class_get_type(klass))`。
  - 選択中の日が遊べない (ボタン非活性) 場合は LEVEL を OFF にして停止 (勝手に通常レベルへ切り替えない)。
- 実機未検証 (クリア後に次の未クリア日が自動選択される前提。スクショ上は完了済み 9 日の次の 10 日が選択されていた)。
