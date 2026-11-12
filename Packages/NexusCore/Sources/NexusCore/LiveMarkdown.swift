import Foundation

/// A typed block's markdown read the way the laptop's notes editor shows it while you type (renderer/src/editor.js `buildDecos`):
/// the words keep their markdown, and the marks (`**`, `# `, `> `, `[`…`](url)`, …) hide unless the caret is near them. Every range is
/// in UTF-16 units of the whole text, so the iPad's text view can use them as they are.
///
/// When a mark shows (`MDReveal`): `.line` on the caret's line (headings, quotes, bullets, the list mark before a checkbox),
/// `.span` while the selection touches its span (bold, italic, code, links, highlights, …), `.never` (a checkbox is always drawn as
/// a box). Some hidden marks are drawn as something else (`MDGlyph`): a bullet, a checkbox, a rule across the block.

public enum MDLineKind: Equatable {
    case blank
    case text
    case heading(Int)
    case bullet
    case ordered(Int)
    case task(Bool)
    case fence
    case code
    case rule
    case table
    case tableRule
    case mathFence
    case math
}

public enum MDSpanKind: Equatable {
    case bold
    case italic
    case strike
    case code
    case underline
    case math(display: Bool)
    /// `==x==` is "yellow"; `<mark data-c="green">` its colour name.
    case highlight(String)
    /// `<span data-c="red">`: a text colour by name.
    case color(String)
    case link(String)
    case wikilink(String)
    /// `[title](nexus-task:<id>)`: a Nexus task chip.
    case nexusTask(String)
    /// Review mode's suggestions (CriticMarkup): `{++added++}`, `{--deleted--}`, and `{~~old~>new~~}` as both.
    case added
    case deleted
}

public struct MDSpan: Equatable {
    public var range: NSRange
    public var kind: MDSpanKind
    public init(_ range: NSRange, _ kind: MDSpanKind) {
        self.range = range
        self.kind = kind
    }
}

public enum MDReveal: Equatable {
    case line
    case span(NSRange)
    case never
}

public enum MDGlyph: Equatable {
    case none
    case bullet
    case checkbox(Bool)
    case rule
}

public struct MDMark: Equatable {
    public var range: NSRange
    public var reveal: MDReveal
    public var glyph: MDGlyph
    public init(_ range: NSRange, _ reveal: MDReveal, _ glyph: MDGlyph = .none) {
        self.range = range
        self.reveal = reveal
        self.glyph = glyph
    }
}

public struct MDLine: Equatable {
    /// The line without its newline.
    public var range: NSRange
    public var kind: MDLineKind
    /// How deep it is quoted.
    public var quote: Int = 0
    /// A list item's depth (its indent in columns / 2); a line that carries on a list item has the item's.
    public var level: Int = 0
    /// Where the words start, after the marks.
    public var content: Int
    /// A plain line straight after a list item: it carries on that item (indented like its words).
    public var continues: Bool = false
    /// An ordered item's number, or a bullet's or task's list mark.
    public var marker: NSRange? = nil
    public var marks: [MDMark] = []
    public var spans: [MDSpan] = []

    public init(range: NSRange, kind: MDLineKind, content: Int) {
        self.range = range
        self.kind = kind
        self.content = content
    }

    public var isList: Bool {
        switch kind {
        case .bullet, .ordered, .task: return true
        default: return false
        }
    }
}

/// How one mark shows for a given selection.
public enum MDShow: Equatable {
    /// Not drawn and takes no room.
    case hidden
    /// Drawn as this glyph in its place (its characters take their room but aren't drawn).
    case glyph(MDGlyph)
    /// Shown as text, faintly.
    case faint
}

public struct MDShown: Equatable {
    public var range: NSRange
    public var show: MDShow
    public init(_ range: NSRange, _ show: MDShow) {
        self.range = range
        self.show = show
    }
}

public enum LiveMarkdown {
    // UTF-16 code units
    static let tab: UInt16 = 9, nl: UInt16 = 10, cr: UInt16 = 13, space: UInt16 = 32, bang: UInt16 = 33, quoteMark: UInt16 = 34
    static let hash: UInt16 = 35, dollar: UInt16 = 36, lparen: UInt16 = 40, rparen: UInt16 = 41, star: UInt16 = 42, plus: UInt16 = 43
    static let dash: UInt16 = 45, dot: UInt16 = 46, colon: UInt16 = 58, lt: UInt16 = 60, eq: UInt16 = 61, gt: UInt16 = 62
    static let lbracket: UInt16 = 91, backslash: UInt16 = 92, rbracket: UInt16 = 93, underscore: UInt16 = 95, backtick: UInt16 = 96
    static let lbrace: UInt16 = 123, pipe: UInt16 = 124, rbrace: UInt16 = 125, tilde: UInt16 = 126, lowerX: UInt16 = 120, upperX: UInt16 = 88

    // MARK: lines

    /// Every line of the text, with its kind, marks and inline spans.
    public static func parse(_ text: String) -> [MDLine] {
        let u: [UInt16] = Array(text.utf16)
        var lines: [MDLine] = []
        var inFence = false
        var fenceChar: UInt16 = backtick
        var inMath = false
        var start = 0
        var i = 0
        let n = u.count
        while i <= n {
            if i == n || u[i] == nl {
                var end = i
                if end > start, u[end - 1] == cr { end -= 1 }
                let line = readLine(u, start, end, inFence: &inFence, fenceChar: &fenceChar, inMath: &inMath, previous: lines.last)
                lines.append(line)
                start = i + 1
            }
            i += 1
        }
        return lines
    }

    static func isBlankChar(_ c: UInt16) -> Bool { c == space || c == tab }

    static func readLine(_ u: [UInt16], _ start: Int, _ end: Int, inFence: inout Bool, fenceChar: inout UInt16, inMath: inout Bool,
                         previous: MDLine?) -> MDLine {
        let range = NSRange(location: start, length: end - start)
        // a fence opens or closes a code block
        var p = start
        var lead = 0
        while p < end, u[p] == space, lead < 3 { p += 1; lead += 1 }
        if p + 3 <= end, !inMath {
            let c = u[p]
            if c == backtick || c == tilde, u[p + 1] == c, u[p + 2] == c {
                if !inFence {
                    inFence = true
                    fenceChar = c
                    return MDLine(range: range, kind: .fence, content: end)
                } else if c == fenceChar {
                    inFence = false
                    return MDLine(range: range, kind: .fence, content: end)
                }
            }
        }
        if inFence { return MDLine(range: range, kind: .code, content: start) }

        // a $$ line opens or closes a maths block
        let trimmed = trimRange(u, start, end)
        if trimmed.1 - trimmed.0 == 2, u[trimmed.0] == dollar, u[trimmed.0 + 1] == dollar {
            inMath.toggle()
            return MDLine(range: range, kind: .mathFence, content: end)
        }
        if inMath { return MDLine(range: range, kind: .math, content: start) }

        if trimmed.0 == trimmed.1 { return MDLine(range: range, kind: .blank, content: end) }

        var line = MDLine(range: range, kind: .text, content: start)
        // quotes first: "> - [ ] b" is a task in a quote
        p = start
        var depth = 0
        while depth < 8 {
            var q = p
            var sp = 0
            while q < end, u[q] == space, sp < 3 { q += 1; sp += 1 }
            guard q < end, u[q] == gt else { break }
            q += 1
            if q < end, u[q] == space { q += 1 }
            line.marks.append(MDMark(NSRange(location: p, length: q - p), .line))
            depth += 1
            p = q
        }
        line.quote = depth

        // a heading
        var q = p
        var sp = 0
        while q < end, u[q] == space, sp < 3 { q += 1; sp += 1 }
        var hashes = 0
        while q + hashes < end, u[q + hashes] == hash { hashes += 1 }
        if hashes >= 1, hashes <= 6, q + hashes == end || isBlankChar(u[q + hashes]) {
            var after = q + hashes
            if after < end { after += 1 }
            line.kind = .heading(hashes)
            line.marks.append(MDMark(NSRange(location: p, length: after - p), .line))
            line.content = after
            addInline(&line, u, after, end)
            return line
        }

        // a rule: three or more of one of - * _, nothing else
        if isRule(u, p, end) {
            line.kind = .rule
            line.marks.append(MDMark(NSRange(location: p, length: end - p), .line, .rule))
            line.content = end
            return line
        }

        // a list item
        var r = p
        var cols = 0
        while r < end, isBlankChar(u[r]) { cols += u[r] == tab ? 4 : 1; r += 1 }
        let level = min(cols / 2, 8)
        if r < end, (u[r] == dash || u[r] == star || u[r] == plus), r + 1 == end || isBlankChar(u[r + 1]) {
            let markEnd = r + 1
            var after = markEnd
            if after < end { after += 1 }
            line.level = level
            line.marker = NSRange(location: r, length: 1)
            // a task: "- [ ] words"
            if after + 2 < end, u[after] == lbracket, u[after + 2] == rbracket,
               u[after + 1] == space || u[after + 1] == lowerX || u[after + 1] == upperX,
               after + 3 == end || isBlankChar(u[after + 3]) {
                let done = u[after + 1] != space
                line.kind = .task(done)
                line.marks.append(MDMark(NSRange(location: r, length: after - r), .line))
                line.marks.append(MDMark(NSRange(location: after, length: 3), .never, .checkbox(done)))
                var words = after + 3
                if words < end { words += 1 }
                line.content = words
            } else {
                line.kind = .bullet
                line.marks.append(MDMark(NSRange(location: r, length: 1), .line, .bullet))
                line.content = after
            }
            addInline(&line, u, line.content, end)
            return line
        }
        // an ordered item: "12. words" or "3) words"
        var d = r
        while d < end, d - r < 9, u[d] >= 48, u[d] <= 57 { d += 1 }
        if d > r, d < end, (u[d] == dot || u[d] == rparen), d + 1 == end || isBlankChar(u[d + 1]) {
            var number = 0
            for k in r..<d { number = number * 10 + Int(u[k] - 48) }
            line.kind = .ordered(number)
            line.level = level
            line.marker = NSRange(location: r, length: d + 1 - r)
            var after = d + 1
            if after < end { after += 1 }
            // "1. [ ] words" is a task too
            if after + 2 < end, u[after] == lbracket, u[after + 2] == rbracket,
               u[after + 1] == space || u[after + 1] == lowerX || u[after + 1] == upperX,
               after + 3 == end || isBlankChar(u[after + 3]) {
                let done = u[after + 1] != space
                line.kind = .task(done)
                line.marks.append(MDMark(NSRange(location: after, length: 3), .never, .checkbox(done)))
                var words = after + 3
                if words < end { words += 1 }
                line.content = words
            } else {
                line.content = after
            }
            addInline(&line, u, line.content, end)
            return line
        }

        // a table row
        if r < end, u[r] == pipe {
            line.kind = isTableRule(u, r, end) ? .tableRule : .table
            line.content = r
            if line.kind == .table { addInline(&line, u, r, end) }
            return line
        }

        // a plain line: straight after a list item (no blank line) it carries on that item
        line.content = r
        if let prev = previous, prev.isList || prev.continues, prev.quote == depth {
            line.continues = true
            line.level = prev.level
        }
        addInline(&line, u, r, end)
        return line
    }

    static func trimRange(_ u: [UInt16], _ start: Int, _ end: Int) -> (Int, Int) {
        var a = start, b = end
        while a < b, isBlankChar(u[a]) { a += 1 }
        while b > a, isBlankChar(u[b - 1]) { b -= 1 }
        return (a, b)
    }

    static func isRule(_ u: [UInt16], _ start: Int, _ end: Int) -> Bool {
        var p = start
        var sp = 0
        while p < end, u[p] == space, sp < 3 { p += 1; sp += 1 }
        guard p < end, u[p] == dash || u[p] == star || u[p] == underscore else { return false }
        let c = u[p]
        var count = 0
        while p < end {
            if u[p] == c { count += 1 } else if !isBlankChar(u[p]) { return false }
            p += 1
        }
        return count >= 3
    }

    static func isTableRule(_ u: [UInt16], _ start: Int, _ end: Int) -> Bool {
        var dashes = 0
        for k in start..<end {
            let c = u[k]
            if c == dash { dashes += 1 } else if c != pipe && c != colon && !isBlankChar(c) { return false }
        }
        return dashes >= 1
    }

    // MARK: inline

    static func isSpaceLike(_ c: UInt16?) -> Bool {
        guard let c else { return true }
        return c == space || c == tab || c == nl || c == cr || c == 0xA0
    }

    static func isPunct(_ c: UInt16?) -> Bool {
        guard let c else { return false }
        if c >= 33 && c <= 47 { return true }
        if c >= 58 && c <= 64 { return true }
        if c >= 91 && c <= 96 { return true }
        if c >= 123 && c <= 126 { return true }
        if c >= 0x2010 && c <= 0x2027 { return true }
        if c == 0xA1 || c == 0xBF || c == 0xAB || c == 0xBB { return true }
        return false
    }

    static func isWordChar(_ c: UInt16?) -> Bool {
        guard let c else { return false }
        return !isSpaceLike(c) && !isPunct(c)
    }

    /// Does `s` (ASCII) start at `p`?
    static func has(_ u: [UInt16], _ p: Int, _ end: Int, _ s: String) -> Bool {
        let w = Array(s.utf16)
        if p < 0 || p + w.count > end { return false }
        for k in 0..<w.count where u[p + k] != w[k] { return false }
        return true
    }

    static func find(_ u: [UInt16], _ from: Int, _ end: Int, _ s: String, taken: [Bool], base: Int) -> Int? {
        let w = Array(s.utf16)
        guard !w.isEmpty, from <= end - w.count else { return nil }
        var p = from
        while p <= end - w.count {
            if !taken[p - base], has(u, p, end, s) { return p }
            p += 1
        }
        return nil
    }

    /// The line's inline spans and their marks, for the words from `start` to `end`.
    static func addInline(_ line: inout MDLine, _ u: [UInt16], _ start: Int, _ end: Int) {
        var spans: [MDSpan] = []
        var marks: [MDMark] = []
        inlineInto(u, start, end, spans: &spans, marks: &marks)
        line.spans = spans
        line.marks.append(contentsOf: marks)
    }

    static func inlineInto(_ u: [UInt16], _ start: Int, _ end: Int, spans: inout [MDSpan], marks: inout [MDMark]) {
        guard end > start else { return }
        let base = start
        var taken = [Bool](repeating: false, count: end - start)
        func take(_ a: Int, _ b: Int) { if b > a { for k in a..<b { taken[k - base] = true } } }
        func isTaken(_ p: Int) -> Bool { taken[p - base] }
        func addMarks(_ ranges: [(Int, Int)], span: NSRange) {
            for (a, b) in ranges where b > a {
                marks.append(MDMark(NSRange(location: a, length: b - a), .span(span)))
                take(a, b)
            }
        }

        // escapes: "\*" is a literal star
        var p = start
        while p < end - 1 {
            if u[p] == backslash, isPunct(u[p + 1]) {
                taken[p + 1 - base] = true
                p += 2
            } else {
                p += 1
            }
        }

        // code spans: a run of backticks closed by a run of the same length; nothing inside is markdown
        p = start
        while p < end {
            if u[p] == backtick, !isTaken(p) {
                var n = 0
                while p + n < end, u[p + n] == backtick { n += 1 }
                var q = p + n
                var close: Int? = nil
                while q < end {
                    if u[q] == backtick {
                        var m = 0
                        while q + m < end, u[q + m] == backtick { m += 1 }
                        if m == n { close = q; break }
                        q += m
                    } else {
                        q += 1
                    }
                }
                if let c = close {
                    let span = NSRange(location: p, length: c + n - p)
                    spans.append(MDSpan(span, .code))
                    addMarks([(p, p + n), (c, c + n)], span: span)
                    take(p, c + n)
                    p = c + n
                } else {
                    p += n
                }
            } else {
                p += 1
            }
        }

        // maths: $$x$$ and $x$ (no space just inside, no digit straight after the closing $)
        p = start
        while p < end {
            if u[p] == dollar, !isTaken(p) {
                let display = p + 1 < end && u[p + 1] == dollar
                let open = display ? 2 : 1
                let inner = p + open
                if inner < end, !isSpaceLike(u[inner]), u[inner] != dollar {
                    var q = inner
                    var close: Int? = nil
                    while q < end {
                        if u[q] == dollar, !isTaken(q) {
                            if display {
                                if q + 1 < end, u[q + 1] == dollar { close = q }
                            } else if !isSpaceLike(u[q - 1]) && !(q + 1 < end && u[q + 1] >= 48 && u[q + 1] <= 57) {
                                close = q
                            }
                            break
                        }
                        q += 1
                    }
                    if let c = close, c > inner {
                        let span = NSRange(location: p, length: c + open - p)
                        spans.append(MDSpan(span, .math(display: display)))
                        addMarks([(p, inner), (c, c + open)], span: span)
                        take(p, c + open)
                        p = c + open
                        continue
                    }
                }
                p += open
            } else {
                p += 1
            }
        }

        // review mode's suggestions
        p = start
        while p < end {
            if u[p] == lbrace, !isTaken(p) {
                if has(u, p, end, "{++"), let c = find(u, p + 3, end, "++}", taken: taken, base: base) {
                    let span = NSRange(location: p, length: c + 3 - p)
                    spans.append(MDSpan(NSRange(location: p + 3, length: c - p - 3), .added))
                    addMarks([(p, p + 3), (c, c + 3)], span: span)
                    p = c + 3
                    continue
                }
                if has(u, p, end, "{--"), let c = find(u, p + 3, end, "--}", taken: taken, base: base) {
                    let span = NSRange(location: p, length: c + 3 - p)
                    spans.append(MDSpan(NSRange(location: p + 3, length: c - p - 3), .deleted))
                    addMarks([(p, p + 3), (c, c + 3)], span: span)
                    p = c + 3
                    continue
                }
                if has(u, p, end, "{~~"), let mid = find(u, p + 3, end, "~>", taken: taken, base: base),
                   let c = find(u, mid + 2, end, "~~}", taken: taken, base: base) {
                    let span = NSRange(location: p, length: c + 3 - p)
                    spans.append(MDSpan(NSRange(location: p + 3, length: mid - p - 3), .deleted))
                    spans.append(MDSpan(NSRange(location: mid + 2, length: c - mid - 2), .added))
                    addMarks([(p, p + 3), (mid, mid + 2), (c, c + 3)], span: span)
                    p = c + 3
                    continue
                }
            }
            p += 1
        }

        // wikilinks: [[target]], [[target|shown]]
        p = start
        while p < end - 1 {
            if u[p] == lbracket, u[p + 1] == lbracket, !isTaken(p), let c = find(u, p + 2, end, "]]", taken: taken, base: base), c > p + 2 {
                let span = NSRange(location: p, length: c + 2 - p)
                var bar: Int? = nil
                for k in (p + 2)..<c where u[k] == pipe { bar = k; break }
                let target = String(utf16CodeUnits: Array(u[(p + 2)..<(bar ?? c)]), count: (bar ?? c) - p - 2)
                spans.append(MDSpan(span, .wikilink(target)))
                if let b = bar {
                    addMarks([(p, b + 1), (c, c + 2)], span: span)
                } else {
                    addMarks([(p, p + 2), (c, c + 2)], span: span)
                }
                p = c + 2
                continue
            }
            p += 1
        }

        // links: [words](url); an image ![alt](src) is left as it is
        p = start
        while p < end {
            if u[p] == lbracket, !isTaken(p), !(p > start && u[p - 1] == bang) {
                var depth = 0
                var q = p
                var close: Int? = nil
                while q < end {
                    if !isTaken(q) {
                        if u[q] == lbracket { depth += 1 }
                        if u[q] == rbracket { depth -= 1; if depth == 0 { close = q; break } }
                    }
                    q += 1
                }
                if let c = close, c + 1 < end, u[c + 1] == lparen {
                    var r = c + 2
                    var paren = 1
                    var urlEnd: Int? = nil
                    while r < end {
                        if u[r] == lparen { paren += 1 }
                        if u[r] == rparen { paren -= 1; if paren == 0 { urlEnd = r; break } }
                        if u[r] == space && !(r > c + 2) { break }
                        r += 1
                    }
                    if let e = urlEnd {
                        let url = String(utf16CodeUnits: Array(u[(c + 2)..<e]), count: e - c - 2).trimmingCharacters(in: .whitespaces)
                        let span = NSRange(location: p, length: e + 1 - p)
                        if url.hasPrefix("nexus-task:") {
                            spans.append(MDSpan(span, .nexusTask(String(url.dropFirst("nexus-task:".count)))))
                        } else {
                            spans.append(MDSpan(span, .link(url)))
                        }
                        addMarks([(p, p + 1), (c, e + 1)], span: span)
                        p = c
                        continue
                    }
                }
            }
            p += 1
        }

        // html we write: <u>…</u>, <mark data-c="…">…</mark>, <span data-c="…">…</span>
        p = start
        while p < end {
            if u[p] == lt, !isTaken(p) {
                if has(u, p, end, "<u>"), let c = find(u, p + 3, end, "</u>", taken: taken, base: base) {
                    let span = NSRange(location: p, length: c + 4 - p)
                    spans.append(MDSpan(span, .underline))
                    addMarks([(p, p + 3), (c, c + 4)], span: span)
                    p = c + 4
                    continue
                }
                for (tag, isMark) in [("mark", true), ("span", false)] {
                    guard has(u, p, end, "<" + tag) else { continue }
                    var q = p + 1 + tag.count
                    while q < end, u[q] != gt { q += 1 }
                    guard q < end, let c = find(u, q + 1, end, "</" + tag + ">", taken: taken, base: base) else { continue }
                    let open = String(utf16CodeUnits: Array(u[p...q]), count: q - p + 1)
                    let name = colorName(open) ?? (isMark ? "yellow" : "")
                    let span = NSRange(location: p, length: c + tag.count + 3 - p)
                    spans.append(MDSpan(span, isMark ? .highlight(name) : .color(name)))
                    addMarks([(p, q + 1), (c, c + tag.count + 3)], span: span)
                    p = q
                    break
                }
            }
            p += 1
        }

        // ==highlight== and ~~strike~~
        for (delim, kind) in [("==", MDSpanKind.highlight("yellow")), ("~~", MDSpanKind.strike)] {
            p = start
            while p < end - 1 {
                if !isTaken(p), !isTaken(p + 1), has(u, p, end, delim), p + 2 < end, !isSpaceLike(u[p + 2]),
                   let c = find(u, p + 2, end, delim, taken: taken, base: base), c > p + 2, !isSpaceLike(u[c - 1]) {
                    let span = NSRange(location: p, length: c + 2 - p)
                    spans.append(MDSpan(span, kind))
                    addMarks([(p, p + 2), (c, c + 2)], span: span)
                    p = c + 2
                    continue
                }
                p += 1
            }
        }

        emphasis(u, start, end, taken: &taken, spans: &spans, marks: &marks)
        spans.sort { ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length) }
        marks.sort { $0.range.location < $1.range.location }
    }

    static func colorName(_ tag: String) -> String? {
        guard let r = tag.range(of: "data-c=\"") else { return nil }
        let rest = tag[r.upperBound...]
        guard let q = rest.firstIndex(of: "\"") else { return nil }
        let name = String(rest[..<q]).trimmingCharacters(in: .whitespaces).lowercased()
        return name.isEmpty ? nil : name
    }

    /// `*` and `_` emphasis, CommonMark's way (delimiter runs, left and right flanking, the rule of three), simplified.
    static func emphasis(_ u: [UInt16], _ start: Int, _ end: Int, taken: inout [Bool], spans: inout [MDSpan], marks: inout [MDMark]) {
        struct Run {
            var start: Int
            var length: Int
            var char: UInt16
            var canOpen: Bool
            var canClose: Bool
            var left: Int      // still free, counted from the start (an opener gives from its end)
            var usedFront: Int // a closer gives from its start
        }
        let base = start
        var runs: [Run] = []
        var p = start
        while p < end {
            let c = u[p]
            if (c == star || c == underscore), !taken[p - base] {
                var n = 0
                while p + n < end, u[p + n] == c, !taken[p + n - base] { n += 1 }
                let prev: UInt16? = p > start ? u[p - 1] : nil
                let next: UInt16? = p + n < end ? u[p + n] : nil
                let leftFlank = !isSpaceLike(next) && (!isPunct(next) || isSpaceLike(prev) || isPunct(prev))
                let rightFlank = !isSpaceLike(prev) && (!isPunct(prev) || isSpaceLike(next) || isPunct(next))
                var canOpen = leftFlank, canClose = rightFlank
                if c == underscore {
                    canOpen = leftFlank && (!rightFlank || isPunct(prev))
                    canClose = rightFlank && (!leftFlank || isPunct(next))
                }
                runs.append(Run(start: p, length: n, char: c, canOpen: canOpen, canClose: canClose, left: n, usedFront: 0))
                p += n
            } else {
                p += 1
            }
        }
        guard runs.count > 1 else { return }
        var ci = 0
        while ci < runs.count {
            let closer = runs[ci]
            guard closer.canClose, closer.left > 0 else { ci += 1; continue }
            var found: Int? = nil
            var oi = ci - 1
            while oi >= 0 {
                let o = runs[oi]
                if o.char == closer.char, o.canOpen, o.left > 0 {
                    let odd = (o.canClose || closer.canOpen) && (o.length + closer.length) % 3 == 0 && !(o.length % 3 == 0 && closer.length % 3 == 0)
                    if !odd { found = oi; break }
                }
                oi -= 1
            }
            guard let o = found else { ci += 1; continue }
            let use = runs[o].left >= 2 && runs[ci].left >= 2 ? 2 : 1
            let openEnd = runs[o].start + runs[o].left
            let openMark = (openEnd - use, openEnd)
            let closeStart = runs[ci].start + runs[ci].usedFront
            let closeMark = (closeStart, closeStart + use)
            let span = NSRange(location: openMark.0, length: closeMark.1 - openMark.0)
            spans.append(MDSpan(span, use == 2 ? .bold : .italic))
            marks.append(MDMark(NSRange(location: openMark.0, length: use), .span(span)))
            marks.append(MDMark(NSRange(location: closeMark.0, length: use), .span(span)))
            runs[o].left -= use
            runs[ci].left -= use
            runs[ci].usedFront += use
            // delimiters between them can't match any more
            if o + 1 < ci { for k in (o + 1)..<ci { runs[k].left = 0 } }
            if runs[ci].left == 0 { ci += 1 }
        }
    }

    // MARK: showing

    static func touches(_ sel: NSRange, _ a: Int, _ b: Int) -> Bool {
        sel.location <= b && sel.location + sel.length >= a
    }

    /// How every mark shows for this selection (nil: nothing is being edited, so every mark hides).
    public static func shown(_ lines: [MDLine], selection: NSRange?) -> [MDShown] {
        var out: [MDShown] = []
        for line in lines {
            let lineActive = selection.map { touches($0, line.range.location, line.range.location + line.range.length) } ?? false
            for m in line.marks {
                var revealed: Bool
                switch m.reveal {
                case .never: revealed = false
                case .line: revealed = lineActive
                case .span(let s): revealed = selection.map { touches($0, s.location, s.location + s.length) } ?? false
                }
                if case .checkbox = m.glyph { revealed = false }
                if revealed {
                    out.append(MDShown(m.range, .faint))
                } else if m.glyph == .none {
                    out.append(MDShown(m.range, .hidden))
                } else {
                    out.append(MDShown(m.range, .glyph(m.glyph)))
                }
            }
        }
        return out
    }

    // MARK: counting

    /// The words as they read with every mark hidden (a block's word count, read aloud, search snippets).
    public static func visibleText(_ text: String) -> String {
        let lines = parse(text)
        let ns = text as NSString
        var hide = IndexSet()
        for s in shown(lines, selection: nil) {
            if s.range.length > 0 { hide.insert(integersIn: s.range.location..<(s.range.location + s.range.length)) }
        }
        var out: [unichar] = []
        out.reserveCapacity(ns.length)
        for k in 0..<ns.length where !hide.contains(k) { out.append(ns.character(at: k)) }
        return String(utf16CodeUnits: out, count: out.count)
    }

    /// Words and characters (newlines not counted) as they read, like a word processor's count.
    /// Words and characters as the laptop counts them (BlockFacts: no markdown, no taken-out suggestions).
    public static func count(_ text: String) -> (words: Int, characters: Int) {
        (BlockFacts.wordCount(text), BlockFacts.charCount(text))
    }
}
