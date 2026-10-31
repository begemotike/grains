import SwiftUI

/// Entry point. Grains is a menu bar app (`LSUIElement`); all windows are managed by
/// `AppDelegate`, so the only scene is an empty `Settings` placeholder the app never opens.
@main
struct GrainsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
