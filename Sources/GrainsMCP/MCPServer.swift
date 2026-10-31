import Foundation
import GrainsCore
import GrainsReports

/// Identity reported in `initialize`.
public struct ServerInfo: Sendable {
    public static let name = "grains"
    public static let title = "Grains"
    public static let version = "0.1.0"
    /// The only MCP revision this server speaks (D18).
    public static let protocolVersion = "2025-06-18"
}

/// JSON-RPC 2.0 error codes used by the server.
public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

/// Read-only MCP server over an `EntryReading`. Transport-independent: `handle(_:)` maps one
/// JSON-RPC message to its response, so tests need no process; `runStdio()` adds the
/// newline-delimited stdio framing. Immutable after init, hence `Sendable`.
public final class MCPServer: Sendable {
    public struct Options: Sendable {
        /// Hide `note` and replace `raw_text` with `client_text` (or `[redacted]`) everywhere.
        public var redactNotes: Bool
        /// Evaluation instant for running entries, "current week" and elapsed time.
        public var now: @Sendable () -> Date

        public init(redactNotes: Bool = false, now: @escaping @Sendable () -> Date = { Date() }) {
            self.redactNotes = redactNotes
            self.now = now
        }
    }

    let store: any EntryReading
    let spec: WeekSpec
    let exportDirectory: URL
    let options: Options
    let dates: DateCoding

    public init(store: any EntryReading, spec: WeekSpec, exportDirectory: URL, options: Options = Options()) {
        self.store = store
        self.spec = spec
        self.exportDirectory = exportDirectory
        self.options = options
        self.dates = DateCoding(timeZone: spec.calendar.timeZone)
    }

    // MARK: Message handling

    /// Handles one JSON-RPC message (one line, without the newline). Returns the compact
    /// response, or `nil` when no response is due (notifications, client responses).
    public func handle(_ requestJSON: Data) -> Data? {
        handleMessage(requestJSON).map { Data($0.compactString().utf8) }
    }

    /// Same as `handle(_:)` but returns the response as a value (tests).
    public func handleMessage(_ requestJSON: Data) -> JSONValue? {
        let message: JSONValue
        do {
            message = try JSONValue.parse(requestJSON)
        } catch {
            return Self.errorResponse(id: .null, code: JSONRPCErrorCode.parseError, message: "Parse error: the message is not valid JSON")
        }
        if case .array = message {
            // JSON-RPC batching was removed from MCP in 2025-06-18.
            return Self.errorResponse(id: .null, code: JSONRPCErrorCode.invalidRequest, message: "Invalid Request: batch requests are not supported (MCP 2025-06-18)")
        }
        guard case .object(let object) = message else {
            return Self.errorResponse(id: .null, code: JSONRPCErrorCode.invalidRequest, message: "Invalid Request: expected a JSON object")
        }
        let id = object["id"]
        if let id, !Self.isValidID(id) {
            return Self.errorResponse(id: .null, code: JSONRPCErrorCode.invalidRequest, message: "Invalid Request: id must be a string or a number")
        }
        guard object["jsonrpc"] == .string("2.0") else {
            return id == nil ? nil : Self.errorResponse(id: id!, code: JSONRPCErrorCode.invalidRequest, message: "Invalid Request: jsonrpc must be \"2.0\"")
        }
        guard let method = object["method"]?.stringValue else {
            // A response from the client (we never send requests) or garbage without an id.
            if object["result"] != nil || object["error"] != nil { return nil }
            return id == nil ? nil : Self.errorResponse(id: id!, code: JSONRPCErrorCode.invalidRequest, message: "Invalid Request: missing method")
        }
        let params = object["params"]
        guard let id else {
            // Notification: never answered, whatever the method (initialized, cancelled, ...).
            return nil
        }
        if let params, params.objectValue == nil, !params.isNull {
            return Self.errorResponse(id: id, code: JSONRPCErrorCode.invalidParams, message: "Invalid params: params must be an object")
        }
        switch dispatch(method: method, params: params?.objectValue ?? [:]) {
        case .success(let result):
            return ["jsonrpc": "2.0", "id": id, "result": result]
        case .failure(let error):
            return Self.errorResponse(id: id, code: error.code, message: error.message)
        }
    }

    struct RPCError: Error {
        var code: Int
        var message: String
    }

    private func dispatch(method: String, params: [String: JSONValue]) -> Result<JSONValue, RPCError> {
        switch method {
        case "initialize":
            return .success(initializeResult())
        case "ping", "notifications/initialized":
            return .success([:])
        case "tools/list":
            return .success(["tools": .array(Tools.definitions.map(\.json))])
        case "tools/call":
            return callTool(params)
        case "resources/list":
            return .success(["resources": []])
        case "resources/templates/list":
            return .success(["resourceTemplates": []])
        case "prompts/list":
            return .success(["prompts": []])
        default:
            return .failure(RPCError(code: JSONRPCErrorCode.methodNotFound, message: "Method not found: \(method)"))
        }
    }

    private func initializeResult() -> JSONValue {
        [
            "protocolVersion": .string(ServerInfo.protocolVersion),
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": .string(ServerInfo.name), "title": .string(ServerInfo.title), "version": .string(ServerInfo.version)],
            "instructions": .string(Tools.conventions),
        ]
    }

    private func callTool(_ params: [String: JSONValue]) -> Result<JSONValue, RPCError> {
        guard let name = params["name"]?.stringValue else {
            return .failure(RPCError(code: JSONRPCErrorCode.invalidParams, message: "Invalid params: tools/call requires a string \"name\""))
        }
        guard let tool = Tools.definitions.first(where: { $0.name == name }) else {
            return .failure(RPCError(code: JSONRPCErrorCode.invalidParams, message: "Invalid params: unknown tool \"\(name)\""))
        }
        let arguments: [String: JSONValue]
        switch params["arguments"] {
        case nil, .null?: arguments = [:]
        case .object(let object)?: arguments = object
        default:
            return .failure(RPCError(code: JSONRPCErrorCode.invalidParams, message: "Invalid params: arguments must be an object"))
        }
        let output: ToolOutput
        do {
            output = try runTool(tool.name, Arguments(values: arguments, tool: tool.name))
        } catch let failure as ToolFailure {
            output = .failure(failure.message)
        } catch {
            output = .failure("Could not read the Grains database: \(error)")
        }
        return .success(output.json)
    }

    // MARK: Stdio transport

    /// Reads newline-delimited JSON-RPC messages from stdin until EOF and writes each response
    /// as one line to stdout. Returns on EOF or when stdout is closed (broken pipe). Logs go to
    /// stderr only; stdout carries nothing but protocol messages.
    public func runStdio() {
        Self.log("grains-mcp \(ServerInfo.version) ready (protocol \(ServerInfo.protocolVersion), time zone \(spec.calendar.timeZone.identifier)\(options.redactNotes ? ", notes redacted" : ""))")
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let response = handle(Data(trimmed.utf8)) else { continue }
            do {
                try FileHandle.standardOutput.write(contentsOf: response + Data([0x0A]))
            } catch {
                Self.log("stdout closed (\(error.localizedDescription)); exiting")
                return
            }
        }
        Self.log("stdin closed; exiting")
    }

    /// Writes one line to stderr.
    public static func log(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("[grains-mcp] \(message)\n".utf8))
    }

    // MARK: Helpers

    static func errorResponse(id: JSONValue, code: Int, message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .int(Int64(code)), "message": .string(message)]]
    }

    private static func isValidID(_ id: JSONValue) -> Bool {
        switch id {
        case .string, .int: return true
        case .double(let d): return d.rounded() == d
        default: return false
        }
    }
}

/// The result of one tool call.
enum ToolOutput {
    /// Structured result: `content` is the pretty JSON, `structuredContent` the same object.
    case object(JSONValue)
    /// Plain text content plus a structured companion (used by `export_week` for the CSV).
    case text(String, structured: JSONValue)
    /// `isError: true` with a readable message.
    case failure(String)

    var json: JSONValue {
        switch self {
        case .object(let value):
            return ["content": [["type": "text", "text": .string(value.prettyString())]], "structuredContent": value, "isError": false]
        case .text(let text, let structured):
            return ["content": [["type": "text", "text": .string(text)]], "structuredContent": structured, "isError": false]
        case .failure(let message):
            return ["content": [["type": "text", "text": .string(message)]], "isError": true]
        }
    }
}

/// A tool-level failure reported as `isError: true` (bad argument value, not found).
struct ToolFailure: Error {
    var message: String
    init(_ message: String) { self.message = message }
}
