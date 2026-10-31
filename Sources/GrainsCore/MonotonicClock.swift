import Foundation

/// Type-erased monotonic clock: offsets (as `Duration`) from the moment it was wrapped.
/// Lets `TimerEngine` take `any Clock<Duration>` (real or test) without fighting existentials.
struct MonotonicClock: Sendable {
    /// Time since the clock was wrapped.
    let now: @Sendable () -> Duration
    /// Suspends until `now() >= deadline`. Throws `CancellationError` when cancelled.
    let sleep: @Sendable (_ deadline: Duration) async throws -> Void

    init<C: Clock>(_ clock: C) where C.Duration == Swift.Duration {
        let origin = clock.now
        now = { origin.duration(to: clock.now) }
        sleep = { deadline in try await clock.sleep(until: origin.advanced(by: deadline), tolerance: nil) }
    }
}

extension Duration {
    /// The duration in (fractional) seconds.
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
