import Foundation
import Yams

// Applications keeps a school's details in its workstream.yaml (the laptop's store/apps.js): `applying`, `round`, `research: {...}`, `essays: [...]` and
// so on, beside `id`, `name` and `status`. Here: reading those details as JSONValue, and the one edit the laptop's container.js `setDetail` makes,
// set (or remove) one top-level key of a mapping file, done line by line so everything else in the file stays exactly as it was.

public enum YamlValue {
    /// A node as a JSONValue: mappings keep their order; a plain scalar is null, a bool or a number when it reads as one (YAML 1.2's core
    /// schema, as the laptop's reader), else text; quoted and block scalars are always text; a date stays its text ("2026-11-01").
    public static func of(_ n: Node?) -> JSONValue {
        guard let n else { return .null }
        if let m = n.mapping {
            var out: [(String, JSONValue)] = []
            for (k, v) in m { out.append((k.scalar?.string ?? "", of(v))) }
            return .object(out)
        }
        if let s = n.sequence { return .array(s.map { of($0) }) }
        if let s = n.scalar { return s.style == .plain || s.style == .any ? plain(s.string) : .string(s.string) }
        return .null
    }

    /// A plain scalar's value: null, true or false, a number, else the text.
    public static func plain(_ s: String) -> JSONValue {
        switch s {
        case "", "~", "null", "Null", "NULL": return .null
        case "true", "True", "TRUE": return .bool(true)
        case "false", "False", "FALSE": return .bool(false)
        default: break
        }
        if isNumber(s), let d = Double(s) { return .number(d) }
        return .string(s)
    }

    static func isNumber(_ s: String) -> Bool {
        s.range(of: #"^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$"#, options: .regularExpression) != nil
    }

    /// The file's top-level mapping (an empty object when the file is empty). Throws when it does not parse or is not a mapping.
    public static func document(_ text: String) throws -> JSONValue {
        let node: Node?
        do { node = try Yams.compose(yaml: text) } catch { throw DetailEdit.Failure.parse("\(error)".components(separatedBy: "\n").first ?? "does not parse") }
        guard let node else { return .object([]) }
        guard node.mapping != nil else { throw DetailEdit.Failure.parse("it is not a mapping of keys") }
        return of(node)
    }
}

/// Small readers for detail values, forgiving as the laptop's are (a number written as text still counts).
public extension JSONValue {
    /// A number, or a numeric text ("12", "7.5"), else nil.
    var num: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): let t = s.trimmingCharacters(in: .whitespaces); return YamlValue.isNumber(t) ? Double(t) : nil
        default: return nil
        }
    }
    /// Text for a scalar (a number prints as JavaScript would), nil for null, objects and arrays.
    var text1: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return JSONValue.format(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }
    /// The ISO day at the start of a text ("2026-11-01", "2026-11-01T…"), else nil.
    var iso: String? {
        guard let t = text1, t.count >= 10 else { return nil }
        let d = String(t.prefix(10))
        return Days.isIso(d) ? d : nil
    }
    var isNull: Bool { if case .null = self { return true }; return false }
}

/// One top-level key of a YAML mapping file, set or removed, line by line: the key's lines are replaced (or removed, or added before
/// `tasks:` / at the end) and every other line stays as it was. The result is parsed and compared with what was meant before it is
/// returned: the key holds the new value and every other key is unchanged, else nothing is written (`Failure`).
public enum DetailEdit {
    public enum Failure: Error, CustomStringConvertible, Equatable {
        case parse(String)
        case notBlock
        case wouldBreak(String)
        case reserved(String)
        public var description: String {
            switch self {
            case .parse(let why): return "The file does not parse (\(why)), so it was left as it is"
            case .notBlock: return "The file is written in one line ({…}), so Nexus left it as it is"
            case .wouldBreak(let why): return "That edit would break the file (\(why)), so it was not saved"
            case .reserved(let k): return "\"\(k)\" cannot be set this way"
            }
        }
    }

    /// `values` in order; nil removes a key.
    public static func set(_ text: String, _ values: [(String, JSONValue?)]) throws -> String {
        try values.reduce(text) { try set($0, key: $1.0, $1.1) }
    }

    public static func set(_ text: String, key: String, _ value: JSONValue?) throws -> String {
        if key == "id" || key == "tasks" { throw Failure.reserved(key) }
        let before = try YamlValue.document(text)
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if let first = lines.first(where: { let t = $0.trimmingCharacters(in: .whitespaces); return !t.isEmpty && !t.hasPrefix("#") && t != "---" }),
           first.hasPrefix("{") { throw Failure.notBlock }
        // drop a null value: a key with nothing in it is the same as no key
        let value: JSONValue? = (value == nil || value == .null) ? nil : value
        let new = value.map { emit(key, $0, indent: 0) } ?? []
        if let i = lines.firstIndex(where: { keyOf($0) == key }) {
            var j = i + 1
            while j < lines.count && belongs(lines[j]) { j += 1 }
            while j > i + 1 && lines[j - 1].trimmingCharacters(in: .whitespaces).isEmpty { j -= 1 }
            lines.replaceSubrange(i..<j, with: new)
        } else if !new.isEmpty {
            if let t = lines.firstIndex(where: { keyOf($0) == "tasks" }) { lines.insert(contentsOf: new, at: t) } else { lines.append(contentsOf: new) }
        } else {
            return text
        }
        let out = lines.joined(separator: "\n") + "\n"
        // the check: the key holds what was meant, every other key is as it was
        let after: JSONValue
        do { after = try YamlValue.document(out) } catch { throw Failure.wouldBreak("\(error)") }
        guard (after[key] ?? .null) == (value ?? .null) || same(after[key], value) else { throw Failure.wouldBreak("\(key) did not read back as written") }
        guard (before.setting(key, nil)) == (after.setting(key, nil)) else { throw Failure.wouldBreak("another key changed") }
        return out
    }

    /// Numbers compare by value (12 and 12.0), the rest exactly.
    static func same(_ a: JSONValue?, _ b: JSONValue?) -> Bool {
        switch (a ?? .null, b ?? .null) {
        case let (.number(x), .number(y)): return abs(x - y) < 1e-9
        case let (.array(x), .array(y)): return x.count == y.count && zip(x, y).allSatisfy { same($0, $1) }
        case let (.object(x), .object(y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && same($0.1, $1.1) }
        case let (x, y): return x == y
        }
    }

    /// The key of a top-level `key: …` line, else nil (indented lines, comments, list items, document markers).
    static func keyOf(_ line: String) -> String? {
        guard let c = line.first, c != " ", c != "\t", c != "#", c != "-", !line.hasPrefix("...") else { return nil }
        var inQuote: Character? = nil
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if let q = inQuote { if ch == q { inQuote = nil } }
            else if ch == "\"" || ch == "'" { if idx == line.startIndex { inQuote = ch } }
            else if ch == ":" {
                let next = line.index(after: idx)
                if next == line.endIndex || line[next] == " " || line[next] == "\t" {
                    var k = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                    if k.count >= 2, let f = k.first, f == "\"" || f == "'", k.last == f { k = String(k.dropFirst().dropLast()) }
                    return k
                }
            }
            idx = line.index(after: idx)
        }
        return nil
    }

    /// A line under a top-level key: indented, blank, or a list item at the left edge (`- x` under `key:` is legal YAML).
    static func belongs(_ line: String) -> Bool {
        guard let c = line.first else { return true }
        return c == " " || c == "\t" || c == "-" && !line.hasPrefix("---")
    }

    // MARK: writing YAML (block style, as the laptop's writer does)

    /// `key: value` as lines at `indent`.
    public static func emit(_ key: String, _ v: JSONValue, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        let k = keyText(key)
        switch v {
        case .object(let o) where o.isEmpty: return [pad + k + ": {}"]
        case .array(let a) where a.isEmpty: return [pad + k + ": []"]
        case .object(let o): return [pad + k + ":"] + o.flatMap { emit($0.0, $0.1, indent: indent + 2) }
        case .array(let a): return [pad + k + ":"] + a.flatMap { item($0, indent: indent + 2) }
        default: return [pad + k + ": " + scalar(v)]
        }
    }

    /// One list item at `indent`: `- value`, or a mapping whose first key sits on the dash's line.
    static func item(_ v: JSONValue, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        switch v {
        case .object(let o) where !o.isEmpty:
            var out: [String] = []
            for (i, kv) in o.enumerated() {
                var ls = emit(kv.0, kv.1, indent: indent + 2)
                if i == 0 { ls[0] = pad + "- " + String(ls[0].dropFirst(indent + 2)) }
                out += ls
            }
            return out
        case .object: return [pad + "- {}"]
        case .array(let a) where a.isEmpty: return [pad + "- []"]
        case .array: return [pad + "- " + v.text]
        default: return [pad + "- " + scalar(v)]
        }
    }

    static func keyText(_ k: String) -> String {
        k.range(of: #"^[A-Za-z0-9_][A-Za-z0-9_ .-]*$"#, options: .regularExpression) != nil && !k.hasSuffix(" ") ? k : JSONValue.string(k).text
    }

    /// A scalar as YAML: plain when it reads back as the same text, else in double quotes (JSON's escapes are YAML's).
    public static func scalar(_ v: JSONValue) -> String {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return JSONValue.format(n)
        case .string(let s): return plainSafe(s) ? s : v.text
        default: return v.text
        }
    }

    static func plainSafe(_ s: String) -> Bool {
        guard let f = s.first, s == s.trimmingCharacters(in: .whitespaces) else { return false }
        if s.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) { return false }
        if "-?:,[]{}#&*!|>'\"%@`".contains(f) { return false }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return false }
        if ["true", "false", "null", "~", "yes", "no", "on", "off", "y", "n"].contains(s.lowercased()) { return false }
        if YamlValue.isNumber(s) || s.hasPrefix("0x") || s.hasPrefix("0o") || s.lowercased().hasPrefix(".inf") || s.lowercased() == ".nan" { return false }
        return true
    }
}
