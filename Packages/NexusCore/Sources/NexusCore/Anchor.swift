import Foundation

/// Marks that hold on to words (nexus docs/data-format.md "Marks"; the same as the laptop's `renderer/src/board/anchor.js`, and both
/// pass one test table, `anchor-cases.json`). A mark remembers the words it sits on and a little of what is around them:
/// `{q: the words, pre: about 20 characters before, post: about 20 after, i: where q started}`. After edits here or on the laptop the
/// words are found again: the copy of q whose surroundings match best, nearest to i. If q itself was edited (a word fixed) but what
/// was around it is still there, the mark holds on to whatever is between. Not found: the mark is a ghost near where it was.
/// Positions are UTF-16 offsets into the block's markdown, as JavaScript counts them.
public struct WordAnchor: Codable, Equatable, Sendable {
    public var q: String
    public var pre: String
    public var post: String
    public var i: Int

    public init(q: String, pre: String, post: String, i: Int) {
        self.q = q; self.pre = pre; self.post = post; self.i = i
    }

    enum CodingKeys: String, CodingKey { case q, pre, post, i }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        q = (try? c.decodeIfPresent(String.self, forKey: .q)) ?? ""
        pre = (try? c.decodeIfPresent(String.self, forKey: .pre)) ?? ""
        post = (try? c.decodeIfPresent(String.self, forKey: .post)) ?? ""
        i = (try? c.decodeIfPresent(Int.self, forKey: .i)) ?? Int((try? c.decodeIfPresent(Double.self, forKey: .i)) ?? 0)
    }

    /// As it goes in a mark item's "at".
    public var json: JSONValue { .object([("q", .string(q)), ("pre", .string(pre)), ("post", .string(post)), ("i", .number(Double(i)))]) }
    public init?(_ v: JSONValue?) {
        guard let v, v["q"] != nil else { return nil }
        self.init(q: v["q"]?.string ?? "", pre: v["pre"]?.string ?? "", post: v["post"]?.string ?? "", i: Int(v["i"]?.number ?? 0))
    }
}

public struct AnchorMatch: Codable, Equatable, Sendable {
    public var from: Int
    public var to: Int
    /// "exact" (the words as they were) or "between" (edited words, held by what is around them).
    public var how: String
    public init(from: Int, to: Int, how: String) { self.from = from; self.to = to; self.how = how }
}

public enum Anchor {
    public static let context = 20

    typealias U = [UInt16]
    static func units(_ s: String) -> U { Array(s.utf16) }
    static func string(_ u: ArraySlice<UInt16>) -> String { String(decoding: Array(u), as: UTF16.self) }

    /// The anchor for the words text[from ..< to] (UTF-16 offsets).
    public static func make(_ text: String, from: Int, to: Int) -> WordAnchor {
        let t = units(text)
        let f = max(0, min(from, t.count)), e = max(f, min(to, t.count))
        return WordAnchor(q: string(t[f..<e]), pre: string(t[max(0, f - context)..<f]), post: string(t[e..<min(t.count, e + context)]), i: f)
    }

    static func indexes(_ t: U, _ q: U, from start: Int = 0) -> [Int] {
        guard !q.isEmpty, q.count <= t.count else { return [] }
        var out: [Int] = []
        var k = max(0, start)
        while k + q.count <= t.count {
            if t[k] == q[0] && Array(t[k..<(k + q.count)]) == q { out.append(k) }
            k += 1
        }
        return out
    }
    static func firstIndex(_ t: U, _ q: U, from start: Int) -> Int? {
        guard !q.isEmpty else { return start <= t.count ? start : nil }
        var k = max(0, start)
        while k + q.count <= t.count { if t[k] == q[0] && Array(t[k..<(k + q.count)]) == q { return k }; k += 1 }
        return nil
    }
    static func tailMatch(_ a: ArraySlice<UInt16>, _ b: U) -> Int {
        let a = Array(a); var n = 0
        while n < a.count && n < b.count && a[a.count - 1 - n] == b[b.count - 1 - n] { n += 1 }
        return n
    }
    static func headMatch(_ a: ArraySlice<UInt16>, _ b: U) -> Int {
        let a = Array(a); var n = 0
        while n < a.count && n < b.count && a[n] == b[n] { n += 1 }
        return n
    }

    /// How alike two pieces of text are, 0 to 1 (pairs of letters in common, ignoring case: Dice's coefficient).
    public static func similar(_ a: String, _ b: String) -> Double {
        let x = units(a.lowercased()), y = units(b.lowercased())
        if x == y { return 1 }
        if x.count < 2 || y.count < 2 { return 0 }
        var pairs: [UInt32: Int] = [:]
        for k in 0..<(x.count - 1) { pairs[UInt32(x[k]) << 16 | UInt32(x[k + 1]), default: 0] += 1 }
        var both = 0
        for k in 0..<(y.count - 1) {
            let p = UInt32(y[k]) << 16 | UInt32(y[k + 1])
            if let n = pairs[p], n > 0 { both += 1; pairs[p] = n - 1 }
        }
        return Double(2 * both) / Double(x.count - 1 + y.count - 1)
    }

    /// The words again, or nil: a ghost.
    public static func find(_ text: String, _ at: WordAnchor) -> AnchorMatch? {
        let t = units(text), q = units(at.q), pre = units(at.pre), post = units(at.post), hint = at.i
        if !q.isEmpty {
            var best: (from: Int, score: Int)?
            for k in indexes(t, q) {
                let ctx = tailMatch(t[max(0, k - pre.count)..<k], pre) + headMatch(t[(k + q.count)..<min(t.count, k + q.count + post.count)], post)
                let score = ctx * 1000 - abs(k - hint)
                if best == nil || score > best!.score { best = (k, score) }
            }
            if let b = best { return AnchorMatch(from: b.from, to: b.from + q.count, how: "exact") }
        }
        if pre.count >= 4 && post.count >= 4 {
            let room = max(40, q.count * 2 + 20)
            var best: (from: Int, to: Int, score: Int)?
            for a in indexes(t, pre) {
                let from = a + pre.count
                guard let b = firstIndex(t, post, from: from), b - from <= room else { continue }
                if b <= from || similar(at.q, string(t[from..<b])) < 0.5 { continue }
                let score = -abs(from - hint)
                if best == nil || score > best!.score { best = (from, b, score) }
            }
            if let b = best { return AnchorMatch(from: b.from, to: b.to, how: "between") }
        }
        return nil
    }

    /// Where a ghost waits: the start of the line nearest to where its words were.
    public static func ghostAt(_ text: String, _ at: WordAnchor) -> Int {
        let t = units(text)
        let i = max(0, min(t.count, at.i))
        var k = i - 1
        while k >= 0 && t[k] != 10 { k -= 1 }
        return k + 1
    }

    /// The anchor brought up to date after its words were found again (or as it was: a ghost, or nothing moved).
    public static func refresh(_ text: String, _ at: WordAnchor) -> WordAnchor {
        guard let f = find(text, at) else { return at }
        return make(text, from: f.from, to: f.to)
    }
}
