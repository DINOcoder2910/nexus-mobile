import Foundation

// Workstream edits, as the laptop makes them (nexus `renderer/src/store/ops.js` planCreateWorkstream / planRenameWorkstream /
// planMoveWorkstream / planParkWorkstream, and the new app's `desktop/backend/src/workstreams.rs`): New workstream in a group, Rename
// (its `name:`, and [[Old name]] links in notes), Move to another group (the folder moves, path links into it follow), Park and
// Un-park (`status:`), Colour, Add a decision (a dated line under `## Decisions` in its notes.md) and a person's New session (a dated
// note in their folder, "2026-11-23 Essays.md"). Tasks are never touched: their workstream is the file they are in, and the id stays.
// Each edit is one Change with Undo, like a task edit.

public enum WorkstreamText {
    /// The ten colours a workstream can have (the laptop's themes.js, `COLOURS` in workstreams.rs).
    public static var colours: [String] { WorkstreamColor.names }

    // MARK: ids and folder names (the laptop's ids.js slugBase / slugId)

    static let slugMax = 60
    static let device = try! NSRegularExpression(pattern: "^(con|prn|aux|nul|com[0-9]|lpt[0-9])$")

    /// "Physics HL" -> "physics-hl": lowercase, accents dropped, & as "and", at most 60 characters cut at a dash where it can be;
    /// a Windows device name and `files` get "-1"; empty is "workstream".
    public static func slugBase(_ name: String) -> String {
        let folded = name.decomposedStringWithCompatibilityMapping.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }
        var s = String(String.UnicodeScalarView(folded)).lowercased().replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if s.count > slugMax {
            s = String(s.prefix(slugMax))
            if let cut = s.lastIndex(of: "-"), s.distance(from: s.startIndex, to: cut) >= slugMax / 2 { s = String(s[..<cut]) }
            while s.hasSuffix("-") { s.removeLast() }
        }
        if s.isEmpty { s = "workstream" }
        if s == "files" || device.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil { s += "-1" }
        return s
    }

    /// `slugBase`, made unique among `taken` (lowercase) with "-2", "-3" ...
    public static func slugId(_ name: String, taken: Set<String>) -> String {
        let base = slugBase(name)
        let has = { (x: String) in taken.contains(x) || taken.contains(x.lowercased()) }
        if !has(base) { return base }
        var n = 2
        while true {
            let sfx = "-\(n)"
            var s = String(base.prefix(slugMax - sfx.count))
            while s.hasSuffix("-") { s.removeLast() }
            s += sfx
            if !has(s) { return s }
            n += 1
        }
    }

    // MARK: writing a workstream.yaml (the laptop's schema.js workstreamText / yamlScalar)

    static let plain = try! NSRegularExpression(pattern: "^[A-Za-z][A-Za-z0-9 _./()'&-]*$")
    static let reservedWords: Set<String> = ["true", "false", "null", "yes", "no", "on", "off", "~"]

    /// A plain scalar when that reads back as the same string, else a JSON (double-quoted) one.
    public static func scalar(_ v: String) -> String {
        let r = NSRange(v.startIndex..., in: v)
        let ok = plain.firstMatch(in: v, range: r) != nil && v.last.map { !$0.isWhitespace } == true
            && !reservedWords.contains(v.lowercased()) && v.range(of: #":\s|\s#"#, options: .regularExpression) == nil
        return ok ? v : json(v)
    }

    /// JSON.stringify of a string.
    static func json(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    /// A new workstream.yaml: id, name, then kind, colour and aliases when given, and `status: active`.
    public static func manifest(id: String, name: String, kind: String? = nil, color: String? = nil, aliases: [String] = []) -> String {
        var l = ["id: \(scalar(id))", "name: \(scalar(name))"]
        if let kind, !kind.isEmpty { l.append("kind: \(scalar(kind))") }
        if let color, !color.isEmpty { l.append("color: \(scalar(color))") }
        if !aliases.isEmpty { l.append("aliases: [\(aliases.map(scalar).joined(separator: ", "))]") }
        l.append("status: active")
        return l.joined(separator: "\n") + "\n"
    }

    // MARK: links in notes (the laptop's ops.js rewriteLinks)

    static let link = try! NSRegularExpression(pattern: #"(!?\[\[)([^\]\n|#]*)([^\]\n]*)(\]\])"#)

    /// Rewrites the targets of [[links]] and ![[embeds]]: `fn` gets a target without its `|label` and `#heading` and returns the new
    /// one, or nil to leave it. Labels and headings stay; `[[task:…]]` links are never touched.
    public static func rewriteLinks(_ text: String, _ fn: (String) -> String?) -> String {
        let ns = text as NSString
        var out = text as NSString
        for m in link.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let t = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.lowercased().hasPrefix("task:") { continue }
            guard let n = fn(t), n != t else { continue }
            let rep = ns.substring(with: m.range(at: 1)) + n + ns.substring(with: m.range(at: 3)) + ns.substring(with: m.range(at: 4))
            out = out.replacingCharacters(in: m.range, with: rep) as NSString
        }
        return out as String
    }

    /// The targets of a note's links, as `rewriteLinks` sees them.
    public static func linkTargets(_ text: String) -> [String] {
        let ns = text as NSString
        return link.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 2)).trimmingCharacters(in: .whitespaces) }
    }

    static func normPath(_ p: String) -> String {
        var s = p.replacingOccurrences(of: "\\", with: "/")
        if s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }
    static func isInside(_ p: String, _ folder: String) -> Bool {
        let a = normPath(p), f = normPath(folder)
        return a == f || a.hasPrefix(f + "/")
    }
    static func moved(_ p: String, from: String, to: String) -> String {
        isInside(p, from) ? normPath(to) + String(normPath(p).dropFirst(normPath(from).count)) : normPath(p)
    }

    // MARK: decisions and dated notes (workstreams.rs, the laptop's notesmd.js)

    /// "- 2026-10-30 ED: Columbia, not Northwestern." (one line).
    public static func decisionLine(date: String, _ text: String) -> String {
        let one = text.components(separatedBy: CharacterSet(charactersIn: "\r\n")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return "- \(date) " + one.joined(separator: " ")
    }

    /// The decision at the end of the `## Decisions` section (before the next # or ## heading), or a new section at the end.
    public static func addDecision(_ text: String, date: String, _ what: String) -> String {
        let line = decisionLine(date: date, what)
        var t = text.replacingOccurrences(of: "\r\n", with: "\n")
        while let c = t.last, c.isWhitespace { t.removeLast() }
        var l = t.components(separatedBy: "\n")
        func isHead(_ s: String) -> Bool {
            var s = s
            while let c = s.last, c.isWhitespace { s.removeLast() }
            guard s.count > 2, s.hasPrefix("##"), !s.hasPrefix("###") else { return false }
            let rest = s.dropFirst(2)
            return rest.first?.isWhitespace == true && rest.trimmingCharacters(in: .whitespaces).lowercased() == "decisions"
        }
        guard let head = l.firstIndex(where: isHead) else {
            return (t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : t + "\n\n") + "## Decisions\n\n\(line)\n"
        }
        func heading(_ s: String) -> Bool { (s.hasPrefix("# ") || s.hasPrefix("## ")) && !s.hasPrefix("###") }
        var end = l.indices.first { $0 > head && heading(l[$0]) } ?? l.count
        while end > head + 1 && l[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
        var add = end == head + 1 ? ["", line] : [line]
        if end < l.count && !l[end].trimmingCharacters(in: .whitespaces).isEmpty { add.append("") }
        l.insert(contentsOf: add, at: end)
        return l.joined(separator: "\n") + "\n"
    }

    public struct Decision: Equatable {
        public var date: String?
        public var text: String
    }

    /// The decisions in a notes.md: each "- date text" line of its `## Decisions` section, newest first.
    public static func decisions(_ text: String) -> [Decision] {
        var out: [Decision] = []
        var on = false
        for raw in text.components(separatedBy: "\n") {
            var l = raw
            while let c = l.last, c.isWhitespace { l.removeLast() }
            if l.hasPrefix("# ") || (l.hasPrefix("## ") && !l.hasPrefix("###")) {
                on = l.dropFirst(2).trimmingCharacters(in: .whitespaces).lowercased() == "decisions"; continue
            }
            guard on else { continue }
            let rest: Substring
            if l.hasPrefix("- ") || l.hasPrefix("* ") { rest = l.dropFirst(2) } else { continue }
            if let sp = rest.firstIndex(of: " "), Days.isIso(String(rest[..<sp])) {
                out.append(Decision(date: String(rest[..<sp]), text: rest[rest.index(after: sp)...].trimmingCharacters(in: .whitespaces)))
            } else {
                out.append(Decision(date: nil, text: rest.trimmingCharacters(in: .whitespaces)))
            }
        }
        return out.reversed()
    }

    /// A dated note's file name: "2026-10-30 Essays.md" (the title loses what a file name or a [[link]] can't hold); nil when the date
    /// isn't YYYY-MM-DD.
    public static func datedNoteName(date: String, title: String) -> String? {
        guard Days.isIso(date) else { return nil }
        var t = String(title.unicodeScalars.filter { !"\\/:*?\"<>|#^[]".unicodeScalars.contains($0) && !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
        t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        while let c = t.last, c == "." || c == " " { t.removeLast() }
        t = String(t.prefix(100))
        return t.isEmpty ? "\(date).md" : "\(date) \(t).md"
    }

    /// A person's session notes ("2026-10-30 Essays.md" right in their folder), newest first.
    public struct Session: Equatable {
        public var path: String
        public var date: String
        public var title: String
    }

    static let dated = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2})(?:\s+(.*?))?\.md$"#, options: [.caseInsensitive])

    public static func sessions(_ names: [String], folder: String) -> [Session] {
        names.compactMap { n -> Session? in
            guard let m = dated.firstMatch(in: n, range: NSRange(n.startIndex..., in: n)), let d = Range(m.range(at: 1), in: n) else { return nil }
            let title = Range(m.range(at: 2), in: n).map { String(n[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
            return Session(path: folder + "/" + n, date: String(n[d]), title: title.isEmpty ? "Session" : title)
        }
        .sorted { $0.date != $1.date ? $0.date > $1.date : $0.path < $1.path }
    }

    /// The first lines of a new session note (workstreams.rs).
    public static let sessionTemplate = "## Before\n\n## Discussed\n\n## Out of it\n"
}

/// The workstream edits, each written at once and returned as one Change for the undo bar.
public struct WorkstreamEditor {
    public enum Failure: Error, CustomStringConvertible, Equatable {
        case cannot(String)
        public var description: String { if case .cannot(let s) = self { return s }; return "" }
    }

    public var root: URL
    public var read: (URL) throws -> String
    public var write: (URL, String) throws -> Void

    public init(root: URL,
                read: @escaping (URL) throws -> String = { String(decoding: try Data(contentsOf: $0), as: UTF8.self) },
                write: @escaping (URL, String) throws -> Void = { try Data($1.utf8).write(to: $0, options: .atomic) }) {
        self.root = root; self.read = read; self.write = write
    }

    private var fm: FileManager { .default }
    private func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }
    private func exists(_ rel: String) -> Bool { fm.fileExists(atPath: url(rel).path) }

    private func writable(_ s: Snapshot) throws {
        if let why = s.readOnlyReason { throw Failure.cannot(why) }
    }

    private func manifestPath(_ w: Workstream) -> String { w.folder + "/workstream.yaml" }

    /// One key of a workstream.yaml set (nil removes it), line by line (DetailEdit).
    private func detail(_ w: Workstream, _ key: String, _ value: JSONValue?, message: String, in s: Snapshot) throws -> Change {
        try writable(s)
        let rel = manifestPath(w)
        let before = try read(url(rel))
        let after: String
        do { after = try DetailEdit.set(before, key: key, value) } catch { throw Failure.cannot("\(error)") }
        if after != before { try write(url(rel), after) }
        return Change(file: rel, before: before, after: after, message: message)
    }

    /// The names (lowercase) already used in a group folder: its folders and files.
    private func namesIn(_ group: String) -> Set<String> {
        Set(((try? fm.contentsOfDirectory(atPath: url(group).path)) ?? []).map { $0.lowercased() })
    }

    /// New workstream: `<group>/<slug>/workstream.yaml` with `status: active` (tasks.yaml and notes.md come when first needed).
    /// The id and folder are the slug of the name, unique among the workstream ids and the group's folders. Returns its id.
    public func create(group: String, name: String, in s: Snapshot) throws -> (Change, String) {
        try writable(s)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.cannot("A workstream needs a name.") }
        guard s.groups.contains(where: { $0.id == group }) else { throw Failure.cannot("Choose a group for it.") }
        let taken = Set(s.workstreams.keys.map { $0.lowercased() }).union(namesIn(group))
        let id = WorkstreamText.slugId(name, taken: taken)
        let folder = group + "/" + id
        if exists(folder) { throw Failure.cannot("\(folder) already exists.") }
        let rel = folder + "/workstream.yaml"
        let text = WorkstreamText.manifest(id: id, name: name)
        try fm.createDirectory(at: url(folder), withIntermediateDirectories: true)
        try write(url(rel), text)
        var c = Change(file: rel, before: "", after: text, message: "Made \(name)")
        c.created = true
        return (c, id)
    }

    /// Rename: `name:` changes; [[Old name]] links in the folder's notes become [[New name]] (the same Undo puts them back). The
    /// folder and the id stay as they are.
    public func rename(_ w: Workstream, to newName: String, in s: Snapshot) throws -> Change {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.cannot("A workstream needs a name.") }
        let old = w.name.lowercased()
        // the notes to change are read before anything is written
        var notes: [(String, String, String)] = []
        for p in notePaths() {
            guard let text = try? read(url(p)) else { continue }
            guard WorkstreamText.linkTargets(text).contains(where: { target($0).lowercased() == old }) else { continue }
            let out = WorkstreamText.rewriteLinks(text) { $0.lowercased() == old ? name : nil }
            if out != text { notes.append((p, text, out)) }
        }
        var c = try detail(w, "name", .string(name), message: "Renamed to \(name)", in: s)
        for (p, before, after) in notes {
            try write(url(p), after)
            c.also.append(Change(file: p, before: before, after: after, message: c.message))
        }
        return c
    }

    /// Move to another group: the folder moves (named as before, unless the group has that name already), and links that use a path
    /// into the old folder follow it. The id, its tasks and its notes' history stay.
    public func move(_ w: Workstream, to group: String, in s: Snapshot) throws -> Change {
        try writable(s)
        guard let g = s.groups.first(where: { $0.id == group }) else { throw Failure.cannot("Choose a group to move it to.") }
        let from = w.folder
        if w.group == group { return Change(file: manifestPath(w), before: "", after: "", message: "\(w.name) is in \(g.label) already") }
        let base = from.split(separator: "/").last.map(String.init) ?? w.id
        let to = group + "/" + WorkstreamText.slugId(base, taken: namesIn(group))
        if exists(to) { throw Failure.cannot("\(to) already exists.") }
        var notes: [(String, String, String)] = []
        for p in notePaths() {
            guard let text = try? read(url(p)) else { continue }
            guard WorkstreamText.linkTargets(text).contains(where: { WorkstreamText.isInside(WorkstreamText.normPath(target($0)), from) }) else { continue }
            let out = WorkstreamText.rewriteLinks(text) { t in WorkstreamText.isInside(WorkstreamText.normPath(t), from) ? WorkstreamText.moved(t, from: from, to: to) : nil }
            if out != text { notes.append((WorkstreamText.moved(p, from: from, to: to), text, out)) }
        }
        try fm.moveItem(at: url(from), to: url(to))
        var c = Change(file: to + "/workstream.yaml", before: "", after: "", message: "Moved \(w.name) to \(g.label)")
        c.moved = Change.Moved(from: from, to: to)
        for (p, before, after) in notes {
            try write(url(p), after)
            c.also.append(Change(file: p, before: before, after: after, message: c.message))
        }
        return c
    }

    /// Park (or un-park): `status: parked` / `status: active`. Its tasks stay where they are and leave Today, the Planner and the counts.
    public func park(_ w: Workstream, _ parked: Bool, in s: Snapshot) throws -> Change {
        try detail(w, "status", .string(parked ? "parked" : "active"),
                   message: parked ? "Parked \(w.name): its tasks leave Today, the Planner and the counts" : "\(w.name) is back", in: s)
    }

    /// Its own colour (one of the ten), or nil for the group's.
    public func color(_ w: Workstream, _ color: String?, in s: Snapshot) throws -> Change {
        if let color, !WorkstreamText.colours.contains(color) { throw Failure.cannot("\(color) is not one of the colours") }
        return try detail(w, "color", color.map(JSONValue.string), message: "\(w.name) in \(color ?? "its group's colour")", in: s)
    }

    /// Add a decision: one dated line under `## Decisions` in its notes.md (made when missing).
    public func decision(_ w: Workstream, _ text: String, date: String, in s: Snapshot) throws -> Change {
        try writable(s)
        let what = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !what.isEmpty else { throw Failure.cannot("Write what was decided.") }
        let rel = w.folder + "/notes.md"
        let had = exists(rel)
        let before = had ? try read(url(rel)) : ""
        let after = WorkstreamText.addDecision(before, date: date, what)
        try write(url(rel), after)
        var c = Change(file: rel, before: before, after: after, message: "Decision added to \(w.name) notes")
        c.created = !had
        return c
    }

    /// New session with a person: a dated note in their folder, and, when asked, "<title> session" as a task due that day.
    /// Returns the note's path.
    public func session(_ w: Workstream, title: String, date: String, task: Bool, in s: Snapshot, today: String) throws -> (Change, String) {
        try writable(s)
        guard w.kind == "person" else { throw Failure.cannot("\(w.name) is not a person.") }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw Failure.cannot("A session needs a title, for example Essays.") }
        guard let name = WorkstreamText.datedNoteName(date: date, title: t) else { throw Failure.cannot("A session needs a date.") }
        let rel = w.folder + "/" + name
        if exists(rel) { throw Failure.cannot("That session note already exists.") }
        try write(url(rel), WorkstreamText.sessionTemplate)
        var c = Change(file: rel, before: "", after: WorkstreamText.sessionTemplate, message: "Session note made")
        c.created = true
        if task {
            let tasks = w.tasksFile
            var made: Change?
            if !exists(tasks) { try write(url(tasks), "tasks: []\n"); var m = Change(file: tasks, before: "", after: "tasks: []\n", message: ""); m.created = true; made = m }
            let ed = TaskEditor(root: root, read: read, write: write)
            var (tc, _) = try ed.add(title: "\(t) session", to: tasks, due: date, in: s, today: today)
            if let made { tc.before = made.before; tc.created = true }
            c.also.append(tc)
        }
        return (c, rel)
    }

    /// A link's target without its `|label` and `#heading`.
    private func target(_ t: String) -> String {
        String(t.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// The folder's notes (.md files), as the laptop's index has them: not NEXUS.md or CLAUDE.md at the top (Claude's rules), nothing
    /// in `.git`, `.nexus` and the like, and not inside a board (a board's text is its `.jsonl`; its `.md` is a copy).
    func notePaths() -> [String] {
        let skip: Set<String> = [".git", ".import", ".nexus", ".obsidian", "node_modules", ".Trash"]
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        var out: [String] = []
        for case let u as URL in e {
            let name = u.lastPathComponent
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if skip.contains(name) || name.hasSuffix(".board") { e.skipDescendants() }
                continue
            }
            guard name.lowercased().hasSuffix(".md") else { continue }
            let p = u.standardizedFileURL.resolvingSymlinksInPath().path
            guard p.hasPrefix(base + "/") else { continue }
            let rel = String(p.dropFirst(base.count + 1))
            if rel == "NEXUS.md" || rel == "CLAUDE.md" { continue }
            out.append(rel)
        }
        return out.sorted()
    }
}
