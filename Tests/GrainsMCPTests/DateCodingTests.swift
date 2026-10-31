import Foundation
import GrainsReports
import XCTest
@testable import GrainsMCP

final class DateCodingTests: XCTestCase {
    let coding = DateCoding(timeZone: Fixture.timeZone)

    func testDateOnlyIsLocalDay() {
        XCTAssertEqual(coding.parse("2026-10-26", as: .start), Fixture.date(2026, 10, 26))
        XCTAssertEqual(coding.parse("2026-10-26", as: .end), Fixture.date(2026, 10, 27))
        // The DST-ending day is 25 h long; "to" still means the next local midnight.
        XCTAssertEqual(coding.parse("2026-11-01", as: .end), Fixture.date(2026, 11, 2))
        XCTAssertEqual(Fixture.date(2026, 11, 2).timeIntervalSince(Fixture.date(2026, 11, 1)), 25 * Fixture.hour)
    }

    func testRFC3339Variants() {
        let nine = Fixture.date(2026, 10, 26, 9)
        XCTAssertEqual(coding.parse("2026-10-26T09:00:00-08:00", as: .start), nine)
        XCTAssertEqual(coding.parse("2026-10-26T17:00:00Z", as: .start), nine)
        XCTAssertEqual(coding.parse("2026-10-26t17:00:00z", as: .end), nine)
        XCTAssertEqual(coding.parse("2026-10-26 22:30:00+05:30", as: .start), nine)
        XCTAssertEqual(coding.parse("2026-10-26T09:00:00.250-08:00", as: .start), nine.addingTimeInterval(0.25))
        XCTAssertEqual(coding.parse("  2026-10-26T17:00:00Z ", as: .start), nine)
    }

    func testInvalidDates() {
        for text in ["", "yesterday", "2026-02-30", "2026-13-01", "2026-10-26T25:00:00Z", "2026-10-26T09:00:00",
                     "2026-10-26T09:00:00+0800", "2026-10-26T09:00Z", "26-10-2026", "2026-10-26T09:00:00.-08:00",
                     "2026-10-26T09:00:00-08:00x"] {
            XCTAssertNil(coding.parse(text, as: .start), text)
        }
    }

    func testFormatting() {
        XCTAssertEqual(coding.rfc3339(Fixture.date(2026, 10, 26, 9, 5, 7).addingTimeInterval(0.9)), "2026-10-26T09:05:07-08:00")
        XCTAssertEqual(coding.rfc3339(Fixture.date(2026, 11, 2)), "2026-11-02T00:00:00-09:00")
        XCTAssertEqual(DateCoding(timeZone: TimeZone(identifier: "UTC")!).rfc3339(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00+00:00")
        XCTAssertEqual(coding.dateString(Fixture.date(2026, 1, 2, 23, 59)), "2026-01-02")
    }

    func testISOWeekResolution() throws {
        let w44 = try XCTUnwrap(coding.week(isoIdentifier: "2026-W44", spec: Fixture.spec))
        XCTAssertEqual(w44.interval.start, Fixture.date(2026, 10, 26))
        XCTAssertEqual(w44.interval.end, Fixture.date(2026, 11, 2))
        XCTAssertEqual(w44.isoIdentifier, "2026-W44")
        XCTAssertEqual(coding.week(isoIdentifier: "2026-w44", spec: Fixture.spec), w44)

        // Week 1 of 2026 starts in 2025.
        XCTAssertEqual(coding.week(isoIdentifier: "2026-W01", spec: Fixture.spec)?.interval.start, Fixture.date(2025, 12, 29))
        // 2026 has 53 ISO weeks, 2025 has 52.
        XCTAssertEqual(coding.week(isoIdentifier: "2026-W53", spec: Fixture.spec)?.interval.start, Fixture.date(2026, 12, 28))
        XCTAssertNil(coding.week(isoIdentifier: "2025-W53", spec: Fixture.spec))
        for bad in ["2026-W00", "2026-W54", "2026-44", "2026W44", "W44", ""] {
            XCTAssertNil(coding.week(isoIdentifier: bad, spec: Fixture.spec), bad)
        }

        // Sunday-start weeks: the week whose id (its start day's ISO week) is W44 starts Sun Nov 1,
        // which is the week the app's Grains-2026-W44.csv covers.
        let sunday = WeekSpec(startsOn: 1, calendar: Fixture.calendar)
        let sundayW44 = try XCTUnwrap(coding.week(isoIdentifier: "2026-W44", spec: sunday))
        XCTAssertEqual(sundayW44.interval.start, Fixture.date(2026, 11, 1))
        XCTAssertEqual(sundayW44.isoIdentifier, "2026-W44")
    }
}
