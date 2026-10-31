import CoreGraphics
import Foundation
import GrainsReports

/// Maps a `WeekSeries` onto the main lane (D11): x is clock time across the week, y is
/// cumulative hours from 0 to `hoursCeiling`. Pure; the renderer only strokes what this returns.
struct ChartGeometry {
    let series: WeekSeries
    let size: CGSize
    /// Vertical inset so a 2 pt line at 0 or at the ceiling is not clipped.
    let inset: CGFloat

    init(series: WeekSeries, size: CGSize, inset: CGFloat = 1.5) {
        self.series = series
        self.size = size
        self.inset = inset
    }

    private var start: Date { series.week.interval.start }
    private var duration: TimeInterval { max(1, series.week.interval.duration) }

    func x(_ time: Date) -> CGFloat {
        let f = min(1, max(0, time.timeIntervalSince(start) / duration))
        return CGFloat(f) * size.width
    }

    func y(_ hours: Double) -> CGFloat {
        let ceiling = max(series.hoursCeiling, 1)
        let f = min(1, max(0, hours / ceiling))
        return inset + (1 - CGFloat(f)) * (size.height - 2 * inset)
    }

    /// The tracked-hours polyline.
    var trackedPoints: [CGPoint] {
        series.tracked.map { CGPoint(x: x($0.time), y: y($0.hours)) }
    }

    /// The current moment's point (end of the actuals).
    var nowPoint: CGPoint? { trackedPoints.last }

    /// Grid hairlines at 0, ½ and the ceiling.
    var gridYs: [CGFloat] { [y(0), y(series.hoursCeiling / 2), y(series.hoursCeiling)] }

    /// The target trajectory, when configured.
    var targetPoints: [CGPoint]? {
        series.targetLine.map { $0.map { CGPoint(x: x($0.time), y: y($0.hours)) } }
    }

    /// x where the future (dotted baseline) begins; nil for a finished week.
    var futureStartX: CGFloat? {
        guard series.now < series.week.interval.end else { return nil }
        return x(series.now)
    }

    /// Centers of the seven day columns, for weekday markers.
    var dayCenters: [CGFloat] {
        series.week.days.map { x($0.start.addingTimeInterval($0.duration / 2)) }
    }

    /// VoiceOver summary (design.md "Accessibility").
    var accessibilitySummary: String {
        let hours = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), series.totalHours)
        let percent = Int((series.elapsedFraction * 100).rounded())
        return "\(hours) hours tracked, \(percent) percent of the week elapsed"
    }
}
