import GrainsCore
import GrainsReports
import XCTest
@testable import Grains

final class ExportWeekMappingTests: XCTestCase {
    var spec: WeekSpec {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Anchorage") ?? .gmt
        return WeekSpec(startsOn: 2, calendar: calendar)
    }

    /// Local time in Anchorage.
    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        spec.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .distantPast
    }

    func testEntryInsideOneWeek() {
        let entry = Entry(rawText: "a", startedAt: date(2026, 10, 27, 9), stoppedAt: date(2026, 10, 27, 10))
        XCTAssertEqual(ExportWeekMapping.weeks(for: entry, spec: spec, now: date(2026, 10, 30, 9)).map(\.isoIdentifier), ["2026-W44"])
    }

    func testEntryCrossingWeekBoundaryMapsToBoth() {
        let entry = Entry(rawText: "a", startedAt: date(2026, 11, 1, 22), stoppedAt: date(2026, 11, 2, 1))
        XCTAssertEqual(ExportWeekMapping.weeks(for: entry, spec: spec, now: date(2026, 11, 3, 9)).map(\.isoIdentifier), ["2026-W44", "2026-W45"])
    }

    func testStopExactlyAtBoundaryStaysInEarlierWeek() {
        let entry = Entry(rawText: "a", startedAt: date(2026, 11, 1, 22), stoppedAt: date(2026, 11, 2, 0))
        XCTAssertEqual(ExportWeekMapping.weeks(for: entry, spec: spec, now: date(2026, 11, 3, 9)).map(\.isoIdentifier), ["2026-W44"])
    }

    func testRunningEntryUsesNow() {
        let entry = Entry(rawText: "a", startedAt: date(2026, 11, 1, 22))
        XCTAssertEqual(ExportWeekMapping.weeks(for: entry, spec: spec, now: date(2026, 11, 2, 3)).map(\.isoIdentifier), ["2026-W44", "2026-W45"])
    }

    func testEditMovingEntryRewritesOldAndNewWeeks() {
        let old = spec.week(containing: date(2026, 10, 20, 9))
        let moved = Entry(rawText: "a", startedAt: date(2026, 10, 27, 9), stoppedAt: date(2026, 10, 27, 10))
        let weeks = ExportWeekMapping.weeksToRewrite(changed: [moved], previouslyKnown: [old], spec: spec, now: date(2026, 10, 30, 9))
        XCTAssertEqual(weeks.map(\.isoIdentifier), ["2026-W43", "2026-W44"])
    }

    func testDeletedEntryRewritesItsKnownWeek() {
        let old = spec.week(containing: date(2026, 10, 20, 9))
        XCTAssertEqual(ExportWeekMapping.weeksToRewrite(changed: [], previouslyKnown: [old, old], spec: spec, now: Date()).map(\.isoIdentifier), ["2026-W43"])
    }

    func testAllWeeks() {
        let weeks = ExportWeekMapping.allWeeks(from: date(2026, 10, 14, 9), through: date(2026, 10, 30, 9), spec: spec)
        XCTAssertEqual(weeks.map(\.isoIdentifier), ["2026-W42", "2026-W43", "2026-W44"])
    }
}

final class ChartGeometryTests: XCTestCase {
    func testMappingAndSummary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let spec = WeekSpec(startsOn: 2, calendar: calendar)
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26)) ?? .distantPast
        let week = spec.week(containing: monday)
        let now = monday.addingTimeInterval(84 * 3600) // half the week
        let entry = Entry(rawText: "a", startedAt: monday.addingTimeInterval(3600), stoppedAt: monday.addingTimeInterval(6 * 3600))
        let series = WeekSeries.compute(entries: [entry], week: week, now: now, targetHours: 40)
        let g = ChartGeometry(series: series, size: CGSize(width: 700, height: 72), inset: 0)
        XCTAssertEqual(g.x(week.interval.start), 0)
        XCTAssertEqual(g.x(now), 350, accuracy: 0.01)
        XCTAssertEqual(g.y(0), 72)
        XCTAssertEqual(g.y(series.hoursCeiling), 0)
        XCTAssertEqual(g.gridYs, [72, 36, 0])
        XCTAssertEqual(g.futureStartX ?? -1, 350, accuracy: 0.01)
        XCTAssertEqual(g.trackedPoints.last?.x ?? -1, 350, accuracy: 0.01)
        XCTAssertEqual(g.dayCenters.count, 7)
        XCTAssertEqual(g.dayCenters[0], 50, accuracy: 0.01)
        XCTAssertEqual(g.targetPoints?.last?.y ?? -1, 0, accuracy: 0.01) // ceiling == target (40)
        XCTAssertEqual(g.accessibilitySummary, "5.0 hours tracked, 50 percent of the week elapsed")
    }
}

final class CaretAndFormattingTests: XCTestCase {
    func testCaretSolidWhileTypingThenBlinks() {
        let edit = Date(timeIntervalSinceReferenceDate: 1000)
        XCTAssertEqual(CaretBlink.opacity(mode: .typing, lastEdit: edit, now: edit.addingTimeInterval(0.3), smooth: false), 1)
        XCTAssertEqual(CaretBlink.opacity(mode: .typing, lastEdit: edit, now: edit.addingTimeInterval(0.5 + 0.75), smooth: false), 0)
        XCTAssertEqual(CaretBlink.opacity(mode: .typing, lastEdit: edit, now: edit.addingTimeInterval(0.5 + 1.25), smooth: false), 1)
    }

    func testControlBlinksAt1Hz() {
        let t = Date(timeIntervalSinceReferenceDate: 2000)
        XCTAssertEqual(CaretBlink.opacity(mode: .control, lastEdit: .distantPast, now: t.addingTimeInterval(0.25), smooth: false), 1)
        XCTAssertEqual(CaretBlink.opacity(mode: .control, lastEdit: .distantPast, now: t.addingTimeInterval(0.75), smooth: false), 0)
    }

    func testFormatting() {
        XCTAssertEqual(Formatting.clock(seconds: 6209), "01:43:29")
        XCTAssertEqual(Formatting.clock(seconds: 97390), "27:03:10")
        XCTAssertEqual(Formatting.clock(.seconds(59)), "00:00:59")
        XCTAssertEqual(Formatting.shortClock(.seconds(6209)), "01:43")
        XCTAssertEqual(Formatting.hours(23.74), "23.7")
        XCTAssertEqual(Formatting.hours(0), "0.0")
    }

    func testEntryLineStyling() {
        let layout = EntryLineLayout(text: "Denali - iPad", availableWidth: 584)
        XCTAssertEqual(layout.styling.client, NSRange(location: 0, length: 6))
        XCTAssertEqual(layout.styling.separator, NSRange(location: 6, length: 3))
        XCTAssertEqual(layout.styling.note, NSRange(location: 9, length: 4))
        XCTAssertEqual(layout.fontSize, 28)
        let plain = EntryLineLayout(text: "Administrative work", availableWidth: 584)
        XCTAssertNil(plain.styling.client)
    }

    func testEntryLineShrinksLongTextDownToMinimum() {
        let long = EntryLineLayout(text: "Global Credit Union - Jamf certificate troubleshooting", availableWidth: 584)
        XCTAssertLessThan(long.fontSize, 28)
        XCTAssertGreaterThanOrEqual(long.fontSize, 18)
        let huge = EntryLineLayout(text: String(repeating: "x", count: 200), availableWidth: 584)
        XCTAssertEqual(huge.fontSize, 18)
        XCTAssertGreaterThan(huge.scrollOffset(caret: 200), 0)
        XCTAssertEqual(huge.scrollOffset(caret: 0), 0)
    }
}
