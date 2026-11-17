import SwiftUI
import NexusCore

/// Spanish on the iPhone and iPad: the laptop's Spanish study (a workstream whose study/study.yaml says `language: spanish`; nexus
/// docs/guide.md "Spanish"), read from and written to the same plain files in `<workstream>/study/spanish/`, so a check made on the
/// phone shows in the laptop's History and the tutor remembers a chat whichever device it was on. Here: finding the Spanish workstreams,
/// reading their files (the course status, the profile, the log and its numbers, the chats, the prompts and pieces), and every write the
/// screens make (a check added to the log, the numbers counted again, a prompt, a chat, the profile after its review, a skill's note, a
/// marked piece, a card added to a deck, Set up). The pure halves are NexusCore's Spanish*.swift.
@MainActor
@Observable
final class SpanishLibrary {
    static let shared = SpanishLibrary()

    struct ChatRow: Identifiable, Equatable {
        var path, title, started, summary, model: String
        var count: Int
        var id: String { path }
    }

    /// One Spanish workstream's files, as read.
    struct Data {
        var status = Spanish.courseStatus
        var profileText = ""
        var profile = SpanishMemory.parseProfile("")
        var course = ""
        var entries: [SpanishCheck.Entry] = []
        var stats: [(id: String, stat: SpanishCheck.Stat)] = []
        var chats: [ChatRow] = []
        var prompts: [SpanishGrade.Prompt] = []
        var promptsError: String?
        var pieces: [SpanishGrade.PieceInfo] = []
        var samples: [SpanishGrade.Sample] = []
        var noteFiles: Set<String> = []
        /// A month's log that does not parse (nothing is written over it).
        var brokenLogs: [String] = []

        func stat(_ id: String) -> SpanishCheck.Stat? { stats.first { $0.id == id }?.stat }
    }

    /// The Spanish workstreams, in sidebar order.
    private(set) var workstreams: [Workstream] = []
    private(set) var data: [String: Data] = [:]
    /// The open tutor chat of each workstream (kept while the app runs, so leaving the chat and coming back finds it as it was).
    var chats: [String: SpanishChat] = [:]
    /// The checker's last result on each workstream's screen.
    var current: [String: SpanishCheckRun] = [:]
    /// A save that could not be made.
    var problem: String?
    /// Writing: each prompt's piece as it is being written, and its marking (by "<workstream>|<prompt id>").
    var drafts: [String: String] = [:]
    var grades: [String: SpanishGradeRun] = [:]
    @ObservationIgnored private var stamps: [String: String] = [:]
    @ObservationIgnored private var listStamp = ""

    func workstream(_ id: String) -> Workstream? { workstreams.first { $0.id == id } }
    func data(_ id: String) -> Data { data[id] ?? Data() }
    var first: Workstream? { workstreams.first }

    // MARK: finding and reading

    /// The workstreams whose study.yaml says Spanish, read again when the folder changed; a workstream's files are read again when they changed.
    func refreshIfChanged(_ store: NexusStore) {
        guard store.snapshot.isDataFolder else { workstreams = []; return }
        let root = store.folder
        let ws = StudyFolder.workstreams(root, store.snapshot).filter { w in
            Spanish.studyLanguage(try? FolderAccess.read(root.appendingPathComponent(w.folder + "/study/study.yaml"))) == "spanish"
        }
        let ids = ws.map(\.id).joined(separator: "|")
        if ids != listStamp || ws.map(\.name) != workstreams.map(\.name) { workstreams = ws; listStamp = ids }
        for w in ws {
            let fp = Self.fingerprint(root, w)
            if fp != stamps[w.id] { load(store, w) }
        }
    }

    func reload(_ store: NexusStore, _ id: String) {
        if let w = workstream(id) ?? store.workstream(id) { load(store, w) }
    }

    static func fingerprint(_ root: URL, _ w: Workstream) -> String {
        let dir = root.appendingPathComponent(w.folder + "/" + Spanish.dir)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return "" }
        var parts: [String] = []
        for case let u as URL in walk {
            let v = try? u.resourceValues(forKeys: keys)
            parts.append("\(u.path.dropFirst(dir.path.count)):\(v?.fileSize ?? -1):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return parts.sorted().joined(separator: "|")
    }

    /// Every file under study/spanish/, relative to the data folder.
    private func files(_ root: URL, _ w: Workstream) -> [String] {
        let base = w.folder + "/" + Spanish.dir
        let dir = root.appendingPathComponent(base)
        guard let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        let prefix = dir.standardizedFileURL.path
        var out: [String] = []
        for case let u as URL in walk where (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            out.append(base + "/" + String(u.standardizedFileURL.path.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
        return out.sorted()
    }

    private func read(_ root: URL, _ rel: String) -> String? {
        let u = root.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }
        return try? FolderAccess.read(u)
    }

    func load(_ store: NexusStore, _ w: Workstream) {
        let root = store.folder
        if canWrite(store) { foldLogCopies(store, w) }
        let all = files(root, w)
        let base = w.folder + "/"
        let logs = all.filter { $0.hasPrefix(base + Spanish.P.logDir + "/") && ($0 as NSString).lastPathComponent.range(of: #"^\d{4}-\d{2}\.ya?ml$"#, options: .regularExpression) != nil }
        let chats = all.filter { $0.hasPrefix(base + Spanish.P.chats + "/") && $0.lowercased().hasSuffix(".md") && !SyncPaths.isConflictCopy($0) }.sorted(by: >)
        let pieces = all.filter { $0.hasPrefix(base + Spanish.P.writing + "/") && $0.lowercased().hasSuffix(".md") }.sorted(by: >)
        let samples = all.filter { $0.hasPrefix(base + Spanish.P.samples + "/") && $0.lowercased().hasSuffix(".md") }
        var d = Data()
        d.status = Spanish.parseSkills(read(root, base + Spanish.P.skills))
        d.profileText = read(root, base + Spanish.P.profile) ?? ""
        d.profile = SpanishMemory.parseProfile(d.profileText)
        d.course = read(root, base + Spanish.P.course) ?? ""
        for p in logs {
            let r = SpanishCheck.parseLog(read(root, p))
            if r.ok { d.entries += r.entries } else { d.brokenLogs.append(p) }
        }
        d.entries = d.entries.enumerated().sorted { $0.element.at != $1.element.at ? $0.element.at < $1.element.at : $0.offset < $1.offset }.map(\.element)
        d.stats = SpanishCheck.skillStats(d.entries, now: Date().timeIntervalSince1970 * 1000)
        d.chats = chats.prefix(80).compactMap { p in
            guard let t = read(root, p) else { return nil }
            let c = SpanishMemory.parseChat(t, path: p)
            return c.messages.isEmpty ? nil : ChatRow(path: p, title: c.title.isEmpty ? "Tutor chat" : c.title, started: c.started, summary: c.summary, model: c.model, count: c.messages.count)
        }
        let pr = SpanishGrade.parsePrompts(read(root, base + Spanish.P.prompts))
        d.prompts = pr.prompts
        d.promptsError = pr.error
        d.pieces = pieces.prefix(80).compactMap { p in read(root, p).flatMap { SpanishGrade.pieceInfo($0, path: p) } }
        d.samples = samples.compactMap { read(root, $0).flatMap(SpanishGrade.parseSample) }
        d.noteFiles = Set(all.filter { $0.hasPrefix(base + Spanish.P.notes + "/") })
        data[w.id] = d
        stamps[w.id] = Self.fingerprint(root, w)
    }

    /// The hub's conflict copies of a month's log ("2026-11 (conflict iPad 2026-11-16 1030).yaml"): their checks are added to the month's
    /// file (each check once, by its time and words) and the copy removed.
    private func foldLogCopies(_ store: NexusStore, _ w: Workstream) {
        let root = store.folder
        let dir = w.folder + "/" + Spanish.P.logDir
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(dir).path)) ?? []
        for name in names where SyncPaths.isConflictCopy(name) {
            guard let m = name.range(of: #"^\d{4}-\d{2}"#, options: .regularExpression) else { continue }
            let main = dir + "/" + String(name[m]) + ".yaml"
            let copy = SpanishCheck.parseLog(read(root, dir + "/" + name)), mine = SpanishCheck.parseLog(read(root, main))
            guard copy.ok, mine.ok else { continue }
            var seen = Set(mine.entries.map { $0.at + "\u{1}" + $0.text })
            let extra = copy.entries.filter { seen.insert($0.at + "\u{1}" + $0.text).inserted }
            do {
                if !extra.isEmpty {
                    let all = (mine.entries + extra).enumerated().sorted { $0.element.at != $1.element.at ? $0.element.at < $1.element.at : $0.offset < $1.offset }.map(\.element)
                    try FolderAccess.write(root.appendingPathComponent(main), SpanishCheck.serializeLog(all))
                }
                try FileManager.default.removeItem(at: root.appendingPathComponent(dir + "/" + name))
                store.didWrite(touched: [main, dir + "/" + name])
            } catch {
                problem = "A copy of the Spanish log could not be merged: \(error.localizedDescription)"
            }
        }
    }

    // MARK: writing

    func canWrite(_ store: NexusStore) -> Bool { store.snapshot.isDataFolder && store.snapshot.readOnlyReason == nil }

    private func write(_ store: NexusStore, _ rel: String, _ text: String) throws {
        guard canWrite(store) else { throw ClaudeError(store.snapshot.readOnlyReason ?? "The data folder is read-only.") }
        try FolderAccess.write(store.folder.appendingPathComponent(rel), text)
    }

    /// Now, as the laptop stores a check's time: today's date (the day start from Settings) and the local time, to the millisecond (a
    /// check's id in History).
    static func stamp(_ store: NexusStore? = nil) -> String {
        let d = Date()
        let c = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: d)
        let ms = (c.nanosecond ?? 0) / 1_000_000
        return String(format: "%@T%02d:%02d:%02d.%03d", Days.today(), c.hour ?? 0, c.minute ?? 0, c.second ?? 0, ms)
    }

    /// A check: added to this month's log (the lines there stay as they were) and the numbers counted again into stats.yaml.
    func addToLog(_ store: NexusStore, _ wsId: String, _ entry: SpanishCheck.Entry) {
        guard let w = workstream(wsId) else { return }
        var d = data(wsId)
        d.entries.append(entry)
        d.stats = SpanishCheck.skillStats(d.entries, now: Date().timeIntervalSince1970 * 1000)
        data[wsId] = d
        let path = w.folder + "/" + Spanish.P.log(SpanishCheck.monthOf(entry.at))
        let stats = w.folder + "/" + Spanish.P.stats
        do {
            guard let text = SpanishCheck.appendToLog(read(store.folder, path), entry) else {
                problem = "The Spanish log for this month does not parse, so this check was not saved: \(path)"
                return
            }
            try write(store, path, text)
            try write(store, stats, SpanishCheck.serializeStats(d.stats, nowIso: Self.stamp()))
            stamps[wsId] = Self.fingerprint(store.folder, w)
            store.didWrite(touched: [path, stats])
        } catch {
            problem = "Could not save the check: \(error.localizedDescription)"
        }
    }

    /// A prompt from the tutor, added to prompts.yaml (read again first, so one added on the laptop is kept).
    func addPrompt(_ store: NexusStore, _ wsId: String, text: String, unit: String, types: [String], source: String) -> Bool {
        guard let w = workstream(wsId) else { return false }
        let path = w.folder + "/" + Spanish.P.prompts
        let parsed = SpanishGrade.parsePrompts(read(store.folder, path))
        guard parsed.ok else { problem = (parsed.error ?? "prompts.yaml does not parse") + ": the prompt was not added."; return false }
        let p = SpanishGrade.Prompt(id: SpanishGrade.newPromptId(parsed.prompts, day: Days.today()), text: text, unit: unit, types: types, source: source, added: Days.today())
        do {
            try write(store, path, SpanishGrade.serializePrompts(parsed.prompts + [p]))
            data[wsId]?.prompts = parsed.prompts + [p]
            store.didWrite(touched: [path])
            return true
        } catch { problem = "Could not add the prompt: \(error.localizedDescription)"; return false }
    }

    /// A marked piece, saved as writing/<day> <words>.md; returns its path.
    func savePiece(_ store: NexusStore, _ wsId: String, prompt: SpanishGrade.Prompt, text: String, count: SpanishGrade.Count, grade: SpanishGrade.Grade) -> String? {
        guard let w = workstream(wsId) else { return nil }
        let day = Days.today()
        let words = prompt.text.split(whereSeparator: { $0.isWhitespace }).prefix(6).joined(separator: " ")
        let base = "\(w.folder)/\(Spanish.P.writing)/\(day) \(SpanishMemory.slug(String(words)))"
        var path = base + ".md", n = 2
        while FileManager.default.fileExists(atPath: store.folder.appendingPathComponent(path).path) { path = "\(base) \(n).md"; n += 1 }
        do {
            try write(store, path, SpanishGrade.pieceFile(prompt: prompt, text: text, count: count, grade: grade, day: day))
            data[wsId]?.pieces.insert(.init(path: path, prompt: prompt.id, written: day, words: count.counted, total: grade.total), at: 0)
            store.didWrite(touched: [path])
            return path
        } catch { problem = "Could not save the piece: \(error.localizedDescription)"; return nil }
    }

    /// A chat's file, written after every turn.
    func saveChat(_ store: NexusStore, _ wsId: String, _ c: SpanishChat) {
        guard let w = workstream(wsId), !c.messages.isEmpty else { return }
        if c.path.isEmpty { c.path = SpanishMemory.chatPath(base: w.folder, started: c.started, title: "tutor chat") }
        do {
            try write(store, c.path, SpanishMemory.serializeChat(c.file))
            var d = data(wsId)
            let row = ChatRow(path: c.path, title: c.title, started: c.started, summary: c.summary, model: c.model, count: c.messages.count)
            if let i = d.chats.firstIndex(where: { $0.path == c.path }) { d.chats[i] = row } else { d.chats.insert(row, at: 0) }
            data[wsId] = d
            stamps[wsId] = Self.fingerprint(store.folder, w)
            store.didWrite(touched: [c.path])
        } catch { problem = "Could not save the chat: \(error.localizedDescription)" }
    }

    func readChat(_ store: NexusStore, _ path: String) -> SpanishMemory.Chat? {
        read(store.folder, path).map { SpanishMemory.parseChat($0, path: path) }
    }

    /// After the review: the profile (the blocks kept), the chat renamed after its title, and each skill's note with its new lines.
    func saveMemory(_ store: NexusStore, _ wsId: String, chat c: SpanishChat, memory m: SpanishMemory.Memory, profile: [String: String]) throws -> (changes: Int, notes: Int) {
        guard let w = workstream(wsId) else { return (0, 0) }
        var d = data(wsId)
        var final = profile
        final["mine"] = d.profile["mine"] ?? ""
        let text = SpanishMemory.serializeProfile(final)
        let profilePath = w.folder + "/" + Spanish.P.profile
        try write(store, profilePath, text)
        d.profile = final
        d.profileText = text
        c.title = m.title; c.summary = m.summary; c.skills = m.skills; c.taught = m.taught.map { "\($0.skill): \($0.what)" }
        var touched = [profilePath]
        let want = SpanishMemory.chatPath(base: w.folder, started: c.started, title: m.title)
        if !c.path.isEmpty, want != c.path, !FileManager.default.fileExists(atPath: store.folder.appendingPathComponent(want).path) {
            do {
                try FileManager.default.moveItem(at: store.folder.appendingPathComponent(c.path), to: store.folder.appendingPathComponent(want))
                touched.append(c.path)
                d.chats.removeAll { $0.path == c.path }
                c.path = want
            } catch { /* keeps its first name */ }
        }
        data[wsId] = d
        saveChat(store, wsId, c)
        touched.append(c.path)
        var lines: [(skill: String, lines: [String])] = []
        func add(_ skill: String, _ ls: [String]) {
            if let i = lines.firstIndex(where: { $0.skill == skill }) { lines[i].lines += ls } else { lines.append((skill: skill, lines: ls)) }
        }
        for n in m.notes { add(n.skill, n.lines) }
        for t in m.taught { add(t.skill, ["Taught: " + t.what]) }
        for (skill, ls) in lines {
            let p = w.folder + "/" + Spanish.P.note(skill)
            let cur = read(store.folder, p) ?? ""
            try write(store, p, SpanishMemory.addToNote(cur, id: skill, status: d.status[skill] ?? "taught", lines: ls, day: Days.today(), link: SpanishMemory.linkName(c.path)))
            data[wsId]?.noteFiles.insert(p)
            touched.append(p)
        }
        stamps[wsId] = Self.fingerprint(store.folder, w)
        store.didWrite(listChanged: true, touched: touched)
        return (0, lines.count)
    }

    /// A skill's course status (taught, teach again, not yet), changed on its own line of skills.yaml.
    func setStatus(_ store: NexusStore, _ wsId: String, skill: String, status: String) {
        guard let w = workstream(wsId) else { return }
        let path = w.folder + "/" + Spanish.P.skills
        let text = Spanish.setSkillStatus(read(store.folder, path), id: skill, status: status)
        do {
            try write(store, path, text)
            data[wsId]?.status = Spanish.parseSkills(text)
            stamps[wsId] = Self.fingerprint(store.folder, w)
            store.didWrite(touched: [path])
        } catch { problem = "Could not change the skill: \(error.localizedDescription)" }
    }

    // MARK: decks and cards

    /// The workstream's flip decks (the ones a card can go to).
    func decks(_ wsId: String) -> [(path: String, deck: StudyDeck)] {
        (StudyLibrary.shared.study(wsId)?.decks ?? []).compactMap { f in f.deck.flatMap { $0.flip ? (path: f.path, deck: $0) : nil } }
    }

    /// The deck a new word goes to: the vocab deck of the unit being taught now, else Núcleo.
    func defaultDeck(_ wsId: String) -> String {
        let ids = decks(wsId).map(\.deck.id)
        if let u = Spanish.currentUnit, let dk = Spanish.decks.first(where: { $0.unit == u.code }), ids.contains(dk.id) { return dk.id }
        return "es-nucleo"
    }

    /// Writes one card at the end of the deck's cards; returns its id.
    func addCard(_ store: NexusStore, _ wsId: String, deckPath: String, _ card: SpanishCards.Draft) -> String? {
        do {
            let cur = read(store.folder, deckPath) ?? ""
            let r = try SpanishCards.addCardText(cur, front: card.front, back: card.back, tags: card.tags, example: card.example, day: Days.today())
            try write(store, deckPath, r.text)
            store.didWrite(touched: [deckPath])
            StudyLibrary.shared.load(store)
            return r.id
        } catch {
            problem = "Could not add the card: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Set up Spanish study

    /// Writes the files Set up writes (each only if it is not there; study.yaml gets `language: spanish`). Returns how many it wrote.
    @discardableResult
    func setUp(_ store: NexusStore, _ w: Workstream) -> Int {
        var n = 0, touched: [String] = []
        do {
            for f in Spanish.setupFiles() {
                let rel = w.folder + "/" + f.path
                let url = store.folder.appendingPathComponent(rel)
                if !FileManager.default.fileExists(atPath: url.path) { try write(store, rel, f.text); n += 1; touched.append(rel); continue }
                if f.path == "study/study.yaml", let now = Spanish.studyYamlWithSpanish((try? FolderAccess.read(url)) ?? "") { try write(store, rel, now); n += 1; touched.append(rel) }
            }
        } catch {
            problem = "Spanish study could not be set up: \(error.localizedDescription)"
        }
        if n > 0 { store.didWrite(listChanged: true, touched: touched) }
        StudyLibrary.shared.load(store)
        listStamp = ""
        refreshIfChanged(store)
        return n
    }

    static func canSetUp(_ w: Workstream?) -> Bool { w != nil }
}
