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

    /// Begin observing `.grainsEntriesDidChange`.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .grainsEntriesDidChange, object: nil, queue: .main) { [weak self] note in
            let ids = note.grainsChangedEntryIDs
            MainActor.assumeIsolated { self?.entriesChanged(ids) }
        }
    }

    /// Map changed ids to weeks and schedule them.
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

    /// Week rollover: write the finished week once more (final).
    func weekDidRollOver(finished: Week) {
        pending[finished]?.cancel()
        pending[finished] = nil
        Task { await write(finished, force: true) }
    }

    /// Settings → "Export all weeks now": every week from the earliest entry to now.
    /// Returns the number of files written.
    @discardableResult
    func exportAll() async -> Int {
        guard let earliest = (try? store.earliestStart()) ?? nil else { return 0 }
        var count = 0
        for week in ExportWeekMapping.allWeeks(from: earliest, through: Date(), spec: spec()) {
            if await write(week) { count += 1 }
        }
        return count
    }

    /// Writes one week. A week with no entries is written only when its file already exists
    /// (so deleting a week's last entry empties the file, but empty weeks create no files).
    @discardableResult
    private func write(_ week: Week, force: Bool = false) async -> Bool {
        let store = store
        let spec = spec()
        let url = folder().appending(path: CSVExporter.fileName(for: week), directoryHint: .notDirectory)
        let result: Result<Bool, any Error> = await Task.detached(priority: .utility) {
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
        }.value
        switch result {
        case .success(let wrote):
            if wrote { lastError = nil }
            return wrote
        case .failure(let error):
            lastError = "\(url.lastPathComponent): \(error.localizedDescription)"
            log.error("CSV export failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
