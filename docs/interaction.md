# Interaction model

## Summon and dismiss

| Action | Result |
|---|---|
| Global shortcut (default ⌥Space, D14) | Overlay appears on the screen with the pointer, in control mode, key-ready within one frame. If already visible: hides (if visible but not focused: refocuses, D50). |
| Corner trigger (off by default) | Pointer rests ≥ 350 ms in the chosen corner's 12 pt zone → overlay appears. Leaving the corner does not hide it. |
| Escape in control mode | Hide. Timer unaffected. |
| Escape in typing mode | Back to control mode, text kept (second Escape hides). |
| Click outside / app switch | Overlay stays until Escape or shortcut (it is non-activating, so it never steals focus; a setting "hide when I click elsewhere" is available). |
| Menu bar item | Toggle overlay; menu: Start/Stop, History…, Settings…, Check for Updates…, Quit. |

## Two modes, one surface (D12)

The entry line is the only input. The overlay is always in one of two modes, shown by the caret and a small mode label under the line:

**Control mode** (caret is a block `▮`, label reads `space to start` / `space to stop`):

| Key | Action |
|---|---|
| Space | Toggle: stop the running entry; or start a new entry with the current line text (if the line is empty, restart the most recent entry's text) |
| Return | Same as Space when the line has text; otherwise no-op |
| Any printable character | Enter typing mode and insert it (the line is cleared first if it shows a committed/running entry's text) |
| ⌫ | Enter typing mode editing the current line (deletes the character before the caret, D50) |
| ← / → | Previous / next week in the chart |
| ↑ / ↓ | Cycle recent entries into the line (quick re-start) |
| ⌘, | Settings |
| ⌘Z | Undo last stop (restart the just-stopped entry continuing its text) |
| Escape | Hide |

**Typing mode** (caret is a bar `|`, label reads `return to start`):

| Key | Action |
|---|---|
| Space | Inserts a space |
| Return | Commit: stop running entry if any, start new entry with the line, back to control mode |
| Escape | Back to control mode, keep text |
| ⌘A, ⌘⌫, ⌥⌫, ←/→ with modifiers | Standard text editing |
| ⌘V | Paste (single line; newlines collapse to spaces) |
| ⌘C / ⌘X | Copy / cut the selection |
| ↑ / ↓ | Caret to line start / end |

Also in both modes: ⌘W hides, ⌘, opens Settings. Further details in D50.

Mode switching never needs a click. The first printable character is the switch into typing; Return/Escape is the switch out. There is no way to be unsure which mode is active: caret shape, label text and accent color differ.

## Switching entries

Typing a new line while an entry runs and pressing Return ends the old entry at that instant and starts the new one. The chart shows a short "switch" transition (old segment settles, new point begins). One running entry at a time.

## Recovery notice

If the engine recovered an entry (crash), a one-line notice shows under the stats: `Recovered: stopped at 14:02 after crash · R to resume · A to accept`. `R`/`A` work in control mode.

## Fallback when hot keys are blocked

Secure Input (a password field has focus) blocks all global hot keys; the status item shows a dot and the menu still works.
