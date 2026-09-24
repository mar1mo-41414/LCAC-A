# LC_AutoClearArrows

[English README →](README-EN.md)

LiveContainer 上で動かすパズルゲーム **Arrows** (`com.ecffri.arrows`, v0.21.1) を自動でクリアする tweak (dylib) です。

「進行方向が他の矢印で塞がれていない矢印」だけを 1 本ずつ抜いていくので、**ミス (ライフ減少) は発生しません**。

## 使い方

1. `gmake` でビルド (Theos 必須) → `.theos/obj/debug/LCAutoClearArrows.dylib`
2. LiveContainer で Arrows の Tweak フォルダに `LCAutoClearArrows.dylib` を入れて起動
3. 画面右下 (ゲームの # ボタンの上) に 2 つのボタンが出る。起動直後はどちらも OFF。
   縦横を切り替えても常に右下に置き直される。

### AUTO ボタン (矢印の自動クリア)

| 操作 | 動作 |
| --- | --- |
| タップ | ON / OFF (OFF にするとレベル自動進行も止まる) |
| 長押し | 速度切り替え (`x1` → `x2` → `x4` → `MAX`) |

### LEVEL ボタン (レベル自動進行)

| 操作 | 動作 |
| --- | --- |
| タップ | `OFF` → `∞` (止めるまで無限) → `10` → `20` → `50` → `OFF` と切り替え |
| 長押し | 即停止 (OFF) |

- LEVEL を ON にすると AUTO も自動で ON になる。
- クリア後にメインメニューへ戻ったら、メニューが 1.5 秒落ち着いてからプレイボタンと同じ処理で次のレベルを開始する。
  ポップアップ表示中は待つ。
- 表示は `LEVEL 3/10` (回数モード) / `LEVEL ∞ (3)` (無限モード)。回数に達すると AUTO / LEVEL とも OFF に戻る。

速度だけアプリの NSUserDefaults に保存されます (ON/OFF は保存せず、起動時は常に OFF)。
診断ログは対象アプリの `Documents/lcac-debug.log` に出ます。

## 仕組み

- ゲームは Unity 6 (IL2CPP) + Entitas (ECS)。矢印は `GameEntity` で、
  ゲーム自身の `ArrowBlockSystem` が `ArrowGrid.Collides()` で
  「前方に他の矢印があるか」を計算し、塞がれている矢印に `Blocked` コンポーネントを付けている。
- ゲームには未使用 (実験フラグ `AutoRemoveRedArrows`) の自動除去機構があり、
  `AutoRemoveTimer` を付けた矢印は常時登録済みの `ArrowAutoRemoveSystem` が
  「タイマー切れ && Blocked 無し && ポップアップ無し」になった時点で `isTryToMove` を立てて抜いてくれる。
- tweak はメインスレッドの `CADisplayLink` から、`Blocked` の無い矢印 1 本に
  `ReplaceAutoRemoveTimer(0)` するだけ。実際の除去判定はゲーム側が再確認する。
- レベル自動進行は `UiContext.isActiveMainMenuScreen` と `PopupService.HasAnyPopupOrDialogOpen()` でメニュー待機を判定し、
  ホーム画面のプレイボタンと同じ `MainMenuService.StartGame()` を呼ぶ。クリア回数は `GameContext.isLevelComplete` の立ち上がりで数える。
- il2cpp API (`il2cpp_class_get_method_from_name` 等) を `dlsym` で引いて呼ぶだけで、
  **コードの書き換え (インラインフック) は一切しない**ので JIT 無しで動く。

## 対応バージョン

- Arrows 0.21.1 (Unity 6000.0.58f2) で解析。クラス名/メソッド名で解決しているため、
  名前が変わらない限りアップデート後もそのまま動く見込み。
