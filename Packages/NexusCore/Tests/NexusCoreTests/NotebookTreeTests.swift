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

    func tree(_ open: Set<String>) -> [NotebookTreeRow] {
        NotebookTree.rows(root: dir, open: open, counts: NotebookScan.read(dir).counts)
    }

    func testClosedShowsTopLevelOnly() {
        let rows = tree([])
        XCTAssertEqual(rows.map(line), ["> Art", "> School"])
        XCTAssertEqual(rows[1].color, "#007F43")
        XCTAssertEqual(rows[1].boardCount, 5)
        XCTAssertEqual(rows[1].depth, 0)
        XCTAssertNil(NotebookTree.rows(root: dir, open: [])[1].boardCount, "no count before the scan")
    }

    /// The tree reads only the notebooks it shows: a closed notebook's own folder (for its arrow), nothing inside it.
    func testReadsOnlyWhatShows() {
        var read: [String] = []
        let level: (String) -> NotebookLevel = { read.append($0); return Notebook.level(self.dir, $0) }
        _ = NotebookTree.rows(top: Notebook.top(dir), open: [], level: level)
        XCTAssertEqual(read, ["notebooks/Art", "notebooks/School"])
        read = []
        _ = NotebookTree.rows(top: Notebook.top(dir), open: ["notebooks/School", "notebooks/School/Chemistry/R3 Energetics"], level: level)
        XCTAssertEqual(read, ["notebooks/Art", "notebooks/School", "notebooks/School/Chemistry", "notebooks/School/Maths"],
                       "R3 Energetics is remembered open, but Chemistry is closed: nothing in Chemistry is read")
    }

    func testTheLazyTreeIsTheWholeListsTree() {
        let all = Notebook.list(dir)
        let open = Set(all.flatMap(\.allNotebooks).map(\.path))
        var flat: [String] = []
        func add(_ nb: Notebook) { flat.append(nb.path); nb.notebooks.forEach(add); flat += nb.boards.map(\.path) }
        all.forEach(add)
        XCTAssertEqual(tree(open).map(\.path), flat)
        XCTAssertEqual(Notebook.read(dir, "notebooks/School").allBoards.count, 5)
    }

    func testScanCountsAndStamps() throws {
        let scan = NotebookScan.read(dir)
        XCTAssertEqual(scan.counts["notebooks/School"], 5)
        XCTAssertEqual(scan.counts["notebooks/School/Chemistry/R3 Energetics"], 4)
        XCTAssertEqual(scan.counts["notebooks/School/Maths"], 0)
        XCTAssertNil(scan.counts["notebooks/School/Chemistry/Syllabus.board"], "boards aren't walked into")
        XCTAssertEqual(scan.changed(dir), [])
        // a board made deep inside: its notebook's stamp changes, and only that one
        Thread.sleep(forTimeInterval: 0.05)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("notebooks/School/Chemistry/R3 Energetics/Week 1/New.board"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(scan.changed(dir), ["notebooks/School/Chemistry/R3 Energetics/Week 1"])
        let again = NotebookScan.read(dir)
        XCTAssertEqual(again.counts["notebooks/School"], 6)
        XCTAssertEqual(again.changed(from: scan), ["notebooks/School/Chemistry/R3 Energetics/Week 1"])
        // a colour written into notebook.json
        Thread.sleep(forTimeInterval: 0.05)
        try write("notebooks/Art/notebook.json", ##"{"color": "#2769B7"}"##)
        XCTAssertTrue(again.changed(dir).contains("notebooks/Art"))
    }

    func testOpenToAnyDepthInTheNotebookPagesOrder() {
        let open: Set = ["notebooks/School", "notebooks/School/Chemistry", "notebooks/School/Chemistry/R3 Energetics",
                         "notebooks/School/Chemistry/R3 Energetics/Week 1"]
        let rows = tree(open)
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
        let rows = tree(["notebooks/School/Chemistry"])
        XCTAssertEqual(rows.map(line), ["> Art", "> School"])
    }

    func testAnEmptyNotebookHasNoArrowEvenWhenRemembered() {
        let rows = tree(["notebooks/School", "notebooks/School/Maths"])
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
        XCTAssertEqual(NotebookTree.renaming("notebooks/A", to: "notebooks/B/A", in: "notebooks/A|notebooks/A/C|notebooks/Z"),
                       "notebooks/B/A|notebooks/B/A/C|notebooks/Z")
        XCTAssertEqual(NotebookTree.renaming("notebooks/Q", to: "notebooks/R", in: "notebooks/A"), "notebooks/A")
    }

    /// One branch open at each level (Nov 24 2026: the sidebar had grown too long to scroll): opening a notebook closes the ones
    /// beside it and what was open inside them, and keeps what is open inside itself.
    func testOpeningClosesTheNotebooksBesideIt() {
        let open = "notebooks/A|notebooks/A/B|notebooks/A/B/C|notebooks/A/D|notebooks/Z|notebooks/Z/Y"
        XCTAssertEqual(NotebookTree.opening("notebooks/A/D", in: open), "notebooks/A|notebooks/A/D|notebooks/Z|notebooks/Z/Y",
                       "B and C (beside D) close; Z, in another branch higher up, isn't beside D")
        XCTAssertEqual(NotebookTree.opening("notebooks/Z", in: open), "notebooks/Z|notebooks/Z/Y",
                       "a top-level notebook closes every other top-level branch, and keeps its own insides")
        XCTAssertEqual(NotebookTree.opening("notebooks/A", in: "notebooks/A"), "notebooks/A", "nothing changed: the same text")
        XCTAssertEqual(NotebookTree.opening("notebooks/Q", in: ""), "notebooks/Q")
    }

    /// A board opened from anywhere opens its notebooks, closing the ones beside each, and keeps what is open in its own notebook
    /// (SidebarTreeTests: switching to another board of R3 Energetics keeps Week 1 open).
    func testFocusingABoardKeepsOnlyItsBranch() {
        let open = "notebooks/School|notebooks/School/Chemistry|notebooks/School/Chemistry/R3|notebooks/School/Chemistry/R3/Week 1|notebooks/School/Biology|notebooks/Art"
        XCTAssertEqual(NotebookTree.focusing("notebooks/School/Chemistry/R3/Bond.board", in: open),
                       "notebooks/School|notebooks/School/Chemistry|notebooks/School/Chemistry/R3|notebooks/School/Chemistry/R3/Week 1")
        XCTAssertEqual(NotebookTree.focusing("notebooks/Art/Sketch.board", in: open), "notebooks/Art")
        XCTAssertEqual(NotebookTree.focusing("boards/x.board", in: open), open, "not in a notebook: nothing changes")
    }

    func testMoveToTreeIsNotebooksOnly() {
        let all = Notebook.list(dir)
        XCTAssertEqual(NotebookTree.rows(notebooks: all, open: []).map(line), ["  Art", "> School"],
                       "Art holds only a board, so it has no arrow in a tree of notebooks")
        let rows = NotebookTree.rows(notebooks: all, open: ["notebooks/School", "notebooks/School/Chemistry"])
        XCTAssertEqual(rows.map(line), ["  Art", "v School", "  v Chemistry", "    > R3 Energetics", "    Maths"])
        XCTAssertEqual(rows[1].boardCount, 5)
        XCTAssertEqual(rows[1].color, "#007F43")
        XCTAssertEqual(rows[3].boardCount, 4)
    }

    func testScanListsEveryBoardAndNotebook() {
        let scan = NotebookScan.read(dir)
        XCTAssertEqual(Set(scan.boards), Set(Notebook.list(dir).flatMap { $0.allBoards.map { $0.board.path } }))
        XCTAssertEqual(scan.boards.count, 6)
        XCTAssertEqual(scan.notebooks.first, "notebooks/Art")
        XCTAssertTrue(scan.notebooks.contains("notebooks/School/Chemistry/R3 Energetics/Week 1"))
        let hits = NotebookFind.search("calor", in: scan.findEntries)
        XCTAssertEqual(hits.map(\.path), ["notebooks/School/Chemistry/R3 Energetics/Week 1/Calorimetry.board"])
        XCTAssertEqual(hits.first?.place, "School › Chemistry › R3 Energetics › Week 1")
    }
}
