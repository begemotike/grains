import Foundation
import GrainsCore
import GrainsReports
import os

/// Keeps `<folder>/Grains-YYYY-Www.csv` in sync with the store (D17, docs/csv-export.md):
/// a change schedules the affected weeks, each written at most once per 5 s; rollover writes
/// the finished week; `exportAll()` regenerates everything. Writes are atomic.
@MainActor
final class ExportService {
    /// Debounce per week (D17).
    static let debounce: Duration = .seconds(5)

    private let store: any EntryReading
    private let spec: () -> WeekSpec
    private let folder: () -> URL
    private let log = Logger(subsystem: "net.outofajam.Grains", category: "export")
    private var pending: [Week: Task<Void, Never>] = [:]
    /// Weeks each entry occupied when last seen, so a moved or deleted entry's old week is
    /// rewritten too.
    private var knownWeeks: [UUID: [Week]] = [:]
    private var observer: (any NSObjectProtocol)?

    /// Last write error, shown in Settings.
    private(set) var lastError: String?

    init(store: any EntryReading, spec: @escaping () -> WeekSpec, folder: @escaping () -> URL) {
        self.store = store
        self.spec = spec
        self.folder = folder
    }

    /// Prime the known weeks of every live entry, then begin observing
    /// `.grainsEntriesDidChange`. Priming lets a delete or move of an entry created before
    /// this launch rewrite its old week (the deleted row can no longer be read).
    func start(now: Date = Date()) {
        guard observer == nil else { return }
        primeKnownWeeks(now: now)
        observer = NotificationCenter.default.addObserver(forName: .grainsEntriesDidChange, object: nil, queue: .main) { [weak self] note in
            let ids = note.grainsChangedEntryIDs
            MainActor.assumeIsolated { self?.entriesChanged(ids) }
        }
    }

    private func primeKnownWeeks(now: Date) {
        let spec = spec()
        do {
            let earliest = try store.earliestStart() ?? now
            let interval = DateInterval(start: min(earliest, now), end: now.addingTimeInterval(7 * 86_400))
            for entry in try store.entries(overlapping: interval) {
                knownWeeks[entry.id] = ExportWeekMapping.weeks(for: entry, spec: spec, now: now)
            }
        } catch {
            log.error("Cannot prime export weeks: \(String(describing: error), privacy: .public)")
        }
    }

    /// Weeks with a debounced write waiting (tests and diagnostics).
    var pendingWeeks: [Week] { pending.keys.sorted() }

    /// Map changed ids to weeks and schedule them. A changed id the store no longer returns
    /// (soft-deleted) schedules the weeks it was last known to occupy.
    func entriesChanged(_ ids: [UUID]) {
        let now = Date()
        let spec = spec()
        var changed: [Entry] = []
        var previous: [Week] = []
        for id in ids {
            previous += knownWeeks[id] ?? []
            if let entry = try? store.entry(id: id) {
                changed.append(entry)
                knownWeeks[id] = ExportWeekMapping.weeks(for: entry, spec: spec, now: now)
            } else {
                knownWeeks[id] = nil
            }
        }
        for week in ExportWeekMapping.weeksToRewrite(changed: changed, previouslyKnown: previous, spec: spec, now: now) {
            schedule(week)
        }
    }

    /// Coalescing debounce: the first change starts a 5 s window; later changes in the
    /// window ride along. Writes therefore happen at most once per 5 s per week and a steady
    /// stream of changes cannot postpone them forever.
    func schedule(_ week: Week) {
        guard pending[week] == nil else { return }
        pending[week] = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.pending[week] = nil
            await self?.write(week)
        }
    }

    /// Quit: cancel the debounce timers and write every pending week now, synchronously on
    /// the main thread (`applicationWillTerminate` cannot await).
    func flushSync() {
        let weeks = pending.keys.sorted()
        for task in pending.values { task.cancel() }
        pending = [:]
        let spec = spec()
        let folder = folder()
        for week in weeks {
            record(Self.writeFile(week, store: store, spec: spec, folder: folder, force: false), week: week)
        }
    }

    /// Week rollover: write the finished week once more (final).
    func weekDidRollOver(finished: Week) {
        pending[finished]?.cancel()
        pending[finished] = nil
        Task { await write(finished, force: true) }
    }

    /// Settings → "Export all weeks now": every week from the earliest entry to now.
    /// Returns the number of files written and failed; `lastError` names the last failure.
    @discardableResult
    func exportAll() async -> (written: Int, failed: Int) {
        let earliest: Date?
        do {
            earliest = try store.earliestStart()
        } catch {
            lastError = "Cannot read entries: \(error.localizedDescription)"
            return (0, 1)
        }
        guard let earliest else { return (0, 0) }
        var written = 0
        var failed = 0
        for week in ExportWeekMapping.allWeeks(from: earliest, through: Date(), spec: spec()) {
            switch await write(week) {
            case .written: written += 1
            case .failed: failed += 1
            case .skipped: break
            }
        }
        return (written, failed)
    }

    /// Writes one week. A week with no entries is written only when its file already exists
    /// (so deleting a week's last entry empties the file, but empty weeks create no files).
    enum WriteOutcome { case written, skipped, failed }

    @discardableResult
    private func write(_ week: Week, force: Bool = false) async -> WriteOutcome {
        let store = store
        let spec = spec()
        let folder = folder()
        let result = await Task.detached(priority: .utility) {
            Self.writeFile(week, store: store, spec: spec, folder: folder, force: force)
        }.value
        return record(result, week: week)
    }

    @discardableResult
    private func record(_ result: Result<Bool, any Error>, week: Week) -> WriteOutcome {
        switch result {
        case .success(let wrote):
            guard wrote else { return .skipped }
            lastError = nil
            return .written
        case .failure(let error):
            lastError = "\(CSVExporter.fileName(for: week)): \(error.localizedDescription)"
            log.error("CSV export failed: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    /// The file write itself; safe off the main actor.
    private nonisolated static func writeFile(_ week: Week, store: any EntryReading, spec: WeekSpec, folder: URL, force: Bool) -> Result<Bool, any Error> {
        let url = folder.appending(path: CSVExporter.fileName(for: week), directoryHint: .notDirectory)
        do {
            let now = Date()
            let entries = try store.entries(overlapping: week.interval)
            let exists = FileManager.default.fileExists(atPath: url.path)
            guard !entries.isEmpty || exists || force else { return .success(false) }
            if entries.isEmpty && !exists { return .success(false) }
            let csv = CSVExporter(spec: spec).csv(for: week, entries: entries, now: now)
            try AtomicFileWriter.write(Data(csv.utf8), to: url)
            return .success(true)
        } catch {
            return .failure(error)
        }
    }
}
