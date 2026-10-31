import AppKit
import GrainsCore
import GrainsReports
import Sparkle
import os

/// Wires the app together: store, timer engine, model, overlay, menu bar, triggers, export,
/// updater, sleep/wake, rollover and clean shutdown.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "net.outofajam.Grains", category: "app")
    private var store: SQLiteEntryStore?
    private var engine: TimerEngine?
    private var settings: AppSettings?
    private var model: AppModel?
    private var overlay: OverlayController?
    private var statusItem: StatusItemController?
    private var hotKey: HotKey?
    private var cornerTrigger: CornerTrigger?
    private var exporter: ExportService?
    private var updater: SPUStandardUpdaterController?
    private let windows = WindowPresenter()
    private var historyModel: HistoryModel?
    private var observers: [any NSObjectProtocol] = []
    private var rolloverTimer: Timer?
    private var sleptAt: Date?
    private var stateTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !LaunchOptions.isRunningTests else { return }
        let options = LaunchOptions()

        let store: SQLiteEntryStore
        do {
            store = try SQLiteEntryStore.open(at: GrainsPaths.databaseURL)
        } catch {
            fatalOpen(error)
            return
        }
        let engine = TimerEngine(store: store)
        let settings = AppSettings(defaultExportFolder: GrainsPaths.defaultExportDirectory.path(percentEncoded: false))
        let model = AppModel(store: store, engine: engine, settings: settings)
        self.store = store
        self.engine = engine
        self.settings = settings
        self.model = model

        let exporter = ExportService(store: store, spec: { [weak model] in model?.spec ?? WeekSpec() }, folder: { [weak settings] in
            settings?.exportFolderURL ?? GrainsPaths.defaultExportDirectory
        })
        exporter.start()
        model.onWeekRollover = { [weak exporter] week in exporter?.weekDidRollOver(finished: week) }
        self.exporter = exporter

        let overlay = OverlayController(model: model)
        overlay.onOpenSettings = { [weak self] in
            self?.overlay?.hide()
            self?.showSettings()
        }
        self.overlay = overlay

        updater = SPUStandardUpdaterController(startingUpdater: !options.isDemo, updaterDelegate: nil, userDriverDelegate: nil)

        statusItem = StatusItemController(model: model, actions: .init(
            toggleOverlay: { [weak self] in self?.overlay?.show() },
            showHistory: { [weak self] in self?.showHistory() },
            showSettings: { [weak self] in self?.showSettings() },
            checkForUpdates: { [weak self] in self?.updater?.checkForUpdates(nil) }
        ))
        hotKey = HotKey { [weak self] in self?.overlay?.toggle() }

        let corner = CornerTrigger { [weak self] in
            guard let overlay = self?.overlay, !overlay.isVisible else { return }
            overlay.show()
        }
        cornerTrigger = corner
        observeChanges { [weak settings, weak corner] in
            guard let settings else { return }
            corner?.configure(enabled: settings.cornerTriggerEnabled, corner: settings.cornerTriggerCorner)
        }

        installObservers(model: model, engine: engine)

        stateTask = Task { [weak self] in
            await engine.start()
            let states = await engine.states()
            if options.show { self?.presentAtLaunch(options) }
            for await state in states {
                self?.model?.apply(state)
            }
        }
    }

    // MARK: Observers

    private func installObservers(model: AppModel, engine: TimerEngine) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .grainsEntriesDidChange, object: nil, queue: .main) { [weak model] _ in
            MainActor.assumeIsolated { model?.entriesDidChange() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleptAt = Date() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        let timer = Timer(timeInterval: 60, repeats: true) { [weak model] _ in
            MainActor.assumeIsolated { model?.clockDidAdvance() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        rolloverTimer = timer
    }

    private func didWake() {
        let slept = sleptAt.map { Date().timeIntervalSince($0) } ?? 0
        sleptAt = nil
        if let engine {
            Task { await engine.noteWake(sleptFor: slept) }
        }
        model?.clockDidAdvance()
    }

    // MARK: Windows

    private func showHistory() {
        guard let store, let engine, let model else { return }
        let history = historyModel ?? HistoryModel(store: store, engine: engine, spec: { [weak model] in model?.spec ?? WeekSpec() })
        historyModel = history
        history.reload()
        windows.show(id: "history", title: "Grains History", resizable: true) {
            HistoryView(model: history)
        }
    }

    private func showSettings() {
        guard let settings else { return }
        let actions = SettingsActions(
            exportAll: { [weak self] in await self?.exporter?.exportAll() ?? (0, 0) },
            exportError: { [weak self] in self?.exporter?.lastError },
            checkForUpdates: { [weak self] in self?.updater?.checkForUpdates(nil) },
            settingsDidChange: { [weak self] in self?.model?.settingsDidChange() }
        )
        windows.show(id: "settings", title: "Grains Settings", resizable: false) {
            SettingsView(settings: settings, actions: actions)
        }
    }

    // MARK: Launch-time presentation (development)

    private func presentAtLaunch(_ options: LaunchOptions) {
        guard let overlay, let model, let engine else { return }
        overlay.show()
        if let path = options.snapshotPath {
            CaretBlink.frozen = true
            Task {
                try? await Task.sleep(for: .seconds(options.demoState == .stopped ? 5 : 2))
                let ok = overlay.writeSnapshot(to: path)
                log.notice("snapshot \(ok ? "written" : "failed", privacy: .public): \(path, privacy: .public)")
                // Not from inside this main-queue job: terminate: runs a nested run loop that
                // does not drain the main queue (D60).
                RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            }
        }
        guard let demo = options.demoState else { return }
        Task {
            switch demo {
            case .idle:
                if await engine.state.isRunning { _ = try? await engine.stop() }
                model.prepareForShow()
            case .running:
                if await !engine.state.isRunning {
                    _ = try? await engine.start(rawText: "Denali - iPad enrollment issue")
                }
            case .stopped:
                if await !engine.state.isRunning {
                    _ = try? await engine.start(rawText: "Spruce - Policy engine")
                    try? await Task.sleep(for: .seconds(3))
                }
                _ = try? await engine.stop()
            case .typing:
                model.mode = .typing
                model.line.set("Global Credit Union - Jamf cert")
                model.edited()
            }
        }
    }

    // MARK: Termination (D7, D60)

    /// Shutdown is synchronous in `applicationWillTerminate`: a `.terminateLater` reply sent
    /// from a Task never arrives when `terminate:` itself was called from a main-queue job
    /// (Sparkle's relaunch, the snapshot path), because AppKit's nested run loop does not
    /// drain the main dispatch queue.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        rolloverTimer?.invalidate()
        stateTask?.cancel()
        exporter?.flushSync()
        engine?.prepareForCleanShutdownSync()
    }

    private func fatalOpen(_ error: any Error) {
        log.fault("Cannot open database: \(String(describing: error), privacy: .public)")
        let alert = NSAlert()
        alert.messageText = "Grains cannot open its database"
        alert.informativeText = "\(GrainsPaths.databaseURL.path(percentEncoded: false))\n\n\(error)"
        alert.alertStyle = .critical
        NSApp.activate()
        alert.runModal()
        NSApp.terminate(nil)
    }
}
