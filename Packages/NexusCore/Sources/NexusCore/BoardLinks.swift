import Foundation

/// Links on a board, the same as the laptop's `renderer/src/board/links.js` (nexus docs/data-format.md "The board redesign's
/// additions" › Links). A link is an item `{ id, type: "link", x, y, a, b, color, made, by }` kept in the tile of its first end.
/// An end is one of:
///
///     on this board      { on: "<item, stroke or mark id>", at?: { q, pre, post, i } (words of a text block), page?, fx?, fy?, fw?, fh? }
///     on another board   the same plus board: "<path relative to this board>" (no `on`: the whole board)
///     outside boards     { task: "<task id>" } | { note: "<data-folder path>" } | { deck: "<data-folder path>", card: "<card id>" }
///
/// Here: making and reading ends, holding on to words (the quote with its context, found again after edits; offsets count UTF-16
/// units, as JavaScript does), PDF spots as fractions of a page, which links touch what, the cross-board index's pieces, the ribbon's
/// geometry and the words shown for an end. Pure: the board screen (BoardController+Links.swift) draws and edits.
public enum BoardLinks {
    public static let feature = "links"
    public static let colors = ["#7C5CFF", "#1F9D8B", "#E8833A", "#D6457A", "#3B82F6", "#8A8F98"]
    public static let colorNames = ["Violet", "Teal", "Orange", "Pink", "Blue", "Grey"]
    /// An excerpt's paper (a text block pulled out of a PDF).
    public static let excerptFill = "#FFF4B8"

    public enum Kind: String { case here, board, task, note, deck }

    public static func isLink(_ it: BoardItem) -> Bool { it.type == "link" }

    // MARK: ends

    static func str(_ v: JSONValue?) -> String? { if let s = v?.string, !s.isEmpty { return s }; return nil }

    public static func kind(_ e: JSONValue?) -> Kind? {
        guard let e, e.object != nil else { return nil }
        if str(e["task"]) != nil { return .task }
        if str(e["note"]) != nil { return .note }
        if str(e["deck"]) != nil { return .deck }
        if str(e["board"]) != nil { return .board }
        if str(e["on"]) != nil { return .here }
        return nil
    }

    static func r4(_ v: Double) -> Double { (min(1, max(0, v)) * 10000).rounded() / 10000 }

    /// An end as it is written: the fields this app knows cleaned, the others kept as they were read.
    public static func norm(_ e: JSONValue?) -> JSONValue? {
        guard let e, kind(e) != nil, var o = e.object else { return nil }
        if let i = o.firstIndex(where: { $0.0 == "page" }) {
            if let p = o[i].1.number, p >= 1, p == p.rounded() { o[i].1 = .number(p) } else { o.remove(at: i) }
        }
        for f in ["fx", "fy", "fw", "fh"] {
            guard let i = o.firstIndex(where: { $0.0 == f }) else { continue }
            if case .null = o[i].1 { continue }
            if let n = numeric(o[i].1) { o[i].1 = .number(r4(n)) } else { o.remove(at: i) }
        }
        if let i = o.firstIndex(where: { $0.0 == "at" }) {
            if str(o[i].1["q"]) == nil { o.remove(at: i) }
        }
        return .object(o)
    }

    /// A number, or a string holding one (as `+v` reads it in JavaScript).
    static func numeric(_ v: JSONValue) -> Double? {
        if let n = v.number, n.isFinite { return n }
        if let s = v.string, let n = Double(s.trimmingCharacters(in: .whitespaces)), n.isFinite { return n }
        return nil
    }

    public static func isPdfSpot(_ e: JSONValue?) -> Bool {
        guard let e, e["page"] != nil, let fx = e["fx"], let fy = e["fy"] else { return false }
        return numeric(fx) != nil && numeric(fy) != nil
    }

    static func iso(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return f.string(from: d)
    }

    /// A new link item; x, y = where end a is now.
    public static func make(id: String, a: JSONValue, b: JSONValue, color: String = colors[0], by: String = "", now: Date = Date(),
                            x: Double = 0, y: Double = 0) -> BoardItem? {
        guard let A = norm(a), let B = norm(b) else { return nil }
        let ok = color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
        var o: [(String, JSONValue)] = [("id", .string(id)), ("type", .string("link")), ("x", .number((x * 100).rounded() / 100)),
                                        ("y", .number((y * 100).rounded() / 100)), ("a", A), ("b", B),
                                        ("color", .string(ok ? color.uppercased() : colors[0])), ("made", .string(iso(now)))]
        if !by.isEmpty { o.append(("by", .string(by))) }
        return BoardItem(.object(o))
    }

    /// The same end? (a link from a thing to itself is refused; two links between the same ends are one)
    public static func same(_ p: JSONValue?, _ q: JSONValue?) -> Bool {
        guard let p, let q, let kp = kind(p), kp == kind(q) else { return false }
        for k in ["on", "board", "task", "note", "deck", "card", "page", "fx", "fy", "fw", "fh"] where (p[k] ?? .null) != (q[k] ?? .null) { return false }
        return (p["at"]?["q"]?.string) == (q["at"]?["q"]?.string) && (p["at"]?["i"]?.number) == (q["at"]?["i"]?.number)
    }

    public static func other(_ side: String) -> String { side == "a" ? "b" : "a" }

    /// Which side of a link is on a thing of this board ("a" | "b" | nil).
    public static func side(_ link: BoardItem, on id: String) -> String? {
        for s in ["a", "b"] where kind(link.json[s]) == .here && link.json[s]?["on"]?.string == id { return s }
        return nil
    }

    /// The links with an end on any of these things of this board.
    public static func links(_ items: [BoardItem], on ids: Set<String>) -> [BoardItem] {
        items.filter { l in
            isLink(l) && ["a", "b"].contains { s in kind(l.json[s]) == .here && ids.contains(l.json[s]?["on"]?.string ?? "") }
        }
    }

    // MARK: paths (the laptop's format.js resolveIn / relTo: data-folder paths with "/")

    /// A path relative to a board ("../B.board") as a data-folder path, or nil when it leaves the data folder.
    public static func resolve(_ board: String, _ rel: String) -> String? {
        guard !rel.isEmpty, !rel.hasPrefix("/"), !rel.contains("\\"),
              rel.range(of: "^[a-zA-Z]+:", options: .regularExpression) == nil else { return nil }
        var out = board.isEmpty ? [] : board.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for s in rel.split(separator: "/", omittingEmptySubsequences: false) {
            if s.isEmpty || s == "." { continue }
            if s == ".." { if out.isEmpty { return nil }; out.removeLast() } else { out.append(String(s)) }
        }
        return out.joined(separator: "/")
    }

    /// The other way: a data-folder path as a board's items write it.
    public static func rel(from board: String, to path: String) -> String {
        let a = board.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let b = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        return (Array(repeating: "..", count: a.count - i) + b[i...]).joined(separator: "/")
    }

    /// The data-folder path an end on a board names (this board for an end here), else nil.
    public static func board(of end: JSONValue?, from boardPath: String) -> String? {
        switch kind(end) {
        case .here: return boardPath
        case .board: return resolve(boardPath, end?["board"]?.string ?? "")
        default: return nil
        }
    }

    /// An end pointing at a thing on board `target` as written on board `from`: on the same board a plain end here.
    public static func end(for thing: JSONValue, target: String?, from: String) -> JSONValue? {
        var e = thing.setting("board", nil)
        if let target, target != from { e = e.setting("board", .string(rel(from: from, to: target))) }
        return norm(e)
    }

    /// A link read on board `from`, its end turned to be read from board `to`.
    public static func end(_ end: JSONValue?, readOn from: String, shownOn to: String) -> JSONValue? {
        guard let end else { return nil }
        let k = kind(end)
        guard k == .here || k == .board else { return end }
        guard let target = board(of: end, from: from) else { return nil }
        return self.end(for: end, target: target, from: to)
    }

    // MARK: holding on to words

    public static let context = 20

    static func isWordUnit(_ u: unichar) -> Bool {
        guard let s = Unicode.Scalar(u) else { return false }
        return CharacterSet.alphanumerics.contains(s) || "_'’-".unicodeScalars.contains(s)
    }

    /// The quote of md[from..<to] (UTF-16 offsets) with about 20 characters either side and an offset hint; with no words chosen, the
    /// word at `from`. Nil for nothing but spaces.
    public static func quote(_ md: String, from f0: Int, to t0: Int) -> JSONValue? {
        let s = md as NSString, n = s.length
        var from = max(0, min(n, f0)), to = max(from, min(n, t0))
        if to == from {
            while from > 0, isWordUnit(s.character(at: from - 1)) { from -= 1 }
            while to < n, isWordUnit(s.character(at: to)) { to += 1 }
        }
        let q = s.substring(with: NSRange(location: from, length: to - from))
        guard !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let p0 = max(0, from - context)
        let pre = s.substring(with: NSRange(location: p0, length: from - p0))
        let post = s.substring(with: NSRange(location: to, length: min(n, to + context) - to))
        return .object([("q", .string(q)), ("pre", .string(pre)), ("post", .string(post)), ("i", .number(Double(from)))])
    }

    /// Where the quoted words are now (UTF-16 offsets): the occurrence whose context matches best, nearest the hint; nil = a ghost.
    public static func find(_ md: String, _ at: JSONValue?) -> NSRange? {
        guard let at, let q = str(at["q"]) else { return nil }
        let s = md as NSString, n = s.length
        let pre = (at["pre"]?.string ?? "") as NSString, post = (at["post"]?.string ?? "") as NSString
        let qn = (q as NSString).length
        let hint = at["i"].flatMap(numeric) ?? 0
        var best: (r: NSRange, score: Double)?
        var start = 0
        while start <= n {
            let r = s.range(of: q, options: .literal, range: NSRange(location: start, length: n - start))
            if r.location == NSNotFound { break }
            let k = r.location
            let b0 = max(0, k - pre.length)
            let before = s.substring(with: NSRange(location: b0, length: k - b0)) as NSString
            let aEnd = min(n, k + qn + post.length)
            let after = s.substring(with: NSRange(location: k + qn, length: aEnd - k - qn)) as NSString
            let score = Double(common(before, pre, fromEnd: true) + common(after, post, fromEnd: false)) - min(20, abs(Double(k) - hint) / 50)
            if best == nil || score > best!.score { best = (NSRange(location: k, length: qn), score) }
            start = k + 1
        }
        return best?.r
    }

    static func common(_ x: NSString, _ y: NSString, fromEnd: Bool) -> Int {
        var n = 0
        let L = min(x.length, y.length)
        while n < L {
            let a = fromEnd ? x.character(at: x.length - 1 - n) : x.character(at: n)
            let b = fromEnd ? y.character(at: y.length - 1 - n) : y.character(at: n)
            if a != b { break }
            n += 1
        }
        return n
    }

    /// The quote as plain words (markdown marks out), to find it in the drawn block.
    public static func plainWords(_ q: String) -> String {
        var s = q.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\*\*|__|~~|==|\*|_|`)"#, with: "", options: .regularExpression)
        if let re = try? NSRegularExpression(pattern: #"^#+\s+|^\s*[-*+]\s+(\[[ xX]\]\s+)?|^\s*\d+\.\s+"#, options: [.anchorsMatchLines]) {
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }
        return s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    // MARK: PDF spots

    public struct Frame: Equatable { public var x, y, w, h: Double; public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h } }

    /// A box on a page's frame (x0, y0, x1, y1 in any order) as fractions of the page: fx, fy, fw, fh.
    public static func pdfSpot(_ frame: Frame, _ box: [Double]) -> [(String, JSONValue)] {
        let fx = (min(box[0], box[2]) - frame.x) / frame.w, fy = (min(box[1], box[3]) - frame.y) / frame.h
        let fw = abs(box[2] - box[0]) / frame.w, fh = abs(box[3] - box[1]) / frame.h
        let x0 = r4(fx), y0 = r4(fy)
        return [("fx", .number(x0)), ("fy", .number(y0)), ("fw", .number(r4(min(fw, 1 - x0)))), ("fh", .number(r4(min(fh, 1 - y0))))]
    }

    public static func spotBox(_ frame: Frame, _ e: JSONValue) -> [Double] {
        func v(_ k: String) -> Double { e[k].flatMap(numeric) ?? 0 }
        let x = frame.x + v("fx") * frame.w, y = frame.y + v("fy") * frame.h
        return [x, y, x + v("fw") * frame.w, y + v("fh") * frame.h]
    }

    // MARK: the cross-board index

    /// The links in a tile file's text (a quick look first: most tiles have none).
    public static func links(inTile text: String) -> [BoardItem] {
        guard text.contains("\"link\""), let v = try? JSONValue.parse(text) else { return [] }
        return (v["items"]?.array ?? []).compactMap { j -> BoardItem? in
            guard j["type"]?.string == "link", str(j["id"]) != nil, norm(j["a"]) != nil, norm(j["b"]) != nil else { return nil }
            return BoardItem(j)
        }
    }

    public struct Far: Equatable {
        public var from: String
        public var link: BoardItem
        public var side: String
    }

    /// The links elsewhere with an end on `board` (on a thing of it, or the whole board). `index`: board path and its links, in order.
    public static func incoming(_ index: [(String, [BoardItem])], to board: String) -> [Far] {
        var out: [Far] = []
        for (from, links) in index where from != board {
            for l in links { for s in ["a", "b"] where kind(l.json[s]) == .board && resolve(from, l.json[s]?["board"]?.string ?? "") == board {
                out.append(Far(from: from, link: l, side: s))
            } }
        }
        return out
    }

    /// Every link in the index with an end on this task, note or deck (and card).
    public static func linksTo(_ index: [(String, [BoardItem])], task: String? = nil, note: String? = nil, deck: String? = nil, card: String? = nil) -> [Far] {
        var out: [Far] = []
        for (from, links) in index { for l in links { for s in ["a", "b"] {
            let e = l.json[s]
            if (task != nil && e?["task"]?.string == task) || (note != nil && e?["note"]?.string == note)
                || (deck != nil && e?["deck"]?.string == deck && (card == nil || e?["card"]?.string == card)) {
                out.append(Far(from: from, link: l, side: s))
            }
        } } }
        return out
    }

    /// The group a link's far end falls in, for the Links list: here | board:<path> | task | note | deck.
    public static func group(of end: JSONValue?, from boardPath: String) -> String {
        let k = kind(end)
        if k == .board { return "board:" + (board(of: end, from: boardPath) ?? end?["board"]?.string ?? "") }
        return k?.rawValue ?? "here"
    }

    // MARK: the ribbon (screen points): a soft curve that bends around things, drawn as a band wider at its ends

    public struct Curve { public var c1: (Double, Double); public var c2: (Double, Double); public var side: Double; public var hits: Int }

    public static func bez(_ p: (Double, Double), _ c1: (Double, Double), _ c2: (Double, Double), _ q: (Double, Double), _ t: Double) -> (Double, Double) {
        let u = 1 - t
        return (u * u * u * p.0 + 3 * u * u * t * c1.0 + 3 * u * t * t * c2.0 + t * t * t * q.0,
                u * u * u * p.1 + 3 * u * u * t * c1.1 + 3 * u * t * t * c2.1 + t * t * t * q.1)
    }

    /// p, q: the ends; obstacles: boxes [x0, y0, x1, y1] to keep clear of (the ends' own boxes left out).
    public static func curve(_ p: (Double, Double), _ q: (Double, Double), obstacles: [[Double]] = [], maxBend: Double = 160, k: Double = 0.22) -> Curve {
        let dx = q.0 - p.0, dy = q.1 - p.1, len = hypot(dx, dy), L = len == 0 ? 1 : len, nx = -dy / L, ny = dx / L
        let bend = min(maxBend, L * k)
        func bent(_ side: Double) -> Curve {
            let off = bend * side
            return Curve(c1: (p.0 + dx * 0.3 + nx * off, p.1 + dy * 0.3 + ny * off), c2: (p.0 + dx * 0.7 + nx * off, p.1 + dy * 0.7 + ny * off), side: side, hits: 0)
        }
        func hits(_ c: Curve) -> Int {
            var n = 0
            for i in 1..<16 {
                let (x, y) = bez(p, c.c1, c.c2, q, Double(i) / 16)
                for b in obstacles where x > b[0] && x < b[2] && y > b[1] && y < b[3] { n += 1 }
            }
            return n
        }
        let pref: Double = dx >= 0 ? 1 : -1
        var best: Curve?
        for side in [pref, -pref, pref * 0.35, pref * 2] {
            var c = bent(side)
            c.hits = hits(c)
            if best == nil || c.hits < best!.hits { best = c }
            if c.hits == 0 { break }
        }
        return best!
    }

    /// The band's outline, `w0` wide at the ends and `w1` in the middle: one side there, the other back (2 × (n + 1) points).
    public static func band(_ p: (Double, Double), _ q: (Double, Double), _ c: Curve, w0: Double = 9, w1: Double = 3.5, n: Int = 28) -> [(Double, Double)] {
        let pts = (0...n).map { bez(p, c.c1, c.c2, q, Double($0) / Double(n)) }
        var left: [(Double, Double)] = [], right: [(Double, Double)] = []
        for i in 0...n {
            let a = pts[max(0, i - 1)], b = pts[min(n, i + 1)], tx = b.0 - a.0, ty = b.1 - a.1
            let tl = hypot(tx, ty) == 0 ? 1 : hypot(tx, ty)
            let t = Double(i) / Double(n), w = (w1 + (w0 - w1) * pow(abs(2 * t - 1), 1.6)) / 2
            left.append((pts[i].0 - ty / tl * w, pts[i].1 + tx / tl * w))
            right.append((pts[i].0 + ty / tl * w, pts[i].1 - tx / tl * w))
        }
        return left + right.reversed()
    }

    /// Where a ribbon meets a box: the point on its edge toward `toward`.
    public static func edgePoint(_ box: [Double], toward: (Double, Double)) -> (Double, Double) {
        let cx = (box[0] + box[2]) / 2, cy = (box[1] + box[3]) / 2, dx = toward.0 - cx, dy = toward.1 - cy
        let hw = max(1, (box[2] - box[0]) / 2), hh = max(1, (box[3] - box[1]) / 2)
        if dx == 0, dy == 0 { return (cx, cy) }
        let k = min(hw / abs(dx == 0 ? 1e-9 : dx), hh / abs(dy == 0 ? 1e-9 : dy), 1)
        return (cx + dx * k, cy + dy * k)
    }

    /// An end off the view: the view's edge on the way to it.
    public static func clamp(_ p: (Double, Double), _ q: (Double, Double), view: [Double], pad: Double = 18) -> (Double, Double) {
        let b = [view[0] + pad, view[1] + pad, view[2] - pad, view[3] - pad]
        if q.0 >= b[0], q.0 <= b[2], q.1 >= b[1], q.1 <= b[3] { return q }
        let dx = q.0 - p.0, dy = q.1 - p.1
        var t = 1.0
        if dx > 0 { t = min(t, (b[2] - p.0) / dx) }
        if dx < 0 { t = min(t, (b[0] - p.0) / dx) }
        if dy > 0 { t = min(t, (b[3] - p.1) / dy) }
        if dy < 0 { t = min(t, (b[1] - p.1) / dy) }
        t = max(0, t)
        return (p.0 + dx * t, p.1 + dy * t)
    }

    // MARK: words for an end

    public struct LabelContext {
        public var kind: String?      // text | pdf | image | shape | stroke | mark
        public var text: String?
        public var pdfName: String?
        public var taskTitle: String?
        public var cardFront: String?
        public var missing = false
        public init(kind: String? = nil, text: String? = nil, pdfName: String? = nil, taskTitle: String? = nil, cardFront: String? = nil, missing: Bool = false) {
            self.kind = kind; self.text = text; self.pdfName = pdfName; self.taskTitle = taskTitle; self.cardFront = cardFront; self.missing = missing
        }
    }

    static func clip(_ s: String, _ n: Int = 48) -> String {
        let t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return t.count > n ? String(t.prefix(n - 1)) + "…" : t
    }

    static func lastName(_ p: String, dropping ext: String) -> String {
        var s = p
        while s.hasSuffix("/") { s.removeLast() }
        if let i = s.lastIndex(of: "/") { s = String(s[s.index(after: i)...]) }
        return s.replacingOccurrences(of: ext, with: "", options: [.regularExpression, .caseInsensitive])
    }

    public static func label(_ end: JSONValue?, _ ctx: LabelContext = LabelContext()) -> String {
        guard let end else { return "Something" }
        let k = kind(end)
        if k == .task { return ctx.taskTitle.map { clip($0) } ?? "A task" }
        if k == .note { return clip(lastName(end["note"]?.string ?? "", dropping: #"\.md$"#)) }
        if k == .deck {
            return (ctx.cardFront.map { clip($0, 36) + " · " } ?? "") + clip(lastName(end["deck"]?.string ?? "", dropping: #"\.ya?ml$"#), 30)
        }
        let whereName = k == .board ? clip(lastName(end["board"]?.string ?? "", dropping: #"\.board$"#), 30) : ""
        if k == .board, str(end["on"]) == nil { return whereName }
        let page = end["page"]?.number.map { Int($0) }
        var what: String
        if let q = str(end["at"]?["q"]) { what = "“" + clip(plainWords(q), 40) + "”" }
        else if ctx.kind == "text" { what = ctx.text.map { "“" + clip(plainWords($0), 40) + "”" } ?? "Text" }
        else if ctx.kind == "pdf" { what = (ctx.pdfName.map { clip($0, 24) + " " } ?? "") + (page.map { "p. \($0)" } ?? "") }
        else if ctx.kind == "image" { what = "Picture" }
        else if ctx.kind == "shape" { what = "Shape" }
        else if ctx.kind == "stroke" { what = "Ink" }
        else if ctx.kind == "mark" { what = "Comment" }
        else if let page { what = "p. \(page)" }
        else if k == .board, !ctx.missing { return "On " + whereName }
        else { what = ctx.missing ? "Something no longer there" : "Something" }
        if let page, ctx.kind != "pdf", !what.contains("p. ") { what += " · p. \(page)" }
        return whereName.isEmpty ? what : what + " · " + whereName
    }
}
