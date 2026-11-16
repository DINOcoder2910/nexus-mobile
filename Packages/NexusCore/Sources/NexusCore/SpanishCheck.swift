import Foundation

/// Spanish › the sentence checker, pure: a port of the laptop's renderer/src/spanishcheck.js (and lang-service.js's accent variants).
/// Three layers meet here: the device's Spanish dictionary and LanguageTool give marks at once, and Claude's answer (Haiku; the prompt and
/// the answer's shape below) adds what rules miss (ser/estar, the tense for the meaning, a real word in the wrong place), the structures
/// used and every word's meaning. `merge` makes one list of marks over the sentence; where Claude and the algorithm disagree, Claude wins.
/// The log (study/spanish/log/<month>.yaml) keeps every check, and the numbers per skill (stats.yaml) are counted from it here.
/// Places in the sentence are UTF-16 offsets, as JavaScript's.
public enum SpanishCheck {
    public static func onlyAccents(_ a: String, _ b: String) -> Bool {
        a != b && JS.strip(a).lowercased() == JS.strip(b).lowercased() && a.lowercased() != b.lowercased()
    }

    static let notVerb = #"^(aqui|alli|ahi|asi|si|mi|ti|adios|mama|papa|bebe|cafe|sofa|menu|tambien|despues|alla|aca|jamas|ademas|detras|atras|quiza)$"#
    /// Which accent skill a fix is: a question word, a word the accent changes, a verb ending, else the stress rule.
    static func accentSkill(_ wrong: String, _ right: String) -> String {
        let r = right.lowercased(), s = JS.strip(r)
        if JS.test("^(que|como|donde|cuando|cuanto|quien|cual)$", s, ci: true) { return "accent.question" }
        if JS.test("^(el|tu|mi|si|mas|se|te|esta|de|solo)$", s, ci: true) { return "accent.diacritic" }
        let n = JS.len(r)
        let verbish = JS.test("^est(á|ás|án)$", r) || (JS.test("(ió|ó)$", r) && n >= 4) || (JS.test("é$", r) && n >= 5) || (JS.test("[^aeiou]í$", r) && n >= 4) || (JS.test("(rá|rás|rán|ré)$", r) && n >= 5)
        return verbish && !JS.test(notVerb, s, ci: true) && JS.test("(e|o|i|as|a|an|s)$", wrong.lowercased()) ? "accent.verb" : "accent.stress"
    }
    public static func kindOf(_ skill: String) -> String { skill.hasPrefix("accent.") ? "accent" : "error" }

    // MARK: marks

    /// One mark over the sentence: a mistake ("error"), an accent ("accent") or something done well ("good"). `s` is -1 for a mistake
    /// whose words are not in the sentence (listed, not placed).
    public struct Mark: Equatable, Sendable, Identifiable {
        public var s: Int
        public var e: Int
        public var wrong: String
        public var right: String
        public var skill: String
        public var kind: String
        public var why: String
        /// dictionary | languagetool | claude
        public var by: String
        public var id: String { "\(s):\(e):\(kind):\(wrong)" }
        public init(s: Int, e: Int, wrong: String, right: String, skill: String, kind: String, why: String, by: String) {
            self.s = s; self.e = e; self.wrong = wrong; self.right = right; self.skill = skill; self.kind = kind; self.why = why; self.by = by
        }
    }

    /// A word the dictionary does not know: where it is, the same word with its accents right (cafe -> café), its suggestions.
    public struct SpellWord: Equatable, Sendable {
        public var word: String
        public var start: Int
        public var end: Int
        public var accent: String?
        public var suggestions: [String]
        public init(word: String, start: Int, end: Int, accent: String?, suggestions: [String]) {
            self.word = word; self.start = start; self.end = end; self.accent = accent; self.suggestions = suggestions
        }
    }

    public static let wordPattern = "[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]+"
    /// The words of a sentence, with where each starts (UTF-16).
    public static func words(_ text: String) -> [(word: String, at: Int)] { JS.all(wordPattern, text).map { (word: $0.text, at: $0.at) } }

    /// The words a misspelling could have been with its accents right: one acute accent added (or moved), ü for u, ñ for n, a wrong
    /// accent taken off (lang-service.js accentVariants).
    public static func accentVariants(_ word: String) -> [String] {
        let vowelAccent: [Character: Character] = ["a": "á", "e": "é", "i": "í", "o": "ó", "u": "ú"]
        let unaccent: [Character: Character] = ["á": "a", "é": "e", "í": "i", "ó": "o", "ú": "u", "ü": "u"]
        let lo = word.lowercased()
        let bare = Array(String(lo.map { unaccent[$0] ?? $0 }))
        var out: [String] = [], seen = Set<String>()
        func add(_ s: String) { if seen.insert(s).inserted { out.append(s) } }
        if String(bare) != lo { add(String(bare)) }
        for i in bare.indices {
            if let a = vowelAccent[bare[i]] { var x = bare; x[i] = a; add(String(x)) }
            if bare[i] == "u" { var x = bare; x[i] = "ü"; add(String(x)) }
            if bare[i] == "n" {
                var y = bare; y[i] = "ñ"; add(String(y))
                for j in bare.indices { if let a = vowelAccent[bare[j]] { var x = bare; x[i] = "ñ"; x[j] = a; add(String(x)) } }
            }
        }
        out.removeAll { $0 == lo }
        let cap = word.first.map { String($0) == String($0).uppercased() && String($0) != String($0).lowercased() } ?? false
        return out.map { cap ? $0.prefix(1).uppercased() + $0.dropFirst() : $0 }
    }

    /// The dictionary's marks: an accent fix with its skill, or a word it does not know.
    public static func spellMarks(_ words: [SpellWord]) -> [Mark] {
        words.filter { !$0.word.isEmpty }.map { w in
            if let a = w.accent {
                let sk = accentSkill(w.word, a)
                return Mark(s: w.start, e: w.end, wrong: w.word, right: a, skill: sk, kind: "accent", why: "Missing or wrong accent: \(a).", by: "dictionary")
            }
            let why = w.suggestions.isEmpty ? "Not a Spanish word." : "Not a Spanish word; did you mean \(w.suggestions.prefix(3).joined(separator: ", "))?"
            return Mark(s: w.start, e: w.end, wrong: w.word, right: w.suggestions.first ?? "", skill: "spelling", kind: "error", why: why, by: "dictionary")
        }
    }

    /// One LanguageTool match ({ offset, length, message, replacements: [{ value }], rule: { id, category: { id } } }).
    public struct LTMatch: Equatable, Sendable {
        public var offset: Int
        public var length: Int
        public var message: String
        public var replacements: [String]
        public var ruleId: String
        public var category: String
        public init(offset: Int, length: Int, message: String, replacements: [String], ruleId: String, category: String) {
            self.offset = offset; self.length = length; self.message = message; self.replacements = replacements; self.ruleId = ruleId; self.category = category
        }
        /// LanguageTool's answer (POST /v2/check): its matches, at most 3 replacements each.
        public static func list(_ json: JSONValue) -> [LTMatch] {
            (json["matches"]?.array ?? []).compactMap { m in
                guard let o = m["offset"]?.number, let l = m["length"]?.number else { return nil }
                return LTMatch(offset: Int(o), length: Int(l), message: m["message"]?.string ?? "",
                               replacements: (m["replacements"]?.array ?? []).prefix(3).compactMap { $0["value"]?.string },
                               ruleId: m["rule"]?["id"]?.string ?? "", category: m["rule"]?["category"]?["id"]?.string ?? "")
            }
        }
    }

    public static func ltMarks(_ text: String, _ matches: [LTMatch]) -> [Mark] {
        var out: [Mark] = []
        for m in matches {
            let wrong = JS.slice(text, m.offset, m.offset + m.length), right = m.replacements.first ?? ""
            let cat = m.category.uppercased(), rid = m.ruleId
            var skill = "word-choice"
            if !right.isEmpty && onlyAccents(wrong, right) { skill = accentSkill(wrong, right) }
            else if cat == "TYPOS" || JS.test("MORFOLOGIK|SPELL", rid, ci: true) { skill = "spelling" }
            else if cat == "PUNCTUATION" || cat == "TYPOGRAPHY" || JS.test("PUNT|INTERROG|EXCLAM", rid, ci: true) { skill = "punctuation" }
            else if JS.test("CONCORD|AGREEMENT|GEN", rid, ci: true) { skill = JS.test("NUM|PLURAL", rid, ci: true) ? "agree.number" : "agree.gender" }
            else if cat == "GRAMMAR" { skill = Spanish.toSkill(rid + " " + m.message) }
            if cat == "STYLE" || cat == "REDUNDANCY" || (cat == "CASING" && right.isEmpty) { continue } // style advice is not a mistake
            out.append(Mark(s: m.offset, e: m.offset + m.length, wrong: wrong, right: right, skill: skill, kind: kindOf(skill), why: m.message.trimmed, by: "languagetool"))
        }
        return out
    }

    // MARK: Claude: the prompt, the answer's shape, reading it

    public struct AI: Equatable, Sendable {
        public struct Mistake: Equatable, Sendable {
            public var wrong, right, skill, why: String
            public init(wrong: String, right: String, skill: String, why: String) { self.wrong = wrong; self.right = right; self.skill = skill; self.why = why }
        }
        public struct Good: Equatable, Sendable { public var text, skill, why: String }
        public struct Structure: Equatable, Sendable { public var name, text: String }
        public struct Word: Equatable, Sendable {
            public var word, lemma, form, meaning: String
            public init(word: String, lemma: String = "", form: String = "", meaning: String = "") { self.word = word; self.lemma = lemma; self.form = form; self.meaning = meaning }
        }
        public var corrected: String
        public var mistakes: [Mistake]
        public var good: [Good]
        public var structures: [Structure]
        public var words: [Word]
        public init(corrected: String, mistakes: [Mistake] = [], good: [Good] = [], structures: [Structure] = [], words: [Word] = []) {
            self.corrected = corrected; self.mistakes = mistakes; self.good = good; self.structures = structures; self.words = words
        }
    }

    public static let system = "You check Spanish written by an IB Spanish ab initio student (a beginner). You are exact: every mistake is found, nothing correct is marked wrong, and accents count. Explanations are short, in English."

    /// The answer's shape, said in the prompt (the laptop passes it as a schema; here it is asked for as JSON).
    static let shape = #"{"corrected": "the whole sentence, corrected (the same as the input when it is right)", "mistakes": [{"wrong": "the exact wrong text as it appears in the sentence", "right": "what it should be", "skill": "one skill id", "why": "one short English sentence: the rule"}], "good": [{"text": "words from the sentence", "skill": "a skill id", "why": "..."}], "structures": [{"name": "e.g. reflexive, pretérito indefinido, gustar-type, ir a + infinitive", "text": "the words that make it"}], "words": [{"word": "...", "lemma": "base form", "form": "e.g. \"ir / ser, pretérito indefinido, yo\" or \"feminine plural noun\"", "meaning": "the English meaning here"}]}"#

    public static func prompt(text: String, question: String = "", found: [Mark] = [], taught: [String: String] = [:]) -> String {
        let notYet = Spanish.skills.filter { taught[$0.id] == "not-yet" }.map(\.name)
        var lines = ["(Nexus Spanish check)", "", "The sentence: \(text)", question.isEmpty ? "" : "It answers this question: \(question)", ""]
        lines.append(found.isEmpty
            ? "The spell checker and the grammar checker found nothing; look anyway for what they cannot see (ser/estar, por/para, the tense for the meaning, a real word in the wrong place, agreement, missing words)."
            : "A spell checker and a grammar checker flagged these (keep the right ones, drop any that are wrong):\n" + found.map { "- \"\($0.wrong)\" -> \"\($0.right)\" (\($0.why))" }.joined(separator: "\n"))
        lines += ["", "Rules:", "- mistakes: each one separately, `wrong` copied exactly from the sentence, `right` what replaces it, `skill` one id below, `why` the rule in one short English sentence.",
                  "- A missing or wrong accent is a mistake (skill accent.stress, accent.question, accent.diacritic or accent.verb). So is a missing ¿ or ¡ (punctuation).",
                  "- good: up to 3 things done right that are worth noticing (a correct tricky form), with the skill id.",
                  "- structures: the grammar the sentence uses (tense names in Spanish, plus reflexive, gustar-type, ir a + infinitive, comparisons, imperative and so on).",
                  "- words: every content word with its base form, what form it is, and its meaning here in English.",
                  notYet.isEmpty ? "" : "- Not taught yet (do not expect them; mark them only when they are wrong): \(notYet.joined(separator: ", ")).",
                  "", "Skill ids: " + Spanish.skills.map(\.id).joined(separator: ", "),
                  "", "Answer with only one JSON object, in this shape: " + shape]
        // (as the laptop: the empty lines are dropped)
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The answer, made safe: known skill ids, only usable entries.
    public static func readCheck(_ text: String, _ ans: JSONValue?) -> AI? {
        guard let ans, ans.object != nil else { return nil }
        func s(_ v: JSONValue?) -> String { v?.string ?? (v?.number.map { JSONValue.format($0) } ?? "") }
        func skill(_ v: JSONValue?) -> String { let x = s(v); return Spanish.isSkill(x) ? x : Spanish.toSkill(x) }
        let mistakes = (ans["mistakes"]?.array ?? []).filter { !s($0["wrong"]).trimmed.isEmpty }.map {
            AI.Mistake(wrong: s($0["wrong"]).trimmed, right: s($0["right"]).trimmed, skill: skill($0["skill"]), why: s($0["why"]).trimmed)
        }
        let corrected = s(ans["corrected"]).trimmed
        return AI(corrected: corrected.isEmpty ? text : corrected, mistakes: mistakes,
                  good: (ans["good"]?.array ?? []).filter { !s($0["text"]).isEmpty }.prefix(4).map { AI.Good(text: s($0["text"]), skill: skill($0["skill"]), why: s($0["why"])) },
                  structures: (ans["structures"]?.array ?? []).filter { !s($0["name"]).isEmpty }.prefix(8).map { AI.Structure(name: s($0["name"]), text: s($0["text"])) },
                  words: (ans["words"]?.array ?? []).filter { !s($0["word"]).isEmpty }.prefix(40).map { AI.Word(word: s($0["word"]), lemma: s($0["lemma"]), form: s($0["form"]), meaning: s($0["meaning"])) })
    }

    /// A fenced or bare JSON object in a reply.
    public static func jsonFrom(_ text: String) -> JSONValue? {
        let body: String
        if let m = JS.match("```(?:json)?\\s*([\\s\\S]*?)```", text) { body = m[1] }
        else if let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b { body = String(text[a...b]) }
        else { return nil }
        return try? JSONValue.parse(body)
    }

    // MARK: one list of marks

    static func place(_ text: String, _ needle: String, _ used: [(Int, Int)]) -> Int {
        if needle.isEmpty { return -1 }
        let n = JS.len(needle)
        var i = JS.indexOf(text, needle)
        while i >= 0 && used.contains(where: { i < $0.1 && i + n > $0.0 }) { i = JS.indexOf(text, needle, from: i + 1) }
        if i < 0 { i = JS.indexOf(text.lowercased(), needle.lowercased()) }
        return i
    }

    /// The AI's mistakes placed where their words are, then the algorithm's where nothing overlaps (before the AI answers, `ai` is nil and
    /// the algorithm's marks stand alone). An algorithm mark the AI did not make is dropped, unless it is a plain accent fix it missed.
    public static func merge(_ text: String, _ algo: [Mark], _ ai: AI?) -> [Mark] {
        var marks: [Mark] = [], used: [(Int, Int)] = []
        if let ai {
            for m in ai.mistakes {
                let s = place(text, m.wrong, used)
                if s < 0 { marks.append(Mark(s: -1, e: -1, wrong: m.wrong, right: m.right, skill: m.skill, kind: kindOf(m.skill), why: m.why, by: "claude")); continue }
                let e = s + JS.len(m.wrong)
                used.append((s, e))
                marks.append(Mark(s: s, e: e, wrong: JS.slice(text, s, e), right: m.right, skill: m.skill, kind: kindOf(m.skill), why: m.why, by: "claude"))
            }
            for a in algo where a.kind == "accent" && a.by == "dictionary" && !used.contains(where: { a.s < $0.1 && a.e > $0.0 })
                && JS.strip(ai.corrected).contains(JS.strip(a.right)) && !ai.corrected.contains(a.wrong + " ") {
                used.append((a.s, a.e)); marks.append(a)
            }
            for g in ai.good {
                let s = place(text, g.text, used)
                if s >= 0 { let e = s + JS.len(g.text); used.append((s, e)); marks.append(Mark(s: s, e: e, wrong: g.text, right: "", skill: g.skill, kind: "good", why: g.why, by: "claude")) }
            }
        } else {
            for a in algo {
                if used.contains(where: { a.s < $0.1 && a.e > $0.0 }) { continue }
                used.append((a.s, a.e)); marks.append(a)
            }
        }
        return marks.enumerated().sorted { $0.element.s != $1.element.s ? $0.element.s < $1.element.s : $0.offset < $1.offset }.map(\.element)
    }

    /// The sentence as runs, for drawing: the text and its mark (nil for plain words).
    public static func runs(_ text: String, _ marks: [Mark]) -> [(text: String, mark: Mark?)] {
        var out: [(text: String, mark: Mark?)] = [], at = 0
        let placed = marks.filter { $0.s >= 0 }.enumerated().sorted { $0.element.s != $1.element.s ? $0.element.s < $1.element.s : $0.offset < $1.offset }.map(\.element)
        for m in placed {
            if m.s < at { continue }
            if m.s > at { out.append((text: JS.slice(text, at, m.s), mark: nil)) }
            out.append((text: JS.slice(text, m.s, m.e), mark: m))
            at = m.e
        }
        if at < JS.len(text) { out.append((text: JS.slice(text, at), mark: nil)) }
        return out
    }

    /// The corrected sentence from the marks alone (before Claude's own corrected text arrives).
    public static func corrected(_ text: String, _ marks: [Mark]) -> String {
        var out = "", at = 0
        let fixes = marks.filter { $0.s >= 0 && $0.kind != "good" && !$0.right.isEmpty }.enumerated()
            .sorted { $0.element.s != $1.element.s ? $0.element.s < $1.element.s : $0.offset < $1.offset }.map(\.element)
        for m in fixes {
            if m.s < at { continue }
            out += JS.slice(text, at, m.s) + m.right
            at = m.e
        }
        return out + JS.slice(text, at)
    }
    public static func mistakesOf(_ marks: [Mark]) -> [Mark] { marks.filter { $0.kind != "good" } }

    // MARK: the log: study/spanish/log/<YYYY-MM>.yaml

    public struct LogMistake: Equatable, Sendable {
        public var skill, wrong, right, why: String
        public init(skill: String, wrong: String = "", right: String = "", why: String = "") { self.skill = skill; self.wrong = wrong; self.right = right; self.why = why }
    }
    public struct Entry: Equatable, Sendable, Identifiable {
        public var at: String
        public var source: String
        public var text: String
        public var fixed: String
        public var question: String
        public var chat: String
        public var mistakes: [LogMistake]
        public var good: [String]
        public var structures: [String]
        public var words: [AI.Word]
        /// Claude did not answer: only the algorithm checked it.
        public var partial: Bool
        public var id: String { at }
        public init(at: String, source: String = "checker", text: String, fixed: String = "", question: String = "", chat: String = "", mistakes: [LogMistake] = [], good: [String] = [],
                    structures: [String] = [], words: [AI.Word] = [], partial: Bool = false) {
            self.at = at; self.source = source; self.text = text; self.fixed = fixed.isEmpty ? text : fixed; self.question = question; self.chat = chat
            self.mistakes = mistakes; self.good = good; self.structures = structures; self.words = words; self.partial = partial
        }
    }

    /// A finished check, for the log.
    public struct Result: Equatable, Sendable {
        public var marks: [Mark]
        public var corrected: String
        public var structures: [AI.Structure]
        public var words: [AI.Word]
        public var partial: Bool
        public init(marks: [Mark], corrected: String, structures: [AI.Structure] = [], words: [AI.Word] = [], partial: Bool = false) {
            self.marks = marks; self.corrected = corrected; self.structures = structures; self.words = words; self.partial = partial
        }
    }

    public static func logEntry(at: String, source: String = "checker", text: String, question: String = "", result: Result, chat: String = "") -> Entry {
        let marks = result.marks
        return Entry(at: at, source: source, text: text, fixed: result.corrected.isEmpty ? corrected(text, marks) : result.corrected, question: question, chat: chat,
                     mistakes: mistakesOf(marks).map { LogMistake(skill: $0.skill, wrong: $0.wrong, right: $0.right, why: $0.why) },
                     good: marks.filter { $0.kind == "good" }.map(\.skill), structures: result.structures.map(\.name), words: result.words, partial: result.partial)
    }

    /// The log file read: ok false when it does not parse (then nothing is written over it).
    public static func parseLog(_ text: String?) -> (ok: Bool, entries: [Entry]) {
        guard let text else { return (true, []) }
        guard let v = try? YValue.parse(text) else { return (false, []) }
        var out: [Entry] = []
        for e in v["entries"]?.list ?? [] {
            let t = e["text"]?.str ?? "", at = e["at"]?.str ?? ""
            if t.isEmpty || at.isEmpty { continue }
            out.append(Entry(at: at, source: e["source"]?.str.isEmpty == false ? e["source"]!.str : "checker", text: t, fixed: e["fixed"]?.str ?? t,
                             question: e["question"]?.str ?? "", chat: e["chat"]?.str ?? "",
                             mistakes: (e["mistakes"]?.list ?? []).compactMap { m in
                                 let sk = m["skill"]?.str ?? ""
                                 return sk.isEmpty ? nil : LogMistake(skill: sk, wrong: m["wrong"]?.str ?? "", right: m["right"]?.str ?? "", why: m["why"]?.str ?? "")
                             },
                             good: e["good"]?.strings ?? [], structures: e["structures"]?.strings ?? [],
                             words: (e["words"]?.list ?? []).map { AI.Word(word: $0["word"]?.str ?? "", lemma: $0["lemma"]?.str ?? "", form: $0["form"]?.str ?? "", meaning: $0["meaning"]?.str ?? "") },
                             partial: e["partial"] == .bool(true)))
        }
        return (true, out)
    }

    static func yaml(_ e: Entry) -> YValue {
        var m: [YValue.YPair] = [.init("at", .string(e.at)), .init("source", .string(e.source)), .init("text", .string(e.text)), .init("fixed", .string(e.fixed)),
                                 .init("mistakes", .list(e.mistakes.map { .map([.init("skill", .string($0.skill)), .init("wrong", .string($0.wrong)), .init("right", .string($0.right)), .init("why", .string($0.why))]) })),
                                 .init("good", .list(e.good.map { .string($0) }))]
        if !e.question.isEmpty { m.append(.init("question", .string(e.question))) }
        if !e.chat.isEmpty { m.append(.init("chat", .string(e.chat))) }
        if !e.structures.isEmpty { m.append(.init("structures", .list(e.structures.map { .string($0) }))) }
        if !e.words.isEmpty { m.append(.init("words", .list(e.words.map { .map([.init("word", .string($0.word)), .init("lemma", .string($0.lemma)), .init("form", .string($0.form)), .init("meaning", .string($0.meaning))]) }))) }
        if e.partial { m.append(.init("partial", .bool(true))) }
        return .map(m)
    }

    static let logHeader = "# Written by Nexus (Spanish): every sentence checked this month, oldest first. Never rewritten, only added to.\n"

    public static func serializeLog(_ entries: [Entry]) -> String {
        logHeader + YValue.map([.init("entries", .list(entries.map(yaml)))]).yaml
    }

    /// The log file with one more entry at its end: the lines already there stay as they were (so a sync merge sees only an addition).
    /// nil when the file does not parse.
    public static func appendToLog(_ text: String?, _ e: Entry) -> String? {
        guard let text, !text.trimmed.isEmpty else { return serializeLog([e]) }
        let p = parseLog(text)
        guard p.ok else { return nil }
        var lines = text.components(separatedBy: "\n")
        while let last = lines.last, last.trimmed.isEmpty { lines.removeLast() }
        // `entries: []` (or no entries key): written again whole
        guard let k = lines.firstIndex(where: { $0.hasPrefix("entries:") }), JS.test(#"^entries:\s*(#.*)?$"#, lines[k]) else {
            return serializeLog(p.entries + [e])
        }
        var item: [String] = []
        SpanishYAML.emit(.list([yaml(e)]), indent: 2, into: &item)
        // where the entries block ends (a later top-level key)
        var end = k + 1
        while end < lines.count, lines[end].trimmed.isEmpty || lines[end].hasPrefix(" ") || lines[end].hasPrefix("-") || lines[end].hasPrefix("#") { end += 1 }
        var at = end
        while at > k + 1, lines[at - 1].trimmed.isEmpty { at -= 1 }
        // a list at no indent (entries:\n- at: …) gets its items at no indent too
        if lines[(k + 1)..<at].contains(where: { $0.hasPrefix("- ") }) { item = item.map { String($0.dropFirst(2)) } }
        lines.insert(contentsOf: item, at: at)
        let out = lines.joined(separator: "\n") + "\n"
        guard parseLog(out).entries.count == p.entries.count + 1 else { return serializeLog(p.entries + [e]) }
        return out
    }

    public static func monthOf(_ iso: String) -> String { String(iso.prefix(7)) }

    // MARK: the numbers per skill, from the log

    public struct Stat: Equatable, Sendable {
        public var tries: Int
        public var mistakes: Int
        public var accuracy: Int
        public var last: String
        /// new | weak | improving | solid
        public var status: String
        /// 0-1: how much it needs practice now.
        public var due: Double
    }
    public static let statWords = ["new": "just started", "weak": "weak", "improving": "improving", "solid": "solid"]

    /// Tries, mistakes, accuracy over the last 20 tries, last seen, status, a due score; in the order each skill was first seen.
    public static func skillStats(_ entries: [Entry], now: Double) -> [(id: String, stat: Stat)] {
        struct Acc { var tries = 0, mistakes = 0; var recent: [Int] = []; var last = "", lastRight = "" }
        var by: [String: Acc] = [:], order: [String] = []
        let sorted = entries.enumerated().sorted { jsLess($0.element.at, $1.element.at) || ($0.element.at == $1.element.at && $0.offset < $1.offset) }.map(\.element)
        for e in sorted {
            let wrong = Set(e.mistakes.map(\.skill))
            var used: [String] = []
            for x in e.mistakes.map(\.skill) + e.good.filter(Spanish.isSkill) where !used.contains(x) { used.append(x) }
            for id in used {
                if by[id] == nil { by[id] = Acc(); order.append(id) }
                by[id]!.tries += 1
                if wrong.contains(id) { by[id]!.mistakes += 1 }
                by[id]!.recent.append(wrong.contains(id) ? 0 : 1)
                if by[id]!.recent.count > 20 { by[id]!.recent.removeFirst() }
                by[id]!.last = e.at
                if !wrong.contains(id) { by[id]!.lastRight = e.at }
            }
        }
        let day = 86_400_000.0
        return order.map { id in
            let s = by[id]!
            let acc = Double(s.recent.reduce(0, +)) / Double(s.recent.count)
            let days = s.lastRight.isEmpty ? 30 : max(0, (now - (JS.parseLocal(s.lastRight) ?? now)) / day)
            let status = s.tries < 3 ? (acc >= 0.67 ? "new" : "weak") : acc >= 0.85 && s.tries >= 5 ? "solid" : acc < 0.6 ? "weak" : "improving"
            let hold = 2 + 25 * acc * acc * min(1, Double(s.tries) / 10)
            let due = JS.round(100 * min(1, 0.6 * (1 - acc) + 0.4 * min(1, days / hold))) / 100
            return (id: id, stat: Stat(tries: s.tries, mistakes: s.mistakes, accuracy: Int(JS.round(acc * 100)), last: s.last, status: status, due: due))
        }
    }

    /// The skills that need practice most, first.
    public static func weakest(_ stats: [(id: String, stat: Stat)], _ n: Int = 5) -> [(id: String, stat: Stat)] {
        Array(stats.enumerated().sorted { a, b in
            if a.element.stat.due != b.element.stat.due { return a.element.stat.due > b.element.stat.due }
            if a.element.stat.accuracy != b.element.stat.accuracy { return a.element.stat.accuracy < b.element.stat.accuracy }
            return a.offset < b.offset
        }.map(\.element).prefix(n))
    }

    public static func serializeStats(_ stats: [(id: String, stat: Stat)], nowIso: String) -> String {
        let rows = stats.enumerated().sorted { $0.element.stat.due != $1.element.stat.due ? $0.element.stat.due > $1.element.stat.due : $0.offset < $1.offset }.map(\.element)
        let v = YValue.map([.init("skills", .map(rows.map { r in
            .init(r.id, .map([.init("name", .string(Spanish.skillName(r.id))), .init("tries", .int(r.stat.tries)), .init("mistakes", .int(r.stat.mistakes)),
                              .init("accuracy", .int(r.stat.accuracy)), .init("last", .string(r.stat.last)), .init("status", .string(r.stat.status)), .init("due", .double(r.stat.due))]))
        }))])
        return "# Written by Nexus (Spanish) from the log, \(nowIso): per skill, tries, mistakes, accuracy over the last 20 tries (%), last seen, status and due (0-1: how much it needs practice now).\n" + v.yaml
    }

    /// Clean sentences in a row, newest back (the checker's counter).
    public static func streak(_ entries: [Entry]) -> Int {
        var n = 0
        for e in entries.reversed() { if !e.mistakes.isEmpty { break }; n += 1 }
        return n
    }

    /// The share of taught skills that are solid.
    public static func solidShare(_ stats: [(id: String, stat: Stat)], _ status: [String: String]) -> (solid: Int, of: Int) {
        let taught = Spanish.skills.filter { status[$0.id] != "not-yet" }
        let solid = taught.filter { s in stats.first { $0.id == s.id }?.stat.status == "solid" }
        return (solid: solid.count, of: taught.count)
    }

    // MARK: Move to chat, and the checker's result as the tutor reads it

    public static func moveToChatText(_ entries: [Entry]) -> String {
        var lines = ["Here are some sentences I checked. Look at what went wrong across them, explain it, and then give me practice on it.", ""]
        for (i, e) in entries.enumerated() {
            lines.append("\(i + 1). I wrote: \(e.text)")
            if !e.question.isEmpty { lines.append("   (answering: \(e.question))") }
            if !e.mistakes.isEmpty {
                lines.append("   Fixed: \(e.fixed)")
                for m in e.mistakes { lines.append("   - \(m.wrong) -> \(m.right) [\(m.skill)] \(m.why)".trimEnd) }
            } else { lines.append("   No mistakes.") }
        }
        return lines.joined(separator: "\n")
    }

    public static func resultForTutor(_ e: Entry) -> String {
        var lines = ["My answer: \(e.text)"]
        if e.mistakes.isEmpty { lines.append("The checker found no mistakes.") }
        else {
            lines.append("The checker's correction: \(e.fixed)")
            for m in e.mistakes { lines.append("- \(m.wrong) -> \(m.right) [\(m.skill)] \(m.why)".trimEnd) }
        }
        if !e.good.isEmpty { lines.append("Done right: " + e.good.joined(separator: ", ")) }
        if e.partial { lines.append("(Only the spell and grammar checkers ran; Claude could not check it.)") }
        return lines.joined(separator: "\n")
    }
}
