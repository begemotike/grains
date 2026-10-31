import Foundation

/// Read-only view of a Grains database, returned by `SQLiteEntryStore.openReadOnly(at:)`.
/// Deliberately conforms to `EntryReading` only, so writing is a compile-time error, and the
/// connection itself is `SQLITE_OPEN_READONLY` + `query_only` as a second line of defence.
final class SQLiteEntryReader: EntryReading, @unchecked Sendable {
    let database: SQLiteEntryDatabase

    init(database: SQLiteEntryDatabase) {
        self.database = database
    }

    func entry(id: UUID) throws -> Entry? { try database.entry(id: id) }
    func runningEntry() throws -> Entry? { try database.runningEntry() }
    func entries(overlapping interval: DateInterval) throws -> [Entry] { try database.entries(overlapping: interval) }
    func recentEntries(limit: Int) throws -> [Entry] { try database.recentEntries(limit: limit) }
    func search(_ text: String, limit: Int) throws -> [Entry] { try database.search(text, limit: limit) }
    func clientLabels() throws -> [ClientLabelCount] { try database.clientLabels() }
    func earliestStart() throws -> Date? { try database.earliestStart() }
}
