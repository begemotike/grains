import AppKit
import GrainsCore

/// Measures and styles the entry line: font size fit, caret/selection x positions, horizontal
/// scroll, and the parser's client/separator/note ranges. Uses the same SF Mono `NSFont` the
/// view renders with, so positions match the glyphs.
struct EntryLineLayout {
    /// UTF-16 ranges of the parsed pieces.
    struct Styling: Equatable {
        var client: NSRange?
        var separator: NSRange?
        var note: NSRange
    }

    let text: String
    let fontSize: CGFloat
    let font: NSFont
    let availableWidth: CGFloat

    init(text: String, availableWidth: CGFloat) {
        self.text = text
        self.availableWidth = availableWidth
        var size = Theme.Size.entryLine
        while size > Theme.Size.entryLineMinimum {
            let candidate = Theme.monoNSFont(size)
            if Self.width(of: text, font: candidate) + Self.blockWidth(candidate) <= availableWidth { break }
            size -= 1
        }
        fontSize = size
        font = Theme.monoNSFont(size)
    }

    /// Fixed line box height (from the largest size) so the layout never jumps.
    static var lineHeight: CGFloat {
        let font = Theme.monoNSFont(Theme.Size.entryLine)
        return ceil(font.ascender - font.descender + font.leading) + 4
    }

    static func width(of string: String, font: NSFont) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        return ceil((string as NSString).size(withAttributes: [.font: font]).width * 100) / 100
    }

    static func blockWidth(_ font: NSFont) -> CGFloat {
        width(of: "0", font: font)
    }

    var blockWidth: CGFloat { Self.blockWidth(font) }
    var textWidth: CGFloat { Self.width(of: text, font: font) }

    /// x of the boundary before UTF-16 offset `offset`.
    func x(at offset: Int) -> CGFloat {
        let ns = text as NSString
        let clamped = min(max(0, offset), ns.length)
        return Self.width(of: ns.substring(to: clamped), font: font)
    }

    /// Horizontal scroll so the caret stays visible when even the minimum size overflows.
    func scrollOffset(caret: Int) -> CGFloat {
        let total = textWidth + blockWidth
        guard total > availableWidth else { return 0 }
        let caretRight = x(at: caret) + blockWidth + 4
        return min(max(0, caretRight - availableWidth), total - availableWidth)
    }

    /// Client accent / separator muted / note text (design.md typography table).
    var styling: Styling {
        let parsed = EntryParser.parse(text)
        let length = (text as NSString).length
        guard let sep = parsed.separatorRange else {
            return Styling(client: nil, separator: nil, note: NSRange(location: 0, length: length))
        }
        let sepRange = NSRange(sep, in: text)
        return Styling(
            client: NSRange(location: 0, length: sepRange.location),
            separator: sepRange,
            note: NSRange(location: NSMaxRange(sepRange), length: length - NSMaxRange(sepRange))
        )
    }
}
