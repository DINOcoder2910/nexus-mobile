import Foundation

/// Review mode's suggestions in a typed block's markdown: CriticMarkup `{++added++}`, `{--deleted--}` and `{~~old~>new~~}` (nexus
/// docs/board-writing.md "Review mode"; a line-for-line port of the laptop's renderer/src/board/critic.js, checked against its own outputs
/// in CriticTests). Markup never spans a line break: a line made only of `{++ ++}` is a whole added line, one made only of `{-- --}` a whole
/// deleted line, and that is how a suggested line break is written. Broken markup, markup holding another opening, and markup inside a
/// code span or a fenced code block are plain text. Text is handled as UTF-16 code units, as the laptop's JavaScript does.
public enum Critic {
    public typealias U = [UInt16]

    public enum Kind: String, Sendable { case add, del, sub }

    /// One suggestion: where its whole markup is in the markdown (UTF-16), its words, and where those words are inside the markup.
    public struct Mark: Equatable, Sendable {
        public var kind: Kind
        public var from: Int
        public var to: Int
        public var old: String
        public var new: String
        /// Where the old words start (for an add: just inside the opening).
        public var oldAt: Int
        /// Where the new words start.
        public var newAt: Int
    }

    struct M { var kind: Kind; var from: Int; var to: Int; var old: U; var new: U; var oAt: Int; var nAt: Int }

    struct Rec {
        var raw: U
        var marks: [M] = []
        var old: U?
        var new: U?
        var fresh = false
        var code = false
        var keep = false
    }

    // MARK: text helpers

    static func u(_ s: String) -> U { Array(s.utf16) }
    static func str(_ u: U) -> String { String(decoding: u, as: UTF16.self) }
    static let nl: UInt16 = 10, tick: UInt16 = 96, brace: UInt16 = 123

    static func indexOf(_ hay: U, _ needle: U, _ from: Int = 0) -> Int {
        let n = needle.count
        guard n > 0 else { return min(max(from, 0), hay.count) }
        var i = max(from, 0)
        while i + n <= hay.count {
            if hay[i] == needle[0] {
                var k = 1
                while k < n && hay[i + k] == needle[k] { k += 1 }
                if k == n { return i }
            }
            i += 1
        }
        return -1
    }

    static func indexOf(_ hay: U, _ c: UInt16, _ from: Int) -> Int {
        var i = max(from, 0)
        while i < hay.count { if hay[i] == c { return i }; i += 1 }
        return -1
    }

    static func slice(_ s: U, _ a: Int, _ b: Int? = nil) -> U {
        let lo = min(max(a, 0), s.count), hi = min(max(b ?? s.count, lo), s.count)
        return Array(s[lo..<hi])
    }

    static func split(_ s: U) -> [U] { s.split(separator: nl, omittingEmptySubsequences: false).map(Array.init) }
    static func join(_ lines: [U]) -> U {
        var out = U()
        for (i, l) in lines.enumerated() { if i > 0 { out.append(nl) }; out += l }
        return out
    }

    static let openAdd = u("{++"), openDel = u("{--"), openSub = u("{~~")
    static let closeAdd = u("++}"), closeDel = u("--}"), closeSub = u("~~}"), arrow = u("~>")

    static func hasOpen(_ s: U) -> Bool { indexOf(s, openAdd) >= 0 || indexOf(s, openDel) >= 0 || indexOf(s, openSub) >= 0 }

    /// JavaScript's `\s` for one code unit.
    static func isSpace(_ c: UInt16) -> Bool {
        switch c {
        case 9, 10, 11, 12, 13, 32, 0xA0, 0x1680, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF: return true
        case 0x2000...0x200A: return true
        default: return false
        }
    }

    // MARK: reading one line

    /// [from, to) of each code span on a line: a run of backticks closed by the next run of the same length (runs inside marks don't count).
    static func codeSpans(_ line: U, _ marks: [M] = []) -> [(Int, Int)] {
        var runs: [(Int, Int)] = []
        var i = 0
        while i < line.count {
            if line[i] == tick {
                var j = i
                while j < line.count && line[j] == tick { j += 1 }
                let at = i
                if !marks.contains(where: { $0.from < at && at < $0.to }) { runs.append((i, j - i)) }
                i = j
            } else { i += 1 }
        }
        var out: [(Int, Int)] = []
        var k = 0
        while k < runs.count {
            var j = k + 1
            while j < runs.count && runs[j].1 != runs[k].1 { j += 1 }
            if j < runs.count { out.append((runs[k].0, runs[j].0 + runs[j].1)); k = j }
            k += 1
        }
        return out
    }

    /// The markup opening at p, or nil when it is broken (no close on the line, no `~>`, or another opening inside).
    static func markAt(_ line: U, _ p: Int) -> M? {
        let t = line[p + 1], s = p + 3
        if t == 126 { // ~
            let sep = indexOf(line, arrow, s)
            if sep < 0 { return nil }
            let early = indexOf(line, closeSub, s)
            if early >= 0 && early < sep { return nil }
            let end = indexOf(line, closeSub, sep + 2)
            if end < 0 { return nil }
            let o = slice(line, s, sep), n = slice(line, sep + 2, end)
            return hasOpen(o) || hasOpen(n) ? nil : M(kind: .sub, from: p, to: end + 3, old: o, new: n, oAt: s, nAt: sep + 2)
        }
        let end = indexOf(line, t == 43 ? closeAdd : closeDel, s)
        if end < 0 { return nil }
        let x = slice(line, s, end)
        if hasOpen(x) { return nil }
        return t == 43 ? M(kind: .add, from: p, to: end + 3, old: [], new: x, oAt: s, nAt: s) : M(kind: .del, from: p, to: end + 3, old: x, new: [], oAt: s, nAt: s)
    }

    /// The marks on a line, left to right; then a mark inside a code span (paired from backticks outside marks) is plain text, until none is.
    static func scanLine(_ line: U) -> [M] {
        var marks: [M] = []
        var p = indexOf(line, brace, 0)
        while p >= 0 {
            var m: M?
            if p + 3 <= line.count {
                let t = slice(line, p, p + 3)
                if t == openAdd || t == openDel || t == openSub { m = markAt(line, p) }
            }
            if let m { marks.append(m); p = indexOf(line, brace, m.to) } else { p = indexOf(line, brace, p + 1) }
        }
        while !marks.isEmpty && line.contains(tick) {
            let spans = codeSpans(line, marks)
            let keep = marks.filter { m in !spans.contains { $0.0 < m.from && m.to <= $0.1 } }
            if keep.count == marks.count { break }
            marks = keep
        }
        return marks
    }

    static func only(_ line: U, _ marks: [M], _ kind: Kind) -> Bool {
        guard !marks.isEmpty else { return false }
        for (i, m) in marks.enumerated() where m.kind != kind || m.from != (i > 0 ? marks[i - 1].to : 0) { return false }
        return marks[marks.count - 1].to == line.count
    }

    static func sideOf(_ line: U, _ marks: [M], old: Bool) -> U {
        var s = U(), p = 0
        for m in marks { s += slice(line, p, m.from) + (old ? m.old : m.new); p = m.to }
        return s + slice(line, p)
    }

    /// A line as written (raw) and what it is in the old and the new words (nil: the line is not there).
    static func readLine(_ raw: U) -> Rec {
        let marks = scanLine(raw)
        let add = only(raw, marks, .add), del = !add && only(raw, marks, .del)
        return Rec(raw: raw, marks: marks, old: add ? nil : sideOf(raw, marks, old: true), new: del ? nil : sideOf(raw, marks, old: false))
    }

    // MARK: reading the markdown

    /// A fence line: (its character, how many), or nil. `closing`: nothing but spaces and tabs after the run.
    static func fenceRun(_ l: U, closing: Bool) -> (UInt16, Int, U)? {
        var i = 0
        while i < l.count && l[i] == 32 && i < 4 { i += 1 }
        if i > 3 || i >= l.count { return nil }
        let c = l[i]
        guard c == tick || c == 126 else { return nil }
        var j = i
        while j < l.count && l[j] == c { j += 1 }
        guard j - i >= 3 else { return nil }
        let rest = slice(l, j)
        if closing { if !rest.allSatisfy({ $0 == 32 || $0 == 9 }) { return nil } }
        else if rest.contains(where: { $0 == 13 || $0 == 0x2028 || $0 == 0x2029 }) { return nil }
        return (c, j - i, rest)
    }

    /// [first, last] line of each fenced code block (``` or ~~~, up to 3 spaces in; an unclosed one runs to the end).
    static func fences(_ lines: [U]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var i = 0
        while i < lines.count {
            guard let open = fenceRun(lines[i], closing: false), !(open.0 == tick && open.2.contains(tick)) else { i += 1; continue }
            var j = i + 1
            while j < lines.count {
                if let c = fenceRun(lines[j], closing: true), c.0 == open.0, c.1 >= open.1 { break }
                j += 1
            }
            out.append((i, min(j, lines.count - 1)))
            i = j + 1
        }
        return out
    }

    static func readDoc(_ md: U) -> [Rec] {
        let lines = split(md)
        var code = [Bool](repeating: false, count: lines.count)
        for (a, b) in fences(lines) where a <= b { for k in a...b { code[k] = true } }
        return lines.enumerated().map { i, raw in code[i] ? Rec(raw: raw, old: raw, new: raw, code: true) : readLine(raw) }
    }

    static func viewOf(_ recs: [Rec], old: Bool) -> U { join(recs.compactMap { old ? $0.old : $0.new }) }

    /// Every suggestion in the markdown, in order.
    public static func parse(_ md: String) -> [Mark] {
        var out: [Mark] = []
        var at = 0
        for r in readDoc(u(md)) {
            for m in r.marks {
                out.append(Mark(kind: m.kind, from: at + m.from, to: at + m.to, old: str(m.old), new: str(m.new), oldAt: at + m.oAt, newAt: at + m.nAt))
            }
            at += r.raw.count + 1
        }
        return out
    }

    /// The words with every suggestion applied (`old: false`) or rejected (`old: true`).
    public static func text(_ md: String, old: Bool = false) -> String { str(viewOf(readDoc(u(md)), old: old)) }
    public static func acceptAll(_ md: String) -> String { text(md, old: false) }
    public static func rejectAll(_ md: String) -> String { text(md, old: true) }

    // MARK: writing: markup that reads back as meant

    enum Part { case add, del, old, new }

    /// Text cut where it holds something that would end or break its markup (the cut goes inside that token, so no piece holds one).
    static func pieces(_ text: U, _ part: Part) -> [U] {
        var stops: [U]
        switch part {
        case .add: stops = [closeAdd]
        case .del: stops = [closeDel]
        case .old: stops = [arrow, closeSub]
        case .new: stops = [closeSub]
        }
        stops += [openAdd, openDel, openSub]
        var out: [U] = []
        var rest = text
        while true {
            var cut = -1
            for t in stops { let i = indexOf(rest, t); if i >= 0 && (cut < 0 || i < cut) { cut = i } }
            if cut < 0 { out.append(rest); return out }
            out.append(slice(rest, 0, cut + 1)); rest = slice(rest, cut + 1)
        }
    }

    static func adds(_ t: U) -> U { pieces(t, .add).reduce(into: U()) { $0 += openAdd + $1 + closeAdd } }
    static func dels(_ t: U) -> U { pieces(t, .del).reduce(into: U()) { $0 += openDel + $1 + closeDel } }
    static func subs(_ o: U, _ n: U) -> U {
        let a = pieces(o, .old), b = pieces(n, .new)
        var s = U()
        for i in 0..<max(a.count, b.count) { s += openSub + (i < a.count ? a[i] : []) + arrow + (i < b.count ? b[i] : []) + closeSub }
        return s
    }

    static func addRec(_ t: U) -> Rec { Rec(raw: adds(t), old: nil, new: t, fresh: true) }
    static func delRec(_ t: U) -> Rec { Rec(raw: dels(t), old: t, new: nil, fresh: true) }
    static func fits(_ r: Rec) -> Bool { let x = readLine(r.raw); return x.old == r.old && x.new == r.new }

    /// A line whose markup does not read as meant, written so it does: its marks kept where possible, else one substitution, else a
    /// deleted line and an added line.
    static func safeRecs(_ r: Rec) -> [Rec] {
        if let ro = r.old, let rn = r.new {
            var tries: [U] = []
            let x = readLine(r.raw), m = x.marks.first
            if let m, x.old == nil, ro.isEmpty, x.new == rn { tries.append(subs([], m.new) + slice(r.raw, m.to)) }
            if let m, x.new == nil, rn.isEmpty, x.old == ro { tries.append(subs(m.old, []) + slice(r.raw, m.to)) }
            if ro == rn { tries.append(ro) }
            tries.append(subs(ro, rn))
            for raw in tries { let c = Rec(raw: raw, old: ro, new: rn); if fits(c) { return [c] } }
            return [delRec(ro), addRec(rn)]
        }
        if let o = r.old { return [delRec(o)] }
        if let n = r.new { return [addRec(n)] }
        return []
    }

    /// Make the lines read back as meant: a fenced block holding a change is written out as deleted and added lines (markup in code is
    /// plain text), and a new line, or one that was code, is checked.
    static func finalize(_ input: [Rec]) -> [Rec] {
        var recs = input
        while true {
            let blocks = fences(recs.map(\.raw))
            var redo = false
            for (a, b) in blocks {
                let seg = Array(recs[a...b])
                if seg.contains(where: { $0.old != $0.raw || $0.new != $0.raw }) {
                    let repl = seg.compactMap { $0.old }.map(delRec) + seg.compactMap { $0.new }.map(addRec)
                    recs.replaceSubrange(a...b, with: repl)
                    redo = true
                    break
                }
            }
            if redo { continue }
            var code = [Bool](repeating: false, count: recs.count)
            for (a, b) in blocks where a <= b { for k in a...b { code[k] = true } }
            var i = recs.count - 1
            while i >= 0 {
                let r = recs[i]
                if code[i] || !(r.fresh || r.code) { i -= 1; continue }
                if fits(r) { recs[i] = Rec(raw: r.raw, old: r.old, new: r.new) } else { recs.replaceSubrange(i...i, with: safeRecs(r)) }
                i -= 1
            }
            return recs
        }
    }

    /// (a text that is one empty added or deleted line has no words on either side: it is the empty text)
    static func joinRaw(_ recs: [Rec]) -> U {
        let raw = join(finalize(recs).map(\.raw))
        return raw == u("{++++}") || raw == u("{----}") ? [] : raw
    }

    // MARK: a line from characters: each P (in both), D (old only) or A (new only)

    enum St: UInt8 { case P, D, A, X }

    static func serial(_ st: [St], _ ch: U) -> U {
        let anyP = st.contains(.P)
        var raw = U()
        var i = 0
        while i < st.count {
            var j = i
            if st[i] == .P {
                while j < st.count && st[j] == .P { j += 1 }
                raw += slice(ch, i, j)
            } else {
                var o = U(), n = U()
                while j < st.count && st[j] != .P { if st[j] == .D { o.append(ch[j]) } else { n.append(ch[j]) }; j += 1 }
                // a change to the same text is plain text; a line with no plain text stays a line of both words
                if o == n { raw += o } else if (!o.isEmpty && !n.isEmpty) || !anyP { raw += subs(o, n) } else if !n.isEmpty { raw += adds(n) } else { raw += dels(o) }
            }
            i = j
        }
        return raw
    }

    /// A change inside a code span takes in the whole span (markup inside a span would be plain text).
    static func widen(_ st: [St], _ ch: U) -> ([St], U) {
        var S = st, C = ch
        for _ in 0..<20 {
            var hit = [Bool](repeating: false, count: S.count)
            var any = false
            for side in [St.D, St.A] {
                var idx: [Int] = []
                var text = U()
                let skip: St = side == .D ? .A : .D
                for i in 0..<S.count where S[i] != skip { idx.append(i); text.append(C[i]) }
                for (a, b) in codeSpans(text) {
                    let lo = idx[a], hi = idx[b - 1]
                    var changed = false
                    var i = lo
                    while i <= hi && !changed { changed = S[i] != .P; i += 1 }
                    if changed { for i in lo...hi where S[i] == .P && !hit[i] { hit[i] = true; any = true } }
                }
            }
            if !any { break }
            var S2: [St] = [], C2 = U()
            for i in 0..<S.count { if hit[i] { S2 += [.D, .A]; C2 += [C[i], C[i]] } else { S2.append(S[i]); C2.append(C[i]) } }
            S = S2; C = C2
        }
        return (S, C)
    }

    static func pairLine(_ st: [St], _ ch: U) -> [Rec] {
        var o = U(), n = U()
        for i in 0..<st.count { if st[i] != .A { o.append(ch[i]) }; if st[i] != .D { n.append(ch[i]) } }
        var r = Rec(raw: serial(st, ch), old: o, new: n, fresh: true)
        if fits(r) { return [r] }
        let (S, C) = widen(st, ch)
        r = Rec(raw: serial(S, C), old: o, new: n, fresh: true)
        return fits(r) ? [r] : safeRecs(r)
    }

    /// Lines for a run of characters with their states (newlines too: a P newline ends a line of both, a D one an old line only, an A one
    /// a new line only). Within each run between P newlines, the old and new lines sharing the most text are paired up as lines of both
    /// words; the rest become whole deleted and added lines. whole: the run is the whole text, so an empty side has no lines at all.
    static func encodeStream(_ S: [St], _ C: U, whole: Bool, into out: inout [Rec]) {
        var blocks: [(Int, Int)] = []
        var a = 0
        for i in 0...S.count where i == S.count || (S[i] == .P && C[i] == nl) { blocks.append((a, i)); a = i + 1 }
        for (x, y) in blocks { encodeBlock(S, C, x, y, whole: whole && blocks.count == 1, into: &out) }
    }

    static func encodeBlock(_ S: [St], _ C: U, _ a: Int, _ b: Int, whole: Bool, into out: inout [Rec]) {
        let n = b - a
        var oAt = [Int](repeating: -1, count: n), nAt = [Int](repeating: -1, count: n)
        var oi = 0, ni = 0, oAny = false, nAny = false
        for i in a..<b {
            if C[i] == nl { if S[i] == .D { oi += 1; oAny = true } else { ni += 1; nAny = true }; continue }
            if S[i] != .A { oAt[i - a] = oi; oAny = true }
            if S[i] != .D { nAt[i - a] = ni; nAny = true }
        }
        let oN = whole && !oAny ? 0 : oi + 1, nN = whole && !nAny ? 0 : ni + 1
        var byO = [[Int]](repeating: [], count: oN), byN = [[Int]](repeating: [], count: nN)
        for k in 0..<n { if oAt[k] >= 0 { byO[oAt[k]].append(k) }; if nAt[k] >= 0 { byN[nAt[k]].append(k) } }
        // shared text between old line o and new line n, in order (both only go down)
        var pairs: [(Int, Int, Int)] = []
        for k in 0..<n {
            if S[a + k] != .P || C[a + k] == nl { continue }
            let w = isSpace(C[a + k]) ? 1 : 4
            if let last = pairs.last, last.0 == oAt[k], last.1 == nAt[k] { pairs[pairs.count - 1].2 += w } else { pairs.append((oAt[k], nAt[k], w)) }
        }
        var best = pairs.map { $0.2 }, prev = [Int](repeating: -1, count: pairs.count)
        var top = -1
        for i in 0..<pairs.count {
            var j = i - 1
            while j >= 0 {
                if pairs[j].0 < pairs[i].0 && pairs[j].1 < pairs[i].1 && best[j] + pairs[i].2 > best[i] { best[i] = best[j] + pairs[i].2; prev[i] = j }
                j -= 1
            }
            if top < 0 || best[i] > best[top] { top = i }
        }
        var chosen: [(Int, Int)] = []
        var i = top
        while i >= 0 { chosen.insert((pairs[i].0, pairs[i].1), at: 0); i = prev[i] }
        if chosen.isEmpty && oN == nN { for i in 0..<oN { chosen.append((i, i)) } }
        func text(_ list: [Int]) -> U { list.map { C[a + $0] } }
        var po = 0, pn = 0
        func rest(_ o: Int, _ w: Int) {
            while po < o { out.append(delRec(text(byO[po]))); po += 1 }
            while pn < w { out.append(addRec(text(byN[pn]))); pn += 1 }
        }
        for (o, w) in chosen {
            rest(o, w)
            let L = byO[o], R = byN[w]
            var st: [St] = [], ch = U()
            var x = 0, y = 0
            while x < L.count || y < R.count {
                if y >= R.count || (x < L.count && L[x] < R[y]) { ch.append(C[a + L[x]]); x += 1; st.append(.D) }
                else if x >= L.count || R[y] < L[x] { ch.append(C[a + R[y]]); y += 1; st.append(.A) }
                else { ch.append(C[a + L[x]]); x += 1; y += 1; st.append(.P) }
            }
            out += pairLine(st, ch)
            po = o + 1; pn = w + 1
        }
        rest(oN, nN)
    }

    // MARK: diffs

    enum Op { case E, DEL, INS }

    /// Myers' O(ND) diff of two int arrays, or nil past maxD differences.
    static func myers(_ A: [Int], _ B: [Int], _ maxD: Int) -> [Op]? {
        let n = A.count, m = B.count
        if n == 0 || m == 0 { return [Op](repeating: .DEL, count: n) + [Op](repeating: .INS, count: m) }
        let max = n + m, off = max + 1
        var V = [Int](repeating: 0, count: 2 * max + 3)
        var trace: [[Int]] = []
        var d = 0
        while d <= Swift.min(max, maxD) {
            trace.append(Array(V[(off - d - 1)..<(off + d + 2)]))
            var k = -d
            while k <= d {
                var x = k == -d || (k != d && V[off + k - 1] < V[off + k + 1]) ? V[off + k + 1] : V[off + k - 1] + 1
                var y = x - k
                while x < n && y < m && A[x] == B[y] { x += 1; y += 1 }
                V[off + k] = x
                if x >= n && y >= m { return backtrack(trace, d, n, m) }
                k += 2
            }
            d += 1
        }
        return nil
    }

    static func backtrack(_ trace: [[Int]], _ D: Int, _ n: Int, _ m: Int) -> [Op] {
        var ops: [Op] = []
        var x = n, y = m
        var d = D
        while d > 0 {
            let T = trace[d]
            func at(_ k: Int) -> Int { T[k + d + 1] }
            let k = x - y
            let down = k == -d || (k != d && at(k - 1) < at(k + 1))
            let pk = down ? k + 1 : k - 1, px = at(pk), py = px - pk
            while x > px && y > py { ops.append(.E); x -= 1; y -= 1 }
            ops.append(down ? .INS : .DEL)
            if down { y -= 1 } else { x -= 1 }
            d -= 1
        }
        while x > 0 && y > 0 { ops.append(.E); x -= 1; y -= 1 }
        return ops.reversed()
    }

    /// Steps between two lists: ops, and rough (too different to diff closely: the middle is all deleted then all added).
    static func diffSeq(_ X: [U], _ Y: [U], budget: Int = 40_000_000) -> (ops: [Op], rough: Bool) {
        var ids: [U: Int] = [:]
        func id(_ t: U) -> Int { if let v = ids[t] { return v }; let v = ids.count; ids[t] = v; return v }
        let A = X.map(id), B = Y.map(id)
        var p = 0
        while p < A.count && p < B.count && A[p] == B[p] { p += 1 }
        var s = 0
        while s < A.count - p && s < B.count - p && A[A.count - 1 - s] == B[B.count - 1 - s] { s += 1 }
        let a = Array(A[p..<(A.count - s)]), b = Array(B[p..<(B.count - s)])
        let maxD = min(2000, max(64, budget / (a.count + b.count + 1)))
        var mid = myers(a, b, maxD)
        let rough = mid == nil
        if mid == nil { mid = [Op](repeating: .DEL, count: a.count) + [Op](repeating: .INS, count: b.count) }
        return ([Op](repeating: .E, count: p) + mid! + [Op](repeating: .E, count: s), rough)
    }

    /// A changed run of lines between two lists of lines (to is exclusive).
    public struct Hunk: Equatable, Sendable { public var oldFrom, oldTo, newFrom, newTo: Int }

    static func lineHunks(_ a: [U], _ b: [U]) -> [Hunk] {
        let ops = diffSeq(a, b).ops
        var out: [Hunk] = []
        var i = 0, j = 0
        var h: Hunk?
        for op in ops {
            if op == .E { if let x = h { out.append(x); h = nil }; i += 1; j += 1; continue }
            if h == nil { h = Hunk(oldFrom: i, oldTo: i, newFrom: j, newTo: j) }
            if op == .DEL { i += 1; h!.oldTo = i } else { j += 1; h!.newTo = j }
        }
        if let x = h { out.append(x) }
        return out
    }

    public static func lineHunks(_ a: [String], _ b: [String]) -> [Hunk] { lineHunks(a.map(u), b.map(u)) }

    /// Words, runs of spaces, newlines and single other characters.
    static let token = try! NSRegularExpression(pattern: "\\n|[^\\S\\n]+|[\\p{L}\\p{M}\\p{N}_]+(?:['’][\\p{L}\\p{M}\\p{N}_]+)*|[\\s\\S]")

    static func tokens(_ s: U) -> [U] {
        let ns = str(s) as NSString
        return token.matches(in: ns as String, range: NSRange(location: 0, length: ns.length)).map { slice(s, $0.range.location, NSMaxRange($0.range)) }
    }

    static func put(_ S: inout [St], _ C: inout U, _ st: St, _ text: U) { for c in text { S.append(st); C.append(c) } }

    static func diffWords(_ x: U, _ y: U, _ S: inout [St], _ C: inout U) -> Bool {
        let X = tokens(x), Y = tokens(y)
        let (ops, rough) = diffSeq(X, Y)
        if rough { return false }
        var i = 0, j = 0
        for op in ops {
            switch op {
            case .E: put(&S, &C, .P, X[i]); i += 1; j += 1
            case .DEL: put(&S, &C, .D, X[i]); i += 1
            case .INS: put(&S, &C, .A, Y[j]); j += 1
            }
        }
        return true
    }

    /// Suggestion lines for old lines A becoming new lines B: line diff first, then words within the changed runs.
    static func critRecs(_ A: [U], _ B: [U]) -> [Rec] {
        var out: [Rec] = []
        var i = 0
        for h in lineHunks(A, B) {
            while i < h.oldFrom { out.append(Rec(raw: A[i], old: A[i], new: A[i], fresh: true)); i += 1 }
            let o = Array(A[h.oldFrom..<h.oldTo]), n = Array(B[h.newFrom..<h.newTo])
            if o.isEmpty { out += n.map(addRec) } else if n.isEmpty { out += o.map(delRec) } else {
                var S: [St] = [], C = U()
                if !diffWords(join(o) + [nl], join(n) + [nl], &S, &C) {
                    S = []; C = []
                    if o.count == n.count {
                        for k in 0..<o.count {
                            if !diffWords(o[k], n[k], &S, &C) { put(&S, &C, .D, o[k]); put(&S, &C, .A, n[k]) }
                            put(&S, &C, .P, [nl])
                        }
                    } else { put(&S, &C, .D, join(o)); put(&S, &C, .A, join(n)); put(&S, &C, .P, [nl]) }
                }
                S.removeLast(); C.removeLast() // the newline both runs end with
                encodeStream(S, C, whole: false, into: &out)
            }
            i = h.oldTo
        }
        while i < A.count { out.append(Rec(raw: A[i], old: A[i], new: A[i], fresh: true)); i += 1 }
        return out
    }

    static func splitLines(_ s: U) -> [U] { s.isEmpty ? [] : split(s) }

    /// b's markdown with its changes from a marked as suggestions: text(result, old: true) == a and text(result) == b for any a and b.
    public static func diff(_ a: String, _ b: String) -> String { str(joinRaw(critRecs(splitLines(u(a)), splitLines(u(b))))) }

    /// A piece of Bring them over's result: a line kept as written, or a clash (the new draft's lines with the old draft's as a suggestion).
    public enum Piece { case line(String); case change(old: [String], new: [String]) }

    /// Markdown from lines kept as written and suggested changes, as Bring them over writes a clash.
    public static func withSuggestions(_ parts: [Piece]) -> String {
        var recs: [Rec] = []
        for p in parts {
            switch p {
            case .line(let l): recs.append(Rec(raw: u(l), keep: true))
            case .change(let o, let n): recs += critRecs(o.map(u), n.map(u))
            }
        }
        var code = [Bool](repeating: false, count: recs.count)
        for (a, b) in fences(recs.map(\.raw)) where a <= b { for k in a...b { code[k] = true } }
        return str(joinRaw(recs.enumerated().map { i, r in !r.keep ? r : code[i] ? Rec(raw: r.raw, old: r.raw, new: r.raw, code: true) : readLine(r.raw) }))
    }

    // MARK: Apply and Reject one suggestion

    static func resolveAt(_ mdS: String, _ i: Int, accept: Bool) -> String {
        let md = u(mdS)
        var recs = readDoc(md)
        guard i >= 0 else { return mdS }
        var li = 0, n = i
        while li < recs.count && n >= recs[li].marks.count { n -= recs[li].marks.count; li += 1 }
        if li >= recs.count { return mdS }
        let r = recs[li], m = r.marks[n], to = accept ? m.new : m.old, left = r.marks.count - 1
        func side(_ old: Bool) -> U {
            var t = U(), p = 0
            for (k, x) in r.marks.enumerated() { t += slice(r.raw, p, x.from) + (k == n ? to : (old ? x.old : x.new)); p = x.to }
            return t + slice(r.raw, p)
        }
        let kind: Kind? = r.old == nil ? .add : r.new == nil ? .del : nil
        let raw = slice(r.raw, 0, m.from) + to + slice(r.raw, m.to)
        // an added line rejected or a deleted line accepted goes, line break and all, once its last mark goes
        if (kind == .add && !accept) || (kind == .del && accept) {
            if left == 0 { recs.remove(at: li) } else {
                recs[li] = Rec(raw: raw, old: kind == .del ? side(true) : nil, new: kind == .add ? side(false) : nil, fresh: true)
            }
        } else { recs[li] = Rec(raw: raw, old: side(true), new: side(false), fresh: true) }
        return str(joinRaw(recs))
    }

    /// Apply (accept) or Reject suggestion i (its index in `parse`'s list); the other suggestions stay as they are.
    public static func accept(_ md: String, _ i: Int) -> String { resolveAt(md, i, accept: true) }
    public static func reject(_ md: String, _ i: Int) -> String { resolveAt(md, i, accept: false) }

    // MARK: typing in Review mode

    /// The offset in md of each character of the new words (a line break: the one just before the next line of the new words).
    public static func newOffsets(_ md: String) -> [Int] { newOffsets(u(md)) }

    static func newOffsets(_ md: U) -> [Int] {
        var map: [Int] = []
        var base = 0, first = true
        for r in readDoc(md) {
            if r.new != nil {
                if !first { map.append(base - 1) }
                first = false
                var p = 0
                for m in r.marks {
                    for k in p..<max(p, m.from) { map.append(base + k) }
                    for k in 0..<m.new.count { map.append(base + m.nAt + k) }
                    p = m.to
                }
                for k in p..<max(p, r.raw.count) { map.append(base + k) }
            }
            base += r.raw.count + 1
        }
        return map
    }

    /// What a typed edit does in Review mode: md[from..<to] (UTF-16) is replaced by `insert`. Typed text is added (joining the add it
    /// touches); plain text deleted is marked deleted (joining the deletion it touches); added text deleted really goes; typing over plain
    /// text makes a substitution; typing inside deleted text is ignored and the caret moves past it; a line break typed is a suggested line
    /// break (whole added lines). `forward`: the Delete key (the caret goes after deleted text). Only the lines the edit touches change.
    public static func edit(_ mdS: String, from: Int, to: Int, insert insS: String = "", forward fwd: Bool = false) -> (md: String, cursor: Int) {
        let md = u(mdS), insert = u(insS)
        func clamp(_ v: Int) -> Int { max(0, min(md.count, v)) }
        var f = clamp(from), t = clamp(to)
        if t < f { swap(&f, &t) }
        let recs = readDoc(md), n = recs.count
        var starts: [Int] = []
        var acc = 0
        for r in recs { starts.append(acc); acc += r.raw.count + 1 }
        func lineOf(_ p: Int) -> Int {
            var lo = 0, hi = n - 1
            while lo < hi { let mid = (lo + hi + 1) >> 1; if starts[mid] <= p { lo = mid } else { hi = mid - 1 } }
            return lo
        }
        // is the line break after line i in the old / new words (each line there but the first has one before it)
        var oSeen: [Bool] = [], nSeen: [Bool] = []
        var o = false, w = false
        for r in recs { o = o || r.old != nil; w = w || r.new != nil; oSeen.append(o); nSeen.append(w) }
        func brO(_ i: Int) -> Bool { recs[i + 1].old != nil && oSeen[i] }
        func brN(_ i: Int) -> Bool { recs[i + 1].new != nil && nSeen[i] }
        var r0 = lineOf(f), r1 = lineOf(t)
        while r0 > 0 && !(brO(r0 - 1) && brN(r0 - 1)) { r0 -= 1 }
        while r1 < n - 1 && !(brO(r1) && brN(r1)) { r1 += 1 }
        // the touched lines as characters: state, character, offset in md
        var S: [St] = [], C = U(), R: [Int] = []
        func push(_ s: St, _ c: UInt16, _ at: Int) { S.append(s); C.append(c); R.append(at) }
        for i in r0...r1 {
            let r = recs[i], base = starts[i]
            var p = 0
            for m in r.marks {
                for k in p..<max(p, m.from) { push(.P, r.raw[k], base + k) }
                for k in 0..<m.old.count { push(.D, m.old[k], base + m.oAt + k) }
                for k in 0..<m.new.count { push(.A, m.new[k], base + m.nAt + k) }
                p = m.to
            }
            for k in p..<max(p, r.raw.count) { push(.P, r.raw[k], base + k) }
            if i < r1 { let bo = brO(i), bn = brN(i); push(bo && bn ? .P : bo ? .D : bn ? .A : .X, nl, base + r.raw.count) }
        }
        func bound(_ p: Int) -> Int {
            var lo = 0, hi = R.count
            while lo < hi { let mid = (lo + hi) >> 1; if R[mid] < p { lo = mid + 1 } else { hi = mid } }
            return lo
        }
        var af = bound(f), aT = bound(t)
        if t > f && af == aT { // only markup was selected: the character next to it
            if fwd {
                var j = aT
                while j < S.count && S[j] == .X { j += 1 }
                if j < S.count { af = j; aT = j + 1 }
            } else {
                var j = af - 1
                while j >= 0 && S[j] == .X { j -= 1 }
                if j >= 0 { af = j; aT = j + 1 }
            }
        }
        func seen(_ arr: [St], _ end: Int) -> Int { var c = 0; for i in 0..<max(0, end) where arr[i] == .P || arr[i] == .A { c += 1 }; return c }
        let before = recs[0..<r0].compactMap(\.new)
        let pre = before.isEmpty ? 0 : join(before).count + 1
        let oldView = viewOf(recs, old: true), newView = viewOf(recs, old: false)
        let nf = pre + seen(S, af), nt = pre + seen(S, aT)
        // the edit: plain text in the range becomes deleted, added text goes, deleted text stays
        var S2: [St] = [], C2 = U()
        var af2 = 0, at2 = 0, changed = false
        for i in 0...S.count {
            if i == af { af2 = S2.count }
            if i == aT { at2 = S2.count }
            if i == S.count { break }
            if i >= af && i < aT && (S[i] == .P || S[i] == .A) { changed = true; if S[i] == .P { S2.append(.D); C2.append(C[i]) }; continue }
            S2.append(S[i]); C2.append(C[i])
        }
        var pos = at2
        var mode = "", k = 0, ignored = false
        if !insert.isEmpty {
            if pos > 0 && pos < S2.count && S2[pos - 1] == .D && S2[pos] == .D && C2[pos - 1] != nl && C2[pos] != nl { // inside deleted text
                if t == f { ignored = true } else { while pos < S2.count && S2[pos] == .D && C2[pos] != nl { pos += 1 } }
            }
        }
        if !insert.isEmpty && !ignored {
            for (i, c) in insert.enumerated() { S2.insert(.A, at: pos + i); C2.insert(c, at: pos + i) }
            k = pre + seen(S2, pos + insert.count); mode = "after"
        } else if ignored { k = pre + seen(S2, pos); mode = "past" } else { k = pre + seen(S2, af2); mode = fwd ? "past" : "before" }
        var md2 = md
        if changed || (!insert.isEmpty && !ignored) {
            var S3: [St] = [], C3 = U()
            for i in 0..<S2.count where S2[i] != .X { S3.append(S2[i]); C3.append(C2[i]) }
            var mid: [Rec] = []
            encodeStream(S3, C3, whole: r0 == 0 && r1 == n - 1, into: &mid)
            let out = finalize(Array(recs[0..<r0]) + mid + Array(recs[(r1 + 1)...]))
            let want = slice(newView, 0, nf) + insert + slice(newView, nt)
            md2 = join(out.map(\.raw))
            if viewOf(out, old: true) != oldView || viewOf(out, old: false) != want { md2 = joinRaw(critRecs(splitLines(oldView), splitLines(want))) } // a safety net
        }
        let map = newOffsets(md2)
        let cursor = mode == "past" ? (k < map.count ? map[k] : md2.count) : k > 0 ? (k - 1 < map.count ? map[k - 1] + 1 : md2.count) : 0
        return (str(md2), cursor)
    }
}
