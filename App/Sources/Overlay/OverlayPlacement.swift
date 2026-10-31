import CoreGraphics

/// Where the overlay panel goes (design.md "Overlay geometry", D15). Pure math, tested.
///
/// The panel is larger than the visible card by `margins`, so the SwiftUI shadow has room;
/// the transparent margin passes clicks through.
enum OverlayPlacement {
    /// Transparent room around the card for its shadow (0 24 60).
    struct Margins: Equatable {
        var horizontal: CGFloat = 70
        var top: CGFloat = 40
        var bottom: CGFloat = 100
    }

    static let margins = Margins()
    /// The panel is tall enough for the tallest card (recovery notice + target label).
    static let cardMaxHeight: CGFloat = 470

    /// Size of the panel window.
    static func panelSize(cardWidth: CGFloat = Theme.Metrics.overlayWidth, margins: Margins = margins) -> CGSize {
        CGSize(width: cardWidth + 2 * margins.horizontal, height: cardMaxHeight + margins.top + margins.bottom)
    }

    /// The card's top-left in screen coordinates (AppKit, y up): centered horizontally on
    /// `screen`, its top edge at `topFraction` of the screen height from the top, kept inside
    /// `visible` (the area below the menu bar and above the Dock).
    static func cardOrigin(screen: CGRect, visible: CGRect, cardWidth: CGFloat = Theme.Metrics.overlayWidth, topFraction: CGFloat = Theme.Metrics.topFraction) -> CGPoint {
        let x = screen.midX - cardWidth / 2
        var top = screen.maxY - screen.height * topFraction
        top = min(top, visible.maxY)
        return CGPoint(x: x.rounded(), y: top.rounded())
    }

    /// The panel frame for `screen`.
    static func panelFrame(screen: CGRect, visible: CGRect, cardWidth: CGFloat = Theme.Metrics.overlayWidth, margins: Margins = margins) -> CGRect {
        let size = panelSize(cardWidth: cardWidth, margins: margins)
        let top = cardOrigin(screen: screen, visible: visible, cardWidth: cardWidth)
        return CGRect(
            x: top.x - margins.horizontal,
            y: top.y + margins.top - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The screen frame containing `point`, else the first one.
    static func screen(containing point: CGPoint, in frames: [CGRect]) -> CGRect? {
        frames.first { $0.contains(point) } ?? frames.first(where: { point.x >= $0.minX && point.x <= $0.maxX && point.y >= $0.minY && point.y <= $0.maxY }) ?? frames.first
    }
}
