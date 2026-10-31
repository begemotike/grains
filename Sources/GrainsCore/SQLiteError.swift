import Foundation
import SQLite3

/// An error reported by SQLite, carrying the result code and `sqlite3_errmsg` text.
public struct SQLiteError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Extended result code (e.g. `SQLITE_CONSTRAINT_UNIQUE`).
    public let code: Int32
    /// SQLite's message for the failure.
    public let message: String
    /// The statement that failed, when known (never contains bound values).
    public let sql: String?

    public init(code: Int32, message: String, sql: String? = nil) {
        self.code = code
        self.message = message
        self.sql = sql
    }

    /// Primary result code (the low byte of the extended code).
    public var primaryCode: Int32 { code & 0xFF }
    /// True for any constraint violation (unique, primary key, not null...).
    public var isConstraintViolation: Bool { primaryCode == SQLITE_CONSTRAINT }
    /// True when the connection is read-only and a write was attempted.
    public var isReadOnly: Bool { primaryCode == SQLITE_READONLY }

    public var description: String {
        if let sql { return "SQLite error \(code): \(message) [\(sql)]" }
        return "SQLite error \(code): \(message)"
    }
}
