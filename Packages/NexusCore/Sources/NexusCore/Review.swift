import Foundation

/// One Review mode suggestion in a block's words (CriticMarkup): `{++added++}`, `{--deleted--}` or `{~~old~>new~~}`.
public struct Suggestion: Equatable, Sendable {
    /// The whole suggestion, marks included (UTF-16).
    public var range: NSRange
    /// The words it takes out (nil: only adds).
    public var old: String?
    /// The words it puts in (nil: only takes out).
    public var new: String?
    /// Where the added words are (inside the marks), when it adds.
    public var added: NSRange?
    /// Where the taken-out words are, when it takes out.
    public var removed: NSRange?
}

/// Review mode (a block's `review`): typing suggests instead of changing. New words go in as `{++…++}`, words taken out stay as
/// `{--…--}`, words typed over become `{~~old~>new~~}`; Accept and Reject rewrite a suggestion into plain words.
public enum Review {
    public static func suggestions(_ text: String) -> [Suggestion] {
        let s = text as NSString
        var out: [Suggestion] = []
        var p = 0
        func find(_ needle: String, from: Int) -> Int? {
            let r = s.range(of: needle, range: NSRange(location: from, length: s.length - from))
            return r.location == NSNotFound ? nil : r.location
        }
        while p < s.length {
            let r = s.range(of: "{", range: NSRange(location: p, length: s.length - p))
            guard r.location != NSNotFound else { break }
            let a = r.location
            guard a + 3 <= s.length else { break }
            let open = s.substring(with: NSRange(location: a, length: 3))
            switch open {
            case "{++":
                if let c = find("++}", from: a + 3) {
                    let inner = NSRange(location: a + 3, length: c - a - 3)
                    out.append(Suggestion(range: NSRange(location: a, length: c + 3 - a), old: nil, new: s.substring(with: inner), added: inner, removed: nil))
                    p = c + 3
                    continue
                }
            case "{--":
                if let c = find("--}", from: a + 3) {
                    let inner = NSRange(location: a + 3, length: c - a - 3)
                    out.append(Suggestion(range: NSRange(location: a, length: c + 3 - a), old: s.substring(with: inner), new: nil, added: nil, removed: inner))
                    p = c + 3
                    continue
                }
            case "{~~":
                if let m = find("~>", from: a + 3), let c = find("~~}", from: m + 2) {
                    let o = NSRange(location: a + 3, length: m - a - 3), n = NSRange(location: m + 2, length: c - m - 2)
                    out.append(Suggestion(range: NSRange(location: a, length: c + 3 - a), old: s.substring(with: o), new: s.substring(with: n), added: n, removed: o))
                    p = c + 3
                    continue
                }
            default:
                break
            }
            p = a + 1
        }
        return out
    }

    /// The suggestion at a caret or touching a selection.
    public static func at(_ text: String, _ sel: NSRange) -> Suggestion? {
        suggestions(text).first { NSLocationInRange(sel.location, $0.range) || sel.location == NSMaxRange($0.range) && sel.length == 0
            || (sel.length > 0 && NSIntersectionRange($0.range, sel).length > 0) }
    }

    public static func accept(_ text: String, _ s: Suggestion) -> MDEdit {
        let t = (text as NSString).replacingCharacters(in: s.range, with: s.new ?? "")
        return MDEdit(t, NSRange(location: s.range.location + ((s.new ?? "") as NSString).length, length: 0))
    }

    public static func reject(_ text: String, _ s: Suggestion) -> MDEdit {
        let t = (text as NSString).replacingCharacters(in: s.range, with: s.old ?? "")
        return MDEdit(t, NSRange(location: s.range.location + ((s.old ?? "") as NSString).length, length: 0))
    }

    public static func all(_ text: String, accept: Bool) -> String {
        var t = text
        for s in suggestions(text).reversed() { t = accept ? self.accept(t, s).text : reject(t, s).text }
        return t
    }

    /// Typing in Review mode: what replacing `range` with `typed` does to the words. Inside words already suggested (`{++…++}`) it
    /// is plain typing; anywhere else it becomes a suggestion. Taking out words next to a `{--…--}` joins it.
    public static func type(_ text: String, range: NSRange, with typed: String) -> MDEdit {
        let s = text as NSString
        let list = suggestions(text)
        let typedLen = (typed as NSString).length
        // inside the added words of a suggestion: plain typing (and an emptied {++ ++} goes)
        if let sug = list.first(where: { $0.added.map { range.location >= $0.location && NSMaxRange(range) <= NSMaxRange($0) } ?? false }),
           let add = sug.added {
            let t = s.replacingCharacters(in: range, with: typed)
            if sug.old == nil, add.length - range.length + typedLen == 0 {
                let gone = (t as NSString).replacingCharacters(in: NSRange(location: sug.range.location, length: 6), with: "")
                return MDEdit(gone, NSRange(location: sug.range.location, length: 0))
            }
            return MDEdit(t, NSRange(location: range.location + typedLen, length: 0))
        }
        // touching a suggestion's marks or taken-out words: don't change it, step past it
        if let sug = list.first(where: { NSIntersectionRange($0.range, range).length > 0 }) {
            if typed.isEmpty { return MDEdit(text, NSRange(location: sug.range.location, length: 0)) }
            let at = range.location <= sug.range.location ? sug.range.location : NSMaxRange(sug.range)
            let ins = "{++\(typed)++}"
            return MDEdit(s.replacingCharacters(in: NSRange(location: at, length: 0), with: ins), NSRange(location: at + 3 + typedLen, length: 0))
        }
        let old = s.substring(with: range)
        if old.isEmpty {
            guard typedLen > 0 else { return MDEdit(text, range) }
            return MDEdit(s.replacingCharacters(in: range, with: "{++\(typed)++}"), NSRange(location: range.location + 3 + typedLen, length: 0))
        }
        if typed.isEmpty {
            // join a deletion right after or right before
            if let next = list.first(where: { $0.range.location == NSMaxRange(range) && $0.new == nil }), let r = next.removed {
                let joined = "{--" + old + s.substring(with: r) + "--}"
                let span = NSRange(location: range.location, length: NSMaxRange(next.range) - range.location)
                return MDEdit(s.replacingCharacters(in: span, with: joined), NSRange(location: range.location, length: 0))
            }
            if let prev = list.first(where: { NSMaxRange($0.range) == range.location && $0.new == nil }), let r = prev.removed {
                let joined = "{--" + s.substring(with: r) + old + "--}"
                let span = NSRange(location: prev.range.location, length: NSMaxRange(range) - prev.range.location)
                return MDEdit(s.replacingCharacters(in: span, with: joined), NSRange(location: prev.range.location, length: 0))
            }
            return MDEdit(s.replacingCharacters(in: range, with: "{--\(old)--}"), NSRange(location: range.location, length: 0))
        }
        let sub = "{~~\(old)~>\(typed)~~}"
        return MDEdit(s.replacingCharacters(in: range, with: sub), NSRange(location: range.location + 3 + (old as NSString).length + 2 + typedLen, length: 0))
    }
}
