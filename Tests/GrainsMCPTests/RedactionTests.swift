import Foundation
import GrainsCore
import GrainsReports
import XCTest
@testable import GrainsMCP

final class RedactionTests: XCTestCase {
    let server = Fixture.server(redact: true)

    func testSessionsHaveNoNotesAndRawTextIsTheLabel() throws {
        let result = server.ok("list_sessions", ["from": "2026-10-20", "to": "2026-11-01"])
        XCTAssertFalse(result.allKeys.contains("note"))
        let sessions = try XCTUnwrap(result["sessions"]?.arrayValue)
        for session in sessions {
            XCTAssertEqual(session["raw_text"], session["client_text"] == .null ? "[redacted]" : session["client_text"])
        }
        XCTAssertFalse(result.compactString().contains("secret"))
        XCTAssertFalse(result.compactString().contains("iPad"))
        let text = server.call("list_sessions", ["from": "2026-10-20", "to": "2026-11-01"])["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
        XCTAssertFalse(text.contains("secret"))
    }

    func testGetAndRunningAreRedacted() {
        let session = server.ok("get_session", ["id": .string(Fixture.id(3).uuidString)])["session"]
        XCTAssertEqual(session?["raw_text"], "[redacted]")
        XCTAssertNil(session?["note"])
        let running = server.ok("running_session")["running"]
        XCTAssertEqual(running?["raw_text"], "denali")
        XCTAssertNil(running?["note"])
    }

    func testSearchOnlyMatchesTheVisibleLabel() {
        XCTAssertEqual(server.ok("search_sessions", ["query": "secret"])["count"], 0, "hidden text must not be searchable")
        XCTAssertEqual(server.ok("search_sessions", ["query": "enrollment"])["count"], 0)
        XCTAssertEqual(server.ok("search_sessions", ["query": "acm"])["count"], 3)
        XCTAssertEqual(server.ok("search_sessions", ["query": "acm", "limit": 1])["count"], 1)
    }

    func testExportWeekIsRedacted() throws {
        let result = server.call("export_week", ["week": "2026-W44"])
        let text = try XCTUnwrap(result["content"]?.arrayValue?.first?["text"]?.stringValue)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("iPad"))
        XCTAssertFalse(text.contains("followup"))
        let redacted = Fixture.entries.map { entry -> Entry in
            var e = entry
            e.rawText = entry.clientText ?? "[redacted]"
            e.note = nil
            return e
        }
        let week = Fixture.spec.week(containing: Fixture.now)
        XCTAssertEqual(text, CSVExporter(spec: Fixture.spec).csv(for: week, entries: redacted, now: Fixture.now))
    }

    func testTotalsAreUnchangedByRedaction() {
        let args: [String: JSONValue] = ["from": "2026-10-26", "to": "2026-11-01", "group_by": "client"]
        XCTAssertEqual(server.ok("aggregate", args), Fixture.server().ok("aggregate", args))
        XCTAssertEqual(server.ok("list_client_labels"), Fixture.server().ok("list_client_labels"))
    }
}
