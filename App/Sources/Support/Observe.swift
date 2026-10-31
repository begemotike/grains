import Observation

/// Re-runs `apply` whenever any observable property it reads changes (and once now).
/// The AppKit side (status item, triggers) uses this to follow `@Observable` state.
@MainActor
func observeChanges(_ apply: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in observeChanges(apply) }
    }
}
