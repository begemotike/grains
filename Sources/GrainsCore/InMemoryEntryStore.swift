import Foundation
import Synchronization

/// An `EntryWriting` kept in memory with the same semantics as `SQLiteEntryStore`
/// (one running entry, soft delete, notifications, kv). For tests, SwiftUI previews and the
/// MCP test suite. Thread-safe via an internal `Mutex`.
public final class InMemoryEntryStore: EntryWriting {
    private struct State {
        var entries: [UUID: Entry] = [:]
        var kv: [String: String] = [:]
    }

    private let state = Mutex(State())
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - entries: initial rows (inserted without validation or notifications).
    ///   - now: wall clock used to bump `updatedAt` and to value running entries in `clientLabels()`.
    public init(entries: [Entry] = [], now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        state.withLock { state in
            for entry in entries { state.entries[entry.id] = entry }
        }
    }

    private var live: [Entry] {
        state.withLock { Array($0.entries.values) }.filter { !$0.isDeleted }
    }

    // MARK: EntryReading

    public func entry(id: UUID) throws -> Entry? {
        state.withLock { $0.entries[id] }.flatMap { $0.isDeleted ? nil : $0 }
    }

    public func runningEntry() throws -> Entry? {
        live.filter(\.isRunning).max { $0.startedAt < $1.startedAt }
    }

    public func entries(overlapping interval: DateInterval) throws -> [Entry] {
        live.filter { entry in
            entry.startedAt < interval.end && (entry.stoppedAt.map { $0 > interval.start } ?? true)
        }
        .sorted(by: Self.oldestFirst)
    }

    public func recentEntries(limit: Int) throws -> [Entry] {
        Array(live.sorted(by: Self.oldestFirst).reversed().prefix(max(0, limit)))
    }

    public func search(_ text: String, limit: Int) throws -> [Entry] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        func matches(_ field: String?) -> Bool {
            field.map { $0.range(of: text, options: .caseInsensitive) != nil } ?? false
        }
        let hits = live.filter { matches($0.rawText) || matches($0.clientText) || matches($0.note) }
        return Array(hits.sorted(by: Self.oldestFirst).reversed().prefix(max(0, limit)))
    }

    public func clientLabels() throws -> [ClientLabelCount] {
        let asOf = now()
        // Group like SQLite's COLLATE NOCASE (ASCII-only case folding).
        let groups = Dictionary(grouping: live.filter { $0.clientText != nil }) {
            Self.asciiLowercased($0.clientText ?? "")
        }
        return groups.values.compactMap { members -> ClientLabelCount? in
            guard let latest = members.max(by: { $0.startedAt < $1.startedAt }),
                  let label = latest.clientText else { return nil }
            return ClientLabelCount(
                clientText: label,
                clientID: latest.clientID,
                count: members.count,
                totalSeconds: members.reduce(0) { $0 + $1.duration(asOf: asOf) }
            )
        }
        .sorted { Self.asciiLowercased($0.clientText) < Self.asciiLowercased($1.clientText) }
    }

    public func earliestStart() throws -> Date? {
        live.map(\.startedAt).min()
    }

    // MARK: EntryWriting

    public func insert(_ entry: Entry) throws {
        try commit([.insert(entry)])
    }

    public func update(_ entry: Entry) throws {
        try commit([.update(entry)])
    }

    public func commit(_ writes: [EntryWrite]) throws {
        guard !writes.isEmpty else { return }
        let timestamp = now()
        try state.withLock { state in
            var staged = state.entries
            for write in writes {
                switch write {
                case .insert(let entry):
                    guard staged[entry.id] == nil else { throw EntryStoreError.duplicateID(entry.id) }
                    staged[entry.id] = entry
                case .update(var entry):
                    guard let stored = staged[entry.id] else { throw EntryStoreError.notFound(entry.id) }
                    if entry.updatedAt <= stored.updatedAt {
                        entry.updatedAt = max(timestamp, stored.updatedAt)
                    }
                    staged[entry.id] = entry
                }
                // Mirrors the partial unique index, checked per statement like SQLite.
                if staged.values.filter({ $0.isRunning && !$0.isDeleted }).count > 1 {
                    throw EntryStoreError.anotherEntryRunning
                }
            }
            state.entries = staged
        }
        EntryChangeNotifier.post(from: self, ids: writes.map(\.entryID))
    }

    public func softDelete(id: UUID, at date: Date) throws {
        try state.withLock { state in
            guard var entry = state.entries[id] else { throw EntryStoreError.notFound(id) }
            guard entry.deletedAt == nil else { return }
            entry.deletedAt = date
            entry.updatedAt = date
            state.entries[id] = entry
        }
        EntryChangeNotifier.post(from: self, ids: [id])
    }

    public func writeHeartbeat(entryID: UUID, at date: Date) throws {
        apply(HeartbeatCoding.pairs(entryID: entryID, at: date))
    }

    public func readHeartbeat() throws -> (entryID: UUID, at: Date)? {
        let (id, at) = state.withLock { ($0.kv[EntryStoreKey.heartbeatEntryID], $0.kv[EntryStoreKey.heartbeatAt]) }
        return HeartbeatCoding.decode(entryID: id, at: at)
    }

    public func clearHeartbeat() throws {
        apply(HeartbeatCoding.clearPairs)
    }

    public func readValue(forKey key: String) throws -> String? {
        state.withLock { $0.kv[key] }
    }

    public func writeValue(_ value: String?, forKey key: String) throws {
        apply([(key, value)])
    }

    // MARK: Helpers

    private func apply(_ pairs: [(key: String, value: String?)]) {
        state.withLock { state in
            for pair in pairs { state.kv[pair.key] = pair.value }
        }
    }

    private static func oldestFirst(_ lhs: Entry, _ rhs: Entry) -> Bool {
        lhs.startedAt == rhs.startedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.startedAt < rhs.startedAt
    }

    private static func asciiLowercased(_ string: String) -> String {
        String(string.unicodeScalars.map { scalar in
            ("A"..."Z").contains(scalar) ? Character(Unicode.Scalar(scalar.value + 32) ?? scalar) : Character(scalar)
        })
    }
}
