import XCTest
@testable import NexusCore

/// Study on the iPhone and iPad: FSRS, the decks, review.yaml and a session. The golden half checks the port against what the laptop's
/// own studyfsrs.js and studydeck.js give (StudyGolden.swift, tools/study-golden/gen.mjs); the rest is the laptop's dev/unit-study.mjs
/// table, then what only the phone and iPad do (merging two devices' grades, a session's steps, finding the decks).
final class StudyTests: XCTestCase {
    lazy var golden: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(studyGolden.utf8)) as? [String: Any]) ?? [:]
    let MIN: Int64 = 60_000, DAY: Int64 = 86_400_000
    var savedZone = FSRS.timeZone

    override func setUp() { savedZone = FSRS.timeZone; FSRS.timeZone = TimeZone(identifier: "UTC")!; Days.dayStartHour = 4 }
    override func tearDown() { FSRS.timeZone = savedZone }

    private func i64(_ a: Any?) -> Int64 { (a as? NSNumber)?.int64Value ?? 0 }
    private func dbl(_ a: Any?) -> Double { (a as? NSNumber)?.doubleValue ?? 0 }
    private func strs(_ a: Any?) -> [String] { a as? [String] ?? [] }

    // MARK: golden: FSRS

    func testGoldenLoads() {
        XCTAssertEqual((golden["zones"] as? [String: Any])?.count, 3)
        XCTAssertGreaterThan((golden["check"] as? [Any])?.count ?? 0, 200)
    }

    func testGoldenReviewsInEveryZone() throws {
        let zones = try XCTUnwrap(golden["zones"] as? [String: [String: Any]])
        for (tz, z) in zones {
            FSRS.timeZone = try XCTUnwrap(TimeZone(identifier: tz))
            for (r, run) in (z["runs"] as? [[[String: Any]]] ?? []).enumerated() {
                var c = SRSCard()
                for (i, step) in run.enumerated() {
                    c = FSRS.review(c, Int(i64(step["g"])), i64(step["now"]))
                    let want = step["card"] as? [Any] ?? []
                    let at = "\(tz) run \(r) step \(i)"
                    XCTAssertEqual(c.state.rawValue, want[0] as? String, at)
                    XCTAssertEqual(c.due, i64(want[1]), at)
                    XCTAssertEqual(c.s, dbl(want[2]), accuracy: 1e-9, at)
                    XCTAssertEqual(c.d, dbl(want[3]), accuracy: 1e-9, at)
                    XCTAssertEqual([c.reps, c.lapses], [Int(i64(want[4])), Int(i64(want[5]))], at)
                    XCTAssertEqual(c.last, i64(want[6]), at)
                    // (the next step starts from the laptop's card, so one difference does not hide the rest)
                    c = SRSCard(state: SRSCard.Phase(rawValue: want[0] as! String)!, due: i64(want[1]), s: dbl(want[2]), d: dbl(want[3]),
                                reps: Int(i64(want[4])), lapses: Int(i64(want[5])), last: i64(want[6]))
                }
            }
            for row in z["dayStart"] as? [[Any]] ?? [] {
                XCTAssertEqual(FSRS.dayStartOf(i64(row[0])), i64(row[1]), "\(tz) dayStartOf \(row[0])")
                XCTAssertEqual(FSRS.daysBetween(i64(row[0]), i64(row[2])), Int(i64(row[3])), "\(tz) daysBetween")
                XCTAssertEqual(FSRS.dueOnDay(i64(row[0]), Int(i64(row[4]))), i64(row[5]), "\(tz) dueOnDay")
            }
            for row in z["words"] as? [[Any]] ?? [] {
                XCTAssertEqual(FSRS.untilWords(i64(row[1]), i64(row[0])), row[2] as? String, "\(tz) untilWords")
            }
            for row in z["preview"] as? [[Any]] ?? [] {
                let w = row[0] as! [Any]
                let c = SRSCard(state: SRSCard.Phase(rawValue: w[0] as! String)!, due: i64(w[1]), s: dbl(w[2]), d: dbl(w[3]), reps: Int(i64(w[4])), lapses: Int(i64(w[5])), last: i64(w[6]))
                let p = FSRS.preview(c, i64(row[1]))
                let want = row[2] as! [[Any]]
                XCTAssertEqual(p.map(\.due), want.map { i64($0[0]) }, "\(tz) preview")
                XCTAssertEqual(p.map(\.inText), want.map { $0[1] as! String }, "\(tz) preview words")
            }
        }
    }

    func testGoldenWordsAndFormulas() {
        for row in golden["inWords"] as? [[Any]] ?? [] { XCTAssertEqual(FSRS.inWords(i64(row[0])), row[1] as? String) }
        for row in golden["dayWords"] as? [[Any]] ?? [] { XCTAssertEqual(FSRS.dayWords(Int(i64(row[0]))), row[1] as? String) }
        for row in golden["intervals"] as? [[Any]] ?? [] { XCTAssertEqual(FSRS.intervalDays(dbl(row[0])), Int(i64(row[1])), "interval \(row[0])") }
        for row in golden["retrievability"] as? [[Any]] ?? [] { XCTAssertEqual(FSRS.retrievability(dbl(row[0]), dbl(row[1])), dbl(row[2]), accuracy: 1e-12) }
    }

    // MARK: golden: decks

    func testGoldenRandom() {
        for row in golden["rng"] as? [[Any]] ?? [] {
            let r = StudyDeck.rng(row[0] as! String)
            XCTAssertEqual((0..<5).map { _ in r() }, (row[1] as! [NSNumber]).map(\.doubleValue), "rng \(row[0])")
        }
    }

    func testGoldenTypedAnswers() {
        for row in golden["check"] as? [[Any]] ?? [] {
            let t = row[0] as! String, a = row[1] as! String
            XCTAssertEqual(StudyDeck.check(t, a, accept: strs(row[2])).rawValue, row[3] as? String, "check \(t) against \(a)")
        }
        for row in golden["formula"] as? [[Any]] ?? [] {
            XCTAssertEqual(StudyDeck.looksFormula(row[0] as! String), (row[1] as! NSNumber).boolValue, "looksFormula \(row[0])")
        }
    }

    private func goldenDecks() -> [String: StudyDeck] {
        var out: [String: StudyDeck] = [:]
        for d in golden["decks"] as? [[String: Any]] ?? [] {
            if let deck = StudyDeck.parse(d["yaml"] as! String, fileId: d["id"] as! String).deck { out[d["id"] as! String] = deck }
        }
        return out
    }

    func testGoldenDecks() throws {
        for d in golden["decks"] as? [[String: Any]] ?? [] {
            let id = d["id"] as! String
            let p = StudyDeck.parse(d["yaml"] as! String, fileId: id)
            XCTAssertEqual(p.deck != nil, (d["ok"] as! NSNumber).boolValue, "\(id) ok")
            XCTAssertEqual(p.problems, strs(d["problems"]), "\(id) problems")
            guard let deck = p.deck, let want = d["deck"] as? [String: Any] else { continue }
            XCTAssertEqual(deck.id, want["id"] as? String, id)
            XCTAssertEqual(deck.title, want["title"] as? String, id)
            XCTAssertEqual(deck.description, want["description"] as? String, id)
            XCTAssertEqual([deck.reversible, deck.flip], [(want["reversible"] as! NSNumber).boolValue, (want["flip"] as! NSNumber).boolValue], id)
            XCTAssertEqual([deck.language, deck.kind, deck.unit], [want["language"], want["kind"], want["unit"]].map { $0 as! String }, id)
            XCTAssertEqual(deck.columns.map { [$0.key, $0.label] }, (want["columns"] as! [[String: String]]).map { [$0["key"]!, $0["label"]!] }, id)
            XCTAssertEqual(deck.groups.map { [$0.id, $0.title] }, (want["groups"] as! [[String: String]]).map { [$0["id"]!, $0["title"]!] }, id)
            XCTAssertEqual(deck.sources.map { [$0.title, $0.url] }, (want["sources"] as! [[String: String]]).map { [$0["title"]!, $0["url"]!] }, id)
            let cards = want["cards"] as! [[String: Any]]
            XCTAssertEqual(deck.cards.map(\.id), cards.map { $0["id"] as! String }, id)
            for (c, w) in zip(deck.cards, cards) {
                let at = "\(id)/\(c.id)"
                XCTAssertEqual([c.group, c.level, c.front, c.back, c.note, c.example, c.added],
                               ["group", "level", "front", "back", "note", "example", "added"].map { w[$0] as! String }, at)
                XCTAssertEqual(c.fields, w["fields"] as? [String: String], at)
                XCTAssertEqual(c.accept, strs(w["accept"]), at)
                XCTAssertEqual(c.acceptReverse, strs(w["acceptReverse"]), at)
                XCTAssertEqual(c.options, w["options"] as? [String], at)
                XCTAssertEqual(c.covers, strs(w["covers"]), at)
                XCTAssertEqual(c.tags, strs(w["tags"]), at)
            }
            let sections = d["sections"] as! [[Any]]
            XCTAssertEqual(deck.sections().map { [$0.id, $0.title] + $0.cards.map(\.id) }, sections.map { [$0[0] as! String, $0[1] as! String] + strs($0[2]) }, id)
            let sides = d["sides"] as! [[Any]]
            for (c, s) in zip(deck.cards, sides) {
                let pairs: [(StudyDeck.Direction, Any)] = [(.forward, s[1]), (.reverse, s[2])]
                for (dir, w) in pairs {
                    let w = w as! [String: Any], got = StudyDeck.side(c, dir)
                    XCTAssertEqual([got.prompt, got.answer], [w["prompt"] as! String, w["answer"] as! String], "\(id)/\(c.id) \(dir)")
                    XCTAssertEqual(got.accept, strs(w["accept"]), "\(id)/\(c.id) \(dir) accept")
                }
            }
            XCTAssertEqual(deck.tags().map { "\($0.tag)=\($0.n)" }, (d["tags"] as! [[Any]]).map { "\($0[0])=\($0[1])" }, id)
        }
    }

    func testGoldenChoicesAndFlips() throws {
        let decks = goldenDecks()
        for row in golden["mcq"] as? [[Any]] ?? [] {
            let deck = try XCTUnwrap(decks[row[0] as! String]), card = try XCTUnwrap(deck.cards.first { $0.id == row[1] as! String })
            let got = deck.choices(card, StudyDeck.Direction(rawValue: row[2] as! String)!, seed: row[3] as! String)
            XCTAssertEqual(got.options, strs(row[4]), "\(row[0])/\(row[1]) \(row[2]) \(row[3])")
            XCTAssertEqual(got.correct, Int(i64(row[5])), "\(row[0])/\(row[1]) correct")
        }
        for row in golden["flip"] as? [[Any]] ?? [] {
            let deck = try XCTUnwrap(decks[row[0] as! String]), card = try XCTUnwrap(deck.cards.first { $0.id == row[1] as! String })
            let s = StudyDeck.flipSide(card, StudyDeck.Show(rawValue: row[2] as! String)!, seed: row[3] as! String)
            XCTAssertEqual([s.prompt, s.answer], [row[4] as! String, row[5] as! String], "flip \(row[1]) \(row[2]) \(row[3])")
            XCTAssertEqual(s.flipped, (row[6] as! NSNumber).boolValue)
        }
    }

    // MARK: golden: review.yaml

    private func plainBook(_ b: ReviewBook) -> [String: [String: [String: [Any]]]] {
        var out: [String: [String: [String: [Any]]]] = [:]
        for (id, d) in b.decks {
            for dir in StudyDeck.Direction.allCases where !d[dir].isEmpty {
                for (cid, c) in d[dir].map {
                    out[id, default: [:]][dir.rawValue, default: [:]][cid] = [c.state.rawValue, c.due, c.s, c.d, c.reps, c.lapses, c.last, c.log.map { "\($0.at)|\($0.grade)|\($0.mode)" }]
                }
            }
        }
        return out
    }
    private func plainJS(_ decks: [String: Any]) -> [String: [String: [String: [Any]]]] {
        var out: [String: [String: [String: [Any]]]] = [:]
        for (id, d) in decks { for (dir, cards) in d as! [String: Any] { for (cid, c) in cards as! [String: [String: Any]] {
            out[id, default: [:]][dir, default: [:]][cid] = [c["state"] as! String, i64(c["due"]), dbl(c["s"]), dbl(c["d"]), Int(i64(c["reps"])), Int(i64(c["lapses"])), i64(c["last"]),
                                                             (c["log"] as! [[Any]]).map { "\(i64($0[0]))|\(i64($0[1]))|\($0[2] as! String)" }]
        } } }
        return out
    }

    /// One sorted line per card, so two books compare whatever order their dictionaries keep.
    private func canon(_ b: [String: [String: [String: [Any]]]]) -> [String] {
        b.flatMap { id, dirs in dirs.flatMap { dir, cards in cards.map { cid, v in "\(id)/\(dir)/\(cid) = \(v)" } } }.sorted()
    }

    func testGoldenReviewFile() throws {
        let r = try XCTUnwrap(golden["review"] as? [String: Any])
        let text = r["text"] as! String
        let book = try ReviewBook.parse(text).get()
        XCTAssertEqual(book.serialize(), text, "the laptop's file, read and written again, is the same text")
        XCTAssertEqual(canon(plainBook(book)), canon(plainJS(r["parsed"] as! [String: Any])))
        let odd = r["odd"] as! [String: Any]
        let ob = try ReviewBook.parse(odd["text"] as! String).get()
        XCTAssertEqual(canon(plainBook(ob)), canon(plainJS(odd["decks"] as! [String: Any])))
        for row in r["empty"] as! [[Any]] {
            let ok: Bool = { if case .success = ReviewBook.parse(row[0] as! String) { return true }; return false }()
            XCTAssertEqual(ok, (row[1] as! NSNumber).boolValue, "parse \(row[0])")
        }
    }

    // MARK: the laptop's unit table (dev/unit-study.mjs)

    func testFSRSAsTheLaptopTestsIt() {
        let T0: Int64 = 1_793_696_400_000 // 2026-11-03 09:00 UTC
        let c1 = FSRS.review(SRSCard(), 3, T0)
        XCTAssertEqual(c1.state, .learning); XCTAssertEqual(c1.due - T0, 10 * MIN); XCTAssertEqual(c1.s, 3.173); XCTAssertEqual(c1.reps, 1)
        let c2 = FSRS.review(c1, 3, T0 + 10 * MIN)
        XCTAssertEqual(c2.state, .review); XCTAssertGreaterThanOrEqual(FSRS.daysBetween(T0 + 10 * MIN, c2.due), 2)
        let e1 = FSRS.review(SRSCard(), 4, T0)
        XCTAssertEqual(e1.state, .review); XCTAssertEqual(FSRS.daysBetween(T0, e1.due), 16); XCTAssertEqual(e1.due, FSRS.dayStartOf(e1.due))
        XCTAssertEqual(FSRS.preview(SRSCard(), T0).map(\.inText), ["1 min", "5 min", "10 min", "16 days"])
        let a1 = FSRS.review(SRSCard(), 1, T0)
        XCTAssertEqual(a1.due - T0, MIN); XCTAssertGreaterThan(a1.d, e1.d)
        let late = FSRS.review(c2, 3, c2.due)
        XCTAssertGreaterThan(late.s, c2.s)
        let lapse = FSRS.review(c2, 1, c2.due)
        XCTAssertEqual(lapse.state, .relearning); XCTAssertEqual(lapse.lapses, 1); XCTAssertEqual(lapse.due - c2.due, 10 * MIN); XCTAssertLessThan(lapse.s, c2.s)
        let (h, g, e) = (FSRS.review(c2, 2, c2.due).due, FSRS.review(c2, 3, c2.due).due, FSRS.review(c2, 4, c2.due).due)
        XCTAssertTrue(h < g && g < e)
        XCTAssertEqual((FSRS.retrievability(10, 10) * 1000).rounded() / 1000, 0.9)
        var b = c2; b.due = T0 - DAY
        let st = ["a": c2, "b": b, "c": lapse]
        XCTAssertEqual(FSRS.counts(["a", "b", "c", "d"], st, c2.due - 1), FSRS.Counts(due: 1, new: 1, learning: 1, known: 1, total: 4))
        XCTAssertEqual(FSRS.sessionQueue(["a", "b", "d", "e", "f"], st, T0, newLimit: 2), ["b", "d", "e"])
        XCTAssertEqual(FSRS.comingBack(["a", "c"], st, lapse.due, []), ["c"])
    }

    func testTypedAnswersAsTheLaptopTestsThem() {
        let A = { (t: String, w: String, acc: [String]) in StudyDeck.check(t, w, accept: acc).rawValue }
        XCTAssertEqual(["SO4 2-", "SO4^2-", "SO42-", "SO4-2", "SO4 -2", "SO4^(2-)", "SO4(2-)", "so4 2-", "SO₄²⁻", " SO4  2 - ", "SO4 2+", "SO4", "SO3 2-", ""].map { A($0, "SO₄²⁻", []) },
                       ["right", "right", "right", "right", "right", "right", "right", "case", "right", "right", "wrong", "wrong", "wrong", "empty"])
        XCTAssertEqual(["OH-", "OH 1-", "OH^-", "OH-1", "oh-", "O-"].map { A($0, "OH⁻", []) }, ["right", "right", "right", "right", "case", "wrong"])
        XCTAssertEqual([A("ClO", "ClO⁻", ["ClO -"]), A("ClO-", "ClO⁻", ["ClO -"]), A("Sulphate", "sulfate", []), A("hydroxide ion", "hydroxide", [])], ["wrong", "right", "right", "right"])
    }

    // MARK: the iPhone and iPad's own: two devices' grades

    private func reviewed(_ g: Int, at: Int64, from c: SRSCard = SRSCard(), mode: String = "flip") -> SRSCard {
        var n = FSRS.review(c, g, at); n.log = c.log + [.init(at: at, grade: g, mode: mode)]; return n
    }

    func testMergeKeepsEachDevicesCardsAndTheNewerReview() {
        let T0: Int64 = 1_793_696_400_000
        var laptop = ReviewBook(), phone = ReviewBook()
        laptop["ions", .forward, "a"] = reviewed(3, at: T0)
        laptop["ions", .forward, "b"] = reviewed(3, at: T0)
        phone["ions", .forward, "b"] = reviewed(4, at: T0 + DAY, from: reviewed(3, at: T0))
        phone["ions", .reverse, "c"] = reviewed(1, at: T0 + DAY)
        phone["es", .forward, "casa"] = reviewed(3, at: T0)
        let m = laptop.merged(with: phone)
        XCTAssertEqual(m["ions", .forward, "a"], laptop["ions", .forward, "a"])
        XCTAssertEqual(m["ions", .forward, "b"]?.last, T0 + DAY, "the newer review of b wins")
        XCTAssertEqual(m["ions", .forward, "b"]?.log.count, 2, "both grades in its log, once each")
        XCTAssertNotNil(m["ions", .reverse, "c"]); XCTAssertNotNil(m["es", .forward, "casa"])
        XCTAssertEqual(m.decks["ions"]?.forward.ids, ["a", "b"])
        XCTAssertEqual(phone.merged(with: laptop)["ions", .forward, "b"]?.last, T0 + DAY, "the same whichever side merges")
    }

    func testReconcileWritesOverOnlyWhatThisAppWrote() throws {
        let T0: Int64 = 1_793_696_400_000
        var mine = ReviewBook()
        mine["ions", .forward, "a"] = reviewed(3, at: T0)
        let first = ReviewBook.reconcile(mine: mine, disk: nil, lastWritten: nil)
        XCTAssertFalse(first.keepBrokenAside)
        // an undone grade: the file is still ours, so it is written without the card
        var undone = mine; undone["ions", .forward, "a"] = nil
        XCTAssertEqual(ReviewBook.reconcile(mine: undone, disk: first.text, lastWritten: first.text).book, undone)
        // the laptop graded b meanwhile: kept
        var laptop = try ReviewBook.parse(first.text).get(); laptop["ions", .forward, "b"] = reviewed(2, at: T0 + MIN)
        mine["ions", .forward, "c"] = reviewed(4, at: T0 + 2 * MIN)
        let r = ReviewBook.reconcile(mine: mine, disk: laptop.serialize(), lastWritten: first.text)
        XCTAssertEqual(Set(r.book.states("ions", .forward).keys), ["a", "b", "c"])
        XCTAssertEqual(try ReviewBook.parse(r.text).get().serialize(), r.text)
        // a file that does not parse is kept aside, never merged
        let broken = ReviewBook.reconcile(mine: mine, disk: "decks: [", lastWritten: first.text)
        XCTAssertTrue(broken.keepBrokenAside); XCTAssertEqual(broken.book, mine)
    }

    func testConflictCopyNames() {
        XCTAssertTrue(ReviewBook.isConflictCopy("review (conflict iPhone 2026-11-12 0815).yaml"))
        XCTAssertTrue(ReviewBook.isConflictCopy("review (conflict Zephyrus Duo 16 2026-11-12 0815 2).yaml"))
        XCTAssertFalse(ReviewBook.isConflictCopy("review.yaml"))
        XCTAssertFalse(ReviewBook.isConflictCopy("sheets (conflict iPad 2026-11-12 0815).yaml"))
    }

    func testTimesAsDateParseReadsThem() {
        XCTAssertEqual(ReviewBook.parseTime("2026-11-03T09:00Z"), 1_793_696_400_000)
        XCTAssertEqual(ReviewBook.parseTime("2026-11-03T09:00:00.123+05:30"), 1_793_676_600_123)
        XCTAssertEqual(ReviewBook.parseTime("2026-11-03"), 1_793_664_000_000)
        XCTAssertEqual(ReviewBook.isoOrNull(1_793_696_459_999), "2026-11-03T09:00Z")
        XCTAssertEqual(ReviewBook.isoOrNull(951_782_400_000), "2000-02-29T00:00Z")
        XCTAssertEqual(ReviewBook.isoOrNull(0), "null")
    }

    // MARK: a session

    private let ionsYaml = "id: ions\ntitle: Ions\nreversible: true\ncards:\n- {id: a, front: sulfate, back: SO₄²⁻}\n- {id: b, front: nitrate, back: NO₃⁻}\n- {id: c, front: hydroxide, back: OH⁻}\n"

    func testASessionAsksDueThenNewAndAgainComesBack() throws {
        let deck = try XCTUnwrap(StudyDeck.parse(ionsYaml).deck)
        let T0: Int64 = 1_793_696_400_000
        var states: [String: SRSCard] = [:]
        states["c"] = reviewed(3, at: T0 - 10 * DAY, from: reviewed(3, at: T0 - 11 * DAY))
        var s = try XCTUnwrap(StudySession(deck: deck, dir: .forward, mode: .type, newLimit: 1, states: states, now: T0))
        XCTAssertEqual(s.current, "c", "the due card first"); XCTAssertEqual(s.queue, ["a"]); XCTAssertEqual(s.total, 2)
        s.submit("OH")
        XCTAssertEqual(s.result, .wrong); XCTAssertEqual(s.suggested, 1)
        let kept = try XCTUnwrap(s.grade(1, now: T0))
        XCTAssertEqual(kept.card, "c"); XCTAssertEqual(kept.state.state, .relearning); XCTAssertEqual(kept.state.log.last?.mode, "type")
        XCTAssertEqual(s.current, "a"); XCTAssertEqual(s.queue, ["c"], "Again comes back in this session")
        s.submit("SO4 2-"); XCTAssertEqual(s.suggested, 3)
        s.grade(3, now: T0 + MIN)
        XCTAssertEqual(s.current, "c")
        // Undo: a is asked again, its state as before
        let back = try XCTUnwrap(s.undo())
        XCTAssertEqual(back.card, "a"); XCTAssertNil(back.state); XCTAssertEqual(s.current, "a"); XCTAssertEqual(s.phase, .ask)
        s.submit("SO4 2-"); s.grade(4, now: T0 + MIN)
        s.submit("OH-"); s.grade(3, now: T0 + 2 * MIN)
        XCTAssertEqual(s.phase, .end); XCTAssertEqual(s.done, 3); XCTAssertEqual(s.right, 1, "a card right the first time counts")
        XCTAssertNil(StudySession(deck: deck, dir: .forward, mode: .flip, newLimit: 0, states: s.states, now: T0 + 3 * MIN), "nothing due, no new")
    }

    func testMultipleChoiceAndPractise() throws {
        let deck = try XCTUnwrap(StudyDeck.parse(ionsYaml).deck)
        var s = try XCTUnwrap(StudySession(deck: deck, dir: .reverse, mode: .mcq, newLimit: 20, practise: true, states: [:], now: 0))
        XCTAssertEqual(s.queue.count, 2); XCTAssertEqual(s.dir, .reverse)
        let c = try XCTUnwrap(s.choices)
        XCTAssertEqual(c.options.count, 3, "two other cards to choose from")
        s.pick(c.correct)
        XCTAssertEqual(s.result, .right)
        XCTAssertNil(s.grade(3, now: 1), "practising keeps nothing")
    }

    func testFlipDeckOneScheduleAndTags() throws {
        let y = "id: es\nflip: true\nreversible: true\ncards:\n- {id: casa, front: la casa, back: the house, tags: [home]}\n- {id: perro, front: el perro, back: the dog}\n"
        let deck = try XCTUnwrap(StudyDeck.parse(y).deck)
        XCTAssertFalse(deck.reversible, "a flip deck is never two cards per word")
        let s = try XCTUnwrap(StudySession(deck: deck, dir: .reverse, mode: .type, show: .en, tag: "home", newLimit: 10, states: [:], now: 0))
        XCTAssertEqual([s.mode.rawValue, s.dir.rawValue], ["flip", "forward"]); XCTAssertEqual(s.total, 1)
        XCTAssertEqual(s.side?.prompt, "the house")
    }

    // MARK: finding the decks

    func testFindsDecksAndConflictCopies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("study-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let w = Workstream(id: "chem", name: "Chem", kind: nil, color: nil, status: "active", aliases: [], folder: "classes/chem", group: "classes")
        func put(_ p: String, _ t: String) throws {
            let u = root.appendingPathComponent(p); try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try t.write(to: u, atomically: true, encoding: .utf8)
        }
        try put("classes/chem/study/decks/ions.yaml", ionsYaml)
        try put("classes/chem/study/decks/more/acids.yml", "cards: []\n")
        try put("classes/chem/study/decks/ions (conflict iPad 2026-11-12 0815).yaml", ionsYaml)
        try put("classes/chem/study/decks/notes.md", "x")
        try put("classes/chem/study/review (conflict iPhone 2026-11-12 0815).yaml", "decks:\n")
        XCTAssertEqual(StudyFolder.deckPaths(root, w), ["classes/chem/study/decks/ions.yaml", "classes/chem/study/decks/more/acids.yml"])
        let f = StudyFolder.readDeck(root, "classes/chem/study/decks/more/acids.yml") { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(f.fileId, "acids"); XCTAssertEqual(f.deck?.cards.count, 0)
        XCTAssertEqual(StudyFolder.reviewConflictCopies(root, w), ["classes/chem/study/review (conflict iPhone 2026-11-12 0815).yaml"])
    }
}
