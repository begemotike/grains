# Interaction model

## Summon and dismiss

| Action | Result |
|---|---|
| Global shortcut (default ⌘Escape, D14) | Overlay appears on the screen with the pointer, in control mode, key-ready within one frame. If already visible (focused or not): hides (D66). |
| Corner trigger (off by default) | Pointer rests ≥ 350 ms in the chosen corner's 12 pt zone → overlay appears. Leaving the corner does not hide it. |
| Escape in control mode | Hide. Timer unaffected. |
| Escape in typing mode | Back to control mode, text kept (second Escape hides). |
| Return in typing mode (non-empty line) | Commit, then hide (D65). |
| Space in control mode (Return too, when it acts as Space) | Toggle the timer, then hide (D65). |
| Click outside / app switch | Hides (setting "Hide overlay when I click elsewhere", on by default, D66). With the setting off the overlay stays until Escape or the shortcut. The panel is non-activating, so it never steals focus from the app underneath. |
| Menu bar item | Toggle overlay; menu: Start/Stop, History…, Settings…, Check for Updates…, Quit. |

## Two modes, one surface (D12)

The entry line is the only input. The overlay is always in one of two modes, shown by the caret and a small mode label under the line:

**Control mode** (caret is a block `▮`, label reads `space to start` / `space to stop`):

| Key | Action |
|---|---|
| Space | Toggle: stop the running entry; or start a new entry with the current line text (if the line is empty, restart the most recent entry's text); then hide (D65) |
| Return | Same as Space (including the hide) when the line has text; otherwise no-op |
| Tab | Nothing |
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
| Return | Commit: stop running entry if any, start new entry with the line, back to control mode, hide (D65). On an empty line: back to control mode only |
| Escape | Back to control mode, keep text |
| Tab / → at the end of the line | Accept the inline completion (inserted into the line; stays in typing mode, never commits, D67). Without a completion Tab does nothing and → moves the caret as usual |
| ⌘A, ⌘⌫, ⌥⌫, ←/→ with modifiers | Standard text editing |
| ⌘V | Paste (single line; newlines collapse to spaces) |
| ⌘C / ⌘X | Copy / cut the selection |
| ↑ / ↓ | Caret to line start / end |

Also in both modes: ⌘W hides, ⌘, opens Settings. Further details in D50.

Key auto-repeat (D62): in control mode a held Space, Return, Escape or arrow key acts once; its repeats are ignored, so holding Space never toggles the timer in a burst. In typing mode repeats work as usual (held Space, ⌫, arrows). Keys pressed while the overlay is fading out after a hide are ignored (D63).

## Inline completion (D67)

While typing, a muted completion ("ghost text") follows the caret when the caret is at the end of the line: before the ` - ` separator it completes a client label plus ` - ` (most recently used label first), otherwise (or when no label matches) the most recent non-deleted entry whose text starts with what is typed (case-insensitive). Every other key keeps typing and recomputes it; Return commits only what is typed. Settings → Overlay → "Suggest previous entries while typing" (on by default) turns it off.

A Space that stops the running entry leaves the line as it is: a draft typed and then Escaped stays a draft (shown as idle with the draft, not as the stopped entry), D64.

Mode switching never needs a click. The first printable character is the switch into typing; Return/Escape is the switch out. There is no way to be unsure which mode is active: caret shape, label text and accent color differ.

## Switching entries

Typing a new line while an entry runs and pressing Return ends the old entry at that instant and starts the new one. The chart shows a short "switch" transition (old segment settles, new point begins). One running entry at a time.

## Recovery notice

If the engine recovered an entry (crash), a one-line notice shows under the stats: `Recovered: stopped at 14:02 after crash · R to resume · A to accept`. `R`/`A` work in control mode.

## Fallback when hot keys are blocked

Secure Input (a password field has focus) blocks all global hot keys; the status item shows a dot and the menu still works.
