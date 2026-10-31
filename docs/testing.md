# Testing and validation

## Automated

| Suite | Runs with | Covers |
|---|---|---|
| `GrainsCoreTests` (69) | `swift test` | parser, SQLite store (temp file), one-running-timer index, timer engine with fake clock/date (start/stop/toggle/switch, heartbeats, recovery paths, clock jump, sleep), soft delete |
| `GrainsReportsTests` (45) | `swift test` | week boundaries incl. DST and year transition, ISO ids, series for midnight/week-crossing/running/overlapping entries, stats, CSV byte-exact fixtures, atomic writer |
| `GrainsMCPTests` (54) | `swift test` | JSON-RPC framing, initialize handshake, every tool against an in-memory store, error shapes, redaction flag |
| `GrainsAppTests` (77) | `make app-test` | key handling state machine (mode transitions for Space/Return/Escape/printables), overlay placement math, theme tokens, settings round-trip |

`make test` runs all of them (245 tests as of 2026-10-30). CI: GitHub Actions `macos-26` runner runs `swift test` and `xcodebuild build` (unsigned) on every push; first run green.

## Review history

Each module was built by an Opus agent and then reviewed read-only by a Fable agent before integration. Bugs the reviews caught and fixed (all have regression tests): SQLite UNIQUE index on a nullable column enforcing nothing (D23); metadata JSON `{}` failing to decode; clean-shutdown marker written after the heartbeat was cleared; soft-deleted recovered entry resurrected by Accept/Resume; CSV quoting missing a comma glued to a combining mark; `aggregate` over a 10,000-year range stalling the MCP server; `terminate` from a Task deadlocking the `.terminateLater` reply; CSV never rewritten after deleting an entry from a previous launch; key auto-repeat toggling the timer every 30 ms.

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
