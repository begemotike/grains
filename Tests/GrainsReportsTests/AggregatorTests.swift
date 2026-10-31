import XCTest
import GrainsCore
@testable import GrainsReports

final class AggregatorTests: XCTestCase {
    typealias F = Fixtures
    let spec = Fixtures.spec
    let now = F.date(2026, 10, 27, 12)

    var entries: [Entry] {
        [
            F.entry(1, F.date(2026, 10, 20, 9), F.date(2026, 10, 20, 11), client: "Acme"),
            F.entry(2, F.date(2026, 10, 25, 23), F.date(2026, 10, 26, 1), client: "Acme"), // crosses week + midnight
            F.entry(3, F.date(2026, 10, 26, 9), F.date(2026, 10, 26, 10), client: "Globex"),
            F.entry(4, F.date(2026, 10, 26, 13), F.date(2026, 10, 26, 13, 30)),
            F.entry(5, F.date(2026, 10, 27, 11), nil, client: "Globex"), // running, 1 h at now
            F.entry(6, F.date(2026, 10, 26, 15), F.date(2026, 10, 26, 18), client: "Acme", deleted: true),
        ]
    }

    var range: DateInterval { DateInterval(start: F.date(2026, 10, 19), end: F.date(2026, 11, 2)) }

    func rows(_ g: GroupBy, _ r: DateInterval? = nil) -> [AggregateRow] {
        Aggregator.aggregate(entries: entries, range: r ?? range, groupBy: g, spec: spec, now: now)
    }

    func testByDay() {
        XCTAssertEqual(rows(.day), [
            AggregateRow(key: "2026-10-20", clientText: nil, seconds: 7200, hours: 2, entryCount: 1),
            AggregateRow(key: "2026-10-25", clientText: nil, seconds: 3600, hours: 1, entryCount: 1),
            AggregateRow(key: "2026-10-26", clientText: nil, seconds: 9000, hours: 2.5, entryCount: 3),
            AggregateRow(key: "2026-10-27", clientText: nil, seconds: 3600, hours: 1, entryCount: 1),
        ])
    }

    func testByWeek() {
        XCTAssertEqual(rows(.week), [
            AggregateRow(key: "2026-W43", clientText: nil, seconds: 10800, hours: 3, entryCount: 2),
            AggregateRow(key: "2026-W44", clientText: nil, seconds: 12600, hours: 3.5, entryCount: 4),
        ])
    }

    func testByClient() {
        XCTAssertEqual(rows(.client), [
            AggregateRow(key: "Acme", clientText: "Acme", seconds: 14400, hours: 4, entryCount: 2),
            AggregateRow(key: "Globex", clientText: "Globex", seconds: 7200, hours: 2, entryCount: 2),
            AggregateRow(key: "(no client)", clientText: nil, seconds: 1800, hours: 0.5, entryCount: 1),
        ])
    }

    func testByClientDay() {
        XCTAssertEqual(rows(.clientDay), [
            AggregateRow(key: "2026-10-20|Acme", clientText: "Acme", seconds: 7200, hours: 2, entryCount: 1),
            AggregateRow(key: "2026-10-25|Acme", clientText: "Acme", seconds: 3600, hours: 1, entryCount: 1),
            AggregateRow(key: "2026-10-26|Acme", clientText: "Acme", seconds: 3600, hours: 1, entryCount: 1),
            AggregateRow(key: "2026-10-26|Globex", clientText: "Globex", seconds: 3600, hours: 1, entryCount: 1),
            AggregateRow(key: "2026-10-26|(no client)", clientText: nil, seconds: 1800, hours: 0.5, entryCount: 1),
            AggregateRow(key: "2026-10-27|Globex", clientText: "Globex", seconds: 3600, hours: 1, entryCount: 1),
        ])
    }

    func testRangeClipping() {
        // 00:30 on Oct 26 through 09:30: half an hour of entry 2, half an hour of entry 3.
        let r = DateInterval(start: F.date(2026, 10, 26, 0, 30), end: F.date(2026, 10, 26, 9, 30))
        XCTAssertEqual(rows(.client, r), [
            AggregateRow(key: "Acme", clientText: "Acme", seconds: 1800, hours: 0.5, entryCount: 1),
            AggregateRow(key: "Globex", clientText: "Globex", seconds: 1800, hours: 0.5, entryCount: 1),
        ])
        XCTAssertEqual(rows(.day, r).map(\.key), ["2026-10-26"])
    }

    func testEmptyRangeAndGroupByCases() {
        XCTAssertEqual(rows(.day, DateInterval(start: now, duration: 0)), [])
        XCTAssertEqual(GroupBy.allCases.map(\.rawValue), ["day", "week", "client", "clientDay"])
    }

    func testDSTDayKeys() {
        let es = [F.entry(1, F.date(2026, 11, 1, 0, 30), F.date(2026, 11, 2, 0, 30))]
        let r = DateInterval(start: F.date(2026, 11, 1), end: F.date(2026, 11, 3))
        let out = Aggregator.aggregate(entries: es, range: r, groupBy: .day, spec: spec, now: now)
        XCTAssertEqual(out.map(\.key), ["2026-11-01", "2026-11-02"])
        XCTAssertEqual(out.map(\.seconds), [24.5 * 3600, 0.5 * 3600])
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(rows(.client))
        XCTAssertEqual(try JSONDecoder().decode([AggregateRow].self, from: data), rows(.client))
    }
}
