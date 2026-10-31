# Weekly graph

The chart lives inside the overlay. Its math lives in `GrainsReports`; the renderer in `App/Sources/Chart/` only draws arrays of points.

## Week boundaries (binding API)

```swift
public struct WeekSpec: Sendable, Hashable {
    public var startsOn: Int            // Calendar weekday number, 2 = Monday (default)
    public var calendar: Calendar       // .autoupdatingCurrent by default; tests inject fixed calendar + time zone
    public init(startsOn: Int = 2, calendar: Calendar = .autoupdatingCurrent)
    public func week(containing date: Date) -> Week
}
public struct Week: Sendable, Hashable, Comparable {
    public var interval: DateInterval          // [start, end) in the spec's time zone; 167–169 h across DST
    public var isoIdentifier: String            // "2026-W44" (ISO 8601 week-based year and week of the *start day*)
    public var days: [DateInterval]             // 7 local days, each [midnight, next midnight)
    public func previous(spec:) -> Week; public func next(spec:) -> Week
}
```

`isoIdentifier` uses `Calendar(identifier: .iso8601)` components `yearForWeekOfYear`/`weekOfYear` of the week's start date, so a week starting Monday Dec 29 2025 is `2026-W01`. If `startsOn` is not Monday the identifier is still the ISO week of the start day (documented quirk).

## Series (binding API)

```swift
public struct WeekSeries: Sendable, Equatable {
    public struct Point: Sendable, Equatable { public var time: Date; public var hours: Double }
    public var week: Week
    public var now: Date
    /// Cumulative tracked hours. Flat while idle, rising while running. Ends exactly at `now`
    /// (or at week end if the week is over). First point is (week.start, 0).
    public var tracked: [Point]
    /// 0...1 fraction of the week elapsed at `now`, clamped.
    public var elapsedFraction: Double
    /// Optional target: straight line from (start, 0) to (end, targetHours) when configured.
    public var targetHours: Double?
    /// Suggested y-axis ceiling for `tracked` (≥ 10, multiple of 5, ≥ max tracked and ≥ target).
    public var hoursCeiling: Double
    public var totalHours: Double { tracked.last?.hours ?? 0 }

    public static func compute(entries: [Entry], week: Week, now: Date, targetHours: Double?) -> WeekSeries
}
```

Computation: clip each non-deleted entry to the week interval with `Entry.seconds(within:asOf:)`; build segment boundaries at every clipped start/stop; walk them in time order accumulating hours; emit a point at each boundary; if an entry is running at `now`, the final point is at `now`. Overlapping entries (should not exist, but historical edits can create them) are counted once by merging overlapping intervals first. The result is deterministic for a given (entries, week, now).

## Statistics (binding API)

```swift
public struct Stats: Sendable, Equatable {
    public var weekHours: Double
    public var todayHours: Double
    public var sessionSeconds: TimeInterval?    // running entry only
    public var byClient: [(clientText: String?, hours: Double)]   // this week, descending
    public static func compute(entries: [Entry], week: Week, today: DateInterval, now: Date) -> Stats
}
```

Displayed with one decimal for hours (`23.7`), `HH:MM:SS` for the session.

## The scale problem and its resolution (D11)

Two aligned lanes sharing the x-axis:

- **Main lane** (≈ 72 pt tall in the default overlay): cumulative tracked hours, y from 0 to `hoursCeiling`. Past is a solid line with a soft fill; the current point glows; the future is empty. Optional target trajectory is a muted dotted straight line in the same lane because it is also hours.
- **Elapsed lane** (≈ 6 pt tall, directly below): a thin track across the whole week with a filled portion from start to `now`. It is clock time, labeled `62% of week`. It never shares the y-axis with hours.

Weekday markers sit under the x-axis (`M T W T F S S`, start day first). Past days dim, today is bright, future days dimmer still.

## Rollover and history

The visible week is `spec.week(containing: now)` unless the user navigated (← → in control mode). Rollover is detected by a one-minute timer and by re-evaluating on wake; the chart resets to the new empty week with a short animation. Previous weeks read the same way from the store.

## Validation cases (tests in `GrainsReportsTests`)

- Session crossing midnight: both days' hours sum to the session, none lost.
- Session crossing the week boundary: split between two `WeekSeries`.
- DST week: `interval.duration` is 167 or 169 h; `elapsedFraction` uses it.
- Backdated edit in a prior week changes only that week's series.
- Running entry: last point time == `now`, `sessionSeconds` set.
