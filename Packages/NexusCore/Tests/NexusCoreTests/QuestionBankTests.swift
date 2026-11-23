import XCTest
@testable import NexusCore

/// The question bank on the iPhone and iPad: finding questions in a paper's words (the laptop's questions.rs tests, case for case),
/// reading the marks, command term and type off them (bank.rs tests), and the two files read and written as the laptop writes them.
final class QuestionBankTests: XCTestCase {
    typealias L = QuestionFinder.Line
    typealias Spot = QuestionFinder.Spot
    private func l(_ x: Double, _ y: Double, _ t: String) -> L { L(x: x, y: y, text: t) }
    private func lead(_ s: String) -> QuestionFinder.Lead { QuestionFinder.lead(s) }

    // MARK: questions.rs

    func testALineSaysWhichQuestionItStarts() {
        XCTAssertEqual(lead("3. Ethanol burns"), .init(main: 3))
        XCTAssertEqual(lead("3 (a) State"), .init(main: 3, sub: "a"))
        XCTAssertEqual(lead("12a(ii) Deduce"), .init(main: 12, sub: "a", part: "ii"))
        XCTAssertEqual(lead("(b) Outline"), .init(sub: "b"))
        XCTAssertEqual(lead("(iii) Explain"), .init(part: "iii"))
        XCTAssertEqual(lead("1. a i any two of"), .init(main: 1, sub: "a", part: "i"))
        for not in ["2.5 g of copper", "2019 May", "2 marks", "a solution of", "A student", "In 1 mol", "iron"] { XCTAssertEqual(lead(not), .init(), not) }
    }

    func testQuestionsRunInOrderAndEndWhereTheNextStarts() {
        let pages = [
            [l(0.1, 0.1, "1. Ethane burns"), l(0.15, 0.2, "(a) State"), l(0.4, 0.25, "2 moles of it"), l(0.15, 0.3, "(b) Explain"), l(0.2, 0.32, "(i) why"), l(0.2, 0.4, "(ii) how")],
            [l(0.1, 0.05, "Turn over"), l(0.1, 0.1, "2. Iron"), l(0.1, 0.3, "7 is not next"), l(0.1, 0.6, "3 (a) Copper")],
        ]
        let r = QuestionFinder.runs(pages)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].map(\.key), ["1", "1a", "1b", "1b(i)", "1b(ii)", "2", "3", "3a"])
        XCTAssertEqual(r[0][0].from, Spot(page: 0, y: 0.1))
        XCTAssertEqual(r[0][0].to, Spot(page: 1, y: 0.1))
        XCTAssertEqual(r[0][1].to, Spot(page: 0, y: 0.3), "1a ends where 1b starts")
        XCTAssertEqual(r[0][3].to, Spot(page: 0, y: 0.4), "1b(i) ends where 1b(ii) starts")
        XCTAssertEqual(r[0][7].to, Spot(page: 1, y: 1), "the last runs to the end")
        XCTAssertEqual(QuestionFinder.leaves(r[0]).map(\.key), ["1a", "1b(i)", "1b(ii)", "2", "3a"])
    }

    func testAMarkschemeAtTheEndOfThePaperIsFoundAndMatched() {
        var pages = [
            [l(0.1, 0.1, "1. Which"), l(0.1, 0.5, "2. What")],
            [l(0.1, 0.1, "3 (a) State"), l(0.15, 0.4, "(b) Explain")],
            [l(0.3, 0.05, "Markscheme"), l(0.05, 0.2, "1. C"), l(0.05, 0.3, "2. B"), l(0.05, 0.4, "3 a  oxidation number rises"), l(0.05, 0.6, "3 b  electrons lost")],
        ]
        let (paper, ms) = QuestionFinder.split(pages)
        XCTAssertEqual(paper.map(\.key), ["1", "2", "3", "3a", "3b"])
        XCTAssertEqual(ms?.map(\.key), ["1", "2", "3", "3a", "3b"])
        XCTAssertEqual(QuestionFinder.matching(paper[4], in: ms ?? [])?.from, Spot(page: 2, y: 0.6))
        // without the word, a second run is not a markscheme (Section B numbered from 1, say)
        pages[2][0].text = "Section B"
        XCTAssertNil(QuestionFinder.split(pages).markscheme)
    }

    func testAPartTheMarkschemeLacksGoesToItsQuestion() {
        let ms = QuestionFinder.runs([[l(0.05, 0.1, "3"), l(0.05, 0.2, "4"), l(0.05, 0.5, "5")]])[0]
        let q = QuestionFinder.Q(main: 4, sub: "c", part: "ii", from: Spot(page: 0, y: 0), to: Spot(page: 0, y: 0))
        XCTAssertEqual(QuestionFinder.matching(q, in: ms)?.key, "4")
    }

    // MARK: bank.rs

    func testMarksCommandTermsAndMcqAreReadOffTheWords() {
        XCTAssertEqual(QuestionFinder.marks("Calculate the enthalpy change. [3]"), 3)
        XCTAssertEqual(QuestionFinder.marks("State one reason. (2 marks)"), 2)
        XCTAssertEqual(QuestionFinder.marks("(a) [2]\n(b) [1]"), 3)
        XCTAssertNil(QuestionFinder.marks("Use 2.0 mol (see page 3)"))
        XCTAssertEqual(QuestionFinder.command("3a(ii) Explain why the reaction is exothermic. [2]"), "explain")
        XCTAssertEqual(QuestionFinder.command("1. A sample of gas is heated.\nCalculate its new volume."), "calculate")
        XCTAssertEqual(QuestionFinder.command("2b Define the term standard enthalpy"), "define")
        XCTAssertNil(QuestionFinder.command("4 The graph shows a curve"))
        XCTAssertTrue(QuestionFinder.isMcq("1. Which is a strong acid?\nA. CH3COOH\nB. HCl\nC. NH3\nD. H2O"))
        XCTAssertFalse(QuestionFinder.isMcq("1. Explain why.\nA student says"))
    }

    func testARegionsWordsAreTheLinesBetweenItsSpots() {
        let pages = [[l(0.1, 0.1, "1. Ethane"), l(0.1, 0.5, " (a) State [2] ")], [l(0.1, 0.2, "2. Iron")]]
        XCTAssertEqual(QuestionFinder.regionText(pages, from: Spot(page: 0, y: 0.5), to: Spot(page: 1, y: 0.2)), "(a) State [2]")
        XCTAssertEqual(QuestionFinder.regionText(pages, from: Spot(page: 0, y: 0), to: Spot(page: 1, y: 1)), "1. Ethane\n(a) State [2]\n2. Iron")
    }

    // MARK: the files

    /// questions.yaml as the laptop writes it (bank.rs questions_text, serde_json numbers: 5.0 stays "5.0").
    static let laptopQuestions = """
    # Written by Nexus (Study › Question bank): each question of your papers, sorted once per paper.
    # facts = the paper's year, session, paper and level; questions = the sort (by the decision model or Claude, with how sure);
    # mine = what you changed by hand, which a new sort never overwrites.
    papers:
      "chem/Sheets/05 Reactivity 1 — Energetics/Energetics HL test/P2.pdf":
        facts: {"year":2023,"session":"May","paper":"2","level":"HL","sorted":"2026-11-22","by":"decider+claude"}
        questions:
          "1a": {"topics":["R1.1"],"type":"short","difficulty":3.0,"marks":2,"command":"state","sure":0.91,"by":"decider","from":{"page":0,"y":0.1},"to":{"page":0,"y":0.4}}
          "1b": {"topics":["R1.2"],"type":"structured","difficulty":6.5,"marks":4,"command":"calculate","by":"claude","model":{"topics":["R1.1"],"sure":0.42},"from":{"page":0,"y":0.4},"to":{"page":1,"y":1.0}}
        mine:
          "1a": {"topics":["R1.4"]}
      "notebooks/Chemistry/Class 12 Nov.board":
        facts: {"kind":"class","made":"2026-11-22","from":"Class 12 Nov","codes":["R3.2"]}
        questions:
          "c1": {"rect":[100.0,200.5,700.0,420.0],"label":"Question 1","topics":["R3.2"],"type":"short","marks":null,"command":null,"made":"2026-11-22","by":"none"}

    """

    static let laptopMarks = """
    # Written by Nexus (Study › Question bank): your marks on questions ("<paper>#<question>": done, hard or review),
    # the sheets you pinned as Working on, and where you stopped on each (bookmarks). One line each.
    marks:
      "chem/Sheets/05 Reactivity 1 — Energetics/Energetics HL test/P2.pdf#1a": {"mark":"hard","at":"2026-11-21"}
    pins: {}
    bookmarks:
      "chem/Sheets/05 Reactivity 1 — Energetics/Energetics HL test/P2.pdf": "1b"

    """

    static let p2 = "chem/Sheets/05 Reactivity 1 — Energetics/Energetics HL test/P2.pdf"

    func testTheLaptopsQuestionsFileComesBackByteForByte() throws {
        let q = try XCTUnwrap(QuestionBank.Questions.parse(Self.laptopQuestions))
        XCTAssertEqual(q.papers.map(\.path), [Self.p2, "notebooks/Chemistry/Class 12 Nov.board"])
        XCTAssertEqual(q.text, Self.laptopQuestions)
        let p = try XCTUnwrap(q[Self.p2])
        XCTAssertEqual(p.questions.keys, ["1a", "1b"])
        XCTAssertEqual(p.facts.value["level"]?.string, "HL")
        XCTAssertEqual(QuestionBank.paperFacts(p.facts.value), "May 2023 · Paper 2 · HL")
        // a hand change wins, and says so
        let m = try XCTUnwrap(p.merged("1a"))
        XCTAssertEqual(m["topics"], .array([.string("R1.4")]))
        XCTAssertEqual(m["fixed"], .array([.string("topics")]))
        XCTAssertEqual(m["difficulty"]?.number, 3)
        XCTAssertNil(p.merged("9"))
        XCTAssertTrue(q["notebooks/Chemistry/Class 12 Nov.board"]?.isClass == true)
    }

    func testAChangeRewritesOnlyItsOwnLine() throws {
        var q = try XCTUnwrap(QuestionBank.Questions.parse(Self.laptopQuestions))
        var p = try XCTUnwrap(q[Self.p2])
        try QuestionBank.fix(&p, "1b", [("type", .string("data"))])
        try QuestionBank.fix(&p, "1a", [("topics", nil)])
        q[Self.p2] = p
        let before = Self.laptopQuestions.split(separator: "\n"), after = q.text.split(separator: "\n")
        let gone = before.filter { !after.contains($0) }, added = after.filter { !before.contains($0) }
        XCTAssertEqual(gone, [#"      "1a": {"topics":["R1.4"]}"#])
        XCTAssertEqual(added, [#"      "1b": {"type":"data"}"#])
        XCTAssertThrowsError(try QuestionBank.fix(&p, "1a", [("marks", .number(3))]))
        XCTAssertThrowsError(try QuestionBank.fix(&p, "1a", [("type", .string("essay"))]))
        // and it reads back as written
        XCTAssertEqual(QuestionBank.Questions.parse(q.text), q)
    }

    func testTheMarksFileRoundTripsAndChangesByLine() throws {
        var m = try XCTUnwrap(QuestionBank.Marks.parse(Self.laptopMarks))
        XCTAssertEqual(m.text, Self.laptopMarks)
        XCTAssertEqual(m.mark(Self.p2, "1a"), "hard")
        XCTAssertEqual(m.bookmark(Self.p2), "1b")
        XCTAssertFalse(m.pinned(Self.p2))
        m.setMark(Self.p2, "1b", "done", today: "2026-11-23")
        m.setMark(Self.p2, "1a", nil, today: "2026-11-23")
        m.setPin(Self.p2, true, today: "2026-11-23")
        let want = """
        # Written by Nexus (Study › Question bank): your marks on questions ("<paper>#<question>": done, hard or review),
        # the sheets you pinned as Working on, and where you stopped on each (bookmarks). One line each.
        marks:
          "\(Self.p2)#1b": {"mark":"done","at":"2026-11-23"}
        pins:
          "\(Self.p2)": "2026-11-23"
        bookmarks:
          "\(Self.p2)": "1b"

        """
        XCTAssertEqual(m.text, want)
        XCTAssertEqual(QuestionBank.Marks.parse(m.text), m)
        // none yet: every part empty
        XCTAssertEqual(QuestionBank.Marks().text.hasSuffix("marks: {}\npins: {}\nbookmarks: {}\n"), true)
        XCTAssertEqual(QuestionBank.Marks.parse(nil), QuestionBank.Marks())
        // the docs' list of pins
        XCTAssertTrue(QuestionBank.Marks.parse("pins: [\"a.pdf\"]\n")?.pinned("a.pdf") == true)
    }

    func testAFileInAnotherShapeIsNeverWrittenOver() {
        XCTAssertNil(QuestionBank.Questions.parse("papers:\n  a.pdf:\n    facts:\n      year: 2023\n"))
        XCTAssertNil(QuestionBank.Marks.parse("marks:\n  \"a#1\":\n    mark: done\n"))
        XCTAssertEqual(QuestionBank.Questions.parse("")?.papers.count, 0)
        XCTAssertEqual(QuestionBank.Questions.parse("papers: {}\n")?.papers.count, 0)
    }

    func testMarkAsQuestionAddsTheNextQuestionOfTheBoard() throws {
        var q = try XCTUnwrap(QuestionBank.Questions.parse(Self.laptopQuestions))
        let b = "notebooks/Chemistry/Class 12 Nov.board"
        let k = QuestionBank.addMarked(&q, board: b, rect: [10, 20, 300, 140.5], label: nil, words: "2. Which is oxidised?\nA. Cu\nB. Zn\nC. Fe\nD. Ag [1]", source: nil, today: "2026-11-23")
        XCTAssertEqual(k, "c2")
        XCTAssertEqual(q[b]?.questions["c2"]?.text, #"{"rect":[10,20,300,140.5],"label":"Question 2","topics":["R3.2"],"type":"mcq","marks":1,"command":null,"made":"2026-11-23","by":"none"}"#)
        // a new board: its facts from board.json's source
        let src = try JSONValue.parse(#"{"course":"Chemistry HL","class_date":"2026-11-20","codes":["R2.1","R2.2"],"link":null}"#)
        let k2 = QuestionBank.addMarked(&q, board: "notebooks/Chemistry/Kinetics.board", rect: [0, 0, 10, 10], label: "Rates", words: "Explain why", source: src, today: "2026-11-23")
        XCTAssertEqual(k2, "c1")
        let p = try XCTUnwrap(q["notebooks/Chemistry/Kinetics.board"])
        XCTAssertEqual(p.facts.value.text, #"{"kind":"class","made":"2026-11-23","from":"Kinetics","classDate":"2026-11-20","course":"Chemistry HL","codes":["R2.1","R2.2"]}"#)
        XCTAssertEqual(p.merged("c1")?["command"]?.string, "explain")
        XCTAssertEqual(QuestionBank.rect(p.questions["c1"]!), [0, 0, 10, 10])
        XCTAssertEqual(q.papers.last?.path, "notebooks/Chemistry/Kinetics.board", "a new paper goes at the end")
    }

    // MARK: boards

    func testAPapersBoardIsInItsSubjectsNotebook() {
        let pdf = "classes/chem/files/05 Reactivity 1 — Energetics/Energetics HL test/P2.pdf"
        XCTAssertEqual(QuestionBank.papersBoard(pdf: pdf, sheetsRoot: "classes/chem/files", notebook: "notebooks/Chemistry"),
                       "notebooks/Chemistry/Papers/05 Reactivity 1 — Energetics/P2.board")
        XCTAssertEqual(QuestionBank.papersBoard(pdf: "classes/chem/files/Loose.pdf", sheetsRoot: "classes/chem/files", notebook: "notebooks/Chem"), "notebooks/Chem/Papers/Loose.board")
        XCTAssertEqual(QuestionBank.papersBoard(pdf: "classes/chem/x/A.pdf", sheetsRoot: "classes/chem/files", notebook: "notebooks/Chem"), "notebooks/Chem/Papers/A.board")
        XCTAssertEqual(QuestionBank.subjectNotebook([("notebooks/Z", "chem"), ("notebooks/Chem", "chem"), ("notebooks/Bio", "bio")], subject: "chem", name: "Chemistry"), "notebooks/Chem")
        XCTAssertEqual(QuestionBank.subjectNotebook([("notebooks/Bio", nil)], subject: "chem", name: "Chemistry HL"), "notebooks/Chemistry HL")
        let board = "notebooks/Chemistry/Papers/05 Reactivity 1 — Energetics/P2.board"
        let rel = QuestionBank.relTo(board: board, pdf)
        XCTAssertEqual(rel, "../../../../../" + pdf)
        XCTAssertEqual(QuestionBank.resolveIn(board: board, rel), pdf)
        XCTAssertEqual(QuestionBank.relTo(board: "a/P2.board", "a/P2.pdf"), "../P2.pdf")
        XCTAssertEqual(QuestionBank.resolveIn(board: "a/P2.board", "../P2.pdf"), "a/P2.pdf")
        XCTAssertNil(QuestionBank.resolveIn(board: "a.board", "../../x.pdf"))
        XCTAssertEqual(QuestionBank.besideBoard("a/b/P2.pdf"), "a/b/P2.board")
        XCTAssertEqual(QuestionBank.boardName(board), "P2")
    }

    func testAQuestionsPlaceAndTheInkWrittenThere() {
        // two pages 1000 tall at x 0, w 800, the second page opened at its middle with 300 of room (Insert space)
        let segs = [
            BoardFiles.PdfSegment(page: 0, x: 0, y: 0, w: 800, h: 1000, top: 0, bottom: 1),
            BoardFiles.PdfSegment(page: 1, x: 0, y: 1040, w: 800, h: 500, top: 0, bottom: 0.5),
            BoardFiles.PdfSegment(page: 1, x: 0, y: 1840, w: 800, h: 500, top: 0.5, bottom: 1),
        ]
        let q = try! JSONValue.parse(#"{"from":{"page":0,"y":0.612},"to":{"page":1,"y":0.762}}"#)
        let rects = QuestionBank.place(q, segs: segs)!
        XCTAssertEqual(rects.count, 3)
        XCTAssertEqual(rects[0][1], 600, accuracy: 1e-6)
        XCTAssertEqual(rects[0][3], 1000, accuracy: 1e-6)
        XCTAssertEqual(rects[1], [0, 1040, 800, 1540])
        XCTAssertEqual(rects[2][3], 1840 + 0.25 * 1000, accuracy: 1e-6)
        var ink = QuestionBank.Ink()
        ink.strokes = [([100, 700, 300, 720], 5), ([100, 1990, 900, 2000], 9), ([100, 560, 200, 600], 7), ([2000, 700, 2100, 720], 8)]
        ink.texts = [[50, 1100, 400, 1200]]
        let got = QuestionBank.inkIn(ink, rects)
        XCTAssertEqual(got.strokes, 2 + 3, "the stroke above the place and the one far right don't count; a text block counts 3")
        XCTAssertEqual(got.last, 9)
        XCTAssertEqual(QuestionBank.writtenWord(0, marks: 3), "none")
        XCTAssertEqual(QuestionBank.writtenWord(5, marks: 3), "some")
        XCTAssertEqual(QuestionBank.writtenWord(6, marks: 3), "plenty")
        XCTAssertEqual(QuestionBank.writtenWord(3, marks: nil), "some")
        XCTAssertEqual(QuestionBank.writtenWord(4, marks: nil), "plenty")
    }

    // MARK: the list

    func testFiltersPickByUnitTypeMarkAndHowMuchIsWritten() throws {
        let sort = try JSONValue.parse(#"{"topics":["R1.2"],"type":"short","command":"calculate","difficulty":5.0}"#)
        let r = QuestionBank.Row(paper: "p.pdf", q: "2a", title: "Energetics", isClass: false, facts: try JSONValue.parse(#"{"level":"HL","year":2023}"#),
                                 sort: sort, mark: "hard", written: "some")
        func f(_ set: (inout QuestionBank.Filter) -> Void) -> QuestionBank.Filter { var x = QuestionBank.Filter(); set(&x); return x }
        XCTAssertTrue(QuestionBank.keep(r, f { $0.unit = "R1" }))
        XCTAssertTrue(QuestionBank.keep(r, f { $0.unit = "R1.2"; $0.type = "short"; $0.mark = "hard"; $0.written = "started"; $0.level = "HL" }))
        XCTAssertFalse(QuestionBank.keep(r, f { $0.unit = "S1" }))
        XCTAssertFalse(QuestionBank.keep(r, f { $0.mark = "none" }))
        XCTAssertTrue(QuestionBank.keep(r, f { $0.difficulty = "hard" }), "your Hard mark counts as hard")
        XCTAssertFalse(QuestionBank.keep(r, f { $0.source = "class" }))
        XCTAssertTrue(QuestionBank.keep(r, f { $0.find = "energ" }))
        XCTAssertTrue(QuestionBank.keep(r, f { $0.find = "r1.2" }))
        XCTAssertFalse(QuestionBank.keep(r, f { $0.paper = "other.pdf" }))
        // physics codes: a theme letter picks its subtopics
        var p = r
        p.sort = p.sort.setting("topics", .array([.string("A.1")]))
        XCTAssertTrue(QuestionBank.keep(p, f { $0.unit = "A" }))
        // a textbook's question carries its own level, which counts over its paper's (the laptop's bank.rs, Nov 23)
        var t = p
        t.facts = .object([("kind", .string("textbook"))])
        t.sort = t.sort.setting("level", .string("SL"))
        XCTAssertTrue(QuestionBank.keep(t, f { $0.level = "SL" }))
        XCTAssertFalse(QuestionBank.keep(t, f { $0.level = "HL" }))
        XCTAssertEqual(r.meta, "R1.2 · Short answer · Calculate · medium")
    }

    func testPinnedFirstThenPaperOrderOrLastWritten() {
        func row(_ q: String, pinned: Bool = false, last: String? = nil) -> QuestionBank.Row {
            QuestionBank.Row(paper: "p", q: q, title: "", isClass: false, facts: .object([]), sort: .object([]), lastWritten: last, pinned: pinned)
        }
        let rows = [row("1"), row("2", last: "2026-11-20"), row("3", pinned: true), row("4", last: "2026-11-22")]
        XCTAssertEqual(QuestionBank.ordered(rows, recent: false).map(\.q), ["3", "1", "2", "4"])
        XCTAssertEqual(QuestionBank.ordered(rows, recent: true).map(\.q), ["4", "2", "3", "1"])
    }

    func testNames() {
        XCTAssertEqual(QuestionBank.qName("c3"), "Question 3")
        XCTAssertEqual(QuestionBank.qName("3a(ii)"), "3(a)(ii)")
        XCTAssertEqual(QuestionBank.qName("12"), "12")
        XCTAssertEqual(QuestionBank.paperFacts(.object([("year", .number(2021))])), "2021")
        XCTAssertEqual(QuestionBank.level(7), "hard")
    }
}
