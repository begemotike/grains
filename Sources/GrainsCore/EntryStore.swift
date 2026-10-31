import Foundation

/// Read side of the entry store. Implemented by `SQLiteEntryStore` and by `InMemoryEntryStore`
/// (tests, previews). The MCP server only ever sees this protocol.
///
/// All methods exclude soft-deleted entries unless the method name says otherwise.
/// Implementations must be safe to call from any thread (serialize internally).
public protocol EntryReading: Sendable {
    func entry(id: UUID) throws -> Entry?
    /// The single running entry, if any.
    func runningEntry() throws -> Entry?
    /// Entries whose [startedAt, stoppedAt ?? now] overlaps `interval`, ordered by startedAt.
    /// A running entry is included when `startedAt < interval.end`.
    func entries(overlapping interval: DateInterval) throws -> [Entry]
    /// Most recent entries by startedAt, newest first.
    func recentEntries(limit: Int) throws -> [Entry]
    /// Case-insensitive substring search over rawText, clientText and note.
    func search(_ text: String, limit: Int) throws -> [Entry]
    /// Distinct provisional client labels with their entry counts (for "unknown client" review).
    func clientLabels() throws -> [ClientLabelCount]
    /// Earliest startedAt across all entries, or nil when the store is empty.
    func earliestStart() throws -> Date?
}

public struct ClientLabelCount: Hashable, Sendable, Codable {
    public var clientText: String
    public var clientID: UUID?
    public var count: Int
    public var totalSeconds: TimeInterval
    public init(clientText: String, clientID: UUID?, count: Int, totalSeconds: TimeInterval) {
        self.clientText = clientText
        self.clientID = clientID
        self.count = count
        self.totalSeconds = totalSeconds
    }
}

/// Write side. Only the app process writes; the MCP server opens the database read-only.
public protocol EntryWriting: EntryReading {
    func insert(_ entry: Entry) throws
    /// Replace the stored row for `entry.id`. Must bump `updatedAt` (callers may pre-set it).
    func update(_ entry: Entry) throws
    func softDelete(id: UUID, at: Date) throws
    /// Timer liveness marker written periodically while an entry runs; read at launch to
    /// bound how much time can be trusted after a crash. See `TimerEngine`.
    func writeHeartbeat(entryID: UUID, at: Date) throws
    func readHeartbeat() throws -> (entryID: UUID, at: Date)?
    func clearHeartbeat() throws

    /// Apply several inserts/updates atomically (all or nothing) and post one change
    /// notification. The timer engine uses this so "stop the running entry, insert the next"
    /// is a single transaction (docs/data-model.md). Added by D25.
    func commit(_ writes: [EntryWrite]) throws
    /// Raw access to the `kv` table (keys in `EntryStoreKey`). `nil` deletes the key.
    /// The timer engine stores its clean-shutdown marker here. Added by D25.
    func readValue(forKey key: String) throws -> String?
    func writeValue(_ value: String?, forKey key: String) throws
}

/// One write inside `EntryWriting.commit(_:)`.
public enum EntryWrite: Hashable, Sendable {
    case insert(Entry)
    case update(Entry)

    /// The id of the entry this write touches.
    public var entryID: UUID {
        switch self {
        case .insert(let entry), .update(let entry): return entry.id
        }
    }
}

/// Keys used in the `kv` table (docs/data-model.md).
public enum EntryStoreKey {
    public static let heartbeatEntryID = "heartbeat_entry_id"
    public static let heartbeatAt = "heartbeat_at"
    public static let cleanShutdown = "clean_shutdown"
}

/// Errors shared by every `EntryWriting` implementation, so callers can react the same way
/// whether they talk to SQLite or to the in-memory store.
public enum EntryStoreError: Error, Equatable, Sendable {
    /// `update`/`softDelete` targeted an id that does not exist.
    case notFound(UUID)
    /// `insert` used an id that already exists.
    case duplicateID(UUID)
    /// A second entry with `stoppedAt == nil` would violate the one-running-entry rule.
    case anotherEntryRunning
    /// The database was written by a newer Grains (its `user_version` is higher than we know).
    case unsupportedSchemaVersion(Int)
    /// A read-only open found a file that has never been initialized by Grains.
    case notAGrainsDatabase
}

/// Notification posted by the store on the main queue after any successful write,
/// so the overlay, exporter and stats recompute from one source of truth.
public extension Notification.Name {
    static let grainsEntriesDidChange = Notification.Name("net.outofajam.grains.entriesDidChange")
}
