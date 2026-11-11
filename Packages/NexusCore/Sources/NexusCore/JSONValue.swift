import Foundation

/// A JSON value that keeps object keys in their order, and writes numbers the way JavaScript's JSON.stringify does, so a board tile the
/// iPad writes back is byte for byte what the laptop would write (a sync merge or a diff then shows only what really changed).
public indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case let (.bool(x), .bool(y)): return x == y
        case let (.number(x), .number(y)): return x == y
        case let (.string(x), .string(y)): return x == y
        case let (.array(x), .array(y)): return x == y
        case let (.object(x), .object(y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    // MARK: reading values

    public subscript(_ key: String) -> JSONValue? {
        if case .object(let o) = self { return o.first { $0.0 == key }?.1 }
        return nil
    }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var number: Double? { if case .number(let n) = self { return n }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var object: [(String, JSONValue)]? { if case .object(let o) = self { return o }; return nil }

    /// The object with `key` set (kept in place if it was there, else added at the end) or removed (nil).
    public func setting(_ key: String, _ value: JSONValue?) -> JSONValue {
        guard case .object(var o) = self else { return self }
        if let i = o.firstIndex(where: { $0.0 == key }) {
            if let value { o[i].1 = value } else { o.remove(at: i) }
        } else if let value { o.append((key, value)) }
        return .object(o)
    }

    // MARK: writing

    /// JSON.stringify(value) with no spaces.
    public var text: String {
        var out = ""
        write(&out)
        return out
    }

    func write(_ out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += JSONValue.format(n)
        case .string(let s): JSONValue.quote(s, &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() { if i > 0 { out += "," }; v.write(&out) }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, kv) in o.enumerated() { if i > 0 { out += "," }; JSONValue.quote(kv.0, &out); out += ":"; kv.1.write(&out) }
            out += "}"
        }
    }

    /// A number as JavaScript prints it (Number.prototype.toString): 100, 2.4, -0.5, 0.00001, 1e-7, 1e+21.
    public static func format(_ n: Double) -> String {
        guard n.isFinite else { return "null" }
        if n == 0 { return "0" }
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        // Swift's description is the shortest text that reads back the same, as JavaScript's is; only the layout differs
        var s = "\(abs(n))"
        var e = 0
        if let r = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            e = Int(s[s.index(after: r)...].replacingOccurrences(of: "+", with: "")) ?? 0
            s = String(s[..<r])
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        let ip = String(parts[0]), fp = parts.count > 1 ? String(parts[1]) : ""
        // value = 0.<digits> x 10^point
        var digits = Array(ip + fp)
        var point = ip.count + e
        while digits.first == "0" { digits.removeFirst(); point -= 1 }
        while digits.last == "0" { digits.removeLast() }
        if digits.isEmpty { return "0" }
        let k = digits.count
        let d = String(digits)
        var out: String
        if k <= point && point <= 21 {
            out = d + String(repeating: "0", count: point - k)
        } else if 0 < point && point <= 21 {
            out = String(digits[0..<point]) + "." + String(digits[point...])
        } else if -6 < point && point <= 0 {
            out = "0." + String(repeating: "0", count: -point) + d
        } else {
            let x = point - 1
            out = (k == 1 ? d : String(digits[0]) + "." + String(digits[1...])) + "e" + (x < 0 ? "-" : "+") + String(abs(x))
        }
        return n < 0 ? "-" + out : out
    }

    static func quote(_ s: String, _ out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }

    // MARK: parsing

    public struct ParseError: Error, CustomStringConvertible {
        public var description: String
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(Array(text.utf8))
        p.skip()
        let v = try p.value()
        p.skip()
        guard p.i == p.b.count else { throw ParseError(description: "extra text at \(p.i)") }
        return v
    }

    struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        mutating func skip() { while i < b.count, b[i] == 32 || b[i] == 10 || b[i] == 13 || b[i] == 9 { i += 1 } }
        func fail(_ m: String) -> ParseError { ParseError(description: "\(m) at \(i)") }

        mutating func value() throws -> JSONValue {
            guard i < b.count else { throw fail("unexpected end") }
            switch b[i] {
            case UInt8(ascii: "{"):
                i += 1; skip()
                var o: [(String, JSONValue)] = []
                if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return .object(o) }
                while true {
                    skip()
                    guard i < b.count, b[i] == UInt8(ascii: "\"") else { throw fail("expected a key") }
                    let k = try str()
                    skip()
                    guard i < b.count, b[i] == UInt8(ascii: ":") else { throw fail("expected :") }
                    i += 1; skip()
                    o.append((k, try value()))
                    skip()
                    guard i < b.count else { throw fail("unexpected end") }
                    if b[i] == UInt8(ascii: ",") { i += 1; continue }
                    if b[i] == UInt8(ascii: "}") { i += 1; return .object(o) }
                    throw fail("expected , or }")
                }
            case UInt8(ascii: "["):
                i += 1; skip()
                var a: [JSONValue] = []
                if i < b.count, b[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                while true {
                    skip()
                    a.append(try value())
                    skip()
                    guard i < b.count else { throw fail("unexpected end") }
                    if b[i] == UInt8(ascii: ",") { i += 1; continue }
                    if b[i] == UInt8(ascii: "]") { i += 1; return .array(a) }
                    throw fail("expected , or ]")
                }
            case UInt8(ascii: "\""): return .string(try str())
            case UInt8(ascii: "t"): try word("true"); return .bool(true)
            case UInt8(ascii: "f"): try word("false"); return .bool(false)
            case UInt8(ascii: "n"): try word("null"); return .null
            default: return .number(try num())
            }
        }

        static func numeric(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 || c == 101 || c == 69 }

        mutating func word(_ w: String) throws {
            let u = Array(w.utf8)
            guard i + u.count <= b.count, Array(b[i..<(i + u.count)]) == u else { throw fail("unexpected word") }
            i += u.count
        }

        mutating func num() throws -> Double {
            let start = i
            while i < b.count && Parser.numeric(b[i]) { i += 1 }
            guard i > start, let s = String(bytes: b[start..<i], encoding: .ascii), let d = Double(s) else { throw fail("bad number") }
            return d
        }

        mutating func str() throws -> String {
            i += 1 // the opening quote
            var bytes: [UInt8] = []
            while i < b.count {
                let c = b[i]
                if c == UInt8(ascii: "\"") { i += 1; return String(decoding: bytes, as: UTF8.self) }
                if c == UInt8(ascii: "\\") {
                    i += 1
                    guard i < b.count else { break }
                    let e = b[i]
                    switch e {
                    case UInt8(ascii: "n"): bytes.append(10)
                    case UInt8(ascii: "r"): bytes.append(13)
                    case UInt8(ascii: "t"): bytes.append(9)
                    case UInt8(ascii: "b"): bytes.append(8)
                    case UInt8(ascii: "f"): bytes.append(12)
                    case UInt8(ascii: "u"):
                        guard i + 4 < b.count, let s = String(bytes: b[(i + 1)...(i + 4)], encoding: .ascii), var code = UInt32(s, radix: 16) else { throw fail("bad \\u") }
                        i += 4
                        // a surrogate pair
                        if code >= 0xD800 && code < 0xDC00, i + 6 < b.count, b[i + 1] == UInt8(ascii: "\\"), b[i + 2] == UInt8(ascii: "u"),
                           let s2 = String(bytes: b[(i + 3)...(i + 6)], encoding: .ascii), let low = UInt32(s2, radix: 16), low >= 0xDC00 && low < 0xE000 {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            i += 6
                        }
                        bytes.append(contentsOf: Array(String(Character(Unicode.Scalar(code) ?? "?")).utf8))
                    default: bytes.append(e) // \" \\ \/
                    }
                    i += 1
                    continue
                }
                bytes.append(c)
                i += 1
            }
            throw fail("unclosed string")
        }
    }
}
