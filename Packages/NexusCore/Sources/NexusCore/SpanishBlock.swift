import Foundation

/// Spanish underlines in a typed block on a board (the laptop's desktop/src/board/spanish.ts, nexus docs/board-writing.md "Spanish
/// blocks"): each paragraph of a Spanish block is read by the checker (Claude Haiku, the same prompt as Spanish › Check) a moment after
/// the typing stops, once for the words it has, and its mistakes are underlined while the block is open and on the closed block; a tap
/// on one shows the fix with Apply. These checks are not counted in the skills' numbers; Check it now reads the whole block and is
/// counted, Correct this turns every fix into a Review suggestion. They follow the live corrections switch, the block's own "Check my
/// Spanish" and Practice mode.
///
/// The pure half: a block's markdown as paragraphs of plain words (one markdown line is one paragraph, as the laptop's copy has it,
/// without the marks, maths and code), where a paragraph's marks fall in the markdown, and the paragraphs already read.
public enum SpanishBlock {
    /// One paragraph: its words as the checker reads them, and for each of their UTF-16 units where it is in the markdown.
    public struct Para: Equatable, Sendable {
        public var text: String
        public var map: [Int]
        public var line: NSRange
    }

    /// A mark placed in the block's markdown.
    public struct Placed: Equatable, Sendable {
        public var range: NSRange
        public var mark: SpanishCheck.Mark
        public init(range: NSRange, mark: SpanishCheck.Mark) { self.range = range; self.mark = mark }
    }

    /// The paragraphs of a block's markdown (blank lines, code, maths and tables left out).
    public static func paragraphs(_ md: String) -> [Para] {
        let ns = md as NSString
        var out: [Para] = []
        for line in LiveMarkdown.parse(md) {
            switch line.kind {
            case .blank, .fence, .code, .rule, .table, .tableRule, .mathFence, .math: continue
            default: break
            }
            var skip = IndexSet()
            for m in line.marks { skip.insert(integersIn: m.range.location..<NSMaxRange(m.range)) }
            if let r = line.marker { skip.insert(integersIn: r.location..<NSMaxRange(r)) }
            for sp in line.spans {
                switch sp.kind {
                case .code, .math, .nexusTask, .deleted: skip.insert(integersIn: sp.range.location..<NSMaxRange(sp.range))
                default: break
                }
            }
            if line.content > line.range.location { skip.insert(integersIn: line.range.location..<min(line.content, NSMaxRange(line.range))) }
            var units: [unichar] = [], map: [Int] = []
            for i in line.range.location..<NSMaxRange(line.range) where !skip.contains(i) {
                units.append(ns.character(at: i))
                map.append(i)
            }
            let text = String(utf16CodeUnits: units, count: units.count)
            if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            out.append(Para(text: text, map: map, line: line.range))
        }
        return out
    }

    /// Worth a check: two words or more.
    public static func worth(_ text: String) -> Bool {
        (try? NSRegularExpression(pattern: "\\p{L}+"))?.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? 0 >= 2
    }

    /// The checker's answer on some words as marks over them (offsets in those words, untrimmed): only mistakes whose words are really
    /// there and differ from their fix (the laptop's rule).
    public static func marks(_ text: String, _ ai: SpanishCheck.AI?) -> [SpanishCheck.Mark] {
        let ns = text as NSString
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = ns.range(of: t).location == NSNotFound ? 0 : ns.range(of: t).location
        let tn = t as NSString
        return SpanishCheck.merge(t, [], ai).filter { m in
            m.kind != "good" && m.s >= 0 && m.e > m.s && m.e <= tn.length && tn.substring(with: NSRange(location: m.s, length: m.e - m.s)) == m.wrong && m.wrong != m.right
        }.map { var m = $0; m.s += lead; m.e += lead; return m }
    }

    /// The marks known for each paragraph, placed in the markdown.
    public static func place(_ md: String, known: (String) -> [SpanishCheck.Mark]?) -> [Placed] {
        var out: [Placed] = []
        for p in paragraphs(md) {
            for m in known(p.text) ?? [] {
                guard m.s >= 0, m.e > m.s, m.e <= p.map.count else { continue }
                let a = p.map[m.s], b = p.map[m.e - 1] + 1
                out.append(Placed(range: NSRange(location: a, length: b - a), mark: m))
            }
        }
        return out
    }

    /// The whole block's words as Check it now sends them (its paragraphs, one a line), and where each paragraph starts in them.
    public static func whole(_ md: String) -> (text: String, starts: [(para: Para, at: Int)]) {
        var text = "", starts: [(para: Para, at: Int)] = []
        for p in paragraphs(md) {
            if !text.isEmpty { text += "\n" }
            starts.append((p, (text as NSString).length))
            text += p.text
        }
        return (text, starts)
    }

    /// Marks over the whole block's words split back into each paragraph's own (offsets in the paragraph).
    public static func split(_ md: String, _ marks: [SpanishCheck.Mark]) -> [(text: String, marks: [SpanishCheck.Mark])] {
        whole(md).starts.map { x in
            let n = (x.para.text as NSString).length
            return (x.para.text, marks.filter { $0.s >= x.at && $0.e <= x.at + n }.map { var m = $0; m.s -= x.at; m.e -= x.at; return m })
        }
    }

    /// Every fix as (range in the markdown, its words): what Correct this writes as Review suggestions.
    public static func fixes(_ placed: [Placed]) -> [(range: NSRange, fix: String)] {
        var used: [NSRange] = []
        var out: [(range: NSRange, fix: String)] = []
        for p in placed.sorted(by: { $0.range.location < $1.range.location }) where !p.mark.right.isEmpty {
            if used.contains(where: { NSIntersectionRange($0, p.range).length > 0 }) { continue }
            used.append(p.range)
            out.append((p.range, p.mark.right))
        }
        return out
    }

    // MARK: the paragraphs already read

    /// A paragraph's words -> its mistakes, kept across launches (the newest 600, as the laptop's).
    public struct Known: Sendable {
        public static let max = 600
        private(set) public var order: [String] = []
        private var marks: [String: [SpanishCheck.Mark]] = [:]
        public init() {}

        public func get(_ text: String) -> [SpanishCheck.Mark]? { marks[text] }
        public func has(_ text: String) -> Bool { marks[text] != nil }
        public mutating func set(_ text: String, _ m: [SpanishCheck.Mark]) {
            if marks[text] != nil { order.removeAll { $0 == text } }
            marks[text] = m
            order.append(text)
            while order.count > Self.max { marks[order.removeFirst()] = nil }
        }

        /// As JSON: [[words, [{s, e, wrong, right, skill, kind, why}]]], oldest first.
        public func encode() -> String {
            JSONValue.array(order.map { t in
                .array([.string(t), .array((marks[t] ?? []).map { m in
                    .object([("s", .number(Double(m.s))), ("e", .number(Double(m.e))), ("wrong", .string(m.wrong)), ("right", .string(m.right)),
                             ("skill", .string(m.skill)), ("kind", .string(m.kind)), ("why", .string(m.why))])
                })])
            }).text
        }

        public static func decode(_ s: String?) -> Known {
            var k = Known()
            guard let s, let v = try? JSONValue.parse(s), let rows = v.array else { return k }
            for r in rows {
                guard let pair = r.array, pair.count == 2, let t = pair[0].string, let ms = pair[1].array else { continue }
                k.set(t, ms.compactMap { m in
                    guard let a = m["s"]?.number, let b = m["e"]?.number else { return nil }
                    return SpanishCheck.Mark(s: Int(a), e: Int(b), wrong: m["wrong"]?.string ?? "", right: m["right"]?.string ?? "", skill: m["skill"]?.string ?? "",
                                             kind: m["kind"]?.string ?? "error", why: m["why"]?.string ?? "", by: "claude")
                })
            }
            return k
        }
    }

    // MARK: whether a block is checked

    /// "set" (its lang is es), "detected" (its words read as Spanish and it isn't marked English) or nil.
    public static func langBy(_ item: BoardItem, _ md: String) -> String? {
        let l = item.string("lang")
        if l == "es" { return "set" }
        if l == "en" { return nil }
        return BlockFacts.lang(nil, md) == "es" ? "detected" : nil
    }

    /// Underlined as it is written: Spanish, its own "Check my Spanish" on, not in practice.
    public static func checking(_ item: BoardItem, _ md: String) -> Bool {
        langBy(item, md) != nil && item.json["check"]?.bool != false && !Practice.isOn(item)
    }
}
