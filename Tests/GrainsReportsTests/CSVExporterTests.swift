import XCTest
import GrainsCore
@testable import GrainsReports

final class CSVExporterTests: XCTestCase {
    typealias F = Fixtures
    let spec = Fixtures.spec
    var exporter: CSVExporter { CSVExporter(spec: spec) }
    var w43: Week { spec.week(containing: F.date(2026, 10, 21)) }

    func testThreeEntryWeekFixture() {
        let e1 = Entry(id: F.id(1), rawText: "Acme, Inc: fix \"login\" bug", clientText: "Acme, Inc",
                       note: "fix \"login\" bug", startedAt: F.date(2026, 10, 20, 9),
                       stoppedAt: F.date(2026, 10, 20, 10, 30), updatedAt: F.date(2026, 10, 20, 10, 30))
        let e2 = Entry(id: F.id(2), rawText: "Globex standup", clientText: "Globex", note: "standup",
                       clientID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                       startedAt: F.date(2026, 10, 21, 23, 30), stoppedAt: F.date(2026, 10, 22, 0, 45),
                       metadata: EntryMetadata(recovered: .init(lastHeartbeat: F.date(2026, 10, 22, 0, 45),
                                                                noticedAt: F.date(2026, 10, 22, 8))))
        let e3 = Entry(id: F.id(3), rawText: "deep work", note: "deep work", startedAt: F.date(2026, 10, 25, 22))
        let deleted = F.entry(4, F.date(2026, 10, 22, 9), F.date(2026, 10, 22, 10), deleted: true)
        let now = F.date(2026, 10, 25, 23, 0, 30)

        let expected = """
        id,week,started_at,stopped_at,started_local_date,started_local_time,stopped_local_date,stopped_local_time,duration_seconds,whole_duration_seconds,hours,raw_text,client_text,note,client_id,running,recovered,created_at,updated_at
        00000000-0000-0000-0000-000000000001,2026-W43,2026-10-20T09:00:00-08:00,2026-10-20T10:30:00-08:00,2026-10-20,09:00:00,2026-10-20,10:30:00,5400,5400,1.50,"Acme, Inc: fix ""login"" bug","Acme, Inc","fix ""login"" bug",,false,false,2026-10-20T09:00:00-08:00,2026-10-20T10:30:00-08:00
        00000000-0000-0000-0000-000000000002,2026-W43,2026-10-21T23:30:00-08:00,2026-10-22T00:45:00-08:00,2026-10-21,23:30:00,2026-10-22,00:45:00,4500,4500,1.25,Globex standup,Globex,standup,11111111-2222-3333-4444-555555555555,false,true,2026-10-21T23:30:00-08:00,2026-10-21T23:30:00-08:00
        00000000-0000-0000-0000-000000000003,2026-W43,2026-10-25T22:00:00-08:00,,2026-10-25,22:00:00,,,3630,3630,1.01,deep work,,deep work,,true,false,2026-10-25T22:00:00-08:00,2026-10-25T22:00:00-08:00

        """
        let csv = exporter.csv(for: w43, entries: [e3, deleted, e2, e1], now: now)
        XCTAssertEqual(csv, expected)
        XCTAssertEqual(Array(csv.utf8), Array(expected.utf8))
        XCTAssertFalse(csv.contains("\r"))
        XCTAssertEqual(CSVExporter.fileName(for: w43), "Grains-2026-W43.csv")
    }

    func testWeekBoundaryClipping() {
        let e = F.entry(1, F.date(2026, 10, 25, 23), F.date(2026, 10, 26, 1))
        let now = F.date(2026, 10, 30)
        let a = exporter.csv(for: w43, entries: [e], now: now)
        let b = exporter.csv(for: w43.next(spec: spec), entries: [e], now: now)
        func columns(_ csv: String) -> [String: String] {
            let lines = csv.split(separator: "\n").map(String.init)
            XCTAssertEqual(lines.count, 2)
            return Dictionary(uniqueKeysWithValues: zip(CSVSchema.columns, lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)))
        }
        let ra = columns(a), rb = columns(b)
        XCTAssertEqual(ra["week"], "2026-W43")
        XCTAssertEqual(rb["week"], "2026-W44")
        XCTAssertEqual(ra["duration_seconds"], "3600")
        XCTAssertEqual(rb["duration_seconds"], "3600")
        XCTAssertEqual(ra["whole_duration_seconds"], "7200")
        XCTAssertEqual(rb["whole_duration_seconds"], "7200")
        XCTAssertEqual(ra["hours"], "1.00")
        XCTAssertEqual(rb["started_at"], "2026-10-25T23:00:00-08:00")
    }

    func testEntriesOutsideWeekExcludedAndZeroLengthInsideIncluded() {
        let outside = F.entry(1, F.date(2026, 10, 27, 9), F.date(2026, 10, 27, 10))
        let zero = F.entry(2, F.date(2026, 10, 21, 9), F.date(2026, 10, 21, 9))
        let csv = exporter.csv(for: w43, entries: [outside, zero], now: F.date(2026, 10, 30))
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasPrefix(F.id(2).uuidString))
        XCTAssertTrue(lines[1].contains(",0,0,0.00,"))
    }

    func testFractionalSecondsTruncatedConsistently() {
        let start = F.date(2026, 10, 21, 9).addingTimeInterval(0.7)
        let stop = F.date(2026, 10, 21, 9, 0, 10).addingTimeInterval(0.2)
        let csv = exporter.csv(for: w43, entries: [F.entry(1, start, stop)], now: stop)
        XCTAssertTrue(csv.contains(",2026-10-21T09:00:00-08:00,2026-10-21T09:00:10-08:00,"))
        XCTAssertTrue(csv.contains(",10,10,0.00,"))
    }

    func testOffsetsAcrossDSTAndUTC() {
        let clock = LocalClock(timeZone: Fixtures.timeZone)
        XCTAssertEqual(clock.rfc3339(F.date(2026, 11, 2, 9, 14, 3)), "2026-11-02T09:14:03-09:00")
        XCTAssertEqual(clock.rfc3339(F.date(2026, 10, 27, 9, 14, 3)), "2026-10-27T09:14:03-08:00")
        let utc = LocalClock(timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(utc.rfc3339(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00+00:00")
        let kolkata = LocalClock(timeZone: TimeZone(identifier: "Asia/Kolkata")!)
        XCTAssertEqual(kolkata.rfc3339(Date(timeIntervalSince1970: 0)), "1970-01-01T05:30:00+05:30")
    }

    func testQuotingAndHours() {
        XCTAssertEqual(CSVExporter.quote("plain"), "plain")
        XCTAssertEqual(CSVExporter.quote("a,b"), "\"a,b\"")
        XCTAssertEqual(CSVExporter.quote("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(CSVExporter.quote("line1\nline2"), "\"line1\nline2\"")
        XCTAssertEqual(CSVExporter.quote("cr\r\nlf"), "\"cr\r\nlf\"")
        XCTAssertEqual(CSVExporter.quote(""), "")
        XCTAssertEqual(CSVExporter.hours(seconds: 0), "0.00")
        XCTAssertEqual(CSVExporter.hours(seconds: 17), "0.00")
        XCTAssertEqual(CSVExporter.hours(seconds: 18), "0.01")
        XCTAssertEqual(CSVExporter.hours(seconds: 1799), "0.50")
        XCTAssertEqual(CSVExporter.hours(seconds: 36_000), "10.00")
    }

    func testSchema() {
        XCTAssertEqual(CSVSchema.version, 1)
        XCTAssertEqual(CSVSchema.columns.count, 19)
        XCTAssertEqual(Set(CSVSchema.columns).count, 19)
    }

    func testDeterministicOrderingByStartThenID() {
        let s = F.date(2026, 10, 21, 9)
        let es = [F.entry(9, s, s.addingTimeInterval(60)), F.entry(3, s, s.addingTimeInterval(60))]
        let csv = exporter.csv(for: w43, entries: es, now: s)
        let lines = csv.split(separator: "\n")
        XCTAssertTrue(lines[1].hasPrefix(F.id(3).uuidString))
        XCTAssertTrue(lines[2].hasPrefix(F.id(9).uuidString))
        XCTAssertEqual(csv, exporter.csv(for: w43, entries: es.reversed(), now: s))
    }
}
