import Foundation
import GrainsCore

/// Chart data for one week: cumulative tracked hours, elapsed fraction and optional target.
/// Pure and deterministic for a given `(entries, week, now, targetHours)`.
public struct WeekSeries: Sendable, Equatable {
    /// One vertex of the cumulative tracked-hours line.
    public struct Point: Sendable, Equatable {
        /// Instant of the vertex.
        public var time: Date
        /// Cumulative tracked hours from the week start up to `time`.
        public var hours: Double

        /// Creates a point.
        public init(time: Date, hours: Double) {
            self.time = time
            self.hours = hours
        }
    }

    /// The week this series describes.
    public var week: Week
    /// The evaluation instant.
    public var now: Date
    /// Cumulative tracked hours. Flat while idle, rising while running. Ends exactly at `now`
    /// (or at week end if the week is over). First point is `(week.start, 0)`. For a week that
    /// has not started yet the series is the single point `(week.start, 0)`.
    public var tracked: [Point]
    /// 0...1 fraction of the week elapsed at `now`, clamped; uses the real (DST) week length.
    public var elapsedFraction: Double
    /// Optional target: straight line from `(start, 0)` to `(end, targetHours)` when configured.
    public var targetHours: Double?
    /// Suggested y-axis ceiling for `tracked` (≥ 10, multiple of 5, ≥ max tracked and ≥ target).
    public var hoursCeiling: Double
    /// Tracked hours per local day of the week (7 values, start day first), clipped at `now`.
    public var dailyHours: [Double]
    /// Total tracked hours this week as of `now`.
    public var totalHours: Double { tracked.last?.hours ?? 0 }

    /// The two endpoints of the target trajectory, or `nil` when no target is configured.
    public var targetLine: [Point]? {
        guard let targetHours else { return nil }
        return [Point(time: week.interval.start, hours: 0), Point(time: week.interval.end, hours: targetHours)]
    }

    /// Builds the series.
    ///
    /// Non-deleted entries are clipped to `[week.start, min(now, week.end))`, overlapping
    /// intervals are merged (so overlaps count once), and a point is emitted at every merged
    /// interval start and end, plus a final point at `now` (or week end).
    public static func compute(entries: [Entry], week: Week, now: Date, targetHours: Double?) -> WeekSeries {
        let bounds = IntervalMath.upTo(week.interval, now: now)
        let merged = IntervalMath.merge(IntervalMath.clipped(entries, to: bounds, now: now))

        var points = [Point(time: week.interval.start, hours: 0)]
        var accumulated: TimeInterval = 0
        for iv in merged {
            if iv.start > points[points.count - 1].time {
                points.append(Point(time: iv.start, hours: accumulated / 3600))
            }
            accumulated += iv.duration
            points.append(Point(time: iv.end, hours: accumulated / 3600))
        }
        if points[points.count - 1].time < bounds.end {
            points.append(Point(time: bounds.end, hours: accumulated / 3600))
        }

        let daily = week.days.map { IntervalMath.seconds(of: merged, within: $0) / 3600 }
        let duration = week.interval.duration
        let fraction = duration > 0 ? min(1, max(0, now.timeIntervalSince(week.interval.start) / duration)) : 0
        let total = accumulated / 3600

        return WeekSeries(
            week: week,
            now: now,
            tracked: points,
            elapsedFraction: fraction,
            targetHours: targetHours,
            hoursCeiling: hoursCeiling(trackedHours: total, targetHours: targetHours),
            dailyHours: daily
        )
    }

    /// The y-axis ceiling rule (D11): the smallest multiple of 5 that is ≥ 10 and ≥ both
    /// `trackedHours` and `targetHours`.
    public static func hoursCeiling(trackedHours: Double, targetHours: Double?) -> Double {
        let needed = max(trackedHours, targetHours ?? 0, 10)
        return (needed / 5).rounded(.up) * 5
    }
}
