# LCAC-A — LiveContainer AutoClear Arrows

[English README →](README-EN.md)

[LiveContainer](https://github.com/LiveContainer/LiveContainer) で動かすパズルゲーム **Arrows** (`com.ecffri.arrows`) を自動でクリアする tweak (dylib) です。

- **矢印の自動クリア** — 前が塞がれていない矢印だけを 1 本ずつ抜くので、**ミス (ライフ減少) は起きません**。
- **レベル自動進行** — クリア後に次のレベルを自動で開始。無限 / 10 / 20 / 50 回から選べます。
  ホーム画面なら通常レベル、チャレンジ画面ならデイリーチャレンジを進めます。
- 途中で出る実績解除・評価のお願いのポップアップも自動で閉じます。

## ダウンロード

[Releases](../../releases/latest) から `LCAC-A.dylib` を取得してください。

## 使い方

1. LiveContainer で Arrows の Tweak フォルダに `LCAC-A.dylib` を入れて起動
2. 画面右下に `LEVEL` と `AUTO` の 2 つのボタンが出ます (起動直後はどちらも OFF)

### AUTO ボタン (矢印の自動クリア)

| 操作 | 動作 |
| --- | --- |
| タップ | ON / OFF |
| 長押し | 速度切り替え (`x1` → `x2` → `x4` → `MAX`) |

### LEVEL ボタン (レベル自動進行)

| 操作 | 動作 |
| --- | --- |
| タップ | `OFF` → `∞` (止めるまで無限) → `10` → `20` → `50` → `OFF` |
| 長押し | 即停止 |

- LEVEL を ON にすると AUTO も ON になります。AUTO を OFF にすると LEVEL も止まります。
- 表示は `LEVEL 3/10` / `LEVEL ∞ (3)`。指定回数に達すると両方 OFF に戻ります。
- チャレンジ画面で遊べる日が無くなった (その月をすべてクリアした等) 場合は停止します。
- 速度設定だけ保存されます。ON/OFF は保存されず、起動時は常に OFF です。

## 注意

- 広告は対象外です。広告が出るとそこで止まり、閉じると再開します
  (広告ブロックは [LCAB](https://github.com/mar1mo-41414/LCAB) 等をどうぞ)。
- 動作がおかしい時は、アプリの `Documents/lcac-a-debug.log` を確認してください。
- Arrows 0.21.1 で確認しています。ゲーム内部のクラス名・メソッド名で動いているため、
  アップデートで名前が変わると動かなくなる可能性があります。

## ビルド

[Theos](https://theos.dev) が必要です。

```bash
make FINALPACKAGE=1
```

`.theos/obj/LCAC-A.dylib` が出力されます。

仕組みの詳細は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)、開発の経緯は [HISTORY.md](HISTORY.md) を参照してください。
