import Foundation

/// Marks (nexus docs/data-format.md "Marks", feature `marks`): comments (`bubble`, typed or handwritten) and ink attached to text
/// (`ink`), each an item of type `mark` that holds on to words with a WordAnchor (`at`) in the block `on`. Pure: the app places them.
public enum BoardMarks {
    public static func isMark(_ it: BoardItem) -> Bool { it.type == "mark" }
    public static func kind(_ it: BoardItem) -> String { it.string("kind") ?? "bubble" }
    public static func on(_ it: BoardItem) -> String? { it.string("on") }
    public static func anchor(_ it: BoardItem) -> WordAnchor? { WordAnchor(it.json["at"]) }
    public static func isDone(_ it: BoardItem) -> Bool { it.json["done"]?.bool ?? false }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    /// A new mark. `strokes` (a handwritten comment) are kept with their points relative to x, y.
    public static func make(id: String, kind: String, on: String?, at: WordAnchor?, page: Int? = nil, x: Double, y: Double,
                            text: String? = nil, strokes: [BoardStroke]? = nil, by: String, now: Date = Date()) -> BoardItem {
        var f: [(String, JSONValue)] = [("kind", .string(kind))]
        if let on { f.append(("on", .string(on))) }
        if let at { f.append(("at", at.json)) }
        if let page { f.append(("page", .number(Double(page)))) }
        if let text { f.append(("text", .string(text))) }
        if kind == "bubble" { f.append(("replies", .array([]))) }
        if let strokes { f.append(("strokes", .array(relative(strokes, x: x, y: y).map(\.json)))) }
        f += [("by", .string(by)), ("made", .string(iso(now))), ("done", .bool(false))]
        return BoardItem(id: id, type: "mark", x: r2(x), y: r2(y), fields: f)
    }

    /// Positions as the laptop keeps them (two decimals).
    static func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    static func relative(_ strokes: [BoardStroke], x: Double, y: Double) -> [BoardStroke] {
        strokes.map { s in
            var s = s
            s.raw = nil
            s.points = s.points.map { p in
                var q = p
                if q.count >= 2 { q[0] -= r2(x); q[1] -= r2(y) }
                return q
            }
            return s
        }
    }

    /// A handwritten comment's strokes, back in board units (or the mark's own when `absolute` is false).
    public static func strokes(_ it: BoardItem, absolute: Bool = true) -> [BoardStroke] {
        (it.json["strokes"]?.array ?? []).compactMap { BoardStroke($0, fields: nil) }.map { s in
            guard absolute else { return s }
            var s = s
            s.points = s.points.map { p in
                var q = p
                if q.count >= 2 { q[0] += it.x; q[1] += it.y }
                return q
            }
            return s
        }
    }

    public struct Reply: Equatable, Sendable {
        public var text: String?
        public var strokes: JSONValue?
        public var by: String
        public var made: String
    }

    public static func replies(_ it: BoardItem) -> [Reply] {
        (it.json["replies"]?.array ?? []).map {
            Reply(text: $0["text"]?.string, strokes: $0["strokes"], by: $0["by"]?.string ?? "", made: $0["made"]?.string ?? "")
        }
    }

    public static func reply(_ it: BoardItem, text: String, by: String, now: Date = Date()) -> BoardItem {
        var list = it.json["replies"]?.array ?? []
        list.append(.object([("text", .string(text)), ("by", .string(by)), ("made", .string(iso(now)))]))
        return it.with("replies", .array(list))
    }

    /// The marks that hold on to a block's words.
    public static func marks(on id: String, _ items: [BoardItem]) -> [BoardItem] {
        items.filter { isMark($0) && on($0) == id && anchor($0) != nil }
    }

    /// After a block's words changed: each mark on it follows its words (`at` brought up to date; a ghost stays as it was).
    public static func refreshed(_ items: [BoardItem], block id: String, words: String) -> [BoardItem] {
        items.map { it in
            guard isMark(it), on(it) == id, let at = anchor(it) else { return it }
            let next = Anchor.refresh(words, at)
            return next == at ? it : it.with("at", next.json)
        }
    }

    // MARK: ink attached to text

    /// The mark a stroke belongs to (`"mark"` in the stroke), or nil.
    public static func strokeMark(_ s: BoardStroke) -> String? { s.raw?["mark"]?.string }

    /// The stroke tagged with a mark (nil takes the tag off). Its other fields are kept.
    public static func tagged(_ s: BoardStroke, mark: String?) -> BoardStroke {
        var s = s
        let base = s.raw ?? .object([])
        s.raw = base.setting("mark", mark.map { .string($0) })
        return s
    }

    /// An ink mark's words moved to `to` (where their top-left is now): its strokes move by the same amount and x, y follow.
    public static func follow(_ c: BoardContent, mark id: String, to: (x: Double, y: Double)) -> BoardContent {
        guard let k = c.items.firstIndex(where: { $0.id == id && isMark($0) }) else { return c }
        let it = c.items[k]
        let dx = (to.x - it.x).rounded(), dy = (to.y - it.y).rounded()
        guard dx != 0 || dy != 0 else { return c }
        var out = c
        for i in out.strokes.indices where strokeMark(out.strokes[i]) == id {
            out.strokes[i].points = out.strokes[i].points.map { p in
                var q = p
                if q.count >= 2 { q[0] = ((q[0] + dx) * 100).rounded() / 100; q[1] = ((q[1] + dy) * 100).rounded() / 100 }
                return q
            }
        }
        out.items[k] = it.with("x", .number(it.x + dx)).with("y", .number(it.y + dy))
        return out
    }

    /// Attach to text: tags the strokes with a new ink mark on the words `from..<to` of block `on`, whose top-left is at x, y.
    public static func attach(_ c: BoardContent, strokes ids: Set<String>, mark id: String, on block: String, words: String,
                              from: Int, to: Int, x: Double, y: Double, by: String, now: Date = Date()) -> BoardContent {
        var out = c
        for i in out.strokes.indices where ids.contains(out.strokes[i].id) {
            out.strokes[i] = tagged(out.strokes[i], mark: id)
        }
        out.items.append(make(id: id, kind: "ink", on: block, at: Anchor.make(words, from: from, to: to), x: x, y: y, by: by, now: now))
        return out
    }

    /// Detach: the strokes stay where they are, without the mark.
    public static func detach(_ c: BoardContent, mark id: String) -> BoardContent {
        var out = c
        for i in out.strokes.indices where strokeMark(out.strokes[i]) == id { out.strokes[i] = tagged(out.strokes[i], mark: nil) }
        out.items.removeAll { $0.id == id }
        return out
    }
}
