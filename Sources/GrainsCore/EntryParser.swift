import Foundation

/// Splits `Client - note` into a provisional client label and a note.
///
/// Rules (from the product spec):
/// - The separator is the first occurrence of ` - ` (space, hyphen-minus, space). It is optional.
/// - Text before it, trimmed, is `clientText`; text after it, trimmed, is `note`.
/// - With no separator the whole trimmed string is the note and `clientText` is nil
///   (e.g. `Administrative work`).
/// - Empty pieces become nil. The original string is never modified by the parser; callers
///   always store `rawText` unchanged.
/// - En dash / em dash with spaces (` – `, ` — `) are accepted as separators too, because macOS
///   autocorrect turns ` - ` into them.
public enum EntryParser {
    public struct Result: Hashable, Sendable {
        public var clientText: String?
        public var note: String?
        /// Range of the separator in the original string, for UI styling. Nil when absent.
        public var separatorRange: Range<String.Index>?
        public init(clientText: String?, note: String?, separatorRange: Range<String.Index>?) {
            self.clientText = clientText
            self.note = note
            self.separatorRange = separatorRange
        }
    }

    public static let separators = [" - ", " – ", " — "]

    public static func parse(_ raw: String) -> Result {
        var best: Range<String.Index>? = nil
        for sep in separators {
            if let r = raw.range(of: sep), best == nil || r.lowerBound < best!.lowerBound {
                best = r
            }
        }
        func clean(_ s: Substring) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        guard let sep = best else {
            return Result(clientText: nil, note: clean(raw[...]), separatorRange: nil)
        }
        return Result(
            clientText: clean(raw[..<sep.lowerBound]),
            note: clean(raw[sep.upperBound...]),
            separatorRange: sep
        )
    }
}
