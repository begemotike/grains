import XCTest
@testable import GrainsCore

/// SQLite-specific behaviour: schema, persistence, derived columns, read-only opening.
final class SQLiteEntryStoreTests: XCTestCase {
    let t0 = TestDate.reference

    private func rawConnection(_ url: URL) throws -> SQLiteConnection {
        try SQLiteConnection(path: url.path(percentEncoded: false), readOnly: false)
    }

    func testSchemaVersionWALAndPartialUniqueIndex() throws {
        let url = try temporaryDatabaseURL(for: self)
        _ = try SQLiteEntryStore.open(at: url)
        let db = try rawConnection(url)
        XCTAssertEqual(try db.userVersion(), 1)
        XCTAssertEqual(try db.query("PRAGMA journal_mode") { $0.string(0) }.first, "wal")
        let indexSQL = try db.query("SELECT sql FROM sqlite_master WHERE name = 'entries_one_running'") { $0.string(0) }.first
        XCTAssertEqual(
            indexSQL,
            "CREATE UNIQUE INDEX entries_one_running ON entries((stopped_at IS NULL)) WHERE stopped_at IS NULL AND deleted_at IS NULL"
        )
        let indexes = try db.query("SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'entries_%' ORDER BY name") { $0.string(0) }
        XCTAssertEqual(indexes, ["entries_client_text", "entries_one_running", "entries_started_at"])
    }

    func testReopeningKeepsDataAndDoesNotRemigrate() throws {
        let url = try temporaryDatabaseURL(for: self)
        let entry = Entry.fixture("Denali - a", start: t0, minutes: 10)
        do {
            let store = try SQLiteEntryStore.open(at: url)
            try store.insert(entry)
        }
        let reopened = try SQLiteEntryStore.open(at: url)
        XCTAssertEqual(try reopened.entry(id: entry.id), entry)
    }

    func testRefusesNewerSchema() throws {
        let url = try temporaryDatabaseURL(for: self)
        _ = try SQLiteEntryStore.open(at: url)
        try rawConnection(url).exec("PRAGMA user_version = 99")
        XCTAssertThrowsError(try SQLiteEntryStore.open(at: url)) { error in
            XCTAssertEqual(error as? EntryStoreError, .unsupportedSchemaVersion(99))
        }
    }

    func testDurationColumnRecomputedOnEveryWriteAndNullWhileRunning() throws {
        let url = try temporaryDatabaseURL(for: self)
        let store = try SQLiteEntryStore.open(at: url)
        var entry = Entry.fixture("A", start: t0, minutes: nil)
        try store.insert(entry)
        func storedDuration() throws -> Double? {
            try rawConnection(url).query("SELECT duration_seconds FROM entries WHERE id = ?", [SQLiteValue(entry.id)]) {
                $0.optionalDouble(0)
            }.first ?? nil
        }
        XCTAssertNil(try storedDuration())
        entry.stoppedAt = t0.addingTimeInterval(1500)
        try store.update(entry)
        XCTAssertEqual(try storedDuration(), 1500)
        entry.startedAt = t0.addingTimeInterval(-300)  // backdated correction
        try store.update(entry)
        XCTAssertEqual(try storedDuration(), 1800)
    }

    func testUUIDsStoredUppercaseAndMetadataSortedKeys() throws {
        let url = try temporaryDatabaseURL(for: self)
        let store = try SQLiteEntryStore.open(at: url)
        var entry = Entry.fixture("A", start: t0, minutes: 1)
        entry.metadata.extra = ["b": "2", "a": "1"]
        try store.insert(entry)
        let row = try rawConnection(url).query("SELECT id, metadata FROM entries") { ($0.string(0), $0.string(1)) }.first
        XCTAssertEqual(row?.0, entry.id.uuidString.uppercased())
        XCTAssertEqual(row?.1, #"{"extra":{"a":"1","b":"2"}}"#)
    }

    func testUndecodableMetadataIsPreserved() throws {
        let url = try temporaryDatabaseURL(for: self)
        let store = try SQLiteEntryStore.open(at: url)
        let entry = Entry.fixture("A", start: t0, minutes: 1)
        try store.insert(entry)
        try rawConnection(url).run("UPDATE entries SET metadata = 'not json' WHERE id = ?", [SQLiteValue(entry.id)])
        XCTAssertEqual(try store.entry(id: entry.id)?.metadata.extra["unparsed_metadata"], "not json")
    }

    func testRawIndexViolationIsAConstraintError() throws {
        let url = try temporaryDatabaseURL(for: self)
        _ = try SQLiteEntryStore.open(at: url)
        let db = try rawConnection(url)
        let insert = "INSERT INTO entries (id, raw_text, started_at, created_at, updated_at) VALUES (?, 'x', 0, 0, 0)"
        try db.run(insert, [.text(UUID().uuidString)])
        XCTAssertThrowsError(try db.run(insert, [.text(UUID().uuidString)])) { error in
            let sqliteError = error as? SQLiteError
            XCTAssertEqual(sqliteError?.isConstraintViolation, true)
            XCTAssertTrue(sqliteError?.message.contains("entries_one_running") ?? false, "\(error)")
        }
    }

    // MARK: Read-only

    func testReadOnlyStoreReadsWhileWriterIsOpen() throws {
        let url = try temporaryDatabaseURL(for: self)
        let writer = try SQLiteEntryStore.open(at: url)
        let entry = Entry.fixture("Denali - a", start: t0, minutes: 10)
        try writer.insert(entry)

        let reader = try SQLiteEntryStore.openReadOnly(at: url)
        XCTAssertEqual(try reader.entry(id: entry.id), entry)

        // Writes made after the reader opened are visible (WAL).
        let later = Entry.fixture("Denali - b", start: t0.addingTimeInterval(3600), minutes: nil)
        try writer.insert(later)
        XCTAssertEqual(try reader.runningEntry()?.id, later.id)
        XCTAssertEqual(try reader.search("denali", limit: 10).count, 2)
    }

    func testReadOnlyStoreAfterWriterClosed() throws {
        let url = try temporaryDatabaseURL(for: self)
        let entry = Entry.fixture("A", start: t0, minutes: 10)
        do {
            let writer = try SQLiteEntryStore.open(at: url)
            try writer.insert(entry)
        }
        let reader = try SQLiteEntryStore.openReadOnly(at: url)
        XCTAssertEqual(try reader.recentEntries(limit: 1).first?.id, entry.id)
    }

    /// The type-level guarantee: `openReadOnly` returns `some EntryReading`, so
    /// `reader.insert(...)` does not compile. At runtime the value is not an `EntryWriting`
    /// either, and its connection rejects raw writes.
    func testReadOnlyStoreRefusesWrites() throws {
        let url = try temporaryDatabaseURL(for: self)
        _ = try SQLiteEntryStore.open(at: url)
        let reader = try SQLiteEntryStore.openReadOnly(at: url)
        XCTAssertFalse(reader is any EntryWriting)

        let concrete = try XCTUnwrap(reader as? SQLiteEntryReader)
        XCTAssertTrue(concrete.database.isReadOnly)
        XCTAssertThrowsError(try concrete.database.commit([.insert(Entry.fixture("x", start: t0, minutes: 1))])) { error in
            XCTAssertEqual((error as? SQLiteError)?.isReadOnly, true, "\(error)")
        }
    }

    func testReadOnlyOpenOfMissingFileThrows() throws {
        let url = try temporaryDatabaseURL(for: self)
        XCTAssertThrowsError(try SQLiteEntryStore.openReadOnly(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    func testReadOnlyOpenOfUninitializedFileThrows() throws {
        let url = try temporaryDatabaseURL(for: self)
        _ = try SQLiteConnection(path: url.path(percentEncoded: false), readOnly: false)  // empty db file
        XCTAssertThrowsError(try SQLiteEntryStore.openReadOnly(at: url)) { error in
            XCTAssertEqual(error as? EntryStoreError, .notAGrainsDatabase)
        }
    }
}
