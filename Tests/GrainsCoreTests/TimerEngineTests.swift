import XCTest
@testable import GrainsCore

final class TimerEngineTests: XCTestCase {
    let clock = TestClock()
    let date = TestDate()
    var t0: Date { TestDate.reference }

    private func makeEngine(_ store: any EntryWriting) -> TimerEngine {
        TimerEngine(store: store, clock: clock, now: date.closure)
    }

    private func makeStore() -> InMemoryEntryStore {
        InMemoryEntryStore(now: date.closure)
    }

    // MARK: Start / stop / switch / toggle

    func testStartAndStop() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        await engine.start()

        let entry = try await engine.start(rawText: "Denali - iPad enrollment")
        XCTAssertEqual(entry.clientText, "Denali")
        XCTAssertEqual(entry.note, "iPad enrollment")
        XCTAssertEqual(entry.startedAt, t0)
        XCTAssertEqual(try store.runningEntry()?.id, entry.id)
        let running = await engine.state
        XCTAssertEqual(running.running?.id, entry.id)

        advanceBoth(90, clock: clock, date: date)
        let stopped = try await engine.stop()
        XCTAssertEqual(stopped?.stoppedAt, t0.addingTimeInterval(90))
        XCTAssertEqual(try store.entry(id: entry.id)?.stoppedAt, t0.addingTimeInterval(90))
        XCTAssertNil(try store.runningEntry())
        XCTAssertNil(try store.readHeartbeat())
        let idle = await engine.state
        XCTAssertEqual(idle, .idle)

        let again = try await engine.stop()
        XCTAssertNil(again, "stop when idle is a no-op")
    }

    func testSwitchStopsPreviousAtTheSameInstant() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        let first = try await engine.start(rawText: "Denali - a")
        advanceBoth(600, clock: clock, date: date)
        let second = try await engine.start(rawText: "Arctic - b")

        let stoppedFirst = try XCTUnwrap(store.entry(id: first.id))
        XCTAssertEqual(stoppedFirst.stoppedAt, second.startedAt)
        XCTAssertEqual(second.startedAt, t0.addingTimeInterval(600))
        XCTAssertEqual(try store.runningEntry()?.id, second.id)
        XCTAssertEqual(try store.readHeartbeat()?.entryID, second.id)
        let elapsed = await engine.state.elapsed
        XCTAssertEqual(elapsed, .zero)
    }

    func testEmptyTextIsRejected() async throws {
        let engine = makeEngine(makeStore())
        do {
            try await engine.start(rawText: "   ")
            XCTFail("expected emptyText")
        } catch {
            XCTAssertEqual(error as? TimerEngineError, .emptyText)
        }
    }

    func testToggle() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        try await engine.toggle()
        XCTAssertNil(try store.runningEntry(), "toggle on an empty store does nothing")

        let first = try await engine.start(rawText: "Denali - a")
        advanceBoth(60, clock: clock, date: date)
        try await engine.toggle()
        XCTAssertNil(try store.runningEntry())
        XCTAssertEqual(try store.entry(id: first.id)?.stoppedAt, t0.addingTimeInterval(60))

        advanceBoth(60, clock: clock, date: date)
        try await engine.toggle()
        let restarted = try XCTUnwrap(store.runningEntry())
        XCTAssertNotEqual(restarted.id, first.id)
        XCTAssertEqual(restarted.rawText, "Denali - a")
        XCTAssertEqual(restarted.startedAt, t0.addingTimeInterval(120))
    }

    func testUndoLastStop() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        let nothing = try await engine.undoLastStop()
        XCTAssertNil(nothing)

        _ = try await engine.start(rawText: "Denali - a")
        advanceBoth(60, clock: clock, date: date)
        try await engine.stop()
        advanceBoth(5, clock: clock, date: date)
        let undone = try await engine.undoLastStop()
        XCTAssertEqual(undone?.rawText, "Denali - a")
        XCTAssertEqual(undone?.startedAt, t0.addingTimeInterval(65))
        XCTAssertEqual(try store.runningEntry()?.id, undone?.id)

        let twice = try await engine.undoLastStop()
        XCTAssertNil(twice, "single level, and nothing to undo while running")
    }

    func testStopBeforeStartClampsToZeroDuration() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        let entry = try await engine.start(rawText: "A")
        date.set(t0.addingTimeInterval(-3600))  // wall clock set backwards
        let stopped = try await engine.stop()
        XCTAssertEqual(stopped?.stoppedAt, entry.startedAt)
        XCTAssertEqual(stopped?.duration(asOf: t0), 0)
    }

    // MARK: Heartbeats, clock jumps, sleep

    func testHeartbeatWrittenAtStartAndEveryInterval() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        let entry = try await engine.start(rawText: "A")
        XCTAssertEqual(try store.readHeartbeat()?.entryID, entry.id)
        XCTAssertEqual(try store.readHeartbeat()?.at, t0)

        advanceBoth(30, clock: clock, date: date)
        try await waitUntil { try store.readHeartbeat()?.at == self.t0.addingTimeInterval(30) }
        advanceBoth(30, clock: clock, date: date)
        try await waitUntil { try store.readHeartbeat()?.at == self.t0.addingTimeInterval(60) }
        XCTAssertNil(try store.entry(id: entry.id)?.metadata.extra[TimerEngine.clockJumpKey])
    }

    func testClockJumpBetweenHeartbeatsIsRecorded() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        let entry = try await engine.start(rawText: "A")
        // 30 s pass on the monotonic clock, but the wall clock moves 30 s + 10 min.
        date.advance(by: 30 + 600)
        clock.advance(by: .seconds(30))
        try await waitUntil { try store.entry(id: entry.id)?.metadata.extra[TimerEngine.clockJumpKey] == "600" }
        // The live counter is monotonic: it ignores the jump.
        let elapsed = await engine.state.elapsed
        XCTAssertEqual(elapsed, .seconds(30))
        let running = await engine.state.running
        XCTAssertEqual(running?.metadata.extra[TimerEngine.clockJumpKey], "600")
    }

    func testLongSleepIsRecordedOnWake() async throws {
        let store = makeStore()
        let engine = makeEngine(store)
        let entry = try await engine.start(rawText: "A")
        await engine.noteWake(sleptFor: 60)
        XCTAssertNil(try store.entry(id: entry.id)?.metadata.extra[TimerEngine.longSleepKey])

        advanceBoth(3 * 3600, clock: clock, date: date)
        await engine.noteWake(sleptFor: 3 * 3600)
        XCTAssertEqual(try store.entry(id: entry.id)?.metadata.extra[TimerEngine.longSleepKey], "10800")
        XCTAssertNil(try store.entry(id: entry.id)?.stoppedAt, "sleep never stops the timer")
        XCTAssertEqual(try store.readHeartbeat()?.at, t0.addingTimeInterval(3 * 3600), "wake writes a heartbeat")
    }

    // MARK: Recovery

    func testCrashRecoveryStopsAtLastHeartbeatAndFlags() async throws {
        let url = try temporaryDatabaseURL(for: self)
        var entryID: UUID
        do {
            let store = try SQLiteEntryStore.open(at: url, now: date.closure)
            let engine = makeEngine(store)
            await engine.start()
            entryID = try await engine.start(rawText: "Denali - a").id
            advanceBoth(30, clock: clock, date: date)
            try await waitUntil { try store.readHeartbeat()?.at == self.t0.addingTimeInterval(30) }
            advanceBoth(20, clock: clock, date: date)  // dies 50 s in, between heartbeats
            // No prepareForCleanShutdown: simulated crash.
        }

        date.advance(by: 3600)  // relaunch an hour later
        let store = try SQLiteEntryStore.open(at: url, now: date.closure)
        let engine = makeEngine(store)
        await engine.start()

        let recovered = try XCTUnwrap(store.entry(id: entryID))
        XCTAssertEqual(recovered.stoppedAt, t0.addingTimeInterval(30))
        XCTAssertEqual(recovered.metadata.recovered?.lastHeartbeat, t0.addingTimeInterval(30))
        XCTAssertEqual(recovered.metadata.recovered?.noticedAt, t0.addingTimeInterval(3650))
        XCTAssertEqual(recovered.metadata.recovered?.reconciled, false)
        XCTAssertNil(try store.runningEntry())
        XCTAssertNil(try store.readHeartbeat())
        XCTAssertEqual(try store.readValue(forKey: EntryStoreKey.cleanShutdown), "0")
        let state = await engine.state
        XCTAssertNil(state.running)
        XCTAssertEqual(state.recovered?.id, entryID)

        try await engine.resumeRecovered()
        let resumed = try XCTUnwrap(store.runningEntry())
        XCTAssertNotEqual(resumed.id, entryID)
        XCTAssertEqual(resumed.rawText, "Denali - a")
        XCTAssertEqual(resumed.startedAt, t0.addingTimeInterval(3650))
        XCTAssertEqual(try store.entry(id: entryID)?.metadata.recovered?.reconciled, true)
        XCTAssertEqual(try store.entry(id: entryID)?.stoppedAt, t0.addingTimeInterval(30))
        let after = await engine.state
        XCTAssertNil(after.recovered)
    }

    func testCrashWithoutHeartbeatGivesZeroCredit() async throws {
        let store = makeStore()
        let entry = Entry.fixture("A", start: t0, minutes: nil)
        try store.insert(entry)
        try store.writeHeartbeat(entryID: UUID(), at: t0.addingTimeInterval(500))  // someone else's
        date.advance(by: 7200)

        let engine = makeEngine(store)
        await engine.start()
        let recovered = try XCTUnwrap(store.entry(id: entry.id))
        XCTAssertEqual(recovered.stoppedAt, t0)
        XCTAssertEqual(recovered.duration(asOf: date.now), 0)
        XCTAssertEqual(recovered.metadata.recovered?.lastHeartbeat, t0)
        let state = await engine.state
        XCTAssertEqual(state.recovered?.id, entry.id)
    }

    func testAcceptRecoveredAndPendingNoticeSurvivesRelaunch() async throws {
        let store = makeStore()
        let entry = Entry.fixture("A", start: t0, minutes: nil)
        try store.insert(entry)
        try store.writeHeartbeat(entryID: entry.id, at: t0.addingTimeInterval(90))
        date.advance(by: 600)
        await makeEngine(store).start()

        // Not reconciled yet: the next launch shows the notice again.
        let second = makeEngine(store)
        await second.start()
        let pending = await second.state.recovered
        XCTAssertEqual(pending?.id, entry.id)

        try await second.acceptRecovered()
        let stored = try XCTUnwrap(store.entry(id: entry.id))
        XCTAssertEqual(stored.metadata.recovered?.reconciled, true)
        XCTAssertEqual(stored.stoppedAt, t0.addingTimeInterval(90))
        let cleared = await second.state.recovered
        XCTAssertNil(cleared)
        XCTAssertNil(try store.runningEntry())
    }

    func testCleanShutdownKeepsEntryRunning() async throws {
        let store = makeStore()
        let first = makeEngine(store)
        await first.start()
        let entry = try await first.start(rawText: "Denali - a")
        advanceBoth(60, clock: clock, date: date)
        await first.prepareForCleanShutdown()
        XCTAssertEqual(try store.readValue(forKey: EntryStoreKey.cleanShutdown), "1")
        XCTAssertNil(try store.readHeartbeat())
        XCTAssertNil(try store.entry(id: entry.id)?.stoppedAt)

        date.advance(by: 540)  // relaunch 9 minutes later
        let second = makeEngine(store)
        await second.start()
        XCTAssertEqual(try store.runningEntry()?.id, entry.id)
        XCTAssertNil(try store.entry(id: entry.id)?.metadata.recovered)
        XCTAssertEqual(try store.readValue(forKey: EntryStoreKey.cleanShutdown), "0")
        XCTAssertEqual(try store.readHeartbeat()?.entryID, entry.id)
        let state = await second.state
        XCTAssertEqual(state.running?.id, entry.id)
        XCTAssertEqual(state.elapsed, .seconds(600), "anchored at the entry's wall-clock age")
        XCTAssertNil(state.recovered)
    }

    func testLaunchWithNothingRunningClearsStaleHeartbeat() async throws {
        let store = makeStore()
        try store.writeHeartbeat(entryID: UUID(), at: t0)
        await makeEngine(store).start()
        XCTAssertNil(try store.readHeartbeat())
        XCTAssertEqual(try store.readValue(forKey: EntryStoreKey.cleanShutdown), "0")
    }

    // MARK: states()

    func testStatesEmitsImmediatelyOnChangeAndEverySecond() async throws {
        let engine = makeEngine(makeStore())
        let stream = await engine.states()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        XCTAssertEqual(initial, .idle)

        let entry = try await engine.start(rawText: "A")
        let started = await iterator.next()
        XCTAssertEqual(started?.running?.id, entry.id)
        XCTAssertEqual(started?.elapsed, .zero)

        for second in 1...3 {
            advanceBoth(1, clock: clock, date: date)
            let tick = await iterator.next()
            XCTAssertEqual(tick?.elapsed, .seconds(second))
            XCTAssertEqual(tick?.running?.id, entry.id)
        }

        try await engine.stop()
        let stopped = await iterator.next()
        XCTAssertEqual(stopped, .idle)
    }
}
