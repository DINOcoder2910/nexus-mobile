import Foundation

/// Spanish › Oral practice on the iPhone and iPad: the IB ab initio individual oral's files in `<workstream>/study/spanish/oral/`, the
/// same files the laptop's Oral page reads and writes (nexus renderer/src/spanishoral.js, the new app's backend/src/oral.rs). The phone
/// shows the past orals and their marks (a teacher's or tutor's under `given`, Claude's under `marks`), one oral whole, and the listening
/// test's results; it adds a recording (made on the phone, or a file) and records the listening test's lines. Hearing a recording
/// needs the laptop's voice models (Whisper and the two ears, on its graphics card), so what the phone adds waits there: an added
/// oral's oral.yaml says `waiting: hear`, a listening test take sits in `listening-test/phone/<stamp>/`, and the laptop hears them on
/// its Oral page, writing the oral and the result back as it does its own.
/// No UIKit; golden cases from the laptop's JS in SpanishOralGolden.swift (tools/spanish-golden/oral.mjs).
public enum SpanishOral {
    public static let dir = "study/spanish/oral"
    public enum P {
        public static let orals = dir + "/orals"
        public static let images = dir + "/images"
        public static let imagesFile = dir + "/images.yaml"
        public static let settings = dir + "/settings.yaml"
        public static let listening = dir + "/listening-test"
        /// Listening test takes recorded on a phone or iPad, waiting for the laptop's ears.
        public static let takes = dir + "/listening-test/phone"
        public static func oral(_ id: String) -> String { "\(orals)/\(id)" }
    }

    // MARK: themes

    public struct Theme: Equatable, Sendable { public let id, es, en: String; public let topics: [String] }
    public static let themes: [Theme] = [
        Theme(id: "identidades", es: "Identidades", en: "Identities", topics: ["Atributos personales", "Relaciones personales", "Comer y beber", "Bienestar físico"]),
        Theme(id: "experiencias", es: "Experiencias", en: "Experiences", topics: ["Rutina diaria", "Ocio", "Vacaciones", "Festivales y celebraciones"]),
        Theme(id: "ingenio", es: "Ingenio humano", en: "Human ingenuity", topics: ["Transporte", "Entretenimiento", "Medios de comunicación", "Tecnología"]),
        Theme(id: "organizacion", es: "Organización social", en: "Social organization", topics: ["Problemas sociales", "Educación", "El mundo laboral", "El barrio"]),
        Theme(id: "planeta", es: "Compartir el planeta", en: "Sharing the planet", topics: ["El clima", "La geografía física", "El medio ambiente", "Problemas globales"]),
    ]
    public static func themeName(_ id: String) -> String { themes.first { $0.id == id }?.es ?? id }

    static func fold(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The closest theme id for whatever was written ("Ingenio humano", "human ingenuity", "tecnologia"), or "".
    public static func toTheme(_ raw: String) -> String {
        let s = fold(raw)
        if s.isEmpty { return "" }
        for t in themes where s == t.id || s == fold(t.es) || s == fold(t.en) { return t.id }
        for t in themes where t.topics.contains(where: { fold($0) == s }) { return t.id }
        let words = [("identidad", "identidades"), ("identit", "identidades"), ("experien", "experiencias"), ("ingenio", "ingenio"), ("ingenuity", "ingenio"),
                     ("organiza", "organizacion"), ("social", "organizacion"), ("planet", "planeta"), ("compartir", "planeta")]
        for (w, id) in words where s.contains(w) { return id }
        return ""
    }

    // MARK: settings (only what the phone shows: who marks and who you practise with)

    public struct Settings: Equatable, Sendable {
        public var teacher = "Miss K"
        public var tutor = "my tutor"
        public init() {}
    }

    public static func parseSettings(_ text: String?) -> Settings {
        var s = Settings()
        guard let text, let o = try? YValue.parse(text) else { return s }
        if case .string(let t)? = o["teacher"], !t.trimmed.isEmpty { s.teacher = t.trimmed }
        if case .string(let t)? = o["tutor"], !t.trimmed.isEmpty { s.tutor = t.trimmed }
        return s
    }

    // MARK: one oral (orals/<id>/oral.yaml)

    public static let critMax: [(key: String, max: Int)] = [("A", 12), ("B1", 6), ("B2", 6), ("C", 6)]
    public static let critNames = ["A": "Language", "B1": "Message: the picture", "B2": "Message: conversation", "C": "Interactive skills"]

    public struct Given: Equatable, Sendable {
        public var crit: [String: Double] = [:]
        public var total: Double?
        public var max: Double?
        public var comments = ""
        public var points: [String] = []
        public init() {}
    }

    public struct Turn: Equatable, Sendable { public var start, end: Double; public var who, text: String }
    public struct Segment: Equatable, Sendable { public var part: Int; public var file: String; public var ms: Double; public var q, heard, said: String }

    public struct Oral: Equatable, Sendable {
        public var id = ""
        /// full | conversation | session
        public var kind = "full"
        /// practice | teacher | tutor
        public var by = "practice"
        public var title = ""
        public var recording = ""
        public var started = ""
        public var image = ""
        public var theme = ""
        public var otherTheme = ""
        public var notes = ""
        public var given: Given?
        /// Claude's marks: A, B1, B2, C, total.
        public var marks: [String: Double]?
        public var summary = ""
        public var segments: [Segment] = []
        public var turns: [Turn] = []
        /// What the laptop's ears found, as written (talk, diffs, sounds, delivery, ears).
        public var listening: YValue?
        /// "hear" while a recording added on a phone waits for the laptop; "" once heard.
        public var waiting = ""
        /// The device that added it ("iPhone", "iPad"), when not the laptop.
        public var from = ""
        public init() {}
    }

    static func num(_ v: YValue?) -> Double? {
        guard let v else { return nil }
        if case .string(let s) = v, s.trimmed.isEmpty { return nil }
        guard let n = v.number, n.isFinite else { return nil }
        return n
    }

    static func readGiven(_ g: YValue?) -> Given? {
        guard let g, g.map != nil else { return nil }
        var out = Given()
        var tot = 0.0, max = 0, any = false
        for (k, m) in critMax { if let x = num(g[k]) { out.crit[k] = x; tot += x; max += m; any = true } }
        out.total = num(g["total"]) ?? (any ? tot : nil)
        out.max = num(g["max"]) ?? (any ? Double(max) : nil)
        out.comments = (g["comments"]?.str ?? "").trimmed
        out.points = (g["points"]?.list ?? []).map(\.str).filter { !$0.isEmpty }
        return out
    }

    public static func parseOral(_ text: String, id: String = "") -> Oral? {
        guard let o = try? YValue.parse(text), o.map != nil else { return nil }
        func s(_ k: String) -> String { o[k]?.str ?? "" }
        var r = Oral()
        r.id = s("id").isEmpty ? id : s("id")
        r.kind = ["full", "conversation", "session"].contains(s("kind")) ? s("kind") : "full"
        r.by = ["teacher", "tutor"].contains(s("by")) ? s("by") : "practice"
        r.title = s("title"); r.recording = s("recording"); r.started = s("started"); r.image = s("image")
        r.theme = toTheme(s("theme")); r.otherTheme = toTheme(s("otherTheme")); r.notes = s("notes"); r.summary = s("summary")
        r.given = readGiven(o["given"])
        if let m = o["marks"], m.map != nil {
            var x: [String: Double] = [:]
            for k in ["A", "B1", "B2", "C", "total"] { if let v = num(m[k]) { x[k] = v } }
            r.marks = x
        }
        r.segments = (o["segments"]?.list ?? []).compactMap { x in
            let file = x["file"]?.str ?? ""
            guard !file.isEmpty else { return nil }
            return Segment(part: Int(num(x["part"]) ?? 1), file: file, ms: num(x["ms"]) ?? 0, q: x["q"]?.str ?? "", heard: x["heard"]?.str ?? "", said: x["said"]?.str ?? "")
        }
        r.turns = (o["turns"]?.list ?? []).compactMap { x in
            let t = x["text"]?.str ?? ""
            guard !t.isEmpty else { return nil }
            let who = x["who"]?.str ?? ""
            return Turn(start: num(x["start"]) ?? 0, end: num(x["end"]) ?? 0, who: who == "examiner" || who == "feedback" ? who : "me", text: t)
        }
        if let l = o["listening"], l.map != nil { r.listening = l }
        r.waiting = s("waiting"); r.from = s("from")
        return r
    }

    /// The most a kind of oral is marked out of (a conversation has no picture: no B1).
    public static func maxOf(_ kind: String) -> Int { kind == "conversation" ? 24 : 30 }

    /// The mark shown for an oral: the teacher's or tutor's for theirs, else Claude's.
    public static func markOf(_ o: Oral) -> (total: Double?, max: Double?) {
        if o.by != "practice", let t = o.given?.total { return (t, o.given?.max) }
        guard let t = o.marks?["total"] else { return (nil, nil) }
        return (t, Double(maxOf(o.kind)))
    }

    // MARK: what the laptop's ears heard (an oral's listening:, as OralAdd.tsx ListeningBox shows it)

    /// The sounds the phoneme ear flags (spanishoralhear.js PHONE_ISSUE's say).
    public static let phoneIssue: [String: String] = [
        "r": "an English r", "rr": "a tapped r where Spanish rolls it", "vowel": "an English vowel", "h": "the h sounded (it is silent)",
        "v": "an English v (Spanish v is a b)", "jg": "an English j sound (Spanish j and ge / gi are from the throat)", "ll": "ll said as l (it is like a y)",
        "off": "sounds unlike the word",
    ]

    /// "Part 2", "Overall", "At 3:10" (partLabel).
    public static func partLabel(_ part: YValue?, lower: Bool = false) -> String {
        let raw = part?.str ?? ""
        let t: String
        if case .int = part { t = "Part \(raw)" } else if case .double = part { t = "Part \(raw)" }
        else if raw.range(of: #"^\d+$"#, options: .regularExpression) != nil { t = "Part \(raw)" }
        else if raw == "all" { t = "Overall" }
        else if raw.range(of: #"^\d+:\d\d$"#, options: .regularExpression) != nil { t = "At \(raw)" }
        else { t = raw }
        return lower && !t.isEmpty ? t.prefix(1).lowercased() + t.dropFirst() : t
    }

    public struct Heard: Equatable, Sendable {
        public struct Diff: Equatable, Sendable { public var said, meant, kind, part: String }
        public struct Sound: Equatable, Sendable { public var kind, say: String; public var count: Int?; public var words: [String] }
        /// Your share of the talking (0...1) and your seconds, when the recording had more than one voice.
        public var mine: Double?
        public var me: Double?
        public var diffs: [Diff] = []
        public var sounds: [Sound] = []
        /// "Part 1: 92/min, 3 pauses (1 long), English: okay"
        public var delivery: [String] = []
        public var saidEar = false
        public var soundsEar = false
        public var earError = ""
        public init() {}

        /// "You spoke 64% of the time (3 min)."
        public var talkLine: String? {
            guard let mine, let me else { return nil }
            return "You spoke \(Int((mine * 100).rounded()))% of the time (\(me < 60 ? "\(Int(me.rounded())) s" : "\(Int((me / 60).rounded())) min"))."
        }
    }

    public static func heard(_ L: YValue?) -> Heard? {
        guard let L, L.map != nil, L["ears"] != nil || L["talk"] != nil else { return nil }
        var h = Heard()
        if let t = L["talk"], t.map != nil { h.mine = num(t["mine"]); h.me = num(t["me"]) }
        h.diffs = (L["diffs"]?.list ?? []).map { d in
            Heard.Diff(said: d["said"]?.str ?? "", meant: d["meant"]?.str ?? "", kind: d["kind"]?.str ?? "", part: d["part"].map { partLabel($0, lower: true) } ?? "")
        }
        if let s = L["sounds"]?.map {
            h.sounds = s.map { p in
                Heard.Sound(kind: p.key, say: phoneIssue[p.key] ?? p.key, count: L["soundCounts"]?[p.key].flatMap { num($0) }.map { Int($0) },
                            words: (p.value.list ?? []).map(\.str))
            }
        }
        h.delivery = (L["delivery"]?.list ?? []).map { x in
            let pauses = Int(num(x["pauses"]) ?? 0), long = Int(num(x["longPauses"]) ?? 0)
            let eng = (x["english"]?.list ?? []).map(\.str)
            return "\(partLabel(x["part"])): \(Int(num(x["wpm"]) ?? 0))/min, \(pauses) \(pauses == 1 ? "pause" : "pauses")" + (long > 0 ? " (\(long) long)" : "") + (eng.isEmpty ? "" : ", English: " + eng.joined(separator: ", "))
        }
        h.saidEar = L["ears"]?["said"]?.str == "true"
        h.soundsEar = L["ears"]?["sounds"]?.str == "true"
        h.earError = L["earError"]?.str ?? ""
        return h
    }

    // MARK: the picture bank (only the labels, for the titles)

    public struct Image: Equatable, Sendable { public var file, theme, topic, label, about: String }

    public static func parseImages(_ text: String?) -> [Image] {
        guard let text, let o = try? YValue.parse(text) else { return [] }
        return (o["images"]?.list ?? []).compactMap { x in
            let f = x["file"]?.str ?? ""
            guard !f.isEmpty else { return nil }
            return Image(file: f, theme: toTheme(x["theme"]?.str ?? ""), topic: x["topic"]?.str ?? "", label: x["label"]?.str ?? "", about: (x["about"]?.str ?? "").trimmed)
        }
    }

    /// The label the IB puts on a picture: "Experiencias: Festivales y celebraciones".
    public static func labelFor(_ img: Image) -> String {
        img.label.isEmpty ? [themeName(img.theme), img.topic].filter { !$0.isEmpty }.joined(separator: ": ") : img.label
    }

    // MARK: the list of past orals

    public struct Row: Equatable, Sendable, Identifiable {
        public var id, kind, by, title, when, summary, image, waiting, from: String
        public var total: Double?
        public var max: Double?
        public var share: Double? { guard let t = total, let m = max, m > 0 else { return nil }; return t / m }
    }

    /// An oral's title as the list shows it: its own, else the kind's (a session with the tutor, a conversation, the picture's label,
    /// the theme).
    public static func title(_ o: Oral, settings: Settings, images: [Image]) -> String {
        if !o.title.isEmpty { return o.title }
        switch o.kind {
        case "conversation": return "Conversation"
        case "session": return "Session with \(settings.tutor)"
        default:
            if let p = images.first(where: { $0.file == o.image }) { let l = labelFor(p); if !l.isEmpty { return l } }
            return o.theme.isEmpty ? "Oral" : themeName(o.theme)
        }
    }

    /// "2026-11-19 20:10" from an ISO start.
    public static func when(_ started: String) -> String { String(started.prefix(16)).replacingOccurrences(of: "T", with: " ") }

    /// The past orals, newest first.
    public static func rows(_ orals: [Oral], settings: Settings, images: [Image]) -> [Row] {
        orals.sorted { $0.started > $1.started }.map { o in
            let m = markOf(o)
            return Row(id: o.id, kind: o.kind, by: o.by, title: title(o, settings: settings, images: images), when: when(o.started), summary: o.summary,
                       image: o.image, waiting: o.waiting, from: o.from, total: m.total, max: m.max)
        }
    }

    /// Who an oral is by, in words.
    public static func who(_ by: String, settings: Settings) -> String {
        by == "teacher" ? settings.teacher : by == "tutor" ? settings.tutor : "Practice"
    }

    // MARK: adding a recording on the phone

    /// An oral's folder name from its start: "2026-11-19 2010" (the laptop's oralId).
    public static func oralId(_ iso: String) -> String {
        var s = String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
        if let r = s.range(of: ":") { s.replaceSubrange(r, with: "") }
        return s
    }

    public struct NewRecording: Equatable, Sendable {
        /// tutor | teacher
        public var by = "tutor"
        /// session | full | conversation
        public var kind = "session"
        public var title = ""
        public var date = ""
        public var crit: [String: Double] = [:]
        public var total: Double?
        public var max: Double?
        public var comments = ""
        public init() {}
    }

    /// oral.yaml for a recording added on a phone: what is known now, `waiting: hear` until the laptop hears it.
    public static func newOral(_ r: NewRecording, id: String, started: String, recording: String, device: String) -> String {
        var pairs: [YValue.YPair] = [.init("id", .string(id)), .init("kind", .string(r.kind)), .init("by", .string(r.by))]
        if !r.title.trimmed.isEmpty { pairs.append(.init("title", .string(r.title.trimmed))) }
        pairs.append(.init("recording", .string(recording)))
        pairs.append(.init("started", .string(started)))
        var g: [YValue.YPair] = []
        for (k, _) in critMax { if let v = r.crit[k] { g.append(.init(k, number(v))) } }
        var total = r.total, max = r.max
        if total == nil, !r.crit.isEmpty {
            total = critMax.compactMap { r.crit[$0.key] }.reduce(0, +)
            max = max ?? Double(critMax.filter { r.crit[$0.key] != nil }.map(\.max).reduce(0, +))
        }
        if let total { g.append(.init("total", number(total))) }
        if let max { g.append(.init("max", number(max))) }
        if !r.comments.trimmed.isEmpty { g.append(.init("comments", .string(r.comments.trimmed))) }
        if !g.isEmpty { pairs.append(.init("given", .map(g))) }
        pairs.append(.init("waiting", .string("hear")))
        pairs.append(.init("from", .string(device)))
        return "# An oral recording added on the \(device) (Spanish › Oral). waiting: hear until the laptop's ears hear it: it writes down what was\n"
            + "# said, tells your answers from the questions and feedback, and fills this file in, as with a recording added there.\n"
            + YValue.map(pairs).yaml
    }

    static func number(_ d: Double) -> YValue { d == d.rounded() && abs(d) < 1e9 ? .int(Int(d)) : .double(d) }

    // MARK: the listening test

    public struct Line: Equatable, Sendable { public let id, read, how: String }
    /// The lines to read (the laptop's spanishoralhear.js LISTEN_TEST): mistakes and English sounds planted on purpose; the last
    /// is read as well as you can.
    public static let listenTest: [Line] = [
        Line(id: "t1", read: "Ayer yo fue al cine con mis amigos.", how: ""),
        Line(id: "t2", read: "Nosotros come en un restaurante los domingos.", how: ""),
        Line(id: "t3", read: "La problema es que los casas son muy caro.", how: ""),
        Line(id: "t4", read: "Mi hermana es cansada hoy.", how: ""),
        Line(id: "t5", read: "Pero el perro come arroz.", how: "Say \"pero\" with an English r (like \"pair-oh\"); say \"perro\" and \"arroz\" properly."),
        Line(id: "t6", read: "Hablo con mi hermano en verano.", how: "Sound the h in \"hablo\" (like \"hello\") and say \"verano\" with an English v."),
        Line(id: "t7", read: "La gente joven trabaja mucho.", how: "Say \"gente\" like English \"gentle\" (a j sound) and \"joven\" with an English j."),
        Line(id: "t8", read: "Me gusta la casa de mi tía.", how: "Say \"me\" like English \"may\" and end \"casa\" with an \"uh\"."),
        Line(id: "control", read: "Los fines de semana me gusta leer y salir con mis amigos.", how: "Read this one as well as you can: nothing should be flagged."),
    ]

    /// A kept result (listening-test/<date time>.yaml).
    public struct TestResult: Equatable, Sendable {
        public var file, at, advice, from: String
        public var grammarSaid, grammarMeant, grammarTotal, soundsFlagged, soundsTotal, falseFlags: Int
    }

    public static func parseTest(_ text: String, file: String) -> TestResult? {
        guard let o = try? YValue.parse(text), o.map != nil, let r = o["result"], r.map != nil else { return nil }
        func n(_ v: YValue?) -> Int { Int(num(v) ?? 0) }
        return TestResult(file: file, at: o["at"]?.str ?? "", advice: r["advice"]?.str ?? "", from: o["from"]?.str ?? "",
                          grammarSaid: n(r["grammar"]?["said"]), grammarMeant: n(r["grammar"]?["meant"]), grammarTotal: n(r["grammar"]?["total"]),
                          soundsFlagged: n(r["sounds"]?["flagged"]), soundsTotal: n(r["sounds"]?["total"]), falseFlags: r["falseFlags"]?.list?.count ?? 0)
    }

    /// A take recorded on a phone: listening-test/phone/<stamp>/take.yaml beside one recording a line (<line id>.m4a).
    public struct Take: Equatable, Sendable {
        public var stamp, at, device: String
        public var lines: [String]
        /// The result file the laptop wrote once it heard the take ("" while it waits).
        public var heard: String
    }

    public static func takeYaml(at: String, device: String, lines: [String]) -> String {
        "# A listening test read on the \(device) (Spanish › Oral). The laptop's ears hear it on its Oral page and keep the result in listening-test/.\n"
            + YValue.map([.init("at", .string(at)), .init("device", .string(device)), .init("lines", .list(lines.map { .string($0) }))]).yaml
    }

    public static func parseTake(_ text: String, stamp: String) -> Take? {
        guard let o = try? YValue.parse(text), o.map != nil else { return nil }
        return Take(stamp: stamp, at: o["at"]?.str ?? "", device: o["device"]?.str ?? "", lines: (o["lines"]?.list ?? []).map(\.str).filter { !$0.isEmpty },
                    heard: o["heard"]?.str ?? "")
    }
}
