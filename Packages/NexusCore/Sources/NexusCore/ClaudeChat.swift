import Foundation
import Yams

/// The Claude conversation on the iPhone and iPad, the pure half (the laptop's Claude panel: claude.js, claude-service.js, claudecommands.js,
/// compose-day.js). On the laptop Claude Code runs in the data folder with Read, Glob, Grep, Edit and Write, and every edit waits for the
/// user's Accept. Here Claude is reached through the Messages API or the hub, neither of which can run tools on this device, so Claude asks
/// for them in its reply with small tags and the app does them:
///
///     <read path="classes/chem/tasks.yaml"/>        a file's text            (Read)
///     <list path="classes"/>                        a folder's entries       (Glob)
///     <search>polymer</search>                      lines that mention it    (Grep)
///     <edit path="…"><old>…</old><new>…</new></edit>  a change to a file    (Edit: the old text must be there exactly once)
///     <write path="…">…</write>                     a new file              (Write)
///
/// Look-ups are answered at once in the next message (`<result …>`), up to a few rounds a turn. Edits and new files become proposals the
/// user accepts or rejects one by one, as on the laptop; the next message tells Claude which were accepted. Paths are checked as the
/// laptop's claude-guard.js does: inside the folder, never `.git/`, `.nexus/` or a folder named `the-thing`.
public enum ClaudeChat {
    // MARK: the tags

    public enum Action: Equatable, Sendable {
        case read(String)
        case list(String)
        case search(String)
        case edit(path: String, old: String, new: String)
        case write(path: String, content: String)

        /// Answered at once (read, list, search), not a proposal.
        public var isLookup: Bool {
            switch self { case .read, .list, .search: return true; default: return false }
        }
        public var path: String? {
            switch self {
            case .read(let p), .list(let p): return p
            case .edit(let p, _, _), .write(let p, _): return p
            case .search: return nil
            }
        }
        /// "Read classes/chem/tasks.yaml", what the conversation shows for a look-up.
        public var label: String {
            switch self {
            case .read(let p): return "Read " + p
            case .list(let p): return "Looked in " + (p.isEmpty || p == "." ? "the data folder" : p)
            case .search(let q): return "Searched for “\(q)”"
            case .edit(let p, _, _): return "Change " + p
            case .write(let p, _): return "New file " + p
            }
        }
    }

    public enum Piece: Equatable, Sendable {
        case text(String)
        case action(Action)
    }

    static let openers = ["<read", "<list", "<search", "<edit", "<write"]

    /// A reply cut into its words and its tags, in order. With `final` false (still streaming) an unfinished tag at the end is left out,
    /// so it never flashes on screen; when final, an unfinished tag is kept as words.
    public static func parse(_ reply: String, final: Bool = true) -> [Piece] {
        var out: [Piece] = []
        var text = ""
        var i = reply.startIndex
        func flush() {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(.text(t)) }
            text = ""
        }
        while i < reply.endIndex {
            guard reply[i] == "<" else { text.append(reply[i]); i = reply.index(after: i); continue }
            let rest = reply[i...]
            guard let opener = openers.first(where: { rest.hasPrefix($0) && isTagEnd(rest.dropFirst($0.count).first) }) else {
                // a tag still arriving: "<ed" at the very end
                if !final, rest.count < 8, openers.contains(where: { $0.hasPrefix(String(rest)) }) { break }
                text.append("<"); i = reply.index(after: i); continue
            }
            if let (action, end) = tag(opener, in: reply, at: i) {
                flush()
                out.append(.action(action))
                i = end
            } else if !final {
                break // its end has not arrived yet
            } else {
                text.append("<"); i = reply.index(after: i)
            }
        }
        flush()
        return out
    }

    /// The words of a reply without its tags (what the conversation shows while it streams).
    public static func words(_ reply: String, final: Bool = false) -> String {
        parse(reply, final: final).compactMap { if case .text(let t) = $0 { return t }; return nil }.joined(separator: "\n\n")
    }

    static func isTagEnd(_ c: Character?) -> Bool { c == nil || c == " " || c == ">" || c == "/" || c == "\n" }

    static func attr(_ name: String, in head: Substring) -> String? {
        for q in ["\"", "'"] {
            if let r = head.range(of: name + "=" + q) {
                let after = head[r.upperBound...]
                if let e = after.firstIndex(of: Character(q)) { return String(after[..<e]) }
            }
        }
        return nil
    }

    /// One whole tag at `i`: the action and where the reply goes on after it, or nil when it is not complete.
    static func tag(_ opener: String, in s: String, at i: String.Index) -> (Action, String.Index)? {
        guard let headEnd = s[i...].firstIndex(of: ">") else { return nil }
        let head = s[s.index(i, offsetBy: opener.count)..<headEnd]
        let selfClosing = head.hasSuffix("/")
        let afterHead = s.index(after: headEnd)
        let name = String(opener.dropFirst())
        let path = cleanPathText(attr("path", in: head) ?? "")
        func body() -> (String, String.Index)? {
            guard let close = s.range(of: "</\(name)>", range: afterHead..<s.endIndex) else { return nil }
            return (String(s[afterHead..<close.lowerBound]), close.upperBound)
        }
        switch name {
        case "read", "list":
            if selfClosing { return (name == "read" ? .read(path) : .list(path), afterHead) }
            // <read path="x"></read> or <read>x</read>
            guard let (b, end) = body() else { return nil }
            let p = path.isEmpty ? cleanPathText(b) : path
            return (name == "read" ? .read(p) : .list(p), end)
        case "search":
            if selfClosing { return (.search(attr("query", in: head) ?? ""), afterHead) }
            guard let (b, end) = body() else { return nil }
            return (.search(b.trimmingCharacters(in: .whitespacesAndNewlines)), end)
        case "edit":
            guard let (b, end) = body() else { return nil }
            guard let old = inner("old", b), let new = inner("new", b) else { return nil }
            return (.edit(path: path, old: old, new: new), end)
        case "write":
            guard let (b, end) = body() else { return nil }
            return (.write(path: path, content: trimOneNewline(b)), end)
        default:
            return nil
        }
    }

    static func inner(_ name: String, _ s: String) -> String? {
        guard let a = s.range(of: "<\(name)>"), let b = s.range(of: "</\(name)>", range: a.upperBound..<s.endIndex) else { return nil }
        return trimOneNewline(String(s[a.upperBound..<b.lowerBound]))
    }

    /// The text between tags without the one newline after the opening tag and the one before the closing tag.
    static func trimOneNewline(_ s: String) -> String {
        var t = Substring(s)
        if t.hasPrefix("\r\n") { t = t.dropFirst(2) } else if t.hasPrefix("\n") { t = t.dropFirst() }
        if t.hasSuffix("\r\n") { t = t.dropLast(2) } else if t.hasSuffix("\n") { t = t.dropLast() }
        return String(t)
    }

    static func cleanPathText(_ p: String) -> String {
        var s = p.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\", with: "/")
        while s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasPrefix("/") { s.removeFirst() }
        while s.hasSuffix("/") { s.removeLast() }
        return s == "." ? "" : s
    }

    // MARK: the boundary (claude-guard.js)

    /// Why a path is refused, or nil when Claude may use it. `write`: a change, not a look-up.
    public static func refused(_ path: String, write: Bool) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        if parts.contains("..") { return "That path goes outside the data folder." }
        if parts.contains(where: { $0.lowercased() == "the-thing" }) { return "That folder is off limits." }
        if let f = parts.first, f == ".git" || f == ".nexus" { return write ? "Nexus keeps \(f)/ for itself; it is never changed." : "Nexus keeps \(f)/ for itself." }
        if write && path.isEmpty { return "A change needs a file's path." }
        return nil
    }

    // MARK: the data folder, as Claude sees it

    /// Reading the data folder for Claude's look-ups, and turning its proposals into whole-file before/after. `read` reads a file's text
    /// (FolderAccess.read in the app); nothing here writes.
    public struct Workspace {
        public var root: URL
        public var read: (URL) throws -> String
        public var fm: FileManager = .default
        /// A file longer than this is cut for Claude (it is told so).
        public var maxRead = 60_000

        public init(root: URL, read: @escaping (URL) throws -> String = { try String(contentsOf: $0, encoding: .utf8) }) {
            self.root = root; self.read = read
        }

        /// Files Claude is told it can't read here (pictures, PDFs, documents, audio, archives).
        static let binary: Set<String> = ["pdf", "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "docx", "doc", "xlsx", "xls", "pptx", "ppt", "zip",
                                          "one", "onepkg", "m4a", "mp3", "wav", "mp4", "mov", "ipa", "bin", "wasm"]

        func url(_ rel: String) -> URL { rel.isEmpty ? root : root.appendingPathComponent(rel) }

        func isDir(_ u: URL) -> Bool {
            var d: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &d) && d.boolValue
        }

        /// A look-up's answer, as the next message gives it to Claude.
        public func answer(_ a: Action) -> String {
            switch a {
            case .read(let p): return "<result of=\"read \(p)\">\n\(readText(p))\n</result>"
            case .list(let p): return "<result of=\"list \(p.isEmpty ? "." : p)\">\n\(listText(p))\n</result>"
            case .search(let q): return "<result of=\"search \(q)\">\n\(searchText(q))\n</result>"
            default: return ""
            }
        }

        public func readText(_ p: String) -> String {
            if let why = ClaudeChat.refused(p, write: false) { return "Refused: " + why }
            let u = url(p)
            if p.isEmpty || isDir(u) { return "That is a folder; list it instead.\n" + listText(p) }
            guard fm.fileExists(atPath: u.path) else { return "There is no file at \(p)." }
            if Self.binary.contains(u.pathExtension.lowercased()) { return "\(p) is not a text file Nexus can show you (a \(u.pathExtension.uppercased()))." }
            guard let t = try? read(u) else { return "\(p) is not a text file Nexus can show you." }
            if t.count > maxRead { return String(t.prefix(maxRead)) + "\n… (cut here: the file is \(t.count) characters; search it for the part you need)" }
            return t
        }

        public func listText(_ p: String) -> String {
            if let why = ClaudeChat.refused(p, write: false) { return "Refused: " + why }
            let u = url(p)
            guard isDir(u) else { return fm.fileExists(atPath: u.path) ? "\(p) is a file; read it instead." : "There is no folder at \(p.isEmpty ? "the top" : p)." }
            let names = ((try? fm.contentsOfDirectory(atPath: u.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            if names.isEmpty { return "(empty)" }
            let shown = names.prefix(300).map { isDir(u.appendingPathComponent($0)) ? $0 + "/" : $0 }
            return shown.joined(separator: "\n") + (names.count > 300 ? "\n… and \(names.count - 300) more" : "")
        }

        /// Lines that mention the words (any case), in the folder's YAML, markdown and text files; the notebooks (thousands of board files)
        /// are left out, as are files over 300 KB. At most 40 lines.
        public func searchText(_ q: String) -> String {
            let needle = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !needle.isEmpty else { return "Nothing to search for." }
            var hits: [String] = []
            var seen = 0
            let kinds: Set<String> = ["yaml", "yml", "md", "txt"]
            guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return "Nothing found." }
            let rootReal = root.resolvingSymlinksInPath().path
            for case let u as URL in walk {
                let full = u.resolvingSymlinksInPath().path
                let rel = (full.hasPrefix(rootReal) ? String(full.dropFirst(rootReal.count)) : u.lastPathComponent)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let vals = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if vals?.isDirectory == true {
                    if rel == "notebooks" || rel.hasSuffix(".board") || ClaudeChat.refused(rel, write: false) != nil { walk.skipDescendants() }
                    continue
                }
                guard kinds.contains(u.pathExtension.lowercased()), (vals?.fileSize ?? 0) < 300_000 else { continue }
                seen += 1
                if seen > 4000 { break }
                guard let text = try? read(u), text.lowercased().contains(needle) else { continue }
                var n = 0
                for line in text.components(separatedBy: "\n") {
                    n += 1
                    if line.lowercased().contains(needle) {
                        let l = line.trimmingCharacters(in: .whitespaces)
                        hits.append("\(rel):\(n): \(l.count > 200 ? String(l.prefix(200)) + "…" : l)")
                        if hits.count >= 40 { break }
                    }
                }
                if hits.count >= 40 { break }
            }
            if hits.isEmpty { return "Nothing found (notebooks are not searched; list notebooks/ to look there)." }
            return hits.joined(separator: "\n") + (hits.count >= 40 ? "\n… (more; search for something narrower)" : "")
        }

        /// A proposal from an edit or a new file, worked out against the file as it is now.
        public func propose(_ a: Action, id: String, takenIds: Set<String> = []) -> Proposal {
            switch a {
            case .edit(let p, let old, let new):
                var pr = Proposal(id: id, action: a, path: p, isNew: false, before: "", after: "")
                if let why = ClaudeChat.refused(p, write: true) { pr.problem = why; return pr }
                let u = url(p)
                guard fm.fileExists(atPath: u.path), !isDir(u) else {
                    if old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pr.isNew = true; pr.after = new; pr.problem = check(p, new, takenIds: takenIds); return pr }
                    pr.problem = "There is no file at \(p)."
                    return pr
                }
                guard let before = try? read(u) else { pr.problem = "\(p) is not a text file."; return pr }
                pr.before = before
                switch ClaudeChat.replace(old, with: new, in: before) {
                case .success(let after): pr.after = after; pr.problem = check(p, after, takenIds: takenIds)
                case .failure(let e): pr.problem = e.message
                }
                return pr
            case .write(let p, let content):
                var pr = Proposal(id: id, action: a, path: p, isNew: true, before: "", after: content)
                if let why = ClaudeChat.refused(p, write: true) { pr.problem = why; return pr }
                let u = url(p)
                if fm.fileExists(atPath: u.path) {
                    pr.problem = isDir(u) ? "\(p) is a folder." : "\(p) already exists; change it with an edit instead."
                    return pr
                }
                pr.problem = check(p, content, takenIds: takenIds)
                return pr
            default:
                return Proposal(id: id, action: a, path: a.path ?? "", isNew: false, before: "", after: "", problem: "Not a change.")
            }
        }

        /// Why a file's new text can't be saved, or nil: YAML must still parse; a task file must still be a task list whose ids are unique
        /// in it and not used by another file's tasks.
        public func check(_ path: String, _ text: String, takenIds: Set<String>) -> String? {
            ClaudeChat.check(path, text, takenIds: takenIds)
        }
    }

    public struct Proposal: Equatable, Identifiable, Sendable {
        public var id: String
        public var action: Action
        public var path: String
        public var isNew: Bool
        public var before: String
        public var after: String
        /// Why it can't be applied (shown on the card, and told to Claude).
        public var problem: String?
        public init(id: String, action: Action, path: String, isNew: Bool, before: String, after: String, problem: String? = nil) {
            self.id = id; self.action = action; self.path = path; self.isNew = isNew; self.before = before; self.after = after; self.problem = problem
        }
    }

    public struct EditError: Error, Equatable { public let message: String }

    /// The laptop's Edit: `old` must be in `text` exactly once (with the file's own line ends).
    public static func replace(_ old: String, with new: String, in text: String) -> Result<String, EditError> {
        let crlf = text.contains("\r\n")
        let o = crlf ? old.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") : old
        let n = crlf ? new.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n") : new
        guard !o.isEmpty else { return .failure(EditError(message: "The edit has no text to replace.")) }
        let count = text.components(separatedBy: o).count - 1
        if count == 0 { return .failure(EditError(message: "The text to replace is not in the file as it is now (copy it exactly, with its indentation, from what you read).")) }
        if count > 1 { return .failure(EditError(message: "The text to replace is in the file \(count) times; include more of the lines around it so it is there once.")) }
        return .success(text.replacingOccurrences(of: o, with: n))
    }

    static func isTaskFile(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        return name == "tasks.yaml" || name == "inbox.yaml"
    }

    public static func check(_ path: String, _ text: String, takenIds: Set<String>) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "yaml" || ext == "yml" else { return nil }
        do { _ = try Yams.compose(yaml: text) } catch { return "\(path) would no longer read as YAML: \(TaskFile.yamlMessage(error))" }
        guard isTaskFile(path) else { return nil }
        let parsed: TaskFile.Parsed
        do { parsed = try TaskFile.parse(text, file: path, workstream: nil) } catch { return "\(path) would no longer be a task list: \(error)" }
        var seen = Set<String>()
        for t in parsed.tasks where t.hasId {
            if seen.contains(t.id) { return "Two tasks in \(path) would share the id \(t.id)." }
            if takenIds.contains(t.id) { return "The id \(t.id) is already used by a task in another file." }
            seen.insert(t.id)
        }
        return nil
    }

    /// Every task id outside `file` (a proposal's new ids must not be among them).
    public static func idsOutside(_ file: String, in s: Snapshot) -> Set<String> {
        Set(s.tasks.values.filter { $0.hasId && $0.file != file }.map(\.id))
    }

    // MARK: a diff for the card

    public enum Line: Equatable, Sendable {
        case same(String), removed(String), added(String), gap(Int)
    }

    /// The changed lines with up to `context` lines around them; long runs of unchanged lines become a gap.
    public static func diff(_ before: String, _ after: String, context: Int = 2) -> [Line] {
        let a = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let b = after.components(separatedBy: "\n")
        var pre = 0
        while pre < a.count && pre < b.count && a[pre] == b[pre] { pre += 1 }
        var suf = 0
        while suf < a.count - pre && suf < b.count - pre && a[a.count - 1 - suf] == b[b.count - 1 - suf] { suf += 1 }
        var out: [Line] = []
        let from = max(0, pre - context)
        if from > 0 { out.append(.gap(from)) }
        for i in from..<pre { out.append(.same(a[i])) }
        for i in pre..<(a.count - suf) { out.append(.removed(a[i])) }
        for i in pre..<(b.count - suf) { out.append(.added(b[i])) }
        let tailEnd = min(a.count, a.count - suf + context)
        for i in (a.count - suf)..<tailEnd { out.append(.same(a[i])) }
        if a.count - tailEnd > 0 { out.append(.gap(a.count - tailEnd)) }
        return out
    }

    // MARK: what Claude is told

    public static let boundary = "You work only inside the open data folder. Every change you make to a file is shown to the user, who accepts or rejects it, so make small, clear edits one at a time. Never touch anything outside this folder. When you add a new task, give it an `added: YYYY-MM-DD` key with the date of today (the date is in the context you are given)."

    /// The system prompt: who Claude is, the boundary, how to read and change files here, and the folder's rules (NEXUS.md, or the
    /// laptop's default when the folder has none).
    public static func system(rules: String?, device: String) -> String {
        let r = (rules?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ? ClaudeRules.defaultText : rules!
        return """
        You are Claude inside Nexus, the user's personal workspace (their files, tasks and plans). The user is on their \(device).

        \(boundary)

        How you work here. You cannot run tools on this \(device). Instead, write these tags in your reply and Nexus does them:
        - <read path="inbox.yaml"/> gives you a file's text. Paths are relative to the data folder.
        - <list path="classes"/> lists a folder (path "" for the top of the data folder).
        - <search>words</search> finds the lines that mention them in the folder's YAML and markdown files.
        After look-up tags, stop writing and wait: the next message brings the results as <result of="…">…</result>. Read only what you need; the context may already say enough.
        - To change a file, propose an edit:
        <edit path="classes/chem/tasks.yaml">
        <old>
        exact lines from the file as it is now
        </old>
        <new>
        the lines that replace them
        </new>
        </edit>
        The old text must be in the file exactly once: copy whole lines exactly as you read them, with their indentation. One edit per task or note, so each is easy to accept. Never rewrite a whole file.
        - To make a new file: <write path="people/kim/2026-11-16 Catch-up.md">its text</write>. Never use write for a file that exists.
        Each edit and new file is shown to the user as a card to accept or reject, so say what you propose, not that it is done; the next message tells you which they accepted. If an edit can't be used (its old text is not in the file), you are told why: read the file again and propose it once more.
        - A new task needs an id: use one of the free ids in the context, one per task.
        Write plain, short replies (light markdown is fine). Don't repeat the tags' content in your words.

        The rules for this data folder follow (they come from NEXUS.md).

        \(r)
        """
    }

    /// One workstream as the context lists it.
    public struct WorkstreamLine: Sendable {
        public var id: String, name: String, folder: String, open: Int, parked: Bool
        public init(id: String, name: String, folder: String, open: Int, parked: Bool) {
            self.id = id; self.name = name; self.folder = folder; self.open = open; self.parked = parked
        }
    }

    /// The text around the user's message (the laptop's contextBlock): what they are looking at, today and now, the workstreams (on the
    /// first message of a conversation), free ids for new tasks, and anything the screen adds (Applications' schools).
    public static func context(looking: String?, today: String, now: String, workstreams: [WorkstreamLine]?, inboxOpen: Int?, freeIds: [String], extra: String?) -> String {
        var bits: [String] = []
        if let looking, !looking.isEmpty { bits.append("Looking at: " + looking) }
        bits.append("Today is \(today) (\(weekdayName(today))), now \(now).")
        if let ws = workstreams, !ws.isEmpty {
            bits.append("Workstreams (id: name, folder, open tasks):\n" + ws.map { "- \($0.id): \($0.name), \($0.folder)/, \($0.open) open\($0.parked ? ", parked" : "")" }.joined(separator: "\n"))
        }
        if let n = inboxOpen { bits.append("Inbox: inbox.yaml, \(n) open.") }
        if !freeIds.isEmpty { bits.append("Free ids for new tasks: " + freeIds.joined(separator: ", ") + ".") }
        if let e = extra?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { bits.append(e.count > 16_000 ? String(e.prefix(16_000)) + "\n(cut here)" : e) }
        return "<context>\n" + bits.joined(separator: "\n") + "\n</context>\n\n"
    }

    static func weekdayName(_ iso: String) -> String {
        ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][max(0, min(6, Days.weekday(iso)))]
    }

    /// What the user decided on the last reply's proposals, said at the top of their next message.
    public static func decisions(accepted: [String], rejected: [String], failed: [String]) -> String {
        var bits: [String] = []
        if !accepted.isEmpty { bits.append("Accepted and saved: " + accepted.joined(separator: "; ") + ".") }
        if !rejected.isEmpty { bits.append("Rejected (don't propose them again; ask what I'd like instead): " + rejected.joined(separator: "; ") + ".") }
        if !failed.isEmpty { bits.append("Could not be saved: " + failed.joined(separator: "; ") + ".") }
        return bits.isEmpty ? "" : "<changes>\n" + bits.joined(separator: "\n") + "\n</changes>\n\n"
    }

    // MARK: the "/" commands (claudecommands.js)

    public struct Command: Identifiable, Sendable {
        public var id: String
        public var title: String
        public var detail: String
        public var icon: String
    }

    public static let commands: [Command] = [
        Command(id: "/plan", title: "Plan my days", detail: "Suggest a day for each piece of work", icon: "calendar.badge.clock"),
        Command(id: "/file-inbox", title: "File my Inbox", detail: "Place what is left in the Inbox", icon: "tray.and.arrow.down"),
        Command(id: "/weekly-review", title: "Weekly review", detail: "What moved, slipped and waits", icon: "arrow.triangle.2.circlepath"),
        Command(id: "/new-meeting", title: "New meeting note", detail: "A session note with their open items", icon: "person.2"),
        Command(id: "/tidy", title: "Tidy loose ends", detail: "Stale, finished and duplicate tasks", icon: "sparkles"),
    ]

    static func withArgs(_ base: String, _ args: String, _ label: String = "The user adds") -> String { args.isEmpty ? base : "\(base)\n\n\(label): \(args)" }

    /// A command's prompt (the laptop's TEMPLATES), or nil when it is not one.
    public static func expand(_ name: String, args: String = "", today: String, dayHours: Double = 6, dayStart: Int = 4) -> String? {
        let a = args.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "/plan":
            let hours = dayHours == dayHours.rounded() ? String(Int(dayHours)) : String(dayHours)
            return withArgs("Plan my days. Today is \(today). Read the open tasks in the workstreams (due, key, plan, est) and what has slipped. Suggest which day each piece of work goes on, "
                + "keeping a day to about \(hours) hours of planned work and starting around \(String(format: "%02d", dayStart)):00 or later. Say the picture in two sentences first, then propose the changes as edits to each task's plan: field, one container file at a time. Do not change deadlines.", a)
        case "/file-inbox":
            return withArgs("File my Inbox. Read inbox.yaml: what is left there is what capture could not place. For each open item say which workstream it belongs in (a class, a project, an application, a person) or someday, and propose the move: add it to that container and remove it from the inbox. If you cannot tell, leave it and say why. Keep titles exactly as written.", a)
        case "/weekly-review":
            return withArgs("Walk me through my week (today is \(today)). What moved, what slipped, what is waiting and has gone quiet, what the next week needs. Keep it short, then ask what I want to change before proposing any edits.", a)
        case "/new-meeting":
            return a.isEmpty
                ? "Start a meeting note. Ask me who it is with (list the people under meetings/), then propose the session note."
                : "Start a meeting note for \(a). Find their person.yaml under meetings/, list their open tasks and waiting-ons, then propose a new session note next to it named \(today)-<title>.md with the frontmatter from the rules (session: true, date, title, person) and those open items as an agenda. Ask me for the title if it is not obvious."
        case "/tidy":
            return withArgs("Tidy loose ends. Look for finished tasks that clutter a container, tasks whose dates passed long ago with no plan (likely stale), and duplicates. List what you found and propose what to clear or re-date. Do not delete anything without showing it first; finished tasks stay in their file unless I say otherwise.", a)
        default:
            return nil
        }
    }

    /// "/plan next week" -> ("/plan", "next week"); nil when the text is not a command.
    public static func command(in text: String) -> (name: String, args: String)? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("/") else { return nil }
        let name = String(t.prefix { !$0.isWhitespace }).lowercased()
        guard commands.contains(where: { $0.id == name }) else { return nil }
        return (name, String(t.dropFirst(name.count)).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Plan with Claude (compose-day.js)

    public struct SlippedTask: Sendable {
        public var id: String, title: String, path: String, minutes: Int
        public init(id: String, title: String, path: String, minutes: Int) { self.id = id; self.title = title; self.path = path; self.minutes = minutes }
    }

    /// What Plan with Claude places: tasks whose deadline passed with no plan ahead, and tasks planned only on earlier days, latest first.
    public static func slippedForPlan(_ p: Planning) -> [SlippedTask] {
        var seen = Set<String>()
        var out: [SlippedTask] = []
        let late = DayBrief.slipped(p).sorted { $0.out > $1.out }.map { $0.task }
        for t in late + p.slipped where t.hasId && !seen.contains(t.id) {
            seen.insert(t.id)
            out.append(SlippedTask(id: t.id, title: t.text, path: t.file, minutes: max(15, Int(((p.estimate(t) ?? 0.5) * 60).rounded()))))
        }
        return out
    }

    /// Today's free time in minutes from midnight: between `from` and `to` (from `now` on, rounded up to 5 minutes), outside the busy
    /// spans, each at least `min` long (schedule.js freeGaps).
    public static func freeGaps(busy: [(Int, Int)], from: Int = 8 * 60, to: Int = 21 * 60, now: Int? = nil, min: Int = 15) -> [(start: Int, end: Int)] {
        var a = from
        if let now { a = Swift.max(a, Int((Double(now) / 5).rounded(.up)) * 5) }
        var gaps: [(Int, Int)] = []
        var cur = a
        for (s, e) in busy.sorted(by: { $0.0 < $1.0 }) {
            if e <= cur { continue }
            if s > cur { gaps.append((cur, Swift.min(s, to))) }
            cur = Swift.max(cur, e)
            if cur >= to { break }
        }
        if cur < to { gaps.append((cur, to)) }
        return gaps.filter { $0.1 - $0.0 >= min }.map { (start: $0.0, end: $0.1) }
    }

    /// The day's hours stretched to cover anything busy outside them (timegrid.js hourRange), in minutes.
    public static func dayRange(busy: [(Int, Int)], from: Int = 8, to: Int = 21) -> (Int, Int) {
        var a = from, z = to
        for (s, e) in busy { a = Swift.min(a, s / 60); z = Swift.max(z, Int((Double(e) / 60).rounded(.up))) }
        return (Swift.max(0, a) * 60, Swift.min(24, z) * 60)
    }

    static func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }

    public static let planHead = "Plan my day."

    /// The Plan with Claude prompt (compose-day.js promptFor), with the task files it touches so Claude can edit them straight away.
    public static func planPrompt(today: String, nowMinute: Int, slipped: [SlippedTask], gaps: [(start: Int, end: Int)], files: [(path: String, text: String)]) -> String {
        var lines = ["\(planHead) Today is \(today), now \(hm(Swift.min(nowMinute, 24 * 60 - 1))).",
                     "Place the slipped tasks below into today's free time: for each one that fits, add \"\(today) HH:MM\" (its start) to the task's plan list in its file, one <edit> per task, and change nothing else. Say in one line what did not fit.",
                     "Slipped:"]
        for r in slipped { lines.append("- \(r.id) \"\(r.title.replacingOccurrences(of: "\"", with: "'"))\" in \(r.path), about \(r.minutes)m") }
        lines.append("Free today: " + (gaps.isEmpty ? "none" : gaps.map { "\(hm($0.start))-\(hm($0.end))" }.joined(separator: ", ")))
        var budget = 40_000
        for f in files where budget > 0 {
            let t = f.text.count > budget ? String(f.text.prefix(budget)) : f.text
            budget -= t.count
            lines.append("<result of=\"read \(f.path)\">\n\(t)\n</result>")
        }
        return lines.joined(separator: "\n")
    }

    /// For a change to a task file: the tasks that gained a plan entry on `today`. `planOnly`: nothing but plan entries changed; `auto`:
    /// planOnly and every plan change is on today (Plan with Claude accepts those at once, as the laptop does; Undo puts them back).
    public struct Placements: Equatable, Sendable {
        public struct Item: Equatable, Sendable { public var id: String; public var title: String; public var time: String? }
        public var list: [Item]
        public var planOnly: Bool
        public var auto: Bool
    }

    public static func placements(path: String, before: String, after: String, today: String) -> Placements? {
        guard isTaskFile(path), !before.isEmpty,
              let a = try? TaskFile.parse(before, file: path, workstream: nil), let b = try? TaskFile.parse(after, file: path, workstream: nil),
              let na = try? Yams.compose(yaml: before), let nb = try? Yams.compose(yaml: after) else { return nil }
        let planOnly = canon(na, skipping: "plan") == canon(nb, skipping: "plan")
        var auto = planOnly
        let was = Dictionary(a.tasks.filter(\.hasId).map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        var list: [Placements.Item] = []
        func live(_ ps: [PlanEntry]) -> [String] { ps.filter { $0.day >= today }.map { $0.raw } }
        for t in b.tasks where t.hasId {
            let p0 = live(was[t.id]?.plan ?? []), p1 = live(t.plan)
            let added = p1.filter { !p0.contains($0) }, removed = p0.filter { !p1.contains($0) }
            if added.isEmpty && removed.isEmpty { continue }
            if (added + removed).contains(where: { PlanEntry($0)?.day != today }) { auto = false }
            if let mine = added.compactMap(PlanEntry.init).first(where: { $0.day == today }) {
                list.append(.init(id: t.id, title: t.text, time: mine.time))
            }
        }
        guard !list.isEmpty else { return nil }
        return Placements(list: list, planOnly: planOnly, auto: auto)
    }

    /// A YAML tree as one string, without the `skipping` keys, to compare two versions of a file.
    static func canon(_ n: Node?, skipping: String) -> String {
        guard let n else { return "~" }
        if let m = n.mapping {
            return "{" + m.compactMap { pair in pair.key.string == skipping ? nil : (pair.key.string ?? "?") + ":" + canon(pair.value, skipping: skipping) }.joined(separator: ",") + "}"
        }
        if let s = n.sequence { return "[" + s.map { canon($0, skipping: skipping) }.joined(separator: ",") + "]" }
        return "'" + (n.string ?? "") + "'"
    }

    // MARK: a few free ids

    public static func freeIds(_ n: Int, taken: Set<String>) -> [String] {
        var t = taken
        var out: [String] = []
        for _ in 0..<n { let id = TaskIds.new(taken: t); t.insert(id); out.append(id) }
        return out
    }
}
