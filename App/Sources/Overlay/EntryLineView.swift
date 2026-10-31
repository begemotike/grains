import SwiftUI

/// The single editable line: parser-styled text, selection, marked text, the animated caret
/// (block in control mode, bar in typing mode) and the running dot. Rendering only; edits
/// arrive through `KeyCaptureView`.
struct EntryLineView: View {
    let editor: LineEditor
    let mode: InputMode
    let phase: OverlayPhase
    let isRunning: Bool
    let lastEdit: Date
    let switchPulse: Int
    let presentation: OverlayPresentation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var flash: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let layout = EntryLineLayout(text: editor.text, availableWidth: proxy.size.width)
            let scroll = layout.scrollOffset(caret: editor.caret)
            ZStack(alignment: .topLeading) {
                highlights(layout)
                caret(layout, behindText: true)
                Text(attributed(layout))
                    .font(Theme.mono(layout.fontSize))
                    .fixedSize()
                    .frame(height: EntryLineLayout.lineHeight)
                    .accessibilityLabel(editor.text.isEmpty ? "Empty entry" : editor.text)
                caret(layout, behindText: false)
            }
            .offset(x: -scroll)
            .frame(width: proxy.size.width, height: EntryLineLayout.lineHeight, alignment: .topLeading)
            .clipped()
        }
        .frame(height: EntryLineLayout.lineHeight)
        .overlay(alignment: .leading) {
            if isRunning {
                RunningDot(reduceMotion: reduceMotion).offset(x: -17)
            }
        }
        .onChange(of: switchPulse) {
            flash = 1
            withAnimation(.easeOut(duration: 0.45)) { flash = 0 }
        }
    }

    // MARK: Pieces

    private func attributed(_ layout: EntryLineLayout) -> AttributedString {
        let ns = editor.text as NSString
        guard ns.length > 0 else { return AttributedString("") }
        func piece(_ range: NSRange?, _ color: Color) -> AttributedString {
            guard let range, range.length > 0 else { return AttributedString() }
            var a = AttributedString(ns.substring(with: range))
            a.foregroundColor = color
            return a
        }
        let sub = Theme.sub(contrast)
        if phase == .stopped {
            return piece(NSRange(location: 0, length: ns.length), sub)
        }
        let s = layout.styling
        return piece(s.client, Theme.accent) + piece(s.separator, sub) + piece(s.note, Theme.text)
    }

    @ViewBuilder
    private func highlights(_ layout: EntryLineLayout) -> some View {
        let height = EntryLineLayout.lineHeight
        if editor.hasSelection {
            let r = editor.selectedRange
            let x0 = layout.x(at: r.location)
            Rectangle()
                .fill(Theme.accent.opacity(0.28))
                .frame(width: layout.x(at: NSMaxRange(r)) - x0, height: layout.fontSize * 1.25)
                .offset(x: x0, y: (height - layout.fontSize * 1.25) / 2)
        }
        if let marked = editor.markedRange {
            let x0 = layout.x(at: marked.location)
            Rectangle()
                .fill(Theme.text.opacity(0.8))
                .frame(width: max(1, layout.x(at: NSMaxRange(marked)) - x0), height: 1.5)
                .offset(x: x0, y: height / 2 + layout.fontSize * 0.55)
        }
        if flash > 0, let client = layout.styling.client, client.length > 0 {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.accent.opacity(0.35 * flash))
                .frame(width: layout.x(at: NSMaxRange(client)) + 6, height: layout.fontSize * 1.3)
                .offset(x: -3, y: (height - layout.fontSize * 1.3) / 2)
        }
    }

    /// Block caret sits behind the text (control mode), bar caret in front (typing mode).
    @ViewBuilder
    private func caret(_ layout: EntryLineLayout, behindText: Bool) -> some View {
        let isBlock = mode == .control
        if isBlock == behindText {
            let height = EntryLineLayout.lineHeight
            let caretHeight = layout.fontSize * (isBlock ? 1.12 : 1.2)
            let width = isBlock ? layout.blockWidth : 2.5
            let x = layout.x(at: editor.caret) - (isBlock ? 0 : 1.25)
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                RoundedRectangle(cornerRadius: isBlock ? 2 : 1.25)
                    .fill(Theme.accent.opacity(isBlock ? 0.85 : 1))
                    .frame(width: width, height: caretHeight)
                    .opacity(CaretBlink.opacity(mode: mode, lastEdit: lastEdit, now: context.date, smooth: !reduceMotion))
            }
            .frame(width: width, height: caretHeight)
            .offset(x: x, y: (height - caretHeight) / 2)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.07), value: x)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { presentation.caretRect = $0 }
            .accessibilityHidden(true)
        }
    }
}

/// Caret blink rules (design.md "Motion"): 1 Hz in control mode; solid while typing, blinking
/// again after 500 ms without an edit.
enum CaretBlink {
    static let restartDelay: TimeInterval = 0.5
    /// Development snapshots draw the caret solid (D57).
    nonisolated(unsafe) static var frozen = false

    static func opacity(mode: InputMode, lastEdit: Date, now: Date, smooth: Bool = true) -> Double {
        if frozen { return 1 }
        let t: TimeInterval
        switch mode {
        case .typing:
            let idle = now.timeIntervalSince(lastEdit)
            if idle < restartDelay { return 1 }
            t = idle - restartDelay
        case .control:
            t = now.timeIntervalSinceReferenceDate
        }
        let phase = t.truncatingRemainder(dividingBy: 1)
        guard smooth else { return phase < 0.5 ? 1 : 0 }
        // Soft square wave: on for ~half a second, quick fades.
        let v = 0.5 + 0.5 * cos(2 * .pi * phase)
        return min(1, max(0, (v - 0.5) * 3 + 0.5))
    }
}

/// The small pulsing accent dot before the line while running.
struct RunningDot: View {
    let reduceMotion: Bool
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true }
            }
            .accessibilityLabel("Running")
    }
}
