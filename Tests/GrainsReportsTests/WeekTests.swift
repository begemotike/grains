import XCTest
@testable import GrainsReports

final class WeekTests: XCTestCase {
    let spec = Fixtures.spec
    typealias F = Fixtures

    func testEveryWeekdayMapsToMondayStart() {
        let monday = F.date(2026, 10, 26)
        for offset in 0..<7 {
            let day = F.date(2026, 10, 26 + offset, 12)
            let week = spec.week(containing: day)
            XCTAssertEqual(week.interval.start, monday, "day offset \(offset)")
            XCTAssertEqual(week.interval.end, F.date(2026, 11, 2))
        }
    }

    func testBoundaryInstants() {
        XCTAssertEqual(spec.week(containing: F.date(2026, 10, 26)).interval.start, F.date(2026, 10, 26))
        XCTAssertEqual(spec.week(containing: F.date(2026, 11, 1, 23, 59, 59)).interval.start, F.date(2026, 10, 26))
        XCTAssertEqual(spec.week(containing: F.date(2026, 11, 2)).interval.start, F.date(2026, 11, 2))
    }

    func testSundayStartSetting() {
        let sunday = WeekSpec(startsOn: 1, calendar: F.calendar)
        XCTAssertEqual(sunday.week(containing: F.date(2026, 10, 28, 9)).interval.start, F.date(2026, 10, 25))
        XCTAssertEqual(sunday.week(containing: F.date(2026, 10, 25)).interval.start, F.date(2026, 10, 25))
        XCTAssertEqual(sunday.week(containing: F.date(2026, 10, 31, 23)).interval.start, F.date(2026, 10, 25))
        XCTAssertEqual(sunday.week(containing: F.date(2026, 11, 1)).interval.start, F.date(2026, 11, 1))
        // Identifier is the ISO week of the start day (a Sunday belongs to the prior ISO week).
        XCTAssertEqual(sunday.week(containing: F.date(2026, 10, 28)).isoIdentifier, "2026-W43")
    }

    func testISOIdentifiersAcrossYearBoundary() {
        let w1 = spec.week(containing: F.date(2025, 12, 31, 10))
        XCTAssertEqual(w1.interval.start, F.date(2025, 12, 29))
        XCTAssertEqual(w1.isoIdentifier, "2026-W01")

        let w53 = spec.week(containing: F.date(2027, 1, 1, 10))
        XCTAssertEqual(w53.interval.start, F.date(2026, 12, 28))
        XCTAssertEqual(w53.isoIdentifier, "2026-W53")
        XCTAssertEqual(w53.next(spec: spec).isoIdentifier, "2027-W01")

        XCTAssertEqual(spec.week(containing: F.date(2026, 10, 30)).isoIdentifier, "2026-W44")
    }

    func testSpringForwardWeekIs167Hours() {
        let week = spec.week(containing: F.date(2026, 3, 8, 12))
        XCTAssertEqual(week.interval.start, F.date(2026, 3, 2))
        XCTAssertEqual(week.interval.duration, 167 * F.hour)
        XCTAssertEqual(week.days.map { $0.duration / F.hour }, [24, 24, 24, 24, 24, 24, 23])
    }

    func testFallBackWeekIs169Hours() {
        let week = spec.week(containing: F.date(2026, 11, 1, 12))
        XCTAssertEqual(week.interval.start, F.date(2026, 10, 26))
        XCTAssertEqual(week.interval.duration, 169 * F.hour)
        XCTAssertEqual(week.days.map { $0.duration / F.hour }, [24, 24, 24, 24, 24, 24, 25])
    }

    func testOrdinaryWeekIs168HoursWithContiguousDays() {
        let week = spec.week(containing: F.date(2026, 6, 10))
        XCTAssertEqual(week.interval.duration, 168 * F.hour)
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.days.first?.start, week.interval.start)
        XCTAssertEqual(week.days.last?.end, week.interval.end)
        for i in 1..<7 { XCTAssertEqual(week.days[i - 1].end, week.days[i].start) }
        for (i, day) in week.days.enumerated() {
            XCTAssertEqual(day.start, F.date(2026, 6, 8 + i))
        }
    }

    func testTodayLengths() {
        XCTAssertEqual(spec.today(at: F.date(2026, 3, 8, 15)).duration, 23 * F.hour)
        XCTAssertEqual(spec.today(at: F.date(2026, 6, 1, 15)).duration, 24 * F.hour)
        XCTAssertEqual(spec.today(at: F.date(2026, 11, 1, 15)).duration, 25 * F.hour)
        XCTAssertEqual(spec.today(at: F.date(2026, 11, 1, 15)).start, F.date(2026, 11, 1))
    }

    func testPreviousNextAndComparable() {
        let week = spec.week(containing: F.date(2026, 10, 30))
        let prev = week.previous(spec: spec)
        let next = week.next(spec: spec)
        XCTAssertEqual(prev.isoIdentifier, "2026-W43")
        XCTAssertEqual(next.isoIdentifier, "2026-W45")
        XCTAssertEqual(prev.interval.end, week.interval.start)
        XCTAssertEqual(next.interval.start, week.interval.end)
        XCTAssertEqual(next.previous(spec: spec), week)
        XCTAssertLessThan(prev, week)
        XCTAssertLessThan(week, next)
        XCTAssertEqual([next, prev, week].sorted(), [prev, week, next])
    }
}
