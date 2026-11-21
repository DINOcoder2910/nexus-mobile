import Foundation

/// Recordings: an in-person meeting, a class, a call or a screen, recorded on one device, turned into words on that device, then read
/// by Claude, who prepares a title, a subject, a summary, tasks and dates. Nothing is filed until the user accepts it (review first,
/// Nov 21). The format is the same on every device (nexus docs/data-format.md "Recordings"):
///
///     recordings/<YYYY-MM-DD HHMM> <Kind>/   one recording, named once when it starts and never renamed
///       recording.json    {"format": "nexus-recordings/1", "id", "kind", "title", "started", "duration", "device", "state",
///                          "problem"?, "audio": "audio.m4a", "video"?: "video.mov", "language"?, "subject"?,
///                          "pictures": [{"file": "pictures/0012.jpg", "at": 12.3}]}
///       audio.m4a         AAC mono (about 14 MB an hour); a filmed class also has video.mov (kept out of the GitHub backup)
///       pictures/         photos snapped while recording, and the important moments of a video, each pinned to its time
///       transcript.json   {"format": "nexus-transcript/1", "language", "engine", "segments": [{"start", "end", "text", "speaker"?}]}
///       transcript.md     the same words to read, a paragraph per stretch with its time
///       proposal.json     what Claude prepared (Recordings.Proposal), waiting for review
///       summary.md        written when the user accepts: the summary, the class notes, the people, a link to the transcript
///       filed.json        what accepting added (task ids), so it can be undone
///
/// `state` in recording.json is only the recorder's part (recording, transcribing, failed, done); whether it waits for Claude, for
/// review or is filed comes from which files exist (`Recordings.status`), so two devices never write the same file at once.
public enum Recordings {
    public static let dir = "recordings"
    public static let format = "nexus-recordings/1"
    public static let transcriptFormat = "nexus-transcript/1"
    public static let metaFile = "recording.json"
    public static let audioFile = "audio.m4a"
    public static let videoFile = "video.mov"
    public static let transcriptFile = "transcript.json"
    public static let transcriptText = "transcript.md"
    public static let proposalFile = "proposal.json"
    public static let summaryFile = "summary.md"
    public static let filedFile = "filed.json"
    public static let picturesDir = "pictures"
    /// recordings/.gitignore: videos sync to every device through the hub, but stay out of the data folder's GitHub backup.
    public static let gitignorePath = "recordings/.gitignore"
    public static let gitignore = "# Nexus: class videos sync to every device but are too big for the GitHub backup.\n*.mov\n*.mp4\n*.m4v\n"
    /// A class's teaching notes in its subject's folder, which every accepted class adds to (the tutor reads it).
    public static let teachingFile = "teaching.md"

    public enum Kind: String, CaseIterable, Sendable {
        case meeting, call, screen
        /// A lesson at school ("class" in the file).
        case lesson = "class"
        /// The word in a folder name and a heading.
        public var word: String {
            switch self {
            case .meeting: return "Meeting"
            case .lesson: return "Class"
            case .call: return "Call"
            case .screen: return "Screen"
            }
        }
        public var icon: String {
            switch self {
            case .meeting: return "person.2.wave.2"
            case .lesson: return "graduationcap"
            case .call: return "video"
            case .screen: return "rectangle.on.rectangle"
            }
        }
    }

    /// Where a recording is: the recorder's states, then what the files say.
    public enum Status: String, Sendable {
        case recording, transcribing, failed, preparing, review, filed
        public var label: String {
            switch self {
            case .recording: return "Recording"
            case .transcribing: return "Turning into words"
            case .failed: return "Needs a look"
            case .preparing: return "Claude is reading it"
            case .review: return "Ready to review"
            case .filed: return "Filed"
            }
        }
    }

    // MARK: recording.json

    public struct Picture: Equatable, Sendable {
        public var file: String
        public var at: Double
        public var note: String?
        public init(file: String, at: Double, note: String? = nil) { self.file = file; self.at = at; self.note = note }
    }

    public struct Meta: Equatable {
        public var id: String
        public var kind: Kind
        public var title: String
        public var started: String
        public var duration: Double
        public var device: String
        /// recording | transcribing | failed | done
        public var state: String
        public var problem: String?
        public var audio: String
        public var video: String?
        public var language: String?
        public var subject: String?
        public var pictures: [Picture]
        /// The file as read: fields this app doesn't know are kept when it is written again.
        public var raw: JSONValue?

        public init(id: String, kind: Kind, started: Date, device: String) {
            self.id = id; self.kind = kind; title = kind.word; self.started = Recordings.iso(started); duration = 0
            self.device = device; state = "recording"; audio = Recordings.audioFile; pictures = []
        }

        public init?(json v: JSONValue) {
            guard v["format"]?.string == Recordings.format, let id = v["id"]?.string, !id.isEmpty else { return nil }
            self.id = id
            kind = Kind(rawValue: v["kind"]?.string ?? "") ?? .meeting
            title = v["title"]?.string ?? kind.word
            started = v["started"]?.string ?? ""
            duration = v["duration"]?.number ?? 0
            device = v["device"]?.string ?? ""
            state = v["state"]?.string ?? "done"
            problem = v["problem"]?.string
            audio = v["audio"]?.string ?? Recordings.audioFile
            video = v["video"]?.string
            language = v["language"]?.string
            subject = v["subject"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            pictures = (v["pictures"]?.array ?? []).compactMap { p in
                guard let f = p["file"]?.string else { return nil }
                return Picture(file: f, at: p["at"]?.number ?? 0, note: p["note"]?.string)
            }
            raw = v
        }

        public var json: JSONValue {
            var o: JSONValue = raw ?? .object([])
            o = o.setting("format", .string(Recordings.format)).setting("id", .string(id)).setting("kind", .string(kind.rawValue))
                .setting("title", .string(title)).setting("started", .string(started)).setting("duration", .number(Recordings.r1(duration)))
                .setting("device", .string(device)).setting("state", .string(state)).setting("problem", problem.map { .string($0) })
                .setting("audio", .string(audio)).setting("video", video.map { .string($0) }).setting("language", language.map { .string($0) })
                .setting("subject", subject.map { .string($0) })
            let pics: [JSONValue] = pictures.map { p in
                var e: [(String, JSONValue)] = [("file", .string(p.file)), ("at", .number(Recordings.r1(p.at)))]
                if let n = p.note { e.append(("note", .string(n))) }
                return .object(e)
            }
            return o.setting("pictures", .array(pics))
        }

        public var startedDate: Date? { Recordings.date(started) }
    }

    // MARK: folders and names

    /// "2026-11-21 1430 Meeting", with " 2", " 3" while `taken` says the name is used.
    public static func folderName(started: Date, kind: Kind, taken: (String) -> Bool = { _ in false }, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd HHmm"
        let base = f.string(from: started) + " " + kind.word
        if !taken(base) { return base }
        var n = 2
        while taken(base + " \(n)") { n += 1 }
        return base + " \(n)"
    }

    /// A new id: 8 base-36 characters.
    public static func newId() -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        return String((0..<8).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    /// A picture's file for a moment: "pictures/0754.jpg" (seconds in), "pictures/0754-2.jpg" when that second is taken.
    public static func pictureFile(at: Double, taken: Set<String>, ext: String = "jpg") -> String {
        let s = String(format: "%04d", Int(max(0, at)))
        var name = "\(picturesDir)/\(s).\(ext)"
        var n = 2
        while taken.contains(name) { name = "\(picturesDir)/\(s)-\(n).\(ext)"; n += 1 }
        return name
    }

    /// The state from the recorder's part and the files present.
    public static func status(_ m: Meta, transcript: Bool, proposal: Bool, filed: Bool) -> Status {
        switch m.state {
        case "recording": return .recording
        case "transcribing": return .transcribing
        case "failed": return .failed
        default: break
        }
        if filed { return .filed }
        if proposal { return .review }
        return transcript ? .preparing : .failed
    }

    /// One recording found in the data folder.
    public struct Entry: Equatable, Identifiable {
        /// "recordings/2026-11-21 1430 Meeting"
        public var path: String
        public var meta: Meta
        public var status: Status
        public var id: String { path }
    }

    /// Every recording under `root/recordings`, newest first.
    public static func list(_ root: URL, fm: FileManager = .default) -> [Entry] {
        let base = root.appendingPathComponent(dir)
        guard let names = try? fm.contentsOfDirectory(atPath: base.path) else { return [] }
        var out: [Entry] = []
        for name in names where !name.hasPrefix(".") {
            let folder = base.appendingPathComponent(name)
            guard let data = fm.contents(atPath: folder.appendingPathComponent(metaFile).path),
                  let text = String(data: data, encoding: .utf8), let v = try? JSONValue.parse(text), let m = Meta(json: v) else { continue }
            let has = { (f: String) in fm.fileExists(atPath: folder.appendingPathComponent(f).path) }
            out.append(Entry(path: dir + "/" + name, meta: m,
                             status: status(m, transcript: has(transcriptFile), proposal: has(proposalFile), filed: has(filedFile))))
        }
        return out.sorted { ($0.meta.started, $0.path) > ($1.meta.started, $1.path) }
    }

    // MARK: the transcript

    public struct Segment: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var text: String
        public var speaker: String?
        public init(start: Double, end: Double, text: String, speaker: String? = nil) {
            self.start = start; self.end = end; self.text = text; self.speaker = speaker
        }
    }

    public struct Transcript: Equatable, Sendable {
        public var language: String
        public var engine: String
        public var segments: [Segment]
        public init(language: String, engine: String, segments: [Segment]) { self.language = language; self.engine = engine; self.segments = segments }

        public init?(json v: JSONValue) {
            guard v["format"]?.string == Recordings.transcriptFormat else { return nil }
            language = v["language"]?.string ?? ""
            engine = v["engine"]?.string ?? ""
            segments = (v["segments"]?.array ?? []).compactMap { s in
                guard let t = s["text"]?.string else { return nil }
                return Segment(start: s["start"]?.number ?? 0, end: s["end"]?.number ?? 0, text: t, speaker: s["speaker"]?.string)
            }
        }

        public var json: JSONValue {
            .object([("format", .string(Recordings.transcriptFormat)), ("language", .string(language)), ("engine", .string(engine)),
                     ("segments", .array(segments.map { s in
                        var e: [(String, JSONValue)] = [("start", .number(Recordings.r1(s.start))), ("end", .number(Recordings.r1(s.end))), ("text", .string(s.text))]
                        if let sp = s.speaker { e.append(("speaker", .string(sp))) }
                        return .object(e)
                     }))])
        }

        public var words: Int { segments.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count } }

        /// Paragraphs: segments joined until a pause of `gap` seconds, a change of speaker, or about `maxWords` words.
        public func paragraphs(gap: Double = 2.5, maxWords: Int = 90) -> [Segment] {
            var out: [Segment] = []
            for s in segments {
                let t = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                if var last = out.last, s.start - last.end < gap, last.speaker == s.speaker,
                   last.text.split(separator: " ").count < maxWords {
                    last.text += " " + t
                    last.end = max(last.end, s.end)
                    out[out.count - 1] = last
                } else {
                    out.append(Segment(start: s.start, end: s.end, text: t, speaker: s.speaker))
                }
            }
            return out
        }

        /// transcript.md: a heading, then each paragraph with its time ("**12:04** words").
        public func markdown(title: String, names: [String: String] = [:]) -> String {
            var lines = ["# \(title): transcript", ""]
            for p in paragraphs() {
                let who = p.speaker.map { names[$0] ?? $0 }.map { " \($0):" } ?? ""
                lines.append("**\(Recordings.clock(p.start))**\(who) \(p.text)")
                lines.append("")
            }
            return lines.joined(separator: "\n")
        }

        /// What Claude reads: a line per paragraph, "[12:04] S1: words".
        public var forClaude: String {
            paragraphs().map { p in "[\(Recordings.clock(p.start))]" + (p.speaker.map { " \($0):" } ?? "") + " " + p.text }.joined(separator: "\n")
        }
    }

    // MARK: what Claude prepares

    public struct ProposedTask: Equatable, Sendable {
        public var title: String
        public var due: String?
        /// Seconds into the recording where it was said.
        public var at: Double?
        public var note: String?
        /// The user may untick it before accepting.
        public var take: Bool
        public init(title: String, due: String? = nil, at: Double? = nil, note: String? = nil, take: Bool = true) {
            self.title = title; self.due = due; self.at = at; self.note = note; self.take = take
        }
    }

    public struct ProposedDate: Equatable, Sendable {
        public var what: String
        /// YYYY-MM-DD
        public var date: String
        /// HH:MM, nil for all day
        public var time: String?
        public var at: Double?
        public var take: Bool
        public init(what: String, date: String, time: String? = nil, at: Double? = nil, take: Bool = true) {
            self.what = what; self.date = date; self.time = time; self.at = at; self.take = take
        }
    }

    /// A class's notes: what was taught and how.
    public struct ClassNotes: Equatable, Sendable {
        /// The Study unit it fits ("R3.2"), when Claude can tell.
        public var unit: String?
        /// Markdown: what was taught, in order.
        public var taught: String
        /// Worked examples and questions used, one each.
        public var examples: [String]
        /// Markdown: how the teacher explains it (methods, words they use, what they stress, mistakes they warn about).
        public var teaching: String
        public init(unit: String? = nil, taught: String, examples: [String] = [], teaching: String) {
            self.unit = unit; self.taught = taught; self.examples = examples; self.teaching = teaching
        }
    }

    public struct Proposal: Equatable, Sendable {
        public var title: String
        /// A workstream id, nil for the Inbox.
        public var subject: String?
        public var people: [String]
        /// Speaker labels in the transcript ("S1") -> who they are ("you", "Ms K").
        public var speakers: [String: String]
        /// Markdown.
        public var summary: String
        public var decisions: [String]
        public var tasks: [ProposedTask]
        public var dates: [ProposedDate]
        public var classNotes: ClassNotes?
        public var model: String?
        public var made: String?
        /// Take the subject's teaching note too (a class only).
        public var takeTeaching: Bool

        public init(title: String, subject: String? = nil, people: [String] = [], speakers: [String: String] = [:], summary: String,
                    decisions: [String] = [], tasks: [ProposedTask] = [], dates: [ProposedDate] = [], classNotes: ClassNotes? = nil,
                    model: String? = nil, made: String? = nil, takeTeaching: Bool = true) {
            self.title = title; self.subject = subject; self.people = people; self.speakers = speakers; self.summary = summary
            self.decisions = decisions; self.tasks = tasks; self.dates = dates; self.classNotes = classNotes
            self.model = model; self.made = made; self.takeTeaching = takeTeaching
        }

        /// Reads what Claude answered (or proposal.json). `subjects`: the workstream ids it may pick from; anything else becomes the Inbox.
        public init?(json v: JSONValue, subjects: Set<String>? = nil) {
            guard let t = v["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
            title = String(t.prefix(80))
            let s = v["subject"]?.string?.trimmingCharacters(in: .whitespaces)
            subject = s.flatMap { $0.isEmpty || $0 == "inbox" ? nil : $0 }.flatMap { subjects == nil || subjects!.contains($0) ? $0 : nil }
            people = (v["people"]?.array ?? []).compactMap { $0.string }.filter { !$0.isEmpty }
            var sp: [String: String] = [:]
            for (k, n) in v["speakers"]?.object ?? [] { if let n = n.string, !n.isEmpty { sp[k] = n } }
            speakers = sp
            summary = v["summary"]?.string ?? ""
            decisions = (v["decisions"]?.array ?? []).compactMap { $0.string }.filter { !$0.isEmpty }
            tasks = (v["tasks"]?.array ?? []).compactMap { e in
                guard let t = e["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                return ProposedTask(title: t, due: Recordings.day(e["due"]?.string), at: e["at"].flatMap(Recordings.seconds), note: e["note"]?.string,
                                    take: e["take"]?.bool ?? true)
            }
            dates = (v["dates"]?.array ?? []).compactMap { e in
                guard let w = e["what"]?.string, !w.isEmpty, let d = Recordings.day(e["date"]?.string) else { return nil }
                let tm = e["time"]?.string.flatMap { $0.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil ? $0 : nil }
                return ProposedDate(what: w, date: d, time: tm, at: e["at"].flatMap(Recordings.seconds), take: e["take"]?.bool ?? true)
            }
            if let c = v["class"], case .object = c, let taught = c["taught"]?.string, !taught.isEmpty {
                classNotes = ClassNotes(unit: c["unit"]?.string.flatMap { $0.isEmpty ? nil : $0 }, taught: taught,
                                        examples: (c["examples"]?.array ?? []).compactMap { $0.string }, teaching: c["teaching"]?.string ?? "")
            } else {
                classNotes = nil
            }
            model = v["model"]?.string
            made = v["made"]?.string
            takeTeaching = v["takeTeaching"]?.bool ?? true
        }

        public var json: JSONValue {
            var o: [(String, JSONValue)] = [("title", .string(title)), ("subject", subject.map { .string($0) } ?? .null),
                                            ("people", .array(people.map { .string($0) })),
                                            ("speakers", .object(speakers.sorted { $0.key < $1.key }.map { ($0.key, .string($0.value)) })),
                                            ("summary", .string(summary)), ("decisions", .array(decisions.map { .string($0) }))]
            o.append(("tasks", .array(tasks.map { t in
                var e: [(String, JSONValue)] = [("title", .string(t.title))]
                if let d = t.due { e.append(("due", .string(d))) }
                if let a = t.at { e.append(("at", .number(Recordings.r1(a)))) }
                if let n = t.note { e.append(("note", .string(n))) }
                if !t.take { e.append(("take", .bool(false))) }
                return .object(e)
            })))
            o.append(("dates", .array(dates.map { d in
                var e: [(String, JSONValue)] = [("what", .string(d.what)), ("date", .string(d.date))]
                if let t = d.time { e.append(("time", .string(t))) }
                if let a = d.at { e.append(("at", .number(Recordings.r1(a)))) }
                if !d.take { e.append(("take", .bool(false))) }
                return .object(e)
            })))
            if let c = classNotes {
                var e: [(String, JSONValue)] = []
                if let u = c.unit { e.append(("unit", .string(u))) }
                e += [("taught", .string(c.taught)), ("examples", .array(c.examples.map { .string($0) })), ("teaching", .string(c.teaching))]
                o.append(("class", .object(e)))
                if !takeTeaching { o.append(("takeTeaching", .bool(false))) }
            }
            if let m = model { o.append(("model", .string(m))) }
            if let m = made { o.append(("made", .string(m))) }
            return .object(o)
        }
    }

    // MARK: asking Claude

    /// A subject Claude may file under.
    public struct Subject: Equatable, Sendable {
        public var id: String
        public var name: String
        public var kind: String?
        public init(id: String, name: String, kind: String? = nil) { self.id = id; self.name = name; self.kind = kind }
    }

    public static let system = """
    You read a recording the user made in Nexus, their personal planner and notes app, and prepare it to be filed. The user reviews \
    what you prepare before anything is saved, so be useful and specific, and leave out what you are unsure of rather than guess.

    The recording is one of: an in-person meeting, a class (a lesson at school), a video call, or a screen recording. You get a \
    transcript made by speech recognition on the user's device: lines of "[mm:ss] words", sometimes with a speaker label ("S1:"). \
    The recognition makes mistakes: read past misheard words, and correct names and subject terms from context. Speakers are often \
    not marked; tell them apart from what is said where you can. "You" is the user, who made the recording.

    Answer with ONE JSON object and nothing else, with these keys:
    - "title": a short title, at most 8 words ("Meeting with Ms K about the EE", "Redox: half-equations").
    - "subject": the id of the subject (from the list you are given) this belongs to, or null when none fits (it then goes to the Inbox).
    - "people": the people who took part or were talked about, by name or role.
    - "speakers": an object from each speaker label in the transcript to who it is ("S1": "Ms K"); {} when there are none.
    - "summary": markdown, a few short paragraphs or bullets: what it was about and what was said that matters later.
    - "decisions": what was decided or agreed, one short line each.
    - "tasks": the user's own action items only (not other people's), each {"title", "due"?: "YYYY-MM-DD", "at": "mm:ss" where it was \
    said, "note"?: one line of context}. Titles start with a verb. A date said as "Friday" or "next week" is worked out from the \
    recording's date. No tasks for a class unless homework or a test was set.
    - "dates": events and deadlines mentioned (a test, a meeting, a hand-in), each {"what", "date": "YYYY-MM-DD", "time"?: "HH:MM", "at": "mm:ss"}.
    - "class": only for a class, else null: {"unit"?: the Study unit or topic code if you can tell, "taught": markdown of what was \
    taught in order, "examples": the worked examples and questions used (one string each, with the numbers), "teaching": markdown \
    on HOW the teacher teaches it: their method and steps, the words and shortcuts they use, what they stress or say comes up in \
    tests, common mistakes they warn about. A tutor will read "teaching" to explain things the way this class does.}
    Pictures, when given, are photos or screenshots the user took at those moments (the board, slides): use what they show.
    """

    /// The user's message: what kind it is, when, the subjects, the calendar event at that time, then the transcript.
    public static func prompt(meta: Meta, transcript: Transcript, subjects: [Subject], event: String?, today: String, pictures: [Picture] = []) -> String {
        var lines: [String] = []
        let when = meta.startedDate.map { localStamp($0) } ?? meta.started
        lines.append("Recording: a \(meta.kind == .screen ? "screen recording" : meta.kind == .call ? "video call" : meta.kind == .lesson ? "class" : "in-person meeting"), started \(when), \(clock(meta.duration)) long.")
        lines.append("Today is \(today).")
        if let e = event, !e.isEmpty { lines.append("The calendar had this at that time: \(e).") }
        if !subjects.isEmpty {
            lines.append("")
            lines.append("Subjects (id: name):")
            for s in subjects { lines.append("- \(s.id): \(s.name)" + (s.kind.map { " (\($0))" } ?? "")) }
        }
        if !pictures.isEmpty {
            lines.append("")
            lines.append("Pictures, in order: " + pictures.map { clock($0.at) }.joined(separator: ", ") + ".")
        }
        lines.append("")
        lines.append("Transcript:")
        lines.append(transcript.forClaude.isEmpty ? "(nothing was heard)" : transcript.forClaude)
        return lines.joined(separator: "\n")
    }

    /// The JSON object in Claude's answer (bare, or in a ``` fence, with words around it).
    public static func parseReply(_ text: String, subjects: Set<String>?) -> Proposal? {
        var t = text
        if let f = t.range(of: "```") {
            var rest = t[f.upperBound...]
            if let nl = rest.firstIndex(of: "\n") { rest = rest[rest.index(after: nl)...] }
            if let end = rest.range(of: "```") { t = String(rest[..<end.lowerBound]) }
        }
        guard let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b, let v = try? JSONValue.parse(String(t[a...b])) else { return nil }
        return Proposal(json: v, subjects: subjects)
    }

    // MARK: accepting

    /// summary.md, written when the user accepts.
    public static func summaryMarkdown(meta: Meta, proposal p: Proposal, subjectName: String?) -> String {
        var l = ["# \(p.title)", ""]
        let when = meta.startedDate.map { localStamp($0) } ?? meta.started
        var facts = ["\(meta.kind.word), \(when), \(clock(meta.duration))"]
        if let s = subjectName { facts.append(s) }
        l.append(facts.joined(separator: " · "))
        if !p.people.isEmpty { l += ["", "With: " + p.people.joined(separator: ", ")] }
        l += ["", "## Summary", "", p.summary.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !p.decisions.isEmpty { l += ["", "## Decided", ""] + p.decisions.map { "- \($0)" } }
        let tasks = p.tasks.filter(\.take)
        if !tasks.isEmpty {
            l += ["", "## To do", ""] + tasks.map { t in "- [ ] \(t.title)" + (t.due.map { " (by \($0))" } ?? "") + (t.at.map { " · \(clock($0))" } ?? "") }
        }
        if !p.dates.isEmpty {
            l += ["", "## Dates", ""] + p.dates.map { d in "- \(d.date)" + (d.time.map { " \($0)" } ?? "") + ": \(d.what)" }
        }
        if let c = p.classNotes {
            l += ["", "## What was taught" + (c.unit.map { " (\($0))" } ?? ""), "", c.taught.trimmingCharacters(in: .whitespacesAndNewlines)]
            if !c.examples.isEmpty { l += ["", "## Examples", ""] + c.examples.map { "- \($0)" } }
            if !c.teaching.isEmpty { l += ["", "## How it was taught", "", c.teaching.trimmingCharacters(in: .whitespacesAndNewlines)] }
        }
        if !meta.pictures.isEmpty {
            l += ["", "## Pictures", ""] + meta.pictures.map { "- \(clock($0.at)): ![](\($0.file))" }
        }
        l += ["", "[The full transcript](\(transcriptText))", ""]
        return l.joined(separator: "\n")
    }

    /// The task's note: where it came from.
    public static func taskNote(_ t: ProposedTask, title: String, path: String) -> String {
        var n = "From the recording “\(title)”" + (t.at.map { " at \(clock($0))" } ?? "") + " (\(path))."
        if let x = t.note, !x.isEmpty { n = x + "\n" + n }
        return n
    }

    /// The subject's teaching.md with this class added at the top (newest first), under its heading.
    public static func addTeaching(_ existing: String?, subjectName: String, date: String, title: String, path: String, notes c: ClassNotes) -> String {
        let head = "# How \(subjectName) is taught\n\nWhat each recorded class showed about how it is taught, newest first. The tutor reads this to explain things the way your class does.\n"
        var body = (existing ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { body = head.trimmingCharacters(in: .whitespacesAndNewlines) }
        var entry = ["## \(date): \(title)" + (c.unit.map { " (\($0))" } ?? ""), ""]
        entry.append(c.teaching.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "(nothing noted)" : c.teaching.trimmingCharacters(in: .whitespacesAndNewlines))
        if !c.examples.isEmpty { entry += ["", "Examples used:"] + c.examples.map { "- \($0)" } }
        entry += ["", "[The class](\(path)/\(summaryFile))"]
        // the entry goes after the head (the part before the first "## ")
        if let r = body.range(of: "\n## ") {
            return String(body[..<r.lowerBound]) + "\n\n" + entry.joined(separator: "\n") + "\n" + String(body[r.lowerBound...]) + "\n"
        }
        return body + "\n\n" + entry.joined(separator: "\n") + "\n"
    }

    /// filed.json: what accepting added.
    public struct Filed: Equatable, Sendable {
        public var accepted: String
        public var device: String
        public var subject: String?
        /// The task ids added, and the file each went into.
        public var tasks: [(id: String, file: String)]
        /// The teaching.md written to, and its text before (for Undo).
        public var teaching: String?
        public var teachingBefore: String?

        public init(accepted: String, device: String, subject: String?, tasks: [(id: String, file: String)] = [], teaching: String? = nil, teachingBefore: String? = nil) {
            self.accepted = accepted; self.device = device; self.subject = subject; self.tasks = tasks
            self.teaching = teaching; self.teachingBefore = teachingBefore
        }

        public static func == (a: Filed, b: Filed) -> Bool {
            a.accepted == b.accepted && a.device == b.device && a.subject == b.subject && a.teaching == b.teaching
                && a.teachingBefore == b.teachingBefore && a.tasks.map(\.id) == b.tasks.map(\.id) && a.tasks.map(\.file) == b.tasks.map(\.file)
        }

        public init?(json v: JSONValue) {
            guard let a = v["accepted"]?.string else { return nil }
            accepted = a; device = v["device"]?.string ?? ""; subject = v["subject"]?.string
            tasks = (v["tasks"]?.array ?? []).compactMap { t in
                guard let id = t["id"]?.string, let f = t["file"]?.string else { return nil }
                return (id: id, file: f)
            }
            teaching = v["teaching"]?.string
            teachingBefore = v["teachingBefore"]?.string
        }

        public var json: JSONValue {
            var o: [(String, JSONValue)] = [("accepted", .string(accepted)), ("device", .string(device)), ("subject", subject.map { .string($0) } ?? .null),
                                            ("tasks", .array(tasks.map { .object([("id", .string($0.id)), ("file", .string($0.file))]) }))]
            if let t = teaching { o.append(("teaching", .string(t))) }
            if let b = teachingBefore { o.append(("teachingBefore", .string(b))) }
            return .object(o)
        }
    }

    // MARK: helpers

    static func r1(_ x: Double) -> Double { (x * 10).rounded() / 10 }

    /// 75 -> "1:15", 3725 -> "1:02:05".
    public static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// "12:04", "1:02:05", or a number -> seconds.
    static func seconds(_ v: JSONValue) -> Double? {
        if let n = v.number { return n >= 0 ? n : nil }
        guard let s = v.string else { return nil }
        let parts = s.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    /// "YYYY-MM-DD" or nil.
    static func day(_ s: String?) -> String? {
        guard let s, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return s
    }

    /// "2026-11-21T09:00:00.000Z", as JavaScript's toISOString.
    public static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }

    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    /// "Sat 21 Nov 2026, 14:30" in the device's time zone.
    public static func localStamp(_ d: Date, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB"); f.timeZone = zone; f.dateFormat = "EEE d MMM yyyy, HH:mm"
        return f.string(from: d)
    }

    /// YYYY-MM-DD in the device's time zone.
    public static func localDay(_ d: Date, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
