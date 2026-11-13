import SwiftUI
import NexusCore

/// Ideas on the iPad and iPhone: the data folder's nexus-ideas.yaml (NexusCore Ideas, the laptop's Customize › Ideas), read when the
/// screen shows and whenever the file changes underneath (sync, the laptop), written whole after each edit with Undo on the bar.
/// Claude sorts the new ones in a batch (5 waiting, or one from an earlier day, while the screen is open; Sort now any time), through
/// ClaudeClient (the app-wide Plan / API switch). "Claude" on an idea: a change to Nexus is marked for Claude and waits for the laptop's
/// change door; anything else Claude works on once, and its reply is kept with the idea.
@MainActor
@Observable
final class IdeasModel {
    private(set) var items: [Idea] = []
    private(set) var error: String?
    private(set) var loaded = false
    private(set) var sorting = false
    private(set) var working: Set<String> = []
    /// What the last batch did, or why it couldn't.
    private(set) var last: String?
    @ObservationIgnored private var stamp: Date?
    @ObservationIgnored private var written: String?
    @ObservationIgnored private var failedBatch: String?
    @ObservationIgnored private weak var store: NexusStore?

    static let testSeed = ProcessInfo.processInfo.arguments.contains("-NexusTestIdeas")

    private func url(_ name: String) -> URL? { store?.folder.appendingPathComponent(name) }
    private var today: String { Days.today() }

    func attach(_ s: NexusStore) { store = s; load() }

    /// Reads the file (or, with none yet, the To-do list's items) and folds in any conflict copy.
    func load() {
        guard let file = url(Ideas.file) else { return }
        if Self.testSeed && !FileManager.default.fileExists(atPath: file.path) { try? FolderAccess.write(file, Self.seed(today)) }
        let text = try? FolderAccess.read(file)
        stamp = Self.modified(file)
        if text == nil, let t = url(Ideas.todoFile) {
            let todo = try? FolderAccess.read(t)
            apply(Ideas.parse(nil, todo: todo), text: nil)
        } else {
            apply(Ideas.parse(text), text: text)
        }
        loaded = true
        foldCopies()
    }
    private func apply(_ p: Ideas.Parsed, text: String?) {
        written = text
        if let e = p.error { error = Ideas.file + " " + e + ", so Ideas is read-only until it is fixed on the laptop or in Files."; return }
        error = nil; items = p.items
    }
    func reloadIfChanged() {
        guard let file = url(Ideas.file) else { return }
        if Self.modified(file) != stamp { load() }
    }
    static func modified(_ u: URL) -> Date? { (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date }

    private func foldCopies() {
        guard let root = store?.folder, let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        for n in names where Ideas.isConflict(n) {
            let u = root.appendingPathComponent(n)
            guard let t = try? FolderAccess.read(u) else { continue }
            let p = Ideas.parse(t); if p.error != nil { continue }
            let f = Ideas.fold(items, p.items)
            if f.changed { save(f.items, message: nil) }
            try? FileManager.default.removeItem(at: u)
            store?.didWrite()
        }
    }

    /// Writes the list; with a message, the bar offers Undo.
    @discardableResult
    func save(_ next: [Idea], message: String?) -> Bool {
        guard loaded, let store, let file = url(Ideas.file) else { return false }
        if let error { store.problem = error; return false }
        guard next != items || written == nil else { return false }
        let text = Ideas.serialize(next)
        let before = written ?? Ideas.serialize(items) // (no file yet: Undo goes back to the carried-over list, written out)
        do {
            try FolderAccess.write(file, text)
            items = next; written = text; stamp = Self.modified(file)
            store.didWrite()
            if let message { store.toast = NexusStore.Toast(message: message, change: Change(file: Ideas.file, before: before, after: text, message: message)) }
            return true
        } catch {
            store.problem = "Couldn't save \(Ideas.file): \(error.localizedDescription)"
            return false
        }
    }

    // MARK: the edits

    var now: String { Ideas.stamp() }
    func add(_ text: String) -> Bool {
        let next = Ideas.add(items, text, today: today, now: now, from: Device.name)
        guard next != items else { return false }
        save(next, message: nil)
        autoSort()
        return true
    }
    func rename(_ x: Idea, _ title: String) { save(Ideas.rename(items, x.id, title, now: now), message: "Renamed") }
    func me(_ x: Idea) { save(Ideas.setWho(items, x.id, "me", now: now), message: x.who == "me" ? "Undecided: \(x.shownTitle)" : "Yours: \(x.shownTitle)") }
    func tick(_ x: Idea) { save(Ideas.tick(items, x.id, today: today, now: now), message: x.done == nil ? "Done: \(x.shownTitle)" : "Not done: \(x.shownTitle)") }
    func remove(_ x: Idea) { save(Ideas.remove(items, x.id), message: "Removed “\(x.shownTitle)”") }
    func unmerge(_ x: Idea) { save(Ideas.unmerge(items, x.id, now: now), message: "On its own again") }

    /// Claude on one idea. Already sent: undecided again. A change to Nexus: marked for Claude (the laptop's Ideas puts it in its change
    /// door's ask box). Anything else: Claude works on it now.
    func claude(_ x: Idea) {
        if working.contains(x.id) { return }
        if x.who == "claude" && x.sent != nil { save(Ideas.setWho(items, x.id, nil, now: now), message: "Undecided: \(x.shownTitle)"); return }
        if Ideas.goesToDoor(x) {
            save(Ideas.setWho(items, x.id, "claude", now: now), message: "For Claude: send it from Ideas on the laptop, where changes to Nexus are made")
            return
        }
        working.insert(x.id)
        save(x.who == "claude" ? items : Ideas.setWho(items, x.id, "claude", now: now), message: nil)
        let repeats = items.filter { $0.sameAs == x.id }
        let req = ClaudeRequest(model: "sonnet", system: Ideas.workSystem, messages: [.user(Ideas.workPrompt(x, repeats: repeats))], maxTokens: 1200)
        Task {
            do {
                let r = try await ClaudeClient.shared.stream(req) { _ in }
                let text = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { throw ClaudeError("Claude sent back nothing.") }
                reloadIfChanged()
                save(Ideas.markSent(items, x.id, today: today, reply: text, now: now), message: "Claude worked on “\(x.shownTitle)”")
            } catch {
                store?.problem = "Claude could not work on “\(x.shownTitle)”: " + ((error as? ClaudeError)?.message ?? error.localizedDescription)
            }
            working.remove(x.id)
        }
    }

    // MARK: sorting

    func autoSort() {
        guard loaded, error == nil, !sorting, Ideas.due(items, today: today) else { return }
        let key = Ideas.organisePrompt(items).batch.joined(separator: ",")
        if key == failedBatch { return }
        sort(auto: true)
    }
    func sort(auto: Bool = false) {
        guard !sorting, error == nil else { return }
        let (batch, prompt) = Ideas.organisePrompt(items)
        guard !batch.isEmpty else { if !auto { last = "Nothing new to sort." }; return }
        sorting = true; last = nil
        let req = ClaudeRequest(model: "sonnet", system: Ideas.organiseSystemPlain, messages: [.user(prompt)], maxTokens: 4096)
        Task {
            defer { sorting = false }
            do {
                let r = try await ClaudeClient.shared.stream(req) { _ in }
                guard let reply = Ideas.readReply(r.text) else { throw ClaudeError("Claude's answer could not be read.") }
                reloadIfChanged() // (an edit that arrived meanwhile)
                let out = Ideas.applyOrganise(items, reply, batch: batch, today: today, now: now)
                failedBatch = nil
                guard out.sorted > 0 else { last = "Claude didn't sort any of them; they wait for the next try."; return }
                save(out.items, message: Ideas.sortedLine(out.sorted, out.topics))
                last = Ideas.sortedLine(out.sorted, out.topics)
            } catch {
                failedBatch = batch.joined(separator: ",")
                last = "Could not sort the new ideas: " + ((error as? ClaudeError)?.message ?? error.localizedDescription) + " They wait for the next try."
            }
        }
    }

    var statusLine: String {
        let w = Ideas.group(items).waiting.count
        if sorting { return w == 1 ? "Claude is sorting the new idea…" : "Claude is sorting the \(min(w, Ideas.batchMax)) new ideas…" }
        if let last { return last }
        if w == 0 { return "Everything is sorted." }
        return (w == 1 ? "1 new idea waits" : "\(w) new ideas wait") + " to be sorted. Claude sorts them once \(Ideas.batchAt) wait, or the day after."
    }

    /// The UI check's ideas (-NexusTestIdeas): sorted ones in topics, one Claude worked on, a repeat, two new.
    static func seed(_ today: String) -> String {
        var a = Idea(id: "t0n3l1qx", text: "Make board text better. Typed text on boards is good for now; polish it later."); a.title = "Make board text better"; a.note = "Typed text on boards is good for now; polish it later."; a.topic = "Nexus"; a.kind = "nexus"; a.added = "2026-11-11"; a.organised = "2026-11-11"; a.who = "claude"
        var b = Idea(id: "i8wq2k1m", text: "um so a week view in the planner where i can drag stuff between days"); b.title = "A week view in the Planner"; b.note = "Drag tasks between days."; b.topic = "Nexus"; b.kind = "nexus"; b.added = today; b.from = "iPhone"; b.organised = today
        var c = Idea(id: "i3b7v0dd", text: "planner week view with drag"); c.topic = "Nexus"; c.kind = "nexus"; c.added = today; c.organised = today; c.sameAs = "i8wq2k1m"
        var d = Idea(id: "i5k9m2aa", text: "an app that reminds me to stretch every hour when im at the desk"); d.title = "An app that reminds me to stretch every hour at my desk"; d.topic = "App ideas"; d.kind = "app"; d.added = today; d.organised = today
        var e = Idea(id: "i2p4r6tt", text: "run a 10k before summer"); e.title = "Run a 10k before summer"; e.topic = "Health"; e.kind = "life"; e.added = today; e.organised = today; e.who = "claude"; e.sent = today
        e.reply = "Here is a start on \"Run a 10k before summer\":\n- Pick a race date in May and count back 10 weeks\n- Weeks 1 to 3: three easy 20-minute runs a week\nOne question: can you run in the mornings?"
        var f = Idea(id: "i7h1c8zz", text: "call grandma on sunday"); f.title = "Call grandma on Sunday"; f.topic = "Family"; f.kind = "life"; f.added = today; f.organised = today; f.who = "me"
        var g = Idea(id: "i9x0c3de", text: "build a little weather station with the raspberry pi"); g.added = today; g.from = "iPhone"
        var h = Idea(id: "i4f6g8hh", text: "learn the basics of watercolour"); h.added = today
        return Ideas.serialize([a, b, c, d, e, f, g, h])
    }
}
