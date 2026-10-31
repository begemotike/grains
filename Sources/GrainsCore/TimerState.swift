import Foundation

/// Snapshot of the timer for the UI (docs/timer-engine.md).
public struct TimerState: Sendable, Equatable {
    /// The running entry; nil when idle.
    public var running: Entry?
    /// Monotonic elapsed time of the running entry (zero when idle). See `TimerEngine` for how
    /// it is anchored when the engine adopts an entry that started before launch.
    public var elapsed: Duration
    /// Most recent entry auto-stopped by crash recovery and not yet reconciled.
    public var recovered: Entry?

    public init(running: Entry? = nil, elapsed: Duration = .zero, recovered: Entry? = nil) {
        self.running = running
        self.elapsed = elapsed
        self.recovered = recovered
    }

    /// Nothing running, nothing to reconcile.
    public static let idle = TimerState()

    public var isRunning: Bool { running != nil }
}

/// Errors thrown by `TimerEngine`.
public enum TimerEngineError: Error, Equatable, Sendable {
    /// `start(rawText:)` was given only whitespace. The UI should use `toggle()` instead.
    case emptyText
}
