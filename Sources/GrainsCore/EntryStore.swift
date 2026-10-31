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
}

/// Notification posted by the store on the main queue after any successful write,
/// so the overlay, exporter and stats recompute from one source of truth.
public extension Notification.Name {
    static let grainsEntriesDidChange = Notification.Name("net.outofajam.grains.entriesDidChange")
}
