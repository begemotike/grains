import Foundation
import GrainsCore
import GrainsReports
import Observation

/// State of the History window (D22): one week of entries, newest first, with editing,
/// soft delete and restore. Restoring is limited to entries deleted in this session because
/// the store API exposes no listing of deleted rows (D53).
@MainActor @Observable
final class HistoryModel {
    @ObservationIgnored private let store: any EntryWriting
    @ObservationIgnored private let engine: TimerEngine
    @ObservationIgnored private let spec: () -> WeekSpec
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private(set) var week: Week
    private(set) var entries: [Entry] = []
    /// Week total from `GrainsReports`.
    private(set) var weekHours: Double = 0
    /// Deleted in this session, newest first; each can be restored.
    private(set) var recentlyDeleted: [Entry] = []
    var errorMessage: String?

    init(store: any EntryWriting, engine: TimerEngine, spec: @escaping () -> WeekSpec) {
        self.store = store
        self.engine = engine
        self.spec = spec
        week = spec().week(containing: Date())
        reload()
        observer = NotificationCenter.default.addObserver(forName: .grainsEntriesDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    var isCurrentWeek: Bool { week == spec().week(containing: Date()) }

    func reload() {
        let now = Date()
        do {
            let list = try store.entries(overlapping: week.interval)
            entries = list.sorted { $0.startedAt > $1.startedAt }
            weekHours = WeekSeries.compute(entries: list, week: week, now: now, targetHours: nil).totalHours
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func previousWeek() { week = week.previous(spec: spec()); reload() }
    func nextWeek() { guard !isCurrentWeek else { return }; week = week.next(spec: spec()); reload() }
    func currentWeek() { week = spec().week(containing: Date()); reload() }

    /// Entries grouped by local day, newest day first.
    var days: [(day: Date, entries: [Entry])] {
        let calendar = spec().calendar
        let groups = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    /// Validates and saves an edit. `newText` is nil when the user did not touch the text,
    /// so `rawText` is only rewritten on an explicit edit (then client/note are re-parsed).
    @discardableResult
    func save(_ entry: Entry, start: Date, stop: Date?, newText: String?) -> Bool {
        if let stop, stop < start {
            errorMessage = "The stop time is before the start time."
            return false
        }
        let now = Date()
        if start > now {
            errorMessage = "The start time is in the future."
            return false
        }
        if let stop, !entry.isRunning, stop > now {
            errorMessage = "The stop time is in the future."
            return false
        }
        var updated = entry
        updated.startedAt = start
        updated.stoppedAt = entry.isRunning ? nil : stop
        if let newText {
            let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "The text cannot be empty."
                return false
            }
            if newText != entry.rawText {
                let parsed = EntryParser.parse(newText)
                updated.rawText = newText
                updated.clientText = parsed.clientText
                updated.note = parsed.note
            }
        }
        updated.updatedAt = Date()
        return write { try store.update(updated) }
    }

    func delete(_ entry: Entry) {
        if write({ try store.softDelete(id: entry.id, at: Date()) }) {
            recentlyDeleted.insert(entry, at: 0)
        }
    }

    func restore(_ entry: Entry) {
        var restored = entry
        restored.deletedAt = nil
        restored.updatedAt = Date()
        if write({ try store.update(restored) }) {
            recentlyDeleted.removeAll { $0.id == entry.id }
        }
    }

    /// Undo the most recent delete.
    func undoDelete() {
        if let last = recentlyDeleted.first { restore(last) }
    }

    /// Entries in this week that overlap `entry` (shown as a warning, not blocked).
    func overlaps(_ entry: Entry) -> Bool {
        let now = Date()
        let a = DateInterval(start: entry.startedAt, end: max(entry.startedAt, entry.stoppedAt ?? now))
        return entries.contains { other in
            guard other.id != entry.id else { return false }
            let b = DateInterval(start: other.startedAt, end: max(other.startedAt, other.stoppedAt ?? now))
            return a.start < b.end && b.start < a.end
        }
    }

    private func write(_ body: () throws -> Void) -> Bool {
        do {
            try body()
            errorMessage = nil
            reload()
            let engine = engine
            Task { await engine.reload() }
            return true
        } catch EntryStoreError.anotherEntryRunning {
            errorMessage = "Another entry is already running."
        } catch {
            errorMessage = String(describing: error)
        }
        return false
    }
}
