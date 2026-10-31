import Foundation
import GrainsCore
import GrainsReports
import XCTest
@testable import GrainsMCP

final class ToolTests: XCTestCase {
    let server = Fixture.server()
    var week: Week { Fixture.spec.week(containing: Fixture.now) }

    private func ids(_ result: JSONValue, _ key: String = "sessions") -> [String] {
        result[key]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
    }

    private func uuid(_ n: Int) -> String { Fixture.id(n).uuidString }

    // MARK: list_sessions

    func testListSessionsForOneLocalDay() throws {
        let result = server.ok("list_sessions", ["from": "2026-10-26", "to": "2026-10-26"])
        XCTAssertEqual(result["time_zone"], "America/Anchorage")
        XCTAssertEqual(result["from"], "2026-10-26T00:00:00-08:00")
        XCTAssertEqual(result["to"], "2026-10-27T00:00:00-08:00")
        XCTAssertEqual(ids(result), [uuid(5), uuid(1)])
        let sessions = try XCTUnwrap(result["sessions"]?.arrayValue)
        // Crosses the week/day start: whole 4 h, 2 h inside the day.
        XCTAssertEqual(sessions[0]["duration_seconds"], 14_400)
        XCTAssertEqual(sessions[0]["seconds_in_range"], 7_200)
        XCTAssertEqual(sessions[1]["started_at"], "2026-10-26T09:00:00-08:00")
        XCTAssertEqual(sessions[1]["stopped_at"], "2026-10-26T11:30:00-08:00")
        XCTAssertEqual(sessions[1]["raw_text"], "Denali - iPad enrollment")
        XCTAssertEqual(sessions[1]["client_text"], "Denali")
        XCTAssertEqual(sessions[1]["note"], "iPad enrollment")
        XCTAssertEqual(sessions[1]["running"], false)
        XCTAssertEqual(sessions[1]["seconds_in_range"], 9_000)
        XCTAssertEqual(result["count"], 2)
        XCTAssertEqual(result["truncated"], false)
    }

    func testListSessionsClientFilterAndRunningEntry() throws {
        let result = server.ok("list_sessions", ["from": "2026-10-26", "to": "2026-11-01", "client": "DENALI"])
        XCTAssertEqual(ids(result), [uuid(1), uuid(4)])
        let running = try XCTUnwrap(result["sessions"]?.arrayValue?.last)
        XCTAssertEqual(running["running"], true)
        XCTAssertEqual(running["stopped_at"], .null)
        XCTAssertEqual(running["duration_seconds"], 7_200)
    }

    func testListSessionsExcludesDeletedAndMarksRecovered() throws {
        let result = server.ok("list_sessions", ["from": "2026-10-27T00:00:00-08:00", "to": "2026-10-29T00:00:00-08:00"])
        XCTAssertFalse(ids(result).contains(uuid(6)))
        XCTAssertEqual(ids(result), [uuid(2), uuid(7), uuid(3)])
        let recovered = result["sessions"]?.arrayValue?.first { $0["id"] == .string(uuid(7)) }
        XCTAssertEqual(recovered?["recovered"], true)
    }

    func testListSessionsLimit() {
        let result = server.ok("list_sessions", ["from": "2026-10-20", "to": "2026-11-01", "limit": 2])
        XCTAssertEqual(result["count"], 2)
        XCTAssertEqual(result["total_matching"], 6)
        XCTAssertEqual(result["truncated"], true)
    }

    func testListSessionsErrors() {
        XCTAssertTrue(server.toolError("list_sessions", ["from": "last tuesday", "to": "2026-10-27"]).contains("could not parse from"))
        XCTAssertTrue(server.toolError("list_sessions", ["from": "2026-10-27", "to": "2026-10-26T00:00:00Z"]).contains("must be after"))
        XCTAssertTrue(server.toolError("list_sessions", ["to": "2026-10-27"]).contains("missing required argument \"from\""))
        XCTAssertTrue(server.toolError("list_sessions", ["from": "2026-10-26", "to": "2026-10-27", "limit": 0]).contains("between 1 and 1000"))
        XCTAssertTrue(server.toolError("list_sessions", ["from": "2026-10-26", "to": "2026-10-27", "limit": "ten"]).contains("integer"))
        XCTAssertTrue(server.toolError("list_sessions", ["from": 20261026, "to": "2026-10-27"]).contains("must be a string"))
    }

    // MARK: get_session

    func testGetSession() {
        let result = server.ok("get_session", ["id": .string(uuid(2))])
        XCTAssertEqual(result["time_zone"], "America/Anchorage")
        XCTAssertEqual(result["session"]?["client_text"], "Acme")
        XCTAssertEqual(result["session"]?["started_at"], "2026-10-27T23:00:00-08:00")
        XCTAssertEqual(result["session"]?["duration_seconds"], 7_200)
        XCTAssertNil(result["session"]?["seconds_in_range"])
        // Lowercase UUIDs are accepted.
        XCTAssertEqual(server.ok("get_session", ["id": .string(uuid(2).lowercased())])["session"]?["id"], .string(uuid(2)))
    }

    func testGetSessionErrors() {
        XCTAssertTrue(server.toolError("get_session", ["id": .string(Fixture.id(99).uuidString)]).contains("no session"))
        XCTAssertTrue(server.toolError("get_session", ["id": .string(uuid(6))]).contains("no session"), "deleted is not found")
        XCTAssertTrue(server.toolError("get_session", ["id": "abc"]).contains("not a session id"))
        XCTAssertTrue(server.toolError("get_session").contains("missing required argument"))
    }

    // MARK: search_sessions

    func testSearchSessions() {
        let result = server.ok("search_sessions", ["query": "MIGRATION"])
        XCTAssertEqual(ids(result), [uuid(2)])
        XCTAssertEqual(result["query"], "MIGRATION")
        XCTAssertEqual(result["time_zone"], "America/Anchorage")
        // Newest first, limit honored.
        XCTAssertEqual(ids(server.ok("search_sessions", ["query": "acme", "limit": 2])), [uuid(7), uuid(2)])
        XCTAssertEqual(ids(server.ok("search_sessions", ["query": "ghost"])), [])
    }

    func testSearchSessionsErrors() {
        XCTAssertTrue(server.toolError("search_sessions").contains("missing required argument \"query\""))
        XCTAssertTrue(server.toolError("search_sessions", ["query": "  "]).contains("missing required argument"))
        XCTAssertTrue(server.toolError("search_sessions", ["query": "a", "limit": 501]).contains("between 1 and 500"))
    }

    // MARK: aggregate

    func testAggregateByDay() throws {
        let result = server.ok("aggregate", ["from": "2026-10-26", "to": "2026-11-01", "group_by": "day"])
        let rows = try XCTUnwrap(result["rows"]?.arrayValue)
        XCTAssertEqual(rows.map { $0["key"] }, ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29"])
        XCTAssertEqual(rows.map { $0["seconds"] }, [16_200, 3_600, 10_800, 7_200])
        XCTAssertEqual(rows.map { $0["hours"] }, [4.5, 1, 3, 2])
        XCTAssertEqual(rows.map { $0["entry_count"] }, [2, 1, 3, 1])
        XCTAssertEqual(result["total_seconds"], 37_800)
        XCTAssertEqual(result["total_hours"], 10.5)
        XCTAssertEqual(result["group_by"], "day")
        XCTAssertEqual(result["time_zone"], "America/Anchorage")
        XCTAssertEqual(result["to"], "2026-11-02T00:00:00-09:00")
    }

    func testAggregateByClientAndClientDay() throws {
        let byClient = server.ok("aggregate", ["from": "2026-10-26", "to": "2026-11-01", "group_by": "client"])
        let rows = try XCTUnwrap(byClient["rows"]?.arrayValue)
        XCTAssertEqual(rows.map { $0["key"] }, ["Acme", "Denali", "denali", "(no client)"])
        XCTAssertEqual(rows.map { $0["client_text"] }, ["Acme", "Denali", "denali", .null])
        XCTAssertEqual(rows.map { $0["seconds"] }, [18_000, 9_000, 7_200, 3_600])
        XCTAssertEqual(byClient["total_seconds"], 37_800)

        let clientDay = server.ok("aggregate", ["from": "2026-10-28", "to": "2026-10-28", "group_by": "client_day"])
        XCTAssertEqual(clientDay["rows"]?.arrayValue?.map { $0["key"] }, ["2026-10-28|Acme", "2026-10-28|(no client)"])
        XCTAssertEqual(clientDay["rows"]?.arrayValue?.map { $0["seconds"] }, [7_200, 3_600])
        XCTAssertEqual(clientDay["group_by"], "client_day")
    }

    func testAggregateMatchesAggregatorForEveryGrouping() throws {
        let range = DateInterval(start: Fixture.date(2026, 10, 20), end: Fixture.date(2026, 11, 2))
        for (name, groupBy) in [("day", GroupBy.day), ("week", .week), ("client", .client), ("client_day", .clientDay)] {
            let expected = Aggregator.aggregate(entries: Fixture.entries, range: range, groupBy: groupBy, spec: Fixture.spec, now: Fixture.now)
            let result = server.ok("aggregate", ["from": "2026-10-20", "to": "2026-11-01", "group_by": .string(name)])
            let rows = try XCTUnwrap(result["rows"]?.arrayValue)
            XCTAssertEqual(rows.map { $0["key"]?.stringValue }, expected.map(\.key), name)
            XCTAssertEqual(rows.map { $0["seconds"]?.doubleValue }, expected.map(\.seconds), name)
            XCTAssertEqual(rows.map { $0["hours"]?.doubleValue }, expected.map(\.hours), name)
            XCTAssertEqual(rows.map { $0["entry_count"]?.intValue }, expected.map(\.entryCount), name)
        }
    }

    /// docs/testing.md: "MCP aggregate for the week equals the overlay's week total".
    func testAggregateForTheWeekEqualsWeekSeriesTotal() throws {
        let series = WeekSeries.compute(entries: Fixture.entries, week: week, now: Fixture.now, targetHours: nil)
        let coding = DateCoding(timeZone: Fixture.timeZone)
        let result = server.ok("aggregate", [
            "from": .string(coding.rfc3339(week.interval.start)),
            "to": .string(coding.rfc3339(week.interval.end)),
            "group_by": "week",
        ])
        let rows = try XCTUnwrap(result["rows"]?.arrayValue)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["key"], "2026-W44")
        let seconds = try XCTUnwrap(rows[0]["seconds"]?.doubleValue)
        XCTAssertEqual(seconds / 3600, series.totalHours, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(result["total_seconds"]?.doubleValue) / 3600, series.totalHours, accuracy: 1e-9)
        XCTAssertEqual(series.totalHours, 10.5, accuracy: 1e-9)
        // And the same number current_week reports.
        XCTAssertEqual(server.ok("current_week")["total_hours"], result["total_hours"])
    }

    func testAggregateErrors() {
        XCTAssertTrue(server.toolError("aggregate", ["from": "2026-10-26", "to": "2026-11-01", "group_by": "month"]).contains("group_by must be one of"))
        XCTAssertTrue(server.toolError("aggregate", ["from": "2026-10-26", "to": "2026-11-01"]).contains("missing required argument \"group_by\""))
        XCTAssertTrue(server.toolError("aggregate", ["from": "2026-10-26", "to": "2026-13-01", "group_by": "day"]).contains("could not parse to"))
    }

    // MARK: list_client_labels

    func testListClientLabels() throws {
        let result = server.ok("list_client_labels")
        let labels = try XCTUnwrap(result["labels"]?.arrayValue)
        XCTAssertEqual(labels.map { $0["client_text"] }, ["Acme", "denali", .null])
        XCTAssertEqual(labels.map { $0["entry_count"] }, [3, 2, 1])
        XCTAssertEqual(labels.map { $0["total_seconds"] }, [25_200, 16_200, 3_600])
        XCTAssertEqual(labels.map { $0["total_hours"] }, [7, 4.5, 1])
        XCTAssertEqual(result["count"], 3)
    }

    func testListClientLabelsEmptyStore() {
        XCTAssertEqual(Fixture.server(entries: []).ok("list_client_labels"), ["count": 0, "labels": []])
    }

    // MARK: current_week

    func testCurrentWeek() throws {
        let result = server.ok("current_week")
        XCTAssertEqual(result["week"], "2026-W44")
        XCTAssertEqual(result["start"], "2026-10-26T00:00:00-08:00")
        XCTAssertEqual(result["end"], "2026-11-02T00:00:00-09:00")
        XCTAssertEqual(result["now"], "2026-10-29T15:00:00-08:00")
        XCTAssertEqual(result["time_zone"], "America/Anchorage")
        XCTAssertEqual(result["total_hours"], 10.5)
        XCTAssertEqual(result["week_length_hours"], 169)
        XCTAssertEqual(result["elapsed_fraction"], .double((87.0 / 169 * 10_000).rounded() / 10_000))
        XCTAssertEqual(result["days"]?.arrayValue?.map { $0["hours"] }, [4.5, 1, 3, 2, 0, 0, 0])
        XCTAssertEqual(result["days"]?.arrayValue?.first?["date"], "2026-10-26")
        XCTAssertEqual(result["running"], true)
        XCTAssertEqual(result["target_hours"], .null)
        XCTAssertNil(result["target_hours_at_now"])

        let target = server.ok("current_week", ["target_hours": 40])
        XCTAssertEqual(target["target_hours"], 40)
        XCTAssertEqual(target["target_hours_at_now"], .double((40 * 87.0 / 169 * 100).rounded() / 100))
    }

    func testCurrentWeekErrors() {
        XCTAssertTrue(server.toolError("current_week", ["target_hours": -1]).contains("between 0 and 168"))
        XCTAssertTrue(server.toolError("current_week", ["target_hours": "forty"]).contains("must be a number"))
    }

    // MARK: running_session

    func testRunningSession() {
        let result = server.ok("running_session")
        XCTAssertEqual(result["running"]?["id"], .string(uuid(4)))
        XCTAssertEqual(result["elapsed_seconds"], 7_200)
        XCTAssertEqual(result["now"], "2026-10-29T15:00:00-08:00")
        XCTAssertEqual(result["time_zone"], "America/Anchorage")
    }

    func testRunningSessionIdle() {
        let idle = Fixture.server(entries: Fixture.entries.filter { !$0.isRunning }).ok("running_session")
        XCTAssertEqual(idle["running"], .null)
        XCTAssertEqual(idle["elapsed_seconds"], .null)
    }

    // MARK: list_exports

    func testListExports() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "grains-mcp-exports-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("abc".utf8).write(to: dir.appending(path: "Grains-2026-W44.csv"))
        try Data("abcdef".utf8).write(to: dir.appending(path: "Grains-2026-W43.csv"))
        try Data("x".utf8).write(to: dir.appending(path: "notes.txt"))
        try Data("x".utf8).write(to: dir.appending(path: "Grains-backup.csv"))
        let modified = Fixture.date(2026, 10, 28, 12)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: dir.appending(path: "Grains-2026-W43.csv").path(percentEncoded: false))

        let result = Fixture.server(exportDirectory: dir).ok("list_exports")
        XCTAssertEqual(result["exists"], true)
        XCTAssertEqual(result["export_directory"], .string(dir.path(percentEncoded: false)))
        let files = try XCTUnwrap(result["files"]?.arrayValue)
        XCTAssertEqual(files.map { $0["name"] }, ["Grains-2026-W43.csv", "Grains-2026-W44.csv", "Grains-backup.csv"])
        XCTAssertEqual(files.map { $0["week"] }, ["2026-W43", "2026-W44", .null])
        XCTAssertEqual(files.map { $0["size_bytes"] }, [6, 3, 1])
        XCTAssertEqual(files[0]["modified"], "2026-10-28T12:00:00-08:00")
        XCTAssertEqual(result["time_zone"], "America/Anchorage")
    }

    func testListExportsMissingFolder() {
        let result = server.ok("list_exports")
        XCTAssertEqual(result["exists"], false)
        XCTAssertEqual(result["files"], [])
    }

    // MARK: export_week

    func testExportWeekEqualsCSVExporter() throws {
        let result = server.call("export_week", ["week": "2026-W44"])
        XCTAssertEqual(result["isError"], false)
        let text = try XCTUnwrap(result["content"]?.arrayValue?.first?["text"]?.stringValue)
        let expected = CSVExporter(spec: Fixture.spec).csv(for: week, entries: Fixture.entries, now: Fixture.now)
        XCTAssertEqual(text, expected)
        XCTAssertTrue(text.hasPrefix(CSVSchema.columns.joined(separator: ",") + "\n"))
        XCTAssertEqual(result["structuredContent"]?["csv"], .string(expected))
        XCTAssertEqual(result["structuredContent"]?["file_name"], "Grains-2026-W44.csv")
        XCTAssertEqual(result["structuredContent"]?["row_count"], 6)
        XCTAssertEqual(result["structuredContent"]?["time_zone"], "America/Anchorage")
        XCTAssertFalse(text.contains("Ghost"))
    }

    func testExportWeekKeepsZeroLengthEntryAtWeekStart() throws {
        let zero = Entry(id: Fixture.id(20), rawText: "blip", startedAt: week.interval.start, stoppedAt: week.interval.start)
        let entries = Fixture.entries + [zero]
        let text = try XCTUnwrap(Fixture.server(entries: entries).call("export_week", ["week": "2026-W44"])["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertEqual(text, CSVExporter(spec: Fixture.spec).csv(for: week, entries: entries, now: Fixture.now))
        XCTAssertTrue(text.contains("blip"))
    }

    func testExportWeekOtherWeekAndErrors() throws {
        let w43 = week.previous(spec: Fixture.spec)
        let text = try XCTUnwrap(server.call("export_week", ["week": "2026-W43"])["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertEqual(text, CSVExporter(spec: Fixture.spec).csv(for: w43, entries: Fixture.entries, now: Fixture.now))
        XCTAssertTrue(text.contains(uuid(5)), "the week-crossing session appears in both weeks")
        XCTAssertTrue(server.toolError("export_week", ["week": "2026-W60"]).contains("not a valid ISO week id"))
        XCTAssertTrue(server.toolError("export_week", ["week": "last week"]).contains("not a valid ISO week id"))
        XCTAssertTrue(server.toolError("export_week").contains("missing required argument \"week\""))
    }

    // MARK: Conventions

    func testEveryResultWithTimesCarriesTimeZone() {
        let calls: [(String, [String: JSONValue])] = [
            ("list_sessions", ["from": "2026-10-26", "to": "2026-11-01"]),
            ("get_session", ["id": .string(uuid(1))]),
            ("search_sessions", ["query": "a"]),
            ("aggregate", ["from": "2026-10-26", "to": "2026-11-01", "group_by": "day"]),
            ("current_week", [:]),
            ("running_session", [:]),
            ("list_exports", [:]),
            ("export_week", ["week": "2026-W44"]),
        ]
        for (tool, arguments) in calls {
            XCTAssertEqual(server.ok(tool, arguments)["time_zone"], "America/Anchorage", tool)
        }
    }
}
