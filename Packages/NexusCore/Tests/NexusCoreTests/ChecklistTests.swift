import XCTest
@testable import NexusCore

/// The task panel's checklist moves (TaskEditor.nest / unnest / shift): a subtask goes under the one above, back out after its
/// parent, and up or down among the ones beside it, with everything under it, in one line-level write that Undo puts back.
final class ChecklistTests: XCTestCase {
    var dir: URL!
    let file = "classes/chem/tasks.yaml"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-check-\(UUID().uuidString)")
        func write(_ rel: String, _ text: String) throws {
            let u = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("nexus.yaml", "nexus: 2\n")
        try write("classes/group.yaml", "label: Classes\n")
        try write("classes/chem/workstream.yaml", "id: chem\nname: Chemistry HL\ncolor: green\n")
        try write(file, """
        tasks:
          - id: c1
            title: Redox set
            subtasks:
              - id: a
                title: Q1-5
              - id: b
                title: Q6-10
                est: 30m
              - {id: c, title: Q11-15}
          - id: c2
            title: Lab write-up

        """)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func snap() -> Snapshot { DataFolder.load(dir) }
    func text() -> String { (try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)) ?? "" }
    func kids(_ id: String) -> [String] { snap().tasks[id]?.children ?? [] }

    func testNestUnderTheOneAboveAndBackOut() throws {
        let e = TaskEditor(root: dir)
        let before = text()
        let c = try e.nest(snap().tasks["b"]!, in: snap())
        XCTAssertEqual(kids("c1"), ["a", "c"])
        XCTAssertEqual(kids("a"), ["b"])
        XCTAssertEqual(snap().tasks["b"]?.est, "30m", "its fields came with it")
        XCTAssertTrue(text().contains("      - id: a\n        title: Q1-5\n        subtasks:\n          - id: b\n            title: Q6-10\n            est: 30m\n"), text())
        // back out: just after the task it was under
        _ = try e.unnest(snap().tasks["b"]!, in: snap())
        XCTAssertEqual(kids("c1"), ["a", "b", "c"])
        XCTAssertEqual(kids("a"), [])
        XCTAssertFalse(text().contains("subtasks:\n          -"), "the emptied subtasks list went")
        // undo of the first step only works while the file still holds what it wrote
        XCTAssertThrowsError(try e.undo(c))
        _ = before
    }

    func testUndoPutsTheFileBack() throws {
        let e = TaskEditor(root: dir)
        let before = text()
        let c = try e.nest(snap().tasks["c"]!, in: snap())
        XCTAssertEqual(kids("b"), ["c"])
        try e.undo(c)
        XCTAssertEqual(text(), before)
    }

    func testOutOfATopTaskLandsAfterIt() throws {
        let e = TaskEditor(root: dir)
        _ = try e.unnest(snap().tasks["a"]!, in: snap())
        XCTAssertEqual(snap().top[file], ["c1", "a", "c2"])
        XCTAssertNil(snap().tasks["a"]?.parent)
        XCTAssertEqual(kids("c1"), ["b", "c"])
        // the last one out of a top task with nothing after it goes last
        _ = try e.unnest(snap().tasks["c"]!, in: snap())
        _ = try e.unnest(snap().tasks["b"]!, in: snap())
        XCTAssertEqual(snap().top[file], ["c1", "b", "c", "a", "c2"])
        XCTAssertTrue(text().contains("    title: Redox set\n  - id: b"), "c1 has no subtasks key left:\n" + text())
    }

    func testShiftUpAndDown() throws {
        let e = TaskEditor(root: dir)
        _ = try e.shift(snap().tasks["c"]!, by: -1, in: snap())
        XCTAssertEqual(kids("c1"), ["a", "c", "b"])
        _ = try e.shift(snap().tasks["a"]!, by: 1, in: snap())
        XCTAssertEqual(kids("c1"), ["c", "a", "b"])
        _ = try e.shift(snap().tasks["a"]!, by: 1, in: snap())
        XCTAssertEqual(kids("c1"), ["c", "b", "a"])
        XCTAssertThrowsError(try e.shift(snap().tasks["a"]!, by: 1, in: snap()), "already last")
        XCTAssertThrowsError(try e.shift(snap().tasks["c"]!, by: -1, in: snap()), "already first")
        XCTAssertThrowsError(try e.nest(snap().tasks["c1"]!, in: snap()), "nothing above the first task")
        XCTAssertThrowsError(try e.unnest(snap().tasks["c2"]!, in: snap()), "already at the top")
        // top-level tasks shift too
        _ = try e.shift(snap().tasks["c2"]!, by: -1, in: snap())
        XCTAssertEqual(snap().top[file], ["c2", "c1"])
        XCTAssertEqual(kids("c1"), ["c", "b", "a"], "its subtasks came with it")
    }

    func testANestedTreeMovesWhole() throws {
        let e = TaskEditor(root: dir)
        _ = try e.nest(snap().tasks["b"]!, in: snap())      // a > b
        _ = try e.nest(snap().tasks["c"]!, in: snap())      // a > b, c ... c goes under a (the one above it now)
        XCTAssertEqual(kids("a"), ["b", "c"])
        _ = try e.nest(snap().tasks["c"]!, in: snap())      // a > b > c
        XCTAssertEqual(kids("b"), ["c"])
        _ = try e.unnest(snap().tasks["a"]!, in: snap())    // a (with b > c) out to the top, after c1
        XCTAssertEqual(snap().top[file], ["c1", "a", "c2"])
        XCTAssertEqual(kids("a"), ["b"]); XCTAssertEqual(kids("b"), ["c"])
        XCTAssertEqual(snap().tasks.count, 5)
    }
}
