import AppKit
import SwiftUI

/// Design tokens from docs/design.md. A light theme (roadmap) is a change to this table only.
enum Theme {
    /// Hex values of the palette, kept as data so tests can pin them to design.md.
    enum Hex {
        static let bg: UInt32 = 0x161a20
        static let sub: UInt32 = 0x646f7e
        /// `sub` under Increase Contrast.
        static let subHighContrast: UInt32 = 0x8f9aab
        static let text: UInt32 = 0xd1d7e0
        static let accent: UInt32 = 0xe2b714
        static let elapsed: UInt32 = 0x8a93a3
        static let error: UInt32 = 0xca4754
    }

    static let bg = Color(hex: Hex.bg)
    static let sub = Color(hex: Hex.sub)
    static let text = Color(hex: Hex.text)
    static let accent = Color(hex: Hex.accent)
    /// Tracked-hours fill: accent at 25%.
    static let accentDim = Color(hex: Hex.accent).opacity(accentDimOpacity)
    static let elapsed = Color(hex: Hex.elapsed)
    /// Target trajectory (drawn dotted).
    static let target = Color(hex: Hex.sub)
    static let error = Color(hex: Hex.error)

    static let accentDimOpacity = 0.25
    static let panelOpacity = 0.96
    static let hairlineOpacity = 0.06

    /// `sub`, brightened when the user asked for more contrast.
    static func sub(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? Color(hex: Hex.subHighContrast) : sub
    }

    /// Overlay geometry (design.md "Overlay geometry" and "Chart geometry").
    enum Metrics {
        static let overlayWidth: CGFloat = 640
        static let cornerRadius: CGFloat = 14
        static let topFraction: CGFloat = 0.22
        static let horizontalPadding: CGFloat = 28
        static let shadowRadius: CGFloat = 30   // CSS blur 60 ≈ SwiftUI radius 30
        static let shadowY: CGFloat = 24
        static let mainLane: CGFloat = 72
        static let elapsedLane: CGFloat = 6
        static let laneGap: CGFloat = 10
        static let weekdayRow: CGFloat = 14
        static let lineWidth: CGFloat = 2
        static let activePointRadius: CGFloat = 5
        static let activeGlowRadius: CGFloat = 12
    }

    /// Type scale (design.md "Typography"). All SF Mono with tabular numerals (D21).
    enum Size {
        static let entryLine: CGFloat = 28
        static let entryLineMinimum: CGFloat = 18
        static let elapsed: CGFloat = 44
        static let metric: CGFloat = 22
        static let metricLabel: CGFloat = 11
        static let modeLabel: CGFloat = 11
        static let weekday: CGFloat = 10
    }

    /// Metric label tracking, +0.08 em.
    static let labelTracking: CGFloat = 0.08 * Size.metricLabel

    /// Monospaced system font (SF Mono) with tabular numerals.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    /// The AppKit font matching `mono(_:weight:)`, used to measure the entry line.
    static func monoNSFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

extension Color {
    /// `0xRRGGBB`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

extension NSColor {
    /// `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}
