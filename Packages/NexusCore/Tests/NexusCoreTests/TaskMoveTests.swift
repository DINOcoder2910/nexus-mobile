import XCTest
@testable import NexusCore

/// The task panel's Delete and its subject menu (TaskEditor.delete / moveTask): the task goes with everything under it, an emptied
/// list stays a list, and one Undo puts every file back.
final class TaskMoveTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-move-\(UUID().uuidString)")
        func write(_ rel: String, _ text: String) throws {
            let u = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("nexus.yaml", "nexus: 2\n")
        try write("inbox.yaml", "tasks:\n  - id: in1\n    title: Sign the form\n")
        try write("classes/group.yaml", "label: Classes\n")
        try write("classes/chem/workstream.yaml", "id: chem\nname: Chemistry HL\ncolor: green\n")
        try write("classes/chem/tasks.yaml", """
        # chemistry
        tasks:
          - id: c1
            title: Lab write-up
            due: 2026-11-18
          - id: c2
            title: Redox set
            subtasks:
              - id: c2a
                title: Q1-5
          - {id: c3, title: Read ahead}

        """)
        try write("classes/phys/workstream.yaml", "id: phys\nname: Physics HL\ncolor: blue\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func snap() -> Snapshot { DataFolder.load(dir) }
    func text(_ rel: String) -> String { (try? String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)) ?? "" }

    func testDeleteTakesItsSubtasksAndUndoPutsThemBack() throws {
        let e = TaskEditor(root: dir)
        let before = text("classes/chem/tasks.yaml")
        let c = try e.delete(snap().tasks["c2"]!, in: snap())
        let s = snap()
        XCTAssertNil(s.tasks["c2"]); XCTAssertNil(s.tasks["c2a"])
        XCTAssertEqual(s.tasks["c1"]?.title, "Lab write-up"); XCTAssertEqual(s.tasks["c3"]?.title, "Read ahead")
        XCTAssertTrue(text("classes/chem/tasks.yaml").hasPrefix("# chemistry\n"))
        try e.undo(c)
        XCTAssertEqual(text("classes/chem/tasks.yaml"), before)
    }

    func testDeletingTheLastSubtaskOrTaskLeavesAList() throws {
        let e = TaskEditor(root: dir)
        _ = try e.delete(snap().tasks["c2a"]!, in: snap())
        XCTAssertFalse(text("classes/chem/tasks.yaml").contains("subtasks"))
        XCTAssertEqual(snap().tasks["c2"]?.children, [])
        _ = try e.delete(snap().tasks["in1"]!, in: snap())
        XCTAssertEqual(text("inbox.yaml"), "tasks: []\n")
        XCTAssertTrue(snap().brokenFiles.isEmpty)
    }

    func testMoveToAnotherSubjectAndBack() throws {
        let e = TaskEditor(root: dir)
        // to Physics, which has no task file yet: made, with the subtask under it
        _ = try e.moveTask(snap().tasks["c2"]!, to: "phys", in: snap())
        var s = snap()
        XCTAssertEqual(s.tasks["c2"]?.workstream, "phys")
        XCTAssertEqual(s.tasks["c2a"]?.parent, "c2")
        XCTAssertEqual(s.tasks["c2"]?.file, "classes/phys/tasks.yaml")
        XCTAssertTrue(text("classes/phys/tasks.yaml").hasPrefix("tasks:\n  - id: c2\n    title: Redox set\n    subtasks:\n      - id: c2a\n"))
        // a one-line task to the Inbox, after what is there
        _ = try e.moveTask(snap().tasks["c3"]!, to: nil, in: snap())
        s = snap()
        XCTAssertEqual(s.tasks["c3"]?.file, "inbox.yaml")
        XCTAssertEqual(s.top["inbox.yaml"], ["in1", "c3"])
        // a subtask out of its parent, in the same file
        _ = try e.moveTask(snap().tasks["c2a"]!, to: "phys", in: snap())
        XCTAssertNil(snap().tasks["c2a"]?.parent)
        XCTAssertTrue(snap().brokenFiles.isEmpty)
    }

    func testOneUndoPutsBothFilesBack() throws {
        let e = TaskEditor(root: dir)
        let chem = text("classes/chem/tasks.yaml")
        let c = try e.moveTask(snap().tasks["c1"]!, to: "phys", in: snap())
        try e.undo(c)
        XCTAssertEqual(text("classes/chem/tasks.yaml"), chem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("classes/phys/tasks.yaml").path))
    }
}
