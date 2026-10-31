# Timer engine

`actor TimerEngine` in `GrainsCore`. Owns the one running entry, heartbeats, recovery and the monotonic reference for live display.

## API (binding)

```swift
public struct TimerState: Sendable, Equatable {
    public var running: Entry?                 // nil when idle
    public var elapsed: Duration                // monotonic since the engine observed the start (0 when idle)
    public var recovered: Entry?                // most recent entry auto-stopped by recovery and not yet reconciled
}

public actor TimerEngine {
    public init(store: any EntryWriting, clock: any Clock<Duration> = ContinuousClock(), now: @Sendable () -> Date = { Date() }, heartbeatInterval: Duration = .seconds(30))
    /// Call once at launch. Performs recovery (see below) and begins heartbeats if an entry is running.
    public func start() async
    /// Stop the running entry (if any) at `now`, insert a new one from `rawText`, begin heartbeats.
    @discardableResult public func start(rawText: String) async throws -> Entry
    /// Stop the running entry at `now`. No-op when idle.
    @discardableResult public func stop() async throws -> Entry?
    /// Space-bar semantics: stop if running; otherwise restart the most recent entry's text (if any) as a new entry.
    public func toggle() async throws
    /// Resume a recovered entry: a new entry with the same text starting now; marks the old one reconciled.
    public func resumeRecovered() async throws
    public func acceptRecovered() async throws   // marks reconciled, keeps the heartbeat stop time
    /// Call from applicationWillTerminate. Writes clean_shutdown=1, clears heartbeat, keeps the entry running (D7).
    public func prepareForCleanShutdown() async
    public var state: TimerState { get async }
    public func states() -> AsyncStream<TimerState>   // emits current state immediately, then on every change and once per second while running
}
```

## Rules

1. One running entry (DB index enforces). `start(rawText:)` is one transaction: stop old, insert new.
2. Timestamps come from the injected `now()`; tests inject a fake clock and a fake date.
3. **Heartbeat**: while running, write `kv.heartbeat_entry_id` and `kv.heartbeat_at` every 30 s. Clear on stop and on clean shutdown.
4. **Startup recovery** (`start()`):
   - running entry exists and `clean_shutdown == '1'` → trust it, keep running, clear the marker.
   - running entry exists and no clean-shutdown marker → stopped_at = heartbeat_at (if heartbeat matches the entry) else started_at (zero credit); set `metadata.recovered`; emit `recovered`.
   - no running entry → clear stale heartbeat.
   - always set `clean_shutdown` = '0' after processing so the next launch can tell.
5. **Sleep/wake**: the engine does not stop timers on sleep (the user said they were working; the record is wall-clock). On wake, if the sleep lasted more than 2 h while running, `metadata.extra["long_sleep"] = "<seconds>"` is recorded so an AI or the user can review it. App layer forwards `NSWorkspace.didWakeNotification`.
6. **Clock changes**: `elapsed` is monotonic; the stored stop time is wall-clock. A jump > 5 min between consecutive heartbeats is recorded in `metadata.extra["clock_jump"]`.
7. Durations are never negative; `stop()` with `now < startedAt` clamps to `startedAt`.

## Live display

The overlay renders `state.elapsed` formatted `HH:MM:SS`; `states()` ticks once per second aligned to the monotonic clock, so the counter never skips or repeats a second because of wall-clock adjustments.
