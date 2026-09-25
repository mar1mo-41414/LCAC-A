# LCAC-A — LiveContainer AutoClear Arrows

[日本語 README →](README.md)

A tweak (dylib) for [LiveContainer](https://github.com/LiveContainer/LiveContainer) that automatically solves the puzzle game **Arrows** (`com.ecffri.arrows`).

- **Auto-clear arrows** — only pulls arrows whose path is free, one at a time, so **no mistakes (lives lost) ever happen**.
- **Auto-advance levels** — starts the next level after each clear. Choose ∞ / 10 / 20 / 50.
  Advances regular levels on the Home screen, and daily challenges on the Challenge screen.
- Achievement and rate-us popups that appear in between are dismissed automatically.

## Download

Get `LCAC-A.dylib` from [Releases](../../releases/latest).

## Usage

1. Put `LCAC-A.dylib` into the Arrows tweak folder in LiveContainer and launch
2. Two buttons, `LEVEL` and `AUTO`, appear at the bottom-right (both OFF on launch)

### AUTO button (auto-clear arrows)

| Action | Effect |
| --- | --- |
| Tap | ON / OFF |
| Long press | Cycle speed (`x1` → `x2` → `x4` → `MAX`) |

### LEVEL button (auto-advance)

| Action | Effect |
| --- | --- |
| Tap | `OFF` → `∞` (until stopped) → `10` → `20` → `50` → `OFF` |
| Long press | Stop immediately |

- Turning LEVEL on also turns AUTO on; turning AUTO off also stops LEVEL.
- Shows `LEVEL 3/10` / `LEVEL ∞ (3)`. When the count is reached, both turn OFF.
- On the Challenge screen, it stops when no playable day is left (e.g. the whole month is cleared).
- Only the speed is saved. ON/OFF is not saved; everything is OFF on launch.

## Notes

- Ads are out of scope. An ad stops the loop until you close it
  (use an ad blocker such as [LCAB](https://github.com/mar1mo-41414/LCAB)).
- If something goes wrong, check `Documents/lcac-a-debug.log` in the app's container.
- Tested with Arrows 0.21.1. It relies on the game's internal class/method names, so a game update that renames them may break it.

## Build

Requires [Theos](https://theos.dev).

```bash
make FINALPACKAGE=1
```

Output: `.theos/obj/LCAC-A.dylib`.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it works and [HISTORY.md](HISTORY.md) (Japanese) for the development log.
