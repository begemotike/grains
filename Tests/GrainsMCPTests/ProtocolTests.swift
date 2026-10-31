import Foundation
import XCTest
@testable import GrainsMCP

final class ProtocolTests: XCTestCase {
    func testInitializeHandshake() {
        let server = Fixture.server()
        let response = server.request("initialize", [
            "protocolVersion": "2025-06-18",
            "capabilities": [:],
            "clientInfo": ["name": "test", "version": "1"],
        ])
        XCTAssertEqual(response["jsonrpc"], "2.0")
        XCTAssertEqual(response["id"], 1)
        let result = response["result"]
        XCTAssertEqual(result?["protocolVersion"], "2025-06-18")
        XCTAssertEqual(result?["capabilities"]?["tools"]?["listChanged"], false)
        XCTAssertEqual(result?["serverInfo"]?["name"], "grains")
        XCTAssertEqual(result?["serverInfo"]?["version"], .string(ServerInfo.version))
        XCTAssertTrue(result?["instructions"]?.stringValue?.contains("provisional label") ?? false)

        // The initialized notification gets no response.
        XCTAssertNil(server.send(["jsonrpc": "2.0", "method": "notifications/initialized"]))
        XCTAssertNil(server.handle(Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)))
    }

    func testPingAndEmptyListings() {
        let server = Fixture.server()
        XCTAssertEqual(server.request("ping")["result"], [:])
        XCTAssertEqual(server.request("resources/list")["result"], ["resources": []])
        XCTAssertEqual(server.request("prompts/list")["result"], ["prompts": []])
    }

    func testResponsesAreSingleLineWithSortedKeys() throws {
        let server = Fixture.server()
        let data = try XCTUnwrap(server.handle(Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"current_week"}}"#.utf8)))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\n"), "framing requires one line per message")
        XCTAssertTrue(text.hasPrefix(#"{"id":7,"jsonrpc":"2.0","result":"#))
    }

    func testStringIDIsEchoed() {
        let response = Fixture.server().request("ping", id: "abc-1")
        XCTAssertEqual(response["id"], "abc-1")
        XCTAssertEqual(response["result"], [:])
    }

    func testUnknownMethod() {
        let response = Fixture.server().request("sampling/createMessage", id: 9)
        XCTAssertEqual(response["id"], 9)
        XCTAssertEqual(response["error"]?["code"], .int(Int64(JSONRPCErrorCode.methodNotFound)))
        XCTAssertNil(response["result"])
    }

    func testUnknownNotificationIsIgnored() {
        XCTAssertNil(Fixture.server().send(["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": 3]]))
    }

    func testClientResponsesAreIgnored() {
        XCTAssertNil(Fixture.server().send(["jsonrpc": "2.0", "id": 4, "result": [:]]))
    }

    func testMalformedJSON() throws {
        let data = try XCTUnwrap(Fixture.server().handle(Data(#"{"jsonrpc":"2.0","id":1,"method":"#.utf8)))
        let response = try JSONValue.parse(data)
        XCTAssertEqual(response["id"], .null)
        XCTAssertEqual(response["error"]?["code"], .int(Int64(JSONRPCErrorCode.parseError)))
    }

    func testBatchIsNotSupported() throws {
        let batch = #"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","id":2,"method":"ping"}]"#
        let response = try JSONValue.parse(XCTUnwrap(Fixture.server().handle(Data(batch.utf8))))
        XCTAssertEqual(response["id"], .null)
        XCTAssertEqual(response["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidRequest)))
        XCTAssertTrue(response["error"]?["message"]?.stringValue?.contains("batch") ?? false)
    }

    func testInvalidRequests() {
        let server = Fixture.server()
        // Not an object.
        XCTAssertEqual(server.send("hello")?["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidRequest)))
        // Wrong jsonrpc version.
        XCTAssertEqual(server.send(["jsonrpc": "1.0", "id": 1, "method": "ping"])?["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidRequest)))
        // Missing method.
        XCTAssertEqual(server.send(["jsonrpc": "2.0", "id": 1])?["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidRequest)))
        // Null id is not allowed by MCP.
        XCTAssertEqual(server.send(["jsonrpc": "2.0", "id": nil, "method": "ping"])?["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidRequest)))
        // params must be an object.
        XCTAssertEqual(server.request("tools/list", [1, 2])["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidParams)))
    }

    func testToolsCallInvalidParams() {
        let server = Fixture.server()
        let unknownTool = server.request("tools/call", ["name": "delete_everything"])
        XCTAssertEqual(unknownTool["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidParams)))
        let missingName = server.request("tools/call", ["arguments": [:]])
        XCTAssertEqual(missingName["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidParams)))
        let badArguments = server.request("tools/call", ["name": "get_session", "arguments": "x"])
        XCTAssertEqual(badArguments["error"]?["code"], .int(Int64(JSONRPCErrorCode.invalidParams)))
    }

    func testToolsListHasNineToolsWithValidSchemas() throws {
        let response = Fixture.server().request("tools/list")
        let tools = try XCTUnwrap(response["result"]?["tools"]?.arrayValue)
        XCTAssertEqual(tools.count, 9)
        XCTAssertEqual(Set(tools.compactMap { $0["name"]?.stringValue }), [
            "list_sessions", "get_session", "search_sessions", "aggregate", "list_client_labels",
            "current_week", "running_session", "list_exports", "export_week",
        ])
        for tool in tools {
            let name = tool["name"]?.stringValue ?? "?"
            let description = try XCTUnwrap(tool["description"]?.stringValue, name)
            XCTAssertTrue(description.contains("client_text is a provisional label typed by the user"), name)
            XCTAssertTrue(description.contains("RFC 3339"), name)
            XCTAssertTrue(description.contains("computed deterministically by Grains"), name)
            let schema = try XCTUnwrap(tool["inputSchema"], name)
            XCTAssertEqual(schema["type"], "object", name)
            XCTAssertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema", name)
            let properties = try XCTUnwrap(schema["properties"]?.objectValue, name)
            let required = try XCTUnwrap(schema["required"]?.arrayValue, name).compactMap(\.stringValue)
            XCTAssertTrue(Set(required).isSubset(of: properties.keys), name)
            for (key, property) in properties {
                XCTAssertNotNil(property["type"]?.stringValue, "\(name).\(key) has no type")
                XCTAssertNotNil(property["description"]?.stringValue, "\(name).\(key) has no description")
            }
            XCTAssertEqual(tool["annotations"]?["readOnlyHint"], true, name)
        }
        let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0["name"]!.stringValue!, $0) })
        XCTAssertEqual(byName["aggregate"]?["inputSchema"]?["required"], ["from", "to", "group_by"])
        XCTAssertEqual(byName["aggregate"]?["inputSchema"]?["properties"]?["group_by"]?["enum"], ["day", "week", "client", "client_day"])
        XCTAssertEqual(byName["export_week"]?["inputSchema"]?["required"], ["week"])
        XCTAssertEqual(byName["list_client_labels"]?["inputSchema"]?["required"], [])
    }

    func testJSONSerialization() throws {
        let value: JSONValue = ["b": [1, 2.5, "x\n\"y\"", nil, true], "a": ["z": 1, "c": [:]]]
        XCTAssertEqual(value.compactString(), #"{"a":{"c":{},"z":1},"b":[1,2.5,"x\n\"y\"",null,true]}"#)
        XCTAssertEqual(try JSONValue.parse(Data(value.prettyString().utf8)), value)
        XCTAssertEqual(JSONValue.double(3.0).compactString(), "3")
        XCTAssertEqual(JSONValue.string("\u{01}").compactString(), #""\u0001""#)
    }
}
