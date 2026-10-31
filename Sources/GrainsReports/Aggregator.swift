import Foundation
import GrainsCore

/// How `Aggregator` buckets time.
public enum GroupBy: String, CaseIterable, Codable, Sendable {
    /// One row per local day (`2026-10-27`).
    case day
    /// One row per spec week (`2026-W44`).
    case week
    /// One row per client label (`clientText`, exact match).
    case client
    /// One row per (local day, client label): key `2026-10-27|Acme`.
    case clientDay
}

/// One aggregated bucket.
public struct AggregateRow: Codable, Equatable, Sendable {
    /// Bucket key: `yyyy-MM-dd`, ISO week id, the client label (`(no client)` when nil),
    /// or `yyyy-MM-dd|<client label>`.
    public var key: String
    /// Client label for `client`/`clientDay` rows; `nil` for day/week rows and for no-client rows.
    public var clientText: String?
    /// Tracked seconds inside the bucket (overlapping entries within the bucket counted once).
    public var seconds: TimeInterval
    /// `seconds / 3600` rounded to 2 decimals.
    public var hours: Double
    /// Number of entries contributing time to the bucket.
    public var entryCount: Int

    /// Creates a row.
    public init(key: String, clientText: String?, seconds: TimeInterval, hours: Double, entryCount: Int) {
        self.key = key
        self.clientText = clientText
        self.seconds = seconds
        self.hours = hours
        self.entryCount = entryCount
    }
}

/// Deterministic totals over an arbitrary range; backs the MCP `aggregate` tool.
public enum Aggregator {
    /// Key used for entries without a client label.
    public static let noClientKey = "(no client)"

    /// Aggregates non-deleted entries clipped to `range` (running entries end at `now`).
    ///
    /// Buckets with no time are omitted. Ordering: `day`/`week` chronological; `client` by
    /// seconds descending then label (`nil` last); `clientDay` by day, then seconds descending,
    /// then label.
    public static func aggregate(entries: [Entry], range: DateInterval, groupBy: GroupBy, spec: WeekSpec, now: Date) -> [AggregateRow] {
        let live = entries.filter { !$0.isDeleted }
        guard range.duration > 0 else { return [] }
        let clock = LocalClock(timeZone: spec.calendar.timeZone)

        switch groupBy {
        case .day:
            return dayBuckets(range, spec: spec).compactMap { bucket in
                row(key: clock.dateString(bucket.start), client: nil, entries: live, bucket: bucket, now: now)
            }
        case .week:
            return weekBuckets(range, spec: spec).compactMap { key, bucket in
                row(key: key, client: nil, entries: live, bucket: bucket, now: now)
            }
        case .client:
            return byClient(live, bucket: range, now: now) { $0 ?? noClientKey }
        case .clientDay:
            return dayBuckets(range, spec: spec).flatMap { bucket in
                let day = clock.dateString(bucket.start)
                return byClient(live, bucket: bucket, now: now) { "\(day)|\($0 ?? noClientKey)" }
            }
        }
    }

    private static func row(key: String, client: String?, entries: [Entry], bucket: DateInterval, now: Date) -> AggregateRow? {
        let pieces = IntervalMath.clipped(entries, to: bucket, now: now)
        guard !pieces.isEmpty else { return nil }
        let seconds = IntervalMath.merge(pieces).reduce(0) { $0 + $1.duration }
        return AggregateRow(key: key, clientText: client, seconds: seconds, hours: (seconds / 36).rounded() / 100, entryCount: pieces.count)
    }

    private static func byClient(_ entries: [Entry], bucket: DateInterval, now: Date, key: (String?) -> String) -> [AggregateRow] {
        var groups: [String?: [Entry]] = [:]
        for entry in entries { groups[entry.clientText, default: []].append(entry) }
        var rows: [AggregateRow] = []
        for (client, group) in groups {
            if let r = row(key: key(client), client: client, entries: group, bucket: bucket, now: now) { rows.append(r) }
        }
        rows.sort { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : IntervalMath.clientPrecedes($0.clientText, $1.clientText) }
        return rows
    }

    /// Local days intersecting `range`, each clipped to it.
    private static func dayBuckets(_ range: DateInterval, spec: WeekSpec) -> [DateInterval] {
        var out: [DateInterval] = []
        var day = spec.today(at: range.start)
        while day.start < range.end {
            let start = max(day.start, range.start)
            let end = min(day.end, range.end)
            if end > start { out.append(DateInterval(start: start, end: end)) }
            day = spec.today(at: day.end)
        }
        return out
    }

    /// Spec weeks intersecting `range`, each clipped to it.
    private static func weekBuckets(_ range: DateInterval, spec: WeekSpec) -> [(String, DateInterval)] {
        var out: [(String, DateInterval)] = []
        var week = spec.week(containing: range.start)
        while week.interval.start < range.end {
            let start = max(week.interval.start, range.start)
            let end = min(week.interval.end, range.end)
            if end > start { out.append((week.isoIdentifier, DateInterval(start: start, end: end))) }
            week = week.next(spec: spec)
        }
        return out
    }
}
