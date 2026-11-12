import Foundation

/// A tutor session, the same file as the laptop's `renderer/src/tutor/session.js` (nexus docs/data-format.md "Tutor sessions"): the
/// conversation is `tutor.json` beside a board's `board.json`, and what was drawn is ordinary board content. Either app carries a session
/// on: plan mode resumes its Claude Code session, API mode sends the earlier turns back (text only).
///
///     {"format": "nexus-tutor/1", "created": ISO, "title": "...", "sessionId": "<plan mode's session>" | null, "turns": [
///       {"at": ISO, "you": "what you asked", "reply": "Claude's reply as written (prose + <step> lines)", "mode": "plan" | "api",
///        "model": "...", "cost"?: dollars, "ms"?: until the first words}
///     ]}
public struct TutorSession: Equatable {
    public static let format = "nexus-tutor/1"
    public static let file = "tutor.json"
    public static let dir = "notebooks/Tutor"
    public static let historyTurns = 12

    public var created: String
    public var title: String
    public var sessionId: String?
    /// Each turn as its JSON object, so fields this app doesn't know are kept.
    public var turns: [JSONValue]

    public init(at: Date = Date(), title: String = "") {
        created = TutorSession.iso(at); self.title = title; sessionId = nil; turns = []
    }

    /// "2026-11-11T09:05:00.000Z", as JavaScript's toISOString.
    public static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    /// A few words of the first question, safe as a folder name (at most 40 characters).
    public static func topic(_ words: String) -> String {
        let clean = words.replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]{}]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        var s = ""
        for w in clean.split(separator: " ") {
            let next = (s + " " + w).trimmingCharacters(in: .whitespaces)
            if next.count > 40 { break }
            s = next
        }
        while let l = s.last, l == "." || l == " " { s.removeLast() }
        return s
    }

    /// The board for a new session started at `d` about `words`; `taken` says whether a path is in use.
    public static func path(at d: Date, words: String, taken: (String) -> Bool = { _ in false }, dir: String = TutorSession.dir, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        func p2(_ n: Int?) -> String { String(format: "%02d", n ?? 0) }
        let stamp = "\(c.year ?? 2000)-\(p2(c.month))-\(p2(c.day)) \(p2(c.hour))\(p2(c.minute))"
        let t = topic(words)
        let base = "\(dir)/\(stamp)\(t.isEmpty ? "" : " " + t)"
        for i in 1..<100 {
            let p = base + (i > 1 ? " (\(i))" : "") + ".board"
            if !taken(p) { return p }
        }
        return base + " \(Int(d.timeIntervalSince1970 * 1000)).board"
    }

    public struct Turn {
        public var at: Date
        public var you: String
        public var reply: String
        public var mode: String
        public var model: String?
        public var cost: Double?
        public var ms: Int?
        public var sessionId: String?
        public init(at: Date, you: String, reply: String, mode: String, model: String?, cost: Double? = nil, ms: Int? = nil, sessionId: String? = nil) {
            self.at = at; self.you = you; self.reply = reply; self.mode = mode; self.model = model; self.cost = cost; self.ms = ms; self.sessionId = sessionId
        }
    }

    @discardableResult
    public mutating func add(_ t: Turn) -> JSONValue {
        var o: [(String, JSONValue)] = [("at", .string(TutorSession.iso(t.at))), ("you", .string(t.you)), ("reply", .string(t.reply)),
                                        ("mode", .string(t.mode == "api" ? "api" : "plan")), ("model", t.model.map { .string($0) } ?? .null)]
        if let c = t.cost, c.isFinite { o.append(("cost", .number(TutorSteps.jsRound(c * 1e6) / 1e6))) }
        if let ms = t.ms { o.append(("ms", .number(Double(ms)))) }
        let turn = JSONValue.object(o)
        turns.append(turn)
        if let s = t.sessionId { sessionId = s }
        if title.isEmpty && !t.you.isEmpty { title = TutorSession.topic(t.you) }
        return turn
    }

    /// tutor.json's text: JSON.stringify(session, null, 1) and a newline, as the laptop writes it.
    public var serialized: String {
        JSONValue.object([("format", .string(TutorSession.format)), ("created", .string(created)), ("title", .string(title)),
                          ("sessionId", sessionId.map { .string($0) } ?? .null), ("turns", .array(turns))]).indented(1) + "\n"
    }

    public struct Parsed {
        public var ok: Bool
        public var session: TutorSession
        public var fresh = false
        public var newer = false
        public var error: String?
    }

    /// Reads tutor.json; a missing or broken file is a fresh session (the board itself still opens), a newer format is not written.
    public static func parse(_ text: String?, at: Date = Date()) -> Parsed {
        guard let text else { return Parsed(ok: true, session: TutorSession(at: at), fresh: true) }
        guard let js = try? JSONValue.parse(text) else { return Parsed(ok: false, session: TutorSession(at: at), error: "tutor.json does not parse") }
        guard case .object = js else { return Parsed(ok: false, session: TutorSession(at: at), error: "tutor.json is not an object") }
        let fm = js["format"]?.string ?? ""
        if fm != format {
            return Parsed(ok: false, session: TutorSession(at: at), newer: fm.range(of: #"^nexus-tutor/\d+$"#, options: .regularExpression) != nil,
                          error: "tutor.json is " + (fm.isEmpty ? "not a tutor session" : fm))
        }
        var s = TutorSession(at: at)
        s.created = js["created"]?.string ?? iso(at)
        s.title = js["title"]?.string ?? ""
        s.sessionId = js["sessionId"]?.string
        s.turns = (js["turns"]?.array ?? []).filter { t in
            guard case .object = t else { return false }
            return !(t["you"]?.string ?? "").isEmpty || !(t["reply"]?.string ?? "").isEmpty
        }
        return Parsed(ok: true, session: s)
    }

    public func you(_ t: JSONValue) -> String { t["you"]?.string ?? "" }
    public func reply(_ t: JSONValue) -> String { t["reply"]?.string ?? "" }

    /// What Replay plays again (the laptop's tutorboard.js `replay`): each turn whose reply draws something, read again into its
    /// sentences and steps in order, gestures included (they are never saved on the board); marks on the screen left out.
    public func replayTurns() -> [[TutorEvent]] {
        turns.compactMap { t -> [TutorEvent]? in
            let r = TutorReader.read(reply(t))
            guard !r.steps.isEmpty else { return nil }
            return r.events.filter { e in if case .step(let s) = e { return s.on != "screen" }; return true }
        }
    }

    /// API mode: the earlier turns as messages (role, text), the newest `max`; the first is the user's.
    public func history(max: Int = TutorSession.historyTurns) -> [(role: String, text: String)] {
        turns.suffix(max).flatMap { t -> [(role: String, text: String)] in
            [("user", you(t).isEmpty ? "(no words)" : you(t)), ("assistant", reply(t).isEmpty ? "(no reply)" : reply(t))]
        }
    }

    /// Plan mode resumes its Claude Code session when the last turn was in plan mode.
    public var planResume: String? {
        guard let last = turns.last, last["mode"]?.string == "plan", let s = sessionId else { return nil }
        return s
    }

    /// The conversation so far, for a plan mode turn that can't resume its session.
    public func recap(max: Int = TutorSession.historyTurns) -> String {
        let t = turns.suffix(max)
        guard !t.isEmpty else { return "" }
        return "The conversation so far in this tutoring session (you are carrying it on):\n"
            + t.map { "Student: \(you($0))\nYou: \(reply($0))" }.joined(separator: "\n\n")
    }

    /// Everything the tutor drew in this session, read back from the replies (for "already on the board").
    public var steps: [TutorStep] { turns.flatMap { TutorReader.read(reply($0)).steps } }
}

/// What the tutor's Claude is told, the same as the laptop's `renderer/src/tutor/prompt.js`, plus the iPad's own: there the tutor sees
/// the part of the board on screen (a picture with a coordinate grid, and the handwriting read from it) instead of a screenshot.
public enum TutorPrompt {
    public static let screenGuide = [
        "Marks on the screen: only when the screenshot is attached and you mean something that is really on it, at most 3 per reply.",
        "The screenshot has a grid drawn on it: columns A, B, C... from the left, rows 1, 2, 3... from the top. Give \"area\" (the cell with most of the thing) and a precise \"label\" (\"the Submit button\", \"the second equation\", \"the word oxidised in line 3\"): Nexus zooms into that cell and finds the exact spot from the label. Give \"target\" only when you are sure of the pixels.",
    ].joined(separator: "\n")

    public static let boardGuide = [
        "Their board: the picture attached is the part of the board on their screen, with a faint grid of this turn's coordinates (a line every 100 units, numbered along the top and left edges). Their own writing has the coordinates the grid shows, so you can circle, underline, box or point at it with board steps (target [x, y, w, h]), and draw arrows from it to your explanation.",
        "Use the boxes listed under <handwriting> and <typed> when the thing you mean is there: they are exact, the picture is not. (0, 0) is free space beside their writing: put your blocks from there, not on top of what they wrote.",
    ].joined(separator: "\n")

    static func lead(_ name: String, how: String) -> String {
        "You are a patient, warm tutor inside Nexus, \(name.isEmpty ? "the student's" : name + "'s") study app. \(how)"
    }

    static func body(_ stepsGuide: String, _ viewGuide: String) -> [String] {
        [
            "",
            "How you speak:",
            "- Talk like a good teacher sitting next to them: short, clear sentences, one idea each. Start with the answer, not a preamble.",
            "- Usually 2 to 6 sentences. Go longer when they ask for an explanation or a worked solution, and then explain step by step, a short sentence per step. Say \"you\" and \"we\".",
            "- Never write markdown, lists, headings, code or LaTeX in what you say: it is read aloud. Say symbols and maths in words (\"x squared\", \"delta H\", \"M n O 4 minus\").",
            "- Check understanding sometimes with a short question back, and end by inviting the next question only when it helps.",
            "- When they ask you to check their work, say what is right first, then the one most important fix.",
            "- If the screenshot has nothing to do with the question, ignore it. If you cannot see what they mean, say so and ask.",
            "",
            "Drawing: you teach at a board beside them, like a teacher at a whiteboard or a good explainer video. The board is the lesson: someone who missed the voice should be able to follow it from the board alone. Write each step on its own line as <step>{...one JSON object...}</step>, right after the sentence it goes with: it is drawn while that sentence is said.",
            "- Show while you tell: every sentence that explains something does something on the board as it is said: writes the next piece, points at what it names, or marks it. Never solve it all first and explain it afterwards in words, and never put all the steps at the start.",
            "- Build a picture piece by piece: the axes or the outline first, then one element per sentence (a side, a force, a point, a bond), each labelled as you name it. Draw the thing the question is about first (the wave, the graph, the triangle, the vectors, the molecule, the setup with its forces), then the working beside or below it.",
            "- Point while you talk: when you say \"this term\", \"this angle\", \"here\", point at it, the way a teacher taps the board: a point at {\"in\": id, \"part\": \"(x+3)\"} for part of an equation, {\"in\": id, \"at\": [2, -1]} for a point on a graph. Brief circles, underlines and arrows are for passing emphasis; ink without brief is for what should stay in the notes.",
            "- Point at least every two or three sentences: whenever a sentence names something already on the board (a term, a number, a side, a force, a point), put a point or a brief mark right after that sentence. One sentence, one gesture: if a sentence names two things, make it two sentences.",
            "- When you split a quantity into parts (velocity components, weight along and into a slope), draw the parts on the picture as dashed arrows, in the colours used in the maths, as you say them. A path of motion is drawn as a graph of its real equation, starting along its launch arrow.",
            "- Mark what you claim on the picture: a right angle gets an angle step with \"right\": true, an angle you name gets its arc and its letter, lengths, forces and points get their labels on them.",
            "- Write what matters, not every word: the symbols, key terms, each result, and the reason for each move as a short grey note to the right of its line (\"÷ 2 both sides\", \"zero product\", \"charge +7 → +2\"). A new word or term: say it and write it. Every result you say gets its own line.",
            "- Teach, not only solve: start from a concrete case or the numbers in front of them, name the parts before you use them, and sometimes ask them to predict the next step before you show it. Call out the common mistake in red, boxed, in a few words.",
            "- A grey note goes beside its line with \"at\": {\"right\": \"<id of the line>\"}, never at a coordinate. Label each side or quantity once (\"hypotenuse 5\"), not with a number and a separate word. Draw the common-mistake note right after the sentence that says it.",
            "- Make it look like a neat board: a title or the key equation first, working in a column under it, one line of working per math step, labels short (one to four words), arrows from the label to the exact thing, a box around the final answer. A longer explanation ends with a one-line summary in a box. Never restate a diagram as a list: point at its parts instead.",
            "- Layout: one column per topic. A diagram on the left (x 0 to 380) with notes or equations to its right (x 420 to 800) or below it; a new topic goes below everything, never beside it. Notes beside a diagram are short.",
            "- Colour links ideas: give each quantity one colour and keep it everywhere, in the picture, on every line (\\color{blue}{u} in maths) and in the summary; show cancelling with \\cancel{(x+3)} on the next line. Green for the answer, red for a mistake, grey for construction lines and notes, black for the rest; at most three colours besides black.",
            "- Any symbol or formula is maths, even in a label, a title or a sentence of text (\"y = e^{x}\", \"$\\mathrm{NH_3}$\", \"$2\\pi$\"). Graphs: x and y ranges that frame the interesting part, key points marked with their coordinates, the curve labelled with its equation, asymptotes and lines of symmetry as dashed grey lines. Draw a graph once and add curves to it with \"in\"; a curve you call dashed has \"dash\": true.",
            "- For small talk or a one-line answer, draw nothing. Follow-up turns tell you what is already on the board: point at it by its id instead of drawing it again.",
            "",
            stepsGuide.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            viewGuide,
            "",
            "Tags are never spoken. Write each tag in one piece, with valid JSON inside.",
        ]
    }

    /// The laptop's system prompt, word for word.
    public static func system(name: String = "", stepsGuide: String = TutorSteps.prompt) -> String {
        ([lead(name, how: "The student holds a key, asks out loud, and you answer out loud: everything you write outside a tag is spoken by a voice, sentence by sentence, as you write it.")]
            + body(stepsGuide, screenGuide)).joined(separator: "\n")
    }

    /// The iPad's: the tutor button instead of a key, the board on screen instead of a screenshot. The same every turn (so it caches).
    public static func iPadSystem(name: String = "") -> String {
        ([lead(name, how: "The student is writing on a board on their iPad. They hold the tutor button and ask out loud (or type), and you answer out loud: everything you write outside a tag is spoken by a voice, sentence by sentence, as you write it.")]
            + body(TutorSteps.iPadPrompt, boardGuide)).joined(separator: "\n")
            .replacingOccurrences(of: "If the screenshot has nothing", with: "If the picture of their board has nothing")
    }

    /// One thing read on the board: handwriting (Vision) or a typed block, with its box in the turn's coordinates.
    public struct Seen: Equatable {
        public var text: String
        public var box: TutorBox
        public init(text: String, box: TutorBox) { self.text = text; self.box = box }
    }

    static func boxText(_ b: TutorBox) -> String { "[" + [b.x, b.y, b.w, b.h].map { String(Int(TutorSteps.jsRound($0))) }.joined(separator: ", ") + "]" }

    /// The text of one iPad turn. view: the part of the board on screen, in the turn's coordinates, when its picture goes with the turn.
    public static func iPadTurn(words: String, board: String = "", view: TutorBox? = nil, handwriting: [Seen] = [], typed: [Seen] = [], recap: String = "") -> String {
        var parts: [String] = []
        if !recap.isEmpty { parts.append(recap) }
        if !board.isEmpty { parts.append("<board>\nAlready on the board (yours, from earlier turns):\n" + String(board.prefix(4000)) + "\n</board>") }
        if let v = view {
            parts.append("<view>The picture is their board from x \(Int(TutorSteps.jsRound(v.x))) to \(Int(TutorSteps.jsRound(v.maxX))) and y \(Int(TutorSteps.jsRound(v.y))) to \(Int(TutorSteps.jsRound(v.maxY))) in this turn's coordinates.</view>")
            if !handwriting.isEmpty {
                parts.append("<handwriting>\nTheir handwriting, as read by the iPad (it may misread a word):\n"
                             + handwriting.prefix(60).map { "\"\($0.text)\" at \(boxText($0.box))" }.joined(separator: "\n") + "\n</handwriting>")
            }
            if !typed.isEmpty {
                parts.append("<typed>\nTheir typed text:\n" + typed.prefix(30).map { "\"\(String($0.text.prefix(300)))\" at \(boxText($0.box))" }.joined(separator: "\n") + "\n</typed>")
            }
        } else {
            parts.append("<view>No picture of the board this turn.</view>")
        }
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        parts.append(!w.isEmpty ? "They said: " + w : view != nil ? "They held the button but said nothing you could hear. Say briefly what you see on their board that you could help with." : "They said nothing.")
        return parts.joined(separator: "\n\n")
    }

    /// Where a turn's (0, 0) goes on the board: beside the writing in view (to its right when there is room on screen, else below it),
    /// or near the top-left of the view on an empty one. visible: the board on screen; content: the boxes of what is on the board.
    public static func frame(visible v: TutorBox, content: [TutorBox], need: Double = 360, gap: Double = 48) -> [Double] {
        let inView = content.filter { $0.maxX > v.x && $0.x < v.maxX && $0.maxY > v.y && $0.y < v.maxY }
        guard var u = inView.first else { return [TutorSteps.jsRound(v.x + 40), TutorSteps.jsRound(v.y + 40)] }
        for b in inView.dropFirst() { u = u.union(b) }
        if v.maxX - u.maxX - gap >= need { return [TutorSteps.jsRound(u.maxX + gap), TutorSteps.jsRound(max(u.y, v.y + 20))] }
        return [TutorSteps.jsRound(max(u.x, v.x + 20)), TutorSteps.jsRound(u.maxY + gap)]
    }
}

extension JSONValue {
    /// JSON.stringify(value, null, indent): each array entry and object key on its own line, empty ones as [] and {}.
    public func indented(_ indent: Int = 1, level: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent * (level + 1)), end = String(repeating: " ", count: indent * level)
        switch self {
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { pad + $0.indented(indent, level: level + 1) }.joined(separator: ",\n") + "\n" + end + "]"
        case .object(let o):
            if o.isEmpty { return "{}" }
            return "{\n" + o.map { kv -> String in
                var k = ""; JSONValue.quote(kv.0, &k)
                return pad + k + ": " + kv.1.indented(indent, level: level + 1)
            }.joined(separator: ",\n") + "\n" + end + "}"
        default: return text
        }
    }
}
