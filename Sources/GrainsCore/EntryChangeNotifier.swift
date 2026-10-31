import Foundation

/// Posts `.grainsEntriesDidChange` on the main queue (object: the store, userInfo "ids": [UUID]).
enum EntryChangeNotifier {
    /// userInfo key carrying the `[UUID]` of the entries a write touched.
    static let idsKey = "ids"

    static func post(from store: any EntryReading, ids: [UUID]) {
        guard !ids.isEmpty else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .grainsEntriesDidChange, object: store, userInfo: [idsKey: ids])
        }
    }
}

public extension Notification {
    /// The entry ids carried by a `.grainsEntriesDidChange` notification (empty otherwise).
    var grainsChangedEntryIDs: [UUID] {
        (userInfo?[EntryChangeNotifier.idsKey] as? [UUID]) ?? []
    }
}

/// Heartbeat helpers shared by both stores: two kv keys written together.
enum HeartbeatCoding {
    static func pairs(entryID: UUID, at date: Date) -> [(key: String, value: String?)] {
        [
            (EntryStoreKey.heartbeatEntryID, entryID.uuidString),
            (EntryStoreKey.heartbeatAt, String(date.timeIntervalSince1970)),
        ]
    }

    static let clearPairs: [(key: String, value: String?)] = [
        (EntryStoreKey.heartbeatEntryID, nil),
        (EntryStoreKey.heartbeatAt, nil),
    ]

    static func decode(entryID: String?, at: String?) -> (entryID: UUID, at: Date)? {
        guard let entryID, let id = UUID(uuidString: entryID),
              let at, let seconds = Double(at) else { return nil }
        return (id, Date(timeIntervalSince1970: seconds))
    }
}
