import Foundation

/// Schema migrations, applied in order from the database's `PRAGMA user_version` upward.
/// Never edit a shipped migration; append a new one (docs/data-model.md).
enum SQLiteSchema {
    ///
    /// D23: the one-running index is on the expression `(stopped_at IS NULL)`, not on the bare
    /// `stopped_at` column as first drafted in data-model.md: SQLite treats NULLs as distinct
    /// in UNIQUE indexes, so an index on `stopped_at` filtered to NULL rows never conflicts.
    static let migrations: [String] = [
        // v1
        """
        CREATE TABLE entries (
          id               TEXT PRIMARY KEY,
          raw_text         TEXT NOT NULL,
          client_text      TEXT,
          note             TEXT,
          client_id        TEXT,
          started_at       REAL NOT NULL,
          stopped_at       REAL,
          duration_seconds REAL,
          created_at       REAL NOT NULL,
          updated_at       REAL NOT NULL,
          deleted_at       REAL,
          metadata         TEXT NOT NULL DEFAULT '{}'
        );
        CREATE UNIQUE INDEX entries_one_running ON entries((stopped_at IS NULL)) WHERE stopped_at IS NULL AND deleted_at IS NULL;
        CREATE INDEX entries_started_at ON entries(started_at);
        CREATE INDEX entries_client_text ON entries(client_text COLLATE NOCASE);
        CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        """,
    ]

    static var currentVersion: Int { migrations.count }

    /// Column list shared by every entry SELECT, in the order `entry(from:)` reads it.
    static let entryColumns = """
        id, raw_text, client_text, note, client_id, started_at, stopped_at, \
        created_at, updated_at, deleted_at, metadata
        """

    static func entry(from row: SQLiteStatement) -> Entry? {
        guard let id = UUID(uuidString: row.string(0)) else { return nil }
        return Entry(
            id: id,
            rawText: row.string(1),
            clientText: row.optionalString(2),
            note: row.optionalString(3),
            clientID: row.optionalString(4).flatMap(UUID.init(uuidString:)),
            startedAt: Date(timeIntervalSince1970: row.double(5)),
            stoppedAt: row.optionalDouble(6).map(Date.init(timeIntervalSince1970:)),
            createdAt: Date(timeIntervalSince1970: row.double(7)),
            updatedAt: Date(timeIntervalSince1970: row.double(8)),
            deletedAt: row.optionalDouble(9).map(Date.init(timeIntervalSince1970:)),
            metadata: EntryMetadataCoding.decode(row.string(10))
        )
    }

    /// Values for every column in `entryColumns` order, plus `duration_seconds` last.
    /// `duration_seconds` is recomputed here on every write (D6) and is NULL while running.
    static func values(for entry: Entry) throws -> [SQLiteValue] {
        let duration: Double? = entry.stoppedAt.map { _ in entry.duration(asOf: entry.startedAt) }
        return [
            SQLiteValue(entry.id),
            .text(entry.rawText),
            SQLiteValue(entry.clientText),
            SQLiteValue(entry.note),
            SQLiteValue(entry.clientID),
            SQLiteValue(entry.startedAt),
            SQLiteValue(entry.stoppedAt),
            SQLiteValue(entry.createdAt),
            SQLiteValue(entry.updatedAt),
            SQLiteValue(entry.deletedAt),
            .text(try EntryMetadataCoding.encode(entry.metadata)),
            SQLiteValue(duration),
        ]
    }
}
