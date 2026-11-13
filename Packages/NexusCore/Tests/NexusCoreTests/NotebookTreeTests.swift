import XCTest
@testable import NexusCore

/// The sidebar's notebook tree (NotebookTree): nesting to any depth, boards under their notebook, the arrows, and the order the
/// notebook page uses (notebook.json `order`, OneNote's, then by name).
final class NotebookTreeTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tree-tests-" + UUID().uuidString, isDirectory: true)
        for p in ["notebooks/School/Chemistry/R3 Energetics/Week 2/Bond enthalpy.board",
                  "notebooks/School/Chemistry/R3 Energetics/Week 1/Calorimetry.board",
                  "notebooks/School/Chemistry/R3 Energetics/Zeta notes.board",
                  "notebooks/School/Chemistry/R3 Energetics/Alpha notes.board",
                  "notebooks/School/Chemistry/Syllabus.board",
                  "notebooks/School/Maths",
                  "notebooks/Art/Sketches.board"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(p), withIntermediateDirectories: true)
        }
        // OneNote's order: Week 2 before Week 1, Zeta before Alpha; the colour on the top-level notebook
        try write("notebooks/School/Chemistry/R3 Energetics/notebook.json", #"{"order": ["Week 2", "Week 1", "Zeta notes.board", "Alpha notes.board"]}"#)
        try write("notebooks/School/notebook.json", ##"{"color": "#007F43", "order": ["Chemistry", "Maths"]}"##)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ rel: String, _ text: String) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func line(_ r: NotebookTreeRow) -> String {
        String(repeating: "  ", count: r.depth) + (r.kind == .board ? "· " : r.hasChildren ? (r.isOpen ? "v " : "> ") : "  ") + r.name
    }

    func testClosedShowsTopLevelOnly() {
        let rows = NotebookTree.rows(Notebook.list(dir), open: [])
        XCTAssertEqual(rows.map(line), ["> Art", "> School"])
        XCTAssertEqual(rows[1].color, "#007F43")
        XCTAssertEqual(rows[1].boardCount, 5)
        XCTAssertEqual(rows[1].depth, 0)
    }

    func testOpenToAnyDepthInTheNotebookPagesOrder() {
        let open: Set = ["notebooks/School", "notebooks/School/Chemistry", "notebooks/School/Chemistry/R3 Energetics",
                         "notebooks/School/Chemistry/R3 Energetics/Week 1"]
        let rows = NotebookTree.rows(Notebook.list(dir), open: open)
        XCTAssertEqual(rows.map(line), [
            "> Art",
            "v School",
            "  v Chemistry",
            "    v R3 Energetics",
            "      > Week 2",
            "      v Week 1",
            "        · Calorimetry",
            "      · Zeta notes",
            "      · Alpha notes",
            "    · Syllabus",
            "    Maths",
        ])
        let board = rows.first { $0.name == "Calorimetry" }!
        XCTAssertEqual(board.path, "notebooks/School/Chemistry/R3 Energetics/Week 1/Calorimetry.board")
        XCTAssertEqual(board.depth, 4)
        XCTAssertNil(rows.first { $0.name == "Chemistry" }!.color, "only a top-level notebook shows its colour")
        // the same order as the notebook page (Notebook.list's)
        let r3 = Notebook.find(Notebook.list(dir), "notebooks/School/Chemistry/R3 Energetics")!
        XCTAssertEqual(r3.notebooks.map(\.name) + r3.boards.map(\.name), ["Week 2", "Week 1", "Zeta notes", "Alpha notes"])
    }

    func testAnOpenNotebookInsideAClosedOneStaysHidden() {
        let rows = NotebookTree.rows(Notebook.list(dir), open: ["notebooks/School/Chemistry"])
        XCTAssertEqual(rows.map(line), ["> Art", "> School"])
    }

    func testAnEmptyNotebookHasNoArrowEvenWhenRemembered() {
        let rows = NotebookTree.rows(Notebook.list(dir), open: ["notebooks/School", "notebooks/School/Maths"])
        let maths = rows.first { $0.name == "Maths" }!
        XCTAssertFalse(maths.hasChildren)
        XCTAssertFalse(maths.isOpen)
    }

    func testAncestorsAndReveal() {
        XCTAssertEqual(NotebookTree.ancestors(of: "notebooks/A/B/x.board"), ["notebooks/A", "notebooks/A/B"])
        XCTAssertEqual(NotebookTree.ancestors(of: "notebooks/A"), [])
        XCTAssertEqual(NotebookTree.ancestors(of: "boards/x.board"), [])
        XCTAssertEqual(NotebookTree.revealing("notebooks/A/B/x.board", in: "notebooks/Z"), "notebooks/A|notebooks/A/B|notebooks/Z")
        XCTAssertEqual(NotebookTree.revealing("notebooks/A/x.board", in: "notebooks/A"), "notebooks/A")
        XCTAssertEqual(NotebookTree.setting("notebooks/A", open: false, in: "notebooks/A|notebooks/B"), "notebooks/B")
        XCTAssertEqual(NotebookTree.setting("notebooks/C", open: true, in: "notebooks/B"), "notebooks/B|notebooks/C")
        XCTAssertEqual(NotebookTree.parse(""), [])
    }
}
