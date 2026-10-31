import Foundation
import GrainsCore
import GrainsReports

/// Which weekly CSV files an entry change touches (D17, docs/csv-export.md). Pure.
enum ExportWeekMapping {
    /// Every week the entry overlaps: the week of its start, the week of its stop (or of
    /// `now` while running) and any week in between. A zero-length entry maps to one week.
    static func weeks(for entry: Entry, spec: WeekSpec, now: Date) -> [Week] {
        let first = spec.week(containing: entry.startedAt)
        let end = entry.stoppedAt ?? max(now, entry.startedAt)
        var weeks = [first]
        var cursor = first
        // A stop exactly at a week boundary belongs to the earlier week only.
        while cursor.interval.end < end, weeks.count < 520 {
            cursor = cursor.next(spec: spec)
            weeks.append(cursor)
        }
        return weeks
    }

    /// Weeks to rewrite after a change: the entries' current weeks plus the weeks they
    /// occupied before the change (an edit can move an entry out of a week, and a deleted
    /// entry can no longer be read). Sorted, unique.
    static func weeksToRewrite(changed: [Entry], previouslyKnown: [Week], spec: WeekSpec, now: Date) -> [Week] {
        var set = Set(previouslyKnown)
        for entry in changed { set.formUnion(weeks(for: entry, spec: spec, now: now)) }
        return set.sorted()
    }

    /// Every week from the one containing `earliest` through the one containing `now`.
    static func allWeeks(from earliest: Date, through now: Date, spec: WeekSpec) -> [Week] {
        var week = spec.week(containing: earliest)
        let last = spec.week(containing: max(now, earliest))
        var result = [week]
        while week < last, result.count < 5_200 {
            week = week.next(spec: spec)
            result.append(week)
        }
        return result
    }
}
