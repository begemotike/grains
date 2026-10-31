import Foundation
import SQLite3

/// `SQLITE_TRANSIENT`: tells SQLite to copy bound text before `bind` returns.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A value bound to a prepared-statement parameter.
enum SQLiteValue: Sendable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

/// Thin wrapper over one `sqlite3*` connection (D5). Not thread-safe: the owning store
/// serializes every call on its private queue. Values are only ever bound, never interpolated.
final class SQLiteConnection {
    let handle: OpaquePointer

    /// Opens (and with `readOnly == false`, creates) the database at `path`.
    init(path: String, readOnly: Bool) throws {
        var db: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE))
            | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            if let db { sqlite3_close_v2(db) }
            throw SQLiteError(code: rc, message: message)
        }
        sqlite3_extended_result_codes(db, 1)
        handle = db
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Text of the most recent error on this connection.
    var lastErrorMessage: String { String(cString: sqlite3_errmsg(handle)) }
    /// Extended code of the most recent error on this connection.
    var lastErrorCode: Int32 { sqlite3_extended_errcode(handle) }
    /// Rows changed by the most recent INSERT/UPDATE/DELETE.
    var changes: Int { Int(sqlite3_changes(handle)) }
    /// Whether the main database is open read-only.
    var isReadOnly: Bool { sqlite3_db_readonly(handle, "main") == 1 }

    func error(rc: Int32, sql: String?) -> SQLiteError {
        SQLiteError(code: lastErrorCode == 0 ? rc : lastErrorCode, message: lastErrorMessage, sql: sql)
    }

    /// Runs one or more statements that take no parameters (DDL, PRAGMAs).
    func exec(_ sql: String) throws {
        let rc = sqlite3_exec(handle, sql, nil, nil, nil)
        guard rc == SQLITE_OK else { throw error(rc: rc, sql: sql) }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(connection: self, sql: sql)
    }

    /// Prepares, binds and steps a statement that returns no rows.
    func run(_ sql: String, _ values: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        try statement.bind(values)
        while try statement.step() {}
    }

    /// Prepares, binds and maps every row.
    func query<T>(_ sql: String, _ values: [SQLiteValue] = [], map: (SQLiteStatement) throws -> T) throws -> [T] {
        let statement = try prepare(sql)
        try statement.bind(values)
        var rows: [T] = []
        while try statement.step() { rows.append(try map(statement)) }
        return rows
    }

    /// Runs `body` inside `BEGIN IMMEDIATE ... COMMIT`, rolling back if it throws.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// `PRAGMA user_version`.
    func userVersion() throws -> Int {
        try query("PRAGMA user_version") { Int($0.int64(0)) }.first ?? 0
    }

    /// Registers a deterministic two-argument SQL function `grains_icontains(haystack, needle)`
    /// that does a Unicode-aware case-insensitive substring match (SQLite's LIKE only folds ASCII).
    func registerContainsFunction() throws {
        let rc = sqlite3_create_function_v2(
            handle, "grains_icontains", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil,
            { context, argc, argv in
                guard argc == 2, let argv,
                      let hayPointer = sqlite3_value_text(argv[0]),
                      let needlePointer = sqlite3_value_text(argv[1]) else {
                    sqlite3_result_int(context, 0)
                    return
                }
                let haystack = String(cString: hayPointer)
                let needle = String(cString: needlePointer)
                let found = haystack.range(of: needle, options: [.caseInsensitive]) != nil
                sqlite3_result_int(context, found ? 1 : 0)
            },
            nil, nil, nil
        )
        guard rc == SQLITE_OK else { throw error(rc: rc, sql: nil) }
    }
}

/// A prepared statement. Finalized on deinit.
final class SQLiteStatement {
    private let connection: SQLiteConnection
    private let handle: OpaquePointer
    let sql: String

    init(connection: SQLiteConnection, sql: String) throws {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(connection.handle, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            throw connection.error(rc: rc, sql: sql)
        }
        self.connection = connection
        self.handle = statement
        self.sql = sql
    }

    deinit {
        sqlite3_finalize(handle)
    }

    /// Binds `values` to parameters 1...n.
    func bind(_ values: [SQLiteValue]) throws {
        for (offset, value) in values.enumerated() {
            try bind(value, at: Int32(offset + 1))
        }
    }

    func bind(_ value: SQLiteValue, at index: Int32) throws {
        let rc: Int32
        switch value {
        case .null: rc = sqlite3_bind_null(handle, index)
        case .integer(let int): rc = sqlite3_bind_int64(handle, index, int)
        case .real(let double): rc = sqlite3_bind_double(handle, index, double)
        case .text(let string): rc = sqlite3_bind_text(handle, index, string, -1, sqliteTransient)
        }
        guard rc == SQLITE_OK else { throw connection.error(rc: rc, sql: sql) }
    }

    /// Advances one row. Returns true when a row is available, false when done.
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw connection.error(rc: rc, sql: sql)
        }
    }

    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    func isNull(_ column: Int32) -> Bool { sqlite3_column_type(handle, column) == SQLITE_NULL }
    func int64(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }
    func double(_ column: Int32) -> Double { sqlite3_column_double(handle, column) }
    func optionalDouble(_ column: Int32) -> Double? { isNull(column) ? nil : double(column) }
    func string(_ column: Int32) -> String {
        guard let text = sqlite3_column_text(handle, column) else { return "" }
        return String(cString: text)
    }
    func optionalString(_ column: Int32) -> String? { isNull(column) ? nil : string(column) }
}

extension SQLiteValue {
    init(_ string: String?) { self = string.map(SQLiteValue.text) ?? .null }
    init(_ double: Double?) { self = double.map(SQLiteValue.real) ?? .null }
    init(_ date: Date?) { self = date.map { .real($0.timeIntervalSince1970) } ?? .null }
    init(_ uuid: UUID?) { self = uuid.map { .text($0.uuidString) } ?? .null }
}
