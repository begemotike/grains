import AppKit

/// The floating, non-activating overlay window (D15). It becomes key without activating
/// Grains, so Escape returns the user exactly where they were; it joins every Space and
/// shows over full-screen apps.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // the card draws its own design-spec shadow
        isReleasedWhenClosed = false
        animationBehavior = .none
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        setAccessibilityLabel("Grains")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
