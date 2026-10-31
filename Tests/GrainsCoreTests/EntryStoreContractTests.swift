import XCTest
@testable import GrainsCore

/// Behaviour every `EntryWriting` must share. Runs against `InMemoryEntryStore` here and
/// against `SQLiteEntryStore` (temp file) in the subclass below.
class InMemoryEntryStoreContractTests: XCTestCase {
    let date = TestDate()

    func makeStore() throws -> any EntryWriting {
        InMemoryEntryStore(now: date.closure)
    }

    var t0: Date { TestDate.reference }

    func testInsertFetchUpdate() throws {
        let store = try makeStore()
        var entry = Entry.fixture("Denali - iPad enrollment", start: t0, minutes: 30)
        try store.insert(entry)
        XCTAssertEqual(try store.entry(id: entry.id), entry)

        entry.note = "MDM enrollment"
        entry.updatedAt = t0.addingTimeInterval(3600)
        try store.update(entry)
        XCTAssertEqual(try store.entry(id: entry.id)?.note, "MDM enrollment")
        XCTAssertEqual(try store.entry(id: entry.id)?.updatedAt, t0.addingTimeInterval(3600))
        XCTAssertEqual(try store.entry(id: entry.id)?.rawText, "Denali - iPad enrollment")
    }

    func testUpdateBumpsUpdatedAtWhenCallerDidNot() throws {
        let store = try makeStore()
        var entry = Entry.fixture("A - b", start: t0, minutes: 5)
        try store.insert(entry)
        date.set(t0.addingTimeInterval(7200))
        entry.note = "changed"
        try store.update(entry)
        XCTAssertEqual(try store.entry(id: entry.id)?.updatedAt, t0.addingTimeInterval(7200))
    }

    func testUpdateUnknownIDThrowsNotFound() throws {
        let store = try makeStore()
        let entry = Entry.fixture("A", start: t0, minutes: 1)
        XCTAssertThrowsError(try store.update(entry)) { error in
            XCTAssertEqual(error as? EntryStoreError, .notFound(entry.id))
        }
    }

    func testDuplicateInsertThrows() throws {
        let store = try makeStore()
        let entry = Entry.fixture("A", start: t0, minutes: 1)
        try store.insert(entry)
        XCTAssertThrowsError(try store.insert(entry)) { error in
            XCTAssertEqual(error as? EntryStoreError, .duplicateID(entry.id))
        }
    }

    func testSecondRunningEntryIsRejected() throws {
        let store = try makeStore()
        let first = Entry.fixture("A", start: t0, minutes: nil)
        try store.insert(first)
        let second = Entry.fixture("B", start: t0.addingTimeInterval(60), minutes: nil)
        XCTAssertThrowsError(try store.insert(second)) { error in
            XCTAssertEqual(error as? EntryStoreError, .anotherEntryRunning)
        }
        XCTAssertEqual(try store.runningEntry()?.id, first.id)
        XCTAssertNil(try store.entry(id: second.id))
    }

    func testCommitIsAtomic() throws {
        let store = try makeStore()
        let running = Entry.fixture("A", start: t0, minutes: nil)
        try store.insert(running)
        var stopped = running
        stopped.stoppedAt = t0.addingTimeInterval(60)
        let next = Entry.fixture("B", start: t0.addingTimeInterval(60), minutes: nil)
        // Fails on the duplicate id: the stop must be rolled back too.
        XCTAssertThrowsError(try store.commit([.update(stopped), .insert(next), .insert(running)]))
        XCTAssertEqual(try store.runningEntry()?.id, running.id)
        XCTAssertNil(try store.entry(id: next.id))

        try store.commit([.update(stopped), .insert(next)])
        XCTAssertEqual(try store.runningEntry()?.id, next.id)
        XCTAssertEqual(try store.entry(id: running.id)?.stoppedAt, t0.addingTimeInterval(60))
    }

    func testSoftDeleteHidesEverywhere() throws {
        let store = try makeStore()
        let kept = Entry.fixture("Denali - kept", start: t0, minutes: 10)
        let gone = Entry.fixture("Denali - gone", start: t0.addingTimeInterval(-3600), minutes: 10)
        try store.insert(kept)
        try store.insert(gone)
        try store.softDelete(id: gone.id, at: t0)

        XCTAssertNil(try store.entry(id: gone.id))
        XCTAssertEqual(try store.recentEntries(limit: 10).map(\.id), [kept.id])
        XCTAssertEqual(try store.search("gone", limit: 10), [])
        XCTAssertEqual(try store.entries(overlapping: DateInterval(start: t0.addingTimeInterval(-7200), duration: 86400)).map(\.id), [kept.id])
        XCTAssertEqual(try store.clientLabels().first?.count, 1)
        XCTAssertEqual(try store.earliestStart(), t0)
        XCTAssertThrowsError(try store.softDelete(id: UUID(), at: t0))
    }

    func testSoftDeletedRunningEntryFreesTheRunningSlot() throws {
        let store = try makeStore()
        let first = Entry.fixture("A", start: t0, minutes: nil)
        try store.insert(first)
        try store.softDelete(id: first.id, at: t0)
        XCTAssertNil(try store.runningEntry())
        try store.insert(Entry.fixture("B", start: t0, minutes: nil))
        XCTAssertEqual(try store.runningEntry()?.rawText, "B")
    }

    func testOverlappingQueries() throws {
        let store = try makeStore()
        let day = DateInterval(start: t0, duration: 86400)
        let before = Entry.fixture("before", start: t0.addingTimeInterval(-7200), minutes: 60)
        let crossesStart = Entry.fixture("crosses start", start: t0.addingTimeInterval(-1800), minutes: 60)
        let inside = Entry.fixture("inside", start: t0.addingTimeInterval(3600), minutes: 30)
        let endsAtStart = Entry.fixture("ends at start", start: t0.addingTimeInterval(-600), minutes: 10)
        let after = Entry.fixture("after", start: day.end, minutes: 30)
        let running = Entry.fixture("running", start: t0.addingTimeInterval(80000), minutes: nil)
        for entry in [before, crossesStart, inside, endsAtStart, after, running] { try store.insert(entry) }

        XCTAssertEqual(
            try store.entries(overlapping: day).map(\.rawText),
            ["crosses start", "inside", "running"]
        )
        // A running entry that started before the interval is included too.
        let tomorrow = DateInterval(start: day.end, duration: 86400)
        XCTAssertEqual(try store.entries(overlapping: tomorrow).map(\.rawText), ["running", "after"])
        // ...but not once the interval ends before it started.
        let yesterday = DateInterval(start: t0.addingTimeInterval(-86400), duration: 86400)
        XCTAssertEqual(try store.entries(overlapping: yesterday).map(\.rawText), ["before", "crosses start", "ends at start"])
    }

    func testRecentAndEarliest() throws {
        let store = try makeStore()
        XCTAssertNil(try store.earliestStart())
        for index in 0..<5 {
            try store.insert(Entry.fixture("e\(index)", start: t0.addingTimeInterval(Double(index) * 3600), minutes: 10))
        }
        XCTAssertEqual(try store.recentEntries(limit: 2).map(\.rawText), ["e4", "e3"])
        XCTAssertEqual(try store.earliestStart(), t0)
    }

    func testSearchIsCaseInsensitiveAcrossFields() throws {
        let store = try makeStore()
        try store.insert(Entry.fixture("Denali - iPad enrollment", start: t0, minutes: 10))
        try store.insert(Entry.fixture("Ölwein – Firewall", start: t0.addingTimeInterval(60), minutes: 10))
        try store.insert(Entry.fixture("Administrative work", start: t0.addingTimeInterval(120), minutes: 10))
        try store.insert(Entry.fixture("100% done_ish", start: t0.addingTimeInterval(180), minutes: 10))

        XCTAssertEqual(try store.search("IPAD", limit: 10).map(\.rawText), ["Denali - iPad enrollment"])
        XCTAssertEqual(try store.search("ölwein", limit: 10).map(\.rawText), ["Ölwein – Firewall"])
        XCTAssertEqual(try store.search("e", limit: 2).count, 2)
        XCTAssertEqual(try store.search("%", limit: 10).map(\.rawText), ["100% done_ish"])
        XCTAssertEqual(try store.search("_", limit: 10).map(\.rawText), ["100% done_ish"])
        XCTAssertEqual(try store.search("  ", limit: 10), [])
    }

    func testClientLabelsGroupCaseInsensitivelyAndCountRunning() throws {
        let store = try makeStore()
        try store.insert(Entry.fixture("denali - a", start: t0, minutes: 30))
        try store.insert(Entry.fixture("Denali - b", start: t0.addingTimeInterval(3600), minutes: 15))
        try store.insert(Entry.fixture("Admin work", start: t0.addingTimeInterval(7200), minutes: 15))
        try store.insert(Entry.fixture("Arctic - running", start: t0.addingTimeInterval(9000), minutes: nil))
        date.set(t0.addingTimeInterval(9000 + 600))

        let labels = try store.clientLabels()
        XCTAssertEqual(labels.map(\.clientText), ["Arctic", "Denali"])
        XCTAssertEqual(labels[0].count, 1)
        XCTAssertEqual(labels[0].totalSeconds, 600, accuracy: 0.001)
        XCTAssertEqual(labels[1].count, 2)
        XCTAssertEqual(labels[1].totalSeconds, 45 * 60, accuracy: 0.001)
    }

    func testMetadataRoundTrip() throws {
        let store = try makeStore()
        var entry = Entry.fixture("A - b", start: t0, minutes: 5)
        entry.clientID = UUID()
        entry.metadata = EntryMetadata(
            recovered: .init(lastHeartbeat: t0.addingTimeInterval(270), noticedAt: t0.addingTimeInterval(9999), reconciled: false),
            extra: ["clock_jump": "-3600", "source": "import/v1", "z": "ü"]
        )
        try store.insert(entry)
        XCTAssertEqual(try store.entry(id: entry.id), entry)
    }

    func testHeartbeatAndKeyValues() throws {
        let store = try makeStore()
        XCTAssertNil(try store.readHeartbeat())
        let id = UUID()
        try store.writeHeartbeat(entryID: id, at: t0.addingTimeInterval(30.5))
        let heartbeat = try XCTUnwrap(store.readHeartbeat())
        XCTAssertEqual(heartbeat.entryID, id)
        XCTAssertEqual(heartbeat.at, t0.addingTimeInterval(30.5))
        try store.clearHeartbeat()
        XCTAssertNil(try store.readHeartbeat())

        try store.writeValue("1", forKey: EntryStoreKey.cleanShutdown)
        XCTAssertEqual(try store.readValue(forKey: EntryStoreKey.cleanShutdown), "1")
        try store.writeValue("0", forKey: EntryStoreKey.cleanShutdown)
        XCTAssertEqual(try store.readValue(forKey: EntryStoreKey.cleanShutdown), "0")
        try store.writeValue(nil, forKey: EntryStoreKey.cleanShutdown)
        XCTAssertNil(try store.readValue(forKey: EntryStoreKey.cleanShutdown))
    }

    func testWritesPostChangeNotificationOnMain() throws {
        let store = try makeStore()
        let entry = Entry.fixture("A", start: t0, minutes: 1)
        let posted = expectation(forNotification: .grainsEntriesDidChange, object: store) { note in
            XCTAssertTrue(Thread.isMainThread)
            return note.grainsChangedEntryIDs == [entry.id]
        }
        try store.insert(entry)
        wait(for: [posted], timeout: 2)
    }
}

final class SQLiteEntryStoreContractTests: InMemoryEntryStoreContractTests {
    override func makeStore() throws -> any EntryWriting {
        try SQLiteEntryStore.open(at: temporaryDatabaseURL(for: self), now: date.closure)
    }
}
