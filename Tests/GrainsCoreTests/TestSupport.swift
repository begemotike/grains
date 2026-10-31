import Foundation
import XCTest
@testable import GrainsCore

/// A manually advanced `Clock` for deterministic engine tests.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [UUID: Sleeper] = [:]

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    /// Number of tasks currently suspended in `sleep(until:)`.
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if deadline <= current {
                    lock.unlock()
                    continuation.resume()
                } else if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    lock.unlock()
                }
            }
        } onCancel: {
            let sleeper = lock.withLock { sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            current = current.advanced(by: duration)
            let ready = sleepers.filter { $0.value.deadline <= current }
            for key in ready.keys { sleepers[key] = nil }
            return Array(ready.values)
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

/// A settable wall clock.
final class TestDate: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date = TestDate.reference) { self.value = value }

    /// 2026-09-21 (a Monday) 09:00 UTC, an arbitrary fixed start for tests.
    static let reference = Date(timeIntervalSince1970: 1_790_067_600)

    var now: Date { lock.withLock { value } }
    var closure: @Sendable () -> Date { { [self] in self.now } }

    func advance(by seconds: TimeInterval) { lock.withLock { value += seconds } }
    func set(_ date: Date) { lock.withLock { value = date } }
}

/// Moves wall and monotonic time forward together, as on a normally running Mac.
func advanceBoth(_ seconds: Int, clock: TestClock, date: TestDate) {
    date.advance(by: TimeInterval(seconds))
    clock.advance(by: .seconds(seconds))
}

/// A unique temporary database URL; the directory is removed in the test's teardown.
func temporaryDatabaseURL(for testCase: XCTestCase) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "GrainsCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    testCase.addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return directory.appending(path: "grains.sqlite")
}

/// Polls `condition` until true or `timeout` elapses (background tasks hop actors).
func waitUntil(
    timeout: TimeInterval = 2,
    file: StaticString = #filePath, line: UInt = #line,
    _ condition: () async throws -> Bool
) async rethrows {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if try await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    XCTFail("condition not met within \(timeout)s", file: file, line: line)
}

extension Entry {
    /// A stopped entry for fixtures.
    static func fixture(
        _ raw: String, start: Date, minutes: Double?, id: UUID = UUID()
    ) -> Entry {
        let parsed = EntryParser.parse(raw)
        return Entry(
            id: id, rawText: raw, clientText: parsed.clientText, note: parsed.note,
            startedAt: start, stoppedAt: minutes.map { start.addingTimeInterval($0 * 60) }
        )
    }
}
