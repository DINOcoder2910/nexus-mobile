import Foundation

/// Where each question of a sheet is, from the PDF's own words, as the laptop's question bank finds them (nexus
/// `desktop/backend/src/questions.rs`, and the words' helpers of `bank.rs`): the lines of the pages are searched for question numbers at
/// the left of a line ("3.", "3 (a)", "(b)", "(ii)", "3a(ii)"), kept only when they run in order, so a "2" in the middle of a sentence
/// or a table is not taken for one. A markscheme is read the same way; one at the end of the paper's own PDF is the second run of
/// numbers, after a page that says "markscheme" or "answers". A question on the paper is matched to the same number (and part) in the
/// markscheme. Pure: the lines come from PDFKit on the device (PDFium on the laptop), so it is tested on lines written by hand.
public enum QuestionFinder {
    /// A line of a page: where it starts (x, a fraction of the page's width), its top (y, a fraction of the height from the top), its words.
    public struct Line: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var text: String
        public init(x: Double, y: Double, text: String) { self.x = x; self.y = y; self.text = text }
    }

    /// A place on a page: the page (from 0) and how far down it (a fraction).
    public struct Spot: Equatable, Sendable {
        public var page: Int
        public var y: Double
        public init(page: Int, y: Double) { self.page = page; self.y = y }
        public init?(_ v: JSONValue?) {
            guard let p = v?["page"]?.number, let y = v?["y"]?.number else { return nil }
            self.init(page: Int(p), y: y)
        }
        public var json: JSONValue { .object([("page", .number(Double(page))), ("y", .number((y * 10000).rounded() / 10000))]) }
    }

    public struct Q: Equatable, Sendable {
        public var main: Int
        public var sub: Character?
        public var part: String?
        public var from: Spot
        public var to: Spot
        public init(main: Int, sub: Character? = nil, part: String? = nil, from: Spot, to: Spot) {
            self.main = main; self.sub = sub; self.part = part; self.from = from; self.to = to
        }
        /// Its key: "3", "3a", "3a(ii)".
        public var key: String {
            var s = String(main)
            if let sub { s.append(sub) }
            if let part { s += "(\(part))" }
            return s
        }
        var level: Int { part != nil ? 2 : sub != nil ? 1 : 0 }
    }

    static let romans = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]
    /// A number is only a question's when its line starts this near the left of the page.
    static let left = 0.24
    static let subLeft = 0.34

    /// What a line starts with: a question's number, a part's letter, a sub-part's roman numeral (any of them).
    struct Lead: Equatable {
        var main: Int?
        var sub: Character?
        var part: String?
    }

    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
    static func isPartLetter(_ c: Character) -> Bool { c >= "a" && c <= "h" }

    static func lead(_ text: String) -> Lead {
        let s = Array(text.drop { $0.isWhitespace })
        var i = 0
        var out = Lead()
        // the number: one or two digits, then nothing, a space, '.', ')', '(' or the part's letter; never a decimal, a year or "2 marks"
        let d0 = i
        while i < s.count, isDigit(s[i]), i - d0 < 3 { i += 1 }
        if i > d0 {
            if i - d0 > 2 { return Lead() }
            let n = Int(String(s[d0..<i])) ?? 0
            if n == 0 { return Lead() }
            if i < s.count, s[i] == ".", i + 1 < s.count, isDigit(s[i + 1]) { return Lead() }
            if i < s.count, !(s[i].isWhitespace || s[i] == "." || s[i] == ")" || s[i] == "(" || isPartLetter(s[i])) { return Lead() }
            var rest = String(s[i...])
            while let f = rest.first, f == "." || f == ")" { rest.removeFirst() }
            rest = String(rest.drop { $0.isWhitespace }).lowercased()
            if ["mark", "marks", "mol", "g ", "cm", "dm", "kj", "min", "hour", "%"].contains(where: { rest.hasPrefix($0) }) { return Lead() }
            out.main = n
            if i < s.count, s[i] == "." || s[i] == ")" { i += 1 }
        }
        // the part: "(a)", "a)", "a " or "a" straight after the number ("3a")
        func skip(_ i: inout Int) { while i < s.count, s[i].isWhitespace { i += 1 } }
        skip(&i)
        var open = i < s.count && s[i] == "("
        var j = open ? i + 1 : i
        if j < s.count, isPartLetter(s[j]) {
            let after: Character? = j + 1 < s.count ? s[j + 1] : nil
            let closed = after == ")"
            let ok = open ? closed : (closed || ((after == nil || after!.isWhitespace || after == "(") && out.main != nil))
            // (a bare "a " opening a line is the word "a", unless a number came before it)
            if ok && !(out.main == nil && !open && !closed) {
                out.sub = s[j]
                i = j + 1 + (closed ? 1 : 0)
            }
        }
        // the sub-part: "(ii)" or "ii)"
        skip(&i)
        open = i < s.count && s[i] == "("
        j = open ? i + 1 : i
        var k = j
        while k < s.count, s[k] == "i" || s[k] == "v" || s[k] == "x" { k += 1 }
        if k > j {
            let r = String(s[j..<k])
            let closed = k < s.count && s[k] == ")"
            let bare = !open && (out.main != nil || out.sub != nil) && (k >= s.count || s[k].isWhitespace)
            if romans.contains(r) && (closed || bare) { out.part = r }
        }
        return out
    }

    /// The questions found on these pages, in runs: a run ends where the numbers start again at 1.
    public static func runs(_ pages: [[Line]]) -> [[Q]] {
        var runs: [[Q]] = [[]]
        var main = 0
        var sub: Character?
        var part: String?
        func push(_ m: Int, _ s: Character?, _ p: String?, _ at: Spot) { runs[runs.count - 1].append(Q(main: m, sub: s, part: p, from: at, to: at)) }
        for (p, lines) in pages.enumerated() {
            for l in lines {
                if l.x > subLeft { continue }
                var d = lead(l.text)
                let at = Spot(page: p, y: l.y)
                if let n = d.main {
                    if l.x > left { continue }
                    if n == main && main > 0 {
                        // the same number again ("3 (continued)", or a markscheme's row for its next part): read as its part alone
                        d.main = nil
                    } else {
                        if n == 1 && main >= 2 { runs.append([]); main = 0 }
                        let next = main + 1
                        if !(n >= next && n <= next + 2) { continue }
                        main = n; sub = nil; part = nil
                        push(main, nil, nil, at)
                        if let c = d.sub { sub = c; push(main, sub, nil, at) }
                        if d.part != nil { part = d.part; push(main, sub, part, at) }
                        continue
                    }
                }
                if main == 0 { continue }
                // a part on a line of its own: the next letter, then its sub-parts in order
                if let c = d.sub, c != sub {
                    let ok: Bool
                    if let s = sub { ok = c.unicodeScalars.first!.value == s.unicodeScalars.first!.value + 1 } else { ok = c == "a" }
                    if !ok { continue }
                    sub = c; part = nil
                    push(main, sub, nil, at)
                    if d.part != nil { part = d.part; push(main, sub, part, at) }
                } else if d.part != nil && romanNext(part, d.part) {
                    part = d.part
                    push(main, sub, part, at)
                }
            }
        }
        runs.removeAll { $0.isEmpty }
        // where each one ends: where the next at its level or above starts, else at the end of the last page
        let last = Spot(page: max(0, pages.count - 1), y: 1)
        for r in runs.indices {
            let n = runs[r].count
            for i in 0..<n {
                let lvl = runs[r][i].level
                runs[r][i].to = ((i + 1)..<n).first { runs[r][$0].level <= lvl }.map { runs[r][$0].from } ?? last
            }
        }
        return runs
    }

    static func romanNext(_ cur: String?, _ next: String?) -> Bool {
        let a = cur.flatMap { romans.firstIndex(of: $0) }, b = next.flatMap { romans.firstIndex(of: $0) }
        switch (a, b) {
        case (nil, .some(0)): return true
        case let (.some(x), .some(y)): return y == x + 1
        default: return false
        }
    }

    /// Does a page say it is a markscheme?
    public static func saysMarkscheme(_ lines: [Line]) -> Bool {
        lines.contains { l in
            let t = l.text.lowercased()
            return t.contains("markscheme") || t.contains("mark scheme") || t.contains("marking scheme") || t.trimmingCharacters(in: .whitespaces) == "answers" || t.contains("answer key")
        }
    }

    /// A sheet's questions, and its markscheme's when that is at the end of the same PDF (the run after a page that says so).
    public static func split(_ pages: [[Line]]) -> (paper: [Q], markscheme: [Q]?) {
        let rs = runs(pages)
        for k in rs.indices.dropFirst() {
            let start = rs[k][0].from.page, before = rs[k - 1].last?.from.page ?? 0
            if before <= start, (before...start).contains(where: { $0 < pages.count && saysMarkscheme(pages[$0]) }) {
                return (rs[..<k].flatMap { $0 }, rs[k...].flatMap { $0 })
            }
        }
        return (rs.flatMap { $0 }, nil)
    }

    /// The markscheme's place for a question: the same number and part, else the same number and letter, else the number.
    public static func matching(_ q: Q, in ms: [Q]) -> Q? {
        ms.first { $0.main == q.main && $0.sub == q.sub && $0.part == q.part }
            ?? ms.first { $0.main == q.main && $0.sub == q.sub && $0.part == nil }
            ?? ms.first { $0.main == q.main && $0.sub == nil }
            ?? ms.first { $0.main == q.main }
    }

    /// The questions of a paper that have no parts of their own (what is answered and marked).
    public static func leaves(_ qs: [Q]) -> [Q] {
        qs.enumerated().filter { i, q in
            guard i + 1 < qs.count else { return true }
            let n = qs[i + 1]
            let parent = n.main == q.main && ((q.sub == nil && n.sub != nil) || (q.sub != nil && q.part == nil && n.sub == q.sub && n.part != nil))
            return !parent
        }.map(\.element)
    }

    // MARK: a question's words (bank.rs)

    /// The words in a region of the paper, from one spot to another (pages from 0, y as a fraction of the page).
    public static func regionText(_ pages: [[Line]], from: Spot, to: Spot) -> String {
        var out: [String] = []
        for (p, lines) in pages.enumerated() where p >= from.page && p <= to.page {
            for l in lines {
                let after = p > from.page || l.y >= from.y - 1e-6
                let before = p < to.page || l.y < to.y - 1e-6
                if after && before { out.append(l.text.trimmingCharacters(in: .whitespaces)) }
            }
        }
        return out.joined(separator: "\n")
    }

    /// The marks printed with a question: "[3]", "[3 marks]", "(3 marks)"; a region holding several is their sum.
    public static func marks(_ text: String) -> Int? {
        let b = Array(text)
        var sum = 0, found = false
        var i = 0
        while i < b.count {
            if b[i] == "[" || b[i] == "(" {
                let close: Character = b[i] == "[" ? "]" : ")"
                var j = i + 1
                while j < b.count, b[j] == " " { j += 1 }
                let d0 = j
                while j < b.count, isDigit(b[j]) { j += 1 }
                if j > d0 && j - d0 <= 2 {
                    let n = Int(String(b[d0..<j])) ?? 0
                    let rest = String(String(b[j..<min(b.count, j + 8)]).lowercased().drop { $0.isWhitespace })
                    let ok = rest.hasPrefix(String(close)) || ((rest.hasPrefix("mark") || rest.hasPrefix("mk")) && b[j...].contains(close))
                    // "(3 marks)" counts, a bare "(3)" only in square brackets (round ones are often parts or references)
                    if ok && (close == "]" || !rest.hasPrefix(String(close))) && n > 0 && n <= 30 { sum += n; found = true }
                }
            }
            i += 1
        }
        return found ? sum : nil
    }

    /// The IB's command terms (the first word of a question's sentence, usually).
    public static let commands = [
        "analyse", "annotate", "apply", "calculate", "classify", "comment", "compare", "construct", "contrast", "deduce", "define",
        "demonstrate", "derive", "describe", "design", "determine", "discuss", "distinguish", "draw", "estimate", "evaluate", "explain",
        "formulate", "identify", "interpret", "justify", "label", "list", "measure", "outline", "predict", "sketch", "state", "suggest",
    ]

    /// The words after a question's own number and letters ("3a(ii) Explain why…" -> "Explain why…").
    static func afterLead(_ line: String) -> Substring {
        let t = Substring(line.drop { $0.isWhitespace })
        let b = Array(t.utf8)
        func lower(_ c: UInt8) -> Bool { c >= 97 && c <= 122 }
        func digit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }
        func starts(_ at: Int, _ w: String) -> Bool { Array(w.utf8).enumerated().allSatisfy { at + $0.offset < b.count && b[at + $0.offset] == $0.element } }
        var i = 0
        while i < b.count {
            let c = b[i]
            let nextOk = i + 1 >= b.count || !lower(b[i + 1]) || [105, 118, 120].contains(b[i])
            let ok = digit(c) || c == 32 || c == 46 || c == 40 || c == 41 || (i > 0 && lower(c) && (digit(b[i - 1]) || b[i - 1] == 40) && nextOk)
            if !ok { break }
            // stop at a real word
            if lower(c), i + 1 < b.count, lower(b[i + 1]), !starts(i, "ii"), !starts(i, "iv"), !starts(i, "vi") { break }
            i += 1
        }
        let idx = t.utf8.index(t.utf8.startIndex, offsetBy: i)
        return t[idx...]
    }

    /// The question's command term: the first IB term its words start a sentence with.
    public static func command(_ text: String) -> String? {
        for (k, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let words = k == 0 ? afterLead(String(line)) : Substring(line)
            for (w, word) in words.split(whereSeparator: { !$0.isLetter }).enumerated() {
                let lw = word.lowercased()
                if commands.contains(lw) && (w == 0 || word.first?.isUppercase == true) { return lw }
                if w > 12 { break }
            }
        }
        return nil
    }

    /// A multiple-choice question: at least three of its lines start with the options A to D.
    public static func isMcq(_ text: String) -> Bool {
        var seen = Set<Character>()
        for l in text.split(separator: "\n") {
            let t = Array(l.drop { $0.isWhitespace })
            if t.count >= 2, "ABCD".contains(t[0]), t[1] == "." || t[1] == ")" || t[1] == " " || t[1] == "\t" { seen.insert(t[0]) }
        }
        return seen.count >= 3
    }
}
