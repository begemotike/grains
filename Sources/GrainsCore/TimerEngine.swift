import Foundation

/// Owns the one running entry, heartbeats, crash recovery and the monotonic reference for
/// the live display (docs/timer-engine.md, D7–D9).
///
/// Wall-clock timestamps (`now()`) go into records; the injected monotonic `clock` drives
/// `TimerState.elapsed`, heartbeat scheduling and the once-per-second `states()` ticks.
public actor TimerEngine {
    /// A wake after more than this many seconds of sleep while running records `long_sleep`.
    public static let longSleepThreshold: TimeInterval = 2 * 60 * 60
    /// Wall-clock vs monotonic drift between consecutive heartbeats beyond this records `clock_jump`.
    public static let clockJumpThreshold: TimeInterval = 5 * 60
    /// `metadata.extra` key: cumulative seconds slept (> threshold) while this entry ran.
    public static let longSleepKey = "long_sleep"
    /// `metadata.extra` key: cumulative signed seconds the wall clock jumped while this entry ran.
    public static let clockJumpKey = "clock_jump"

    private let store: any EntryWriting
    private let clock: MonotonicClock
    private let now: @Sendable () -> Date
    private let heartbeatInterval: Duration

    private var running: Entry?
    private var recovered: Entry?
    /// The entry `stop()` stopped most recently, for `undoLastStop()`. Cleared by any start.
    private var lastStopped: Entry?
    /// `elapsed = offset + (clock.now() - mono)`.
    private var elapsedBase: (mono: Duration, offset: Duration) = (.zero, .zero)
    private var lastBeat: (wall: Date, mono: Duration)?
    private var heartbeatTask: Task<Void, Never>?
    /// Bumped whenever heartbeats are (re)scheduled or stopped, so a heartbeat that already
    /// woke up but reaches the actor late is ignored.
    private var heartbeatGeneration = 0
    /// Set by `prepareForCleanShutdown()`; no heartbeat may be written afterwards.
    private var isShutDown = false
    private var tickTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<TimerState>.Continuation] = [:]
    private var didStart = false

    /// Description of the most recent error swallowed by a non-throwing path (heartbeat,
    /// launch recovery, clean shutdown). For diagnostics only.
    public private(set) var lastBackgroundError: String?

    /// - Parameters:
    ///   - store: the write store (the app's `SQLiteEntryStore`, or `InMemoryEntryStore`).
    ///   - clock: monotonic clock for elapsed time and scheduling. `ContinuousClock` keeps
    ///     advancing during system sleep, which is what the wall-clock record does too.
    ///   - now: wall clock for every stored timestamp.
    ///   - heartbeatInterval: liveness marker period while running (D8).
    public init(
        store: any EntryWriting,
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping @Sendable () -> Date = { Date() },
        heartbeatInterval: Duration = .seconds(30)
    ) {
        self.store = store
        self.clock = MonotonicClock(clock)
        self.now = now
        self.heartbeatInterval = heartbeatInterval
    }

    deinit {
        heartbeatTask?.cancel()
        tickTask?.cancel()
        for continuation in subscribers.values { continuation.finish() }
    }

    // MARK: State

    /// The current state.
    public var state: TimerState { currentState() }

    /// Emits the current state immediately, then on every change, and once per second
    /// (aligned to whole elapsed seconds on the monotonic clock) while an entry runs.
    /// Buffers the newest 64 values for slow consumers.
    public func states() -> AsyncStream<TimerState> {
        let (stream, continuation) = AsyncStream.makeStream(of: TimerState.self, bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id) }
        }
        continuation.yield(currentState())
        updateTicker()
        return stream
    }

    // MARK: Lifecycle

    /// Call once at launch. Performs recovery and begins heartbeats if an entry is running.
    ///
    /// - Running entry + `clean_shutdown == "1"`: keep running (D7).
    /// - Running entry, no marker: stop at the last heartbeat (if it belongs to the entry),
    ///   else at `startedAt` (zero credit); set `metadata.recovered`; expose as `recovered` (D8).
    /// - No running entry: clear any stale heartbeat. An unreconciled recovered entry that is
    ///   still the most recent entry is exposed again as `recovered`.
    /// - Always sets `clean_shutdown = "0"` afterwards.
    public func start() async {
        guard !didStart else { return }
        didStart = true
        do {
            try recoverAtLaunch()
        } catch {
            lastBackgroundError = String(describing: error)
        }
        broadcast()
    }

    /// Call from `applicationWillTerminate`. Writes `clean_shutdown = "1"`, clears the
    /// heartbeat and stops heartbeating; the entry stays running in the database (D7).
    public func prepareForCleanShutdown() async {
        isShutDown = true
        stopHeartbeats()
        lastBeat = nil
        do {
            // Marker first, heartbeat second: a kill between the two writes then leaves a stale
            // heartbeat (harmless, overwritten on adopt) instead of a zero-credit recovery.
            try store.writeValue("1", forKey: EntryStoreKey.cleanShutdown)
            try store.clearHeartbeat()
        } catch {
            lastBackgroundError = String(describing: error)
        }
    }

    /// Re-read the running entry from the store, e.g. after the History window edited it.
    /// Re-anchors `elapsed` if the running entry or its start time changed.
    public func reload() async {
        do {
            let stored = try store.runningEntry()
            if let stored {
                if stored.id != running?.id || stored.startedAt != running?.startedAt {
                    adopt(stored, at: now())
                } else {
                    running = stored
                }
            } else if running != nil {
                becomeIdle()
            }
        } catch {
            lastBackgroundError = String(describing: error)
        }
        broadcast()
    }

    // MARK: Commands

    /// Stop the running entry (if any) at `now`, insert a new one from `rawText`, begin
    /// heartbeats. Stop and insert are one transaction and share the same instant.
    /// Starting new work dismisses a pending `recovered` notice (the row stays flagged).
    @discardableResult
    public func start(rawText: String) async throws -> Entry {
        try begin(rawText: rawText, alsoWriting: [])
    }

    /// Stop the running entry at `now` (clamped to its start). No-op when idle.
    @discardableResult
    public func stop() async throws -> Entry? {
        guard let current = try store.runningEntry() else {
            if running != nil {
                becomeIdle()
                broadcast()
            }
            return nil
        }
        let stopped = Self.stopping(current, at: now())
        try store.update(stopped)
        try store.clearHeartbeat()
        lastStopped = stopped
        becomeIdle()
        broadcast()
        return stopped
    }

    /// Space-bar semantics: stop if running; otherwise restart the most recent entry's
    /// text (if any) as a new entry.
    public func toggle() async throws {
        if try store.runningEntry() != nil {
            try await stop()
        } else if let latest = try store.recentEntries(limit: 1).first {
            try begin(rawText: latest.rawText, alsoWriting: [])
        }
    }

    /// ⌘Z: when idle, restart the text of the entry `stop()` just stopped as a new entry.
    /// Single level; returns nil (and does nothing) when something is running or there is
    /// no stop to undo in this session.
    @discardableResult
    public func undoLastStop() async throws -> Entry? {
        guard let stopped = lastStopped, try store.runningEntry() == nil else { return nil }
        return try begin(rawText: stopped.rawText, alsoWriting: [])
    }

    /// Resume a recovered entry: a new entry with the same text starting now; marks the old
    /// one reconciled (in the same transaction).
    public func resumeRecovered() async throws {
        guard let pending = recovered else { return }
        let writes: [EntryWrite] = try reconciling(pending).map { [.update($0)] } ?? []
        try begin(rawText: pending.rawText, alsoWriting: writes)
    }

    /// Marks the recovered entry reconciled, keeping the heartbeat stop time.
    public func acceptRecovered() async throws {
        guard let pending = recovered else { return }
        if let reconciled = try reconciling(pending) { try store.update(reconciled) }
        recovered = nil
        broadcast()
    }

    /// The app forwards `NSWorkspace.didWakeNotification` with how long the Mac slept.
    /// The timer keeps running (wall-clock record); a sleep over 2 h while running adds the
    /// seconds to `metadata.extra["long_sleep"]` for review. Also writes a heartbeat.
    public func noteWake(sleptFor seconds: TimeInterval) async {
        guard running != nil else { return }
        if seconds > Self.longSleepThreshold {
            accumulate(seconds, into: Self.longSleepKey)
        }
        beat()
        broadcast()
    }

    // MARK: Internals

    private func currentState() -> TimerState {
        guard running != nil else { return TimerState(running: nil, elapsed: .zero, recovered: recovered) }
        let elapsed = elapsedBase.offset + (clock.now() - elapsedBase.mono)
        return TimerState(running: running, elapsed: max(.zero, elapsed), recovered: recovered)
    }

    @discardableResult
    private func begin(rawText: String, alsoWriting extra: [EntryWrite]) throws -> Entry {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TimerEngineError.emptyText
        }
        let instant = now()
        var writes: [EntryWrite] = []
        if let current = try store.runningEntry() {
            writes.append(.update(Self.stopping(current, at: instant)))
        }
        writes.append(contentsOf: extra)
        let parsed = EntryParser.parse(rawText)
        let entry = Entry(
            rawText: rawText, clientText: parsed.clientText, note: parsed.note,
            startedAt: instant, createdAt: instant, updatedAt: instant
        )
        writes.append(.insert(entry))
        try store.commit(writes)
        recovered = nil
        lastStopped = nil
        adopt(entry, at: instant)
        broadcast()
        return entry
    }

    private func recoverAtLaunch() throws {
        let instant = now()
        let clean = try store.readValue(forKey: EntryStoreKey.cleanShutdown) == "1"
        if let entry = try store.runningEntry() {
            if clean {
                adopt(entry, at: instant)
            } else {
                let heartbeat = try store.readHeartbeat()
                let lastAlive = heartbeat.flatMap { $0.entryID == entry.id ? $0.at : nil } ?? entry.startedAt
                var stopped = Self.stopping(entry, at: lastAlive)
                stopped.updatedAt = instant
                stopped.metadata.recovered = .init(lastHeartbeat: lastAlive, noticedAt: instant)
                try store.update(stopped)
                try store.clearHeartbeat()
                recovered = stopped
            }
        } else {
            try store.clearHeartbeat()
            if let latest = try store.recentEntries(limit: 1).first,
               latest.metadata.recovered?.reconciled == false {
                recovered = latest
            }
        }
        try store.writeValue("0", forKey: EntryStoreKey.cleanShutdown)
    }

    /// Make `entry` the running entry: anchor elapsed (wall-clock age at `instant`, then
    /// monotonic), write a heartbeat now, schedule heartbeats and ticks.
    private func adopt(_ entry: Entry, at instant: Date) {
        running = entry
        elapsedBase = (clock.now(), .seconds(max(0, instant.timeIntervalSince(entry.startedAt))))
        lastBeat = nil
        beat()
        startHeartbeats()
        updateTicker()
    }

    private func becomeIdle() {
        running = nil
        lastBeat = nil
        stopHeartbeats()
        // Rule 3 of timer-engine.md: no heartbeat may outlive the running entry, including when
        // the entry was stopped externally (History edit) and observed through `reload()`.
        do { try store.clearHeartbeat() } catch { lastBackgroundError = String(describing: error) }
        updateTicker()
    }

    /// Returns the stored row marked reconciled, or nil when the row no longer exists (soft
    /// deleted in History after the notice appeared). Falling back to the in-memory snapshot
    /// would resurrect the deleted row.
    private func reconciling(_ entry: Entry) throws -> Entry? {
        guard var current = try store.entry(id: entry.id) else { return nil }
        current.metadata.recovered?.reconciled = true
        current.updatedAt = now()
        return current
    }

    private static func stopping(_ entry: Entry, at instant: Date) -> Entry {
        var stopped = entry
        stopped.stoppedAt = max(instant, entry.startedAt)
        stopped.updatedAt = instant
        return stopped
    }

    /// Writes the heartbeat and checks for a wall-clock jump since the previous one.
    private func beat() {
        guard let entry = running, !isShutDown else { return }
        let wall = now()
        let mono = clock.now()
        if let last = lastBeat {
            let drift = wall.timeIntervalSince(last.wall) - (mono - last.mono).timeInterval
            if abs(drift) > Self.clockJumpThreshold {
                accumulate(drift, into: Self.clockJumpKey)
            }
        }
        do {
            try store.writeHeartbeat(entryID: entry.id, at: wall)
        } catch {
            lastBackgroundError = String(describing: error)
        }
        lastBeat = (wall, mono)
    }

    /// Adds `seconds` to an integer-seconds counter in the running entry's `metadata.extra`.
    private func accumulate(_ seconds: TimeInterval, into key: String) {
        guard let id = running?.id else { return }
        do {
            guard var entry = try store.entry(id: id) else { return }
            let previous = entry.metadata.extra[key].flatMap(Double.init) ?? 0
            entry.metadata.extra[key] = String(Int((previous + seconds).rounded()))
            entry.updatedAt = now()
            try store.update(entry)
            running = entry
        } catch {
            lastBackgroundError = String(describing: error)
        }
    }

    private func heartbeatFired(generation: Int) {
        guard generation == heartbeatGeneration else { return }
        beat()
    }

    private func stopHeartbeats() {
        heartbeatGeneration += 1
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func startHeartbeats() {
        stopHeartbeats()
        let generation = heartbeatGeneration
        let clock = self.clock
        let interval = heartbeatInterval
        // Anchor the schedule now, not when the task first runs, so it is relative to the
        // heartbeat `adopt` just wrote.
        let firstDeadline = clock.now() + interval
        heartbeatTask = Task { [weak self] in
            var deadline = firstDeadline
            while !Task.isCancelled {
                do { try await clock.sleep(deadline) } catch { return }
                guard let engine = self else { return }
                await engine.heartbeatFired(generation: generation)
                let current = clock.now()
                deadline += interval
                if deadline <= current { deadline = current + interval }
            }
        }
    }

    private func updateTicker() {
        tickTask?.cancel()
        tickTask = nil
        guard running != nil, !subscribers.isEmpty else { return }
        let clock = self.clock
        let base = elapsedBase
        // Monotonic instant at which elapsed next reaches a whole second after `instant`.
        let nextTick: @Sendable (Duration) -> Duration = { instant in
            let elapsed = base.offset + (instant - base.mono)
            let nextWhole = Duration.seconds(max(0, elapsed.components.seconds) + 1)
            return base.mono + (nextWhole - base.offset)
        }
        // First deadline is fixed now, not when the task first runs (no skipped first tick).
        let firstDeadline = nextTick(clock.now())
        tickTask = Task { [weak self] in
            var deadline = firstDeadline
            while !Task.isCancelled {
                do { try await clock.sleep(deadline) } catch { return }
                guard let engine = self else { return }
                await engine.broadcast()
                deadline += .seconds(1)
                let current = clock.now()
                if deadline <= current { deadline = nextTick(current) }  // fell behind (sleep): realign
            }
        }
    }

    private func broadcast() {
        let snapshot = currentState()
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty { updateTicker() }
    }
}
