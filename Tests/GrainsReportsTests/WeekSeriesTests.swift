import XCTest
import GrainsCore
@testable import GrainsReports

final class WeekSeriesTests: XCTestCase {
    typealias F = Fixtures
    let spec = Fixtures.spec
    /// 2026-W44, the 169 h fall-back week (Mon Oct 26 – Mon Nov 2).
    var week: Week { spec.week(containing: F.date(2026, 10, 28)) }
    typealias P = WeekSeries.Point

    func testSingleEntry() {
        let now = F.date(2026, 10, 28, 12)
        let e = F.entry(1, F.date(2026, 10, 27, 9), F.date(2026, 10, 27, 11))
        let s = WeekSeries.compute(entries: [e], week: week, now: now, targetHours: nil)
        XCTAssertEqual(s.tracked, [
            P(time: F.date(2026, 10, 26), hours: 0),
            P(time: F.date(2026, 10, 27, 9), hours: 0),
            P(time: F.date(2026, 10, 27, 11), hours: 2),
            P(time: now, hours: 2),
        ])
        XCTAssertEqual(s.totalHours, 2)
        XCTAssertEqual(s.hoursCeiling, 10)
        XCTAssertEqual(s.elapsedFraction, 60.0 / 169.0, accuracy: 1e-12)
        XCTAssertEqual(s.dailyHours, [0, 2, 0, 0, 0, 0, 0])
    }

    func testMidnightCrossingSplitsAcrossDaysExactly() {
        let e = F.entry(1, F.date(2026, 10, 27, 22, 30), F.date(2026, 10, 28, 1, 15))
        let s = WeekSeries.compute(entries: [e], week: week, now: F.date(2026, 10, 29), targetHours: nil)
        XCTAssertEqual(s.dailyHours[1], 1.5)
        XCTAssertEqual(s.dailyHours[2], 1.25)
        XCTAssertEqual(s.dailyHours.reduce(0, +), 2.75)
        XCTAssertEqual(s.totalHours, 2.75)
        XCTAssertEqual(s.totalHours * 3600, e.duration(asOf: F.date(2026, 10, 29)))
    }

    func testWeekCrossingEntrySplitsAcrossTwoWeeks() {
        let e = F.entry(1, F.date(2026, 11, 1, 23), F.date(2026, 11, 2, 2))
        let now = F.date(2026, 11, 3)
        let w44 = WeekSeries.compute(entries: [e], week: week, now: now, targetHours: nil)
        let w45 = WeekSeries.compute(entries: [e], week: week.next(spec: spec), now: now, targetHours: nil)
        XCTAssertEqual(w44.totalHours, 1)
        XCTAssertEqual(w45.totalHours, 2)
        XCTAssertEqual(w44.totalHours + w45.totalHours, e.duration(asOf: now) / 3600)
        XCTAssertEqual(w44.tracked.last, P(time: week.interval.end, hours: 1))
        XCTAssertEqual(w44.elapsedFraction, 1)
        XCTAssertEqual(w45.dailyHours, [2, 0, 0, 0, 0, 0, 0])
    }

    func testRunningEntryEndsAtNow() {
        let now = F.date(2026, 10, 28, 10, 30)
        let e = F.entry(1, F.date(2026, 10, 28, 8), nil)
        let s = WeekSeries.compute(entries: [e], week: week, now: now, targetHours: nil)
        XCTAssertEqual(s.tracked.last, P(time: now, hours: 2.5))
        XCTAssertEqual(s.tracked.count, 3)
    }

    func testOverlappingEntriesCountedOnce() {
        let a = F.entry(1, F.date(2026, 10, 27, 9), F.date(2026, 10, 27, 11))
        let b = F.entry(2, F.date(2026, 10, 27, 10), F.date(2026, 10, 27, 12))
        let c = F.entry(3, F.date(2026, 10, 27, 9, 30), F.date(2026, 10, 27, 10))
        let s = WeekSeries.compute(entries: [c, b, a], week: week, now: F.date(2026, 10, 30), targetHours: nil)
        XCTAssertEqual(s.totalHours, 3)
        XCTAssertEqual(s.tracked.count, 4)
        XCTAssertEqual(s.dailyHours[1], 3)
    }

    func testDeletedEntriesExcluded() {
        let a = F.entry(1, F.date(2026, 10, 27, 9), F.date(2026, 10, 27, 11), deleted: true)
        let s = WeekSeries.compute(entries: [a], week: week, now: F.date(2026, 10, 30), targetHours: nil)
        XCTAssertEqual(s.totalHours, 0)
    }

    func testEmptyCurrentFutureAndPastWeeks() {
        let now = F.date(2026, 10, 28)
        let current = WeekSeries.compute(entries: [], week: week, now: now, targetHours: nil)
        XCTAssertEqual(current.tracked, [P(time: week.interval.start, hours: 0), P(time: now, hours: 0)])
        XCTAssertEqual(current.hoursCeiling, 10)
        XCTAssertEqual(current.dailyHours, Array(repeating: 0, count: 7))

        let future = WeekSeries.compute(entries: [], week: week.next(spec: spec), now: now, targetHours: nil)
        XCTAssertEqual(future.tracked, [P(time: week.interval.end, hours: 0)])
        XCTAssertEqual(future.elapsedFraction, 0)

        let past = WeekSeries.compute(entries: [], week: week.previous(spec: spec), now: now, targetHours: nil)
        XCTAssertEqual(past.tracked.last?.time, week.interval.start)
        XCTAssertEqual(past.elapsedFraction, 1)
    }

    func testEntryStartingAtWeekStartHasNoDuplicatePoint() {
        let e = F.entry(1, F.date(2026, 10, 26), F.date(2026, 10, 26, 1))
        let s = WeekSeries.compute(entries: [e], week: week, now: F.date(2026, 10, 26, 1), targetHours: nil)
        XCTAssertEqual(s.tracked, [P(time: F.date(2026, 10, 26), hours: 0), P(time: F.date(2026, 10, 26, 1), hours: 1)])
    }

    func testElapsedFractionUsesDSTLength() {
        let spring = spec.week(containing: F.date(2026, 3, 4))
        // Sun Mar 8 00:00 is 144 real hours into a 167 h week.
        let s = WeekSeries.compute(entries: [], week: spring, now: F.date(2026, 3, 8), targetHours: nil)
        XCTAssertEqual(s.elapsedFraction, 144.0 / 167.0, accuracy: 1e-12)
    }

    func testHoursCeilingRule() {
        XCTAssertEqual(WeekSeries.hoursCeiling(trackedHours: 0, targetHours: nil), 10)
        XCTAssertEqual(WeekSeries.hoursCeiling(trackedHours: 10, targetHours: nil), 10)
        XCTAssertEqual(WeekSeries.hoursCeiling(trackedHours: 10.01, targetHours: nil), 15)
        XCTAssertEqual(WeekSeries.hoursCeiling(trackedHours: 23.7, targetHours: 40), 40)
        XCTAssertEqual(WeekSeries.hoursCeiling(trackedHours: 41, targetHours: 40), 45)
        XCTAssertEqual(WeekSeries.hoursCeiling(trackedHours: 12, targetHours: 7), 15)
        XCTAssertEqual(WeekSeries.hoursCeiling(trackedHours: 3, targetHours: 12.5), 15)
    }

    func testTargetLine() {
        let s = WeekSeries.compute(entries: [], week: week, now: F.date(2026, 10, 28), targetHours: 40)
        XCTAssertEqual(s.targetHours, 40)
        XCTAssertEqual(s.hoursCeiling, 40)
        XCTAssertEqual(s.targetLine, [P(time: week.interval.start, hours: 0), P(time: week.interval.end, hours: 40)])
        XCTAssertNil(WeekSeries.compute(entries: [], week: week, now: F.date(2026, 10, 28), targetHours: nil).targetLine)
    }

    func testBackdatedEditChangesOnlyThatWeek() {
        let now = F.date(2026, 10, 28)
        let current = [F.entry(1, F.date(2026, 10, 27, 9), F.date(2026, 10, 27, 10))]
        let edited = current + [F.entry(2, F.date(2026, 10, 21, 9), F.date(2026, 10, 21, 13))]
        let prior = week.previous(spec: spec)
        XCTAssertEqual(WeekSeries.compute(entries: current, week: week, now: now, targetHours: nil),
                       WeekSeries.compute(entries: edited, week: week, now: now, targetHours: nil))
        XCTAssertEqual(WeekSeries.compute(entries: current, week: prior, now: now, targetHours: nil).totalHours, 0)
        XCTAssertEqual(WeekSeries.compute(entries: edited, week: prior, now: now, targetHours: nil).totalHours, 4)
    }

    func testDeterministicRegardlessOfInputOrder() {
        let es = (0..<10).map { i in
            F.entry(i, F.date(2026, 10, 26, 8 + i), F.date(2026, 10, 26, 8 + i, 45))
        }
        let now = F.date(2026, 10, 29)
        XCTAssertEqual(WeekSeries.compute(entries: es, week: week, now: now, targetHours: 40),
                       WeekSeries.compute(entries: es.reversed(), week: week, now: now, targetHours: 40))
    }
}
