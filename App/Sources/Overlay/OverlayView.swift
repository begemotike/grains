import GrainsCore
import SwiftUI

/// The whole panel content: the card at the top, transparent room for its shadow around it,
/// and the entrance/exit transition (120 ms scale 0.98→1 + fade in, 90 ms fade out).
struct OverlayRootView: View {
    let model: AppModel
    let presentation: OverlayPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OverlayView(model: model, presentation: presentation)
            .scaleEffect(presentation.isPresented || reduceMotion ? 1 : 0.98, anchor: .top)
            .opacity(presentation.isPresented ? 1 : 0)
            .padding(.top, OverlayPlacement.margins.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The overlay card (design.md): entry line, mode label, stats, recovery notice, chart.
struct OverlayView: View {
    let model: AppModel
    let presentation: OverlayPresentation
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EntryLineView(
                editor: model.line,
                completion: model.completion,
                mode: model.mode,
                phase: model.phase,
                isRunning: model.timer.isRunning,
                lastEdit: model.lastEdit,
                switchPulse: model.switchPulse,
                presentation: presentation
            )
            Text(model.modeLabel)
                .font(Theme.mono(Theme.Size.modeLabel))
                .foregroundStyle(model.timer.isRunning ? Theme.accent : Theme.sub(contrast))
                .padding(.top, 6)
                .accessibilityLabel("Mode: \(model.modeLabel)")
            StatsRowView(model: model)
                .padding(.top, 24)
            if let notice = model.recoveryNotice {
                Text(notice)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.error)
                    .padding(.top, 14)
                    .transition(.opacity)
            }
            WeekChartView(
                series: model.series,
                isRunning: model.timer.isRunning,
                isCurrentWeek: model.isViewingCurrentWeek,
                generation: model.chartGeneration,
                calendar: model.spec.calendar
            )
            .padding(.top, 22)
        }
        .padding(.horizontal, Theme.Metrics.horizontalPadding)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .frame(width: Theme.Metrics.overlayWidth, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Metrics.cornerRadius, style: .continuous)
            // The shadow is cut out under the card so it never shows through the 96% fill.
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(0.55), radius: Theme.Metrics.shadowRadius, y: Theme.Metrics.shadowY)
                .mask {
                    Rectangle()
                        .padding(-160)
                        .overlay(shape.blendMode(.destinationOut))
                        .compositingGroup()
                }
            shape
                .fill(Theme.bg.opacity(Theme.panelOpacity))
                .overlay(shape.strokeBorder(Color.white.opacity(Theme.hairlineOpacity), lineWidth: 1))
        }
        .environment(\.colorScheme, .dark)
    }
}

/// Session counter (44 pt) with the week and today metrics (22 pt) and their labels.
struct StatsRowView: View {
    let model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let running = model.timer.isRunning
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Formatting.clock(model.displayedElapsed))
                    .font(Theme.mono(Theme.Size.elapsed, weight: .light))
                    .foregroundStyle(running ? Theme.accent : Theme.sub(contrast))
                    .id(model.timer.running?.id)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: model.timer.running?.id)
                    .animation(.easeOut(duration: 0.4), value: running)
                    .accessibilityLabel("Session \(Formatting.clock(model.displayedElapsed))")
                MetricLabel(text: "session")
            }
            Spacer(minLength: 16)
            Metric(value: Formatting.hours(model.visibleWeekHours),
                   label: model.isViewingCurrentWeek ? "week" : model.visibleWeek.isoIdentifier)
            Metric(value: Formatting.hours(model.stats.todayHours), label: "today")
                .padding(.leading, 40)
        }
    }
}

/// A 22 pt number over an 11 pt uppercase label.
struct Metric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value)
                .font(Theme.mono(Theme.Size.metric))
                .foregroundStyle(Theme.text)
            MetricLabel(text: label)
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

/// 11 pt uppercase label with +0.08 em tracking.
struct MetricLabel: View {
    let text: String
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(Theme.Size.metricLabel))
            .tracking(Theme.labelTracking)
            .foregroundStyle(Theme.sub(contrast))
    }
}
