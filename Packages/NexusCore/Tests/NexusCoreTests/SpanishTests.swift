import XCTest
@testable import NexusCore

/// Spanish on the iPhone and iPad (SpanishCore, SpanishCards, SpanishCheck, SpanishMemory, SpanishGrade). The golden half checks the port
/// against what the laptop's own spanishcore.js, spanishcheck.js, spanishmemory.js, spanishgrade.js and lang-service.js give
/// (SpanishGolden.swift, tools/spanish-golden/gen.mjs); the rest is the laptop's dev/unit-spanish.mjs table, then what only the phone and
/// iPad do (adding to a log without rewriting it, a card written into a deck that keeps its comments, the tutor's fuller first message).
final class SpanishTests: XCTestCase {
    lazy var g: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(spanishGolden.utf8)) as? [String: Any]) ?? [:]

    private func s(_ a: Any?) -> String { a as? String ?? "" }
    private func n(_ a: Any?) -> Int { (a as? NSNumber)?.intValue ?? 0 }
    private func d(_ a: Any?) -> Double { (a as? NSNumber)?.doubleValue ?? 0 }
    private func strs(_ a: Any?) -> [String] { a as? [String] ?? [] }
    private func list(_ a: Any?) -> [Any] { a as? [Any] ?? [] }
    private func obj(_ a: Any?) -> [String: Any] { a as? [String: Any] ?? [:] }
    /// A golden JSON value as the app's JSONValue (what a reply's JSON is read into).
    private func json(_ a: Any?) -> JSONValue? {
        guard let a, let data = try? JSONSerialization.data(withJSONObject: a, options: [.fragmentsAllowed]) else { return nil }
        return try? JSONValue.parse(String(decoding: data, as: UTF8.self))
    }
    private func mark(_ a: Any?) -> SpanishCheck.Mark {
        let o = obj(a)
        return SpanishCheck.Mark(s: n(o["s"]), e: n(o["e"]), wrong: s(o["wrong"]), right: s(o["right"]), skill: s(o["skill"]), kind: s(o["kind"]), why: s(o["why"]), by: s(o["by"]))
    }
    private func entry(_ a: Any?) -> SpanishCheck.Entry {
        let o = obj(a)
        return SpanishCheck.Entry(at: s(o["at"]), source: o["source"] == nil ? "checker" : s(o["source"]), text: s(o["text"]), fixed: s(o["fixed"]), question: s(o["question"]),
                                  mistakes: list(o["mistakes"]).map { let m = obj($0); return SpanishCheck.LogMistake(skill: s(m["skill"]), wrong: s(m["wrong"]), right: s(m["right"]), why: s(m["why"])) },
                                  good: strs(o["good"]), partial: (o["partial"] as? Bool) ?? false)
    }

    func testGoldenLoads() {
        XCTAssertGreaterThan(list(g["merge"]).count, 40)
        XCTAssertGreaterThan(list(g["stats"]).count, 20)
    }

    // MARK: golden: skills, tags, the files Set up writes

    func testGoldenSkillsAndTags() {
        for p in list(g["toSkill"]) { let x = strs(p); XCTAssertEqual(Spanish.toSkill(x[0]), x[1], "toSkill(\(x[0]))") }
        for p in list(g["cleanTag"]) { let x = strs(p); XCTAssertEqual(Spanish.cleanTag(x[0]), x[1], "cleanTag(\(x[0]))") }
        for p in list(g["accents"]) { let x = list(p); XCTAssertEqual(SpanishCheck.accentVariants(s(x[0])), strs(x[1]), "accentVariants(\(s(x[0])))") }
    }

    func testGoldenFiles() {
        var status = Spanish.courseStatus
        status["verb.subjuntivo"] = "taught"
        XCTAssertEqual(Spanish.serializeSkills(status), s(g["skillsYaml"]))
        XCTAssertEqual(Spanish.course(), s(g["course"]))
        XCTAssertEqual(Spanish.profileTemplate(), s(g["profileTemplate"]))
        let want = list(g["setupFiles"]).map { strs($0) }
        let got = Spanish.setupFiles()
        XCTAssertEqual(got.map(\.path), want.map { $0[0] })
        for (a, b) in zip(got, want) { XCTAssertEqual(a.text, b[1], a.path) }
    }

    // MARK: golden: cards

    func testGoldenCards() {
        for c in list(g["cardId"]) { let x = list(c); XCTAssertEqual(SpanishCards.cardId(s(x[0]), taken: strs(x[1])), s(x[2]), "cardId(\(s(x[0])))") }
        for c in list(g["draft"]) {
            let x = list(c), w = obj(x[0]), want = obj(x[1])
            let got = SpanishCards.draft(word: s(w["word"]), lemma: s(w["lemma"]), form: s(w["form"]), meaning: s(w["meaning"]), deck: "es-viajes")
            XCTAssertEqual([got.front, got.back, got.deck, got.example], [s(want["front"]), s(want["back"]), s(want["deck"]), s(want["example"])], s(w["word"]))
            XCTAssertEqual(got.tags, strs(want["tags"]), s(w["word"]))
        }
        for c in list(g["warnings"]) {
            let x = list(c), card = obj(x[0])
            let ex = list(x[1]).map { let e = obj($0); return SpanishCards.Existing(front: s(e["front"]), back: s(e["back"]), deck: s(e["deck"])) }
            XCTAssertEqual(SpanishCards.warnings(front: s(card["front"]), back: s(card["back"]), tags: strs(card["tags"]), existing: ex), strs(x[2]), s(card["front"]))
        }
    }

    // MARK: golden: the checker's layers and their merge

    func testGoldenMarks() {
        let sm = SpanishCheck.spellMarks([.init(word: "comi", start: 5, end: 9, accent: "comí", suggestions: ["comí"]), .init(word: "cafe", start: 16, end: 20, accent: "café", suggestions: ["café"]),
                                          .init(word: "xyz", start: 0, end: 3, accent: nil, suggestions: ["y", "z", "w", "q"])])
        XCTAssertEqual(sm, list(g["spellMarks"]).map(mark))
        let lt = obj(g["lt"])
        let matches = SpanishCheck.LTMatch.list(json(["matches": lt["matches"] as Any])!)
        XCTAssertEqual(matches.count, 5)
        XCTAssertEqual(SpanishCheck.ltMarks(s(lt["text"]), matches), list(lt["marks"]).map(mark))
    }

    func testGoldenReadAndMerge() {
        let rc = obj(g["readCheck"])
        let ai = SpanishCheck.readCheck(s(rc["text"]), json(rc["ans"]))
        let want = obj(rc["ai"])
        XCTAssertEqual(ai?.corrected, s(want["corrected"]))
        XCTAssertEqual(ai?.mistakes.map { [$0.wrong, $0.right, $0.skill, $0.why] }, list(want["mistakes"]).map { let m = obj($0); return [s(m["wrong"]), s(m["right"]), s(m["skill"]), s(m["why"])] })
        XCTAssertEqual(ai?.good.map(\.skill), list(want["good"]).map { s(obj($0)["skill"]) })
        XCTAssertEqual(ai?.words.map(\.meaning), list(want["words"]).map { s(obj($0)["meaning"]) })
        for (i, c) in list(g["merge"]).enumerated() {
            let o = obj(c), text = s(o["text"])
            let algo = list(o["algo"]).map(mark)
            let ai = o["ans"] is NSNull || o["ans"] == nil ? nil : SpanishCheck.readCheck(text, json(o["ans"]))
            let marks = SpanishCheck.merge(text, algo, ai)
            XCTAssertEqual(marks, list(o["marks"]).map(mark), "merge \(i): \(text)")
            XCTAssertEqual(SpanishCheck.runs(text, marks).map { [$0.text, $0.mark?.wrong ?? "∅"] }, list(o["runs"]).map { let r = list($0); return [s(r[0]), (r[1] as? String) ?? "∅"] }, "runs \(i)")
            XCTAssertEqual(SpanishCheck.corrected(text, marks), s(o["corrected"]), "corrected \(i)")
        }
    }

    func testGoldenPromptsAndJSON() {
        let T = "Ayer comi en el cafe con mi amigos."
        let lt = obj(g["lt"])
        let algo = SpanishCheck.spellMarks([.init(word: "comi", start: 5, end: 9, accent: "comí", suggestions: ["comí"]), .init(word: "cafe", start: 16, end: 20, accent: "café", suggestions: ["café"])])
            + SpanishCheck.ltMarks(T, Array(SpanishCheck.LTMatch.list(json(["matches": lt["matches"] as Any])!).prefix(2)))
        let prompts = strs(g["checkPrompt"])
        XCTAssertTrue(SpanishCheck.prompt(text: T, found: algo, taught: Spanish.courseStatus).hasPrefix(prompts[0] + "\n"))
        XCTAssertTrue(SpanishCheck.prompt(text: "Hola.", question: "¿Qué tal?", taught: ["verb.subjuntivo": "taught"]).hasPrefix(prompts[1] + "\n"))
        for p in list(g["jsonFrom"]) {
            let x = list(p)
            XCTAssertEqual(SpanishCheck.jsonFrom(s(x[0])), x[1] is NSNull ? nil : json(x[1]), s(x[0]))
        }
    }

    // MARK: golden: the log and the numbers

    func testGoldenLog() {
        let want = obj(g["logEntry"])
        let back = SpanishCheck.parseLog(s(g["logText"]))
        XCTAssertTrue(back.ok)
        XCTAssertEqual(back.entries.count, 2)
        let e = back.entries[0]
        XCTAssertEqual([e.at, e.source, e.text, e.fixed, e.question, e.chat], [s(want["at"]), "checker", s(want["text"]), s(want["fixed"]), s(want["question"]), s(want["chat"])])
        XCTAssertEqual(e.mistakes.map(\.skill), list(want["mistakes"]).map { s(obj($0)["skill"]) })
        XCTAssertEqual(e.mistakes.map(\.why), list(want["mistakes"]).map { s(obj($0)["why"]) })
        XCTAssertEqual(e.good, strs(want["good"]))
        XCTAssertEqual(e.structures, strs(want["structures"]))
        XCTAssertEqual(e.words.map(\.lemma), ["ayer"])
        XCTAssertEqual(back.entries[1].text, "Hola: \"sí\" #1")
        XCTAssertEqual(back.entries[1].source, "chat")
        // the iPhone's own writing of the same entries says the same, line for line
        XCTAssertEqual(SpanishCheck.serializeLog(back.entries), s(g["logText"]))
    }

    func testGoldenStats() {
        for (k, run) in list(g["stats"]).enumerated() {
            let o = obj(run)
            let entries = list(o["entries"]).map(entry)
            let now = JS.parseLocal(s(o["nowText"]))!
            let got = SpanishCheck.skillStats(entries, now: now)
            let want = list(o["stats"]).map { list($0) }
            XCTAssertEqual(got.map(\.id), want.map { s($0[0]) }, "stats \(k): order")
            for (a, b) in zip(got, want) {
                let w = obj(b[1])
                XCTAssertEqual([a.stat.tries, a.stat.mistakes, a.stat.accuracy], [n(w["tries"]), n(w["mistakes"]), n(w["accuracy"])], "stats \(k) \(a.id)")
                XCTAssertEqual(a.stat.last, s(w["last"]))
                XCTAssertEqual(a.stat.status, s(w["status"]), "stats \(k) \(a.id)")
                XCTAssertEqual(a.stat.due, d(w["due"]), accuracy: 0.0001, "stats \(k) \(a.id) due")
            }
            XCTAssertEqual(SpanishCheck.weakest(got, 5).map(\.id), strs(o["weakest"]), "weakest \(k)")
            XCTAssertEqual(SpanishCheck.streak(entries), n(o["streak"]))
            XCTAssertEqual(SpanishCheck.solidShare(got, Spanish.courseStatus).solid, n(obj(o["solid"])["solid"]))
        }
    }

    func testGoldenChatTexts() {
        let e1 = SpanishCheck.parseLog(s(g["logText"])).entries[0]
        XCTAssertEqual(SpanishCheck.moveToChatText([e1, SpanishCheck.Entry(at: "x", text: "Hola.", fixed: "Hola.")]), s(g["moveToChat"]))
        let rft = strs(g["resultForTutor"])
        XCTAssertEqual(SpanishCheck.resultForTutor(e1), rft[0])
        XCTAssertEqual(SpanishCheck.resultForTutor(SpanishCheck.Entry(at: "x", text: "Hola", partial: true)), rft[1])
    }

    // MARK: golden: the tutor's reply, chats, memory

    func testGoldenReplies() {
        for p in list(g["replies"]) {
            let x = list(p), want = obj(x[1])
            let r = SpanishMemory.parseReply(s(x[0]))
            XCTAssertEqual(r.text, s(want["text"]), s(x[0]))
            XCTAssertEqual(r.check, want["check"] as? String, s(x[0]))
            XCTAssertEqual(r.cards.map(\.front), list(want["cards"]).map { s(obj($0)["front"]) })
            XCTAssertEqual(r.cards.map(\.deck), list(want["cards"]).map { s(obj($0)["deck"]) })
        }
    }

    func testGoldenChats() {
        let back = SpanishMemory.parseChat(s(g["chatText"]), path: "p")
        let want = obj(g["chatBack"])
        XCTAssertEqual([back.title, back.started, back.model, back.session, back.summary], [s(want["title"]), s(want["started"]), s(want["model"]), s(want["session"]), s(want["summary"])])
        XCTAssertEqual(back.skills, strs(want["skills"]))
        XCTAssertEqual(back.taught, strs(want["taught"]))
        XCTAssertEqual(back.messages.map(\.role), list(want["messages"]).map { s(obj($0)["role"]) })
        XCTAssertEqual(back.messages.map(\.text), list(want["messages"]).map { s(obj($0)["text"]) })
        XCTAssertEqual(SpanishMemory.parseChat(SpanishMemory.serializeChat(back), path: "p"), back)
        for c in list(g["chatPaths"]) { let x = strs(c); XCTAssertEqual(SpanishMemory.chatPath(base: x[0], started: x[1], title: x[2]), x[3]) }
    }

    func testGoldenProfile() {
        let base = SpanishMemory.parseProfile(Spanish.profileTemplate())
        XCTAssertEqual(base, obj(g["profileBase"]).mapValues { s($0) })
        var after = base
        after["working"] = "- Preterite endings.\n- ser and estar"
        after["strengths"] = "- Accents"
        let ch = SpanishMemory.profileChanges(base, after)
        let want = list(g["profileChanges"]).map(obj)
        XCTAssertEqual(ch.map(\.block), want.map { s($0["block"]) })
        XCTAssertEqual(ch.map(\.added), want.map { strs($0["added"]) })
        XCTAssertEqual(ch.map(\.removed), want.map { strs($0["removed"]) })
        after["mine"] = "my own"
        XCTAssertEqual(SpanishMemory.serializeProfile(after), s(g["profileText"]))
        for c in list(g["caps"]) {
            let x = list(c), w = obj(x[2])
            let got = SpanishMemory.capBlock(s(x[0]), s(x[1]))
            XCTAssertEqual(got.text, s(w["text"]), s(x[0]))
            XCTAssertEqual(got.cut, strs(w["cut"]), s(x[0]))
        }
        let rm = list(g["readMemory"])
        let m = SpanishMemory.readMemory(json(rm[0]))
        let wm = obj(rm[1])
        XCTAssertEqual(m?.skills, strs(wm["skills"]))
        XCTAssertEqual(m?.taught.map(\.skill), list(wm["taught"]).map { s(obj($0)["skill"]) })
        XCTAssertEqual(m?.notes.map(\.skill), list(wm["notes"]).map { s(obj($0)["skill"]) })
        XCTAssertEqual(m?.profile, obj(wm["profile"]).mapValues { s($0) })
        let notes = strs(g["notes"])
        let n1 = SpanishMemory.addToNote("", id: "ser-estar", status: "taught", lines: ["Mixed up soy and estoy."], day: "2026-11-09", link: "2026-11-09 1405 Preterite")
        XCTAssertEqual(n1, notes[0])
        XCTAssertEqual(SpanishMemory.addToNote(n1, id: "ser-estar", status: "taught", lines: ["Got it right.", "Again."], day: "2026-11-10"), notes[1])
        XCTAssertEqual(SpanishMemory.addToNote("# Hand written\n\nno notes heading", id: "gustar", status: "reteach", lines: ["x"], day: "2026-11-11"), notes[2])
    }

    // MARK: golden: writing

    func testGoldenWriting() {
        for c in list(g["wordCount"]) {
            let x = list(c), w = obj(x[1])
            let got = SpanishGrade.wordCount(s(x[0]))
            XCTAssertEqual([got.counted, got.total, got.paragraphs], [n(w["counted"]), n(w["total"]), n(w["paragraphs"])], s(x[0]))
            XCTAssertEqual(got.band, s(w["band"]))
            XCTAssertEqual(got.skipped.map(\.why), list(w["skipped"]).map { s(obj($0)["why"]) }, s(x[0]))
        }
        let back = SpanishGrade.parsePrompts(s(g["promptsText"]))
        let want = obj(g["promptsBack"])
        XCTAssertTrue(back.ok)
        XCTAssertEqual(back.prompts.map(\.id), list(want["prompts"]).map { s(obj($0)["id"]) })
        XCTAssertEqual(back.prompts.map(\.text), list(want["prompts"]).map { s(obj($0)["text"]) })
        XCTAssertEqual(back.prompts.map(\.types), list(want["prompts"]).map { strs(obj($0)["types"]) })
        XCTAssertEqual(SpanishGrade.serializePrompts(back.prompts), s(g["promptsText"]))
        for c in list(g["typesIn"]) { let x = list(c); XCTAssertEqual(SpanishGrade.typesIn(s(x[0])), strs(x[1]), s(x[0])) }
        for (i, c) in list(g["grades"]).enumerated() {
            let o = obj(c), cnt = obj(o["count"]), w = obj(o["grade"])
            let got = SpanishGrade.readGrade(json(o["ans"]), count: SpanishGrade.Count(counted: n(cnt["counted"]), paragraphs: n(cnt["paragraphs"])))
            XCTAssertEqual([got?.A.mark, got?.B.mark, got?.C.mark, got?.total], [n(obj(w["A"])["mark"]), n(obj(w["B"])["mark"]), n(obj(w["C"])["mark"]), n(w["total"])], "grade \(i)")
            XCTAssertEqual(got?.applied, strs(w["applied"]), "grade \(i)")
        }
        let p0 = SpanishGrade.Prompt(id: "p-1", text: "Escribe un correo electrónico o un blog sobre tus vacaciones.", unit: "G12.1", types: ["correo electrónico", "blog"], source: "Ms. Panhausen", added: "2026-11-09")
        let text0 = s(list(list(g["wordCount"])[0])[0])
        let gp = SpanishGrade.gradePrompt(prompt: p0, text: "y", count: SpanishGrade.wordCount(text0), samples: [.init(A: 4, B: 5, C: 2, comment: "good", prompt: "", text: "Hola amigo.")])
        XCTAssertTrue(gp.hasPrefix(s(g["gradePrompt"]) + "\n"))
        let g0 = SpanishGrade.readGrade(json(obj(list(g["grades"])[0])["ans"]), count: SpanishGrade.Count(counted: 0, paragraphs: 3))
        XCTAssertEqual(SpanishGrade.pieceFile(prompt: p0, text: text0, count: SpanishGrade.wordCount(text0), grade: g0, day: "2026-11-09"), s(g["piece"]))
        let samples = list(g["samples"])
        let s0 = SpanishGrade.parseSample(s(list(samples[0])[0]))
        XCTAssertEqual(s0?.A, 4); XCTAssertEqual(s0?.comment, "good"); XCTAssertEqual(s0?.text, "Hola amigo.")
        XCTAssertNil(SpanishGrade.parseSample(s(list(samples[1])[0])))
        XCTAssertNil(SpanishGrade.parseSample(s(list(samples[2])[0])))
        let info = SpanishGrade.pieceInfo(s(g["piece"]), path: "w.md")
        XCTAssertEqual(info?.total, g0?.total)
        XCTAssertEqual(info?.words, 23)
    }

    // MARK: the laptop's table (dev/unit-spanish.mjs)

    func testSettingASkillsStatus() {
        // one line changes, the comments and the rest stay
        let file = Spanish.serializeSkills(Spanish.courseStatus).replacingOccurrences(of: "skills:\n", with: "skills:\n  # mine\n")
        let after = Spanish.setSkillStatus(file, id: "verb.imperativo", status: "taught")
        XCTAssertEqual(Spanish.parseSkills(after)["verb.imperativo"], "taught")
        XCTAssertEqual(Spanish.parseSkills(after)["verb.imperativo-neg"], "reteach")
        XCTAssertTrue(after.contains("  # mine\n"))
        XCTAssertEqual(file.components(separatedBy: "\n").count, after.components(separatedBy: "\n").count)
        XCTAssertEqual(zip(file.components(separatedBy: "\n"), after.components(separatedBy: "\n")).filter { $0 != $1 }.count, 1)
        // a skill the file leaves out is added under skills:
        let short = "skills:\n  - { id: gustar, status: taught }\n"
        let added = Spanish.setSkillStatus(short, id: "verb.subjuntivo", status: "taught")
        XCTAssertEqual(Spanish.parseSkills(added)["verb.subjuntivo"], "taught")
        XCTAssertTrue(added.hasSuffix("  - { id: gustar, status: taught }\n"))
        // no file, or one that does not parse: written whole
        XCTAssertEqual(Spanish.parseSkills(Spanish.setSkillStatus(nil, id: "gustar", status: "reteach"))["gustar"], "reteach")
        XCTAssertEqual(Spanish.parseSkills(Spanish.setSkillStatus("skills: [", id: "gustar", status: "not-yet"))["gustar"], "not-yet")
        // an unknown skill or status changes nothing
        XCTAssertEqual(Spanish.setSkillStatus(short, id: "nope", status: "taught"), short)
        XCTAssertEqual(Spanish.setSkillStatus(short, id: "gustar", status: "maybe"), short)
    }

    func testCourse() {
        XCTAssertEqual([Spanish.courseStatus["verb.imperativo"], Spanish.courseStatus["verb.imperativo-neg"]], ["reteach", "reteach"])
        XCTAssertEqual([Spanish.courseStatus["verb.imperfecto"], Spanish.courseStatus["verb.subjuntivo"]], ["not-yet", "not-yet"])
        XCTAssertTrue(Spanish.skills.allSatisfy { s in Spanish.groups.contains { $0.id == s.group } && Spanish.statusWords[Spanish.courseStatus[s.id] ?? ""] != nil })
        XCTAssertTrue(Spanish.course().contains("Ms. Panhausen") && !Spanish.course().contains("Miss P "))
        XCTAssertEqual(Spanish.parseSkills("skills:\n  - { id: nope, status: taught }\n  - { id: gustar, status: weird }")["gustar"], "taught")
        for f in Spanish.setupFiles() where f.path.hasPrefix("study/decks/") {
            let p = StudyDeck.parse(f.text)
            XCTAssertNotNil(p.deck, f.path)
            XCTAssertTrue(p.deck?.flip == true && p.deck?.language == "es" && p.deck?.cards.isEmpty == true, f.path)
        }
        XCTAssertEqual(Spanish.studyLanguage(Spanish.setupFiles()[0].text), "spanish")
        XCTAssertEqual(Spanish.studyYamlWithSpanish("sheets: files\n"), "sheets: files\nlanguage: spanish\n")
        XCTAssertEqual(Spanish.studyYamlWithSpanish("language: chem\n\n"), "language: spanish\n")
        XCTAssertNil(Spanish.studyYamlWithSpanish("language: spanish\n"))
    }

    func testAddingACard() throws {
        let base = Spanish.deckFile(Spanish.decks[1])
        let r1 = try SpanishCards.addCardText(base, front: "la maleta", back: "the suitcase", tags: ["sustantivo", "tema::experiencias", "bogus"], example: "Hago la maleta.", day: "2026-11-09")
        let deck = try XCTUnwrap(StudyDeck.parse(r1.text).deck)
        XCTAssertEqual(r1.id, "maleta")
        XCTAssertEqual(deck.cards.first?.tags, ["pos::sustantivo", "tema::experiencias"])
        XCTAssertEqual(deck.cards.first?.example, "Hago la maleta.")
        XCTAssertEqual(deck.cards.first?.added, "2026-11-09")
        XCTAssertTrue(r1.text.hasPrefix("# Vocab · Viajes") && r1.text.contains("flip: true"))
        let r2 = try SpanishCards.addCardText(r1.text, front: "la maleta", back: "luggage")
        XCTAssertEqual(r2.id, "maleta-2")
        // the lines already there are untouched: the second card is only added
        XCTAssertTrue(r2.text.hasPrefix(r1.text.trimEnd))
        XCTAssertEqual(StudyDeck.parse(r2.text).deck?.cards.map(\.id), ["maleta", "maleta-2"])
        // a deck with comments between its cards and a key after them
        let hand = "# mine\nflip: true\ncards:\n# first\n- id: a\n  front: el perro\n  back: dog\n\n# later\nsources: []\n"
        let r3 = try SpanishCards.addCardText(hand, front: "el gato", back: "cat")
        XCTAssertEqual(StudyDeck.parse(r3.text).deck?.cards.map(\.id), ["a", "gato"])
        XCTAssertTrue(r3.text.contains("# first\n- id: a") && r3.text.hasSuffix("sources: []\n"))
        XCTAssertThrowsError(try SpanishCards.addCardText("cards: [\n", front: "x", back: "y"))
    }

    func testAppendingToTheLog() throws {
        let e1 = SpanishCheck.Entry(at: "2026-11-09T10:00:00.000", text: "Hola.", fixed: "Hola.")
        let e2 = SpanishCheck.Entry(at: "2026-11-09T10:01:00.000", text: "Yo es.", fixed: "Yo soy.", mistakes: [.init(skill: "agree.verb", wrong: "es", right: "soy", why: "yo")])
        let first = try XCTUnwrap(SpanishCheck.appendToLog(nil, e1))
        XCTAssertEqual(first, SpanishCheck.serializeLog([e1]))
        let second = try XCTUnwrap(SpanishCheck.appendToLog(first, e2))
        XCTAssertTrue(second.hasPrefix(first))
        XCTAssertEqual(second, SpanishCheck.serializeLog([e1, e2]))
        XCTAssertEqual(SpanishCheck.parseLog(second).entries.map(\.text), ["Hola.", "Yo es."])
        XCTAssertNil(SpanishCheck.appendToLog("entries: [", e2))
        // a log the laptop wrote with its items at no indent
        let flat = "entries:\n- at: a\n  text: x\n  mistakes: []\n  good: []\n"
        XCTAssertEqual(SpanishCheck.parseLog(SpanishCheck.appendToLog(flat, e2)).entries.map(\.text), ["x", "Yo es."])
    }

    func testYAMLScalars() throws {
        for t in ["plain", "two words", "a: b", "#x", "- x", "-x", "yes", "12", "1.5", "2026-11-09", "x #y", "line\nbreak", " pad", "ends:", "¿Qué?", "\"q\"", "it's", "null", "[a]", "1:20", "", "@me", "tab\there"] {
            let v = YValue.map([.init("k", .string(t))])
            XCTAssertEqual(try YValue.parse(v.yaml)["k"], .string(t), t)
        }
    }

    func testTutorFirstMessage() {
        let e = SpanishCheck.Entry(at: "2026-11-09T10:00:00", text: "Soy cansado.", fixed: "Estoy cansado.", mistakes: [.init(skill: "ser-estar")])
        let stats = SpanishCheck.skillStats([e], now: JS.parseLocal("2026-11-10T10:00:00")!)
        let idx = SpanishMemory.tutorIndex(base: "Spanish", profile: "## Strengths\n- x", status: Spanish.courseStatus, stats: stats, chats: [.init(path: "a.md", title: "A", summary: "did x")],
                                           decks: [.init(id: "es-viajes", title: "V", cards: 3)], prompts: 2, unit: "G12.4 Mi mundo laboral", today: "2026-11-09",
                                           course: "# course", notes: [(id: "ser-estar", text: "# ser or estar\n- mixed up")], recent: [e])
        XCTAssertTrue(idx.contains("teach again from scratch: verb.imperativo, verb.imperativo-neg"))
        XCTAssertTrue(idx.contains("a.md: did x") && idx.contains("Current unit: G12.4"))
        XCTAssertTrue(idx.contains("## The course") && idx.contains("### ser-estar") && idx.contains("Soy cansado. -> Estoy cansado. [ser-estar]"))
        XCTAssertTrue(idx.hasPrefix("<memory>") && idx.hasSuffix("</memory>"))
        let sys = SpanishMemory.tutorSystem(base: "Spanish", model: "sonnet")
        XCTAssertTrue(sys.contains("Explanations are in English") && sys.contains("```check") && sys.contains("Spanish/study/spanish/profile.md") && sys.contains("from scratch"))
    }
}
