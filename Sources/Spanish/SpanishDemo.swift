import Foundation
import NexusCore

/// The UI check's Spanish (UITests/SpanishTests and SpanishPhoneTests, launched with -NexusSpanishDemo): a Spanish workstream set up in the
/// sample data with a few checks, a chat, a prompt and a note already there, and canned answers in place of Claude and LanguageTool, so
/// the simulator can photograph every Spanish screen going through real turns. Nothing here runs in a normal launch.
enum SpanishDemo {
    static let active = ProcessInfo.processInfo.arguments.contains("-NexusSpanishDemo")
    static let folder = "classes/spanish-ab"

    /// After the sample data is made: the Spanish workstream, set up, with some history.
    @MainActor
    static func prepare(_ store: NexusStore) {
        guard active, store.snapshot.isDataFolder else { return }
        let root = store.folder
        let ws = root.appendingPathComponent(folder + "/workstream.yaml")
        guard !FileManager.default.fileExists(atPath: ws.path) else { return }
        let today = Days.today()
        let month = String(today.prefix(7))
        let base = folder + "/"
        var files: [(String, String)] = [
            ("workstream.yaml", "id: spanish-ab\nname: Spanish ab initio\ncolor: orange\nstatus: active\n"),
            ("tasks.yaml", "tasks:\n  - id: es1\n    title: Spanish writing practice\n    due: \(Days.add(today, 3))\n"),
        ]
        files += Spanish.setupFiles().map { ($0.path, $0.text) }
        let at = { (h: Int, m: Int) in String(format: "%@T%02d:%02d:00.000", Days.add(today, -1), h, m) }
        let entries = [
            SpanishCheck.Entry(at: at(17, 2), text: "Mi hermana es muy cansada hoy.", fixed: "Mi hermana está muy cansada hoy.",
                               mistakes: [.init(skill: "ser-estar", wrong: "es", right: "está", why: "A temporary state takes estar.")], structures: ["presente"]),
            SpanishCheck.Entry(at: at(17, 5), text: "El fin de semana pasado fui al cine con mis primos.", good: ["tense.past"], structures: ["pretérito indefinido"]),
            SpanishCheck.Entry(at: at(17, 9), text: "Mañana voy a estudiar para el examen.", structures: ["ir a + infinitivo"]),
            SpanishCheck.Entry(at: at(17, 14), text: "Ayer compre una camiseta para mi madre.", fixed: "Ayer compré una camiseta para mi madre.",
                               mistakes: [.init(skill: "accent.verb", wrong: "compre", right: "compré", why: "The yo form of the preterite ends in -é.")], structures: ["pretérito indefinido"]),
            SpanishCheck.Entry(at: at(17, 20), text: "Me gusta los deportes.", fixed: "Me gustan los deportes.",
                               mistakes: [.init(skill: "gustar", wrong: "gusta", right: "gustan", why: "Gustar agrees with what is liked: los deportes is plural.")], structures: ["gustar-type"]),
        ]
        files.append((Spanish.P.log(month), SpanishCheck.serializeLog(entries)))
        files.append((Spanish.P.stats, SpanishCheck.serializeStats(SpanishCheck.skillStats(entries, now: Date().timeIntervalSince1970 * 1000), nowIso: SpanishLibrary.stamp())))
        let chat = SpanishMemory.Chat(title: "Ser and estar", started: at(18, 0), model: "sonnet", summary: "Practised ser and estar with states and places; mixed up es / está with feelings twice. Next: more feelings with estar.",
                                      skills: ["ser-estar"], taught: ["ser-estar: estar for states and places, ser for what something is"],
                                      messages: [.init(role: "user", text: "Can we practise ser and estar?"),
                                                 .init(role: "tutor", text: "Of course. **Ser** says what something *is*; **estar** says how or where it is right now.\n\n```check\n¿Cómo está tu hermana hoy?\n```"),
                                                 .init(role: "check", text: "My answer: Mi hermana es muy cansada hoy.\nThe checker's correction: Mi hermana está muy cansada hoy.\n- es -> está [ser-estar] A temporary state takes estar."),
                                                 .init(role: "tutor", text: "Close! Tired is a state, so it takes **estar**: *Mi hermana está muy cansada.*")])
        files.append((SpanishMemory.chatPath(base: "", started: chat.started, title: chat.title).dropFirst().description, SpanishMemory.serializeChat(chat)))
        let prompt = SpanishGrade.Prompt(id: "\(today)-1", text: "Acabas de volver de un viaje con tu familia. Escribe un correo electrónico a tu amigo/a contándole adónde fuiste, qué hiciste y qué te gustó más.",
                                         unit: Spanish.currentUnit?.code ?? "", types: ["correo electrónico", "blog", "diario"], source: "Ms. Panhausen, worksheet 3", added: today)
        files.append((Spanish.P.prompts, SpanishGrade.serializePrompts([prompt])))
        files.append((Spanish.P.note("ser-estar"), SpanishMemory.addToNote("", id: "ser-estar", status: "taught", lines: ["Taught: estar for states and places", "Wrote \"es cansada\" for a feeling: está cansada"], day: today, link: "chat")))
        do {
            for (rel, text) in files {
                let u = root.appendingPathComponent(base + rel)
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FolderAccess.write(u, text)
            }
        } catch { store.problem = "The Spanish demo could not be written: \(error.localizedDescription)" }
        store.reload()
        store.didWrite(listChanged: true)
        StudyLibrary.shared.load(store)
    }

    // MARK: canned answers

    static func languageTool(_ text: String) -> [SpanishCheck.LTMatch] {
        let r = (text as NSString).range(of: "mi amigos")
        guard r.location != NSNotFound else { return [] }
        return [.init(offset: r.location, length: r.length, message: "Possible agreement error: the possessive should agree with the noun.", replacements: ["mis amigos"], ruleId: "AGREEMENT_POSTPONED_ADJ", category: "GRAMMAR")]
    }

    static func check(_ text: String) -> String {
        if text.contains("voy a la playa") {
            return #"""
            {"corrected": "Ayer yo fui a la playa con mis amigos y comí un helado.",
             "mistakes": [{"wrong": "voy", "right": "fui", "skill": "tense.past", "why": "Ayer needs the preterite: fui, not the present voy."},
                          {"wrong": "mi amigos", "right": "mis amigos", "skill": "agree.number", "why": "The possessive agrees with the plural noun: mis."},
                          {"wrong": "comi", "right": "comí", "skill": "accent.verb", "why": "The yo form of the preterite of -er verbs ends in -í."}],
             "good": [{"text": "un helado", "skill": "articles", "why": "Right article for a masculine noun."}],
             "structures": [{"name": "pretérito indefinido", "text": "comí"}, {"name": "posesivos", "text": "mis amigos"}],
             "words": [{"word": "Ayer", "lemma": "ayer", "form": "adverb of time", "meaning": "yesterday"},
                       {"word": "voy", "lemma": "ir", "form": "ir, presente, yo", "meaning": "I go"},
                       {"word": "playa", "lemma": "playa", "form": "feminine singular noun", "meaning": "beach"},
                       {"word": "amigos", "lemma": "amigo", "form": "masculine plural noun", "meaning": "friends"},
                       {"word": "comi", "lemma": "comer", "form": "comer, pretérito indefinido, yo", "meaning": "I ate"},
                       {"word": "helado", "lemma": "helado", "form": "masculine singular noun", "meaning": "ice cream"}]}
            """#
        }
        if text.contains("fui") {
            return #"{"corrected": "\#(text)", "mistakes": [], "good": [{"text": "fui", "skill": "tense.past", "why": "The preterite for a finished trip."}], "structures": [{"name": "pretérito indefinido", "text": "fui"}], "words": [{"word": "fui", "lemma": "ir", "form": "ir / ser, pretérito indefinido, yo", "meaning": "I went"}, {"word": "Madrid", "lemma": "Madrid", "form": "proper noun", "meaning": "Madrid"}]}"#
        }
        return #"{"corrected": "\#(text.replacingOccurrences(of: "\"", with: "'"))", "mistakes": [], "good": [], "structures": [], "words": []}"#
    }

    /// The tutor: streamed in small pieces.
    static func tutor(_ text: String, turn: Int, onText: @escaping (String) -> Void) async -> String {
        let reply: String
        if text.hasPrefix("My answer:") {
            reply = "¡Muy bien! **Fui** is exactly right for a trip that is over: the preterite tells a finished event.\n\nOne more, a little harder: use two verbs in the past.\n\n```check\n¿Qué hiciste allí? Escribe dos frases.\n```"
        } else if text.hasPrefix("Here are some sentences") {
            reply = "Across these, the pattern is the **past tense with ayer** and **accents on the preterite**: *compré*, *comí*. The stress falls on the last syllable, so it needs the accent.\n\n```card\n{\"front\": \"la camiseta\", \"back\": \"the T-shirt\", \"deck\": \"es-nucleo\", \"tags\": [\"pos::sustantivo\"]}\n```\n\nLet's practise it:\n\n```check\n¿Adónde fuiste el verano pasado?\n```"
        } else {
            reply = "Let's work on the **preterite**, the past tense for finished actions. Regular -ar verbs take -é in the *yo* form (*hablé*), -er and -ir verbs take -í (*comí*); *ir* is irregular: *fui*.\n\n```card\n{\"front\": \"la playa\", \"back\": \"the beach\", \"deck\": \"es-viajes\", \"tags\": [\"pos::sustantivo\"], \"example\": \"Fui a la playa.\"}\n```\n\nYour turn:\n\n```check\n¿Adónde fuiste el fin de semana pasado?\n```"
        }
        try? await Task.sleep(for: .milliseconds(900))
        var i = reply.startIndex
        while i < reply.endIndex {
            let j = reply.index(i, offsetBy: 30, limitedBy: reply.endIndex) ?? reply.endIndex
            onText(String(reply[i..<j]))
            i = j
            try? await Task.sleep(for: .milliseconds(15))
        }
        return reply
    }

    static func memory(feedback: String) -> String {
        #"""
        {"title": "The preterite with ir", "summary": "Practised the preterite of ir and regular verbs; got fui right first time. Next: two past verbs in one sentence.",
         "skills": ["tense.past", "accent.verb"], "taught": [{"skill": "tense.past", "what": "the preterite for finished events; ir is irregular (fui)"}],
         "profile": {"strengths": "- The preterite of ir (fui) for a finished trip\n- Articles with nouns", "working": "- Accents on the preterite (compré, comí)\n- ser and estar with feelings",
                     "mistakes": "- Present instead of the preterite after ayer\n- es for a temporary state (está cansada)", "taught": "- The preterite: -é / -í, ir = fui",
                     "next": "- Two past verbs in one sentence\n- Feelings with estar", "learn": "- Short explanations, then a question to answer"},
         "notes": [{"skill": "tense.past", "lines": ["Got fui right for a finished trip", "Wrote voy after ayer: fui"]}]}
        """#
    }

    static func grade() -> String {
        #"""
        {"textType": "correo electrónico", "overall": "A clear, friendly email that answers all three parts; past tenses are mostly right, with a few accent slips.",
         "A": {"mark": 4, "met": ["Basic structures used accurately", "Vocabulary generally appropriate and varied"], "missed": ["Few complex structures"], "evidence": ["fuimos a la playa", "comí paella"], "next": ["Join ideas with porque and aunque."]},
         "B": {"mark": 5, "met": ["All three parts of the task covered", "Ideas developed with details"], "missed": [], "evidence": ["lo que más me gustó fue"], "next": ["Add one more detail to the last paragraph."]},
         "C": {"mark": 3, "met": ["Email conventions: greeting, sign-off", "Informal register suits a friend"], "missed": [], "evidence": ["¡Hola Marta!", "Un abrazo"], "next": []},
         "applied": [], "mistakes": [{"wrong": "compre", "right": "compré", "skill": "accent.verb", "why": "The yo preterite ends in -é."}]}
        """#
    }
}
