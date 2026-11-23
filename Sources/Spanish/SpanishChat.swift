import SwiftUI
import NexusCore

/// The Spanish tutor's chat, as the laptop's (nexus app/spanishchat.js): Claude explains in English, asks you to write (its question
/// becomes a checker card; your answer is checked with the three layers, logged, and the result goes back to the tutor), offers words as
/// cards, and remembers. The chat is a file (study/spanish/chats/<day time> <title>.md) written after every turn; End chat asks Claude
/// for the chat's title and summary, the notes on each skill touched and the whole new profile, and the changes are shown block by block
/// (keep or undo each one, or tell Claude what is wrong and Revise) before anything is saved.
///
/// On the iPhone and iPad the tutor cannot open files, so the first message carries the memory (SpanishMemory.tutorIndex: the profile,
/// the course, the weakest skills with their notes, the recent mistakes, the last chats, the decks). Plan mode keeps its own session
/// with the hub while the app runs; the file's `session` (the laptop's) is left as it was.
@MainActor
@Observable
final class SpanishChat: Identifiable {
    struct Msg: Identifiable {
        let id = UUID()
        /// user | tutor | check
        var role: String
        /// A tutor's message without its blocks; anything else as written.
        var text: String
        /// A tutor's message as it came (its blocks kept: the file keeps them, so an old chat opens as it was).
        var raw = ""
        var check: String?
        var cards: [SpanishCards.Draft] = []
        var answered = false
        /// The check of the answer (on the tutor's card, and on the "Checked" message after it).
        var run: SpanishCheckRun?

        static func tutor(_ raw: String) -> Msg {
            let r = SpanishMemory.parseReply(raw)
            return Msg(role: "tutor", text: r.text, raw: raw, check: r.check, cards: r.cards)
        }
    }

    struct Review {
        enum Phase { case working, review, error }
        var phase: Phase = .working
        var error = ""
        var memory: SpanishMemory.Memory?
        var after: [String: String] = [:]
        var changes: [SpanishMemory.Change] = []
        var keep: Set<String> = []
        var feedback = ""
    }

    let id = UUID()
    let wsId: String
    var path = ""
    var title = "Tutor chat"
    var started = ""
    var model = "sonnet"
    var session = ""
    var summary = ""
    var skills: [String] = []
    var taught: [String] = []
    var messages: [Msg] = []
    var busy = false
    var stream = ""
    var error = ""
    var draft = ""
    var review: Review?
    var closed = false
    /// A text type guide this chat is about (Practise with the tutor on a guide, or the guide its first message names), sent with the
    /// memory: the tutor here can't open the file the way the laptop's does.
    var guide = ""
    @ObservationIgnored private var relay: String?
    @ObservationIgnored private var turn: Task<Void, Never>?

    init(wsId: String, model: String) {
        self.wsId = wsId
        self.model = model
        started = SpanishLibrary.stamp()
    }

    /// An old chat, opened from its file.
    init(wsId: String, file c: SpanishMemory.Chat) {
        self.wsId = wsId
        path = c.path; title = c.title.isEmpty ? "Tutor chat" : c.title; started = c.started.isEmpty ? SpanishLibrary.stamp() : c.started
        model = c.model == "opus" ? "opus" : "sonnet"; session = c.session; summary = c.summary; skills = c.skills; taught = c.taught
        messages = c.messages.map { $0.role == "tutor" ? Msg.tutor($0.text) : Msg(role: $0.role, text: $0.text) }
        for i in messages.indices where messages[i].role == "tutor" && messages[i].check != nil && i + 1 < messages.count && messages[i + 1].role == "check" {
            messages[i].answered = true
        }
    }

    var file: SpanishMemory.Chat {
        SpanishMemory.Chat(path: path, title: title, started: started, model: model, session: session, summary: summary, skills: skills, taught: taught,
                           messages: messages.map { .init(role: $0.role, text: $0.role == "tutor" ? ($0.raw.isEmpty ? $0.text : $0.raw) : $0.text) })
    }

    var hasTutor: Bool { messages.contains { $0.role == "tutor" } }
    /// The tutor's last question, while it waits for an answer.
    var liveCheck: Int? {
        guard !busy, let i = messages.lastIndex(where: { $0.role == "tutor" }), messages[i].check != nil, !messages[i].answered else { return nil }
        return i
    }

    // MARK: a turn

    func send(_ store: NexusStore, _ text: String, role: String = "user") {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !t.isEmpty else { return }
        messages.append(Msg(role: role, text: t))
        error = ""
        if role == "user" { draft = "" }
        let lib = SpanishLibrary.shared
        guard let w = lib.workstream(wsId) else { return }
        let d = lib.data(wsId)
        if guide.isEmpty, messages.count == 1, let g = SpanishTextTypes.mentioned(t, d.guides) { guide = SpanishTextTypes.tutorSection(g) }
        let notes = SpanishCheck.weakest(d.stats, 4).compactMap { s -> (id: String, text: String)? in
            let p = w.folder + "/" + Spanish.P.note(s.id)
            guard d.noteFiles.contains(p), let t = try? FolderAccess.read(store.folder.appendingPathComponent(p)) else { return nil }
            return (id: s.id, text: t)
        }
        let unit = Spanish.currentUnit.map { "\($0.code) \($0.title)" } ?? ""
        let memory = SpanishMemory.tutorIndex(base: w.folder, profile: d.profileText, status: d.status, stats: d.stats,
                                             chats: d.chats.filter { $0.path != path }.map { .init(path: $0.path, title: $0.title, summary: $0.summary) },
                                             decks: lib.decks(wsId).map { .init(id: $0.deck.id, title: $0.deck.title, cards: $0.deck.cards.count) },
                                             prompts: d.prompts.count, unit: unit, today: Days.today(), course: d.course, notes: notes, recent: d.entries)
        let index = guide.isEmpty ? memory : memory + "\n\n" + guide
        // the conversation, the memory before its first message; the same role twice in a row is one message
        var convo: [ClaudeMessage] = []
        for (i, m) in messages.enumerated() {
            let role = m.role == "tutor" ? "assistant" : "user"
            var body = m.role == "tutor" ? (m.raw.isEmpty ? m.text : m.raw) : m.text
            if i == 0 { body = index + "\n\n" + body }
            if let last = convo.last, last.role == role { convo[convo.count - 1] = ClaudeMessage(role: role, content: [.text(last.text + "\n\n" + body)]) }
            else { convo.append(ClaudeMessage(role: role, content: [.text(body)])) }
        }
        if convo.first?.role == "assistant" { convo.insert(.user(index), at: 0) }
        let req = ClaudeRequest(model: model, system: SpanishMemory.tutorSystem(base: w.folder, model: model), messages: convo, maxTokens: 4096, sessionId: relay)
        busy = true
        stream = ""
        let asked = messages.count
        turn = Task { [weak self] in
            var failure: String?
            var reply = ""
            if SpanishDemo.active {
                reply = await SpanishDemo.tutor(t, turn: asked) { piece in Task { @MainActor in self?.stream += piece } }
            } else {
                do {
                    let r = try await ClaudeClient.shared.stream(req) { piece in Task { @MainActor in self?.stream += piece } }
                    reply = r.text
                    await MainActor.run { if let s = r.sessionId { self?.relay = s } }
                } catch {
                    failure = error.localizedDescription
                }
            }
            await MainActor.run {
                guard let self else { return }
                let raw = (reply.isEmpty ? self.stream : reply).trimmingCharacters(in: .whitespacesAndNewlines)
                let m = Msg.tutor(raw)
                if !m.text.isEmpty || m.check != nil || !m.cards.isEmpty { self.messages.append(m) }
                if let failure { self.error = "The tutor stopped: " + failure }
                self.busy = false
                self.stream = ""
                SpanishLibrary.shared.saveChat(store, self.wsId, self)
            }
        }
    }

    func stop() { turn?.cancel() }

    /// An answer to the tutor's question: checked (three layers, logged with the chat's name), then the result goes back to the tutor.
    func answer(_ store: NexusStore, at i: Int, _ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, messages.indices.contains(i), messages[i].run == nil else { return }
        let run = SpanishCheckRun(text: t, question: messages[i].check ?? "", source: "chat", chat: path.isEmpty ? "" : SpanishMemory.linkName(path))
        messages[i].run = run
        Task {
            let entry = await run.run(store, wsId: wsId)
            if let j = messages.firstIndex(where: { $0.run === run }) { messages[j].answered = true }
            send(store, SpanishCheck.resultForTutor(entry), role: "check")
            if let last = messages.indices.last, messages[last].role == "check", messages[last].run == nil { messages[last].run = run }
        }
    }

    // MARK: End chat: the memory update, reviewed before it is saved

    /// Returns true when the chat is finished at once (nothing for the tutor to remember, or Claude is not there).
    func end(_ store: NexusStore) -> Bool {
        guard !busy else { return false }
        if !hasTutor { SpanishLibrary.shared.saveChat(store, wsId, self); closed = true; return true }
        consolidate(store, feedback: "")
        return false
    }

    func consolidate(_ store: NexusStore, feedback: String) {
        var r = review ?? Review()
        r.phase = .working; r.error = ""
        review = r
        let d = SpanishLibrary.shared.data(wsId)
        var chat = file
        chat.messages = messages.map { m in
            .init(role: m.role, text: m.role == "tutor" ? [m.text, m.check.map { "(asked: \($0))" } ?? ""].filter { !$0.isEmpty }.joined(separator: "\n") : m.text)
        }
        let prompt = SpanishMemory.memoryPrompt(profile: d.profile, chat: chat, stats: d.stats, status: d.status, feedback: feedback)
        let model = self.model
        Task {
            do {
                let text = try await SpanishClaude.once(model: model, system: SpanishMemory.memorySystem, prompt: prompt, maxTokens: 6000, demo: { SpanishDemo.memory(feedback: feedback) })
                guard let mem = SpanishMemory.readMemory(SpanishCheck.jsonFrom(text)) else { throw ClaudeError("the answer had no profile in it") }
                var after = d.profile
                for (k, v) in mem.profile { after[k] = SpanishMemory.capBlock(k, v).text }
                let changes = SpanishMemory.profileChanges(d.profile, after)
                review = Review(phase: .review, memory: mem, after: after, changes: changes, keep: Set(changes.map(\.block)))
            } catch {
                review?.phase = .error
                review?.error = "Claude could not update the memory: " + error.localizedDescription
            }
        }
    }

    /// Saves what was kept; returns the words for the toast, or nil when it failed (the review shows why).
    func saveMemory(_ store: NexusStore) -> String? {
        guard let r = review, let mem = r.memory else { return nil }
        let d = SpanishLibrary.shared.data(wsId)
        var final = d.profile
        for c in r.changes where r.keep.contains(c.block) { final[c.block] = r.after[c.block] ?? "" }
        do {
            let n = try SpanishLibrary.shared.saveMemory(store, wsId, chat: self, memory: mem, profile: final)
            let kept = r.changes.filter { r.keep.contains($0.block) }.count
            closed = true
            review = nil
            return "Memory updated: \(kept == 1 ? "1 profile change" : "\(kept) profile changes")\(n.notes > 0 ? ", notes on \(n.notes == 1 ? "1 skill" : "\(n.notes) skills")" : "")."
        } catch {
            review?.phase = .error
            review?.error = "Could not save the memory: " + error.localizedDescription
            return nil
        }
    }

    func skipMemory(_ store: NexusStore) {
        SpanishLibrary.shared.saveChat(store, wsId, self)
        review = nil
        closed = true
    }
}

/// The tutor's model (Sonnet or Opus), kept on the device; the laptop keeps its own.
enum SpanishModel {
    static let all: [(id: String, label: String)] = [("sonnet", "Sonnet 5.5"), ("opus", "Opus 5.5")]
    static var current: String {
        get { UserDefaults.standard.string(forKey: "spanish.model") == "opus" ? "opus" : "sonnet" }
        set { UserDefaults.standard.set(newValue == "opus" ? "opus" : "sonnet", forKey: "spanish.model") }
    }
    static func label(_ id: String) -> String { all.first { $0.id == id }?.label ?? "Sonnet 5.5" }
}
