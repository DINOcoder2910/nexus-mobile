import Foundation

/// Spanish › Writing, pure: a port of the laptop's renderer/src/spanishgrade.js. The tutor's prompts (study/spanish/prompts.yaml; Nexus
/// never writes one), the word count the IB way, and marking a piece exactly as an IB Language ab initio Paper 1 task: A Language /6,
/// B Message /6, C Conceptual understanding /3, with the examiners' rules applied in code after the model's reading, so a mark can never
/// break them.
public enum SpanishGrade {
    // MARK: the rubric (a close paraphrase of the official descriptors)

    public struct Band: Sendable { public let lo, hi: Int; public let text: String }
    public struct Criterion: Sendable { public let key, name: String; public let max: Int; public let bands: [Band] }
    public static let criteria: [Criterion] = [
        Criterion(key: "A", name: "Language", max: 6, bands: [
            Band(lo: 1, hi: 2, text: "Command of the language is limited. Vocabulary is sometimes appropriate to the task. Basic grammatical structures are used. Language contains errors in basic structures; errors interfere with communication."),
            Band(lo: 3, hi: 4, text: "Command of the language is partially effective. Vocabulary is generally appropriate to the task and varied. Basic structures are used accurately, with some attempts at more complex ones; errors in complex structures sometimes interfere with communication."),
            Band(lo: 5, hi: 6, text: "Command of the language is effective and mostly accurate. Vocabulary is appropriate to the task and varied. A variety of basic and some more complex structures is used effectively; occasional errors do not interfere with communication."),
        ]),
        Criterion(key: "B", name: "Message", max: 6, bands: [
            Band(lo: 1, hi: 2, text: "The task is partially fulfilled. Few ideas are relevant to the task; ideas are stated but not developed. Ideas are not clearly presented and do not follow a logical structure, making the message difficult to determine."),
            Band(lo: 3, hi: 4, text: "The task is generally fulfilled. Some ideas are relevant to the task; some are developed with detail and examples. Ideas are generally clearly presented and the response is generally structured logically, leading to a mostly successful delivery of the message."),
            Band(lo: 5, hi: 6, text: "The task is fulfilled. Ideas are relevant to the task and developed well with details and examples. Ideas are clearly presented and the response is structured logically, supporting the delivery of the message."),
        ]),
        Criterion(key: "C", name: "Conceptual understanding", max: 3, bands: [
            Band(lo: 1, hi: 1, text: "Conceptual understanding is limited. The choice of text type is generally inappropriate to the context, purpose or audience. The register and tone are inappropriate to the context, purpose and audience. The response incorporates limited recognizable conventions of the chosen text type."),
            Band(lo: 2, hi: 2, text: "Conceptual understanding is mostly demonstrated. The choice of text type is generally appropriate. The register and tone, while occasionally appropriate, fluctuate. The response incorporates some conventions of the chosen text type."),
            Band(lo: 3, hi: 3, text: "Conceptual understanding is fully demonstrated. The choice of text type is appropriate to the context, purpose and audience. The register and tone are appropriate. The response fully incorporates the conventions of the chosen text type."),
        ]),
    ]
    public static let rules = [
        "Within a band: all of its descriptors met gives the higher mark; most of them met gives the lower mark.",
        "Completely off task: 0 for B and C (A can still be high).", "The task misunderstood: B is at most 4.", "No paragraphs: one mark off B, in any band.",
        "Headers, dates, greetings, sign-offs and signatures do not count towards the 70 to 150 words. Under 70 words can still score well on A but rarely reaches the top band of B. Over 150 words is not penalised directly, but the examiner may stop reading, which can cost B.",
        "Punctuation errors count. One error may be a slip; the same error repeated shows the structure is not mastered.",
        "Vocabulary and structures copied from the prompt earn nothing.", "Connectors and sequencing words are judged under B, not A.", "Facts and opinions are not judged for being true.",
        "The text type need not be named. A text type matching none of the three offered: C at most 1 (if tone and register fit). Named one type but wrote another: judged as what was written.",
        "Writing to the wrong audience: C at most 2.", "\"ustedes\" alone does not make a text formal.",
    ]

    // MARK: the word count the IB way

    static let greet = #"^(hola|querid[oa]s?|estimad[oa]s?|buen[oa]s?\s+(días|tardes|noches)|señor|señora|sr\.|sra\.|a quien corresponda|¡?hola)\b"#
    static let signoff = #"^(un\s+(abrazo|saludo|beso)|abrazos|besos|saludos|atentamente|cordialmente|hasta\s+(pronto|luego|la próxima)|un fuerte abrazo|con cariño|tu amig[oa]|chao|adiós|nos vemos)\b"#
    static let date = #"^\s*(\d{1,2}\s+de\s+\w+|\w+,?\s+\d{1,2}\s+de\s+\w+|(lunes|martes|miércoles|jueves|viernes|sábado|domingo)\b.*\d|\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4})"#

    public static func countWords(_ s: String) -> Int { JS.all("[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9]+(?:['’-][A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+)*", s).count }

    public struct Count: Equatable, Sendable {
        public struct Skipped: Equatable, Sendable { public var line, why: String; public var words: Int }
        public var counted: Int
        public var total: Int
        public var skipped: [Skipped]
        public var paragraphs: Int
        /// short | ok | long
        public var band: String
        public init(counted: Int, total: Int = 0, skipped: [Skipped] = [], paragraphs: Int, band: String = "ok") {
            self.counted = counted; self.total = total; self.skipped = skipped; self.paragraphs = paragraphs; self.band = band
        }
    }

    public static func wordCount(_ text: String) -> Count {
        let lines = JS.split(#"\r?\n"#, text)
        var skipped: [Count.Skipped] = [], counted = 0, afterSignoff = false
        for (i, raw) in lines.enumerated() {
            let l = raw.trimmed
            if l.isEmpty { continue }
            let n = countWords(l)
            var why = ""
            if afterSignoff && n <= 4 { why = "signature" }
            else if JS.test(date, l, ci: true) && n <= 8 { why = "date" }
            else if JS.test(greet, l, ci: true) && n <= 6 && JS.test("[,:!]$", l) { why = "greeting" }
            else if JS.test(signoff, l, ci: true) && n <= 6 { why = "sign-off"; afterSignoff = true }
            else if i == 0 && n <= 8 && !JS.test("[.!?]$", l) && lines.dropFirst().contains(where: { !$0.trimmed.isEmpty }) { why = "title" }
            if !why.isEmpty { skipped.append(.init(line: l, why: why, words: n)) } else { counted += n }
        }
        let paragraphs = JS.split(#"\n\s*\n"#, text.trimmed).filter { countWords($0) >= 8 }.count
        return Count(counted: counted, total: countWords(text), skipped: skipped, paragraphs: paragraphs, band: counted < 70 ? "short" : counted > 150 ? "long" : "ok")
    }

    // MARK: prompts.yaml: prompts: [{ id, text, unit, types, task, source, added }]

    public struct Prompt: Equatable, Sendable, Identifiable {
        public var id, text, unit: String
        public var types: [String]
        public var task, source, added: String
        public init(id: String, text: String, unit: String = "", types: [String] = [], task: String = "", source: String = "", added: String = "") {
            self.id = id; self.text = text; self.unit = unit; self.types = types; self.task = task; self.source = source; self.added = added
        }
    }

    public static func parsePrompts(_ text: String?) -> (ok: Bool, error: String?, prompts: [Prompt]) {
        guard let text else { return (true, nil, []) }
        let v: YValue
        do { v = try YValue.parse(text) } catch { return (false, "prompts.yaml does not parse: " + String(describing: error).components(separatedBy: "\n")[0], []) }
        let list = (v["prompts"]?.list ?? []).compactMap { p -> Prompt? in
            let id = p["id"]?.str ?? "", t = p["text"]?.str ?? ""
            if id.isEmpty || t.isEmpty { return nil }
            return Prompt(id: id, text: t.trimmed, unit: p["unit"]?.str ?? "", types: p["types"]?.strings ?? [], task: p["task"]?.str ?? "", source: p["source"]?.str ?? "", added: p["added"]?.str ?? "")
        }
        return (true, nil, list)
    }

    public static func serializePrompts(_ prompts: [Prompt]) -> String {
        let items: [YValue] = prompts.map { p in
            var m: [YValue.YPair] = [.init("id", .string(p.id)), .init("text", .string(p.text))]
            if !p.unit.isEmpty { m.append(.init("unit", .string(p.unit))) }
            if !p.types.isEmpty { m.append(.init("types", .list(p.types.map { .string($0) }))) }
            if !p.task.isEmpty { m.append(.init("task", .string(p.task))) }
            if !p.source.isEmpty { m.append(.init("source", .string(p.source))) }
            if !p.added.isEmpty { m.append(.init("added", .string(p.added))) }
            return .map(m)
        }
        return "# Your tutor's writing prompts (Nexus never writes prompts). text, unit, the text types offered, the source.\n" + YValue.map([.init("prompts", .list(items))]).yaml
    }

    public static func newPromptId(_ prompts: [Prompt], day: String) -> String {
        var n = 1
        let base = "p-" + day.replacingOccurrences(of: "-", with: "")
        while prompts.contains(where: { $0.id == "\(base)-\(n)" }) { n += 1 }
        return "\(base)-\(n)"
    }

    /// The text types a prompt offers, read from its text when the user did not list them.
    public static let textTypes = ["correo electrónico", "email", "carta", "blog", "diario", "artículo", "folleto", "cartel", "anuncio", "discurso", "entrevista", "reseña", "receta", "invitación", "postal", "mensaje", "chat", "redes sociales", "presentación", "instrucciones", "guía"]
    public static func typesIn(_ text: String) -> [String] {
        textTypes.filter { JS.test(#"\b"# + NSRegularExpression.escapedPattern(for: $0) + #"\b"#, text, ci: true) }
    }

    // MARK: marking: the prompt, the answer's shape, the caps applied in code

    public static let system = "You are an experienced IB Language ab initio examiner. You mark Paper 1 writing exactly by the official criteria and the examiners' rules, never by a scale of your own, and you justify every mark with the descriptors and quotes from the piece."
    static let shape = #"{"A": {"mark": 0-6, "met": ["descriptors of the awarded band (or the one above) that the piece meets"], "missed": ["descriptors it misses"], "evidence": ["short quotes from the piece that show it"], "next": ["the one or two changes that would move it up a band"]}, "B": {same, 0-6}, "C": {same, 0-3}, "textType": "the text type the piece actually is", "offTask": false, "misread": false, "wrongAudience": false, "typeOffered": true, "mistakes": [{"wrong": "...", "right": "...", "skill": "a skill id", "why": "..."}], "overall": "two or three sentences to the student: where the piece stands and what to do first"}"#

    public struct Sample: Equatable, Sendable {
        public var A, B, C: Double
        public var comment, prompt, text: String
    }

    public static func gradePrompt(prompt: Prompt, text: String, count: Count, samples: [Sample] = []) -> String {
        let rubric = criteria.map { c in
            "Criterion \(c.key): \(c.name) (0-\(c.max))\n" + c.bands.map { "  \($0.lo == $0.hi ? "\($0.lo)" : "\($0.lo)-\($0.hi)"): \($0.text)" }.joined(separator: "\n") + "\n  0: the work does not reach a standard described above."
        }.joined(separator: "\n")
        let skipped = count.skipped.isEmpty ? "every line counts" : "not counting " + count.skipped.map { "\"\($0.line)\" (\($0.why))" }.joined(separator: ", ")
        let fmt = { (d: Double) in JSONValue.format(d) }
        return ["(Nexus Spanish grade)", "", "Mark this IB Spanish ab initio Paper 1 response.", "", "## The task", prompt.text, prompt.types.isEmpty ? "" : "Text types offered: \(prompt.types.joined(separator: ", "))", "",
                "## The response", text, "", "## Word count (counted the IB way: \(skipped)): \(count.counted) words, \(count.paragraphs) paragraph\(count.paragraphs == 1 ? "" : "s").", "",
                "## The criteria", rubric, "", "## The examiners' rules", rules.map { "- " + $0 }.joined(separator: "\n"), "",
                samples.isEmpty ? "" : "## Pieces the student's teacher marked (match this standard)\n" + samples.map { "\($0.text)\nMarks: A \(fmt($0.A)), B \(fmt($0.B)), C \(fmt($0.C)). \($0.comment)" }.joined(separator: "\n\n") + "\n",
                "Give each criterion its mark with the descriptors met and missed, short quotes as evidence and the one or two changes that would move it up a band. List the language mistakes (wrong text exactly as written, the fix, a skill id, why). Set the flags honestly; the app applies the caps.",
                "Skill ids: \(Spanish.skills.map(\.id).joined(separator: ", "))", "", "Answer with only one JSON object, in this shape: " + shape].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public struct Mark: Equatable, Sendable {
        public var mark: Int
        public var met, missed, evidence, next: [String]
    }
    public struct Grade: Equatable, Sendable {
        public var A, B, C: Mark
        public var textType, overall: String
        public var applied: [String]
        public var mistakes: [SpanishCheck.LogMistake]
        public var total: Int
        public func mark(_ key: String) -> Mark { key == "A" ? A : key == "B" ? B : C }
    }

    /// The model's reading, with the examiners' caps and deductions applied (each one noted).
    public static func readGrade(_ ans: JSONValue?, count: Count?) -> Grade? {
        guard let ans, ans["A"]?.object != nil, ans["B"]?.object != nil, ans["C"]?.object != nil else { return nil }
        func arr(_ v: JSONValue?) -> [String] { (v?.array ?? []).compactMap { $0.string ?? $0.number.map { JSONValue.format($0) } }.filter { !$0.isEmpty } }
        func c(_ k: String, _ max: Int) -> Mark {
            let x = ans[k]
            let raw = x?["mark"]?.number ?? Double(x?["mark"]?.string ?? "") ?? 0
            return Mark(mark: Swift.max(0, Swift.min(max, Int(JS.round(raw.isFinite ? raw : 0)))), met: arr(x?["met"]), missed: arr(x?["missed"]), evidence: arr(x?["evidence"]), next: arr(x?["next"]))
        }
        func flag(_ k: String) -> Bool? { ans[k]?.bool }
        var g = Grade(A: c("A", 6), B: c("B", 6), C: c("C", 3), textType: ans["textType"]?.string ?? "", overall: ans["overall"]?.string ?? "", applied: [],
                      mistakes: (ans["mistakes"]?.array ?? []).filter { !($0["wrong"]?.string ?? "").isEmpty }.map { m in
                          let sk = m["skill"]?.string ?? ""
                          return SpanishCheck.LogMistake(skill: Spanish.isSkill(sk) ? sk : Spanish.toSkill(sk), wrong: m["wrong"]?.string ?? "", right: m["right"]?.string ?? "", why: m["why"]?.string ?? "")
                      }, total: 0)
        func cap(_ k: String, _ n: Int, _ why: String) {
            switch k {
            case "B": if g.B.mark > n { g.B.mark = n; g.applied.append(why) }
            default: if g.C.mark > n { g.C.mark = n; g.applied.append(why) }
            }
        }
        let offTask = flag("offTask") == true
        if offTask {
            if g.B.mark > 0 || g.C.mark > 0 { g.applied.append("Off task: B and C are 0.") }
            g.B.mark = 0; g.C.mark = 0
        }
        if flag("misread") == true { cap("B", 4, "The task was misunderstood: B is at most 4.") }
        if let count, count.paragraphs < 2, g.B.mark > 0, !offTask { g.B.mark -= 1; g.applied.append("No paragraphs: one mark off B.") }
        if flag("typeOffered") == false { cap("C", 1, "The text type is none of the three offered: C is at most 1.") }
        if flag("wrongAudience") == true { cap("C", 2, "Written to the wrong audience: C is at most 2.") }
        g.total = g.A.mark + g.B.mark + g.C.mark
        return g
    }

    // MARK: a teacher-marked sample: samples/<name>.md, front matter A, B, C, comment; the piece below

    public static func parseSample(_ text: String) -> Sample? {
        guard let m = JS.match(#"^---\n([\s\S]*?)\n---\n?([\s\S]*)$"#, text), let fm = try? YValue.parse(m[1]) else { return nil }
        guard let a = fm["A"]?.number, let b = fm["B"]?.number, let c = fm["C"]?.number else { return nil }
        let body = JS.replace("^#.*\\n", m[2], "").trimmed
        if body.isEmpty { return nil }
        return Sample(A: a, B: b, C: c, comment: fm["comment"]?.str ?? "", prompt: fm["prompt"]?.str ?? "", text: body)
    }

    // MARK: a piece: writing/<YYYY-MM-DD> <slug>.md, the marks in front matter, the text, then the feedback

    public static func pieceFile(prompt: Prompt, text: String, count: Count, grade: Grade?, day: String) -> String {
        var fm: [YValue.YPair] = [.init("prompt", .string(prompt.id)), .init("unit", .string(prompt.unit)), .init("written", .string(day)), .init("words", .int(count.counted))]
        if let g = grade { fm.append(.init("marks", .map([.init("A", .int(g.A.mark)), .init("B", .int(g.B.mark)), .init("C", .int(g.C.mark)), .init("total", .int(g.total))]))) }
        else { fm.append(.init("marks", .null)) }
        fm.append(.init("textType", .string(grade?.textType ?? "")))
        var fb: [String] = []
        if let g = grade {
            fb += ["## Marks", "", "**\(g.total)/15** · A Language \(g.A.mark)/6 · B Message \(g.B.mark)/6 · C Conceptual understanding \(g.C.mark)/3", "", g.overall, ""]
            for c in criteria {
                let x = g.mark(c.key)
                fb += ["### \(c.key): \(c.name) (\(x.mark)/\(c.max))", ""] + x.met.map { "- Met: " + $0 } + x.missed.map { "- Missed: " + $0 } + x.evidence.map { "- \"\($0)\"" } + x.next.map { "- Next: " + $0 } + [""]
            }
            fb.append(g.applied.isEmpty ? "" : "### Examiner rules applied\n\n" + g.applied.map { "- " + $0 }.joined(separator: "\n") + "\n")
            fb.append(g.mistakes.isEmpty ? "" : "### Language mistakes\n\n" + g.mistakes.map { "- \($0.wrong) → \($0.right) (\($0.skill)): \($0.why)" }.joined(separator: "\n") + "\n")
        }
        let title = String((prompt.text.components(separatedBy: "\n").first ?? "").prefix(80))
        let out = "---\n\(YValue.map(fm).yaml.trimmed)\n---\n\n# \(title)\n\n\(text.trimmed)\n\n\(fb.joined(separator: "\n"))"
        return JS.replace(#"\n{3,}"#, out, "\n\n")
    }

    /// A piece's front matter, for the list of pieces under a prompt.
    public struct PieceInfo: Equatable, Sendable {
        public var path, prompt, written: String
        public var words: Int
        public var total: Int?
        public init(path: String, prompt: String, written: String, words: Int, total: Int?) { self.path = path; self.prompt = prompt; self.written = written; self.words = words; self.total = total }
    }
    public static func pieceInfo(_ text: String, path: String) -> PieceInfo? {
        guard let m = JS.match(#"^---\n([\s\S]*?)\n---"#, text), let fm = try? YValue.parse(m[1]), fm.map != nil else { return nil }
        let total = fm["marks"]?["total"]?.number
        return PieceInfo(path: path, prompt: fm["prompt"]?.str ?? "", written: fm["written"]?.str ?? "", words: Int(fm["words"]?.number ?? 0), total: total.map { Int($0) })
    }
}
