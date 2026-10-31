import Foundation
import GrainsCore
import GrainsReports
import XCTest
@testable import GrainsMCP

/// Fixed calendar, time zone, clock and data for every MCP test (never the machine's).
enum Fixture {
    static let timeZone = TimeZone(identifier: "America/Anchorage")!

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    static var spec: WeekSpec { WeekSpec(startsOn: 2, calendar: calendar) }

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
    }

    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    /// Thursday of ISO week 2026-W44 (Mon Oct 26 – Mon Nov 2; 169 h long: DST ends Nov 1).
    static let now = date(2026, 10, 29, 15, 0)
    static let hour: TimeInterval = 3600

    static var entries: [Entry] {
        [
            Entry(id: id(1), rawText: "Denali - iPad enrollment", clientText: "Denali", note: "iPad enrollment",
                  startedAt: date(2026, 10, 26, 9), stoppedAt: date(2026, 10, 26, 11, 30)),
            Entry(id: id(2), rawText: "Acme - server migration secret", clientText: "Acme", note: "server migration secret",
                  startedAt: date(2026, 10, 27, 23), stoppedAt: date(2026, 10, 28, 1)),
            Entry(id: id(3), rawText: "admin", startedAt: date(2026, 10, 28, 13), stoppedAt: date(2026, 10, 28, 14)),
            Entry(id: id(4), rawText: "denali - followup", clientText: "denali", note: "followup",
                  startedAt: date(2026, 10, 29, 13)),
            // Crosses the week start: 2 h before, 2 h inside W44.
            Entry(id: id(5), rawText: "Acme - overnight", clientText: "Acme", note: "overnight",
                  startedAt: date(2026, 10, 25, 22), stoppedAt: date(2026, 10, 26, 2)),
            // Soft-deleted: invisible everywhere.
            Entry(id: id(6), rawText: "Ghost - gone", clientText: "Ghost", note: "gone",
                  startedAt: date(2026, 10, 27, 10), stoppedAt: date(2026, 10, 27, 12), deletedAt: date(2026, 10, 27, 12)),
            // Crash-recovered, not reconciled.
            Entry(id: id(7), rawText: "Acme - recovered", clientText: "Acme", note: "recovered",
                  startedAt: date(2026, 10, 28, 8), stoppedAt: date(2026, 10, 28, 9),
                  metadata: EntryMetadata(recovered: .init(lastHeartbeat: date(2026, 10, 28, 9), noticedAt: date(2026, 10, 28, 10)))),
        ]
    }

    static func store(_ entries: [Entry] = Fixture.entries) -> InMemoryEntryStore {
        InMemoryEntryStore(entries: entries, now: { Fixture.now })
    }

    static func server(
        entries: [Entry] = Fixture.entries, redact: Bool = false, spec: WeekSpec = Fixture.spec,
        exportDirectory: URL = URL(filePath: "/nonexistent/grains-exports")
    ) -> MCPServer {
        MCPServer(store: store(entries), spec: spec, exportDirectory: exportDirectory,
                  options: .init(redactNotes: redact, now: { Fixture.now }))
    }
}

/// JSON-RPC helpers over `MCPServer.handle(_:)`.
extension MCPServer {
    func send(_ message: JSONValue) -> JSONValue? {
        handle(Data(message.compactString().utf8)).map { try! JSONValue.parse($0) }
    }

    func request(_ method: String, _ params: JSONValue? = nil, id: JSONValue = 1) -> JSONValue {
        var message: [String: JSONValue] = ["jsonrpc": "2.0", "id": id, "method": .string(method)]
        if let params { message["params"] = params }
        return send(.object(message))!
    }

    /// Calls a tool and returns its `result`.
    func call(_ tool: String, _ arguments: [String: JSONValue] = [:], file: StaticString = #filePath, line: UInt = #line) -> JSONValue {
        let response = request("tools/call", ["name": .string(tool), "arguments": .object(arguments)])
        XCTAssertNil(response["error"], "protocol error: \(response.compactString())", file: file, line: line)
        return response["result"] ?? .null
    }

    /// Calls a tool expected to succeed; returns `structuredContent` after checking it equals the text.
    func ok(_ tool: String, _ arguments: [String: JSONValue] = [:], file: StaticString = #filePath, line: UInt = #line) -> JSONValue {
        let result = call(tool, arguments, file: file, line: line)
        XCTAssertEqual(result["isError"], false, "tool failed: \(result.compactString())", file: file, line: line)
        let structured = result["structuredContent"] ?? .null
        if tool != "export_week", let text = result["content"]?.arrayValue?.first?["text"]?.stringValue {
            XCTAssertEqual(try? JSONValue.parse(Data(text.utf8)), structured, "text and structuredContent differ", file: file, line: line)
            XCTAssertEqual(text, structured.prettyString(), file: file, line: line)
        }
        return structured
    }

    /// Calls a tool expected to fail with `isError: true`; returns the message.
    func toolError(_ tool: String, _ arguments: [String: JSONValue] = [:], file: StaticString = #filePath, line: UInt = #line) -> String {
        let result = call(tool, arguments, file: file, line: line)
        XCTAssertEqual(result["isError"], true, "expected isError: \(result.compactString())", file: file, line: line)
        XCTAssertNil(result["structuredContent"], file: file, line: line)
        return result["content"]?.arrayValue?.first?["text"]?.stringValue ?? ""
    }
}

extension JSONValue {
    /// All object keys anywhere in the tree.
    var allKeys: Set<String> {
        switch self {
        case .object(let o): return o.reduce(into: Set(o.keys)) { $0.formUnion($1.value.allKeys) }
        case .array(let a): return a.reduce(into: Set()) { $0.formUnion($1.allKeys) }
        default: return []
        }
    }
}
