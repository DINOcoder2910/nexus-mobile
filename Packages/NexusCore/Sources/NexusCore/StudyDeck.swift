import Foundation
import Yams

/// A memorize deck (`<workstream>/study/decks/<id>.yaml`, nexus docs/data-format.md "Study"), read as the laptop's
/// renderer/src/studydeck.js reads it: its cards, the sides each way, typed-answer checking (SO4 2-, SO4^2- and SO₄²⁻ all count) and
/// the multiple-choice options. Pure: no disk, no clock. The decks are the user's files and the iPhone and iPad only read them.
public struct StudyDeck: Equatable, Sendable {
    public var id: String
    public var title: String
    public var description: String
    /// Each card can also be asked back to front, with its own schedule.
    public var reversible: Bool
    /// A Spanish deck: one schedule per card, either side shown first, graded by yourself.
    public var flip: Bool
    public var language: String
    public var kind: String
    public var unit: String
    public var columns: [Column]
    public var groups: [Group]
    public var sources: [Source]
    public var cards: [Card]

    public struct Column: Equatable, Sendable { public var key: String; public var label: String }
    public struct Group: Equatable, Sendable { public var id: String; public var title: String }
    public struct Source: Equatable, Sendable { public var title: String; public var url: String }

    public struct Card: Equatable, Sendable, Identifiable {
        public var id: String
        public var group: String
        /// required, common or extra.
        public var level: String
        public var fields: [String: String]
        public var front: String
        public var back: String
        public var accept: [String]
        public var acceptReverse: [String]
        /// The card's own multiple-choice options (two or more), or nil.
        public var options: [String]?
        public var note: String
        /// A rule card's members (shown under it, never asked).
        public var covers: [String]
        public var tags: [String]
        public var example: String
        public var added: String

        public init(id: String, group: String = "", level: String = "required", fields: [String: String] = [:], front: String, back: String,
                    accept: [String] = [], acceptReverse: [String] = [], options: [String]? = nil, note: String = "", covers: [String] = [],
                    tags: [String] = [], example: String = "", added: String = "") {
            self.id = id; self.group = group; self.level = level; self.fields = fields; self.front = front; self.back = back
            self.accept = accept; self.acceptReverse = acceptReverse; self.options = options; self.note = note; self.covers = covers
            self.tags = tags; self.example = example; self.added = added
        }
    }

    public enum Direction: String, CaseIterable, Sendable { case forward, reverse }

    public struct Parsed: Sendable {
        public var deck: StudyDeck?
        /// Why the deck could not be read ("does not parse: …", "has no cards: list").
        public var error: String?
        /// Cards left out: "card 3 (sulfate) repeats an id".
        public var problems: [String]
    }

    // MARK: reading a deck

    public static func parse(_ text: String, fileId: String = "") -> Parsed {
        let root: Node?
        do { root = try Yams.compose(yaml: text) } catch { return Parsed(deck: nil, error: "does not parse: " + TaskFile.yamlMessage(error), problems: []) }
        guard let m = root?.mapping, let cardsNode = val(m, "cards"), let list = cardsNode.sequence else {
            return Parsed(deck: nil, error: "has no cards: list", problems: [])
        }
        var seen = Set<String>(), cards: [Card] = [], problems: [String] = [], fieldKeysInOrder: [String] = []
        for (i, n) in list.enumerated() {
            guard let c = n.mapping else { continue }
            let cid = str(val(c, "id")).trimmed
            let front = str(val(c, "front")).trimmed, back = str(val(c, "back")).trimmed
            if cid.isEmpty || seen.contains(cid) || front.isEmpty || back.isEmpty {
                let why = cid.isEmpty ? "has no id" : seen.contains(cid) ? "repeats an id" : "has no front or back"
                problems.append("card \(i + 1)\(cid.isEmpty ? "" : " (\(cid))") \(why)")
                continue
            }
            seen.insert(cid)
            var fields: [String: String] = [:], fieldOrder: [String] = []
            if let fm = val(c, "fields")?.mapping {
                for (k, v) in fm { let key = str(k); if fields[key] == nil { fieldOrder.append(key) }; fields[key] = str(v) }
            }
            let level = str(val(c, "level"))
            let opts = strList(val(c, "options"))
            cards.append(Card(
                id: cid, group: str(val(c, "group")), level: ["required", "common", "extra"].contains(level) ? level : "required",
                fields: fields, front: front, back: back, accept: strList(val(c, "accept")) ?? [], acceptReverse: strList(val(c, "accept_reverse")) ?? [],
                options: (opts?.count ?? 0) >= 2 ? opts : nil, note: str(val(c, "note")).trimmed,
                covers: (strList(val(c, "covers")) ?? []).filter { !$0.isEmpty },
                tags: (strList(val(c, "tags")) ?? []).map(\.trimmed).filter { !$0.isEmpty },
                example: str(val(c, "example")).trimmed, added: str(val(c, "added")).trimmed))
            fieldKeysInOrder.append(contentsOf: fieldOrder)
        }
        let fieldKeys = unique(fieldKeysInOrder)
        let id = str(val(m, "id")).trimmed.isEmpty ? fileId : str(val(m, "id")).trimmed
        var columns: [Column] = []
        if let cs = val(m, "columns")?.sequence, !cs.isEmpty {
            columns = cs.compactMap { $0.mapping }.filter { !str(val($0, "key")).isEmpty }.map { x -> Column in
                let key = str(val(x, "key")); let label = str(val(x, "label")); return Column(key: key, label: label.isEmpty ? key : label)
            }
        } else if !fieldKeys.isEmpty {
            columns = fieldKeys.map { Column(key: $0, label: $0.prefix(1).uppercased() + $0.dropFirst()) }
        } else {
            columns = [Column(key: "$front", label: "Prompt"), Column(key: "$back", label: "Answer")]
        }
        let groups = (val(m, "groups")?.sequence ?? []).compactMap { $0.mapping }.filter { !str(val($0, "id")).isEmpty }.map { g in
            Group(id: str(val(g, "id")), title: str(val(g, "title")).isEmpty ? str(val(g, "id")) : str(val(g, "title")))
        }
        let sources: [Source] = (val(m, "sources")?.sequence ?? []).compactMap { s -> Source? in
            if let sm = s.mapping {
                let t = str(val(sm, "title")), u = str(val(sm, "url"))
                return Source(title: t.isEmpty ? u : t, url: u)
            }
            let t = str(s); return t.isEmpty ? nil : Source(title: t, url: "")
        }
        let flip = isTrue(val(m, "flip"))
        let title = str(val(m, "title")).trimmed
        let deck = StudyDeck(id: id, title: title.isEmpty ? id : title, description: str(val(m, "description")).trimmed,
                             reversible: isTrue(val(m, "reversible")) && !flip, flip: flip, language: str(val(m, "language")).trimmed,
                             kind: str(val(m, "kind")).trimmed, unit: str(val(m, "unit")).trimmed, columns: columns, groups: groups,
                             sources: sources, cards: cards)
        return Parsed(deck: deck, error: nil, problems: problems)
    }
    /// The deck's sections for its list: the deck's groups in order, then cards with no (or an unknown) group.
    public func sections() -> [(id: String, title: String, cards: [Card])] {
        let known = Set(groups.map(\.id))
        var out: [(id: String, title: String, cards: [Card])] = groups.map { g in (id: g.id, title: g.title, cards: cards.filter { $0.group == g.id }) }
        out = out.filter { !$0.cards.isEmpty }
        let rest = cards.filter { !known.contains($0.group) }
        if !rest.isEmpty { out.append((id: "", title: out.isEmpty ? "" : "Other", cards: rest)) }
        return out
    }

    /// A list cell: the front, the back or one of the card's fields.
    public static func cell(_ card: Card, _ key: String) -> String {
        key == "$front" ? card.front : key == "$back" ? card.back : card.fields[key] ?? ""
    }

    /// The tags on the cards, most used first.
    public func tags() -> [(tag: String, n: Int)] {
        var n: [String: Int] = [:]
        for c in cards { for t in c.tags { n[t, default: 0] += 1 } }
        return n.map { (tag: $0.key, n: $0.value) }.sorted { $0.n != $1.n ? $0.n > $1.n : jsLess($0.tag, $1.tag) }
    }

    /// "Ion → Formula" / "Formula → Ion": the deck's first two columns name the two sides.
    public func directionLabel(_ dir: Direction) -> String {
        let a = columns.first?.label ?? "Prompt", b = columns.count > 1 ? columns[1].label : "Answer"
        return dir == .reverse ? "\(b) → \(a)" : "\(a) → \(b)"
    }

    // MARK: the sides

    public struct Side: Equatable, Sendable {
        public var prompt: String
        public var answer: String
        /// What else is right when typed.
        public var accept: [String]
        /// A flip deck's card shown back first.
        public var flipped = false
    }

    /// A card in a direction. Reverse (back to front) only where the deck says reversible; its answer is the front, and its other
    /// names (fields.name, fields.other, "oxonium (hydronium)" gives both) count.
    public static func side(_ card: Card, _ dir: Direction) -> Side {
        guard dir == .reverse else { return Side(prompt: card.front, answer: card.back, accept: card.accept) }
        var alts: [String] = []
        func add(_ s: String) { if !alts.contains(s) { alts.append(s) } }
        add(card.front); card.acceptReverse.forEach(add)
        if let m = match(#"^(.+?)\s*\((.+)\)\s*$"#, card.front) { add(m[1]); add(m[2]) }
        if let n = card.fields["name"] { add(n) }
        if let o = card.fields["other"] { add(o) }
        return Side(prompt: card.back, answer: card.front, accept: alts.filter { !$0.isEmpty })
    }

    public enum Show: String, CaseIterable, Sendable {
        case es, en, mix
        public var label: String { self == .es ? "Spanish first" : self == .en ? "English first" : "Mixed" }
    }

    /// A flip deck's card as shown: the front first, the back first, or each card one way picked by the seed. The schedule is the
    /// card's one (forward) whichever side is shown.
    public static func flipSide(_ card: Card, _ show: Show, seed: String) -> Side {
        let back = show == .en || (show == .mix && rng("flip|" + seed + "|" + card.id)() < 0.5)
        return back ? Side(prompt: card.back, answer: card.front, accept: [], flipped: true) : Side(prompt: card.front, answer: card.back, accept: card.accept)
    }

    // MARK: multiple choice

    /// The card's own options (the right one among them), else the answers of other cards (its group's first). A list several
    /// cards share (strong acid / weak acid / strong base / weak base) keeps its order; anything else is shuffled by the seed.
    public func choices(_ card: Card, _ dir: Direction, seed: String, n: Int = 4) -> (options: [String], correct: Int) {
        let side = Self.side(card, dir)
        let rnd = Self.rng(seed + "|" + card.id + "|" + dir.rawValue)
        let same = { (a: String, b: String) in Self.check(a, b) == .right }
        if dir == .forward, let own = card.options {
            var opts: [String] = own.contains { same($0, side.answer) } ? own : [side.answer] + Array(own.prefix(n - 1))
            let key = { (l: [String]) in l.map { $0.trimmed.lowercased() }.sorted(by: jsLess).joined(separator: "\u{0}") }
            let shared = cards.filter { $0.options != nil && key($0.options!) == key(own) }.count >= 2
            if !shared { opts = Self.shuffle(opts, rnd) }
            return (opts, opts.firstIndex { same($0, side.answer) } ?? -1)
        }
        let other = { (c: Card) in Self.side(c, dir).answer }
        let pool = { (cs: [Card]) -> [String] in Self.shuffle(cs.filter { $0.id != card.id }, rnd).map(other).filter { !same($0, side.answer) } }
        var picks: [String] = []
        for a in pool(cards.filter { $0.group == card.group }) + pool(cards) {
            if picks.count >= n - 1 { break }
            if !picks.contains(a) { picks.append(a) }
        }
        let opts = Self.shuffle([side.answer] + picks, rnd)
        return (opts, opts.firstIndex(of: side.answer) ?? -1)
    }

    /// The laptop's seeded random (rngOf): the same seed gives the same numbers there and here.
    public static func rng(_ seed: String) -> () -> Double {
        var x: UInt32 = 2_166_136_261
        for u in seed.unicodeScalars { x = (x ^ UInt32(String(u).utf16.first!)) &* 16_777_619 }
        return {
            x = (x ^ (x >> 15)) &* 2_246_822_507
            x = (x ^ (x >> 13)) &* 3_266_489_909
            x ^= x >> 16
            return Double(x) / 4_294_967_296
        }
    }

    static func shuffle<T>(_ a: [T], _ rnd: () -> Double) -> [T] {
        var b = a
        var i = b.count - 1
        while i > 0 { let j = Int((rnd() * Double(i + 1)).rounded(.down)); b.swapAt(i, j); i -= 1 }
        return b
    }

    // MARK: typed answers

    public enum Verdict: String, Sendable {
        case right
        /// Right but for capitals in a formula.
        case `case`
        case wrong
        case empty
    }

    /// A formula answer is checked as a formula: its body and its charge must both be there (OH for OH⁻ is wrong); capitals alone wrong
    /// are `.case`. Words: case, spaces, hyphens, end punctuation and a last "ion" do not matter; sulphate = sulfate.
    public static func check(_ typed: String, _ answer: String, accept: [String] = []) -> Verdict {
        let t = typed.trimmed
        if t.isEmpty { return .empty }
        let want = ([answer] + accept).filter { !$0.isEmpty }
        let tf = forms(t)
        var caseOnly = false
        for w in want {
            if looksFormula(w) {
                let wf = forms(w)[0]
                for f in tf where f.charge == wf.charge {
                    if f.body == wf.body { return .right }
                    if f.body.lowercased() == wf.body.lowercased() { caseOnly = true }
                }
            } else if words(t) == words(w) { return .right }
        }
        return caseOnly ? .case : .wrong
    }

    /// One token with a capital letter (element symbols, digits, brackets), maybe a charge after it ("ClO -", "SO4^2-", "OH⁻", "HCl").
    public static func looksFormula(_ s: String) -> Bool {
        let x = plain(s).trimmed
        return test("[A-Z]", x) && test(#"^[A-Za-z0-9()\[\]]+(?:\s*\^?\s*\(?\s*(?:[0-9]*\s*[+-]|[+-]\s*[0-9]*)\s*\)?)?$"#, x) && !test("^[A-Z]?[a-z]{3,}$", x)
    }

    static let sub = Array("₀₁₂₃₄₅₆₇₈₉".unicodeScalars), sup = Array("⁰¹²³⁴⁵⁶⁷⁸⁹".unicodeScalars)

    /// Sub/superscript digits to digits, superscript and typographic signs to + and -, NFKC.
    static func plain(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for ch in s.precomposedStringWithCanonicalMapping.unicodeScalars {
            if let a = sub.firstIndex(of: ch) { out.append(contentsOf: String(a).unicodeScalars) }
            else if let b = sup.firstIndex(of: ch) { out.append(contentsOf: String(b).unicodeScalars) }
            else if ch == "⁺" || ch == "₊" { out.append("+") }
            else if ch == "⁻" || ch == "₋" || ch == "−" || ch == "–" || ch == "—" { out.append("-") }
            else { out.append(ch) }
        }
        return String(out).precomposedStringWithCompatibilityMapping
    }

    struct Form: Equatable { var body: String; var charge: String }

    /// The charge at the end of an answer, written any way: Unicode superscripts, after a separator ("SO4 2-", "SO4^2-", "SO4(2-)"),
    /// sign first ("SO4-2"), or glued on ("SO42-", ambiguous: every split is a candidate). "1" is dropped from a charge.
    static func forms(_ raw: String) -> [Form] {
        let s0 = raw.precomposedStringWithCanonicalMapping.trimmed
        let tidy = { (b: String) in replace(#"[\s^_()\[\]{}]"#, plain(b), "") }
        let ch = { (digits: String, sign: String) -> String in
            let d = String(digits.drop { $0 == "0" })
            return (d == "1" ? "" : d) + sign
        }
        if let m = matchRange("([⁰¹²³⁴⁵⁶⁷⁸⁹]*)([⁺⁻])$", s0) ?? matchRange("([⁺⁻])([⁰¹²³⁴⁵⁶⁷⁸⁹]*)$", s0), m.location > 0 {
            let ns = s0 as NSString
            let tail = plain(ns.substring(with: m))
            let sign = tail.contains("+") ? "+" : "-"
            let d = tail.filter { $0 != "+" && $0 != "-" }
            return [Form(body: tidy(ns.substring(to: m.location)), charge: ch(String(d), sign))]
        }
        let s = plain(s0).trimmed
        if let a = match(#"^(.+?)(?:\s+|\s*\^\s*|(?=\())\(?\s*([0-9]*)\s*([+-])\s*\)?$"#, s), test(#"\S"#, a[1]) {
            return [Form(body: tidy(a[1]), charge: ch(a[2], a[3]))]
        }
        if let b = match(#"^(.+?)(?:\s+|\s*\^\s*|(?=\())\(?\s*([+-])\s*([0-9]*)\s*\)?$"#, s), test(#"\S"#, b[1]) {
            return [Form(body: tidy(b[1]), charge: ch(b[3], b[2]))]
        }
        let g = replace(#"\s+"#, s, "")
        if let f = match(#"^(.*[A-Za-z0-9)\]])([+-])([0-9]+)$"#, g) {
            return [Form(body: tidy(f[1]), charge: ch(f[3], f[2]))]
        }
        if let gl = match(#"^(.*?[A-Za-z)\]])([0-9]*)([+-])$"#, g) {
            let body = gl[1], digits = Array(gl[2]), sign = gl[3]
            var out: [Form] = []
            for k in 0...digits.count {
                out.append(Form(body: tidy(body + String(digits.prefix(digits.count - k))), charge: ch(String(digits.suffix(k)), sign)))
            }
            return out
        }
        return [Form(body: tidy(s), charge: "")]
    }

    static func words(_ s: String) -> String {
        var x = plain(s).lowercased()
        x = replace(#"[.,;:!?]+$"#, x, "")
        x = x.replacingOccurrences(of: "sulph", with: "sulf").replacingOccurrences(of: "aluminium", with: "aluminum")
        x = replace("[\\s\u{2010}-\u{2015}-]+", x, " ").trimmed
        x = replace(" ions?$", x, "")
        return x.replacingOccurrences(of: " ", with: "")
    }

    // MARK: YAML and regex helpers

    static func val(_ m: Node.Mapping, _ key: String) -> Node? { TaskFile.value(m, key) }

    /// A scalar as the laptop's String(v) gives it ("" for none or null; a list or a map is "").
    static func str(_ n: Node?) -> String {
        guard let n, let s = n.scalar else { return "" }
        if s.style == .plain, ["~", "null", "Null", "NULL", ""].contains(s.string) { return "" }
        return s.string
    }

    static func strList(_ n: Node?) -> [String]? { n?.sequence.map { $0.map { str($0) } } }

    static func isTrue(_ n: Node?) -> Bool {
        guard let s = n?.scalar, s.style == .plain else { return false }
        return ["true", "True", "TRUE"].contains(s.string)
    }

    static func unique(_ a: [String]) -> [String] { var seen = Set<String>(); return a.filter { seen.insert($0).inserted } }

    /// The capture groups of the first match ([0] is the whole match; a group that did not take part is "").
    static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern), let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in let r = m.range(at: i); return r.location == NSNotFound ? "" : (s as NSString).substring(with: r) }
    }

    static func matchRange(_ pattern: String, _ s: String) -> NSRange? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        return re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))?.range
    }

    static func test(_ pattern: String, _ s: String) -> Bool { matchRange(pattern, s) != nil }

    static func replace(_ pattern: String, _ s: String, _ with: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: NSRegularExpression.escapedTemplate(for: with))
    }
}

/// JavaScript's default string order (UTF-16 code units), which the laptop's sorts use.
func jsLess(_ a: String, _ b: String) -> Bool { a.utf16.lexicographicallyPrecedes(b.utf16) }

extension String {
    /// JavaScript's trim(): white space and line ends at both ends.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
