import Foundation
import GrainsCore

/// Inline completion ("ghost text") for the entry line while typing (D67). Pure: the model
/// builds a `Source` from its cached recent entries and client labels whenever the store
/// changes, and the key path only calls `suggestion(for:)`, which never touches the database.
enum Autocomplete {
    /// How many recent entries the model caches for suggestions.
    static let recentLimit = 500

    /// Pre-ranked candidates, built off the key path.
    struct Source: Equatable, Sendable {
        /// Distinct raw texts of non-deleted entries, most recent first.
        var rawTexts: [String]
        /// Client labels (most recent spelling), most recently used first.
        var clientLabels: [String]

        static let empty = Source(rawTexts: [], clientLabels: [])

        init(rawTexts: [String], clientLabels: [String]) {
            self.rawTexts = rawTexts
            self.clientLabels = clientLabels
        }

        /// `entries` in any order (deleted ones are dropped); `labels` from
        /// `EntryReading.clientLabels()`, whose `clientText` is already the most recent spelling.
        /// Labels rank by their latest use among `entries`, then by entry count, then name.
        init(entries: [Entry], labels: [ClientLabelCount]) {
            let live = entries.filter { !$0.isDeleted }.sorted {
                $0.startedAt != $1.startedAt ? $0.startedAt > $1.startedAt : $0.id.uuidString > $1.id.uuidString
            }
            var seen = Set<String>()
            rawTexts = live.map(\.rawText).filter { seen.insert($0).inserted }

            var lastUse: [String: Int] = [:]
            for (index, entry) in live.enumerated() {
                guard let client = entry.clientText?.lowercased(), lastUse[client] == nil else { continue }
                lastUse[client] = index
            }
            clientLabels = labels
                .filter { !$0.clientText.trimmingCharacters(in: .whitespaces).isEmpty }
                .sorted { a, b in
                    let ra = lastUse[a.clientText.lowercased()] ?? Int.max
                    let rb = lastUse[b.clientText.lowercased()] ?? Int.max
                    if ra != rb { return ra < rb }
                    if a.count != b.count { return a.count > b.count }
                    return a.clientText.localizedCaseInsensitiveCompare(b.clientText) == .orderedAscending
                }
                .map(\.clientText)
        }

        /// The text to show after the caret for `typed`, or nil. While `typed` has no
        /// separator yet, a client label plus ` - ` is preferred; otherwise (or when no label
        /// matches) the most recent raw text that has `typed` as a case-insensitive prefix and
        /// is longer than it.
        func suggestion(for typed: String) -> String? {
            guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            if EntryParser.parse(typed).separatorRange == nil {
                for label in clientLabels {
                    if let rest = Autocomplete.remainder(of: label + " - ", after: typed) { return rest }
                }
            }
            for raw in rawTexts {
                if let rest = Autocomplete.remainder(of: raw, after: typed) { return rest }
            }
            return nil
        }
    }

    /// The part of `candidate` after a case-insensitive prefix `typed`, or nil when `typed`
    /// is not a prefix or nothing remains (an exact match is not a completion).
    static func remainder(of candidate: String, after typed: String) -> String? {
        guard let range = candidate.range(of: typed, options: [.anchored, .caseInsensitive]),
              range.upperBound < candidate.endIndex else { return nil }
        return String(candidate[range.upperBound...])
    }
}
