import XCTest
import GrainsCore
@testable import GrainsReports

final class StatsTests: XCTestCase {
    typealias F = Fixtures
    let spec = Fixtures.spec

    func testStats() {
        let now = F.date(2026, 10, 28, 15)
        let week = spec.week(containing: now)
        let entries = [
            F.entry(1, F.date(2026, 10, 26, 9), F.date(2026, 10, 26, 11), client: "Acme"),
            F.entry(2, F.date(2026, 10, 28, 8), F.date(2026, 10, 28, 9), client: "Acme"),
            F.entry(3, F.date(2026, 10, 28, 10), F.date(2026, 10, 28, 11, 30), client: "Globex"),
            F.entry(4, F.date(2026, 10, 28, 12), F.date(2026, 10, 28, 12, 30), client: nil),
            F.entry(5, F.date(2026, 10, 28, 14, 30), nil, client: "Globex"),
            F.entry(6, F.date(2026, 10, 28, 6), F.date(2026, 10, 28, 7), client: "Initech", deleted: true),
            F.entry(7, F.date(2026, 10, 20, 9), F.date(2026, 10, 20, 17), client: "Initech"), // prior week
        ]
        let stats = Stats.compute(entries: entries, week: week, today: spec.today(at: now), now: now)
        XCTAssertEqual(stats.weekHours, 5.5)
        XCTAssertEqual(stats.todayHours, 3.5)
        XCTAssertEqual(stats.sessionSeconds, 1800)
        XCTAssertEqual(stats.byClient, [
            ClientHours(clientText: "Acme", hours: 3),
            ClientHours(clientText: "Globex", hours: 2),
            ClientHours(clientText: nil, hours: 0.5),
        ])
        let series = WeekSeries.compute(entries: entries, week: week, now: now, targetHours: nil)
        XCTAssertEqual(stats.weekHours, series.totalHours)
    }

    func testTiesSortByLabelNilLastAndNoSession() {
        let now = F.date(2026, 10, 30)
        let week = spec.week(containing: now)
        let entries = [
            F.entry(1, F.date(2026, 10, 27, 9), F.date(2026, 10, 27, 10), client: nil),
            F.entry(2, F.date(2026, 10, 27, 11), F.date(2026, 10, 27, 12), client: "Zeta"),
            F.entry(3, F.date(2026, 10, 27, 13), F.date(2026, 10, 27, 14), client: "Alpha"),
        ]
        let stats = Stats.compute(entries: entries.reversed(), week: week, today: spec.today(at: now), now: now)
        XCTAssertNil(stats.sessionSeconds)
        XCTAssertEqual(stats.todayHours, 0)
        XCTAssertEqual(stats.byClient.map(\.clientText), ["Alpha", "Zeta", nil])
    }

    func testTodayClipsMidnightCrossingSession() {
        let now = F.date(2026, 10, 28, 1)
        let week = spec.week(containing: now)
        let running = F.entry(1, F.date(2026, 10, 27, 23), nil)
        let stats = Stats.compute(entries: [running], week: week, today: spec.today(at: now), now: now)
        XCTAssertEqual(stats.todayHours, 1)
        XCTAssertEqual(stats.weekHours, 2)
        XCTAssertEqual(stats.sessionSeconds, 7200)
    }
}
