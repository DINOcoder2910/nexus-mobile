import Foundation

/// The question bank's files and rules, as the laptop's new app keeps them (nexus `desktop/backend/src/bank.rs`, docs/data-format.md
/// "The question bank"). Two files in a subject's `study/` folder, both YAML with one JSON line per entry so the hub merges them by line:
/// - `questions.yaml`: per paper (its path in the data folder: a PDF, or a board for questions marked on it), the paper's facts and each
///   question's sort (`from`/`to` on the paper, topics, type, command, marks, difficulty, how sure, by whom; a box `rect` and a `label`
///   for one marked on a board); what was changed by hand sits under `mine` and always wins over a new sort.
/// - `question-marks.yaml`: the marks (`"<paper>#<q>": {mark: done|hard|review, at}`), the papers pinned as Working on, and bookmarks.
///
/// The iPad and iPhone don't sort papers (the decision model runs on the laptop or the G14): they read the sorts, and write marks,
/// pins, bookmarks, fixes under `mine`, and questions marked on a board. A line they don't change is written back as it was read, so
/// the laptop's file comes back byte for byte apart from the lines that changed. How much is written on a question is read from the
/// boards, never stored. Pure.
public enum QuestionBank {
    public static let questionsFile = "study/questions.yaml"
    public static let marksFile = "study/question-marks.yaml"
    public static let types = ["mcq", "short", "structured", "data"]
    public static let typeWord = ["mcq": "Multiple choice", "short": "Short answer", "structured": "Structured", "data": "Data-based"]
    public static let markWord = ["done": "Done", "hard": "Hard", "review": "Review later"]
    public static let marks = ["done", "hard", "review"]
    /// How far above a line's box a question's place starts (a fraction of the page).
    public static let linePad = 0.012

    /// "c3" -> "Question 3", "3a(ii)" -> "3(a)(ii)".
    public static func qName(_ q: String) -> String {
        if q.range(of: #"^c\d+$"#, options: .regularExpression) != nil { return "Question " + q.dropFirst() }
        guard let r = q.range(of: #"^(\d+)([a-h])"#, options: .regularExpression) else { return q }
        let head = q[r]
        return "\(head.dropLast())(\(head.last!))" + q[r.upperBound...]
    }

    /// "May 2023 · Paper 2 · HL"
    public static func paperFacts(_ f: JSONValue?) -> String {
        let year = f?["year"]?.number.map { String(Int($0)) }
        let first: String? = (f?["session"]?.string).flatMap { s in year.map { "\(s) \($0)" } } ?? year
        return [first, f?["paper"]?.string.map { "Paper \($0)" }, f?["level"]?.string].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "easy", "medium", "hard" from a difficulty of 0 to 10.
    public static func level(_ d: Double?) -> String? {
        guard let d else { return nil }
        return d < 3.5 ? "easy" : d < 6.5 ? "medium" : "hard"
    }

    // MARK: one entry, kept as it was read

    /// A JSON value with the text it was read from: written back unchanged unless it was changed.
    public struct Entry: Equatable {
        public var value: JSONValue
        var raw: String?
        public init(_ value: JSONValue) { self.value = value }
        init(raw: String, value: JSONValue) { self.raw = raw; self.value = value }
        var text: String { raw ?? value.text }
        public static func == (a: Entry, b: Entry) -> Bool { a.value == b.value }
    }

    /// An ordered list of keyed entries (the order is the file's, a new key goes at the end).
    public struct Keyed: Equatable {
        public var items: [(key: String, entry: Entry)] = []
        public init() {}
        public subscript(_ k: String) -> JSONValue? {
            get { items.first { $0.key == k }?.entry.value }
            set {
                if let i = items.firstIndex(where: { $0.key == k }) {
                    if let newValue { if items[i].entry.value != newValue { items[i].entry = Entry(newValue) } } else { items.remove(at: i) }
                } else if let newValue { items.append((k, Entry(newValue))) }
            }
        }
        public var keys: [String] { items.map(\.key) }
        public var isEmpty: Bool { items.isEmpty }
        public static func == (a: Keyed, b: Keyed) -> Bool { a.items.count == b.items.count && zip(a.items, b.items).allSatisfy { $0.key == $1.key && $0.entry == $1.entry } }
    }

    // MARK: questions.yaml

    public struct Paper: Equatable {
        public var path: String
        public var facts = Entry(.object([]))
        public var questions = Keyed()
        public var mine = Keyed()
        public init(path: String) { self.path = path }

        /// A question's sort as it shows: the decision model's or Claude's, with the hand changes over it (`fixed` names them).
        public func merged(_ q: String) -> JSONValue? {
            guard var v = questions[q] else { return nil }
            if let m = mine[q]?.object {
                for (k, x) in m { v = v.setting(k, x) }
                v = v.setting("fixed", .array(m.map { .string($0.0) }))
            }
            return v
        }
        public var isClass: Bool { facts.value["kind"]?.string == "class" }
    }

    public struct Questions: Equatable {
        public var papers: [Paper] = []
        public init() {}
        public subscript(_ path: String) -> Paper? {
            get { papers.first { $0.path == path } }
            set {
                if let i = papers.firstIndex(where: { $0.path == path }) {
                    if let newValue { papers[i] = newValue } else { papers.remove(at: i) }
                } else if let newValue { papers.append(newValue) }
            }
        }

        static let header = "# Written by Nexus (Study › Question bank): each question of your papers, sorted once per paper.\n# facts = the paper's year, session, paper and level; questions = the sort (by the decision model or Claude, with how sure);\n# mine = what you changed by hand, which a new sort never overwrites.\npapers:\n"

        /// The file's text, as the laptop writes it.
        public var text: String {
            var s = Self.header
            for p in papers {
                s += "  \(JSONValue.string(p.path).text):\n"
                s += "    facts: \(p.facts.text)\n"
                for (name, part) in [("questions", p.questions), ("mine", p.mine)] where !part.isEmpty {
                    s += "    \(name):\n"
                    for it in part.items { s += "      \(JSONValue.string(it.key).text): \(it.entry.text)\n" }
                }
            }
            return s
        }

        /// Reads the file (none or empty: no papers). Nil when it isn't the shape Nexus writes (a hand edit in another YAML style):
        /// such a file is shown as far as it reads elsewhere and never written over here.
        public static func parse(_ text: String?) -> Questions? {
            var out = Questions()
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return out }
            var inPapers = false
            var part: String?
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
                let body = line.drop { $0 == " " }
                if body.isEmpty || body.hasPrefix("#") { continue }
                let indent = line.count - body.count
                guard let (key, rest) = QuestionBank.keyLine(String(body)) else { return nil }
                switch indent {
                case 0:
                    guard key == "papers" else { continue }
                    if rest == "{}" { inPapers = false; continue }
                    guard rest.isEmpty else { return nil }
                    inPapers = true
                case 2:
                    guard inPapers, rest.isEmpty else { return nil }
                    out.papers.append(Paper(path: key))
                    part = nil
                case 4:
                    guard inPapers, !out.papers.isEmpty else { return nil }
                    if key == "facts" {
                        guard let e = QuestionBank.entry(rest) else { return nil }
                        out.papers[out.papers.count - 1].facts = e
                        part = nil
                    } else if key == "questions" || key == "mine" {
                        if rest == "{}" { part = nil; continue }
                        guard rest.isEmpty else { return nil }
                        part = key
                    } else {
                        part = nil // a key the laptop doesn't write either: left out, as the laptop's own rewrite leaves it out
                    }
                case 6:
                    guard let part, !out.papers.isEmpty, let e = QuestionBank.entry(rest) else { return nil }
                    if part == "questions" { out.papers[out.papers.count - 1].questions.items.append((key, e)) } else { out.papers[out.papers.count - 1].mine.items.append((key, e)) }
                default:
                    return nil
                }
            }
            return out
        }
    }

    // MARK: question-marks.yaml

    public struct Marks: Equatable {
        public var marks = Keyed()
        public var pins = Keyed()
        public var bookmarks = Keyed()
        public init() {}

        public func mark(_ paper: String, _ q: String) -> String? { marks[paper + "#" + q]?["mark"]?.string }
        public func markedAt(_ paper: String, _ q: String) -> String? { marks[paper + "#" + q]?["at"]?.string }
        public func pinned(_ paper: String) -> Bool { pins[paper] != nil }
        public func bookmark(_ paper: String) -> String? { bookmarks[paper]?.string }

        /// Sets (or with nil takes back) a mark, dated today.
        public mutating func setMark(_ paper: String, _ q: String, _ mark: String?, today: String) {
            marks[paper + "#" + q] = mark.map { .object([("mark", .string($0)), ("at", .string(today))]) }
        }
        public mutating func setPin(_ paper: String, _ on: Bool, today: String) { pins[paper] = on ? .string(today) : nil }
        public mutating func setBookmark(_ paper: String, _ q: String?) { bookmarks[paper] = q.map { .string($0) } }

        static let header = "# Written by Nexus (Study › Question bank): your marks on questions (\"<paper>#<question>\": done, hard or review),\n# the sheets you pinned as Working on, and where you stopped on each (bookmarks). One line each.\n"

        public var text: String {
            var s = Self.header
            for (name, part) in [("marks", marks), ("pins", pins), ("bookmarks", bookmarks)] {
                if part.isEmpty { s += "\(name): {}\n"; continue }
                s += "\(name):\n"
                for it in part.items { s += "  \(JSONValue.string(it.key).text): \(it.entry.text)\n" }
            }
            return s
        }

        public static func parse(_ text: String?) -> Marks? {
            var out = Marks()
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return out }
            var part: String?
            for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
                let body = line.drop { $0 == " " }
                if body.isEmpty || body.hasPrefix("#") { continue }
                let indent = line.count - body.count
                guard let (key, rest) = QuestionBank.keyLine(String(body)) else { return nil }
                if indent == 0 {
                    part = nil
                    guard ["marks", "pins", "bookmarks"].contains(key) else { continue }
                    if rest == "{}" { continue }
                    if rest.hasPrefix("[") {
                        // the docs' first shape for pins, a list of papers: read as pinned with no date
                        guard key == "pins", case .array(let a)? = try? JSONValue.parse(rest) else { return nil }
                        for p in a { if let s = p.string { out.pins.items.append((s, Entry(.string("")))) } }
                        continue
                    }
                    guard rest.isEmpty else { return nil }
                    part = key
                } else if indent == 2 {
                    guard let part, let e = QuestionBank.entry(rest) else { return nil }
                    switch part {
                    case "marks": out.marks.items.append((key, e))
                    case "pins": out.pins.items.append((key, e))
                    default: out.bookmarks.items.append((key, e))
                    }
                } else {
                    return nil
                }
            }
            return out
        }
    }

    /// `"key": rest` or `key: rest` -> (key, rest); nil when the line isn't a key.
    static func keyLine(_ s: String) -> (String, String)? {
        if s.hasPrefix("\"") {
            // a JSON string, then ':'
            var i = s.index(after: s.startIndex), esc = false
            while i < s.endIndex {
                let c = s[i]
                if esc { esc = false } else if c == "\\" { esc = true } else if c == "\"" { break }
                i = s.index(after: i)
            }
            guard i < s.endIndex, case .string(let k)? = try? JSONValue.parse(String(s[...i])) else { return nil }
            let after = s[s.index(after: i)...]
            guard after.hasPrefix(":") else { return nil }
            return (k, after.dropFirst().trimmingCharacters(in: .whitespaces))
        }
        guard let c = s.range(of: ": ") ?? (s.hasSuffix(":") ? s.range(of: ":", options: .backwards) : nil) else { return nil }
        return (String(s[..<c.lowerBound]), s[c.upperBound...].trimmingCharacters(in: .whitespaces))
    }

    static func entry(_ rest: String) -> Entry? {
        guard !rest.isEmpty, let v = try? JSONValue.parse(rest) else { return nil }
        return Entry(raw: rest, value: v)
    }

    // MARK: changes

    /// The fields a hand change may set.
    public static let fixable = ["topics", "type", "difficulty", "command"]

    /// A hand change to a question's sort, kept under `mine` (a nil value takes that field back).
    public static func fix(_ p: inout Paper, _ q: String, _ set: [(String, JSONValue?)]) throws {
        var m = p.mine[q] ?? .object([])
        for (k, v) in set {
            guard fixable.contains(k) else { throw BankError("can't change \(k)") }
            if k == "type", let t = v?.string, !types.contains(t) { throw BankError("not a type") }
            m = m.setting(k, v == .null ? nil : v)
        }
        p.mine[q] = (m.object?.isEmpty ?? true) ? nil : m
    }

    public struct BankError: Error, CustomStringConvertible {
        public let description: String
        init(_ d: String) { description = d }
    }

    /// Mark as question: a box drawn round something on a board becomes a question of that board's "paper" (c1, c2, …). The board's
    /// facts are made the first time (`source` is its board.json `source`: a Schoology class board's course, date and codes). `words`
    /// are the words read under the box (from a printout it is over), for its marks, command term and type. Returns the question's key.
    @discardableResult
    public static func addMarked(_ qs: inout Questions, board: String, rect: [Double], label: String?, words: String, source: JSONValue?, today: String) -> String {
        var p = qs[board] ?? Paper(path: board)
        if p.facts.value.object?.isEmpty ?? true {
            var facts: JSONValue = .object([("kind", .string("class")), ("made", .string(today)), ("from", .string(boardName(board)))])
            for (k, to) in [("class_date", "classDate"), ("course", "course"), ("link", "link"), ("unit", "unit")] {
                if let v = source?[k], v != .null { facts = facts.setting(to, v) }
            }
            if let c = source?["codes"], let a = c.array, !a.isEmpty { facts = facts.setting("codes", c) }
            p.facts = Entry(facts)
        }
        let codes = p.facts.value["codes"]?.array ?? []
        let n = (1...).first { p.questions["c\($0)"] == nil }!
        let q = "c\(n)"
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let mcq = QuestionFinder.isMcq(text)
        let v: JSONValue = .object([
            ("rect", .array(rect.map { .number($0) })), ("label", .string(label ?? "Question \(n)")), ("topics", .array(codes)),
            ("type", .string(mcq ? "mcq" : "short")), ("marks", QuestionFinder.marks(text).map { .number(Double($0)) } ?? .null),
            ("command", QuestionFinder.command(text).map { .string($0) } ?? .null), ("made", .string(today)), ("by", .string("none")),
        ])
        p.questions[q] = v
        qs[board] = p
        return q
    }

    // MARK: paths

    /// A board's name ("notebooks/Chem/P2.board" -> "P2").
    public static func boardName(_ p: String) -> String {
        let b = (p as NSString).lastPathComponent
        return b.hasSuffix(".board") ? String(b.dropLast(6)) : b
    }

    /// A data-folder path as a board's items write it, relative to the board's folder (the laptop's `rel_to`).
    public static func relTo(board: String, _ path: String) -> String {
        let a = board.split(separator: "/", omittingEmptySubsequences: false), b = path.split(separator: "/", omittingEmptySubsequences: false)
        var i = 0
        while i < a.count && i + 1 < b.count && a[i] == b[i] { i += 1 }
        return (Array(repeating: "..", count: a.count - i) + b[i...].map(String.init)).joined(separator: "/")
    }

    /// A path relative to a board folder as a data-folder path; nil when it leaves the folder (the laptop's `resolve_in`).
    public static func resolveIn(board: String, _ rel: String) -> String? {
        if rel.isEmpty || rel.hasPrefix("/") || rel.contains("\\") || rel.range(of: #"^[A-Za-z]+:"#, options: .regularExpression) != nil { return nil }
        var out = board.isEmpty ? [] : board.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for s in rel.split(separator: "/", omittingEmptySubsequences: false) {
            switch s {
            case "", ".": continue
            case "..": if out.popLast() == nil { return nil }
            default: out.append(String(s))
            }
        }
        return out.joined(separator: "/")
    }

    /// The old board beside a PDF ("a/P2.pdf" -> "a/P2.board").
    public static func besideBoard(_ pdf: String) -> String {
        let dir = (pdf as NSString).deletingLastPathComponent, name = (pdf as NSString).lastPathComponent
        let stem = name.lastIndex(of: ".").map { String(name[..<$0]) } ?? name
        return dir.isEmpty ? stem + ".board" : dir + "/" + stem + ".board"
    }

    /// Where a paper's board goes when it is first written on: the subject's notebook › Papers › the paper's unit folder (the first
    /// folder under the sheets folder), named after the paper. `notebook` is the subject's notebook (the first, by path, whose
    /// notebook.json names the subject, else `notebooks/<subject's name>`).
    public static func papersBoard(pdf: String, sheetsRoot: String?, notebook: String) -> String {
        let name = (pdf as NSString).lastPathComponent
        let stem = name.lastIndex(of: ".").map { String(name[..<$0]) } ?? name
        var unit = ""
        if let r = sheetsRoot, pdf.hasPrefix(r.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/") {
            let within = String(pdf.dropFirst(r.trimmingCharacters(in: CharacterSet(charactersIn: "/")).count + 1))
            let dir = (within as NSString).deletingLastPathComponent
            unit = dir.split(separator: "/").first.map(String.init) ?? ""
        }
        return unit.isEmpty ? "\(notebook)/Papers/\(stem).board" : "\(notebook)/Papers/\(unit)/\(stem).board"
    }

    /// The subject's notebook from the top-level notebooks and the subject each names in its notebook.json.
    public static func subjectNotebook(_ notebooks: [(path: String, subject: String?)], subject: String, name: String) -> String {
        notebooks.filter { $0.subject == subject }.map(\.path).min() ?? "notebooks/\(name)"
    }

    // MARK: where a question is on a board, and how much is written there

    /// The rectangles a region of a paper covers on a board (board units), through its printout's pages (Insert space included).
    public static func regionRects(_ segs: [BoardFiles.PdfSegment], from: QuestionFinder.Spot, to: QuestionFinder.Spot) -> [[Double]] {
        var out: [[Double]] = []
        for g in segs where g.page >= from.page && g.page <= to.page {
            let a = g.page == from.page ? from.y : 0, b = g.page == to.page ? to.y : 1
            let lo = max(a, g.top), hi = min(b, g.bottom)
            if hi <= lo { continue }
            let span = max(g.bottom - g.top, 1e-9)
            out.append([g.x, g.y + (lo - g.top) / span * g.h, g.x + g.w, g.y + (hi - g.top) / span * g.h])
        }
        return out
    }

    /// A question's place on a board from its `from` and `to`: a little above each line's box, so the clip shows the whole first line
    /// and stops above the next question.
    public static func place(_ q: JSONValue, segs: [BoardFiles.PdfSegment]) -> [[Double]]? {
        guard var from = QuestionFinder.Spot(q["from"]), var to = QuestionFinder.Spot(q["to"]) else { return nil }
        from.y = max(0, from.y - linePad)
        if to.y < 1 { to.y = max(0, to.y - linePad) }
        return regionRects(segs, from: from, to: to)
    }

    /// A marked question's box.
    public static func rect(_ q: JSONValue) -> [Double]? {
        guard let a = q["rect"]?.array, a.count >= 4 else { return nil }
        let n = a.prefix(4).compactMap(\.number)
        return n.count == 4 ? n : nil
    }

    /// What is drawn on a board: every stroke's box and when its tile was saved, the text blocks' boxes.
    public struct Ink {
        public var strokes: [(box: [Double], when: Double)] = []
        public var texts: [[Double]] = []
        public init() {}
    }

    /// A stroke's box from its points.
    public static func box(_ s: BoardStroke) -> [Double]? {
        guard let f = s.points.first, f.count >= 2 else { return nil }
        var b = [f[0], f[1], f[0], f[1]]
        for p in s.points where p.count >= 2 { b = [min(b[0], p[0]), min(b[1], p[1]), max(b[2], p[0]), max(b[3], p[1])] }
        return b
    }

    /// How much is written in some rectangles: the strokes there (a text block counts 3), and when the latest of their tiles was saved.
    /// A stroke belongs to the question its middle is level with (in the margin beside it too), so a line that brushes the next
    /// question's top doesn't count there.
    public static func inkIn(_ ink: Ink, _ rects: [[Double]]) -> (strokes: Int, last: Double) {
        var n = 0, last = 0.0
        func holds(_ b: [Double], _ r: [Double]) -> Bool {
            let cx = (b[0] + b[2]) / 2, cy = (b[1] + b[3]) / 2, w = r[2] - r[0]
            return cy >= r[1] && cy < r[3] && cx >= r[0] - w && cx <= r[2] + w
        }
        func overlaps(_ a: [Double], _ b: [Double]) -> Bool { a[0] < b[2] && b[0] < a[2] && a[1] < b[3] && b[1] < a[3] }
        for s in ink.strokes where rects.contains(where: { holds(s.box, $0) }) { n += 1; last = max(last, s.when) }
        for t in ink.texts where rects.contains(where: { overlaps(t, $0) }) { n += 3 }
        return (n, last)
    }

    /// "none", "some", "plenty", from the strokes in a question's place and its marks.
    public static func writtenWord(_ strokes: Int, marks: Int?) -> String {
        let want = max((marks ?? 2) * 4, 4)
        return strokes == 0 ? "none" : strokes * 2 < want ? "some" : "plenty"
    }

    // MARK: the list

    /// One question as the bank lists it.
    public struct Row: Identifiable, Equatable {
        public var paper: String
        public var q: String
        public var title: String
        public var isClass: Bool
        public var facts: JSONValue
        public var sort: JSONValue
        public var mark: String?
        public var markedAt: String?
        public var written: String
        public var strokes: Int
        public var lastWritten: String?
        public var board: String?
        public var pinned: Bool
        public var bookmark: Bool
        public var id: String { paper + "#" + q }

        public init(paper: String, q: String, title: String, isClass: Bool, facts: JSONValue, sort: JSONValue, mark: String? = nil, markedAt: String? = nil,
                    written: String = "none", strokes: Int = 0, lastWritten: String? = nil, board: String? = nil, pinned: Bool = false, bookmark: Bool = false) {
            self.paper = paper; self.q = q; self.title = title; self.isClass = isClass; self.facts = facts; self.sort = sort; self.mark = mark
            self.markedAt = markedAt; self.written = written; self.strokes = strokes; self.lastWritten = lastWritten; self.board = board
            self.pinned = pinned; self.bookmark = bookmark
        }
        public var topics: [String] { sort["topics"]?.array?.compactMap(\.string) ?? [] }
        public var type: String { sort["type"]?.string ?? "short" }
        public var command: String? { sort["command"]?.string }
        public var marks: Int? { sort["marks"]?.number.map { Int($0) } }
        public var difficulty: Double? { sort["difficulty"]?.number }
        public var sure: Double? { sort["sure"]?.number }
        public var by: String { sort["by"]?.string ?? "none" }
        public var label: String? { sort["label"]?.string }
        public var fixed: [String] { sort["fixed"]?.array?.compactMap(\.string) ?? [] }

        /// "R1.2 · Short answer · 3 marks · Calculate · medium"
        public var meta: String {
            var parts: [String] = [topics.joined(separator: ", ")]
            parts.append(typeWord[type] ?? type)
            if let m = marks { parts.append(m == 1 ? "1 mark" : "\(m) marks") }
            if let c = command { parts.append(c.prefix(1).uppercased() + String(c.dropFirst())) }
            if let l = level(difficulty) { parts.append(l) }
            return parts.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// The bank's filters (each empty = any).
    public struct Filter: Equatable {
        public var find = "", unit = "", type = "", command = "", mark = "", written = "", difficulty = "", source = "", level = "", paper = ""
        public var pinned = false
        public init() {}
        public var any: Bool { !(find + unit + type + command + mark + written + difficulty + source + level).isEmpty }
    }

    /// Does a question pass the filters? (bank.rs `keep`)
    public static func keep(_ r: Row, _ f: Filter) -> Bool {
        if !f.paper.isEmpty && r.paper != f.paper { return false }
        if !f.unit.isEmpty {
            let u = f.unit
            if !r.topics.contains(where: { $0 == u || $0.hasPrefix(u + ".") || u.hasPrefix($0 + ".") }) { return false }
        }
        if !f.type.isEmpty && r.type != f.type { return false }
        if !f.command.isEmpty && r.command != f.command { return false }
        // a question's own level (a textbook's SL and HL blocks) over its paper's, as the laptop's bank.rs keep()
        if !f.level.isEmpty && (r.sort["level"]?.string ?? r.facts["level"]?.string) != f.level { return false }
        switch f.mark {
        case "": break
        case "none": if r.mark != nil { return false }
        default: if r.mark != f.mark { return false }
        }
        switch f.written {
        case "none": if r.written != "none" { return false }
        case "started": if r.written != "some" { return false }
        case "plenty": if r.written != "plenty" { return false }
        default: break
        }
        if !f.difficulty.isEmpty {
            let v = r.difficulty
            let ok: Bool
            switch f.difficulty {
            case "easy": ok = v.map { $0 < 3.5 } ?? false
            case "medium": ok = v.map { $0 >= 3.5 && $0 < 6.5 } ?? false
            case "hard": ok = (v.map { $0 >= 6.5 } ?? false) || r.mark == "hard"
            default: ok = true
            }
            if !ok { return false }
        }
        if f.source == "class" && !r.isClass { return false }
        if f.source == "papers" && r.isClass { return false }
        if f.pinned && !r.pinned { return false }
        if !f.find.isEmpty {
            let hay = "\(r.title) \(r.q) \(JSONValue.array(r.topics.map { .string($0) }).text)".lowercased()
            if !hay.contains(f.find.lowercased()) { return false }
        }
        return true
    }

    /// Pinned papers first, then the paper order; or the last written on first.
    public static func ordered(_ rows: [Row], recent: Bool) -> [Row] {
        var out = rows.enumerated().sorted { a, b in a.element.pinned != b.element.pinned ? a.element.pinned : a.offset < b.offset }.map(\.element)
        if recent {
            out = out.enumerated().sorted { a, b in
                let x = a.element.lastWritten ?? "", y = b.element.lastWritten ?? ""
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
        return out
    }
}
