import AppKit
import Observation
import SwiftUI

/// Presentation flags the SwiftUI overlay animates on. Separate from `AppModel` because they
/// describe the window, not the data.
@MainActor @Observable
final class OverlayPresentation {
    /// Drives the entrance/exit transition.
    var isPresented = false
    /// Caret rectangle in the hosting view (flipped, top-left origin), for IME placement.
    @ObservationIgnored var caretRect: CGRect = .zero
}

/// Owns the overlay panel, shows/hides it, and executes `InputStateMachine` actions against
/// `AppModel`. The only place that turns keys into model changes.
@MainActor
final class OverlayController: NSObject, KeyCaptureDelegate, NSWindowDelegate {
    let model: AppModel
    let presentation = OverlayPresentation()
    /// Opens Settings (⌘,).
    var onOpenSettings: (() -> Void)?

    private let panel: OverlayPanel
    private let keyView: KeyCaptureView
    private let hostingView: PassiveHostingView<OverlayRootView>
    private var hideGeneration = 0

    init(model: AppModel) {
        self.model = model
        let size = OverlayPlacement.panelSize()
        panel = OverlayPanel(contentRect: NSRect(origin: .zero, size: size))
        keyView = KeyCaptureView(frame: NSRect(origin: .zero, size: size))
        hostingView = PassiveHostingView(rootView: OverlayRootView(model: model, presentation: presentation))
        super.init()
        hostingView.frame = keyView.bounds
        hostingView.autoresizingMask = [.width, .height]
        keyView.addSubview(hostingView)
        keyView.delegate = self
        panel.contentView = keyView
        panel.initialFirstResponder = keyView
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible && presentation.isPresented }

    // MARK: Show / hide

    /// Hot key and menu: show; if visible and key, hide; if visible but not key, refocus.
    func toggle() {
        if isVisible {
            if panel.isKeyWindow { hide() } else { focus() }
        } else {
            show()
        }
    }

    /// Show on the screen containing the pointer, key-ready before the entrance animation.
    func show() {
        hideGeneration += 1
        model.prepareForShow()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            panel.setFrame(OverlayPlacement.panelFrame(screen: screen.frame, visible: screen.visibleFrame), display: false)
        }
        panel.alphaValue = 1
        focus()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .easeOut(duration: 0.12)) {
            presentation.isPresented = true
        }
    }

    /// 90 ms fade, then order out. A show during the fade cancels the order-out.
    func hide() {
        guard presentation.isPresented || panel.isVisible else { return }
        hideGeneration += 1
        let generation = hideGeneration
        withAnimation(.easeIn(duration: 0.09)) {
            presentation.isPresented = false
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.hideGeneration == generation else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Development: render the panel content (card + shadow) over a neutral backdrop to a PNG.
    func writeSnapshot(to path: String) -> Bool {
        let bounds = keyView.bounds
        guard let rep = keyView.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        keyView.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        out.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSColor(hex: 0x4a505a).setFill()
        bounds.fill()
        image.draw(in: bounds)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = out.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(filePath: path))) != nil
    }

    private func focus() {
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(keyView)
    }

    func windowDidResignKey(_ notification: Notification) {
        if model.settings.hideWhenClickingElsewhere && presentation.isPresented { hide() }
    }

    // MARK: KeyCaptureDelegate

    var editor: LineEditor {
        get { model.line }
        set { model.line = newValue }
    }

    func editorDidChange() { model.edited() }

    func caretRectInWindow() -> NSRect {
        hostingView.convert(presentation.caretRect, to: nil)
    }

    func keyCapture(_ input: KeyInput, isRepeat: Bool) {
        // Keys typed during the hide fade (the panel is still key for ~100 ms) are dropped.
        guard presentation.isPresented else { return }
        perform(InputStateMachine.actions(for: input, in: model.inputContext, isRepeat: isRepeat))
    }

    /// Apply actions in order. Pure model mutations; engine work is queued by the model.
    func perform(_ actions: [OverlayAction]) {
        for action in actions {
            switch action {
            case .toggleTimer: model.toggleTimer()
            case .commit(let text): model.commit(text)
            case .insert(let text): model.line.insert(text); model.edited()
            case .deleteBackward: model.line.apply(.deleteBackward); model.edited()
            case .edit(let command): model.line.apply(command); model.lastEdit = Date()
            case .paste:
                if let text = NSPasteboard.general.string(forType: .string) {
                    model.line.paste(text)
                    model.edited()
                }
            case .copy:
                copyToPasteboard(model.line.hasSelection ? model.line.selectedText : model.line.text)
            case .cut:
                if model.line.hasSelection {
                    copyToPasteboard(model.line.deleteSelection())
                    model.edited()
                }
            case .clearLine: model.line.clear(); model.edited()
            case .hide: hide()
            case .previousWeek: model.showPreviousWeek()
            case .nextWeek: model.showNextWeek()
            case .cycleRecent(let delta): model.cycleRecent(delta)
            case .undoStop: model.undoStop()
            case .resumeRecovered: model.resumeRecovered()
            case .acceptRecovered: model.acceptRecovered()
            case .enterTyping: model.mode = .typing; model.lastEdit = Date()
            case .exitTyping: model.mode = .control; model.lastEdit = .distantPast
            case .openSettings: onOpenSettings?()
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// An `NSHostingView` that never takes first responder, so clicks on the card cannot steal
/// keys from `KeyCaptureView`.
final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
}
