# LC_AutoClearArrows

[日本語 README →](README.md)

A tweak (dylib) for LiveContainer that automatically solves the puzzle game **Arrows** (`com.ecffri.arrows`, v0.21.1).

It only pulls arrows whose path is not blocked by another arrow, one at a time, so **no mistakes (lives lost) happen**.

## Usage

1. Build with `gmake` (requires Theos) → `.theos/obj/debug/LCAutoClearArrows.dylib`
2. Put `LCAutoClearArrows.dylib` into the Arrows tweak folder in LiveContainer and launch
3. Two buttons appear at the bottom-right (above the game's # button), both OFF on launch.
   They are re-anchored to the bottom-right when the orientation changes.

### AUTO button (auto-clear arrows)

| Action | Effect |
| --- | --- |
| Tap | ON / OFF (turning OFF also stops auto-level) |
| Long press | Cycle speed (`x1` → `x2` → `x4` → `MAX`) |

### LEVEL button (auto-advance levels)

| Action | Effect |
| --- | --- |
| Tap | Cycle `OFF` → `∞` (until stopped) → `10` → `20` → `50` → `OFF` |
| Long press | Stop immediately |

- Turning LEVEL on also turns AUTO on.
- After a clear, once the main menu has been idle for 1.5 s (no popups), the next level is started the same way the Play button does.
- Shows `LEVEL 3/10` or `LEVEL ∞ (3)`. When the count is reached both AUTO and LEVEL turn OFF.

Only the speed is stored in NSUserDefaults (always OFF on launch). Diagnostic log: `Documents/lcac-debug.log`.

## How it works

- The game is Unity 6 (IL2CPP) + Entitas (ECS). The game's own `ArrowBlockSystem` marks every arrow
  whose path is obstructed with a `Blocked` component (via `ArrowGrid.Collides()`).
- The game ships a dormant auto-remove mechanism: `ArrowAutoRemoveSystem` (always registered)
  removes any arrow carrying an `AutoRemoveTimer` once the timer expires and it is not blocked.
- The tweak, from a main-thread `CADisplayLink`, calls `ReplaceAutoRemoveTimer(0)` on one unblocked arrow at a time.
- Auto-level waits for `UiContext.isActiveMainMenuScreen` with no popup (`PopupService.HasAnyPopupOrDialogOpen()`),
  then calls `MainMenuService.StartGame()` (what the Play button does). Clears are counted on the rising edge of `GameContext.isLevelComplete`.
- It only calls il2cpp exports resolved with `dlsym`; **no code patching / inline hooks**, so no JIT is required.
