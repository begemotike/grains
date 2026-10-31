import Foundation
import SQLite3

/// Shared engine behind `SQLiteEntryStore` and the read-only reader: one connection, one
/// serial queue. Every method hops onto the queue synchronously, which is what makes the
/// public wrappers safe to call from any thread (`@unchecked Sendable` with the queue as the
/// justification, docs/architecture.md).
final class SQLiteEntryDatabase: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let queue: DispatchQueue
    let now: @Sendable () -> Date

    init(url: URL, readOnly: Bool, now: @escaping @Sendable () -> Date) throws {
        let connection = try SQLiteConnection(path: url.path(percentEncoded: false), readOnly: readOnly)
        try connection.exec("PRAGMA busy_timeout = 5000")
        if readOnly {
            try connection.exec("PRAGMA query_only = 1")
            let version = try connection.userVersion()
            if version == 0 { throw EntryStoreError.notAGrainsDatabase }
            if version > SQLiteSchema.currentVersion { throw EntryStoreError.unsupportedSchemaVersion(version) }
        } else {
            try connection.exec("PRAGMA journal_mode = WAL")
            try connection.exec("PRAGMA foreign_keys = ON")
            try Self.migrate(connection)
        }
        try connection.registerContainsFunction()
        self.connection = connection
        self.queue = DispatchQueue(label: "net.outofajam.grains.sqlite.\(readOnly ? "ro" : "rw")")
        self.now = now
    }

    private static func migrate(_ connection: SQLiteConnection) throws {
        let version = try connection.userVersion()
        if version > SQLiteSchema.currentVersion { throw EntryStoreError.unsupportedSchemaVersion(version) }
        guard version < SQLiteSchema.currentVersion else { return }
        try connection.transaction {
            for index in version..<SQLiteSchema.currentVersion {
                try connection.exec(SQLiteSchema.migrations[index])
            }
            // PRAGMA takes no bound parameters; the value is our own integer constant.
            try connection.exec("PRAGMA user_version = \(SQLiteSchema.currentVersion)")
        }
    }

    /// Runs `body` on the serial queue.
    func sync<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        try queue.sync { try body(connection) }
    }

    var isReadOnly: Bool { (try? sync { $0.isReadOnly }) ?? true }

    // MARK: Reads

    private static let select = "SELECT \(SQLiteSchema.entryColumns) FROM entries"

    func entries(_ whereClause: String, _ values: [SQLiteValue] = []) throws -> [Entry] {
        try sync { db in
            try db.query("\(Self.select) \(whereClause)", values) { SQLiteSchema.entry(from: $0) }
                .compactMap { $0 }
        }
    }

    func entry(id: UUID) throws -> Entry? {
        try entries("WHERE id = ? AND deleted_at IS NULL", [SQLiteValue(id)]).first
    }

    func runningEntry() throws -> Entry? {
        try entries("WHERE stopped_at IS NULL AND deleted_at IS NULL ORDER BY started_at DESC LIMIT 1").first
    }

    func entries(overlapping interval: DateInterval) throws -> [Entry] {
        try entries(
            """
            WHERE deleted_at IS NULL AND started_at < ? AND (stopped_at IS NULL OR stopped_at > ?)
            ORDER BY started_at ASC
            """,
            [SQLiteValue(interval.end), SQLiteValue(interval.start)]
        )
    }

    func recentEntries(limit: Int) throws -> [Entry] {
        try entries("WHERE deleted_at IS NULL ORDER BY started_at DESC LIMIT ?", [.integer(Int64(max(0, limit)))])
    }

    func search(_ text: String, limit: Int) throws -> [Entry] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try entries(
            """
            WHERE deleted_at IS NULL AND (grains_icontains(raw_text, ?1)
              OR grains_icontains(coalesce(client_text, ''), ?1)
              OR grains_icontains(coalesce(note, ''), ?1))
            ORDER BY started_at DESC LIMIT ?2
            """,
            [.text(text), .integer(Int64(max(0, limit)))]
        )
    }

    func clientLabels() throws -> [ClientLabelCount] {
        let now = self.now().timeIntervalSince1970
        // Bare client_text/client_id come from the row with max(started_at): the most recent
        // spelling of the label wins (SQLite's documented min/max bare-column behaviour).
        return try sync { db in
            try db.query(
                """
                SELECT client_text, client_id, max(started_at), count(*),
                       sum(CASE WHEN stopped_at IS NULL
                                THEN (CASE WHEN ?1 > started_at THEN ?1 - started_at ELSE 0 END)
                                ELSE coalesce(duration_seconds, 0) END)
                FROM entries
                WHERE deleted_at IS NULL AND client_text IS NOT NULL
                GROUP BY client_text COLLATE NOCASE
                ORDER BY client_text COLLATE NOCASE ASC
                """,
                [.real(now)]
            ) { row in
                ClientLabelCount(
                    clientText: row.string(0),
                    clientID: row.optionalString(1).flatMap(UUID.init(uuidString:)),
                    count: Int(row.int64(3)),
                    totalSeconds: row.double(4)
                )
            }
        }
    }

    func earliestStart() throws -> Date? {
        try sync { db in
            try db.query("SELECT min(started_at) FROM entries WHERE deleted_at IS NULL") {
                $0.optionalDouble(0).map(Date.init(timeIntervalSince1970:))
            }.first ?? nil
        }
    }

    // MARK: Writes (used by SQLiteEntryStore only)

    func commit(_ writes: [EntryWrite]) throws {
        try sync { db in
            try db.transaction {
                for write in writes {
                    switch write {
                    case .insert(let entry): try Self.insert(entry, db)
                    case .update(let entry): try self.update(entry, db)
                    }
                }
            }
        }
    }

    private static func insert(_ entry: Entry, _ db: SQLiteConnection) throws {
        do {
            try db.run(
                "INSERT INTO entries (\(SQLiteSchema.entryColumns), duration_seconds) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                try SQLiteSchema.values(for: entry)
            )
        } catch let error as SQLiteError {
            throw Self.mapConstraint(error, id: entry.id)
        }
    }

    private func update(_ entry: Entry, _ db: SQLiteConnection) throws {
        let stored = try db.query("SELECT updated_at FROM entries WHERE id = ?", [SQLiteValue(entry.id)]) {
            Date(timeIntervalSince1970: $0.double(0))
        }
        guard let storedUpdatedAt = stored.first else { throw EntryStoreError.notFound(entry.id) }
        var entry = entry
        if entry.updatedAt <= storedUpdatedAt {
            entry.updatedAt = max(now(), storedUpdatedAt)
        }
        var values = try SQLiteSchema.values(for: entry)
        values.append(SQLiteValue(entry.id))
        do {
            try db.run(
                """
                UPDATE entries SET id = ?, raw_text = ?, client_text = ?, note = ?, client_id = ?,
                  started_at = ?, stopped_at = ?, created_at = ?, updated_at = ?, deleted_at = ?,
                  metadata = ?, duration_seconds = ?
                WHERE id = ?
                """,
                values
            )
        } catch let error as SQLiteError {
            throw Self.mapConstraint(error, id: entry.id)
        }
    }

    func softDelete(id: UUID, at date: Date) throws {
        try sync { db in
            let exists = try db.query("SELECT deleted_at FROM entries WHERE id = ?", [SQLiteValue(id)]) {
                $0.isNull(0)
            }
            guard let notYetDeleted = exists.first else { throw EntryStoreError.notFound(id) }
            guard notYetDeleted else { return }
            try db.run(
                "UPDATE entries SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2",
                [SQLiteValue(date), SQLiteValue(id)]
            )
        }
    }

    // Extended result codes are C macros Swift does not import (sqlite3.h).
    private static let sqliteConstraintPrimaryKey = SQLITE_CONSTRAINT | (6 << 8)
    private static let sqliteConstraintUnique = SQLITE_CONSTRAINT | (8 << 8)

    /// Turns the two unique-constraint failures we expect into shared store errors.
    private static func mapConstraint(_ error: SQLiteError, id: UUID) -> Error {
        switch error.code {
        case sqliteConstraintPrimaryKey:
            return EntryStoreError.duplicateID(id)
        case sqliteConstraintUnique where error.message.contains("entries_one_running"):
            return EntryStoreError.anotherEntryRunning
        default:
            return error
        }
    }

    // MARK: kv

    func readValue(forKey key: String) throws -> String? {
        try sync { db in
            try db.query("SELECT value FROM kv WHERE key = ?", [.text(key)]) { $0.string(0) }.first
        }
    }

    func writeValues(_ pairs: [(key: String, value: String?)]) throws {
        try sync { db in
            try db.transaction {
                for pair in pairs {
                    if let value = pair.value {
                        try db.run(
                            "INSERT INTO kv (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = ?2",
                            [.text(pair.key), .text(value)]
                        )
                    } else {
                        try db.run("DELETE FROM kv WHERE key = ?", [.text(pair.key)])
                    }
                }
            }
        }
    }
}
