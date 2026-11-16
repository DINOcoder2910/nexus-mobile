import Foundation

/// Spanish (a workstream whose study/study.yaml says `language: spanish`), the pure core: a port of the laptop's
/// renderer/src/spanishcore.js. The skill list every part shares (the checker tags each mistake with these ids, the tutor's memory and the
/// grammar decks use the same ones), the course so far, where each file lives and the files "Set up Spanish study" writes. No UI, no disk.
public enum Spanish {
    // MARK: where things are, inside the workstream's folder

    public static let dir = "study/spanish"
    public enum P {
        public static let skills = dir + "/skills.yaml"
        public static let course = dir + "/course.md"
        public static let profile = dir + "/profile.md"
        public static let stats = dir + "/stats.yaml"
        public static let prompts = dir + "/prompts.yaml"
        public static func log(_ month: String) -> String { "\(dir)/log/\(month).yaml" }
        public static let logDir = dir + "/log"
        public static let chats = dir + "/chats"
        public static let notes = dir + "/skills"
        public static func note(_ id: String) -> String { "\(dir)/skills/\(id).md" }
        public static let writing = dir + "/writing"
        public static let samples = dir + "/samples"
        public static let readme = dir + "/README.md"
    }

    // MARK: the skills

    public struct Skill: Equatable, Sendable, Identifiable {
        public let id: String
        public let group: String
        public let name: String
        public let rule: String
        /// The grammar deck that drills it.
        public let deck: String?
        init(_ id: String, _ group: String, _ name: String, _ rule: String, deck: String? = nil) {
            self.id = id; self.group = group; self.name = name; self.rule = rule; self.deck = deck
        }
    }

    /// How the skills are listed, in order.
    public static let groups: [(id: String, title: String)] = [
        ("accents", "Accents"), ("spelling", "Spelling and punctuation"), ("agreement", "Agreement"), ("verbs", "Verbs and tenses"),
        ("usage", "Choosing the right form"), ("words", "Words and structure"),
    ]

    public static let skills: [Skill] = [
        Skill("accent.stress", "accents", "Written accents (stress)", "A word ending in a vowel, n or s is stressed on the second-to-last syllable; any other word on the last. A word that breaks this gets an accent: tam-BIÉN, di-FÍ-cil, ár-bol."),
        Skill("accent.question", "accents", "Question and exclamation words", "qué, cómo, dónde, cuándo, cuánto, quién, cuál take an accent in a question or exclamation (direct or indirect); que, como, donde without one join clauses."),
        Skill("accent.diacritic", "accents", "Accents that change the word", "él (he) / el (the), tú (you) / tu (your), mí / mi, sí (yes) / si (if), más (more) / mas, sé / se, té / te, está (is) / esta (this)."),
        Skill("accent.verb", "accents", "Accents on verb endings", "Preterite yo and él forms of regular verbs are stressed on the ending: hablé, habló, comí, comió. Also estás, está, están; future forms (hablaré, hablarán)."),
        Skill("spelling", "spelling", "Spelling", "ñ, ll, b/v, h, c/z/qu, g/gu/j: the letters Spanish uses for each sound."),
        Skill("punctuation", "spelling", "¿ ¡ and punctuation", "Questions and exclamations open with ¿ and ¡. A comma never joins two full sentences."),
        Skill("agree.gender", "agreement", "Gender agreement", "Articles and adjectives match the noun: la casa blanca, el problema difícil."),
        Skill("agree.number", "agreement", "Number agreement", "Plural nouns take plural articles and adjectives: los libros nuevos."),
        Skill("agree.verb", "agreement", "Verb matches its subject", "The verb ending matches who does it: mis amigos van, nosotros vamos."),
        Skill("articles", "words", "Articles", "el / la / los / las, un / una; general statements use the article (me gusta el café)."),
        Skill("ser-estar", "usage", "ser or estar", "ser: what something is (identity, origin, job, time, characteristics). estar: where it is and how it is right now (location, feelings, states).", deck: "es-uso"),
        Skill("por-para", "usage", "por or para", "para: purpose, destination, deadline, recipient. por: cause, through, duration, exchange, means.", deck: "es-uso"),
        Skill("tense.past", "usage", "Choosing the past tense", "Perfecto with hoy, esta semana, ya, todavía no, nunca; indefinido with ayer, anoche, el año pasado, hace dos años.", deck: "es-uso"),
        Skill("gustar", "usage", "gustar-type verbs", "The thing liked is the subject: me gusta el libro, me gustan los libros, me duele la cabeza.", deck: "es-uso"),
        Skill("reflexive", "verbs", "Reflexive verbs", "The pronoun matches the subject: me levanto, te duchas, se acuesta, nos vestimos.", deck: "es-pronombres"),
        Skill("verb.presente", "verbs", "Present tense", "-ar: o, as, a, amos, áis, an; -er: o, es, e, emos, éis, en; -ir: o, es, e, imos, ís, en.", deck: "es-presente"),
        Skill("verb.irregular", "verbs", "Irregular and stem-changing verbs", "Stem changes (e→ie, o→ue, e→i) touch every form but nosotros and vosotros; yo-go verbs (tengo, hago, salgo); ser, estar, ir, haber.", deck: "es-presente"),
        Skill("verb.perfecto", "verbs", "Pretérito perfecto", "haber (he, has, ha, hemos, habéis, han) + participle (-ado, -ido); irregular: hecho, dicho, visto, escrito, puesto, vuelto, abierto, roto, muerto.", deck: "es-perfecto"),
        Skill("verb.indefinido", "verbs", "Pretérito indefinido", "-ar: é, aste, ó, amos, asteis, aron; -er/-ir: í, iste, ió, imos, isteis, ieron. ser and ir share fui, fuiste, fue…", deck: "es-indefinido"),
        Skill("verb.imperfecto", "verbs", "Pretérito imperfecto", "-ar: aba, abas, aba…; -er/-ir: ía, ías, ía… Only ser (era), ir (iba) and ver (veía) are irregular.", deck: "es-imperfecto"),
        Skill("verb.futuro", "verbs", "Future (futuro simple, ir a)", "Infinitive + é, ás, á, emos, éis, án; or ir a + infinitive. Irregular stems: tendr-, pondr-, saldr-, vendr-, podr-, sabr-, habr-, querr-, har-, dir-.", deck: "es-futuro"),
        Skill("verb.condicional", "verbs", "Conditional", "Infinitive + ía, ías, ía, íamos, íais, ían, on the same irregular stems as the future: tendría, podría, haría.", deck: "es-futuro"),
        Skill("verb.imperativo", "verbs", "Imperative (commands)", "tú: the él form of the present (habla, come); irregulars: di, haz, ve, pon, sal, sé, ten, ven. Pronouns join the end: levántate.", deck: "es-imperativo"),
        Skill("verb.imperativo-neg", "verbs", "Negative imperative", "no + the present subjunctive: no hables, no comas, no vayas. Pronouns go before: no te levantes.", deck: "es-imperativo"),
        Skill("verb.subjuntivo", "verbs", "Subjunctive", "After wishes, emotions and doubt: quiero que vengas, espero que estés bien.", deck: "es-subjuntivo"),
        Skill("verb.infinitive", "verbs", "Infinitive structures", "tener que, hay que, acabar de, deber, poder, querer + infinitive.", deck: "es-presente"),
        Skill("pronouns", "words", "Object pronouns", "lo / la / los / las (direct), le / les (indirect), before a conjugated verb or joined to an infinitive: lo veo, quiero verlo.", deck: "es-pronombres"),
        Skill("possessives", "words", "Possessives", "mi, tu, su, nuestro (agrees with the thing owned): nuestra casa, mis amigos.", deck: "es-pronombres"),
        Skill("comparisons", "words", "Comparisons", "más / menos … que, tan … como, mejor, peor, mayor, menor.", deck: "es-uso"),
        Skill("prepositions", "words", "Prepositions", "a (direction, personal a: veo a mi madre), en (in, on), de (of, from); ir a, pensar en, depender de."),
        Skill("connectors", "words", "Connectors", "además, sin embargo, por eso, porque, aunque, primero, luego, finalmente: they tie sentences together."),
        Skill("word-choice", "words", "Word choice", "A word that exists but means something else here, false friends (embarazada, realizar), or an English structure in Spanish words."),
        Skill("word-order", "words", "Word order and missing words", "Adjectives usually follow the noun (una casa grande); no word left out or doubled."),
        Skill("register", "words", "tú or usted", "tú with friends and family; usted (and its verb forms) with strangers, teachers, formal letters. Keep one all the way through."),
    ]
    public static let skill: [String: Skill] = Dictionary(uniqueKeysWithValues: skills.map { ($0.id, $0) })
    public static func isSkill(_ id: String) -> Bool { skill[id] != nil }
    public static func skillName(_ id: String) -> String { skill[id]?.name ?? id }

    /// The closest known id for whatever a model wrote ("ser/estar", "Accent", "preterite"), so a mistake always lands on a skill.
    public static func toSkill(_ raw: String) -> String {
        let s = raw.lowercased().trimmed
        if isSkill(s) { return s }
        let pairs: [(String, String)] = [
            (#"ser.?\/?.?estar|ser vs|estar"#, "ser-estar"), (#"por\W*(vs\.?\W*|or\W*|o\W*)?para"#, "por-para"), ("question|interrog|exclam", "accent.question"),
            ("diacrit|tú.?tu|él.?el|si.?sí", "accent.diacritic"), ("accent.*verb|verb.*accent", "accent.verb"), ("accent|tilde|stress", "accent.stress"),
            ("punct|¿|¡", "punctuation"), ("spell|ortograf|ñ", "spelling"), ("gender|género", "agree.gender"), ("number|plural|singular", "agree.number"),
            ("subject.?verb|conjugat|person", "agree.verb"), ("article", "articles"), ("past tense|perfect vs|tense choice|which past", "tense.past"),
            ("gust|doler|encantar|interesar", "gustar"), ("reflex", "reflexive"), ("imperfect", "verb.imperfecto"), ("perfecto|present perfect|haber", "verb.perfecto"),
            ("preter|indefinido", "verb.indefinido"), ("negative imperative|imperativo.?neg", "verb.imperativo-neg"), ("imperat|command", "verb.imperativo"),
            ("subjun", "verb.subjuntivo"), ("condicional|conditional", "verb.condicional"), ("futur|ir a", "verb.futuro"), ("irregular|stem", "verb.irregular"),
            ("present", "verb.presente"), ("infinitive|tener que|hay que", "verb.infinitive"), ("possess", "possessives"), ("pronoun", "pronouns"),
            ("compar", "comparisons"), ("prepos", "prepositions"), ("connect|conjunc", "connectors"), ("register|usted|formal", "register"),
            ("order|missing|extra word", "word-order"), ("word|vocab|false friend|meaning", "word-choice"),
        ]
        for (re, id) in pairs where JS.test(re, s) { return id }
        return "word-choice"
    }

    // MARK: the course so far (Schoology, read 2026-11-09)

    /// Each skill's status: taught | reteach (taught, but the tutor starts from scratch) | not-yet.
    public static let courseStatus: [String: String] = [
        "accent.stress": "taught", "accent.question": "taught", "accent.diacritic": "taught", "accent.verb": "taught", "spelling": "taught", "punctuation": "taught",
        "agree.gender": "taught", "agree.number": "taught", "agree.verb": "taught", "articles": "taught", "ser-estar": "taught", "por-para": "taught", "tense.past": "taught",
        "gustar": "taught", "reflexive": "taught", "verb.presente": "taught", "verb.irregular": "taught", "verb.perfecto": "taught", "verb.indefinido": "taught",
        "verb.imperfecto": "not-yet", "verb.futuro": "taught", "verb.condicional": "taught", "verb.imperativo": "reteach", "verb.imperativo-neg": "reteach",
        "verb.subjuntivo": "not-yet", "verb.infinitive": "taught", "pronouns": "taught", "possessives": "taught", "comparisons": "taught", "prepositions": "taught",
        "connectors": "taught", "word-choice": "taught", "word-order": "taught", "register": "taught",
    ]
    public static let statusWords: [String: String] = ["taught": "taught", "reteach": "teach again from scratch", "not-yet": "not taught yet"]

    /// skills.yaml: { skills: [{ id, status }] } (the names and rules are the app's; the status is the user's to change).
    public static func parseSkills(_ text: String?) -> [String: String] {
        var status = courseStatus
        guard let text, let v = try? YValue.parse(text) else { return status }
        for s in v["skills"]?.list ?? [] {
            let id = s["id"]?.str ?? "", st = s["status"]?.str ?? ""
            if isSkill(id), statusWords[st] != nil { status[id] = st }
        }
        return status
    }

    public static func serializeSkills(_ status: [String: String]) -> String {
        var lines = ["# The Spanish skills Nexus tracks (the checker tags every mistake with one of these ids; the tutor, the memory and the grammar decks use them too).",
                     "# status: taught | reteach (taught, but the tutor teaches it again from scratch) | not-yet. Change a status here and the tutor follows it.", "skills:"]
        for s in skills { lines.append("  - { id: \(s.id), status: \(status[s.id] ?? "taught") }  # \(s.name)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// skills.yaml with one skill's status changed on its own line (the rest of the file, comments included, as it was); a file without
    /// that skill's line gets it added under `skills:`, and a missing or unreadable file is written whole.
    public static func setSkillStatus(_ text: String?, id: String, status: String) -> String {
        guard isSkill(id), statusWords[status] != nil else { return text ?? serializeSkills(courseStatus) }
        guard let text, (try? YValue.parse(text))?["skills"]?.list != nil else {
            var st = parseSkills(text); st[id] = status
            return serializeSkills(st)
        }
        var lines = text.components(separatedBy: "\n")
        let idRe = "(^|[{,\\s])id:\\s*['\"]?" + NSRegularExpression.escapedPattern(for: id) + "['\"]?\\s*[,}]"
        if let i = lines.firstIndex(where: { JS.test(idRe, $0) && JS.test("status:", $0) }) {
            lines[i] = JS.replace("status:\\s*['\"]?[A-Za-z-]+['\"]?", lines[i], "status: " + status)
            return lines.joined(separator: "\n")
        }
        guard let at = lines.firstIndex(where: { JS.test("^skills:\\s*$", $0) }) else {
            var st = parseSkills(text); st[id] = status
            return serializeSkills(st)
        }
        lines.insert("  - { id: \(id), status: \(status) }  # \(skillName(id))", at: at + 1)
        return lines.joined(separator: "\n")
    }

    // MARK: the units (study/units.yaml), grade 11 then grade 12

    public struct Unit: Equatable, Sendable { public let code, title, status, notes: String }
    public static let themes: [String: String] = ["G11": "Grade 11 · Ms. Barton", "G12": "Grade 12 · Ms. Panhausen (Miss Kathleen, Miss K)"]
    public static let units: [Unit] = [
        Unit(code: "G11.1", title: "Atributos personales", status: "done", notes: "Aug–Sept: present tense, ser/estar, tener, gustar, adjectives."),
        Unit(code: "G11.2", title: "Viajes en el mundo hispano · Rutina y ocio", status: "done", notes: "Sept–Dec: reflexives, stem-changing verbs, a first future."),
        Unit(code: "G11.3", title: "Celebraciones", status: "done", notes: "Jan–Feb: comparisons."),
        Unit(code: "G11.4", title: "El futuro", status: "done", notes: "March: futuro simple and condicional."),
        Unit(code: "G11.5", title: "El pretérito", status: "done", notes: "March–April: pretérito indefinido."),
        Unit(code: "G11.6", title: "Entretenimiento", status: "done", notes: "Then finals in June."),
        Unit(code: "G12.1", title: "Unidad repaso · Viajes", status: "done", notes: "Aug–Sept: pretérito perfecto (new); indefinido, gustar, present and possessives reviewed."),
        Unit(code: "G12.2", title: "El bienestar", status: "done", notes: "Sept–Oct: reflexives again, doler, imperative (positive and negative, informal)."),
        Unit(code: "G12.3", title: "La tecnología", status: "done", notes: "October: reading a novel; a past-tenses review (the imperfecto slide was skipped)."),
        Unit(code: "G12.4", title: "Mi mundo laboral", status: "partial", notes: "Now: futuro, ir a + infinitive. Current summatives."),
        Unit(code: "G12.5", title: "Entretenimiento", status: "not-yet", notes: "From late November."),
    ]
    /// The unit being taught now.
    public static var currentUnit: Unit? { units.first { $0.status == "partial" } }

    // MARK: the decks "Set up" makes

    public struct DeckSpec: Equatable, Sendable { public let id, title, kind: String; public let unit: String?; public let description: String }
    public static let decks: [DeckSpec] = [
        DeckSpec(id: "es-nucleo", title: "Vocab · Núcleo", kind: "vocab", unit: nil, description: "Everyday words that belong to no unit."),
        DeckSpec(id: "es-viajes", title: "Vocab · Viajes", kind: "vocab", unit: "G12.1", description: "Words met in Unidad repaso: Viajes."),
        DeckSpec(id: "es-bienestar", title: "Vocab · El bienestar", kind: "vocab", unit: "G12.2", description: "Words met in El bienestar."),
        DeckSpec(id: "es-tecnologia", title: "Vocab · La tecnología", kind: "vocab", unit: "G12.3", description: "Words met in La tecnología."),
        DeckSpec(id: "es-laboral", title: "Vocab · Mi mundo laboral", kind: "vocab", unit: "G12.4", description: "Words met in Mi mundo laboral."),
        DeckSpec(id: "es-presente", title: "Grammar · Presente", kind: "grammar", unit: nil, description: "Present endings, stem changes, yo-go and the fully irregular verbs; infinitive structures."),
        DeckSpec(id: "es-perfecto", title: "Grammar · Pretérito perfecto", kind: "grammar", unit: nil, description: "haber and the irregular participles."),
        DeckSpec(id: "es-indefinido", title: "Grammar · Pretérito indefinido", kind: "grammar", unit: nil, description: "Endings, strong stems, ser/ir, spelling changes."),
        DeckSpec(id: "es-futuro", title: "Grammar · Futuro y condicional", kind: "grammar", unit: nil, description: "The endings and the shared irregular stems."),
        DeckSpec(id: "es-imperativo", title: "Grammar · Imperativo", kind: "grammar", unit: nil, description: "Positive and negative commands."),
        DeckSpec(id: "es-pronombres", title: "Grammar · Pronombres", kind: "grammar", unit: nil, description: "Object and reflexive pronouns, possessives."),
        DeckSpec(id: "es-uso", title: "Grammar · Uso", kind: "grammar", unit: nil, description: "Choosing between forms: ser/estar, por/para, agreement, every tense contrast."),
    ]
    public static func isSpanishDeck(_ d: StudyDeck) -> Bool { d.language == "es" || d.id.hasPrefix("es-") }

    /// Tag groups for the cards (theme, part of speech, irregular family, phrase, skill); the unit is the deck, never a tag.
    public static let tags: [(group: String, values: [String])] = [
        ("tema", ["identidades", "experiencias", "ingenio", "organizacion", "planeta"]),
        ("pos", ["verbo", "sustantivo", "adjetivo", "conector", "adverbio", "pronombre"]),
        ("irr", ["e-ie", "o-ue", "e-i", "o-u", "yo-go", "zco", "ortografico", "fuerte", "futuro", "participio", "gerundio", "total", "otro"]),
    ]
    public static func cleanTag(_ t: String) -> String {
        let s = JS.replace(#"\s+"#, JS.strip(t.trimmed.lowercased()), "-")
        if s.isEmpty { return "" }
        if s == "frase" { return s }
        if let m = JS.match(#"^(tema|pos|irr|skill)::(.+)$"#, s) {
            if m[1] == "skill" { return "skill::" + toSkill(m[2]) }
            return (tags.first { $0.group == m[1] }?.values ?? []).contains(m[2]) ? s : ""
        }
        for g in tags where g.values.contains(s) { return "\(g.group)::\(s)" }
        return isSkill(s) ? "skill::" + s : ""
    }

    static func json(_ s: String) -> String { JSONValue.string(s).text }

    public static func deckFile(_ d: DeckSpec) -> String {
        var lines = ["# \(d.title): a Spanish \(d.kind == "vocab" ? "vocab" : "grammar") deck. One card per word or form; the deck can be flipped (English first) and keeps one schedule.",
                     "id: \(d.id)", "title: \(json(d.title))", "description: \(json(d.description))", "language: es", "kind: \(d.kind)"]
        if let u = d.unit { lines.append("unit: \(u)") }
        lines += ["flip: true", "columns:", "  - { key: $front, label: Spanish }", "  - { key: $back, label: English }", "cards: []"]
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: the files Set up writes (each only if it is not there)

    public static func course() -> String {
        func by(_ st: String) -> [String] { skills.filter { courseStatus[$0.id] == st }.map(\.name) }
        var lines = ["# Spanish ab initio: the course so far", "",
                     "Read from Schoology on 2026-11-09 (the grade 12 course and the archived grade 11 course). The tutor reads this file; correct it here when it is wrong.", "",
                     "## Teachers", "", "- Grade 11: Ms. Barton.", "- Grade 12: Ms. Panhausen (also Miss Kathleen, Miss K). Grade 12 re-covers some of grade 11.", "",
                     "## Units", ""]
        lines += units.map { u in "- \(u.code.hasPrefix("G11") ? "Grade 11" : "Grade 12"), \(u.title) (\(u.status == "done" ? "done" : u.status == "partial" ? "now" : "next")): \(u.notes)" }
        lines += ["", "## Grammar", "", "- Taught: \(by("taught").joined(separator: ", ")).",
                  "- Teach again from scratch: \(by("reteach").joined(separator: ", ")) (taught in El bienestar, but the user wants them taught from the start).",
                  "- Not taught yet: \(by("not-yet").joined(separator: ", ")). Teach them only when the user asks.", "",
                  "## The exam", "", "- IB Spanish ab initio. Paper 1 (writing): 1 hour, two tasks of 70 to 150 words, each marked on A Language /6, B Message /6, C Conceptual understanding /3.", ""]
        return lines.joined(separator: "\n")
    }

    public struct ProfileBlock: Equatable, Sendable { public let key, title: String; public let cap: Int; public let mine: Bool }
    public static let profileBlocks: [ProfileBlock] = [
        ProfileBlock(key: "strengths", title: "Strengths", cap: 600, mine: false), ProfileBlock(key: "working", title: "Working on", cap: 600, mine: false),
        ProfileBlock(key: "mistakes", title: "Recurring mistakes", cap: 800, mine: false), ProfileBlock(key: "taught", title: "Recently taught", cap: 600, mine: false),
        ProfileBlock(key: "next", title: "Next up", cap: 400, mine: false), ProfileBlock(key: "learn", title: "How I like to learn", cap: 600, mine: false),
        ProfileBlock(key: "mine", title: "My notes", cap: 2000, mine: true),
    ]
    static let profileNote = "<!-- Claude rewrites every block but \"My notes\" after each tutor chat and shows what changed. \"My notes\" is yours: Claude never changes it. -->"

    public static func profileTemplate() -> String {
        let body = ["learn": "- Explanations in English, examples in Spanish.\n- Teach the imperative (positive and negative) from scratch.\n- Correct me exactly: show what was wrong and why.", "mine": ""]
        var lines = ["# Spanish: my profile", "", profileNote, ""]
        for b in profileBlocks { lines += ["## \(b.title)", "", body[b.key] ?? "", ""] }
        return lines.joined(separator: "\n")
    }

    /// Every file Set up writes, by its path inside the workstream's folder, in the laptop's order.
    public static func setupFiles() -> [(path: String, text: String)] {
        var f: [(path: String, text: String)] = [
            ("study/study.yaml", "# Study settings for this workstream.\nlanguage: spanish\nsheets: files\n"),
            ("study/units.yaml", "# The Spanish ab initio units, grade 11 then grade 12 (status: done, partial, not-yet).\nunits:\n"
                + units.map { "  - { code: \($0.code), title: \(json($0.title)), status: \($0.status), notes: \(json($0.notes)) }" }.joined(separator: "\n") + "\n"),
            (P.skills, serializeSkills(courseStatus)), (P.course, course()), (P.profile, profileTemplate()),
            (P.prompts, "# Your tutor's writing prompts (Nexus never writes prompts). Add them in Study › Writing.\nprompts: []\n"),
            (P.readme, ["# Spanish study files", "", "Nexus keeps these as plain files; you can open and edit any of them.", "",
                        "- `profile.md`: what the tutor knows about you (always read at the start of a chat). Claude rewrites it after each chat and shows the changes; \"My notes\" is yours.",
                        "- `course.md`: what has been taught, by year and teacher. `skills.yaml`: every skill and whether it has been taught.",
                        "- `skills/<skill>.md`: one note per skill, linked to the chats and pieces where it came up.", "- `log/<month>.yaml`: every sentence checked, with its fixes (never rewritten).",
                        "- `stats.yaml`: the numbers per skill, counted by the app from the log.", "- `chats/`: each tutor chat, with its summary at the top.",
                        "- `prompts.yaml` and `writing/`: your tutor's prompts and your answers with their marks.", ""].joined(separator: "\n")),
        ]
        for d in decks { f.append(("study/decks/\(d.id).yaml", deckFile(d))) }
        return f
    }

    /// study/study.yaml's `language` ("spanish" makes the Study tab a Spanish one), "" when it has none or does not parse.
    public static func studyLanguage(_ text: String?) -> String {
        guard let text, let v = try? YValue.parse(text) else { return "" }
        return v["language"]?.str.trimmed.lowercased() ?? ""
    }

    /// The text study.yaml should have after Set up: the file with `language: spanish` added when it says another language or none.
    public static func studyYamlWithSpanish(_ current: String) -> String? {
        if studyLanguage(current) == "spanish" { return nil }
        var lines = current.components(separatedBy: "\n")
        while let last = lines.last, last.trimmed.isEmpty { lines.removeLast() }
        // a language line already there (another language) is changed rather than repeated: a key twice does not parse
        if let i = lines.firstIndex(where: { $0.hasPrefix("language:") }) { lines[i] = "language: spanish" } else { lines.append("language: spanish") }
        return lines.joined(separator: "\n") + "\n"
    }
}
