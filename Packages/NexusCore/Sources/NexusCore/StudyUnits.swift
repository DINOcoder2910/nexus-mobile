import Foundation
import Yams

/// The rest of a workstream's study/ folder the laptop's renderer/src/studydeck.js reads: study/study.yaml (where the sheets are, the
/// language), study/units.yaml (the syllabus units, each linked to its sheets) and a deck's Practice classifying (its `practice:` list,
/// unscheduled: nothing is written and FSRS is untouched). Pure.
public enum StudyUnits {
    // MARK: study/study.yaml

    public struct Config: Equatable, Sendable {
        /// The practice sheets folder, inside the workstream (default files).
        public var sheets = "files"
        /// "spanish" turns on the Spanish tools.
        public var language = ""
        public init(sheets: String = "files", language: String = "") { self.sheets = sheets; self.language = language }
    }

    public static func parseConfig(_ text: String?) -> Config {
        guard let o = YamlJS.parse(text ?? ""), case .object = o else { return Config() }
        var c = Config()
        if let s = o["sheets"]?.string, !s.trimmed.isEmpty, !RX.test(#"(^|/)\.\.(/|$)"#, s) { c.sheets = RX.replace("^/+|/+$", s.trimmed, "") }
        if let l = o["language"]?.string { c.language = l.trimmed.lowercased() }
        return c
    }

    // MARK: study/units.yaml

    public struct Unit: Equatable, Sendable, Identifiable {
        public var code: String
        public var title: String
        /// done | partial | not-yet
        public var status: String
        public var evidence: String
        public var notes: String
        /// Extra sheets (paths in the sheets folder, or titles).
        public var sheets: [String]
        public var id: String { code + "|" + title }
    }
    public struct Theme: Equatable, Sendable, Identifiable {
        public var code: String
        public var title: String
        public var units: [Unit]
        public var id: String { code }
        /// "Reactivity 1" and "What drives chemical reactions?" from "Reactivity 1 · What drives chemical reactions?".
        public var name: (main: String, sub: String?) {
            let p = title.components(separatedBy: " · ")
            return (p[0], p.count > 1 ? p[1...].joined(separator: " · ") : nil)
        }
    }

    public static let statuses: [(id: String, label: String)] = [("done", "Done"), ("partial", "Partly done"), ("not-yet", "Not yet")]
    public static func statusLabel(_ s: String) -> String { statuses.first { $0.id == s }?.label ?? "Not yet" }

    /// The IB Chemistry 2025 themes and the Spanish ab initio grades, for the unit list's headers.
    public static let themes: [String: String] = [
        "S1": "Structure 1 · Models of the particulate nature of matter", "S2": "Structure 2 · Models of bonding and structure",
        "S3": "Structure 3 · Classification of matter", "R1": "Reactivity 1 · What drives chemical reactions?",
        "R2": "Reactivity 2 · How much, how fast and how far?", "R3": "Reactivity 3 · What are the mechanisms of chemical change?",
        "G11": "Grade 11 · Ms. Barton", "G12": "Grade 12 · Ms. Panhausen (Miss Kathleen, Miss K)",
    ]

    public enum Units: Equatable, Sendable {
        case ok([Unit])
        case failed(String)
    }

    public static func parseUnits(_ text: String) -> Units {
        let o: JSONValue?
        do { o = try YamlJS.parseThrowing(text) } catch { return .failed("study/units.yaml does not parse: " + TaskFile.yamlMessage(error).components(separatedBy: "\n")[0]) }
        let list: [JSONValue]
        if let a = o?.array { list = a } else if let a = o?["units"]?.array { list = a } else { return .failed("study/units.yaml has no units: list.") }
        let units = list.filter { u in
            guard case .object = u else { return false }
            return YamlJS.truthy(u["code"]) || YamlJS.truthy(u["title"])
        }.map { u -> Unit in
            let st = YamlJS.truthy(u["status"]) ? YamlJS.string(u["status"]) : ""
            return Unit(code: YamlJS.truthy(u["code"]) ? YamlJS.string(u["code"]).trimmed : "",
                        title: YamlJS.truthy(u["title"]) ? YamlJS.string(u["title"]).trimmed : "",
                        status: statuses.contains { $0.id == st } && u["status"]?.string != nil ? st : "not-yet",
                        evidence: YamlJS.truthy(u["evidence"]) ? YamlJS.string(u["evidence"]) : "",
                        notes: YamlJS.truthy(u["notes"]) ? YamlJS.string(u["notes"]).trimmed : "",
                        sheets: u["sheets"]?.array?.map { YamlJS.string($0) } ?? [])
        }
        return .ok(units)
    }

    /// Units grouped under their theme (the code before the first dot).
    public static func themesOf(_ units: [Unit]) -> [Theme] {
        var out: [Theme] = []
        for u in units {
            let t = u.code.isEmpty ? "" : u.code.components(separatedBy: ".")[0]
            if let i = out.firstIndex(where: { $0.code == t }) { out[i].units.append(u) }
            else { out.append(Theme(code: t, title: themes[t] ?? (t.isEmpty ? "Other" : t), units: [u])) }
        }
        return out
    }

    // MARK: Practice classifying

    public static let levels: [(id: String, label: String, has: [String])] = [
        ("all", "Everything", ["required", "common", "extra"]), ("common", "Required and common", ["required", "common"]), ("required", "Required only", ["required"]),
    ]

    /// The answers to choose from: the option list the deck's cards share most (strong acid / weak acid / strong base / weak base), with
    /// every practice answer in it; else the practice answers themselves, in the order they first appear.
    public static func practiceOptions(_ deck: StudyDeck) -> [String] {
        var answers = OrderedSet()
        for p in deck.practice { answers.add(p.answer) }
        var lists: [(key: [String], n: Int)] = []
        for c in deck.cards { if let o = c.options { if let i = lists.firstIndex(where: { $0.key == o }) { lists[i].n += 1 } else { lists.append((o, 1)) } } }
        let best = StudySheets.stableSorted(lists) { $0.n > $1.n }.map(\.key).first { l in
            answers.items.allSatisfy { a in l.contains { StudyDeck.check($0, a) == .right } }
        }
        return best ?? answers.items
    }

    /// The items of a round: those of the chosen level (or the given ids), shuffled by `seed`.
    public static func practiceRound(_ deck: StudyDeck, level: String = "all", ids: [String]? = nil, seed: String = "") -> [String] {
        let lv = (levels.first { $0.id == level } ?? levels[0]).has
        let list = deck.practice.filter { ids.map { ids in ids.contains($0.id) } ?? lv.contains($0.level) }
        return StudyDeck.shuffle(list.map(\.id), StudyDeck.rng("practice|" + seed))
    }

    public static func ruleOf(_ deck: StudyDeck, _ item: StudyDeck.PracticeItem) -> StudyDeck.Card? { deck.cards.first { $0.id == item.rule } }

    /// A typed answer: the whole option ("weak base") or its initials ("wb"); "weak" alone is not enough.
    public static func practiceCheck(_ typed: String, _ item: StudyDeck.PracticeItem) -> StudyDeck.Verdict {
        let t = typed.trimmed
        if t.isEmpty { return .empty }
        if StudyDeck.check(t, item.answer) == .right { return .right }
        let ini = item.answer.lowercased().components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }.map { String($0.prefix(1)) }.joined()
        return ini.count > 1 && RX.replace(#"[\s.]"#, t.lowercased(), "") == ini ? .right : .wrong
    }
}

/// YAML read as the laptop's `yaml` package reads it (the core schema): plain true / false, null / ~, integers and floats are those;
/// everything else (dates included) is a string. As JSONValue, maps keep their order.
enum YamlJS {
    static func parseThrowing(_ text: String) throws -> JSONValue? {
        guard let n = try Yams.compose(yaml: text) else { return nil }
        return value(n)
    }
    static func parse(_ text: String) -> JSONValue? { (try? parseThrowing(text)) ?? nil }

    static func value(_ n: Node) -> JSONValue {
        switch n {
        case .scalar(let s): return scalar(s)
        case .sequence(let seq): return .array(seq.map(value))
        case .mapping(let m):
            var out: [(String, JSONValue)] = []
            for (k, v) in m {
                let key = string(value(k))
                if let i = out.firstIndex(where: { $0.0 == key }) { out[i].1 = value(v) } else { out.append((key, value(v))) }
            }
            return .object(out)
        default: return .null
        }
    }

    static func scalar(_ s: Node.Scalar) -> JSONValue { s.style == .plain ? plain(s.string) : .string(s.string) }

    /// A plain (unquoted) scalar's value.
    static func plain(_ t: String) -> JSONValue {
        if ["", "~", "null", "Null", "NULL"].contains(t) { return .null }
        if ["true", "True", "TRUE"].contains(t) { return .bool(true) }
        if ["false", "False", "FALSE"].contains(t) { return .bool(false) }
        if RX.test("^[-+]?[0-9]+$", t), let d = Double(t) { return .number(d) }
        if RX.test("^0o[0-7]+$", t), let i = Int(t.dropFirst(2), radix: 8) { return .number(Double(i)) }
        if RX.test("^0x[0-9a-fA-F]+$", t), let i = Int(t.dropFirst(2), radix: 16) { return .number(Double(i)) }
        if RX.test(#"^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$"#, t), let d = Double(t) { return .number(d) }
        if RX.test(#"^[-+]?\.(inf|Inf|INF)$"#, t) { return .number(t.hasPrefix("-") ? -.infinity : .infinity) }
        if RX.test(#"^\.(nan|NaN|NAN)$"#, t) { return .number(.nan) }
        return .string(t)
    }

    /// JavaScript's truthiness.
    static func truthy(_ v: JSONValue?) -> Bool {
        switch v {
        case nil, .null?: return false
        case .bool(let b)?: return b
        case .number(let n)?: return n != 0 && !n.isNaN
        case .string(let s)?: return !s.isEmpty
        default: return true
        }
    }

    /// JavaScript's String(v) (undefined -> "undefined" is never wanted here: nil gives "").
    static func string(_ v: JSONValue?) -> String {
        switch v {
        case nil: return ""
        case .null?: return "null"
        case .bool(let b)?: return b ? "true" : "false"
        case .number(let n)?: return numberText(n)
        case .string(let s)?: return s
        case .array(let a)?: return a.map { x -> String in if case .null = x { return "" }; return string(x) }.joined(separator: ",")
        case .object?: return "[object Object]"
        }
    }

    static func numberText(_ n: Double) -> String {
        if n.isNaN { return "NaN" }
        if n.isInfinite { return n < 0 ? "-Infinity" : "Infinity" }
        if n == n.rounded(), abs(n) < 1e21 { return String(format: "%.0f", n) }
        return "\(n)"
    }
}
