# Architecture

Grains is three processes sharing one SQLite file and one Swift package.

```
┌────────────────────────── Grains.app (LSUIElement) ──────────────────────────┐
│  OverlayPanel (NSPanel + SwiftUI)   MenuBar (status item)   History/Settings  │
│            │                               │                      │           │
│            └──────────────┬────────────────┴──────────────────────┘           │
│                       AppModel (@MainActor, @Observable)                      │
│        ┌──────────────────┼───────────────────┬─────────────────────┐         │
│   TimerEngine        WeekSeries/Stats     CSVExporter          Updater        │
│   (GrainsCore)       (GrainsReports)      (GrainsReports)      (Sparkle)      │
│        └──────────────────┴───────────────────┘                               │
│                      SQLiteEntryStore (GrainsCore, read/write)                 │
└──────────────────────────────────────┬───────────────────────────────────────┘
                                       │ ~/Library/Application Support/Grains/grains.sqlite (WAL)
┌──────────────────────────────────────┴───────────────────────────────────────┐
│  grains-mcp (bundled tool, launched by Claude Code / Claude Desktop)          │
│  GrainsMCP: JSON-RPC 2.0 over stdio, read-only tools → SQLiteEntryStore(ro)  │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Modules

| Module | Owns | Must not |
|---|---|---|
| `GrainsCore` | `Entry`, `EntryParser`, `EntryReading`/`EntryWriting`, `SQLiteEntryStore`, `InMemoryEntryStore`, `TimerEngine`, recovery, `Settings` keys | import AppKit/SwiftUI, touch the network |
| `GrainsReports` | `WeekSpec`, `Week`, `WeekSeries`, `Stats`, `CSVExporter`, `CSVSchema` | know about the UI or the database (works on `[Entry]`) |
| `GrainsMCP` | MCP protocol handling, tool schemas, tool implementations over `EntryReading` + `GrainsReports` | write to the store |
| `grains-mcp` | `main.swift`: open store read-only, run stdio loop | contain logic |
| `App` | panel, key handling, chart renderer, menu bar, settings, hotkey, corner trigger, Sparkle, launch at login | compute totals itself (always ask `GrainsReports`) |

## Source of truth rules

1. The database is canonical. CSV and MCP are projections.
2. Every number shown or exported comes from `Entry.seconds(within:asOf:)` through `GrainsReports`. The UI never adds durations itself.
3. `rawText` is immutable after capture. Parsing and client normalization write to other columns.
4. The running entry is the row with `stopped_at IS NULL`. There is at most one (enforced by a partial unique index).

## Concurrency model

- `SQLiteEntryStore` is a `final class` with an internal serial `DispatchQueue`; every public method hops onto it synchronously. It is `Sendable` by that discipline (`@unchecked Sendable` with the queue as the justification).
- `TimerEngine` is an `actor`. It owns the heartbeat task and the monotonic reference. The app observes it through an `AsyncStream<TimerState>` and mirrors into the `@MainActor` `AppModel`.
- The app's UI state is a single `@MainActor @Observable final class AppModel`.
- The store posts `.grainsEntriesDidChange` on the main queue after every write; `AppModel` recomputes series/stats and the exporter schedules a debounced write.
- `grains-mcp` is single-threaded: read a request, answer, repeat.

## Data flow for one capture

1. User summons overlay (hot key / corner), types `Denali - iPad enrollment`, presses Return.
2. `OverlayController` → `AppModel.commit(text:)` → `TimerEngine.start(rawText:)`.
3. Engine: if an entry is running, `stoppedAt = now` and `update`; `insert` new entry (parsed via `EntryParser`); start heartbeat task; emit state.
4. Store posts change → `AppModel` recomputes `WeekSeries` and `Stats` for the visible week → chart animates to the new point; `CSVExporter.scheduleWrite(week:)`.
5. Overlay returns to control mode, shows running state. Escape dismisses; the engine keeps running.

## Processes and permissions

| Need | Mechanism | Permission |
|---|---|---|
| Global shortcut | Carbon hot key (`KeyboardShortcuts`) | none |
| Corner trigger | global `mouseMoved` monitor | none |
| Overlay above full-screen apps | `NSPanel` with `.nonactivatingPanel`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, level `.floating` | none |
| Launch at login | `SMAppService.mainApp` | user toggles in Settings |
| Updates | Sparkle 2 | none |

Secure Input (password fields) blocks global hot keys system-wide; the menu bar item remains as the fallback, and the status item shows a small indicator when Secure Input is on (`IsSecureEventInputEnabled()`).
