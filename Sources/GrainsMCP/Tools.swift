import Foundation

/// One entry in `tools/list`.
struct ToolDefinition: Sendable {
    var name: String
    var title: String
    var description: String
    var properties: [String: JSONValue]
    var required: [String]

    var inputSchema: JSONValue {
        [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
            "additionalProperties": false,
        ]
    }

    var json: JSONValue {
        [
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": inputSchema,
            "annotations": [
                "title": .string(title),
                "readOnlyHint": true,
                "destructiveHint": false,
                "idempotentHint": true,
                "openWorldHint": false,
            ],
        ]
    }
}

/// The nine read-only tools (docs/mcp-server.md, binding).
enum Tools {
    /// Stated in `initialize.instructions` and appended to every tool description.
    static let conventions = """
    Grains conventions: client_text is a provisional label typed by the user at capture time; \
    it may be a typo or an alias of another label, so propose merges instead of assuming. \
    raw_text is exactly what the user typed. Times are RFC 3339 with a UTC offset, and every \
    result with times includes time_zone (IANA id) so never guess the zone. Durations, hours \
    and totals are computed deterministically by Grains (overlapping time counts once per \
    bucket); report them as given and do not recompute or estimate them. A running session \
    has stopped_at null and is valued up to now. Access is read-only.
    """

    static let dateFormatNote = "RFC 3339 timestamp with offset (2026-10-27T09:00:00-08:00) or a local date YYYY-MM-DD in the Grains time zone"

    static func dateProperty(_ role: String) -> JSONValue {
        let detail = role == "to"
            ? "Exclusive end of the range. \(dateFormatNote); a date-only value means the end of that day (it is included)."
            : "Inclusive start of the range. \(dateFormatNote); a date-only value means the start of that day."
        return ["type": "string", "minLength": 10, "description": .string(detail)]
    }

    static func limitProperty(default value: Int, maximum: Int) -> JSONValue {
        ["type": "integer", "minimum": 1, "maximum": .int(Int64(maximum)), "default": .int(Int64(value)),
         "description": .string("Maximum number of sessions to return (default \(value), at most \(maximum)).")]
    }

    static func describe(_ text: String) -> String { text + "\n\n" + conventions }

    static let definitions: [ToolDefinition] = [
        ToolDefinition(
            name: "list_sessions",
            title: "List sessions",
            description: describe("Lists tracked sessions (entries) that overlap a time range, oldest first. Each session has its whole duration_seconds and seconds_in_range, the part clipped to the range (sessions crossing midnight or the range edge are split, never double counted). Optional client filters by client_text (case-insensitive exact match)."),
            properties: [
                "from": dateProperty("from"),
                "to": dateProperty("to"),
                "client": ["type": "string", "description": "Only sessions whose client_text equals this label (case-insensitive)."],
                "limit": limitProperty(default: 200, maximum: 1000),
            ],
            required: ["from", "to"]
        ),
        ToolDefinition(
            name: "get_session",
            title: "Get session",
            description: describe("Returns one session by its id (UUID), or an error if it does not exist or was deleted."),
            properties: ["id": ["type": "string", "format": "uuid", "description": "Session id (UUID) as returned by other tools."]],
            required: ["id"]
        ),
        ToolDefinition(
            name: "search_sessions",
            title: "Search sessions",
            description: describe("Case-insensitive substring search over raw_text, client_text and note, newest first. When the server runs with --redact-notes only client_text is searched."),
            properties: [
                "query": ["type": "string", "minLength": 1, "description": "Text to look for."],
                "limit": limitProperty(default: 50, maximum: 500),
            ],
            required: ["query"]
        ),
        ToolDefinition(
            name: "aggregate",
            title: "Aggregate tracked time",
            description: describe("Deterministic totals over a range, computed by Grains. group_by: day (key yyyy-MM-dd, local), week (ISO week id such as 2026-W44, of the Grains week containing the time), client (key = client_text, or \"(no client)\"), client_day (key yyyy-MM-dd|client). Rows have key, client_text, seconds, hours (2 decimals) and entry_count; empty buckets are omitted. total_seconds/total_hours are the merged total for the whole range (equal to the weekly graph's total for a full week)."),
            properties: [
                "from": dateProperty("from"),
                "to": dateProperty("to"),
                "group_by": ["type": "string", "enum": ["day", "week", "client", "client_day"], "description": "Bucket kind."],
            ],
            required: ["from", "to", "group_by"]
        ),
        ToolDefinition(
            name: "list_client_labels",
            title: "List client labels",
            description: describe("Distinct client_text labels with entry counts and total hours, so you can spot typos and aliases and propose merges. Labels are grouped ignoring ASCII case and shown with their most recent spelling. Sessions with no client appear once with client_text null."),
            properties: [:],
            required: []
        ),
        ToolDefinition(
            name: "current_week",
            title: "Current week summary",
            description: describe("Summary of the Grains week containing now (the same numbers as the weekly graph): ISO week id, start/end, total tracked hours, fraction of the week elapsed (real length, 167-169 h across DST), and hours per local day. Optional target_hours adds the target and the on-pace hours at now."),
            properties: ["target_hours": ["type": "number", "minimum": 0, "maximum": 168, "description": "Weekly target in hours (for example 40)."]],
            required: []
        ),
        ToolDefinition(
            name: "running_session",
            title: "Running session",
            description: describe("The session currently running (stopped_at null) and its elapsed seconds as of now, or running: null when the timer is idle."),
            properties: [:],
            required: []
        ),
        ToolDefinition(
            name: "list_exports",
            title: "List CSV exports",
            description: describe("The CSV export folder and the weekly Grains-YYYY-Www.csv files present in it (name, week, size_bytes, modified). Listing only; files are not read."),
            properties: [:],
            required: []
        ),
        ToolDefinition(
            name: "export_week",
            title: "Export week as CSV",
            description: describe("Returns the CSV text (schema v1, the same bytes Grains writes to Grains-YYYY-Www.csv) for one Grains week, computed on the fly from the database. Nothing is written to disk. Use it to build timesheets or QuickBooks-ready exports."),
            properties: ["week": ["type": "string", "pattern": "^[0-9]{4}-W[0-9]{2}$", "description": "ISO week id, for example 2026-W44."]],
            required: ["week"]
        ),
    ]
}

/// Typed access to `tools/call` arguments. Wrong types and missing required values are
/// reported as tool errors (`isError: true`) so the model can correct itself (D41).
struct Arguments {
    var values: [String: JSONValue]
    var tool: String

    func string(_ key: String) throws -> String? {
        switch values[key] {
        case nil, .null?: return nil
        case .string(let s)?: return s
        default: throw ToolFailure("\(tool): \"\(key)\" must be a string.")
        }
    }

    func requiredString(_ key: String) throws -> String {
        guard let s = try string(key), !s.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ToolFailure("\(tool): missing required argument \"\(key)\".")
        }
        return s
    }

    func int(_ key: String, default value: Int, range: ClosedRange<Int>) throws -> Int {
        switch values[key] {
        case nil, .null?: return value
        case let v?:
            guard let i = v.intValue else { throw ToolFailure("\(tool): \"\(key)\" must be an integer.") }
            guard range.contains(i) else { throw ToolFailure("\(tool): \"\(key)\" must be between \(range.lowerBound) and \(range.upperBound).") }
            return i
        }
    }

    func double(_ key: String, range: ClosedRange<Double>) throws -> Double? {
        switch values[key] {
        case nil, .null?: return nil
        case let v?:
            guard let d = v.doubleValue else { throw ToolFailure("\(tool): \"\(key)\" must be a number.") }
            guard range.contains(d) else { throw ToolFailure("\(tool): \"\(key)\" must be between \(JSONValue.format(range.lowerBound)) and \(JSONValue.format(range.upperBound)).") }
            return d
        }
    }
}
