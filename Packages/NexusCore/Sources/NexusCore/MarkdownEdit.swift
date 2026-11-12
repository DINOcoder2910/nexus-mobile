import Foundation

/// A change to a typed block's markdown: the new text and where the selection goes (UTF-16 units).
public struct MDEdit: Equatable {
    public var text: String
    public var selection: NSRange
    public init(_ text: String, _ selection: NSRange) {
        self.text = text
        self.selection = selection
    }
}

/// A line's style in the Styles menu (the laptop's board text bar): Title "# ", Heading 1 to 3 "## " to "#### ", Body, Quote "> ",
/// Code (a ``` fence round the lines). A "#####" or deeper line reads as Heading 3.
public enum BlockStyle: String, CaseIterable, Equatable {
    case title, h1, h2, h3, body, quote, code

    public var label: String {
        switch self {
        case .title: return "Title"
        case .h1: return "Heading 1"
        case .h2: return "Heading 2"
        case .h3: return "Heading 3"
        case .body: return "Body"
        case .quote: return "Quote"
        case .code: return "Code"
        }
    }

    /// The heading prefix's number of #, for the heading styles.
    public var hashes: Int? {
        switch self {
        case .title: return 1
        case .h1: return 2
        case .h2: return 3
        case .h3: return 4
        default: return nil
        }
    }

    /// The style of a heading with this many #.
    public static func heading(_ hashes: Int) -> BlockStyle {
        switch hashes {
        case 1: return .title
        case 2: return .h1
        case 3: return .h2
        default: return .h3
        }
    }
}

/// The edits the formatting bar and the keys make (the laptop's editor.js `wrapSelection`, `toggleLinePrefix`, `setHeading`, and
/// lists that carry on). Pure: text in, text and selection out.
public enum MarkdownEdit {
    static func ns(_ s: String) -> NSString { s as NSString }

    /// Bold, italic, strike, code, highlight, underline: wrap the selection in the marks, or take them off when it already has them
    /// (just outside it, or as its own first and last characters). An empty selection gets the pair with the caret between.
    public static func wrap(_ text: String, _ sel: NSRange, _ left: String, _ right: String? = nil) -> MDEdit {
        let right = right ?? left
        let t = ns(text)
        let l = (left as NSString).length, r = (right as NSString).length
        let from = sel.location, to = sel.location + sel.length
        let inner = t.substring(with: sel)
        let before = from >= l ? t.substring(with: NSRange(location: from - l, length: l)) : ""
        let after = to + r <= t.length ? t.substring(with: NSRange(location: to, length: r)) : ""
        // one star of a longer run (**bold**) is not "already italic"
        let single = l == 1
        let outerL = single && from >= 2 ? t.substring(with: NSRange(location: from - 2, length: 1)) : ""
        let outerR = single && to + 2 <= t.length ? t.substring(with: NSRange(location: to + 1, length: 1)) : ""
        let partOfRun = single && (outerL == left || outerR == right)
        if before == left, after == right, !partOfRun {
            let m = NSMutableString(string: text)
            m.deleteCharacters(in: NSRange(location: to, length: r))
            m.deleteCharacters(in: NSRange(location: from - l, length: l))
            return MDEdit(m as String, NSRange(location: from - l, length: sel.length))
        }
        let innerNS = inner as NSString
        let innerRun = single && innerNS.length >= 2
            && (innerNS.substring(with: NSRange(location: 1, length: 1)) == left
                || innerNS.substring(with: NSRange(location: innerNS.length - 2, length: 1)) == right)
        if innerNS.length >= l + r, inner.hasPrefix(left), inner.hasSuffix(right), !innerRun {
            let stripped = innerNS.substring(with: NSRange(location: l, length: innerNS.length - l - r))
            let m = NSMutableString(string: text)
            m.replaceCharacters(in: sel, with: stripped)
            return MDEdit(m as String, NSRange(location: from, length: (stripped as NSString).length))
        }
        let m = NSMutableString(string: text)
        m.replaceCharacters(in: sel, with: left + inner + right)
        if sel.length == 0 { return MDEdit(m as String, NSRange(location: from + l, length: 0)) }
        return MDEdit(m as String, NSRange(location: from, length: sel.length + l + r))
    }

    /// A highlight in one of the five colours: yellow is `==x==`, the others `<mark data-c="green">x</mark>`.
    public static func highlight(_ text: String, _ sel: NSRange, color: String) -> MDEdit {
        if color == "yellow" { return wrap(text, sel, "==") }
        return wrap(text, sel, "<mark data-c=\"\(color)\">", "</mark>")
    }

    /// A text colour by name (`<span data-c="red">x</span>`).
    public static func textColor(_ text: String, _ sel: NSRange, color: String) -> MDEdit {
        wrap(text, sel, "<span data-c=\"\(color)\">", "</span>")
    }

    /// Ctrl+K: `[selection]()` with the caret inside the brackets of the address.
    public static func link(_ text: String, _ sel: NSRange) -> MDEdit {
        let t = ns(text)
        let words = t.substring(with: sel)
        let m = NSMutableString(string: text)
        m.replaceCharacters(in: sel, with: "[\(words)]()")
        return MDEdit(m as String, NSRange(location: sel.location + (words as NSString).length + 3, length: 0))
    }

    static func lineStart(_ t: NSString, _ i: Int) -> Int {
        var p = min(max(0, i), t.length)
        while p > 0, t.character(at: p - 1) != 10 { p -= 1 }
        return p
    }

    static func lineEnd(_ t: NSString, _ i: Int) -> Int {
        var p = min(max(0, i), t.length)
        while p < t.length, t.character(at: p) != 10 { p += 1 }
        return p
    }

    /// The lines the selection touches, without their newlines (the line the selection ends on counts, as on the laptop).
    static func lineRanges(_ t: NSString, _ sel: NSRange) -> [NSRange] {
        var out: [NSRange] = []
        let from = min(sel.location, t.length)
        let to = min(sel.location + sel.length, t.length)
        var p = lineStart(t, from)
        while true {
            let e = lineEnd(t, p)
            out.append(NSRange(location: p, length: e - p))
            if e >= to || e >= t.length { break }
            p = e + 1
        }
        return out
    }

    /// Changes several lines at once, from the last up so the earlier places stay right; the selection follows.
    static func apply(_ text: String, _ sel: NSRange, _ changes: [(NSRange, String)]) -> MDEdit {
        let m = NSMutableString(string: text)
        var a = sel.location, b = sel.location + sel.length
        for (range, insert) in changes.sorted(by: { $0.0.location > $1.0.location }) {
            m.replaceCharacters(in: range, with: insert)
            let delta = (insert as NSString).length - range.length
            let end = range.location + range.length
            if a >= end { a += delta } else if a > range.location { a = max(range.location, a + delta) }
            if b >= end { b += delta } else if b > range.location { b = max(range.location, b + delta) }
        }
        a = max(0, min(a, m.length)); b = max(a, min(b, m.length))
        return MDEdit(m as String, NSRange(location: a, length: b - a))
    }

    /// Lists and quotes: each line the selection touches gets the prefix, or loses it if it has it (the laptop's way: each line is
    /// toggled on its own). A list line that has another list mark swaps it, so a bullet becomes a checklist item.
    public static func toggleLinePrefix(_ text: String, _ sel: NSRange, _ prefix: String) -> MDEdit {
        let t = ns(text)
        var changes: [(NSRange, String)] = []
        let plen = (prefix as NSString).length
        for line in lineRanges(t, sel) {
            let s = t.substring(with: line)
            let existing = listPrefix(s)
            if isListPrefix(prefix), existing > 0 {
                let indent = leadingSpaces(s)
                let range = NSRange(location: line.location + indent, length: existing)
                let mark = t.substring(with: range)
                // the same kind of list comes off; another kind swaps, so a bullet becomes a checklist item
                changes.append((range, listKind(mark) == prefix ? "" : prefix))
            } else if s.hasPrefix(prefix) {
                changes.append((NSRange(location: line.location, length: plen), ""))
            } else {
                changes.append((NSRange(location: line.location, length: 0), prefix))
            }
        }
        return apply(text, sel, changes)
    }

    static func leadingSpaces(_ s: String) -> Int {
        var n = 0
        for c in s.utf16 { if c == 32 || c == 9 { n += 1 } else { break } }
        return n
    }

    static func isListPrefix(_ p: String) -> Bool { p == "- " || p == "- [ ] " || p == "1. " }

    /// Which of the three list kinds a mark is, as its plain prefix.
    static func listKind(_ mark: String) -> String {
        if mark.contains("[") { return "- [ ] " }
        if let c = mark.unicodeScalars.first, c.value >= 48, c.value <= 57 { return "1. " }
        return "- "
    }

    /// The length of a list item's mark (after its indent): "- ", "- [ ] ", "12. ", "1. [x] ", or 0.
    public static func listPrefix(_ s: String) -> Int {
        let u = Array(s.utf16)
        var p = leadingSpaces(s)
        let start = p
        if p < u.count, u[p] == 45 || u[p] == 42 || u[p] == 43 {
            p += 1
        } else {
            var d = p
            while d < u.count, u[d] >= 48, u[d] <= 57, d - p < 9 { d += 1 }
            guard d > p, d < u.count, u[d] == 46 || u[d] == 41 else { return 0 }
            p = d + 1
        }
        guard p < u.count, u[p] == 32 else { return p == u.count ? p - start : 0 }
        p += 1
        if p + 3 <= u.count, u[p] == 91, u[p + 2] == 93, u[p + 1] == 32 || u[p + 1] == 120 || u[p + 1] == 88,
           p + 3 == u.count || u[p + 3] == 32 {
            p += min(4, u.count - p)
        }
        return p - start
    }

    /// The style of the line the caret is on (the Styles button shows it).
    public static func style(_ text: String, at caret: Int) -> BlockStyle {
        let lines = LiveMarkdown.parse(text)
        var inCode = false
        for line in lines {
            if line.kind == .fence { inCode.toggle() }
            let end = line.range.location + line.range.length
            if caret >= line.range.location, caret <= end {
                switch line.kind {
                case .code, .fence: return .code
                case .heading(let n): return BlockStyle.heading(n)
                default: return line.quote > 0 ? .quote : .body
                }
            }
        }
        return inCode ? .code : .body
    }

    /// Sets the style of every line the selection touches. A heading style on a line that already has it goes back to Body.
    public static func setStyle(_ text: String, _ sel: NSRange, _ style: BlockStyle) -> MDEdit {
        let t = ns(text)
        let lines = lineRanges(t, sel)
        if style == .code { return toggleCode(text, sel, lines) }
        var changes: [(NSRange, String)] = []
        let current = MarkdownEdit.style(text, at: sel.location)
        for line in lines {
            let s = t.substring(with: line)
            let u = Array(s.utf16)
            // the line's own prefix: quotes, then a heading
            var p = 0
            var quoteLen = 0
            while true {
                var q = p
                while q < u.count, u[q] == 32, q - p < 3 { q += 1 }
                guard q < u.count, u[q] == 62 else { break }
                q += 1
                if q < u.count, u[q] == 32 { q += 1 }
                p = q
                quoteLen = q
            }
            var h = p
            while h < u.count, u[h] == 35 { h += 1 }
            var headingLen = 0
            if h > p, h - p <= 6, h == u.count || u[h] == 32 { headingLen = h - p + (h < u.count ? 1 : 0) }
            switch style {
            case .quote:
                if quoteLen > 0 && current == .quote {
                    changes.append((NSRange(location: line.location, length: quoteLen), ""))
                } else if quoteLen == 0 {
                    changes.append((NSRange(location: line.location, length: 0), "> "))
                }
            case .body:
                changes.append((NSRange(location: line.location, length: quoteLen + headingLen), ""))
            default:
                let n = style.hashes ?? 1
                let want = String(repeating: "#", count: n) + " "
                let same = headingLen > 0 && current == style
                changes.append((NSRange(location: line.location + quoteLen, length: headingLen), same ? "" : want))
            }
        }
        return apply(text, sel, changes)
    }

    /// Code: a ``` fence round the lines, or the fences taken off when the lines are already in one.
    static func toggleCode(_ text: String, _ sel: NSRange, _ lines: [NSRange]) -> MDEdit {
        let t = ns(text)
        guard let first = lines.first, let last = lines.last else { return MDEdit(text, sel) }
        let parsed = LiveMarkdown.parse(text)
        let idxFirst = parsed.firstIndex { $0.range.location == first.location }
        let idxLast = parsed.firstIndex { $0.range.location == last.location }
        if let a = idxFirst, let b = idxLast, parsed[a].kind == .code || parsed[a].kind == .fence {
            // find the fences round them
            var open = a
            while open >= 0, parsed[open].kind != .fence { open -= 1 }
            var close = max(b, open + 1)
            while close < parsed.count, parsed[close].kind != .fence { close += 1 }
            if open >= 0, close < parsed.count, open != close {
                let o = parsed[open].range, c = parsed[close].range
                var changes: [(NSRange, String)] = []
                // the closing fence with the newline before it, the opening one with the newline after it
                let cStart = max(0, c.location - 1)
                changes.append((NSRange(location: cStart, length: c.location + c.length - cStart), ""))
                let oLen = min(o.length + 1, t.length - o.location)
                changes.append((NSRange(location: o.location, length: oLen), ""))
                return apply(text, sel, changes)
            }
        }
        let end = last.location + last.length
        return apply(text, sel, [(NSRange(location: end, length: 0), "\n```"), (NSRange(location: first.location, length: 0), "```\n")])
    }

    /// Return in a list: the next item gets the same mark (a checkbox unticked, a number one more); Return on an empty item ends the
    /// list (its mark goes). Nil when the caret's line is not a list item, so a plain newline is typed.
    public static func newline(_ text: String, _ sel: NSRange) -> MDEdit? {
        let t = ns(text)
        let start = lineStart(t, sel.location)
        let len = lineEnd(t, sel.location) - start
        let lineR = NSRange(location: start, length: len)
        let line = t.substring(with: lineR)
        // quotes carry on too
        var quote = ""
        var rest = line
        while let r = rest.range(of: "^ {0,3}> ?", options: .regularExpression) {
            quote += String(rest[r])
            rest = String(rest[r.upperBound...])
        }
        let markLen = listPrefix(rest)
        let restNS = rest as NSString
        if markLen == 0 {
            if quote.isEmpty { return nil }
            if rest.trimmingCharacters(in: .whitespaces).isEmpty {
                return apply(text, NSRange(location: sel.location, length: 0), [(NSRange(location: lineR.location, length: len), "")])
            }
            return insert(text, sel, "\n" + quote)
        }
        let indent = leadingSpaces(rest)
        let mark = restNS.substring(with: NSRange(location: indent, length: markLen))
        let words = restNS.substring(from: indent + markLen)
        if words.trimmingCharacters(in: .whitespaces).isEmpty {
            // an empty item ends the list
            let quoteLen = (quote as NSString).length
            let range = NSRange(location: lineR.location + quoteLen, length: len - quoteLen)
            let m = NSMutableString(string: text)
            m.replaceCharacters(in: range, with: "")
            return MDEdit(m as String, NSRange(location: range.location, length: 0))
        }
        var next = mark
        if let r = next.range(of: "\\[[xX]\\]", options: .regularExpression) { next.replaceSubrange(r, with: "[ ]") }
        if let r = next.range(of: "^\\d+", options: .regularExpression), let n = Int(next[r]) { next.replaceSubrange(r, with: String(n + 1)) }
        let pad = String(restNS.substring(to: indent))
        return insert(text, sel, "\n" + quote + pad + next)
    }

    static func insert(_ text: String, _ sel: NSRange, _ s: String) -> MDEdit {
        let m = NSMutableString(string: text)
        m.replaceCharacters(in: sel, with: s)
        return MDEdit(m as String, NSRange(location: sel.location + (s as NSString).length, length: 0))
    }

    /// Tab and Shift-Tab on list lines: two spaces in or out. Nil when no line the selection touches is a list item.
    public static func indent(_ text: String, _ sel: NSRange, out: Bool) -> MDEdit? {
        let t = ns(text)
        var changes: [(NSRange, String)] = []
        for line in lineRanges(t, sel) {
            let s = t.substring(with: line)
            guard listPrefix(s) > 0 else { continue }
            if out {
                let n = min(2, leadingSpaces(s))
                if n > 0 { changes.append((NSRange(location: line.location, length: n), "")) }
            } else {
                changes.append((NSRange(location: line.location, length: 0), "  "))
            }
        }
        if changes.isEmpty { return nil }
        return apply(text, sel, changes)
    }

    /// Find every match of `query` in a text (case and accents ignored), as UTF-16 ranges.
    public static func find(_ query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }
        let t = ns(text)
        var out: [NSRange] = []
        var from = 0
        while from < t.length {
            let r = t.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: from, length: t.length - from))
            if r.location == NSNotFound || r.length == 0 { break }
            out.append(r)
            from = r.location + r.length
        }
        return out
    }

    /// Replace every match (or only the ones given) of `query` with `with`.
    public static func replace(_ query: String, with: String, in text: String, only: [NSRange]? = nil) -> (text: String, count: Int) {
        let ranges = only ?? find(query, in: text)
        let m = NSMutableString(string: text)
        for r in ranges.sorted(by: { $0.location > $1.location }) where r.location + r.length <= m.length {
            m.replaceCharacters(in: r, with: with)
        }
        return (m as String, ranges.count)
    }
}
