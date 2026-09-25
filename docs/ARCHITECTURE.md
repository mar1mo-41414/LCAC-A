# ARCHITECTURE

LCAC-A の仕組み。対象は Arrows 0.21.1 (Unity 6000.0.58f2, IL2CPP metadata v31)。

## 方針

- **コードの書き換え (インラインフック) を一切しない。** JIT 無しの LiveContainer でも動かすため。
- UnityFramework が export している il2cpp API (`il2cpp_class_from_name`, `il2cpp_class_get_method_from_name` など) を
  `dlsym` で引き、ゲームのメソッドの実装ポインタを直接呼ぶだけ。
- Unity (iOS) はメインスレッドの `CADisplayLink` でフレームを回しているので、tweak も同じスレッドの
  `CADisplayLink` から呼ぶ。フレームとフレームの間に走るため、ECS のエンティティを触ってもゲームと競合しない。
- il2cpp の初期化前に API を呼ばないよう、`il2cpp_get_corlib()` が非 NULL になるまで待つ。
- 名前で解決できなかった場合は何もしない (クラッシュさせない)。

## ゲームの構造

ゲームは Entitas (ECS)。`Contexts._sharedInstance` から `game` / `ui` / `service` の各 Context を取る。

### 矢印

- 矢印は `GameEntity` (`hasArrowId`)。
- `ArrowBlockSystem` が `ArrowGrid.Collides()` で「進行方向に他の矢印があるか」を計算し、
  塞がれている矢印に `Blocked` コンポーネントを付ける (何かが動き出すたびに全矢印を再計算)。
- タップ (`ArrowClickSystem`) は `isTryToMove = true` を立てるだけ。`ArrowMoveSystem` がそれを見て、
  `Blocked` なら Mistake (ライフ -1)、そうでなければ矢印を抜く。

## 矢印の自動クリア

- ゲームには未使用 (実験フラグ `AutoRemoveRedArrows` 用) の自動除去機構があり、`ArrowAutoRemoveSystem` 自体は常に登録されている。
  `AutoRemoveTimer` を持つ矢印のタイマーを毎フレーム減らし、「0 以下 && `Blocked` 無し && ポップアップ無し」で `isTryToMove` を立てる。
- tweak は `GameContext.GetEntities()` から「`Blocked` 無し・移動中でない」矢印を 1 本選び、`ReplaceAutoRemoveTimer(0)` するだけ。
  実際に抜くかどうかはゲーム側が再確認するので、塞がれた矢印を触ることはない。
- 処理待ちのタイマーが残っている間は次を積まない。速度設定は積む間隔。

## レベル自動進行

- クリア回数は `GameContext.isLevelComplete` の立ち上がりで数える。ただし `isLevelComplete` はメニューに戻っても立ったままなので、
  「プレイ中 (`isLevelPlaying && !isLevelComplete`) を見た後の立ち上がり」だけ数える。
- メニューで待っているかどうかは `UiContext.isActiveMainMenuScreen`、非プレイ中、`StartLevel`/`TryStartLevel` 無し、
  `PopupService.HasAnyPopupOrDialogOpen() == false` で判定。これが 1.5 秒続いたら次を開始する。
- 次を開始するときは「表示中の画面のプレイボタン」と同じ処理を呼ぶ。
  - ホーム画面: `MainMenuService.StartGame()` (通常レベル)
  - チャレンジ画面: `UnityEngine.Object.FindFirstObjectByType(Type)` で `DailyChallengeScreenView` を探し、
    `PlayButton.IsInteractable` を確認してから `StartDailyLevel()` を呼ぶ。
    クリア直後は勝利演出が終わるまで選択中の日 (`_year` / `_dayOfYear`) が 0 なので、選ばれるまで待つ。

## ポップアップの自動クローズ

| ポップアップ | 閉じ方 |
| --- | --- |
| 実績解除 (「続ける」) | `isOpen && gameEntityRef.Entity.isAward` の `UiEntity` を探し、`isOpen = false` (ボタンと同じ処理)。以降はゲームの `AwardPopupAutoOpenContinueSystem` が次の実績かメニューを開く |
| 評価のお願い | `RateUsCoordinator.TryGetActivePromptContext` で表示中か確認し、`PopupService.CloseCurrentPopup()` + `RateUsCoordinator.HandleDismiss()` (「閉じる」と同じ処理)。星ボタンは押さない |
| メニュー上のその他 | 6 秒残っていたら `PopupService.CloseAll()` |

## 解析方法

- Unity 6 / metadata v31 は Il2CppDumper (Perfare 版) が非対応のため、[Cpp2IL](https://github.com/SamboyCoding/Cpp2IL) を使用。
  - `--output-as diffable-cs`: クラス構造とフィールドオフセット
  - `--output-as isil`: メソッドごとの逆アセンブル (呼び出し先のメソッド名付き)
- macOS で Cpp2IL のバイナリがそのままだと SIGKILL されるので、`codesign -f -s -` で ad-hoc 署名してから実行する。
