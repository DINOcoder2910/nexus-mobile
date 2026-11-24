import XCTest
@testable import NexusCore

/// Workstream edits as the laptop makes them (ops.js plan*Workstream, the new app's workstreams.rs): ids and folders from the name,
/// rename with its [[links]], move with path links, park, colour, decisions under their heading, a person's sessions; each one Undo.
/// The expected texts are the laptop's own test cases (workstreams.rs `decisions_go_under_their_heading`, `session_names`).
final class WorkstreamEditTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-ws-\(UUID().uuidString)")
        try put("nexus.yaml", "nexus: 2\n")
        try put("inbox.yaml", "tasks: []\n")
        try put("classes/group.yaml", "label: Classes\n")
        try put("classes/chem/workstream.yaml", "# chemistry\nid: chem\nname: Chemistry HL\ncolor: green\nstatus: active\n")
        try put("classes/chem/tasks.yaml", "tasks:\n  - id: c1\n    title: Lab write-up\n")
        try put("classes/chem/notes.md", "# Chemistry\n\nSee [[classes/chem/files/lab.pdf|the lab]] and [[Physics HL#Waves]].\n")
        try put("projects/group.yaml", "label: Projects\n")
        try put("projects/nexus/workstream.yaml", "id: nexus\nname: Nexus\nstatus: active\n")
        try put("projects/chem/notes.txt", "a folder named chem is here already")
        try put("people/group.yaml", "label: People\nkind: person\n")
        try put("people/ms-lee/workstream.yaml", "id: ms-lee\nname: Ms Lee\nrole: counsellor\nstatus: active\n")
        try put("journal.md", "Talked to [[chemistry hl]] about [[Chemistry HL|chem]], ![[classes/chem/files/x.png]], [[task:c1]].\n")
        try put("NEXUS.md", "[[Chemistry HL]] stays: Claude's rules are not notes.\n")
        try put("notebooks/Chem/R1/Lesson.board/text/a.md", "[[Chemistry HL]] in a board stays: its words are the .jsonl\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func put(_ rel: String, _ text: String) throws {
        let u = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }
    func text(_ rel: String) -> String { (try? String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)) ?? "" }
    func has(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(rel).path) }
    var ed: WorkstreamEditor { WorkstreamEditor(root: dir) }
    func snap() -> Snapshot { DataFolder.load(dir) }

    func testSlugs() {
        XCTAssertEqual(WorkstreamText.slugBase("Physics HL"), "physics-hl")
        XCTAssertEqual(WorkstreamText.slugBase("Español & Art"), "espanol-and-art")
        XCTAssertEqual(WorkstreamText.slugBase("  "), "workstream")
        XCTAssertEqual(WorkstreamText.slugBase("files"), "files-1")
        XCTAssertEqual(WorkstreamText.slugBase("CON"), "con-1")
        XCTAssertEqual(WorkstreamText.slugBase(String(repeating: "word ", count: 20)).count <= 60, true)
        XCTAssertFalse(WorkstreamText.slugBase(String(repeating: "word ", count: 20)).hasSuffix("-"))
        XCTAssertEqual(WorkstreamText.slugId("Chem", taken: ["chem"]), "chem-2")
        XCTAssertEqual(WorkstreamText.slugId("Chem", taken: ["chem", "chem-2"]), "chem-3")
    }

    func testScalarsAsTheLaptopWritesThem() {
        XCTAssertEqual(WorkstreamText.scalar("Physics HL"), "Physics HL")
        XCTAssertEqual(WorkstreamText.scalar("yes"), "\"yes\"")
        XCTAssertEqual(WorkstreamText.scalar("ED: Columbia"), "\"ED: Columbia\"")
        XCTAssertEqual(WorkstreamText.scalar("Español"), "\"Español\"")
        XCTAssertEqual(WorkstreamText.scalar("2026 plans"), "\"2026 plans\"")
        XCTAssertEqual(WorkstreamText.manifest(id: "art", name: "Art"), "id: art\nname: Art\nstatus: active\n")
    }

    func testLinksAreRewrittenKeepingLabelsAndHeadings() {
        let t = "[[Old|label]] [[old#Head]] ![[Old]] [[task:Old]] [[Other]]"
        XCTAssertEqual(WorkstreamText.rewriteLinks(t) { $0.lowercased() == "old" ? "New" : nil }, "[[New|label]] [[New#Head]] ![[New]] [[task:Old]] [[Other]]")
    }

    func testCreateMakesTheManifestAndUndoTakesItAway() throws {
        let (c, id) = try ed.create(group: "projects", name: "Chem", in: snap())
        // a folder named chem is in projects already, and chem is a workstream id
        XCTAssertEqual(id, "chem-2")
        XCTAssertEqual(text("projects/chem-2/workstream.yaml"), "id: chem-2\nname: Chem\nstatus: active\n")
        let s = snap()
        XCTAssertEqual(s.workstreams["chem-2"]?.group, "projects")
        XCTAssertTrue(s.groups.first { $0.id == "projects" }!.workstreams.contains("chem-2"))
        XCTAssertThrowsError(try ed.create(group: "projects", name: "  ", in: s))
        XCTAssertThrowsError(try ed.create(group: "nowhere", name: "X", in: s))
        try TaskEditor(root: dir).undo(c)
        XCTAssertFalse(has("projects/chem-2"))
        XCTAssertNil(snap().workstreams["chem-2"])
    }

    func testRenameChangesTheNameLineAndLinks() throws {
        let w = snap().workstreams["chem"]!
        let c = try ed.rename(w, to: "Chemistry SL", in: snap())
        XCTAssertEqual(text("classes/chem/workstream.yaml"), "# chemistry\nid: chem\nname: Chemistry SL\ncolor: green\nstatus: active\n")
        XCTAssertEqual(text("journal.md"), "Talked to [[Chemistry SL]] about [[Chemistry SL|chem]], ![[classes/chem/files/x.png]], [[task:c1]].\n")
        XCTAssertEqual(text("NEXUS.md"), "[[Chemistry HL]] stays: Claude's rules are not notes.\n")
        XCTAssertTrue(text("notebooks/Chem/R1/Lesson.board/text/a.md").hasPrefix("[[Chemistry HL]]"))
        XCTAssertEqual(snap().workstreams["chem"]?.name, "Chemistry SL")
        XCTAssertEqual(snap().workstreams["chem"]?.folder, "classes/chem")
        try TaskEditor(root: dir).undo(c)
        XCTAssertEqual(snap().workstreams["chem"]?.name, "Chemistry HL")
        XCTAssertTrue(text("journal.md").hasPrefix("Talked to [[chemistry hl]]"))
    }

    func testMoveTakesTheFolderAndItsPathLinks() throws {
        let w = snap().workstreams["chem"]!
        let c = try ed.move(w, to: "projects", in: snap())
        // projects has a "chem" folder already
        XCTAssertFalse(has("classes/chem"))
        XCTAssertTrue(has("projects/chem-2/workstream.yaml"))
        let s = snap()
        XCTAssertEqual(s.workstreams["chem"]?.folder, "projects/chem-2")
        XCTAssertEqual(s.tasks["c1"]?.workstream, "chem")
        XCTAssertEqual(text("projects/chem-2/notes.md"), "# Chemistry\n\nSee [[projects/chem-2/files/lab.pdf|the lab]] and [[Physics HL#Waves]].\n")
        XCTAssertEqual(text("journal.md"), "Talked to [[chemistry hl]] about [[Chemistry HL|chem]], ![[projects/chem-2/files/x.png]], [[task:c1]].\n")
        try TaskEditor(root: dir).undo(c)
        XCTAssertTrue(has("classes/chem/workstream.yaml"))
        XCTAssertFalse(has("projects/chem-2"))
        XCTAssertEqual(text("classes/chem/notes.md"), "# Chemistry\n\nSee [[classes/chem/files/lab.pdf|the lab]] and [[Physics HL#Waves]].\n")
        XCTAssertTrue(text("journal.md").contains("![[classes/chem/files/x.png]]"))
    }

    func testParkAndColour() throws {
        var w = snap().workstreams["chem"]!
        let c = try ed.park(w, true, in: snap())
        XCTAssertEqual(text("classes/chem/workstream.yaml"), "# chemistry\nid: chem\nname: Chemistry HL\ncolor: green\nstatus: parked\n")
        XCTAssertTrue(snap().workstreams["chem"]!.parked)
        // parked work leaves the counts
        XCTAssertFalse(snap().counts(snap().tasks["c1"]!))
        try TaskEditor(root: dir).undo(c)
        XCTAssertFalse(snap().workstreams["chem"]!.parked)
        w = snap().workstreams["chem"]!
        _ = try ed.color(w, "teal", in: snap())
        XCTAssertEqual(snap().workstreams["chem"]?.color, "teal")
        XCTAssertThrowsError(try ed.color(w, "magenta", in: snap()))
        // a workstream with no colour of its own gets the line
        _ = try ed.color(snap().workstreams["nexus"]!, "rose", in: snap())
        XCTAssertEqual(text("projects/nexus/workstream.yaml"), "id: nexus\nname: Nexus\nstatus: active\ncolor: rose\n")
    }

    func testDecisionsGoUnderTheirHeading() throws {
        typealias T = WorkstreamText
        XCTAssertEqual(T.addDecision("", date: "2026-11-23", "Drop it"), "## Decisions\n\n- 2026-11-23 Drop it\n")
        XCTAssertEqual(T.addDecision("# Chem\n\nSome notes", date: "2026-11-23", "Drop\nit"), "# Chem\n\nSome notes\n\n## Decisions\n\n- 2026-11-23 Drop it\n")
        let t = "# Chem\n\n## Decisions\n\n- 2026-11-01 First\n\n## Later\n\nmore\n"
        XCTAssertEqual(T.addDecision(t, date: "2026-11-23", "Second"), "# Chem\n\n## Decisions\n\n- 2026-11-01 First\n- 2026-11-23 Second\n\n## Later\n\nmore\n")
        XCTAssertEqual(T.addDecision("## Decisions\n### Sub\n", date: "2026-11-23", "X"), "## Decisions\n### Sub\n- 2026-11-23 X\n")
        let ds = T.decisions(T.addDecision(t, date: "2026-11-23", "Second"))
        XCTAssertEqual(ds.first, .init(date: "2026-11-23", text: "Second"))
        XCTAssertEqual(ds[1].date, "2026-11-01")
        XCTAssertEqual(T.decisions("## Decisions\n- Undated one\n## Other\n- not one\n"), [.init(date: nil, text: "Undated one")])

        let w = snap().workstreams["nexus"]!
        let c = try ed.decision(w, "Ship on Sundays", date: "2026-11-23", in: snap())
        XCTAssertEqual(text("projects/nexus/notes.md"), "## Decisions\n\n- 2026-11-23 Ship on Sundays\n")
        try TaskEditor(root: dir).undo(c)
        XCTAssertFalse(has("projects/nexus/notes.md"))
    }

    func testSessionNames() {
        XCTAssertEqual(WorkstreamText.datedNoteName(date: "2026-10-30", title: "Essays: round 2?"), "2026-10-30 Essays round 2.md")
        XCTAssertEqual(WorkstreamText.datedNoteName(date: "2026-10-30", title: "  "), "2026-10-30.md")
        XCTAssertNil(WorkstreamText.datedNoteName(date: "30 Oct", title: "x"))
        let s = WorkstreamText.sessions(["2026-10-30 Essays.md", "notes.md", "2026-11-02.md", "2026-11-01 Plan.MD"], folder: "people/ms-lee")
        XCTAssertEqual(s.map(\.title), ["Session", "Plan", "Essays"])
        XCTAssertEqual(s.first?.path, "people/ms-lee/2026-11-02.md")
    }

    func testANewSessionWithItsTask() throws {
        let s = snap()
        let lee = s.workstreams["ms-lee"]!
        XCTAssertEqual(lee.kind, "person")
        let (c, path) = try ed.session(lee, title: "Essays", date: "2026-11-23", task: true, in: s, today: "2026-11-23")
        XCTAssertEqual(path, "people/ms-lee/2026-11-23 Essays.md")
        XCTAssertEqual(text(path), "## Before\n\n## Discussed\n\n## Out of it\n")
        let t = snap().tasks.values.first { $0.title == "Essays session" }
        XCTAssertEqual(t?.due, "2026-11-23")
        XCTAssertEqual(t?.workstream, "ms-lee")
        XCTAssertThrowsError(try ed.session(lee, title: "Essays", date: "2026-11-23", task: false, in: snap(), today: "2026-11-23"))
        XCTAssertThrowsError(try ed.session(snap().workstreams["chem"]!, title: "X", date: "2026-11-23", task: false, in: snap(), today: "2026-11-23"))
        try TaskEditor(root: dir).undo(c)
        XCTAssertFalse(has(path))
        XCTAssertFalse(has("people/ms-lee/tasks.yaml"))
    }

    func testReadOnlyFoldersAreLeftAlone() throws {
        try put("nexus.yaml", "nexus: 1\n")
        XCTAssertThrowsError(try ed.create(group: "projects", name: "X", in: snap()))
        XCTAssertThrowsError(try ed.park(snap().workstreams["chem"]!, true, in: snap()))
    }
}

/// The Planner's spans and its Show row (Planner.tsx): any number of days, and what the days leave out.
final class PlannerShowTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-show-\(UUID().uuidString)")
        func put(_ rel: String, _ text: String) throws {
            let u = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try put("nexus.yaml", "nexus: 2\n")
        try put("inbox.yaml", "tasks:\n  - {id: i1, title: Call the bank, plan: [2026-11-21]}\n")
        try put("classes/group.yaml", "label: Classes\n")
        try put("classes/chem/workstream.yaml", "id: chem\nname: Chemistry HL\nstatus: active\n")
        try put("classes/chem/tasks.yaml", "tasks:\n  - {id: c1, title: Redox set, plan: [2026-11-20], est: 1h}\n  - {id: c2, title: Test, due: 2026-11-22}\n  - {id: c3, title: Far, plan: [2026-12-20]}\n")
        try put("classes/phys/workstream.yaml", "id: phys\nname: Physics HL\nstatus: active\n")
        try put("classes/phys/tasks.yaml", "tasks:\n  - {id: p1, title: Waves, plan: [2026-11-21]}\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func week(_ n: Int) -> WeekPlan.Week {
        WeekPlan.week(Planning(DataFolder.load(dir), today: "2026-11-20"), start: "2026-11-20", now: 600, days: n) { _ in [] }
    }

    func testSpans() {
        XCTAssertEqual(week(2).days.map(\.date), ["2026-11-20", "2026-11-21"])
        XCTAssertEqual(week(3).days.count, 3)
        let m = week(35)
        XCTAssertEqual(m.days.count, 35)
        XCTAssertEqual(m.days.last?.date, "2026-12-24")
        XCTAssertTrue(m.lanes.allSatisfy { $0.days.count == 35 })
        XCTAssertEqual(m.days.first { $0.date == "2026-12-20" }?.planned.map(\.title), ["Far"])
        // a lane per subject with work on the days shown, the Inbox last
        XCTAssertEqual(week(2).lanes.map(\.workstream), ["chem", "phys", nil])
    }

    func testShowHidesKindsAndWorkstreams() {
        let w = week(7)
        var show = PlannerShow()
        XCTAssertEqual(show.apply(w), w)
        XCTAssertEqual(show.pills(w), ["chem", "phys", "inbox"])
        show.flip(workstream: "chem")
        let a = show.apply(w)
        XCTAssertEqual(a.lanes.map(\.workstream), ["phys", nil])
        XCTAssertTrue(a.days.allSatisfy { $0.deadlines.isEmpty })
        XCTAssertEqual(a.days[0].planned.map(\.title), [])
        // the load stays what is planned
        XCTAssertEqual(a.days[0].load, 60)
        // a hidden one keeps its pill
        XCTAssertEqual(show.pills(w), ["chem", "phys", "inbox"])
        show.flip(.plan)
        XCTAssertTrue(show.apply(w).lanes.isEmpty)
        XCTAssertTrue(show.apply(w).days.allSatisfy { $0.planned.isEmpty })
        show.flip(calendar: "School|Work")
        let back = PlannerShow(text: show.text)
        XCTAssertEqual(back, show)
        XCTAssertTrue(back.calendars.contains("School|Work"))
        XCTAssertEqual(PlannerShow(text: ""), PlannerShow())
    }
}
