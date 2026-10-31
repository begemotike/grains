import Foundation

/// One week as cut by a `WeekSpec`. Obtain values with `WeekSpec.week(containing:)`.
public struct Week: Sendable, Hashable, Comparable, Codable {
    /// `[start, end)` in the spec's time zone; 167–169 h long across DST transitions.
    public var interval: DateInterval
    /// ISO 8601 week-based year and week number of the week's *start day*, e.g. `2026-W44`.
    /// If the week does not start on Monday this is still the ISO week of the start day.
    public var isoIdentifier: String
    /// The seven local days, each `[midnight, next midnight)`, start day first.
    public var days: [DateInterval]

    init(interval: DateInterval, isoIdentifier: String, days: [DateInterval]) {
        self.interval = interval
        self.isoIdentifier = isoIdentifier
        self.days = days
    }

    /// The week immediately before this one under `spec`.
    public func previous(spec: WeekSpec) -> Week {
        spec.week(containing: interval.start.addingTimeInterval(-1))
    }

    /// The week immediately after this one under `spec`.
    public func next(spec: WeekSpec) -> Week {
        spec.week(containing: interval.end)
    }

    /// Weeks order by their start instant.
    public static func < (lhs: Week, rhs: Week) -> Bool {
        lhs.interval.start < rhs.interval.start
    }
}
