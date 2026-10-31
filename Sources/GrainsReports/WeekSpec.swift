import Foundation

/// How weeks are cut out of the timeline: which weekday starts a week, and in which calendar
/// and time zone. Week boundaries are always evaluated with the spec in effect *now* (D10), so
/// travelling across zones redraws the week; stored timestamps are never affected.
public struct WeekSpec: Sendable, Hashable {
    /// Calendar weekday number the week starts on (1 = Sunday, 2 = Monday, ... 7 = Saturday).
    /// Defaults to Monday. Values outside 1...7 are wrapped into that range.
    public var startsOn: Int
    /// Calendar (and through it, the time zone) used for day and week boundaries.
    /// `.autoupdatingCurrent` in the app; tests inject a fixed calendar and time zone.
    public var calendar: Calendar

    /// Creates a spec. `startsOn` uses `Calendar` weekday numbering (2 = Monday).
    public init(startsOn: Int = 2, calendar: Calendar = .autoupdatingCurrent) {
        self.startsOn = startsOn
        self.calendar = calendar
    }

    /// The week (in this spec's calendar and time zone) that contains `date`.
    ///
    /// The start is the local midnight of the most recent `startsOn` weekday on or before
    /// `date`; days are computed with calendar arithmetic, never by adding 86 400 s, so DST
    /// weeks are 167 or 169 hours long.
    public func week(containing date: Date) -> Week {
        let cal = calendar
        let dayStart = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: dayStart)
        let first = ((startsOn - 1) % 7 + 7) % 7 + 1
        let back = (weekday - first + 7) % 7
        let start = cal.startOfDay(for: Self.add(days: -back, to: dayStart, in: cal))

        var days: [DateInterval] = []
        days.reserveCapacity(7)
        var cursor = start
        for _ in 0..<7 {
            let next = cal.startOfDay(for: Self.add(days: 1, to: cursor, in: cal))
            days.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        let interval = DateInterval(start: start, end: cursor)
        return Week(interval: interval, isoIdentifier: Self.isoIdentifier(for: start, timeZone: cal.timeZone), days: days)
    }

    /// The local calendar day containing `date`: `[midnight, next midnight)` in this spec's
    /// calendar. 23, 24 or 25 hours long.
    public func today(at date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: Self.add(days: 1, to: start, in: calendar))
        return DateInterval(start: start, end: end)
    }

    /// ISO 8601 week identifier (`2026-W44`) of the day containing `date` in `timeZone`.
    static func isoIdentifier(for date: Date, timeZone: TimeZone) -> String {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        let comps = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 0
        let week = comps.weekOfYear ?? 0
        return "\(LocalClock.pad(year, 4))-W\(LocalClock.pad(week, 2))"
    }

    static func add(days: Int, to date: Date, in calendar: Calendar) -> Date {
        // `date(byAdding:)` only fails for out-of-range dates; fall back to a fixed offset
        // rather than trapping (never reached for real timestamps).
        calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }
}
