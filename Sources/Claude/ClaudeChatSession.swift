import SwiftUI
import NexusCore

/// One line of a conversation as the screen shows it.
struct ChatItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case user, claude, lookup, change, note }
    enum State: String, Codable { case pending, accepted, rejected, failed, undone, stale }

    var id = UUID()
    var kind: Kind
    var text: String
    /// A change: its file, whether it is new, and the file before and after (dropped once it is decided and saved, to keep the file small).
    var path: String?
    var isNew = false
    var before: String?
    var after: String?
    /// An edit's own old and new text, to apply it again over an earlier Accept to the same file.
    var old: String?
    var new: String?
    var state: State?
    /// Why a change can't be saved, or an error note's detail.
    var problem: String?
    /// A change Plan with Claude accepted at once (placements on today).
    var auto = false
    /// A note that offers Try again.
    var retry = false
}

/// A conversation with Claude (the laptop's Claude panel). There are a few, by key, as on the laptop: `main`, opened from the sidebar, the
/// Claude button and Plan with Claude, and `apps` for Applications. Each keeps its messages, its model and its plan-mode session, and is
/// shared by every window. A turn goes round until Claude stops asking to look things up (at most 6 rounds); edits and new files wait as
/// cards for Accept or Reject; the next message tells Claude what was decided. It is kept on the device (Application Support), never in
/// the data folder.
@MainActor
@Observable
final class ClaudeConversation {
    let key: String
    private(set) var items: [ChatItem] = []
    /// sonnet | haiku | opus, for the next message (the conversation's header menu).
    var model: String
    private(set) var busy = false
    /// What Claude is doing ("Reading inbox.yaml"), while busy.
    private(set) var status: String?
    /// Claude's words as they stream (without its tags).
    private(set) var streaming = ""
    /// Bumped on every change, for scrolling.
    private(set) var version = 0
    /// The text in the box (kept while the conversation is closed).
    var draft = ""
    /// What the screen adds to each message (Applications' schools); set by whoever opens the conversation.
    @ObservationIgnored var context: (@MainActor () -> String)?
    /// "Today", "Chemistry (classes/chem)": what the user is looking at, set by the screen that opens the conversation.
    var looking: String?

    @ObservationIgnored private var history: [ClaudeMessage] = []
    @ObservationIgnored private var sessionId: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var accepted: [String] = []
    @ObservationIgnored private var rejected: [String] = []
    @ObservationIgnored private var failed: [String] = []
    @ObservationIgnored private var lastPrompt: (shown: String, prompt: String)?

    init(key: String) {
        self.key = key
        model = UserDefaults.standard.string(forKey: "claude.model") ?? "sonnet"
        load()
    }

    var isEmpty: Bool { items.isEmpty }
    var pendingCount: Int { items.filter { $0.kind == .change && $0.state == .pending }.count }
    /// A short name for the conversation (its first message).
    var title: String { items.first { $0.kind == .user }.map { String($0.text.prefix(60)) } ?? "New conversation" }

    // MARK: sending

    /// Sends what the user typed; a "/" command is expanded to its prompt (the laptop's claudecommands.js).
    func send(_ typed: String) {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        let store = AppServices.store
        var prompt = t
        if let c = ClaudeChat.command(in: t), let p = ClaudeChat.expand(c.name, args: c.args, today: store.today, dayHours: Self.dayHours) { prompt = p }
        run(shown: t, prompt: prompt)
    }

    /// A message whose prompt differs from what the conversation shows (a command button, Plan with Claude).
    func run(shown: String, prompt: String, plan: PlanRun? = nil) {
        guard !busy else { return }
        let store = AppServices.store
        lastPrompt = (shown, prompt)
        items.append(ChatItem(kind: .user, text: shown))
        // proposals still waiting are left as they are; Claude hears they were not decided
        let first = history.isEmpty
        let s = store.snapshot
        let p = store.planning
        let ws: [ClaudeChat.WorkstreamLine]? = first ? s.groups.flatMap { g in
            s.workstreams(in: g).filter { !$0.finished }.map { ClaudeChat.WorkstreamLine(id: $0.id, name: $0.name, folder: $0.folder, open: p.openCount($0.id), parked: $0.parked) }
        } : nil
        let ctx = ClaudeChat.context(looking: looking, today: store.today, now: Self.clock(), workstreams: ws, inboxOpen: first ? p.openCount(nil) : nil,
                                     freeIds: ClaudeChat.freeIds(4, taken: Set(s.tasks.keys)), extra: context?())
        let decided = ClaudeChat.decisions(accepted: accepted, rejected: rejected, failed: failed)
        accepted = []; rejected = []; failed = []
        history.append(.user(ctx + decided + prompt))
        busy = true
        status = plan == nil ? "Thinking" : "Working on your day"
        bump()
        save()
        task = Task { await self.loop(plan: plan) }
    }

    func stop() { task?.cancel() }

    /// Sends the last message again (after an error).
    func retry() {
        guard let l = lastPrompt, !busy else { return }
        items.removeAll { $0.retry }
        if let i = items.lastIndex(where: { $0.kind == .user && $0.text == l.shown }) { items.remove(at: i) }
        run(shown: l.shown, prompt: l.prompt)
    }

    /// Starts over (the laptop's New conversation); the old one is kept under Earlier conversations.
    func clear() {
        guard !busy else { return }
        if !items.isEmpty { ClaudeArchive.add(key: key, file: file()) }
        items = []; history = []; sessionId = nil; accepted = []; rejected = []; failed = []; draft = ""; lastPrompt = nil
        bump(); save()
    }

    /// Takes an earlier conversation back up (this one goes to Earlier conversations).
    func resume(_ f: ClaudeArchive.File) {
        guard !busy else { return }
        if !items.isEmpty { ClaudeArchive.add(key: key, file: file()) }
        ClaudeArchive.remove(key: key, id: f.id)
        apply(f)
        bump(); save()
    }

    // MARK: the turn

    private func loop(plan: PlanRun?) async {
        defer { busy = false; status = nil; streaming = ""; bump(); save(); plan?.finished(self) }
        let store = AppServices.store
        let ws = ClaudeChat.Workspace(root: store.folder, read: FolderAccess.read)
        let rules = (try? FolderAccess.read(store.folder.appendingPathComponent(ClaudeRules.file))).flatMap { $0.isEmpty ? nil : $0 }
        let system = ClaudeChat.system(rules: rules, device: Device.name)
        let historyBefore = history.count - 1
        var retriedEdits = false
        for round in 0..<6 {
            streaming = ""
            let req = ClaudeRequest(model: model, system: system, messages: Self.trimmed(history), maxTokens: 4096, sessionId: sessionId)
            let reply: ClaudeReply
            do {
                reply = try await Self.ask(req) { [weak self] piece in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self?.streamed(piece) } }
                }
            } catch {
                // the turn's messages go, so Try again starts clean
                if history.count > historyBefore { history.removeSubrange(historyBefore...) }
                items.append(ChatItem(kind: .note, text: (error as? ClaudeError)?.message ?? error.localizedDescription, retry: true))
                return
            }
            if let sid = reply.sessionId { sessionId = sid }
            history.append(.assistant(reply.text.isEmpty ? "(no reply)" : reply.text))
            streaming = ""
            var lookups: [ClaudeChat.Action] = []
            var unusable: [ChatItem] = []
            for piece in ClaudeChat.parse(reply.text) {
                switch piece {
                case .text(let t):
                    items.append(ChatItem(kind: .claude, text: t))
                case .action(let a) where a.isLookup:
                    lookups.append(a)
                    items.append(ChatItem(kind: .lookup, text: a.label))
                case .action(let a):
                    let path = a.path ?? ""
                    let pr = ws.propose(a, id: UUID().uuidString, takenIds: ClaudeChat.idsOutside(path, in: store.snapshot))
                    var item = ChatItem(kind: .change, text: a.label, path: pr.path, isNew: pr.isNew, before: pr.before, after: pr.after,
                                        state: pr.problem == nil ? .pending : .failed, problem: pr.problem)
                    if case .edit(_, let old, let new) = a { item.old = old; item.new = new }
                    if pr.problem == nil, let plan, let pl = ClaudeChat.placements(path: pr.path, before: pr.before, after: pr.after, today: store.today), pl.auto {
                        item.auto = true
                        items.append(item)
                        accept(item.id)
                        plan.placed(item.id, title: pl.list.map { $0.title + ($0.time.map { " at " + $0 } ?? "") }.joined(separator: ", "))
                        continue
                    }
                    if pr.problem != nil { unusable.append(item) }
                    items.append(item)
                }
            }
            bump()
            if reply.stopped { items.append(ChatItem(kind: .note, text: "Stopped.")); return }
            if lookups.isEmpty && (unusable.isEmpty || retriedEdits) { return }
            if round == 5 { items.append(ChatItem(kind: .note, text: "Claude looked things up six times without finishing; ask again to go on.")); return }
            if !unusable.isEmpty { retriedEdits = true }
            var answers = lookups.map { ws.answer($0) }
            answers += unusable.map { "<result of=\"edit \($0.path ?? "")\">\nNot usable: \($0.problem ?? "")\n</result>" }
            status = lookups.first.map { Self.doing($0) } ?? "Trying the change again"
            history.append(.user(answers.joined(separator: "\n\n")))
        }
    }

    private func streamed(_ piece: String) {
        streaming += piece
        if let line = ClaudeChat.parse(streaming, final: false).last, case .action(let a) = line { status = Self.doing(a) }
        bump()
    }

    static func doing(_ a: ClaudeChat.Action) -> String {
        switch a {
        case .read(let p): return "Reading " + p
        case .list(let p): return "Looking in " + (p.isEmpty ? "the data folder" : p)
        case .search(let q): return "Searching for “\(q)”"
        case .edit(let p, _, _), .write(let p, _): return "Writing a change to " + p
        }
    }

    /// API mode sends the whole conversation each time: results from earlier rounds are cut short so it stays small.
    static func trimmed(_ h: [ClaudeMessage]) -> [ClaudeMessage] {
        h.enumerated().map { i, m in
            guard i < h.count - 3, m.role == "user", m.text.contains("<result of="), m.text.count > 2000 else { return m }
            return .user(String(m.text.prefix(1500)) + "\n… (earlier result, cut; read it again if you need it)")
        }
    }

    /// The demo for the screenshots (-NexusClaudeDemo) or the real Claude.
    static func ask(_ req: ClaudeRequest, onText: @escaping (String) -> Void) async throws -> ClaudeReply {
        if ClaudeDemo.active { return await ClaudeDemo.stream(req, onText: onText) }
        return try await ClaudeClient.shared.stream(req, onText: onText)
    }

    // MARK: deciding

    func accept(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .pending, let path = items[i].path else { return }
        let store = AppServices.store
        if let why = store.snapshot.readOnlyReason { fail(i, why); return }
        let url = store.folder.appendingPathComponent(path)
        let taken = ClaudeChat.idsOutside(path, in: store.snapshot)
        var after = items[i].after ?? ""
        if items[i].isNew {
            if FileManager.default.fileExists(atPath: url.path) { fail(i, "\(path) exists now; ask Claude to change it instead."); return }
        } else {
            // worked out again when the file changed since the card was made (an earlier Accept to the same file)
            let now = (try? FolderAccess.read(url)) ?? ""
            if now != (items[i].before ?? "") {
                guard let old = items[i].old, let new = items[i].new, case .success(let again) = ClaudeChat.replace(old, with: new, in: now) else {
                    items[i].state = .stale
                    items[i].problem = "\(path) changed since Claude proposed this; ask Claude again."
                    failed.append(path + " (it changed since)")
                    bump(); save(); return
                }
                items[i].before = now
                items[i].after = again
                after = again
            }
        }
        if let why = ClaudeChat.check(path, after, takenIds: taken) { fail(i, why); return }
        do { try FolderAccess.write(url, after) } catch { fail(i, "Couldn't save \(path): \(error.localizedDescription)"); return }
        items[i].state = .accepted
        accepted.append(path + (items[i].isNew ? " (new)" : ""))
        store.reload()
        store.didWrite(listChanged: items[i].isNew, touched: [path])
        bump(); save()
    }

    func reject(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .pending else { return }
        items[i].state = .rejected
        rejected.append(items[i].path ?? "")
        bump(); save()
    }

    func acceptAll() { for it in items where it.kind == .change && it.state == .pending { accept(it.id) } }

    /// Puts an accepted change back, if the file still holds what it wrote (a new file is removed).
    func undo(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), items[i].state == .accepted, let path = items[i].path else { return }
        let store = AppServices.store
        let url = store.folder.appendingPathComponent(path)
        guard (try? FolderAccess.read(url)) == items[i].after else { note("\(path) changed since; it was left as it is."); return }
        do {
            if items[i].isNew && (items[i].before ?? "").isEmpty { try FileManager.default.removeItem(at: url) }
            else { try FolderAccess.write(url, items[i].before ?? "") }
        } catch { note("Couldn't put \(path) back: \(error.localizedDescription)"); return }
        items[i].state = .undone
        accepted.removeAll { $0.hasPrefix(path) }
        rejected.append(path + " (accepted, then undone)")
        store.reload()
        store.didWrite(listChanged: items[i].isNew, touched: [path])
        bump(); save()
    }

    private func fail(_ i: Int, _ why: String) {
        items[i].state = .failed
        items[i].problem = why
        failed.append("\(items[i].path ?? ""): \(why)")
        bump(); save()
    }

    private func bump() { version &+= 1 }

    private func note(_ text: String) { items.append(ChatItem(kind: .note, text: text)); bump(); save() }

    // MARK: kept on the device

    struct Message: Codable { var role: String; var text: String }
    struct File: Codable {
        var id = UUID()
        var items: [ChatItem]
        var history: [Message]
        var sessionId: String?
        var model: String
        var updated: Date
    }

    func file() -> File {
        File(items: items.map(Self.slim), history: history.map { Message(role: $0.role, text: $0.text) }, sessionId: sessionId, model: model, updated: Date())
    }

    /// A decided change keeps only what Undo needs; an undecided one only its words once the app restarts.
    static func slim(_ it: ChatItem) -> ChatItem {
        var x = it
        if it.kind == .change, it.state != .pending && it.state != .accepted { x.before = nil; x.after = nil }
        return x
    }

    private func apply(_ f: File) {
        items = f.items
        history = f.history.map { ClaudeMessage(role: $0.role, content: [.text($0.text)]) }
        sessionId = f.sessionId
        model = f.model
    }

    private var url: URL { ClaudeArchive.folder.appendingPathComponent("\(key).json") }

    private func save() {
        guard !ClaudeDemo.active else { return }
        let f = file()
        let u = url
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(f) { try? d.write(to: u, options: .atomic) }
        }
    }

    private func load() {
        guard !ClaudeDemo.active, let d = try? Data(contentsOf: url), var f = try? JSONDecoder().decode(File.self, from: d) else { return }
        // a change left waiting when the app closed can't be accepted any more (the file may have changed)
        for i in f.items.indices where f.items[i].kind == .change && f.items[i].state == .pending {
            f.items[i].state = .stale; f.items[i].problem = "Not decided before Nexus closed; ask Claude again."
        }
        apply(f)
    }

    // MARK: helpers

    static var dayHours: Double { let h = UserDefaults.standard.double(forKey: "claude.dayHours"); return h > 0 ? h : 6 }

    static func clock(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// Earlier conversations, kept on the device (the last 15 of each kind).
enum ClaudeArchive {
    typealias File = ClaudeConversation.File
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("claude-chats", isDirectory: true)
    }
    static func url(_ key: String) -> URL { folder.appendingPathComponent("\(key)-earlier.json") }

    static func list(key: String) -> [File] {
        guard let d = try? Data(contentsOf: url(key)), let l = try? JSONDecoder().decode([File].self, from: d) else { return [] }
        return l
    }
    static func add(key: String, file: File) {
        guard !ClaudeDemo.active else { return }
        save(key, Array(([file] + list(key: key)).prefix(15)))
    }
    static func remove(key: String, id: UUID) { save(key, list(key: key).filter { $0.id != id }) }
    private static func save(_ key: String, _ l: [File]) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(l) { try? d.write(to: url(key), options: .atomic) }
    }
}

/// Where the conversations live and how a screen opens one: on the iPad as the column beside the screen (the laptop's pinned Claude
/// column), on the iPhone as a sheet over it. The sidebar's Claude row shows the main conversation as its own screen on both.
@MainActor
@Observable
final class ClaudeChatSession {
    static let shared = ClaudeChatSession()
    @ObservationIgnored private var conversations: [String: ClaudeConversation] = [:]
    /// The conversation shown in the side column (iPad) or the sheet (iPhone), when one is open.
    var presented: String?

    func conversation(_ key: String) -> ClaudeConversation {
        if let c = conversations[key] { return c }
        let c = ClaudeConversation(key: key)
        conversations[key] = c
        return c
    }

    /// Opens a conversation beside (iPad) or over (iPhone) the screen. `context` is added to each message; `looking` names the screen.
    static func open(conversation key: String = "main", looking: String? = nil, context: (@MainActor () -> String)? = nil, draft: String? = nil) {
        let c = shared.conversation(key)
        if let context { c.context = context }
        if let looking { c.looking = looking }
        if let draft { c.draft = draft }
        shared.presented = key
    }

    /// Opens the main conversation and sends a message at once (a command button, Ask Claude about a task).
    static func ask(_ shown: String, prompt: String? = nil, looking: String? = nil, conversation key: String = "main") {
        open(conversation: key, looking: looking)
        let c = shared.conversation(key)
        if let prompt { c.run(shown: shown, prompt: prompt) } else { c.send(shown) }
    }
}
