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

/// Review mode (a block's `review`): typing suggests instead of changing. The rules are the laptop's (Critic, a port of its critic.js):
/// new words go in as `{++…++}`, words taken out stay as `{--…--}`, words typed over become `{~~old~>new~~}`, a line break typed is a
/// suggested line break, and markup never spans a line. Accept and Reject rewrite one suggestion into plain words.
public enum Review {
    public static func suggestions(_ text: String) -> [Suggestion] {
        Critic.parse(text).map { m in
            let n = (m.new as NSString).length, o = (m.old as NSString).length
            return Suggestion(range: NSRange(location: m.from, length: m.to - m.from),
                              old: m.kind == .add ? nil : m.old, new: m.kind == .del ? nil : m.new,
                              added: m.kind == .del ? nil : NSRange(location: m.newAt, length: n),
                              removed: m.kind == .add ? nil : NSRange(location: m.oldAt, length: o))
        }
    }

    /// The suggestion at a caret or touching a selection.
    public static func at(_ text: String, _ sel: NSRange) -> Suggestion? {
        suggestions(text).first { NSLocationInRange(sel.location, $0.range) || sel.location == NSMaxRange($0.range) && sel.length == 0
            || (sel.length > 0 && NSIntersectionRange($0.range, sel).length > 0) }
    }

    static func resolve(_ text: String, _ s: Suggestion, accept: Bool) -> MDEdit {
        guard let i = suggestions(text).firstIndex(of: s) else { return MDEdit(text, NSRange(location: s.range.location, length: 0)) }
        let t = accept ? Critic.accept(text, i) : Critic.reject(text, i)
        let put = ((accept ? s.new : s.old) ?? "") as NSString
        return MDEdit(t, NSRange(location: min(s.range.location + put.length, (t as NSString).length), length: 0))
    }

    public static func accept(_ text: String, _ s: Suggestion) -> MDEdit { resolve(text, s, accept: true) }
    public static func reject(_ text: String, _ s: Suggestion) -> MDEdit { resolve(text, s, accept: false) }

    public static func all(_ text: String, accept: Bool) -> String { accept ? Critic.acceptAll(text) : Critic.rejectAll(text) }

    /// Typing in Review mode: what replacing `range` with `typed` does to the words (`forward`: the Delete key, so the caret goes after
    /// the words it marks deleted).
    public static func type(_ text: String, range: NSRange, with typed: String, forward: Bool = false) -> MDEdit {
        let r = Critic.edit(text, from: range.location, to: NSMaxRange(range), insert: typed, forward: forward)
        return MDEdit(r.md, NSRange(location: r.cursor, length: 0))
    }
}
