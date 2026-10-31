# Testing and validation

## Automated

| Suite | Runs with | Covers |
|---|---|---|
| `GrainsCoreTests` | `swift test` | parser, SQLite store (temp file), one-running-timer index, timer engine with fake clock/date (start/stop/toggle/switch, heartbeats, recovery paths, clock jump, sleep), soft delete |
| `GrainsReportsTests` | `swift test` | week boundaries incl. DST and year transition, ISO ids, series for midnight/week-crossing/running/overlapping entries, stats, CSV byte-exact fixtures, atomic writer |
| `GrainsMCPTests` | `swift test` | JSON-RPC framing, initialize handshake, every tool against an in-memory store, error shapes, redaction flag |
| `GrainsAppTests` | `make app-test` | key handling state machine (mode transitions for Space/Return/Escape/printables), overlay placement math, theme tokens, settings round-trip |

`make test` runs all of them. CI: GitHub Actions `macos-26` runner runs `swift test` and `xcodebuild build` (unsigned) on every push.

## Manual validation checklist (from the spec)

- [ ] Start/stop with no mouse use
- [ ] Typing spaces in typing mode; Space in control mode toggles
- [ ] Rapid switching between entries
- [ ] Dismiss/reopen keeps the timer running
- [ ] Long session (> 8 h) displays correctly
- [ ] Clock change mid-session: counter continues, record uses wall-clock, `clock_jump` noted
- [ ] Sleep/wake: timer continues; `long_sleep` noted after > 2 h
- [ ] Clean quit and relaunch: still running
- [ ] Kill -9 and relaunch: recovered at last heartbeat, notice shown, Resume works
- [ ] Session across midnight: today/yesterday hours correct, chart split
- [ ] Session across week boundary: both weeks' CSVs carry their portion
- [ ] Edit a prior week entry: that week's CSV regenerates
- [ ] "Export all weeks" regenerates every file byte-identically when nothing changed
- [ ] MCP `aggregate` for the week equals the overlay's week total
- [ ] Overlay appears over a full-screen app and on the screen with the pointer (two displays)
- [ ] Secure Input (password field focused): shortcut blocked, status item indicator shown, menu works
- [ ] Hot Corners: Grains corner trigger does not fire when the system corner is configured for the same corner
