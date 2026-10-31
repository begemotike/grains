import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Summon/dismiss the overlay. Default ⌥Space (D14); changeable in Settings.
    static let toggleOverlay = Self("toggleOverlay", default: .init(.space, modifiers: [.option]))
}

/// The global shortcut (Carbon hot key via `KeyboardShortcuts`, D13). No permission needed;
/// blocked system-wide while Secure Input is on (the menu bar item is the fallback).
@MainActor
final class HotKey {
    init(action: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .toggleOverlay) {
            MainActor.assumeIsolated { action() }
        }
    }
}
