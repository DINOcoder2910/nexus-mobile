import Foundation

/// Spanish › the tutor's memory and its conversation, pure: a port of the laptop's renderer/src/spanishmemory.js. Five layers, all plain
/// files in study/spanish/, linked by skill id: the profile (labelled blocks, always read), a note per skill (skills/<id>.md, linked with
/// [[...]] to the chats where it came up), episodes (the log and the chats, never rewritten), the numbers per skill (stats.yaml) and the
/// content (decks, prompts, pieces). After a chat, one call writes its summary, the skill notes it touched and the new profile; the
/// profile's changes are worked out here, block by block, so the user sees exactly what moved.
///
/// One difference from the laptop: there the tutor opens and searches the memory files itself (Claude Code's Read, Glob and Grep). On the
/// iPhone and iPad Claude has no tools (the API, or the plan through the hub), so the chat starts with more of the memory already in it:
/// the course, the notes on the skills that need practice most, and the recent mistakes from the log.
public enum SpanishMemory {
    // MARK: the profile: "## <block title>" sections

    public static func parseProfile(_ text: String) -> [String: String] {
        var out = Dictionary(uniqueKeysWithValues: Spanish.profileBlocks.map { ($0.key, "") })
        let byTitle = Dictionary(uniqueKeysWithValues: Spanish.profileBlocks.map { ($0.title.lowercased(), $0.key) })
        var cur: String?
        var buf: [String: [String]] = [:]
        for line in JS.split(#"\r?\n"#, text) {
            if let m = JS.match(#"^##\s+(.+?)\s*$"#, line) {
                cur = byTitle[m[1].lowercased()]
                if let cur { buf[cur] = [] }
                continue
            }
            if let c = cur, !JS.test("^<!--.*-->$", line.trimmed) { buf[c, default: []].append(line) }
        }
        for (k, lines) in buf { out[k] = lines.joined(separator: "\n").trimmed }
        return out
    }

    public static func serializeProfile(_ blocks: [String: String]) -> String {
        var lines = ["# Spanish: my profile", "", Spanish.profileNote, ""]
        for b in Spanish.profileBlocks { lines += ["## \(b.title)", "", (blocks[b.key] ?? "").trimmed, ""] }
        return JS.replace(#"\n{3,}"#, lines.joined(separator: "\n"), "\n\n")
    }

    /// A block's lines, for the diff: bullets (or sentences) without their markers.
    static func linesOf(_ s: String) -> [String] {
        JS.split(#"\r?\n"#, s).map { JS.replace(#"^\s*[-*]\s+"#, $0, "").trimmed }.filter { !$0.isEmpty }
    }

    public struct Change: Equatable, Sendable, Identifiable {
        public var block, title: String
        public var added, removed: [String]
        public var before, after: String
        public var id: String { block }
    }
    public static func profileChanges(_ before: [String: String], _ after: [String: String]) -> [Change] {
        var out: [Change] = []
        for b in Spanish.profileBlocks where !b.mine {
            let a = linesOf(before[b.key] ?? ""), c = linesOf(after[b.key] ?? "")
            let added = c.filter { !a.contains($0) }, removed = a.filter { !c.contains($0) }
            if !added.isEmpty || !removed.isEmpty { out.append(Change(block: b.key, title: b.title, added: added, removed: removed, before: before[b.key] ?? "", after: after[b.key] ?? "")) }
        }
        return out
    }

    /// A block over its size cap keeps its first lines (the newest are written first); what is cut is returned.
    public static func capBlock(_ key: String, _ text: String) -> (text: String, cut: [String]) {
        let t = text.trimmed
        guard let b = Spanish.profileBlocks.first(where: { $0.key == key }), JS.len(t) > b.cap else { return (t, []) }
        let lines = t.components(separatedBy: "\n")
        var keep: [String] = [], n = 0
        for l in lines {
            if n + JS.len(l) + 1 > b.cap { break }
            keep.append(l); n += JS.len(l) + 1
        }
        return (keep.joined(separator: "\n"), Array(lines.dropFirst(keep.count)))
    }

    // MARK: the tutor: its rules and what a chat starts with

    public static func tutorSystem(base: String, model: String) -> String {
        [
            "You are the Spanish tutor inside Nexus, for an IB Spanish ab initio student in grade 12. Explanations are in English, examples in Spanish. Be warm, exact and brief: a few short paragraphs at most.",
            "", "How a session goes: ask the student something in Spanish at their level (their current unit unless they ask for something else), check what they write, explain the mistake they actually made (not a general lecture), show one or two correct examples, then ask a follow-up that makes them use the same thing again. When they get it right twice, move on. Answer any question they ask.",
            "", "When you want them to write, end your message with exactly one block like this (the app turns it into a checker card; their answer comes back to you with every mistake, the skill involved and what they did right):",
            "```check", "<your question or instruction>", "```",
            "Only one check block per message, always last. Do not repeat the question outside the block.",
            "", "When a word is worth keeping as a flashcard, you can offer it with a block (the app shows an \"Add to deck\" button; nothing is added unless they press it):",
            "```card", #"{"front": "la maleta", "back": "the suitcase", "deck": "es-viajes", "tags": ["pos::sustantivo"], "example": "Hago la maleta."}"#, "```",
            "Vocab decks: es-nucleo, es-viajes, es-bienestar, es-tecnologia, es-laboral (where the word was met). Grammar decks (an answer that fills a slot in a pattern): es-presente, es-perfecto, es-indefinido, es-futuro, es-imperativo, es-pronombres, es-uso. Nouns always carry their article; one thing per card.",
            "", "Memory. Everything you know about the student is in plain files under \(base)/\(Spanish.dir)/, which the app reads for you: this chat is on the student's iPhone or iPad, and you cannot open files here. The first message starts with <memory>: their profile (\(base)/\(Spanish.P.profile)), the course (what has been taught, by year and teacher), the skills that need practice most with your notes on them, their recent mistakes from the log, the last chats and their decks. You never write files (the app records the session afterwards).",
            "Use that history before teaching something, so you build on what they have done instead of repeating it.",
            "", "Course rules: teach only what has been taught unless they ask for something new. A skill marked \"teach again from scratch\" is taught from the beginning, as if new. A skill marked \"not taught yet\" is taught only when they ask.",
            model.isEmpty ? "" : "(Model: \(model).)",
        ].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public struct ChatInfo: Equatable, Sendable {
        public var path, title, summary: String
        public init(path: String, title: String, summary: String) { self.path = path; self.title = title; self.summary = summary }
    }
    public struct DeckInfo: Equatable, Sendable {
        public var id, title: String
        public var cards: Int
        public init(id: String, title: String, cards: Int) { self.id = id; self.title = title; self.cards = cards }
    }

    /// The first message's context: the profile, the course status, the numbers, the last chats, the decks and prompts; on the iPhone and
    /// iPad also the course file, the notes on the weakest skills and the recent mistakes (what the laptop's tutor would open itself).
    public static func tutorIndex(base: String, profile: String, status: [String: String], stats: [(id: String, stat: SpanishCheck.Stat)], chats: [ChatInfo] = [],
                                  decks: [DeckInfo] = [], prompts: Int = 0, unit: String = "", today: String = "",
                                  course: String = "", notes: [(id: String, text: String)] = [], recent: [SpanishCheck.Entry] = []) -> String {
        let weak = SpanishCheck.weakest(stats, 8)
        var lines = ["<memory>", "Today: \(today).\(unit.isEmpty ? "" : " Current unit: \(unit).")", "", "## Profile (\(base)/\(Spanish.P.profile))",
                     profile.trimmed.isEmpty ? "(empty: this is the first chat)" : profile.trimmed, "", "## Course status"]
        for st in ["reteach", "not-yet"] {
            let ids = Spanish.skills.filter { status[$0.id] == st }.map(\.id)
            lines.append("- \(Spanish.statusWords[st]!): \(ids.isEmpty ? "none" : ids.joined(separator: ", "))")
        }
        lines += ["- everything else: taught", "", "## Skills by need (from the log; due 0-1 = how much it needs practice now)"]
        lines += weak.isEmpty ? ["- nothing checked yet"] : weak.map { "- \($0.id) (\(Spanish.skillName($0.id))): \(SpanishCheck.statWords[$0.stat.status] ?? $0.stat.status), \($0.stat.accuracy)% over \($0.stat.tries) tries, due \(JSONValue.format($0.stat.due))" }
        lines += ["", "## Last chats"]
        lines += chats.isEmpty ? ["- none yet"] : chats.prefix(3).map { "- \($0.path): \($0.summary.isEmpty ? $0.title : $0.summary)" }
        if chats.count > 3 { lines.append("(\(chats.count - 3) older in \(base)/\(Spanish.P.chats)/)") }
        lines += ["", "## Decks"]
        lines += decks.isEmpty ? ["- none"] : decks.map { "- \($0.id): \($0.title), \($0.cards) cards" }
        lines.append("## Writing prompts from the tutor: \(prompts)")
        if !course.trimmed.isEmpty { lines += ["", "## The course (\(base)/\(Spanish.P.course))", String(course.trimmed.prefix(4000))] }
        if !notes.isEmpty {
            lines += ["", "## Your notes on the skills that need practice most (\(base)/\(Spanish.P.notes)/)"]
            for n in notes { lines += ["### \(n.id)", String(n.text.trimmed.prefix(1500))] }
        }
        let wrong = recent.filter { !$0.mistakes.isEmpty }.suffix(25)
        if !wrong.isEmpty {
            lines += ["", "## Their recent mistakes (from the log, oldest first)"]
            for e in wrong {
                lines.append("- \(e.at.prefix(10)): \(e.text) -> \(e.fixed) [\(e.mistakes.map(\.skill).joined(separator: ", "))]")
            }
        }
        lines.append("</memory>")
        return lines.joined(separator: "\n")
    }

    // MARK: the tutor's reply: its text, a check block (the question for the checker card), card offers

    public struct Reply: Equatable, Sendable {
        public var text: String
        public var check: String?
        public var cards: [SpanishCards.Draft]
    }
    public static func parseReply(_ text: String) -> Reply {
        var cards: [SpanishCards.Draft] = []
        var check: String?
        let ns = text as NSString
        var body = ""
        var at = 0
        for m in JS.re("```(check|card)\\s*\\n([\\s\\S]*?)```").matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            body += ns.substring(with: NSRange(location: at, length: m.range.location - at))
            at = NSMaxRange(m.range)
            let kind = ns.substring(with: m.range(at: 1)), inner = ns.substring(with: m.range(at: 2)).trimmed
            if kind == "check" { check = inner; continue }
            if let o = try? JSONValue.parse(inner), let f = o["front"]?.string, let b = o["back"]?.string, !f.isEmpty, !b.isEmpty {
                cards.append(SpanishCards.Draft(front: f, back: b, deck: o["deck"]?.string ?? "es-nucleo", tags: (o["tags"]?.array ?? []).compactMap(\.string), example: o["example"]?.string ?? ""))
            }
        }
        body += ns.substring(from: at)
        // an unclosed check block while it streams
        if let r = body.range(of: "```check") {
            if check == nil { let rest = String(body[r.upperBound...]).trimmed; check = rest.isEmpty ? nil : rest }
            body = String(body[..<r.lowerBound])
        }
        return Reply(text: body.trimmed, check: check, cards: cards)
    }

    // MARK: a chat's file: chats/<YYYY-MM-DD HHMM> <title>.md, front matter + the conversation

    public struct Message: Equatable, Sendable {
        /// user | tutor | check
        public var role: String
        public var text: String
        public init(role: String, text: String) { self.role = role; self.text = text }
    }
    public struct Chat: Equatable, Sendable {
        public var path = ""
        public var title = "Tutor chat"
        public var started = ""
        public var model = "sonnet"
        public var session = ""
        public var summary = ""
        public var skills: [String] = []
        public var taught: [String] = []
        public var messages: [Message] = []
        public init(path: String = "", title: String = "Tutor chat", started: String = "", model: String = "sonnet", session: String = "", summary: String = "",
                    skills: [String] = [], taught: [String] = [], messages: [Message] = []) {
            self.path = path; self.title = title; self.started = started; self.model = model; self.session = session; self.summary = summary
            self.skills = skills; self.taught = taught; self.messages = messages
        }
    }

    public static func slug(_ s: String) -> String {
        let x = JS.replace(#"\s+"#, JS.replace(#"[\\/:*?"<>|#^\[\]]+"#, s.isEmpty ? "chat" : s, " "), " ").trimmed
        let cut = String((x as NSString).substring(to: min(50, JS.len(x))))
        return cut.isEmpty ? "chat" : cut
    }
    public static func chatPath(base: String, started: String, title: String) -> String {
        let d = started
        return "\(base)/\(Spanish.P.chats)/\(JS.slice(d, 0, 10)) \(JS.slice(d, 11, 13))\(JS.slice(d, 14, 16)) \(slug(title)).md"
    }

    public static func serializeChat(_ c: Chat) -> String {
        let fm = YValue.map([.init("title", .string(c.title.isEmpty ? "Tutor chat" : c.title)), .init("started", .string(c.started)), .init("model", .string(c.model.isEmpty ? "sonnet" : c.model)),
                             .init("session", .string(c.session)), .init("summary", .string(c.summary)), .init("skills", .list(c.skills.map { .string($0) })),
                             .init("taught", .list(c.taught.map { .string($0) }))]).yaml.trimmed
        let body = c.messages.map { m in m.role == "user" ? "**You:** \(m.text)" : m.role == "check" ? "> Checked: \(m.text)" : "**Tutor:** \(m.text)" }.joined(separator: "\n\n")
        return "---\n\(fm)\n---\n\n# \(c.title.isEmpty ? "Tutor chat" : c.title)\n\n\(body)\n"
    }

    public static func parseChat(_ text: String, path: String = "") -> Chat {
        var fm: YValue = .null
        var body = text
        if let m = JS.match(#"^---\n([\s\S]*?)\n---\n?([\s\S]*)$"#, text) {
            fm = (try? YValue.parse(m[1])) ?? .null
            body = m[2]
        }
        var messages: [Message] = []
        for part in splitMessages(body) {
            let t = part.trimmed
            if let r = JS.match(#"^\*\*You:\*\*\s*([\s\S]*)$"#, t) { messages.append(Message(role: "user", text: r[1].trimmed)) }
            else if let r = JS.match(#"^\*\*Tutor:\*\*\s*([\s\S]*)$"#, t) { messages.append(Message(role: "tutor", text: r[1].trimmed)) }
            else if let r = JS.match(#"^> Checked:\s*([\s\S]*)$"#, t) { messages.append(Message(role: "check", text: r[1].trimmed)) }
        }
        let model = fm["model"]?.str ?? ""
        return Chat(path: path, title: fm["title"]?.str ?? "", started: fm["started"]?.str ?? "", model: model.isEmpty ? "sonnet" : model, session: fm["session"]?.str ?? "",
                    summary: fm["summary"]?.str ?? "", skills: fm["skills"]?.strings ?? [], taught: fm["taught"]?.strings ?? [], messages: messages)
    }

    /// body.split(/\n\n(?=\*\*You:\*\*|\*\*Tutor:\*\*|> Checked:)/)
    static func splitMessages(_ body: String) -> [String] {
        let ns = body as NSString
        var out: [String] = [], at = 0
        for m in JS.re(#"\n\n(?=\*\*You:\*\*|\*\*Tutor:\*\*|> Checked:)"#).matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: at, length: m.range.location - at)))
            at = NSMaxRange(m.range)
        }
        out.append(ns.substring(from: at))
        return out
    }

    // MARK: after a chat: one call writes the summary, the skill notes it touched and the new profile

    public static let memorySystem = "You keep the memory of a Spanish tutor: an exact, compact record of what a student can do, what they get wrong and what they have been taught. Never invent; keep what is still true; write short bullets."
    static let memoryShape = #"{"title": "a short title for the chat (3-6 words)", "summary": "2-3 lines: what was covered, how it went, what to do next", "skills": ["skill ids practised or discussed"], "taught": [{"skill": "a skill id", "what": "what was taught and how, in one line"}], "profile": {"strengths": "markdown bullets, newest first", "working": "...", "mistakes": "...", "taught": "...", "next": "...", "learn": "..."}, "notes": [{"skill": "a skill id", "lines": ["new lines for the skill note: what was taught, a typical mistake with its fix"]}]}"#

    public static func memoryPrompt(profile: [String: String], chat: Chat, stats: [(id: String, stat: SpanishCheck.Stat)], status: [String: String], feedback: String = "") -> String {
        let blocks = Spanish.profileBlocks.filter { !$0.mine }
        let caps = blocks.map { "\($0.key) (\($0.title), at most \($0.cap) characters)" }.joined(separator: "; ")
        let now = JSONValue.object(blocks.map { ($0.key, JSONValue.string(profile[$0.key] ?? "")) }).pretty
        let statLines = stats.prefix(30).map { "\($0.id): \($0.stat.status), \($0.stat.accuracy)% over \($0.stat.tries)" }.joined(separator: "\n")
        let notTaught = Spanish.skills.filter { (status[$0.id] ?? "taught") != "taught" }.map { "\($0.id): \(Spanish.statusWords[status[$0.id]!] ?? "")" }.joined(separator: "\n")
        let convo = chat.messages.map { "\($0.role == "user" ? "Student" : $0.role == "check" ? "Checker" : "Tutor"): \($0.text)" }.joined(separator: "\n\n")
        let mine = profile["mine"] ?? ""
        return ["(Nexus Spanish memory)", "", "Update the student's memory after this tutor chat.", "", "## Their profile now", now, "",
                mine.isEmpty ? "" : "## Their own notes (read them; never change them)\n\(mine)\n",
                "## The numbers per skill (from every sentence they checked)", statLines.isEmpty ? "none yet" : statLines, "",
                "## Skills not taught yet / to teach again", notTaught.isEmpty ? "none" : notTaught, "", "## The chat", convo, "",
                feedback.isEmpty ? "" : "## The student's feedback on your last update (follow it)\n\(feedback)\n",
                "Write: a title and summary for the chat; the skill ids involved; what was taught; the whole new profile, block by block (\(caps)): keep what is still true, change what the chat showed, newest first; and for each skill touched, new lines for its note. Use skill ids from: \(Spanish.skills.map(\.id).joined(separator: ", ")).",
                "", "Answer with only one JSON object, in this shape: " + memoryShape].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public struct Memory: Equatable, Sendable {
        public var title, summary: String
        public var skills: [String]
        public var taught: [(skill: String, what: String)]
        public var profile: [String: String]
        public var notes: [(skill: String, lines: [String])]
        public static func == (a: Memory, b: Memory) -> Bool {
            a.title == b.title && a.summary == b.summary && a.skills == b.skills && a.profile == b.profile
                && a.taught.map { $0.skill + "\u{1}" + $0.what } == b.taught.map { $0.skill + "\u{1}" + $0.what }
                && a.notes.map { $0.skill + "\u{1}" + $0.lines.joined(separator: "\u{2}") } == b.notes.map { $0.skill + "\u{1}" + $0.lines.joined(separator: "\u{2}") }
        }
    }

    public static func readMemory(_ ans: JSONValue?) -> Memory? {
        guard let ans, let p = ans["profile"], p.object != nil else { return nil }
        func s(_ v: JSONValue?) -> String { v?.string ?? "" }
        func id(_ x: String) -> String { Spanish.isSkill(x) ? x : Spanish.toSkill(x) }
        var skills: [String] = []
        for x in (ans["skills"]?.array ?? []).compactMap(\.string) { let i = id(x); if !skills.contains(i) { skills.append(i) } }
        let title = s(ans["title"]).trimmed
        return Memory(title: String((title.isEmpty ? "Tutor chat" : title).prefix(60)), summary: s(ans["summary"]).trimmed, skills: skills,
                      taught: (ans["taught"]?.array ?? []).filter { !s($0["what"]).isEmpty }.map { (skill: id(s($0["skill"])), what: s($0["what"])) },
                      profile: Dictionary(uniqueKeysWithValues: Spanish.profileBlocks.filter { !$0.mine }.map { ($0.key, s(p[$0.key]).trimmed) }),
                      notes: (ans["notes"]?.array ?? []).compactMap { n in
                          let lines = (n["lines"]?.array ?? []).compactMap(\.string).filter { !$0.isEmpty }
                          return lines.isEmpty ? nil : (skill: id(s(n["skill"])), lines: lines)
                      })
    }

    // MARK: a skill's note: skills/<id>.md, its rule and status, then dated lines, each linking to where it came from

    public static func noteHeader(_ id: String, status: String) -> String {
        let s = Spanish.skill[id]
        return ["# \(s?.name ?? id)", "", "Skill id: `\(id)` · \(Spanish.statusWords[status] ?? "taught")", "", s.map { "**Rule:** \($0.rule)" } ?? "", "", "## Notes", ""].joined(separator: "\n")
    }

    /// The note with new lines added under "## Notes" (newest first), each "- <day>: <line> ([[chat]])".
    public static func addToNote(_ existing: String, id: String, status: String, lines: [String], day: String, link: String = "") -> String {
        let text = existing.trimmed.isEmpty ? noteHeader(id, status: status) : existing
        let add = lines.map { "- \(day): \($0.trimmed)\(link.isEmpty ? "" : " ([[\(link)]])")" }.joined(separator: "\n")
        guard let r = text.range(of: "## Notes") else { return text.trimEnd + "\n\n## Notes\n\n" + add + "\n" }
        let lineEnd = text[r.upperBound...].firstIndex(of: "\n").map { text.index(after: $0) } ?? text.endIndex
        let rest = String(text[lineEnd...])
        return String(text[..<lineEnd]) + "\n" + add + "\n" + JS.replace(#"^\n+"#, rest, "")
    }

    public static func linkName(_ path: String) -> String { JS.replace(#"\.md$"#, JS.replace("^.*/", path, ""), "", ci: true) }
}
