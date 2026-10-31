import Foundation

/// JSON coding for the `metadata` column: sorted keys for deterministic diffs, dates as
/// Unix seconds to match the timestamp columns (D24).
enum EntryMetadataCoding {
    /// Key used to preserve a metadata blob that no longer decodes, instead of dropping it.
    static let unparsedKey = "unparsed_metadata"

    static func encode(_ metadata: EntryMetadata) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(metadata)
        return String(decoding: data, as: UTF8.self)
    }

    /// Never throws: a blob that fails to decode is kept verbatim in `extra["unparsed_metadata"]`
    /// so one bad row cannot break every query and is not lost on the next update.
    static func decode(_ json: String) -> EntryMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let metadata = try? decoder.decode(EntryMetadata.self, from: Data(json.utf8)) {
            return metadata
        }
        return EntryMetadata(extra: [unparsedKey: json])
    }
}
