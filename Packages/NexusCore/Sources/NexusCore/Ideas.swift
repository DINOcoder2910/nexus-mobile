import Foundation
import Yams

/// Ideas: the inbox in the data folder's nexus-ideas.yaml (nexus docs/data-format.md "Ideas"), the same file the laptop's Customize ›
/// Ideas shows. The user dumps ideas as they come (dictation is fine); Claude sorts the new ones in batches (a topic, a tidy title, a
/// repeat linked to the idea it repeats) and never changes what was written ("text"). Each idea has who does it: Claude or me.
/// This mirrors the laptop's renderer/src/ideas.js: the same keys, ids, batch rules and prompt, and the file is written in the same
/// style as the laptop's YAML writer, so a sync merge sees only the lines that changed. A conflict copy the hub made is folded in by id.
public struct Idea: Equatable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var title: String?
    public var note: String?
    public var topic: String?
    public var kind: String?
    public var added: String?
    public var from: String?
    public var organised: String?
    public var sameAs: String?
    public var who: String?
    public var sent: String?
    public var reply: String?
    public var done: String?
    public var edited: String?
    /// Keys of the user's own, kept as written (key, YAML for its value).
    public var extra: [Extra] = []

    public struct Extra: Equatable, Sendable { public var key: String; public var yaml: String }

    public init(id: String, text: String) { self.id = id; self.text = text }
    public var shownTitle: String { (title?.isEmpty == false ? title : nil) ?? text }
    /// What was written, shown under a tidied title when it says more than the title.
    public var originalShown: Bool { guard let t = title else { return false }; return Ideas.line(text).lowercased() != Ideas.line(t).lowercased() }
    public var isWaiting: Bool { done == nil && organised == nil }
}

public enum Ideas {
    public static let file = "nexus-ideas.yaml"
    public static let todoFile = "nexus-todo.yaml"
    public static let kinds = ["nexus", "app", "project", "life", "other"]
    public static let kindLabel = ["nexus": "Change to Nexus", "app": "App idea", "project": "Project", "life": "Life", "other": "Other"]
    public static let batchMax = 20
    public static let batchAt = 5
    static let head = "# Ideas: anything you want to do or try. Claude sorts new ones into topics in batches; what you wrote stays in \"text\".\n# Edit them in Nexus (Customize › Ideas, the iPad's Ideas) or here.\n"
    static let fence = "\u{60}\u{60}\u{60}"

    // MARK: text helpers

    static func trim(_ s: String?) -> String { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    static func line(_ s: String?) -> String { trim(s).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }

    /// FNV-1a over the words (lowercased, spaces folded), base 36: the laptop's wordsId, the same id on every device.
    public static func wordsId(_ s: String, prefix: String = "w") -> String {
        var h: UInt32 = 0x811c9dc5
        for u in line(s).lowercased().unicodeScalars { h ^= u.value; h = h &* 0x01000193 }
        let b = String(h, radix: 36)
        return prefix + String(repeating: "0", count: max(0, 7 - b.count)) + b
    }
    public static func newId(taken: Set<String>) -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        while true {
            let s = "i" + String((0..<7).map { _ in chars[Int.random(in: 0..<36)] })
            if !taken.contains(s) { return s }
        }
    }

    // MARK: reading

    public struct Parsed: Equatable, Sendable {
        public var items: [Idea]
        public var error: String?
        /// The ideas came from the To-do list (there is no nexus-ideas.yaml yet).
        public var fromTodo = false
    }

    /// The file's text (nil: no file yet; then the To-do list's items, its starter when it has no file either).
    public static func parse(_ text: String?, todo: String? = nil) -> Parsed {
        guard let text else { return Parsed(items: fromTodos(todo), error: nil, fromTodo: true) }
        let root: Node?
        do { root = try Yams.compose(yaml: text) } catch { return Parsed(items: [], error: "does not parse (" + TaskFile.yamlMessage(error) + ")") }
        guard let root else { return Parsed(items: [], error: nil) }
        var list: [Node] = []
        if let seq = root.sequence { list = Array(seq) }
        else if let m = root.mapping {
            if let v = TaskFile.value(m, "ideas") {
                if let s = v.sequence { list = Array(s) }
                else if !(v.scalar != nil && (trim(v.scalar?.string).isEmpty || v.scalar?.string == "null")) { return Parsed(items: [], error: "expected a list under \"ideas:\"") }
            }
        }
        else if root.scalar != nil && trim(root.scalar?.string).isEmpty { return Parsed(items: [], error: nil) }
        else { return Parsed(items: [], error: "expected a list under \"ideas:\"") }
        return Parsed(items: uniq(list.compactMap(item)), error: nil)
    }

    static func item(_ n: Node) -> Idea? {
        if let s = n.scalar { let t = trim(s.string); return t.isEmpty ? nil : Idea(id: wordsId(t), text: t) }
        guard let m = n.mapping else { return nil }
        var vals: [String: String] = [:]
        var extra: [Idea.Extra] = []
        let known: Set<String> = ["id", "text", "title", "note", "topic", "kind", "added", "from", "organised", "same_as", "who", "sent", "reply", "done", "edited"]
        for (k, v) in m {
            guard let key = k.scalar?.string else { continue }
            if known.contains(key) { if let s = v.scalar { vals[key] = s.string } }
            else if let y = try? Yams.serialize(node: v) { extra.append(.init(key: key, yaml: y.hasSuffix("\n") ? String(y.dropLast()) : y)) }
        }
        let text = trim(vals["text"]).isEmpty ? trim(vals["title"]) : trim(vals["text"])
        guard !text.isEmpty else { return nil }
        let id = trim(vals["id"])
        var x = Idea(id: id.isEmpty ? wordsId(text) : id, text: text)
        func one(_ k: String, block: Bool = false) -> String? { let v = block ? trim(vals[k]) : line(vals[k]); return v.isEmpty ? nil : v }
        func day(_ k: String) -> String? { let v = trim(vals[k]); return v.isEmpty || v == "false" ? nil : v }
        x.title = one("title"); x.note = one("note", block: true); x.topic = one("topic"); x.from = one("from"); x.sameAs = one("same_as")
        x.reply = one("reply", block: true); x.edited = one("edited")
        x.added = day("added"); x.organised = day("organised"); x.sent = day("sent"); x.done = day("done")
        let kind = trim(vals["kind"]).lowercased(); x.kind = kinds.contains(kind) ? kind : nil
        let who = trim(vals["who"]).lowercased(); x.who = who == "claude" || who == "me" ? who : nil
        x.extra = extra
        return x
    }

    static func uniq(_ list: [Idea]) -> [Idea] {
        var seen = Set<String>()
        return list.enumerated().map { i, x in
            if !seen.contains(x.id) { seen.insert(x.id); return x }
            var y = x; y.id = wordsId(x.text + " " + String(i)); seen.insert(y.id); return y
        }
    }

    /// The To-do list's items (nexus-todo.yaml, or its starter when there is no file) as ideas sorted under Nexus: the laptop's fromTodos.
    public static func fromTodos(_ todo: String?) -> [Idea] {
        struct T { var title: String; var note: String? = nil; var added: String? = nil; var done: String? = nil }
        var todos: [T] = []
        if let todo {
            guard let parsed = try? Yams.compose(yaml: todo) else { return [] }
            var list: [Node] = []
            if let s = parsed.sequence { list = Array(s) } else if let m = parsed.mapping, let v = TaskFile.value(m, "todos"), let s = v.sequence { list = Array(s) }
            for n in list {
                if let s = n.scalar { let t = trim(s.string); if !t.isEmpty { todos.append(T(title: t)) }; continue }
                guard let m = n.mapping else { continue }
                let t = trim(TaskFile.value(m, "title")?.scalar?.string); if t.isEmpty { continue }
                func v(_ k: String) -> String? { let s = trim(TaskFile.value(m, k)?.scalar?.string); return s.isEmpty || s == "false" ? nil : s }
                todos.append(T(title: line(t), note: v("note"), added: v("added"), done: v("done")))
            }
        } else {
            todos = [T(title: "Make board text better", note: "Typed text on boards is good for now; polish it later.")]
        }
        return uniq(todos.map { t in
            let ends = t.title.last.map { ".!?…".contains($0) } ?? false
            var x = Idea(id: wordsId(t.title, prefix: "t"), text: t.note.map { (ends ? t.title : t.title + ".") + " " + $0 } ?? t.title)
            x.title = t.title; x.note = t.note; x.topic = "Nexus"; x.kind = "nexus"; x.added = t.added
            x.organised = t.added ?? "to-do"; x.done = t.done
            return x
        })
    }

    // MARK: writing (the laptop's yaml writer: plain scalars where it writes them plain, else quoted; a multi-line value as a block)

    public static func serialize(_ items: [Idea]) -> String {
        var out = head + "ideas:"
        if items.isEmpty { return out + " []\n" }
        out += "\n"
        for x in items {
            var rows: [(String, String)] = [("id", x.id), ("text", x.text)]
            let opt: [(String, String?)] = [("title", x.title), ("note", x.note), ("topic", x.topic), ("kind", x.kind), ("added", x.added), ("from", x.from), ("organised", x.organised),
                                             ("same_as", x.sameAs), ("who", x.who), ("sent", x.sent), ("reply", x.reply), ("done", x.done), ("edited", x.edited)]
            for (k, v) in opt { if let v, !v.isEmpty { rows.append((k, v)) } }
            for (i, r) in rows.enumerated() { out += (i == 0 ? "  - " : "    ") + r.0 + ":" + value(r.1, indent: 6) + "\n" }
            for e in x.extra {
                if e.yaml.contains("\n") { out += "    " + e.key + ":\n" + e.yaml.split(separator: "\n", omittingEmptySubsequences: false).map { "      " + $0 }.joined(separator: "\n") + "\n" }
                else { out += "    " + e.key + ": " + e.yaml + "\n" }
            }
        }
        return out
    }

    /// " value" after the key's colon, or " |-" and the lines of a multi-line value.
    static func value(_ s: String, indent: Int) -> String {
        if s.contains("\n") && !s.hasPrefix(" ") && !s.contains("\r") && !hasControl(s) {
            let trailing = s.hasSuffix("\n")
            var body = s; if trailing { body.removeLast() }
            if !body.hasSuffix("\n") {
                let pad = String(repeating: " ", count: indent)
                return " " + (trailing ? "|" : "|-") + "\n" + body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : pad + $0 }.joined(separator: "\n")
            }
        }
        return " " + scalar(s)
    }

    static func hasControl(_ s: String) -> Bool { s.unicodeScalars.contains { ($0.value < 0x20 && $0 != "\t" && $0 != "\n") || $0.value == 0x7f } }

    /// A one-line string as the laptop's yaml package writes it (YAML 1.2 core schema).
    public static func scalar(_ s: String) -> String {
        if s.isEmpty { return "\"\"" }
        if !needsQuotes(s) { return s }
        if s.contains("\"") && !s.contains("'") && !s.contains("\n") && !hasControl(s) { return "'" + s + "'" }
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            case "\n": o += "\\n"
            case "\t": o += "\\t"
            default:
                let named: [UInt32: String] = [0: "\\0", 7: "\\a", 8: "\\b", 11: "\\v", 12: "\\f", 13: "\\r", 27: "\\e"]
                if let e = named[u.value] { o += e } else if u.value < 0x20 || u.value == 0x7f { o += String(format: "\\x%02X", u.value) } else { o.unicodeScalars.append(u) }
            }
        }
        return o + "\""
    }

    static let reservedCore: Set<String> = ["null", "Null", "NULL", "~", "true", "True", "TRUE", "false", "False", "FALSE", ".nan", ".NaN", ".NAN", ".inf", ".Inf", ".INF", "+.inf", "+.Inf", "+.INF", "-.inf", "-.Inf", "-.INF"]
    static let indicators = "[]{}#&*!|>'\"%@,\u{60}"
    static func needsQuotes(_ s: String) -> Bool {
        if s.contains("\n") || hasControl(s) { return true }
        if s != s.trimmingCharacters(in: .whitespaces) { return true }
        if reservedCore.contains(s) { return true }
        if s.range(of: #"^[-+]?[0-9]+$|^0o[0-7]+$|^0x[0-9a-fA-F]+$|^[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?$"#, options: .regularExpression) != nil { return true }
        let first = s.first!
        if indicators.contains(first) { return true }
        if "-?:".contains(first) && (s.count == 1 || s.dropFirst().first == " ") { return true }
        if s.contains(": ") || s.contains(" #") || s.hasSuffix(":") { return true }
        return false
    }

    // MARK: the edits (each returns the new list; the same list when nothing changes)

    public static func stamp(_ d: Date = Date()) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }
    static func change(_ items: [Idea], _ id: String, now: String?, _ fn: (inout Idea) -> Bool) -> [Idea] {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return items }
        var y = items[i]
        guard fn(&y) else { return items }
        if let now { y.edited = now }
        var out = items; out[i] = y; return out
    }
    public static func add(_ items: [Idea], _ text: String, today: String?, now: String?, from: String?) -> [Idea] {
        var t = trim(text).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        t = t.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression).replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        guard !t.isEmpty else { return items }
        var x = Idea(id: newId(taken: Set(items.map(\.id))), text: t)
        x.added = today; x.from = from.map { line($0) }; x.edited = now
        return items + [x]
    }
    public static func rename(_ items: [Idea], _ id: String, _ title: String, now: String?) -> [Idea] {
        let t = line(title)
        return change(items, id, now: now) { y in guard !t.isEmpty, t != y.shownTitle else { return false }; y.title = t; return true }
    }
    /// claude, me, or nil (undecided); the same one again is undecided.
    public static func setWho(_ items: [Idea], _ id: String, _ who: String?, now: String?) -> [Idea] {
        change(items, id, now: now) { y in
            var w = who == "claude" || who == "me" ? who : nil
            if y.who == w { if w == nil { return false }; w = nil }
            y.who = w; return true
        }
    }
    public static func markSent(_ items: [Idea], _ id: String, today: String, reply: String?, now: String?) -> [Idea] {
        change(items, id, now: now) { y in y.who = "claude"; y.sent = today; let r = trim(reply); if !r.isEmpty { y.reply = r }; return true }
    }
    public static func tick(_ items: [Idea], _ id: String, today: String, now: String?) -> [Idea] {
        change(items, id, now: now) { y in y.done = y.done == nil ? today : nil; return true }
    }
    public static func unmerge(_ items: [Idea], _ id: String, now: String?) -> [Idea] {
        change(items, id, now: now) { y in guard y.sameAs != nil else { return false }; y.sameAs = nil; return true }
    }
    public static func remove(_ items: [Idea], _ id: String) -> [Idea] { items.filter { $0.id != id } }

    // MARK: what the screen shows

    public struct Row: Equatable, Sendable, Identifiable { public var idea: Idea; public var repeats: [Idea]; public var id: String { idea.id } }
    public struct Topic: Equatable, Sendable, Identifiable { public var name: String; public var rows: [Row]; public var id: String { name } }
    public struct Grouped: Equatable, Sendable { public var waiting: [Idea]; public var topics: [Topic]; public var done: [Row] }

    /// The laptop's groupIdeas: new ones as written; topics by name, undecided before Claude's before mine; a repeat under the idea it
    /// repeats (followed to the first that isn't one); done apart, latest first.
    public static func group(_ items: [Idea]) -> Grouped {
        let byId = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func root(_ x: Idea) -> Idea { var y = x; var seen = Set<String>(); while let s = y.sameAs, let n = byId[s], !seen.contains(y.id) { seen.insert(y.id); y = n }; return y }
        var repeats: [String: [Idea]] = [:]; var tops: [Idea] = []
        for x in items { let r = x.sameAs != nil ? root(x) : x; if r.id != x.id { repeats[r.id, default: []].append(x) } else { tops.append(x) } }
        let row = { (x: Idea) in Row(idea: x, repeats: repeats[x.id] ?? []) }
        let waiting = tops.filter(\.isWaiting)
        let done = tops.filter { $0.done != nil }.sorted { ($0.done ?? "") > ($1.done ?? "") }.map(row)
        func rank(_ x: Idea) -> Int { x.who == nil ? 0 : x.who == "claude" ? 1 : 2 }
        var order: [String] = []; var map: [String: [Idea]] = [:]
        for x in tops where x.done == nil && x.organised != nil { let t = x.topic ?? "Other"; if map[t] == nil { order.append(t) }; map[t, default: []].append(x) }
        let topics = order.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { t in
            Topic(name: t, rows: map[t]!.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map { row($0.element) })
        }
        return Grouped(waiting: waiting, topics: topics, done: done)
    }
    public static func openCount(_ items: [Idea]) -> Int { let g = group(items); return g.waiting.count + g.topics.reduce(0) { $0 + $1.rows.count } }
    public static func countLine(_ items: [Idea]) -> String {
        let g = group(items); let w = g.waiting.count; let open = w + g.topics.reduce(0) { $0 + $1.rows.count }
        return (open == 1 ? "1 idea" : "\(open) ideas") + (w > 0 ? " · \(w) new" : "")
    }
    /// A batch is due: 5 or more waiting, or one waiting since before today.
    public static func due(_ items: [Idea], today: String) -> Bool {
        let w = group(items).waiting
        return w.count >= batchAt || w.contains { ($0.added ?? today) < today }
    }

    // MARK: sorting a batch with Claude

    public static let organiseSystem = "You sort the user's ideas inbox. The user dumps ideas as they come, often dictated: app ideas, project ideas, things for their own life, and changes they want in Nexus (their personal workspace app). For each new idea you give a short tidy title in the user's own voice (fix dictation slips and filler, keep their meaning, no new ideas of your own), a note only when the idea has detail beyond the title (tidied, one or two sentences, else empty), a topic (reuse an existing topic when it fits; a new one is 1 to 3 words), a kind (nexus: a change to the Nexus app itself; app: an idea for some other app or software; project: something to make or study; life: personal life, health, people, errands; other), and same_as: the id of an earlier idea (existing or new) that this one repeats, or empty. Only mark a repeat when it is the same idea, not just the same topic. Answer only with the JSON asked for."
    /// The iPad asks without a schema (the Messages API and the hub take plain text), so it says the shape too.
    public static let organiseSystemPlain = organiseSystem + " The JSON is one object: {\"ideas\": [{\"id\": \"...\", \"title\": \"...\", \"note\": \"...\", \"topic\": \"...\", \"kind\": \"...\", \"same_as\": \"...\"}]}, with no other text."

    static func clip(_ s: String, _ n: Int) -> String { s.count > n ? String(s.prefix(n - 1)) + "…" : s }
    /// -> the batch (ids, oldest first, at most 20) and the prompt, word for word the laptop's organisePrompt.
    public static func organisePrompt(_ items: [Idea]) -> (batch: [String], prompt: String) {
        let batch = Array(group(items).waiting.prefix(batchMax))
        var order: [String] = []; var by: [String: [Idea]] = [:]
        for x in items where x.organised != nil && x.sameAs == nil { let t = x.topic ?? "Other"; if by[t] == nil { order.append(t) }; by[t, default: []].append(x) }
        var lines = ["(Nexus ideas sort)", ""]
        if !by.isEmpty {
            lines.append("Topics so far, with their ideas (id: title):")
            for t in order.sorted(by: { a, b in a.unicodeScalars.lexicographicallyPrecedes(b.unicodeScalars) }) {
                lines.append("## " + t)
                for x in by[t]!.suffix(40) { lines.append("- " + x.id + ": " + clip(x.shownTitle, 120) + (x.done != nil ? " (done)" : "")) }
            }
            lines.append("")
        } else { lines += ["There are no topics yet.", ""] }
        lines.append("New ideas to sort (id: what the user wrote):")
        for x in batch { lines.append("- " + x.id + ": " + clip(line(x.text), 1500)) }
        lines += ["", "Answer with {\"ideas\": [...]}: one entry for each new idea, by its id."]
        return (batch.map(\.id), lines.joined(separator: "\n"))
    }

    public struct Sorted: Equatable, Sendable {
        public var id, title, note, topic, kind, sameAs: String
        public init(id: String, title: String, note: String = "", topic: String, kind: String, sameAs: String = "") { self.id = id; self.title = title; self.note = note; self.topic = topic; self.kind = kind; self.sameAs = sameAs }
    }
    /// Claude's answer: JSON in a fenced block or bare. nil when there is none.
    public static func readReply(_ text: String) -> [Sorted]? {
        var body = text
        if let a = text.range(of: fence), let b = text.range(of: fence, range: a.upperBound..<text.endIndex) {
            body = String(text[a.upperBound..<b.lowerBound]); if body.hasPrefix("json") { body.removeFirst(4) }
        } else if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b { body = String(text[a...b]) }
        guard let d = body.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let list = o["ideas"] as? [[String: Any]] else { return nil }
        return list.map { e in
            func s(_ k: String) -> String { (e[k] as? String) ?? "" }
            return Sorted(id: s("id"), title: s("title"), note: s("note"), topic: s("topic"), kind: s("kind"), sameAs: s("same_as"))
        }
    }

    /// The laptop's applyOrganise: only the batch, each once, only what checks out; "text" is never touched.
    public static func applyOrganise(_ items: [Idea], _ reply: [Sorted], batch: [String], today: String, now: String?) -> (items: [Idea], sorted: Int, topics: [String]) {
        let want = Set(batch); let ids = Set(items.map(\.id))
        let before = Set(items.filter { $0.organised != nil && $0.topic != nil }.map { $0.topic!.lowercased() })
        var got: [String: Sorted] = [:]
        for e in reply { let id = trim(e.id); if want.contains(id), ids.contains(id), got[id] == nil { got[id] = e } }
        func topicName(_ t: String) -> String { let s = clip(line(t), 40); return items.first { $0.topic?.lowercased() == s.lowercased() }?.topic ?? s }
        var next = items.map { x -> Idea in
            guard let e = got[x.id] else { return x }
            var y = x
            let title = clip(line(e.title), 120); if !title.isEmpty { y.title = title }
            let note = trim(e.note); if !note.isEmpty && note.lowercased() != (y.title ?? "").lowercased() { y.note = clip(note, 600) } else { y.note = nil }
            let topic = topicName(e.topic); y.topic = topic.isEmpty ? (y.topic ?? "Other") : topic
            let kind = trim(e.kind).lowercased(); if kinds.contains(kind) { y.kind = kind }
            let s = trim(e.sameAs); y.sameAs = !s.isEmpty && s != x.id && ids.contains(s) ? s : nil
            y.organised = today
            if let now { y.edited = now }
            return y
        }
        // a repeat that leads back to itself is not a repeat
        var nb = Dictionary(next.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for i in next.indices where next[i].sameAs != nil && got[next[i].id] != nil {
            var seen: Set<String> = [next[i].id]; var y = nb[next[i].sameAs!]
            while let yy = y, let s = yy.sameAs, !seen.contains(yy.id) { seen.insert(yy.id); y = nb[s] }
            if let yy = y, seen.contains(yy.id) { next[i].sameAs = nil; nb[next[i].id] = next[i] }
        }
        var topics: [String] = []
        for x in next where got[x.id] != nil { if let t = x.topic, !before.contains(t.lowercased()), !topics.contains(t) { topics.append(t) } }
        return (next, got.count, topics)
    }
    public static func sortedLine(_ n: Int, _ topics: [String]) -> String {
        "Sorted " + (n == 1 ? "1 idea" : "\(n) ideas") + (topics.isEmpty ? "" : "; new " + (topics.count == 1 ? "topic" : "topics") + ": " + topics.joined(separator: ", ")) + "."
    }

    // MARK: sending one to Claude

    /// A change to Nexus waits for the laptop's change door; anything else Claude works on here.
    public static func goesToDoor(_ x: Idea) -> Bool { x.kind == "nexus" }
    public static let workSystem = "The user keeps an ideas inbox and asked you to work on one idea. Do the useful first piece of work: if it is something to make or decide, a short plan (3 to 6 concrete steps), the first step done where you can (a draft, a list, an outline), and at most 3 questions that would change the plan. Plain text with short lines and simple \"-\" lists, no headings, under 300 words. Write to the user directly."
    public static func workPrompt(_ x: Idea, repeats: [Idea] = []) -> String {
        var lines = ["(Nexus ideas work)", "", "The idea: " + x.shownTitle]
        if let n = x.note { lines.append("Its note: " + n) }
        if x.originalShown { lines.append("What the user wrote: " + line(x.text)) }
        for r in repeats { lines.append("Also written as: " + line(r.text)) }
        if let t = x.topic { lines.append("Topic: " + t) }
        return lines.joined(separator: "\n")
    }

    // MARK: a sync conflict copy

    public static func isConflict(_ name: String) -> Bool {
        name.range(of: #"^nexus-ideas \(conflict [^)]*\)\.yaml$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    /// Folds a conflict copy's ideas in by id: one only in the copy is added; one in both keeps the side edited last.
    public static func fold(_ items: [Idea], _ other: [Idea]) -> (items: [Idea], changed: Bool) {
        var out = items; var pos = Dictionary(out.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a }); var changed = false
        for y in other {
            guard let i = pos[y.id] else { out.append(y); pos[y.id] = out.count - 1; changed = true; continue }
            if out[i] != y && (y.edited ?? "") > (out[i].edited ?? "") { out[i] = y; changed = true }
        }
        return (out, changed)
    }
}
