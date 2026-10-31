import Foundation
import GrainsCore
import GrainsReports
import Observation
import os

/// The overlay's visual state (docs/design.md "States").
enum OverlayPhase: Equatable, Sendable {
    case idle, typing, running, stopped
}

/// Single source of UI truth (docs/architecture.md): a mirror of the timer, the visible week,
/// its series and stats, recent entries, the input mode and the line being edited.
/// Every number shown comes from `GrainsReports`; nothing here sums durations.
@MainActor @Observable
final class AppModel {
    @ObservationIgnored let store: any EntryWriting
    @ObservationIgnored let engine: TimerEngine
    let settings: AppSettings

    // MARK: Timer mirror

    private(set) var timer: TimerState = .idle
    /// The entry stopped most recently in this session while nothing else started since.
    private(set) var stoppedEntry: Entry?
    /// The counter value at the moment of the stop (design.md "Stopped").
    private(set) var frozenElapsed: Duration = .zero
    /// Bumped on every switch (commit while running) to drive the switch transition.
    private(set) var switchPulse = 0

    // MARK: Input

    var mode: InputMode = .control
    var line = LineEditor()
    /// The line shows an entry's text (running, stopped, recalled) rather than a draft.
    var lineIsCommitted = false
    /// Time of the last edit, for the caret blink rule. Set on the key path; read by the caret.
    var lastEdit = Date.distantPast
    private var recentCursor: Int?

    // MARK: Week

    private(set) var currentWeek: Week
    private(set) var visibleWeek: Week
    private(set) var series: WeekSeries
    /// Headline numbers for the current week and today.
    private(set) var stats: Stats
    /// Distinct recent entry texts, newest first, for ↑/↓.
    private(set) var recentTexts: [String] = []
    /// Bumped when the chart should replay its draw-in (week navigation, rollover, show).
    private(set) var chartGeneration = 0
    private(set) var lastError: String?

    @ObservationIgnored private var visibleEntries: [Entry] = []
    @ObservationIgnored private var currentEntries: [Entry] = []
    @ObservationIgnored private var commandTail: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "net.outofajam.Grains", category: "model")
    /// Called with the finished week when the week rolls over (exporter hook).
    @ObservationIgnored var onWeekRollover: ((Week) -> Void)?

    init(store: any EntryWriting, engine: TimerEngine, settings: AppSettings, now: Date = Date()) {
        self.store = store
        self.engine = engine
        self.settings = settings
        let spec = WeekSpec(startsOn: settings.weekStartsOn)
        let week = spec.week(containing: now)
        currentWeek = week
        visibleWeek = week
        series = WeekSeries.compute(entries: [], week: week, now: now, targetHours: settings.targetHours)
        stats = Stats.compute(entries: [], week: week, today: spec.today(at: now), now: now)
        reloadEntries()
        recompute(now: now)
    }

    var spec: WeekSpec { WeekSpec(startsOn: settings.weekStartsOn) }
    var isViewingCurrentWeek: Bool { visibleWeek == currentWeek }

    // MARK: Derived presentation

    var phase: OverlayPhase {
        if mode == .typing { return .typing }
        if timer.isRunning { return .running }
        if stoppedEntry != nil && lineIsCommitted { return .stopped }
        return .idle
    }

    /// The session counter: live while running, frozen after a stop, zero otherwise.
    var displayedElapsed: Duration {
        if timer.isRunning { return timer.elapsed }
        return stoppedEntry != nil ? frozenElapsed : .zero
    }

    /// Week total shown in the stats row: the visible week's tracked hours.
    var visibleWeekHours: Double { isViewingCurrentWeek ? stats.weekHours : series.totalHours }

    var modeLabel: String {
        switch phase {
        case .typing: return timer.isRunning ? "return to switch" : "return to start"
        case .running: return "space to stop"
        case .stopped: return "space to resume · type for new"
        case .idle:
            if !line.isEmpty { return "space to start" }
            return recentTexts.isEmpty ? "type to begin" : "type to begin · space to restart last"
        }
    }

    /// One-line crash recovery notice (interaction.md), or nil.
    var recoveryNotice: String? {
        guard let entry = timer.recovered else { return nil }
        let stop = entry.stoppedAt ?? entry.startedAt
        return "Recovered: stopped at \(Formatting.time(stop)) after crash · R to resume · A to accept"
    }

    /// Menu bar title `HH:MM` while running (when enabled).
    var menuBarTitle: String? {
        guard settings.showElapsedInMenuBar, timer.isRunning else { return nil }
        return Formatting.shortClock(timer.elapsed)
    }

    var inputContext: InputStateMachine.Context {
        .init(mode: mode, lineText: line.text, lineIsCommitted: lineIsCommitted, hasRecovery: timer.recovered != nil)
    }

    // MARK: Engine mirror

    /// Mirror one engine state into the model.
    func apply(_ new: TimerState) {
        let old = timer
        timer = new
        if old.running?.id != new.running?.id {
            if let running = new.running {
                stoppedEntry = nil
                if mode == .control && (lineIsCommitted || line.isEmpty) {
                    line.set(running.rawText)
                    lineIsCommitted = true
                }
                if old.running != nil { switchPulse += 1 }
            } else if let previous = old.running {
                frozenElapsed = old.elapsed
                stoppedEntry = previous
            }
            reloadEntries()
        }
        recompute()
    }

    // MARK: Commands (called by OverlayController and the menu)

    /// Space semantics (interaction.md): stop if running; else start the line's text; else
    /// restart the most recent entry. Decided inside the serialized command chain so two
    /// quick presses never race.
    func toggleTimer() {
        let text = line.text
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        recentCursor = nil
        enqueue { [weak self] engine in
            if await engine.state.isRunning {
                // A stop leaves the line alone: a draft typed while running stays a draft
                // instead of being shown as the stopped entry.
                try await engine.stop()
            } else if hasText {
                await self?.markLineCommitted()
                try await engine.start(rawText: text)
            } else {
                try await engine.toggle()
            }
        }
    }

    private func markLineCommitted() { lineIsCommitted = true }

    /// Return in typing mode: stop the running entry (if any) and start `text`.
    func commit(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lineIsCommitted = true
        recentCursor = nil
        mode = .control
        enqueue { engine in try await engine.start(rawText: text) }
    }

    func stop() { enqueue { engine in try await engine.stop() } }
    /// Menu "Start": restart the most recent entry's text (engine toggle while idle).
    func restartLast() {
        enqueue { engine in
            if await !engine.state.isRunning { try await engine.toggle() }
        }
    }
    func undoStop() { enqueue { engine in try await engine.undoLastStop() } }
    func resumeRecovered() { enqueue { engine in try await engine.resumeRecovered() } }
    func acceptRecovered() { enqueue { engine in try await engine.acceptRecovered() } }

    /// ↑/↓: put a recent entry's text in the line, ready to restart with Space.
    func cycleRecent(_ delta: Int) {
        guard !recentTexts.isEmpty else { return }
        let next: Int
        if let cursor = recentCursor {
            next = cursor + delta
        } else {
            next = delta > 0 ? 0 : -1
        }
        guard recentTexts.indices.contains(next) else {
            if next < 0, recentCursor != nil {
                recentCursor = nil
                line.clear()
                lineIsCommitted = false
            }
            return
        }
        recentCursor = next
        line.set(recentTexts[next])
        lineIsCommitted = true
    }

    func showPreviousWeek() {
        visibleWeek = visibleWeek.previous(spec: spec)
        weekNavigated()
    }

    func showNextWeek() {
        guard visibleWeek < currentWeek else { return }
        visibleWeek = visibleWeek.next(spec: spec)
        weekNavigated()
    }

    /// Line edits from the key path mark the line as a draft.
    func edited() {
        lineIsCommitted = false
        recentCursor = nil
        lastEdit = Date()
    }

    /// Reset per-summon state: control mode, current week, line synced to the timer unless
    /// the user left a draft.
    func prepareForShow() {
        mode = .control
        recentCursor = nil
        if visibleWeek != currentWeek { visibleWeek = currentWeek }
        let isDraft = !lineIsCommitted && !line.isEmpty
        if !isDraft {
            if let running = timer.running {
                line.set(running.rawText)
                lineIsCommitted = true
            } else if stoppedEntry == nil {
                line.clear()
                lineIsCommitted = false
            }
        }
        reloadEntries()
        recompute()
        chartGeneration += 1
    }

    // MARK: Recompute

    /// The store changed (any process write in this app).
    func entriesDidChange() {
        reloadEntries()
        recompute()
    }

    /// The 60 s rollover timer and wake both land here.
    func clockDidAdvance(now: Date = Date()) {
        let week = spec.week(containing: now)
        if week != currentWeek {
            let finished = currentWeek
            let followed = visibleWeek == currentWeek
            currentWeek = week
            if followed || visibleWeek > week {
                visibleWeek = week
                chartGeneration += 1
            }
            reloadEntries()
            onWeekRollover?(finished)
        }
        recompute(now: now)
    }

    /// Week start or target changed in Settings.
    func settingsDidChange() {
        let now = Date()
        currentWeek = spec.week(containing: now)
        visibleWeek = currentWeek
        chartGeneration += 1
        reloadEntries()
        recompute(now: now)
    }

    private func weekNavigated() {
        chartGeneration += 1
        reloadEntries()
        recompute()
    }

    private func reloadEntries() {
        do {
            visibleEntries = try store.entries(overlapping: visibleWeek.interval)
            currentEntries = visibleWeek == currentWeek ? visibleEntries : try store.entries(overlapping: currentWeek.interval)
            var seen = Set<String>()
            recentTexts = try store.recentEntries(limit: 60)
                .map(\.rawText)
                .filter { seen.insert($0).inserted }
                .prefix(20)
                .map { $0 }
        } catch {
            report(error)
        }
    }

    private func recompute(now: Date = Date()) {
        let spec = spec
        series = WeekSeries.compute(entries: visibleEntries, week: visibleWeek, now: now, targetHours: settings.targetHours)
        stats = Stats.compute(entries: currentEntries, week: currentWeek, today: spec.today(at: now), now: now)
    }

    // MARK: Serialized engine commands

    private func enqueue(_ operation: @escaping @Sendable (TimerEngine) async throws -> Void) {
        let previous = commandTail
        let engine = engine
        commandTail = Task { [weak self] in
            await previous?.value
            do {
                try await operation(engine)
            } catch {
                self?.report(error)
            }
        }
    }

    private func report(_ error: any Error) {
        lastError = String(describing: error)
        log.error("\(String(describing: error), privacy: .public)")
    }
}
