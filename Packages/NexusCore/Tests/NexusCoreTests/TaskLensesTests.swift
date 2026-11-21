import XCTest
@testable import NexusCore

/// The Tasks screen's lenses (TaskLenses.swift) on the same folder and answers as nexus `desktop/backend/src/tasks.rs`'s `the_lenses`.
final class TaskLensesTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-lenses-\(UUID().uuidString)")
        func write(_ rel: String, _ text: String) throws {
            let u = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("nexus.yaml", "nexus: 2\n")
        try write("inbox.yaml", "tasks:\n  - id: in1\n    title: Sign the form\n")
        try write("classes/group.yaml", "label: Classes\n")
        try write("classes/chemistry/workstream.yaml", "id: chem\nname: Chemistry HL\ncolor: green\n")
        try write("classes/chemistry/tasks.yaml", "tasks:\n  - id: c1\n    title: Lab write-up\n    due: 2026-11-18\n  - id: c2\n    title: Redox set\n    due: 2026-11-25\n    key: true\n    subtasks:\n      - id: c2a\n        title: Q1-5\n        done: 2026-11-19\n  - id: c3\n    title: Ask about the trip\n    waiting:\n      on: Mr Lopez\n      since: 2026-11-15\n  - id: c4\n    title: Read ahead\n    someday: true\n  - id: c5\n    title: Old\n    done: 2026-11-01\n")
        try write("classes/physics/workstream.yaml", "id: phys\nname: Physics HL\ncolor: blue\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testTheLenses() {
        let p = Planning(DataFolder.load(dir), today: "2026-11-20")
        func titles(_ l: Planning.Lens) -> [String] { TaskLenses.rows(p, l).map(\.title) }
        XCTAssertEqual(titles(.all), ["Lab write-up", "Redox set", "Ask about the trip", "Sign the form"])
        XCTAssertEqual(titles(.deadlines), ["Redox set", "Lab write-up"])
        XCTAssertEqual(titles(.waiting), ["Ask about the trip"])
        XCTAssertEqual(titles(.slipped), ["Lab write-up"])
        XCTAssertEqual(titles(.done), ["Q1-5"])
        XCTAssertEqual(titles(.someday), ["Read ahead"])
        XCTAssertEqual(titles(.noDate), ["Sign the form"])
        XCTAssertEqual(TaskLenses.count(p, .all), 4)
        XCTAssertEqual(TaskLenses.late(TaskLenses.rows(p, .slipped)[0], today: p.today), 2)
    }
}
