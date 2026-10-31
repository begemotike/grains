import Foundation

/// A JSON document as a value. Requests are decoded into it and every response is built from
/// it, so the wire format is fully under our control: object keys are always sorted, the
/// compact form never contains a newline (newline-delimited framing), and output is
/// byte-identical for identical input.
public enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // MARK: Accessors

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Integers, and doubles with no fractional part.
    public var intValue: Int? {
        switch self {
        case .int(let i): return Int(exactly: i)
        case .double(let d) where d.rounded() == d && abs(d) < 9e15: return Int(d)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        default: return nil
        }
    }

    public var isNull: Bool { self == .null }

    // MARK: Parsing

    /// Parses UTF-8 JSON text. Throws on malformed input.
    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    // MARK: Serialization

    /// Single-line JSON with sorted keys (the wire format).
    public func compactString() -> String {
        var out = ""
        write(into: &out, pretty: false, indent: 0)
        return out
    }

    /// Two-space indented JSON with sorted keys (tool `text` content).
    public func prettyString() -> String {
        var out = ""
        write(into: &out, pretty: true, indent: 0)
        return out
    }

    private func write(into out: inout String, pretty: Bool, indent: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += Self.format(d)
        case .string(let s): Self.writeString(s, into: &out)
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                if pretty { out += "\n" + String(repeating: "  ", count: indent + 1) }
                item.write(into: &out, pretty: pretty, indent: indent + 1)
            }
            if pretty { out += "\n" + String(repeating: "  ", count: indent) }
            out += "]"
        case .object(let object):
            guard !object.isEmpty else { out += "{}"; return }
            out += "{"
            for (index, key) in object.keys.sorted().enumerated() {
                if index > 0 { out += "," }
                if pretty { out += "\n" + String(repeating: "  ", count: indent + 1) }
                Self.writeString(key, into: &out)
                out += pretty ? ": " : ":"
                object[key]!.write(into: &out, pretty: pretty, indent: indent + 1)
            }
            if pretty { out += "\n" + String(repeating: "  ", count: indent) }
            out += "}"
        }
    }

    /// Integral values print without a fraction; non-finite values (never produced by Grains)
    /// become `null` because JSON cannot represent them.
    static func format(_ d: Double) -> String {
        guard d.isFinite else { return "null" }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return "\(d)"
    }

    private static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\u{2028}": out += "\\u2028"
            case "\u{2029}": out += "\\u2029"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}

extension JSONValue: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int64.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue {
    /// `.string` or `.null`.
    static func optional(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }
    /// `.double` or `.null`.
    static func optional(_ d: Double?) -> JSONValue { d.map(JSONValue.double) ?? .null }
}
