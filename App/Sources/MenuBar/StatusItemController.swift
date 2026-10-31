import AppKit
import Carbon

/// The menu bar presence: template icon (`circle.dotted` idle, `circle.fill` running), an
/// optional `HH:MM` title while running, a Secure Input warning, and the menu
/// (Start/Stop, Show Grains, History…, Settings…, Check for Updates…, Quit).
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// What the menu items do.
    struct Actions {
        var toggleOverlay: @MainActor () -> Void
        var showHistory: @MainActor () -> Void
        var showSettings: @MainActor () -> Void
        var checkForUpdates: @MainActor () -> Void
    }

    private let model: AppModel
    private let actions: Actions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var secureInputTimer: Timer?
    private var secureInputOn = false
    private var secureInputItem: NSMenuItem?

    init(model: AppModel, actions: Actions) {
        self.model = model
        self.actions = actions
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        statusItem.button?.setAccessibilityLabel("Grains")
        secureInputOn = IsSecureEventInputEnabled()
        // Cheap poll so the icon can show the Secure Input warning even with the menu closed.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSecureInput() }
        }
        RunLoop.main.add(timer, forMode: .common)
        secureInputTimer = timer
        observeChanges { [weak self] in self?.updateButton() }
    }

    /// Icon and title from the model (called on every observed change).
    private func updateButton() {
        let running = model.timer.isRunning
        let title = model.menuBarTitle
        guard let button = statusItem.button else { return }
        let symbol = secureInputOn ? (running ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                                   : (running ? "circle.fill" : "circle.dotted")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: running ? "Grains, running" : "Grains")
        image?.isTemplate = true
        button.image = image
        button.title = title.map { " \($0)" } ?? ""
    }

    private func pollSecureInput() {
        let on = IsSecureEventInputEnabled()
        guard on != secureInputOn else { return }
        secureInputOn = on
        updateButton()
        secureInputItem?.isHidden = !on
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let warning = NSMenuItem(title: "⚠︎ Shortcut blocked by Secure Input", action: nil, keyEquivalent: "")
        warning.isEnabled = false
        warning.isHidden = !secureInputOn
        warning.toolTip = "A password field has focus somewhere, so macOS blocks global shortcuts. Use this menu."
        secureInputItem = warning
        menu.addItem(warning)

        menu.addItem(item(startStopTitle, action: #selector(startStop), enabled: model.timer.isRunning || !model.recentTexts.isEmpty))
        menu.addItem(item("Show Grains", action: #selector(showOverlay)))
        menu.addItem(.separator())
        menu.addItem(item("History…", action: #selector(showHistory)))
        menu.addItem(item("Settings…", action: #selector(showSettings), key: ","))
        menu.addItem(item("Check for Updates…", action: #selector(checkForUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Grains", action: #selector(quit), key: "q"))
    }

    func menuWillOpen(_ menu: NSMenu) { pollSecureInput() }

    private var startStopTitle: String {
        if let running = model.timer.running { return "Stop “\(Self.truncate(running.rawText))”" }
        if let last = model.recentTexts.first { return "Start “\(Self.truncate(last))”" }
        return "Start"
    }

    static func truncate(_ text: String, to limit: Int = 40) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    private func item(_ title: String, action: Selector, key: String = "", enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        return item
    }

    @objc private func startStop() {
        if model.timer.isRunning {
            model.stop()
        } else {
            model.restartLast()
        }
    }

    @objc private func showOverlay() { actions.toggleOverlay() }
    @objc private func showHistory() { actions.showHistory() }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func checkForUpdates() { actions.checkForUpdates() }
    @objc private func quit() { NSApp.terminate(nil) }
}
