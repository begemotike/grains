import AppKit
import SwiftUI

/// Shows the app's ordinary windows (History, Settings). Grains is an `LSUIElement` app, so a
/// window needs an explicit activation to come forward.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, resizable: Bool, content: () -> Content) {
        let window: NSWindow
        if let existing = windows[id] {
            window = existing
        } else {
            let controller = NSHostingController(rootView: content())
            window = NSWindow(contentViewController: controller)
            window.title = title
            window.styleMask = resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("Grains.\(id)")
            window.center()
            windows[id] = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
