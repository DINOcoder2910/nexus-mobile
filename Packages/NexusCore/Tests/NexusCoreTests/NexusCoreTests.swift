import XCTest
@testable import NexusCore

/// The fixture is a copy of the laptop's dev/fixtures/data-vault (its YAML files), so both apps are tested on the same folder.
final class FolderTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        let src = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("data-vault")
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-core-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: src, to: dir)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func text(_ rel: String) throws -> String { try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8) }

    func testLoadsGroupsWorkstreamsAndTasks() throws {
        let s = DataFolder.load(dir)
        XCTAssertTrue(s.isDataFolder)
        XCTAssertNil(s.readOnlyReason)
        XCTAssertEqual(s.problems, [])
        XCTAssertEqual(s.groups.first?.id, "classes")
        XCTAssertTrue(s.groups.map(\.id).contains("people"))
        let beta = try XCTUnwrap(s.workstreams["beta"])
        XCTAssertEqual(beta.name, "Beta class")
        XCTAssertEqual(beta.folder, "classes/beta")
        let lab4 = try XCTUnwrap(s.tasks["lab4"])
        XCTAssertEqual(lab4.depth, 3)
        XCTAssertEqual(lab4.parent, "lab3")
        XCTAssertEqual(lab4.est, "15m")
        XCTAssertEqual(lab4.note, "Goggles and gloves.\nAsk the technician about the acid.\n")
        XCTAssertEqual(lab4.workstream, "beta")
        XCTAssertEqual(s.tasks["lab3"]?.plan, [PlanEntry(day: "2026-11-02", time: "15:00")])
        XCTAssertEqual(s.tasks["lab7"]?.waitingOn, "Ms Settle")
        XCTAssertEqual(s.tasks["lab7"]?.waitingSince, "2026-10-26")
        XCTAssertEqual(s.tasks["lab5"]?.doneOn, "2026-10-27")
        XCTAssertEqual(s.tasks["pz53"]?.done, true)
        XCTAssertNil(s.tasks["pz53"]?.doneOn)
        XCTAssertEqual(s.tasks["sdn4"]?.someday, true)
        XCTAssertNil(s.tasks["sdn4"]?.workstream)
        XCTAssertEqual(s.tasks["lab8"]?.someday, true)
        XCTAssertEqual(s.tasks["zq48"]?.title, "Suspicious: sender x@example.com, subject \"THANK YOU\"")
        XCTAssertEqual(s.descendants(of: s.tasks["lab1"]!).map(\.id), ["lab2", "lab3", "lab4", "lab5", "lab6", "lab7", "lab8"])
    }

    func testReadingWritesNothing() throws {
        let before = try text("classes/beta/tasks.yaml")
        _ = DataFolder.load(dir)
        XCTAssertEqual(try text("classes/beta/tasks.yaml"), before)
    }

    func testTickALeafAddsOneLine() throws {
        let s = DataFolder.load(dir)
        let before = try text("classes/beta/tasks.yaml")
        let c = try TaskEditor(root: dir).tick(s.tasks["lab4"]!, in: s, today: "2026-11-11")
        let after = try text("classes/beta/tasks.yaml")
        XCTAssertEqual(after, c.after)
        XCTAssertEqual(after, before.replacingOccurrences(of: "                title: Check the safety sheet\n",
                                                          with: "                title: Check the safety sheet\n                done: 2026-11-11\n"))
        XCTAssertEqual(c.offerParent, "lab3") // lab5, its other subtask, was done already
        XCTAssertEqual(DataFolder.load(dir).tasks["lab4"]?.doneOn, "2026-11-11")
    }

    func testTickTheLastSubtaskOffersTheParent() throws {
        let s = DataFolder.load(dir)
        let e = TaskEditor(root: dir)
        let first = try e.tick(s.tasks["lab3"]!, in: s, today: "2026-11-11")
        XCTAssertNil(first.offerParent) // lab6 is still open under lab2
        let s2 = DataFolder.load(dir)
        let c = try e.tick(s2.tasks["lab6"]!, in: s2, today: "2026-11-11")
        XCTAssertEqual(c.offerParent, "lab2")
    }

    func testTickAParentTicksItsOpenSubtasks() throws {
        let s = DataFolder.load(dir)
        let c = try TaskEditor(root: dir).tick(s.tasks["lab3"]!, in: s, today: "2026-11-11")
        let s2 = DataFolder.load(dir)
        XCTAssertEqual(s2.tasks["lab3"]?.doneOn, "2026-11-11")
        XCTAssertEqual(s2.tasks["lab4"]?.doneOn, "2026-11-11")
        XCTAssertEqual(s2.tasks["lab5"]?.doneOn, "2026-10-27") // was done before: left as it was
        XCTAssertFalse(s2.tasks["lab6"]!.done) // a sibling, not under it
        XCTAssertTrue(c.message.contains("and 1 open subtask"))
    }

    func testUntickReopensTheDoneTaskAbove() throws {
        let s = DataFolder.load(dir)
        let e = TaskEditor(root: dir)
        _ = try e.tick(s.tasks["lab3"]!, in: s, today: "2026-11-11")
        let s2 = DataFolder.load(dir)
        _ = try e.untick(s2.tasks["lab4"]!, in: s2)
        let s3 = DataFolder.load(dir)
        XCTAssertFalse(s3.tasks["lab4"]!.done)
        XCTAssertFalse(s3.tasks["lab3"]!.done)
        XCTAssertTrue(s3.tasks["lab5"]!.done)
    }

    func testUndoPutsTheFileBackByteForByte() throws {
        let s = DataFolder.load(dir)
        let before = try text("classes/beta/tasks.yaml")
        let e = TaskEditor(root: dir)
        let c = try e.plan(s.tasks["tjn4"]!, on: "2026-11-12", in: s)
        XCTAssertNotEqual(try text("classes/beta/tasks.yaml"), before)
        try e.undo(c)
        XCTAssertEqual(try text("classes/beta/tasks.yaml"), before)
    }

    func testUndoRefusesWhenTheFileChangedSince() throws {
        let s = DataFolder.load(dir)
        let e = TaskEditor(root: dir)
        let c = try e.setKey(s.tasks["tjn4"]!, true, in: s)
        try (c.after + "# laptop edit\n").write(to: dir.appendingPathComponent(c.file), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try e.undo(c))
    }

    func testPlanAndUnplan() throws {
        let s = DataFolder.load(dir)
        let e = TaskEditor(root: dir)
        _ = try e.plan(s.tasks["bkd7"]!, on: "2026-11-12", time: "16:00", in: s)
        XCTAssertTrue(try text("classes/beta/tasks.yaml").contains("    plan: [2026-10-26, 2026-11-12 16:00]\n"))
        let s2 = DataFolder.load(dir)
        _ = try e.unplan(s2.tasks["bkd7"]!, from: "2026-10-26", in: s2)
        XCTAssertTrue(try text("classes/beta/tasks.yaml").contains("    key: true\n    plan: [2026-11-12 16:00]\n    tags: [summative]\n"))
        let s3 = DataFolder.load(dir)
        _ = try e.unplan(s3.tasks["bkd7"]!, from: "2026-11-12", in: s3)
        XCTAssertTrue(try text("classes/beta/tasks.yaml").contains("    key: true\n    tags: [summative]\n"))
    }

    func testAddTasks() throws {
        let s = DataFolder.load(dir)
        let e = TaskEditor(root: dir)
        let (_, id) = try e.add(title: "Revise: chapter 3", to: "classes/beta/tasks.yaml", due: "2026-11-20", key: true, in: s, today: "2026-11-11")
        let s2 = DataFolder.load(dir)
        let t = try XCTUnwrap(s2.tasks[id])
        XCTAssertEqual(t.title, "Revise: chapter 3")
        XCTAssertEqual(t.due, "2026-11-20")
        XCTAssertTrue(t.key)
        XCTAssertEqual(t.added, "2026-11-11")
        XCTAssertEqual(s2.top["classes/beta/tasks.yaml"]?.last, id)
        XCTAssertTrue(try text("classes/beta/tasks.yaml").hasSuffix("  - id: \(id)\n    title: 'Revise: chapter 3'\n    due: 2026-11-20\n    key: true\n    added: 2026-11-11\n"))

        // under a task with no subtasks yet
        let (_, sub) = try e.add(title: "First step", to: "classes/beta/tasks.yaml", parent: s2.tasks["tjn4"], in: s2, today: "2026-11-11")
        let s3 = DataFolder.load(dir)
        XCTAssertEqual(s3.tasks["tjn4"]?.children, [sub])
        XCTAssertTrue(try text("classes/beta/tasks.yaml").contains("  - id: tjn4\n    title: Second parent\n    subtasks:\n      - id: \(sub)\n        title: First step\n        added: 2026-11-11\n  - id: bkd7\n"))

        // under a task that has subtasks: at the end of them, at their indent
        let (_, sub2) = try e.add(title: "Conclusion", to: "classes/beta/tasks.yaml", parent: s3.tasks["lab2"], in: s3, today: "2026-11-11")
        let s4 = DataFolder.load(dir)
        XCTAssertEqual(s4.tasks["lab2"]?.children, ["lab3", "lab6", sub2])
        XCTAssertEqual(s4.tasks[sub2]?.depth, 2)
    }

    func testAddToTheInboxAndToAnEmptyFile() throws {
        let s = DataFolder.load(dir)
        let e = TaskEditor(root: dir)
        let (_, id) = try e.add(title: "Call the dentist", to: "inbox.yaml", in: s, today: "2026-11-11")
        XCTAssertEqual(DataFolder.load(dir).inboxTop.last?.id, id)
        let fresh = try YamlEdit.addTask("tasks: []\n", id: "abcd", title: "One")
        XCTAssertEqual(fresh, "tasks:\n  - id: abcd\n    title: One\n")
        let none = try YamlEdit.addTask("", id: "abcd", title: "One")
        XCTAssertEqual(none, "tasks:\n  - id: abcd\n    title: One\n")
    }

    func testEditsKeepCommentsAndTheRest() throws {
        let yaml = "# my tasks\ntasks:\n  # first one\n  - id: aaaa\n    title: A   # inline\n    plan: [2026-11-01]\n\n  - title: B\n    id: bbbb\n    key: true\n"
        let a = try YamlEdit.setField(yaml, id: "aaaa", key: "done", yaml: "2026-11-11")
        XCTAssertEqual(a, "# my tasks\ntasks:\n  # first one\n  - id: aaaa\n    title: A   # inline\n    done: 2026-11-11\n    plan: [2026-11-01]\n\n  - title: B\n    id: bbbb\n    key: true\n")
        let b = try YamlEdit.setField(yaml, id: "bbbb", key: "key", yaml: nil)
        XCTAssertEqual(b, "# my tasks\ntasks:\n  # first one\n  - id: aaaa\n    title: A   # inline\n    plan: [2026-11-01]\n\n  - title: B\n    id: bbbb\n")
        let c = try YamlEdit.setField(yaml, id: "bbbb", key: "due", yaml: "2026-12-01")
        XCTAssertTrue(c.hasSuffix("  - title: B\n    id: bbbb\n    due: 2026-12-01\n    key: true\n"))
        XCTAssertThrowsError(try YamlEdit.setField(yaml, id: "zzzz", key: "key", yaml: "true"))
    }

    func testQuoting() {
        XCTAssertEqual(YamlEdit.scalar("Physics HW"), "Physics HW")
        XCTAssertEqual(YamlEdit.scalar("Re: essay"), "'Re: essay'")
        XCTAssertEqual(YamlEdit.scalar("it's"), "it's")
        XCTAssertEqual(YamlEdit.scalar("'quoted'"), "'''quoted'''")
        XCTAssertEqual(YamlEdit.scalar("yes"), "'yes'")
        XCTAssertEqual(YamlEdit.scalar("2026"), "'2026'")
        XCTAssertEqual(YamlEdit.scalar("Call mom #family"), "'Call mom #family'")
        XCTAssertEqual(YamlEdit.scalar("- bullet"), "'- bullet'")
        for title in ["Re: essay", "it's", "'quoted'", "yes", "Call mom #family", "[x] done", "a \"b\" c"] {
            let yaml = try! YamlEdit.addTask("tasks: []\n", id: "abcd", title: title)
            XCTAssertEqual(try TaskFile.parse(yaml, file: "t", workstream: nil).tasks.first?.title, title)
        }
    }

    func testEstimates() {
        XCTAssertEqual(hoursOf("2h"), 2)
        XCTAssertEqual(hoursOf("45m"), 0.75)
        XCTAssertEqual(hoursOf("1h30"), 1.5)
        XCTAssertEqual(hoursOf("0.5h"), 0.5)
        XCTAssertEqual(hoursOf("90 min"), 1.5)
        XCTAssertEqual(hoursOf("1.5"), 1.5)
        XCTAssertNil(hoursOf("soon"))
        XCTAssertEqual(hoursText(1.5), "1h 30m")
        XCTAssertEqual(hoursText(0.25), "15m")
    }

    func testDays() {
        XCTAssertEqual(Days.add("2026-11-11", 1), "2026-11-12")
        XCTAssertEqual(Days.add("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(Days.between("2026-11-11", "2026-11-14"), 3)
        XCTAssertEqual(Days.weekday("2026-11-11"), 3) // a Wednesday
        XCTAssertEqual(Days.weekStart("2026-11-11"), "2026-11-09")
        XCTAssertEqual(Days.relative("2026-11-10", today: "2026-11-11"), "Yesterday")
        XCTAssertEqual(Days.relative("2026-11-13", today: "2026-11-11"), "Fri")
        XCTAssertEqual(Days.label("2026-11-11"), "Wed 11 Nov")
    }

    func testPlanning() throws {
        let s = DataFolder.load(dir)
        let p = Planning(s, today: "2026-11-02")
        XCTAssertEqual(p.planned(on: "2026-11-02").map(\.id), ["lab3"])
        XCTAssertTrue(p.slipped.map(\.id).contains("bkd7")) // planned 2026-10-26, not done
        XCTAssertFalse(p.slipped.map(\.id).contains("pz53")) // done
        XCTAssertTrue(p.keyDates.map(\.id).contains("lab1"))
        XCTAssertFalse(p.open.map(\.id).contains("sdn4")) // Someday
        XCTAssertFalse(p.open.map(\.id).contains("lab8")) // Someday
        XCTAssertTrue(p.tasks(.someday).map(\.id).contains("sdn4"))
        XCTAssertTrue(p.tasks(.waiting).map(\.id).contains("lab7"))
        XCTAssertEqual(p.progress(s.tasks["lab1"]!)?.total, 6) // lab8 is Someday
        XCTAssertEqual(p.crumb(s.tasks["lab4"]!), "Lab report › Method section › Draft the steps")
        XCTAssertEqual(p.deadline(s.tasks["lab4"]!), "2026-11-03")
        XCTAssertEqual(p.estimate(s.tasks["lab3"]!), 1)
        XCTAssertEqual(Planning(s, today: "2026-11-02").tasks(.done).map(\.id), ["lab5"])
    }

    func testRepeats() {
        let r = Repeat(freq: "week", on: ["fri"], until: nil)
        XCTAssertEqual(r.next(today: "2026-11-11", anchor: nil)?.day, "2026-11-13")
        let w = Repeat(freq: "weekdays", on: [], until: "2026-11-12")
        XCTAssertEqual(w.next(today: "2026-11-14", anchor: nil)?.day, "2026-11-16")
        XCTAssertEqual(w.next(today: "2026-11-14", anchor: nil)?.live, false)
        XCTAssertNil(Repeat(freq: "weekly", on: [], until: nil).next(today: "2026-11-11", anchor: nil))
    }

    func testABrokenFileIsReadOnly() throws {
        try "tasks:\n  - id: x\n   title: bad indent\n  - [\n".write(to: dir.appendingPathComponent("inbox.yaml"), atomically: true, encoding: .utf8)
        let s = DataFolder.load(dir)
        XCTAssertTrue(s.brokenFiles.contains("inbox.yaml"))
        XCTAssertFalse(s.canEdit("inbox.yaml"))
        XCTAssertThrowsError(try TaskEditor(root: dir).add(title: "x", to: "inbox.yaml", in: s, today: "2026-11-11"))
    }
}
