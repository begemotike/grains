import GrainsReports
import SwiftUI

/// The weekly graph (docs/weekly-graph.md, D11, D16): a 72 pt main lane of cumulative tracked
/// hours (soft fill, hairline grid at 0/½/ceiling, dotted future baseline, optional dotted
/// target, glowing active point while running), a 6 pt elapsed lane (0–100 % of the week)
/// and the weekday row. Draws only what `ChartGeometry` computes.
struct WeekChartView: View {
    let series: WeekSeries
    let isRunning: Bool
    let isCurrentWeek: Bool
    /// Changing this replays the 250 ms draw-in.
    let generation: Int
    let calendar: Calendar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var progress: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: 14)
                .padding(.bottom, 4)
            GeometryReader { proxy in
                mainLane(ChartGeometry(series: series, size: proxy.size))
            }
            .frame(height: Theme.Metrics.mainLane)
            GeometryReader { proxy in
                elapsedLane(width: proxy.size.width)
            }
            .frame(height: Theme.Metrics.elapsedLane)
            .padding(.top, Theme.Metrics.laneGap)
            GeometryReader { proxy in
                weekdays(ChartGeometry(series: series, size: proxy.size))
            }
            .frame(height: Theme.Metrics.weekdayRow)
            .padding(.top, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ChartGeometry(series: series, size: .zero).accessibilitySummary)
        .onAppear { replay() }
        .onChange(of: generation) { replay() }
    }

    private func replay() {
        guard !reduceMotion else { progress = 1; return }
        progress = 0
        withAnimation(.easeOut(duration: 0.25)) { progress = 1 }
    }

    private var sub: Color { Theme.sub(contrast) }

    // MARK: Header: ceiling label, week id, elapsed label

    private var header: some View {
        HStack(spacing: 0) {
            Text("\(Int(series.hoursCeiling))h")
                .foregroundStyle(sub)
            Spacer()
            if !isCurrentWeek {
                Text(series.week.isoIdentifier)
                    .foregroundStyle(Theme.text)
                Text("  ·  ").foregroundStyle(sub)
            }
            Text("\(Int((series.elapsedFraction * 100).rounded()))% of week")
                .foregroundStyle(Theme.elapsed)
        }
        .font(Theme.mono(10))
    }

    // MARK: Main lane

    private func mainLane(_ g: ChartGeometry) -> some View {
        let points = g.trackedPoints
        let lineColor = isRunning ? Theme.accent : Theme.text.opacity(0.85)
        let fillColor = isRunning ? Theme.accent : Theme.text
        return ZStack(alignment: .topLeading) {
            Polyline.horizontal(ys: g.gridYs, width: g.size.width)
                .stroke(sub.opacity(0.35), lineWidth: 0.5)
            if let future = g.futureStartX {
                Path { p in
                    p.move(to: CGPoint(x: future, y: g.y(0)))
                    p.addLine(to: CGPoint(x: g.size.width, y: g.y(0)))
                }
                .stroke(sub, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0.1, 5]))
            }
            if let target = g.targetPoints {
                Polyline(points: target)
                    .stroke(Theme.target, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 4]))
            }
            AreaUnderLine(points: points, baseline: g.y(0))
                .fill(LinearGradient(
                    colors: [fillColor.opacity(isRunning ? Theme.accentDimOpacity : 0.10), fillColor.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom))
                .opacity(Double(progress))
            Polyline(points: points)
                .trim(from: 0, to: progress)
                .stroke(lineColor, style: StrokeStyle(lineWidth: Theme.Metrics.lineWidth, lineCap: .round, lineJoin: .round))
            if isCurrentWeek, let now = g.nowPoint {
                ActivePoint(isRunning: isRunning, reduceMotion: reduceMotion)
                    .position(now)
                    .opacity(Double(progress))
            }
        }
        .frame(width: g.size.width, height: g.size.height)
    }

    // MARK: Elapsed lane

    private func elapsedLane(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(sub.opacity(0.18))
            Capsule()
                .fill(Theme.elapsed.opacity(0.6))
                .frame(width: max(Theme.Metrics.elapsedLane, width * CGFloat(series.elapsedFraction) * progress))
                .opacity(series.elapsedFraction > 0 ? 1 : 0)
        }
    }

    // MARK: Weekday row

    private func weekdays(_ g: ChartGeometry) -> some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let now = series.now
        return ZStack(alignment: .topLeading) {
            ForEach(Array(series.week.days.enumerated()), id: \.offset) { index, day in
                let weekday = calendar.component(.weekday, from: day.start)
                let symbol = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "·"
                Text(symbol)
                    .font(Theme.mono(Theme.Size.weekday))
                    .foregroundStyle(color(for: day, now: now))
                    .position(x: g.dayCenters[index], y: g.size.height / 2)
            }
        }
    }

    /// Past days dim, today bright, future dimmer still.
    private func color(for day: DateInterval, now: Date) -> Color {
        if day.contains(now) && now < day.end { return Theme.text }
        return day.end <= now ? sub : sub.opacity(0.45)
    }
}

/// The current-moment point: 5 pt radius, 12 pt glow breathing over 2 s while running.
struct ActivePoint: View {
    let isRunning: Bool
    let reduceMotion: Bool
    @State private var breathe = false

    var body: some View {
        let r = Theme.Metrics.activePointRadius
        ZStack {
            if isRunning {
                Circle()
                    .fill(Theme.accent.opacity(breathe ? 0.10 : 0.35))
                    .frame(width: Theme.Metrics.activeGlowRadius * 2, height: Theme.Metrics.activeGlowRadius * 2)
                    .blur(radius: 3)
            }
            Circle()
                .fill(isRunning ? Theme.accent : Theme.text)
                .frame(width: isRunning ? r * 2 : r * 1.4, height: isRunning ? r * 2 : r * 1.4)
        }
        .onAppear { startBreathing() }
        .onChange(of: isRunning) { startBreathing() }
    }

    private func startBreathing() {
        guard isRunning, !reduceMotion else { breathe = false; return }
        withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { breathe = true }
    }
}

/// A polyline through `points`.
struct Polyline: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for point in points.dropFirst() { p.addLine(to: point) }
        return p
    }

    /// Horizontal hairlines at `ys`.
    static func horizontal(ys: [CGFloat], width: CGFloat) -> Path {
        var p = Path()
        for y in ys {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: width, y: y))
        }
        return p
    }
}

/// The region between the polyline and the zero baseline.
struct AreaUnderLine: Shape {
    var points: [CGPoint]
    var baseline: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first, let last = points.last else { return p }
        p.move(to: CGPoint(x: first.x, y: baseline))
        for point in points { p.addLine(to: point) }
        p.addLine(to: CGPoint(x: last.x, y: baseline))
        p.closeSubpath()
        return p
    }
}
