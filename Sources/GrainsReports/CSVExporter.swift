import Foundation
import GrainsCore

/// Renders one week of entries as CSV (schema version 1). Pure: the same entries, time zone
/// and `now` produce byte-identical output.
///
/// Format: UTF-8, no BOM, `\n` after every record (including the last), RFC 4180 quoting
/// (a field containing `,`, `"`, `\n` or `\r` is wrapped in quotes with `"` doubled).
/// All timestamps are truncated to whole seconds before formatting *and* before duration
/// arithmetic, so durations always agree with the printed timestamps and the two halves of a
/// week-crossing session sum exactly to `whole_duration_seconds`.
public struct CSVExporter: Sendable {
    /// Supplies the time zone for local columns and RFC 3339 offsets.
    public var spec: WeekSpec
    private let clock: LocalClock

    /// Creates an exporter that formats in `spec.calendar.timeZone`.
    public init(spec: WeekSpec) {
        self.spec = spec
        self.clock = LocalClock(timeZone: spec.calendar.timeZone)
    }

    /// `Grains-2026-W44.csv`
    public static func fileName(for week: Week) -> String {
        CSVSchema.version == 1 ? "Grains-\(week.isoIdentifier).csv" : "Grains-\(week.isoIdentifier).v\(CSVSchema.version).csv"
    }

    /// The CSV text for `week`. Includes every non-deleted entry that overlaps the week or
    /// starts inside it (so zero-length entries are not lost), ordered by `started_at`, then id.
    /// `now` is the end of a running entry.
    public func csv(for week: Week, entries: [Entry], now: Date) -> String {
        let weekStart = LocalClock.wholeSeconds(week.interval.start)
        let weekEnd = LocalClock.wholeSeconds(week.interval.end)

        let rows = entries
            .filter { !$0.isDeleted }
            .compactMap { entry -> (Entry, Int64, Int64)? in
                let start = LocalClock.wholeSeconds(entry.startedAt)
                let end = LocalClock.wholeSeconds(entry.stoppedAt ?? now)
                let clipped = max(0, min(end, weekEnd) - max(start, weekStart))
                let startsInside = start >= weekStart && start < weekEnd
                guard clipped > 0 || startsInside else { return nil }
                return (entry, clipped, max(0, end - start))
            }
            .sorted { ($0.0.startedAt, $0.0.id.uuidString) < ($1.0.startedAt, $1.0.id.uuidString) }

        var out = CSVSchema.columns.joined(separator: ",") + "\n"
        for (entry, clipped, whole) in rows {
            let fields: [String] = [
                entry.id.uuidString,
                week.isoIdentifier,
                clock.rfc3339(entry.startedAt),
                entry.stoppedAt.map(clock.rfc3339) ?? "",
                clock.dateString(entry.startedAt),
                clock.timeString(entry.startedAt),
                entry.stoppedAt.map(clock.dateString) ?? "",
                entry.stoppedAt.map(clock.timeString) ?? "",
                String(clipped),
                String(whole),
                Self.hours(seconds: clipped),
                entry.rawText,
                entry.clientText ?? "",
                entry.note ?? "",
                entry.clientID?.uuidString ?? "",
                entry.isRunning ? "true" : "false",
                (entry.metadata.recovered.map { !$0.reconciled } ?? false) ? "true" : "false",
                clock.rfc3339(entry.createdAt),
                clock.rfc3339(entry.updatedAt),
            ]
            out += fields.map(Self.quote).joined(separator: ",") + "\n"
        }
        return out
    }

    /// `seconds / 3600` with exactly two decimals, rounded half up, using integer arithmetic.
    static func hours(seconds: Int64) -> String {
        let hundredths = (seconds * 100 + 1800) / 3600
        return "\(hundredths / 100).\(LocalClock.pad(Int(hundredths % 100), 2))"
    }

    /// RFC 4180 field quoting.
    static func quote(_ field: String) -> String {
        // Test UTF-8 bytes, not Characters: a comma followed by a combining mark is one grapheme
        // cluster that would otherwise slip through unquoted and add a column.
        guard field.utf8.contains(where: { $0 == 0x2C || $0 == 0x22 || $0 == 0x0A || $0 == 0x0D }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
