# Design

Reference: Monkeytype. Typography is the product. Dark first.

## Overlay geometry

- Width 640 pt, minimum height ~ 260 pt (grows with the chart lane). Corner radius 14. Positioned centered horizontally on the pointer's screen, top edge at 22% of the screen height.
- Background: `#161a20` at 96% with a 1 pt inner hairline `#ffffff` at 6%; no system material (consistent across wallpapers, Monkeytype-flat).
- Shadow: 0 24 60 rgba(0,0,0,0.55).

## Typography (SF Mono, D21)

| Element | Size / weight | Color |
|---|---|---|
| Entry line | 28 pt regular, tabular; shrinks to 18 pt to fit, then scrolls (D51) | text `#d1d7e0`; client portion accent `#e2b714`; separator ` - ` muted `#646f7e`; note `#d1d7e0` |
| Inline completion (ghost text, D67) | the entry line's current size, same run and baseline, no background; does not affect the fit (clipped at the edge) | `sub` `#646f7e` |
| Session elapsed | 44 pt light, tabular numerals | accent while running, muted when stopped |
| Metric numbers (week, today) | 22 pt regular | `#d1d7e0` |
| Metric labels | 11 pt, uppercase, +0.08 em tracking | `#646f7e` |
| Mode label | 11 pt | `#646f7e`, accent when running |
| Weekday markers | 10 pt | `#646f7e` / today `#d1d7e0` |

## Palette

| Token | Value | Use |
|---|---|---|
| `bg` | `#161a20` | panel |
| `sub` | `#646f7e` | secondary text, grid |
| `text` | `#d1d7e0` | primary text |
| `accent` | `#e2b714` | running state, client text, active point |
| `accentDim` | `#e2b714` 25% | tracked-hours fill |
| `elapsed` | `#8a93a3` | elapsed lane |
| `target` | `#646f7e` dotted | target trajectory |
| `error` | `#ca4754` | recovery notice, conflicts |

A light theme is on the roadmap; tokens live in `App/Sources/Theme.swift` so it is a table change.

## States

1. **Idle**: empty line with block caret, elapsed `00:00:00` muted, chart in neutral colors, label `type to begin · space to restart last`.
2. **Typing**: bar caret, line text styles live as the parser splits it, label `return to start` (`return to switch` while an entry runs, D50). With the caret at the end, a matching previous entry shows as muted ghost text after the caret (Tab/→ accepts, D67).
3. **Running**: accent elapsed counter ticking, small pulsing dot before the line, chart active point glowing and rising, label `space to stop`.
4. **Stopped** (just stopped): counter freezes then dims over 400 ms, line keeps the text in muted color, label `space to resume · type for new`.
5. **Switching** (commit while running): counter resets with a quick 120 ms fade, chart adds the final point of the old segment then begins the new one; the line briefly flashes accent on the client portion.

## Motion

- Entrance: 120 ms, scale 0.98 → 1 and opacity 0 → 1, ease-out. The text field is first responder before the animation starts; keystrokes during the animation are accepted.
- Exit: 90 ms fade.
- Caret: 1 Hz blink in idle, solid while typing (restart blink after 500 ms of inactivity).
- Chart: new points draw in over 250 ms; the active point has a 2 s breathing glow while running.
- Nothing animates on the key input path; all animation is `withAnimation` on state changes after the model has updated.

## Chart geometry

A 14 pt header row (ceiling label left, `62% of week` right, week id when not current), main lane 72 pt, elapsed lane 6 pt, 10 pt gap, weekday row 14 pt (D56). Hairline grid at 0, ½ and the hours ceiling. Line width 2 pt, round joins. Active point 5 pt radius with 12 pt glow. Future region drawn as a dotted baseline only.

## Multi-display and Spaces

Appears on the screen with the mouse pointer; `canJoinAllSpaces` + `fullScreenAuxiliary` so it shows over full-screen apps. Remembers nothing about position (always recomputed).

## Accessibility

- All overlay text is real text (VoiceOver reads the line, the mode and the counter). The ghost text is not part of the line's accessible value; it is exposed as the hint ("Suggestion: … Tab to accept.").
- Chart exposes an accessibility summary: "14.2 hours tracked, 40 percent of the week elapsed".
- Respects Reduce Motion (no scale/glow animations) and Increase Contrast (brighter `sub`).
- Minimum text size 10 pt. (macOS has no Dynamic Type for custom fonts; the overlay uses fixed sizes. Revisit with a text-size setting.)
