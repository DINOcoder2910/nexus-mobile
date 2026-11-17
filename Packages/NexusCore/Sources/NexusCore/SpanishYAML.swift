import Foundation
import Yams

/// The small YAML kit the Spanish files use on the iPhone and iPad: a value tree written in block style (as the laptop's
/// `YAML.stringify` writes the log, the numbers, the prompts and a chat's front matter), and reading a file into the same tree with
/// Yams. Strings stay strings (a time like 2026-11-09T10:00:00 is never read as a date), as the laptop's YAML 1.2 reader keeps them.
public indirect enum YValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case list([YValue])
    case map([YPair])

    public struct YPair: Equatable, Sendable {
        public var key: String
        public var value: YValue
        public init(_ key: String, _ value: YValue) { self.key = key; self.value = value }
    }

    // MARK: reading

    public subscript(_ key: String) -> YValue? {
        if case .map(let m) = self { return m.first { $0.key == key }?.value }
        return nil
    }
    /// A scalar as JavaScript's String(v) gives it; "" for none, null, a list or a map.
    public var str: String {
        switch self {
        case .string(let s): return s
        case .int(let n): return String(n)
        case .double(let d): return JSONValue.format(d)
        case .bool(let b): return b ? "true" : "false"
        default: return ""
        }
    }
    public var list: [YValue]? { if case .list(let l) = self { return l }; return nil }
    public var map: [YPair]? { if case .map(let m) = self { return m }; return nil }
    public var number: Double? {
        switch self {
        case .int(let n): return Double(n)
        case .double(let d): return d
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
    public var isNull: Bool { if case .null = self { return true }; return false }
    /// A list of strings (each item's str), or [] when it is not a list.
    public var strings: [String] { (list ?? []).map(\.str) }

    /// Parses YAML text (nil text, or an empty file, is null). Throws a message in words when it does not parse.
    public static func parse(_ text: String) throws -> YValue {
        let node: Node?
        do { node = try Yams.compose(yaml: text) } catch { throw SpanishYAML.Failure(message: TaskFile.yamlMessage(error)) }
        return node.map(from) ?? .null
    }

    static func from(_ n: Node) -> YValue {
        switch n {
        case .scalar(let s):
            if s.style == .plain {
                switch s.string {
                case "~", "null", "Null", "NULL", "": return .null
                case "true", "True", "TRUE": return .bool(true)
                case "false", "False", "FALSE": return .bool(false)
                default:
                    if s.string.range(of: #"^[-+]?\d+$"#, options: .regularExpression) != nil, let i = Int(s.string) { return .int(i) }
                    if s.string.range(of: #"^[-+]?(\d+\.\d*|\.\d+|\d+)([eE][-+]?\d+)?$"#, options: .regularExpression) != nil, let d = Double(s.string) { return .double(d) }
                }
            }
            return .string(s.string)
        case .sequence(let q): return .list(q.map(from))
        case .mapping(let m): return .map(m.map { YPair($0.key.scalar?.string ?? "", from($0.value)) })
        case .alias: return .null
        }
    }

    // MARK: writing

    /// The value as a block-style YAML document (a map at the top), ending in a newline.
    public var yaml: String {
        var lines: [String] = []
        SpanishYAML.emit(self, indent: 0, into: &lines)
        return lines.joined(separator: "\n") + "\n"
    }
}

public enum SpanishYAML {
    public struct Failure: Error, CustomStringConvertible { public var message: String; public var description: String { message } }

    /// A string as a YAML scalar: plain when it reads back as the same string, else double-quoted.
    public static func scalar(_ s: String) -> String {
        if plainOK(s) { return s }
        // as the laptop's writer: single quotes for words with a double quote in them (and no single quote or line break)
        if s.contains("\""), !s.contains("'"), !s.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) { return "'" + s + "'" }
        return quoted(s)
    }

    static func plainOK(_ s: String) -> Bool {
        guard let first = s.first, let last = s.last else { return false }
        if first == " " || last == " " || last == ":" { return false }
        if "-?:,[]{}#&*!|>'\"%@`".contains(first) {
            // "- x" and "? x" and ": x" are marks; "-x" is a plain word (but not "-" alone or "-1")
            if !(first == "-" && s.count > 1 && !s.dropFirst().first!.isWhitespace && Double(s) == nil) { return false }
        }
        if s.contains(": ") || s.contains(" #") || s.contains("\n") || s.contains("\t") || s.contains("\r") { return false }
        if ["~", "null", "Null", "NULL", "true", "True", "TRUE", "false", "False", "FALSE", "yes", "Yes", "YES", "no", "No", "NO", "on", "On", "ON", "off", "Off", "OFF", "y", "Y", "n", "N"].contains(s) { return false }
        if s.range(of: #"^[-+]?(\d[\d_]*(\.\d*)?|\.\d+)([eE][-+]?\d+)?$"#, options: .regularExpression) != nil { return false }
        if s.range(of: #"^0[xo][0-9a-fA-F]+$"#, options: .regularExpression) != nil { return false }
        if s.range(of: #"^[-+]?\.(inf|Inf|INF|nan|NaN|NAN)$"#, options: .regularExpression) != nil { return false }
        // sexagesimal numbers (1:20) are numbers to YAML 1.1 readers
        if s.range(of: #"^[-+]?\d+(:[0-5]?\d)+(\.\d*)?$"#, options: .regularExpression) != nil { return false }
        for u in s.unicodeScalars where u.value < 0x20 || u.value == 0x7F || (u.value >= 0x80 && u.value < 0xA0) || u.value == 0xFEFF || u.value == 0x2028 || u.value == 0x2029 { return false }
        return true
    }

    public static func quoted(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if u.value < 0x20 || u.value == 0x7F || u.value == 0xFEFF || u.value == 0x2028 || u.value == 0x2029 || (u.value >= 0x80 && u.value < 0xA0) {
                    out += String(format: "\\u%04X", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }

    static func inline(_ v: YValue) -> String? {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let n): return String(n)
        case .double(let d): return JSONValue.format(d)
        case .string(let s): return scalar(s)
        case .list(let l): return l.isEmpty ? "[]" : nil
        case .map(let m): return m.isEmpty ? "{}" : nil
        }
    }

    static func emit(_ v: YValue, indent: Int, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        switch v {
        case .map(let m):
            for p in m {
                let k = scalar(p.key)
                if let s = inline(p.value) { lines.append(pad + k + ": " + s); continue }
                lines.append(pad + k + ":")
                if case .list = p.value { emit(p.value, indent: indent + 2, into: &lines) } else { emit(p.value, indent: indent + 2, into: &lines) }
            }
        case .list(let l):
            for item in l {
                if let s = inline(item) { lines.append(pad + "- " + s); continue }
                var sub: [String] = []
                emit(item, indent: indent + 2, into: &sub)
                guard let first = sub.first else { continue }
                lines.append(pad + "- " + String(first.dropFirst(indent + 2)))
                lines.append(contentsOf: sub.dropFirst())
            }
        default:
            if let s = inline(v) { lines.append(pad + s) }
        }
    }
}

/// A few things the Spanish files share: regular expressions as JavaScript writes them (cached), and JavaScript's string pieces.
enum JS {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func re(_ p: String, _ ci: Bool = false) -> NSRegularExpression {
        let key = (ci ? "i:" : "-:") + p
        lock.lock(); defer { lock.unlock() }
        if let r = cache[key] { return r }
        let r = try! NSRegularExpression(pattern: p, options: ci ? [.caseInsensitive] : [])
        cache[key] = r
        return r
    }
    static func test(_ p: String, _ s: String, ci: Bool = false) -> Bool {
        re(p, ci).firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
    /// The capture groups of the first match ([0] is the whole match; a group that did not take part is "").
    static func match(_ p: String, _ s: String, ci: Bool = false) -> [String]? {
        let ns = s as NSString
        guard let m = re(p, ci).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in let r = m.range(at: i); return r.location == NSNotFound ? "" : ns.substring(with: r) }
    }
    /// Every match: its text and where it starts (UTF-16, as JavaScript's index).
    static func all(_ p: String, _ s: String, ci: Bool = false) -> [(text: String, at: Int)] {
        let ns = s as NSString
        return re(p, ci).matches(in: s, range: NSRange(location: 0, length: ns.length)).map { (text: ns.substring(with: $0.range), at: $0.range.location) }
    }
    static func replace(_ p: String, _ s: String, _ with: String, ci: Bool = false) -> String {
        re(p, ci).stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: with)
    }
    /// JavaScript's split with a regular expression (no captures).
    static func split(_ p: String, _ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = [], at = 0
        for m in re(p).matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if m.range.length == 0 { continue }
            out.append(ns.substring(with: NSRange(location: at, length: m.range.location - at)))
            at = NSMaxRange(m.range)
        }
        out.append(ns.substring(from: at))
        return out
    }
    /// s.slice(a, b) in UTF-16 units.
    static func slice(_ s: String, _ a: Int, _ b: Int? = nil) -> String {
        let ns = s as NSString
        let lo = max(0, min(a, ns.length)), hi = max(lo, min(b ?? ns.length, ns.length))
        return ns.substring(with: NSRange(location: lo, length: hi - lo))
    }
    static func len(_ s: String) -> Int { (s as NSString).length }
    /// s.indexOf(needle, from) in UTF-16 units, -1 when not there.
    static func indexOf(_ s: String, _ needle: String, from: Int = 0) -> Int {
        let ns = s as NSString
        guard from <= ns.length, !needle.isEmpty else { return needle.isEmpty ? min(from, ns.length) : -1 }
        let r = ns.range(of: needle, options: [.literal], range: NSRange(location: from, length: ns.length - from))
        return r.location == NSNotFound ? -1 : r.location
    }
    /// The letters without their accents (NFD, the combining marks taken off, NFC), as the laptop's strip().
    static func strip(_ s: String) -> String {
        let d = s.decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        for u in d.unicodeScalars where !(0x300...0x36F).contains(u.value) { out.append(u) }
        return String(out).precomposedStringWithCanonicalMapping
    }
    /// A local "YYYY-MM-DDTHH:MM:SS(.sss)" as JavaScript's Date.parse reads it (local time), in milliseconds; nil when it is not one.
    static func parseLocal(_ s: String) -> Double? {
        guard let m = match(#"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?)?"#, s) else { return nil }
        var c = DateComponents()
        c.year = Int(m[1]); c.month = Int(m[2]); c.day = Int(m[3])
        c.hour = Int(m[4]) ?? 0; c.minute = Int(m[5]) ?? 0; c.second = Int(m[6]) ?? 0
        let ms = m[7].isEmpty ? 0 : Double(m[7].padding(toLength: 3, withPad: "0", startingAt: 0)) ?? 0
        // a date alone is UTC to JavaScript; a date with a time is local
        var cal = Calendar(identifier: .gregorian)
        if m[4].isEmpty { cal.timeZone = TimeZone(identifier: "UTC")! } else { cal.timeZone = .current }
        guard let d = cal.date(from: c) else { return nil }
        return d.timeIntervalSince1970 * 1000 + ms
    }
    /// Math.round for the positive numbers used here (half up).
    static func round(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
}

extension String {
    /// JavaScript's trimEnd(): white space and line ends at the end only.
    var trimEnd: String {
        var s = Substring(self)
        while let c = s.last, c.isWhitespace || c.isNewline { s.removeLast() }
        return String(s)
    }
}
