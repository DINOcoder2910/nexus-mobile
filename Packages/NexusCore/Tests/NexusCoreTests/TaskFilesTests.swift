import XCTest
@testable import NexusCore

/// A task's files (Next up's chips and Write on it), as the laptop's `task_files`: links to files, not notes, resolved beside the list.
final class TaskFilesTests: XCTestCase {
    func task(_ title: String, note: String? = nil) -> NexusTask {
        var t = NexusTask(id: "a1", title: title, file: "classes/chem/tasks.yaml", workstream: "chem")
        t.note = note
        return t
    }

    func testTargets() {
        let t = task("Redox set [[files/Redox.pdf|the sheet]] and [[Notes on redox]]",
                     note: "See [[files/Redox.pdf]], [[diagram.png#top]] and [[Lab.md]]")
        XCTAssertEqual(TaskFiles.targets(t), ["files/Redox.pdf", "diagram.png"])
        XCTAssertEqual(TaskFiles.targets(task("No links")), [])
        XCTAssertEqual(TaskFiles.targets(task("Broken [[files/x.pdf")), [])
    }

    func testResolve() {
        let there: Set<String> = ["classes/chem/files/Redox.pdf", "shared/diagram.png", "classes/chem/sheets/old/Lab.pdf"]
        let exists = { (p: String) in there.contains(p) }
        let find = { (name: String) in there.sorted().first { ($0 as NSString).lastPathComponent == name } }
        XCTAssertEqual(TaskFiles.resolve("files/Redox.pdf", from: "classes/chem/tasks.yaml", exists: exists, find: find), "classes/chem/files/Redox.pdf")
        XCTAssertEqual(TaskFiles.resolve("shared/diagram.png", from: "classes/chem/tasks.yaml", exists: exists, find: find), "shared/diagram.png")
        XCTAssertEqual(TaskFiles.resolve("../../shared/diagram.png", from: "classes/chem/tasks.yaml", exists: exists, find: find), "shared/diagram.png")
        XCTAssertEqual(TaskFiles.resolve("Lab.pdf", from: "classes/chem/tasks.yaml", exists: exists, find: find), "classes/chem/sheets/old/Lab.pdf")
        XCTAssertNil(TaskFiles.resolve("Gone.pdf", from: "classes/chem/tasks.yaml", exists: exists, find: find))
        let t = task("Redox [[files/Redox.pdf]] [[Gone.pdf]]", note: "[[files/./Redox.pdf]]")
        let f = TaskFiles.files(t, exists: exists, find: find)
        XCTAssertEqual(f.map(\.path), ["classes/chem/files/Redox.pdf"])
        XCTAssertEqual(f.first?.name, "Redox.pdf"); XCTAssertEqual(f.first?.kind, "pdf")
    }
}
