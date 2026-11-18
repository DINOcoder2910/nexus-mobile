import XCTest
@testable import NexusCore

/// Applications: the laptop's dev/unit-apps.mjs cases on the same small folder, the detail edits, the universities database, Claude's research and
/// the site check, and the writes with Undo.
final class AppsTests: XCTestCase {
    var dir: URL!
    let T = "2026-10-08"

    static let NW = ("northwestern", "name: Northwestern (McCormick)\napplying: true\nround: ed\ninternal: 2026-10-15\nresearch:\n  usn: 9\n  acc: 7.5\n  rounds:\n    ed: {rate: 20.4, dl: 2026-11-01}\n    rd: {rate: 5.8, dl: 2027-01-04}\nessays:\n  - {id: n1, title: Background, lim: 300, fam: bg}\n  - {id: n2, title: Why NU, lim: 200, fam: why}\n",
                     "tasks:\n  - id: aa01\n    title: Supplements\n    est: 4h\n    subtasks:\n      - {id: aa02, title: Background essay, due: 2026-10-15}\n      - {id: aa03, title: Short responses, due: 2026-10-15}\n  - {id: aa04, title: Submit ED, due: 2026-11-01, est: 1h}\n")
    static let CO = ("columbia", "name: Columbia\napplying: true\nround: rd\ninternal: 2026-10-15\nresearch:\n  rounds:\n    rd: {dl: 2027-01-01}\nessays:\n  - {id: c1, title: Why Columbia, lim: 150, fam: why}\n  - {id: c2, title: Adversity, lim: 150, fam: story}\n",
                     "tasks:\n  - {id: bb01, title: Columbia essays, est: 3h}\n")
    static let USC = ("university-of-southern-california", "name: University of Southern California\nshort: USC\napplying: true\nround: ea\ninternal: 2026-10-15\nresearch:\n  rounds:\n    ea: {rate: 9.5, dl: 2026-11-01}\n",
                      "tasks:\n  - {id: cc01, title: USC why, est: 2h}\n")
    static let TU = ("tufts", "name: Tufts\napplying: false\nresearch:\n  usn: 31\n  acc: 10\n  rounds:\n    ed: {rate: 32, dl: 2026-11-02}\n    rd: {dl: 2027-01-04}\n  prompts:\n    - {t: Why Tufts, lim: 150, unit: words, why: true}\n", "tasks: []\n")
    static let CA = ("common-app", "name: Common App\nkind: project\nessays:\n  - {id: ca1, title: Personal statement, lim: 650, fam: story}\n", "tasks:\n  - {id: dd01, title: Finalise statement, due: 2026-11-01, est: 6h}\n")
    static let OV = ("overview", "name: Overview\nkind: project\ninternal_rule: {for: 2026-11-01, date: 2026-10-15}\n", "tasks:\n  - {id: ee01, title: Decide ED}\n")

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-apps-\(UUID().uuidString)")
        try put("nexus.yaml", "nexus: 2\n")
        try put("applications/group.yaml", "label: Applications\nkind: school\ndefault: overview\n")
        for (d, ws, ts) in [Self.NW, Self.CO, Self.USC, Self.TU, Self.CA, Self.OV] {
            try put("applications/\(d)/workstream.yaml", ws)
            try put("applications/\(d)/tasks.yaml", ts)
        }
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func put(_ rel: String, _ text: String) throws {
        let u = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }
    func text(_ rel: String) -> String { (try? String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)) ?? "" }
    func model(db: UniDB? = nil) -> (Snapshot, AppsModel) {
        let s = DataFolder.load(dir)
        return (s, AppsModel(s, read: { self.text($0).isEmpty ? nil : self.text($0) }, today: T, db: db))
    }
    var editor: AppsEditor { AppsEditor(root: dir) }
    func smallDB() throws -> UniDB {
        let u = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("unis-small.json")
        return try UniDB(json: Data(contentsOf: u))
    }

    // MARK: the model (unit-apps.mjs)

    func testSchoolsCapAndConflict() throws {
        let (_, m) = model()
        XCTAssertEqual(m.schools.map(\.id).sorted(), ["columbia", "northwestern", "tufts", "university-of-southern-california"])
        let nw = try XCTUnwrap(m.school("northwestern"))
        XCTAssertEqual(nw.applying, true); XCTAssertEqual(nw.round, "ed"); XCTAssertEqual(nw.internalDate, "2026-10-15")
        XCTAssertEqual(nw.deadline, "2026-11-01"); XCTAssertEqual(nw.research.rounds["ed"]?.rate, 20.4); XCTAssertEqual(nw.short, "Northwestern")
        XCTAssertEqual(nw.path, "applications/northwestern/workstream.yaml"); XCTAssertEqual(nw.tasksPath, "applications/northwestern/tasks.yaml")
        let usc = try XCTUnwrap(m.school("university-of-southern-california"))
        XCTAssertEqual([usc.short, usc.round, usc.deadline, usc.internalDate], ["USC", "ea", "2026-11-01", "2026-10-15"])
        XCTAssertEqual(m.school("tufts")?.applying, false)
        XCTAssertEqual(m.cap, CapStatus(n: 3, max: 10, over: false, atMax: false))
        XCTAssertNotNil(Apps.edConflict(m.schools, schoolId: "tufts", round: "ed"))
        XCTAssertEqual(["rd", "ea", "ed2"].map { Apps.edConflict(m.schools, schoolId: "tufts", round: $0) }, [nil, nil, nil])
        XCTAssertNil(Apps.edConflict(m.schools, schoolId: "northwestern", round: "ed"))
    }

    func testWorkRunwayBoardAndOrder() throws {
        let (_, m) = model()
        func by(_ id: String) -> WorkItem? { m.items.first { $0.id == id } }
        XCTAssertNil(by("aa01"), "a parent with subtasks is not itself work")
        XCTAssertEqual([by("aa02")?.hours, by("aa03")?.hours], [2, 2])
        XCTAssertEqual(by("aa04")?.due, "2026-11-01")
        XCTAssertEqual(by("cc01")?.due, "2026-10-15"); XCTAssertEqual(by("cc01")?.inherited, true)
        XCTAssertEqual(by("bb01")?.due, "2026-10-15"); XCTAssertEqual(by("bb01")?.hours, 3)
        XCTAssertEqual(by("dd01")?.due, "2026-11-01"); XCTAssertNil(by("ee01")?.due)
        XCTAssertFalse(m.items.contains { $0.school == "tufts" })

        XCTAssertEqual(m.runway.gates.map(\.date), ["2026-10-15", "2026-11-01", "2027-01-01"])
        XCTAssertEqual(m.runway.gates.map(\.soft), [true, false, false])
        XCTAssertEqual(m.runway.gates[0].days, 7); XCTAssertEqual(m.runway.gates[0].hours, 9)
        XCTAssertTrue(m.runway.gates[1].binding); XCTAssertEqual(m.runway.gates[1].items.count, 2); XCTAssertTrue(m.runway.gates[1].rounds.contains("ED"))
        XCTAssertEqual(m.runway.undated?.items.map(\.id), ["ee01"])
        XCTAssertEqual(m.runway.openHours, 16)

        let why = try XCTUnwrap(m.board.first { $0.fam.id == "why" })
        XCTAssertEqual(why.master.id, "n2")
        XCTAssertEqual(why.ladder.map { [$0.essay.id, $0.cut] }, [["c1", "cut to 150"]])
        XCTAssertEqual(m.board.map(\.fam.id), ["story", "bg", "why"])
        XCTAssertEqual(m.board[0].master.id, "ca1")
        XCTAssertEqual(m.essays.first { $0.id == "ca1" }?.general, true)

        XCTAssertTrue(m.ordered.prefix(4).allSatisfy { $0.due == "2026-10-15" })
        XCTAssertTrue(m.ordered.allSatisfy { $0.why.count > 3 })
        let pace = try XCTUnwrap(m.pace)
        XCTAssertEqual([pace.hoursPerDay, pace.hours], [1.5, 9]); XCTAssertEqual(pace.forDate, "2026-10-15")
        let sg = Apps.suggestSchedule(m.ordered, today: T, hoursPerDay: 1.5)
        XCTAssertEqual(sg.hours, 16, accuracy: 1e-9)
        XCTAssertTrue(sg.perDay.values.allSatisfy { $0 <= 1.5 + 1e-9 })
        XCTAssertNotNil(sg.perDay[T])
        let fast = Apps.suggestSchedule(m.ordered, today: T, hoursPerDay: 3)
        XCTAssertLessThan(fast.days.last!, sg.days.last!)
    }

    // MARK: detail edits

    func testDetailEditKeepsTheRestOfTheFile() throws {
        let src = "id: x\nname: X # my school\nresearch:\n  usn: 9   # a comment\napplying: false\ntasks: []\n"
        let a = try DetailEdit.set(src, key: "applying", .bool(true))
        XCTAssertEqual(a, src.replacingOccurrences(of: "applying: false", with: "applying: true"))
        let b = try DetailEdit.set(src, key: "round", .string("ed"))
        XCTAssertEqual(b, "id: x\nname: X # my school\nresearch:\n  usn: 9   # a comment\napplying: false\nround: ed\ntasks: []\n")
        let c = try DetailEdit.set(src, key: "research", nil)
        XCTAssertEqual(c, "id: x\nname: X # my school\napplying: false\ntasks: []\n")
        let d = try DetailEdit.set(src, key: "essays", .array([.object([("id", .string("x1")), ("title", .string("Why X: the short one")), ("lim", .number(150))])]))
        XCTAssertTrue(d.contains("essays:\n  - id: x1\n    title: \"Why X: the short one\"\n    lim: 150\n"), d)
        XCTAssertThrowsError(try DetailEdit.set(src, key: "id", .string("y")))
        XCTAssertThrowsError(try DetailEdit.set("{id: x, name: X}\n", key: "applying", .bool(true)))
        // text that reads as another type is quoted
        let e = try DetailEdit.set("name: X\n", key: "short", .string("true"))
        XCTAssertEqual(e, "name: X\nshort: \"true\"\n")
        XCTAssertEqual(try YamlValue.document(e)["short"], .string("true"))
    }

    // MARK: the universities database

    func testDatabaseLinksSystemsAndRows() throws {
        let db = try smallDB()
        XCTAssertEqual(db.list.count, 8)
        let (_, m) = model(db: db)
        XCTAssertEqual(Unis.link(try XCTUnwrap(m.school("northwestern")), db).u?.id, 147767)
        XCTAssertEqual(Unis.link(try XCTUnwrap(m.school("columbia")), db).u?.name, "Columbia University in the City of New York")
        let rows = m.rows(db)
        XCTAssertEqual(rows.count, 8, "every database school; the four folders all link to one")
        XCTAssertEqual(rows.filter(\.mine).count, 4)
        let berkeley = try XCTUnwrap(rows.first { $0.u?.id == 110635 })
        XCTAssertEqual(berkeley.system, "uc")
        var f = Unis.Filters()
        f.tier = []
        XCTAssertTrue(rows.allSatisfy { Unis.passes($0, f) })
        XCTAssertTrue(Unis.matches(berkeley, "berkeley"))
        let sorted = Unis.sortRows(rows, dir: 1) { r in Unis.accOf(r).map { Unis.Key.n($0) } }
        XCTAssertEqual(sorted.count, 8)
    }

    func testConsiderAUCCampusBringsTheSystemWithOneUndo() throws {
        let db = try smallDB()
        var (s, m) = model(db: db)
        let rows = m.rows(db)
        let ucla = try XCTUnwrap(rows.first { $0.u?.id == 110662 })
        let (c, id) = try editor.consider(ucla, model: m, rows: rows, tier: "target", snapshot: s, today: T)
        XCTAssertFalse(id.isEmpty)
        (s, m) = model(db: db)
        let uc = m.schools.filter { $0.system == "uc" }
        XCTAssertEqual(uc.count, 2, "UCLA and Berkeley (the two campuses in the small database)")
        XCTAssertEqual(m.school(id)?.tier, "target")
        try TaskEditor(root: dir).undo(c)
        (s, m) = model(db: db)
        XCTAssertEqual(m.schools.filter { $0.system == "uc" }.count, 0)
        XCTAssertEqual(m.folder.dropped.count, 2)
    }

    // MARK: writes with Undo

    func testStartApplyingMakesEssaysChecklistAndTask() throws {
        var (s, m) = model()
        let tufts = try XCTUnwrap(m.school("tufts"))
        let plan = m.startPlan(tufts, round: "ed")
        XCTAssertEqual(plan.dl, "2026-11-02"); XCTAssertNotNil(plan.conflict)
        let c = try editor.startApplying(tufts, round: "rd", model: m, snapshot: s, today: T)
        (s, m) = model()
        let t2 = try XCTUnwrap(m.school("tufts"))
        XCTAssertEqual(t2.applying, true); XCTAssertEqual(t2.round, "rd")
        XCTAssertEqual(t2.essays.map(\.title), ["Why Tufts"]); XCTAssertEqual(t2.essays.first?.fam, "why"); XCTAssertEqual(t2.essays.first?.lim, 150)
        XCTAssertEqual(t2.requirements.map(\.t), ["Common App (shared)", "Supplemental essays", "Counsellor recommendation", "Teacher recommendation", "Test scores sent"])
        XCTAssertTrue(s.tasks.values.contains { $0.title == "Tufts supplemental essays" && $0.due == "2027-01-04" })
        try TaskEditor(root: dir).undo(c)
        XCTAssertEqual(text("applications/tufts/workstream.yaml"), Self.TU.1)
        XCTAssertEqual(text("applications/tufts/tasks.yaml"), "tasks: []\n")
    }

    func testAddSchoolTiersEssaysAndChecklist() throws {
        var (s, m) = model()
        let (c, id) = try editor.addSchool("Rice University", model: m, tier: "reach", level: 2, round: "ea", dl: "2026-11-01", snapshot: s, today: T)
        XCTAssertEqual(id, "rice-university")
        (s, m) = model()
        let r = try XCTUnwrap(m.school(id))
        XCTAssertEqual(r.tier, "reach"); XCTAssertEqual(r.tierLevel, 2); XCTAssertEqual(r.research.rounds["ea"]?.dl, "2026-11-01"); XCTAssertFalse(r.applying)
        XCTAssertThrowsError(try editor.addSchool("Rice University", model: m, snapshot: s, today: T))
        let e = try editor.addEssay(r, title: "Why Rice?", lim: 150, unit: "words")
        (s, m) = model()
        XCTAssertEqual(m.school(id)?.essays.map(\.id), ["rice1"])
        XCTAssertEqual(m.school(id)?.essays.first?.fam, "why")
        try TaskEditor(root: dir).undo(e)
        try TaskEditor(root: dir).undo(c)
        (s, m) = model()
        XCTAssertNil(m.schools.first { $0.id == id }, "Undo of an add marks the school removed")
        XCTAssertEqual(m.folder.dropped.map(\.id), [id])
        // put back
        _ = try editor.addSchool("Rice University", model: m, snapshot: s, today: T)
        (s, m) = model()
        XCTAssertNotNil(m.schools.first { $0.id == id })
    }

    func testLooseTierOfASchoolWithNoFolder() throws {
        let db = try smallDB()
        let (_, m) = model(db: db)
        let mit = try XCTUnwrap(m.rows(db).first { $0.u?.id == 166683 })
        _ = try editor.setTier(mit, tier: "dream", level: nil, model: m)
        let (_, m2) = model(db: db)
        let row = try XCTUnwrap(m2.rows(db).first { $0.u?.id == 166683 })
        XCTAssertEqual(row.t?.tier, "dream")
        XCTAssertEqual(Unis.tierOf(row), "dream")
        XCTAssertNil(m2.school("massachusetts-institute-of-technology"), "a tier never makes a folder")
    }

    func testRequirementsAppliedAndMoveBack() throws {
        var (s, m) = model()
        var nw = try XCTUnwrap(m.school("northwestern"))
        _ = try editor.addRequirement(nw, "Interview")
        (s, m) = model(); nw = try XCTUnwrap(m.school("northwestern"))
        _ = try editor.toggleRequirement(nw, at: 0)
        (s, m) = model(); nw = try XCTUnwrap(m.school("northwestern"))
        XCTAssertEqual(nw.requirements.first?.done, true)
        _ = try editor.setApplied(nw, true, model: m, today: T)
        (s, m) = model(); nw = try XCTUnwrap(m.school("northwestern"))
        XCTAssertEqual(nw.applied, T)
        _ = try editor.moveBack(nw, model: m)
        (s, m) = model()
        XCTAssertEqual(m.school("northwestern")?.applying, false)
        _ = s
    }

    func testAcceptScheduleWritesPlansAndHours() throws {
        let (s, m) = model()
        let sg = m.suggestion(hoursPerDay: 1.5)
        let c = try editor.acceptSchedule(m, schedule: sg.schedule, hoursPerDay: 1.5, snapshot: s)
        let (s2, m2) = model()
        XCTAssertFalse(s2.tasks["aa02"]?.plan.isEmpty ?? true)
        XCTAssertEqual(m2.folder.writingHours, 1.5)
        try TaskEditor(root: dir).undo(c)
        XCTAssertEqual(text("applications/northwestern/tasks.yaml"), Self.NW.2)
        XCTAssertEqual(text("applications/overview/workstream.yaml"), Self.OV.1)
    }

    // MARK: Claude's research

    func testProfileKeepsOnlySourcedFiguresAndYourOwnRates() throws {
        let reply = """
        Here it is:
        ```json
        {"brief": "A strong engineering school.", "rounds": {"ed": {"offered": true, "rate": "21.5%", "of": "Class of 2029", "src": "https://nu.edu/cds"},
         "ea": {"offered": false}, "rd": {"offered": true, "rate": 5.2, "of": "Class of 2029", "how": "derived", "note": "C1 minus C21"}},
         "city": {"name": "Evanston, IL", "about": "Leafy."}, "opportunities": ["Co-ops"], "greek": {"men": 30, "women": 34, "src": "https://nu.edu/f1"},
         "concerns": [{"issue": "Cold", "detail": "Long winters"}], "sources": ["https://nu.edu/cds", "not a url"]}
        ```
        """
        let p = try XCTUnwrap(SchoolProfile.parse(reply))
        XCTAssertEqual(p.rounds["ed"]?.rate, 21.5)
        XCTAssertNil(p.rounds["rd"]?.rate, "a rate without its page is left out")
        XCTAssertEqual(p.rounds["ea"]?.offered, false)
        XCTAssertEqual(SchoolProfile.greekOf(p.greek), 32)
        XCTAssertEqual(SchoolProfile.greekLevel(32), -2)
        XCTAssertEqual(p.sources, ["https://nu.edu/cds"])
        XCTAssertEqual(SchoolProfile.entryYear("Class of 2029"), 2025)
        XCTAssertEqual(SchoolProfile.entryYear("2024-25"), 2024)

        let (_, m) = model()
        let nw = try XCTUnwrap(m.school("northwestern"))
        let (c, out) = try editor.saveProfile(nw, p, today: T)
        XCTAssertEqual(out.kept, ["ed"], "the 20.4 in the file was typed by hand")
        XCTAssertEqual(out.filled, [])
        let (_, m2) = model()
        let after = try XCTUnwrap(m2.school("northwestern"))
        XCTAssertEqual(after.research.rounds["ed"]?.rate, 20.4)
        XCTAssertEqual(SchoolProfile(after.rawResearch["profile"])?.brief, "A strong engineering school.")
        XCTAssertEqual(after.research.usn, 9, "the rest of research stays")
        try TaskEditor(root: dir).undo(c)
        XCTAssertEqual(text("applications/northwestern/workstream.yaml"), Self.NW.1)
    }

    // MARK: the site check

    func testSiteCheckKeepsOnlyQuotesOnThePage() throws {
        let html = """
        <html><head><title>x</title><script>var a = "Early Decision: November 1";</script></head><body>
        <h1>Apply</h1><table><tr><td>Early Decision</td><td>November 1</td></tr></table>
        <p>Regular Decision applications are due January&nbsp;4, 2027.</p>
        <p>Two teacher recommendations are required.</p>
        <a href="/admissions/deadlines">Key dates and deadlines</a> <a href="https://other.org/x">Deadlines</a> <a href="/about">About</a>
        <a href="/apply/first-year.pdf">First-year checklist (PDF)</a>
        </body></html>
        """
        let text = SiteFacts.htmlToText(html)
        XCTAssertFalse(text.contains("var a"))
        XCTAssertTrue(text.contains("Regular Decision applications are due January 4, 2027."))
        let links = SiteFacts.pickLinks(html, base: "https://www.nu.edu/admissions/")
        XCTAssertEqual(links.map(\.url), ["https://www.nu.edu/admissions/deadlines"])
        XCTAssertEqual(SiteFacts.siteOf("admissions.ox.ac.uk"), "ox.ac.uk")
        XCTAssertEqual(SiteFacts.cycleOf("2026-10-08"), SiteFacts.Cycle(start: "2026-08-01", end: "2027-07-31", year: 2026))
        XCTAssertEqual(SiteFacts.cycleOf("2027-02-01").year, 2026)

        let reply = """
        {"rounds":[{"round":"ed","date":"2026-11-01","quote":"Early Decision | November 1","url":"https://www.nu.edu/admissions/"},
                   {"round":"rd","date":"2027-01-04","quote":"Regular Decision applications are due January 4, 2027.","url":"https://www.nu.edu/admissions/"},
                   {"round":"ea","date":"2026-11-15","quote":"Early Action is due November 15.","url":"https://www.nu.edu/admissions/"}],
         "notOffered":["ed2"],"requirements":[{"text":"Two teacher recommendations","quote":"Two teacher recommendations are required.","url":"https://www.nu.edu/admissions/"}],"testing":null}
        """
        let found = try XCTUnwrap(SiteFacts.parse(reply))
        let kept = SiteFacts.verify(found, pages: [SiteFacts.Page(url: "https://www.nu.edu/admissions/", text: text)], cycle: SiteFacts.cycleOf(T))
        XCTAssertEqual(kept.rounds.map(\.round), ["ed", "rd"])
        XCTAssertEqual(kept.dropped.map(\.why), ["quote not on the page"])
        let (_, m) = model()
        let nw = try XCTUnwrap(m.school("northwestern"))
        let items = SiteFacts.diff(kept, school: nw)
        XCTAssertEqual(items.map(\.status), ["same", "same", "", "new"])
        XCTAssertEqual(items.filter(\.on).map(\.label), ["Two teacher recommendations"])
        _ = try editor.saveFindings(nw, take: items, host: "nu.edu", today: T)
        let (_, m2) = model()
        let after = try XCTUnwrap(m2.school("northwestern"))
        XCTAssertEqual(after.research.reqs.map(\.t), ["Two teacher recommendations"])
        XCTAssertEqual(after.research.checked, T)
        XCTAssertTrue(after.requirements.contains { $0.t == "Two teacher recommendations" }, "an applying school's checklist gets it too")
        XCTAssertEqual(after.research.rounds["ed"]?.rate, 20.4)
    }
}
