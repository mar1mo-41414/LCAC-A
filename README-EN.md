# LC_AutoClearArrows

[日本語 README →](README.md)

A tweak (dylib) for LiveContainer that automatically solves the puzzle game **Arrows** (`com.ecffri.arrows`, v0.21.1).

It only pulls arrows whose path is not blocked by another arrow, one at a time, so **no mistakes (lives lost) happen**.

## Usage

1. Build with `gmake` (requires Theos) → `.theos/obj/debug/LCAutoClearArrows.dylib`
2. Put `LCAutoClearArrows.dylib` into the Arrows tweak folder in LiveContainer and launch
3. An `AUTO ON x1` button appears at the bottom-left. Arrows are removed automatically once a level starts

| Action | Effect |
| --- | --- |
| Tap | Toggle auto-clear ON / OFF |
| Long press | Cycle speed (`x1` → `x2` → `x4` → `MAX`) |
| Drag | Move the button |

Settings are stored in the app's NSUserDefaults. Diagnostic log: `Documents/lcac-debug.log`.

## How it works

- The game is Unity 6 (IL2CPP) + Entitas (ECS). The game's own `ArrowBlockSystem` marks every arrow
  whose path is obstructed with a `Blocked` component (via `ArrowGrid.Collides()`).
- The game ships a dormant auto-remove mechanism: `ArrowAutoRemoveSystem` (always registered)
  removes any arrow carrying an `AutoRemoveTimer` once the timer expires and it is not blocked.
- The tweak, from a main-thread `CADisplayLink`, calls `ReplaceAutoRemoveTimer(0)` on one unblocked arrow at a time.
- It only calls il2cpp exports resolved with `dlsym`; **no code patching / inline hooks**, so no JIT is required.
