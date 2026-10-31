import Foundation

/// One tracked session. The database row is the durable record; `rawText` is never rewritten.
///
/// Invariants:
/// - `stoppedAt == nil` means the entry is running. At most one entry is running at a time.
/// - `rawText` is exactly what the user typed. `clientText`/`note` are derived by `EntryParser`
///   at capture time and may be re-derived; `clientID` is an optional later normalization.
/// - Durations are never stored as truth; they are computed from the two absolute timestamps.
public struct Entry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var rawText: String
    public var clientText: String?
    public var note: String?
    public var clientID: UUID?
    public var startedAt: Date
    public var stoppedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    /// Soft delete. Deleted entries are excluded from totals, charts, exports and MCP results
    /// but remain in the database for audit.
    public var deletedAt: Date?
    public var metadata: EntryMetadata

    public init(
        id: UUID = UUID(),
        rawText: String,
        clientText: String? = nil,
        note: String? = nil,
        clientID: UUID? = nil,
        startedAt: Date,
        stoppedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        metadata: EntryMetadata = EntryMetadata()
    ) {
        self.id = id
        self.rawText = rawText
        self.clientText = clientText
        self.note = note
        self.clientID = clientID
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.createdAt = createdAt ?? startedAt
        self.updatedAt = updatedAt ?? self.createdAt
        self.deletedAt = deletedAt
        self.metadata = metadata
    }

    /// Convenience: parse `rawText` into client/note and start now.
    public init(capturing rawText: String, at start: Date = Date()) {
        let parsed = EntryParser.parse(rawText)
        self.init(rawText: rawText, clientText: parsed.clientText, note: parsed.note, startedAt: start)
    }

    public var isRunning: Bool { stoppedAt == nil }
    public var isDeleted: Bool { deletedAt != nil }

    /// Elapsed seconds as of `now`. For a stopped entry `now` is ignored. Never negative.
    public func duration(asOf now: Date) -> TimeInterval {
        max(0, (stoppedAt ?? now).timeIntervalSince(startedAt))
    }

    /// The seconds of this entry that fall inside `interval`, as of `now` for a running entry.
    /// This is the single primitive every total, chart point and export column is built from,
    /// so sessions that cross midnight or a week boundary are split, never double counted.
    public func seconds(within interval: DateInterval, asOf now: Date) -> TimeInterval {
        let end = stoppedAt ?? now
        let start = max(startedAt, interval.start)
        let stop = min(end, interval.end)
        return max(0, stop.timeIntervalSince(start))
    }
}

/// Extensible optional data stored as JSON in the `metadata` column.
/// Known keys are typed; anything else round-trips through `extra`.
public struct EntryMetadata: Codable, Hashable, Sendable {
    /// Set when the timer engine stopped this entry itself during crash/sleep recovery.
    /// The stop time is then the last heartbeat, not a user action, and the interval
    /// between the heartbeat and the next launch is *uncertain*, never silently counted.
    public var recovered: RecoveryInfo?
    /// Free-form string pairs for future use (tags, AI annotations, import source...).
    public var extra: [String: String]

    public init(recovered: RecoveryInfo? = nil, extra: [String: String] = [:]) {
        self.recovered = recovered
        self.extra = extra
    }

    private enum CodingKeys: String, CodingKey { case recovered, extra }

    /// Tolerant decoding: the schema default is the literal `{}` and hand-repaired blobs may
    /// omit either key. A missing `extra` is empty, a missing `recovered` is nil; neither is
    /// an error, so a recovery flag is never silently lost (D8).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recovered = try c.decodeIfPresent(RecoveryInfo.self, forKey: .recovered)
        extra = try c.decodeIfPresent([String: String].self, forKey: .extra) ?? [:]
    }

    public struct RecoveryInfo: Codable, Hashable, Sendable {
        /// Last moment the app is sure the timer was alive (last heartbeat).
        public var lastHeartbeat: Date
        /// When the app noticed (next launch).
        public var noticedAt: Date
        /// Whether the user has reviewed/accepted the recovered stop time.
        public var reconciled: Bool

        public init(lastHeartbeat: Date, noticedAt: Date, reconciled: Bool = false) {
            self.lastHeartbeat = lastHeartbeat
            self.noticedAt = noticedAt
            self.reconciled = reconciled
        }
    }
}
