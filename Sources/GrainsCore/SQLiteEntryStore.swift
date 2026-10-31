import Foundation

/// The app's read/write store over `grains.sqlite` (WAL, busy_timeout 5000 ms).
///
/// Safe to call from any thread: every call is serialized on one internal serial queue.
/// Successful entry writes post `.grainsEntriesDidChange` on the main queue with the store as
/// object and `userInfo["ids"]` = the touched `[UUID]`. Heartbeat/kv writes do not post.
public final class SQLiteEntryStore: EntryWriting, @unchecked Sendable {
    private let database: SQLiteEntryDatabase

    private init(database: SQLiteEntryDatabase) {
        self.database = database
    }

    /// Opens (creating if needed) the database read/write and applies pending migrations.
    /// - Parameter now: wall clock used to bump `updatedAt` and to value running entries in
    ///   `clientLabels()`; injectable for tests.
    public static func open(at url: URL, now: @escaping @Sendable () -> Date = { Date() }) throws -> SQLiteEntryStore {
        SQLiteEntryStore(database: try SQLiteEntryDatabase(url: url, readOnly: false, now: now))
    }

    /// Opens an existing database with `SQLITE_OPEN_READONLY` (the MCP server's path).
    /// The returned value only conforms to `EntryReading`; it cannot be used to write.
    /// Throws when the file is missing or was never initialized by Grains.
    public static func openReadOnly(at url: URL, now: @escaping @Sendable () -> Date = { Date() }) throws -> some EntryReading {
        SQLiteEntryReader(database: try SQLiteEntryDatabase(url: url, readOnly: true, now: now))
    }

    // MARK: EntryReading

    public func entry(id: UUID) throws -> Entry? { try database.entry(id: id) }
    public func runningEntry() throws -> Entry? { try database.runningEntry() }
    public func entries(overlapping interval: DateInterval) throws -> [Entry] { try database.entries(overlapping: interval) }
    public func recentEntries(limit: Int) throws -> [Entry] { try database.recentEntries(limit: limit) }
    public func search(_ text: String, limit: Int) throws -> [Entry] { try database.search(text, limit: limit) }
    public func clientLabels() throws -> [ClientLabelCount] { try database.clientLabels() }
    public func earliestStart() throws -> Date? { try database.earliestStart() }

    // MARK: EntryWriting

    public func insert(_ entry: Entry) throws {
        try commit([.insert(entry)])
    }

    public func update(_ entry: Entry) throws {
        try commit([.update(entry)])
    }

    public func commit(_ writes: [EntryWrite]) throws {
        guard !writes.isEmpty else { return }
        try database.commit(writes)
        EntryChangeNotifier.post(from: self, ids: writes.map(\.entryID))
    }

    public func softDelete(id: UUID, at date: Date) throws {
        try database.softDelete(id: id, at: date)
        EntryChangeNotifier.post(from: self, ids: [id])
    }

    public func writeHeartbeat(entryID: UUID, at date: Date) throws {
        try database.writeValues(HeartbeatCoding.pairs(entryID: entryID, at: date))
    }

    public func readHeartbeat() throws -> (entryID: UUID, at: Date)? {
        HeartbeatCoding.decode(
            entryID: try database.readValue(forKey: EntryStoreKey.heartbeatEntryID),
            at: try database.readValue(forKey: EntryStoreKey.heartbeatAt)
        )
    }

    public func clearHeartbeat() throws {
        try database.writeValues(HeartbeatCoding.clearPairs)
    }

    public func readValue(forKey key: String) throws -> String? {
        try database.readValue(forKey: key)
    }

    public func writeValue(_ value: String?, forKey key: String) throws {
        try database.writeValues([(key, value)])
    }
}
