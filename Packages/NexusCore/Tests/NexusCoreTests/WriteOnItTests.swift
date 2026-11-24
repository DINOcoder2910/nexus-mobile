import XCTest
@testable import NexusCore

/// WriteOnIt: the same boards as the laptop's writeOnIt (nexus desktop/backend/src/board.rs, bank.rs, sheets.rs and their tests).
final class WriteOnItTests: XCTestCase {
    let subjects = WriteOnIt.Subjects(
        notebooks: ["notebooks/Chem": "chem", "notebooks/Physics": "phys", "notebooks/Aa chem": "chem"],
        workstreams: ["chem": (folder: "classes/chem", name: "Chemistry"), "phys": (folder: "classes/phys", name: "Physics"),
                      "maths": (folder: "classes/maths", name: "Maths"), "chem-sub": (folder: "classes/chem/labs", name: "Labs")],
        sheets: ["chem": "classes/chem/files", "maths": "classes/maths/sheets"])

    func testTheBoardBesideAPdf() {
        XCTAssertEqual(WriteOnIt.besideBoard("a/Paper 1.pdf"), "a/Paper 1.board")
        XCTAssertEqual(WriteOnIt.besideBoard("Paper.v2.pdf"), "Paper.v2.board")
    }

    func testASubjectByNotebookOrFolder() {
        XCTAssertEqual(WriteOnIt.subject(of: "notebooks/Chem/Papers/x.board", subjects), "chem")
        XCTAssertNil(WriteOnIt.subject(of: "notebooks/Other/x.board", subjects))
        XCTAssertEqual(WriteOnIt.subject(of: "classes/chem/files/a.pdf", subjects), "chem")
        // the deepest folder wins
        XCTAssertEqual(WriteOnIt.subject(of: "classes/chem/labs/a.pdf", subjects), "chem-sub")
        XCTAssertNil(WriteOnIt.subject(of: "classes/chemistry/a.pdf", subjects))
        XCTAssertEqual(WriteOnIt.notebooks(of: "chem", subjects), ["notebooks/Aa chem", "notebooks/Chem"])
    }

    func testAPapersBoardInTheSubjectsNotebookUnderItsUnit() {
        // the first notebook filed under the subject, Papers › the unit folder under the sheets folder
        XCTAssertEqual(WriteOnIt.papersBoard("classes/chem/files/05 Reactivity 1/Redox — test, 40 mk/Redox.pdf", subjects),
                       "notebooks/Aa chem/Papers/05 Reactivity 1/Redox.board")
        XCTAssertEqual(WriteOnIt.papersBoard("classes/chem/files/Loose.pdf", subjects), "notebooks/Aa chem/Papers/Loose.board")
        // outside the sheets folder: no unit
        XCTAssertEqual(WriteOnIt.papersBoard("classes/chem/notes/Handout.pdf", subjects), "notebooks/Aa chem/Papers/Handout.board")
        // no notebook for the subject: one named after the workstream
        XCTAssertEqual(WriteOnIt.papersBoard("classes/maths/sheets/Calculus/Integrals.pdf", subjects), "notebooks/Maths/Papers/Calculus/Integrals.board")
        // no subject: none, and the new board goes beside the PDF
        XCTAssertNil(WriteOnIt.papersBoard("downloads/Paper.pdf", subjects))
        XCTAssertEqual(WriteOnIt.newBoard("downloads/Paper.pdf", subjects).board, "downloads/Paper.board")
        XCTAssertNil(WriteOnIt.newBoard("downloads/Paper.pdf", subjects).subject)
        XCTAssertEqual(WriteOnIt.newBoard("classes/maths/sheets/A.pdf", subjects).subject, "maths")
    }

    func testAnExistingBoardIsFoundFirst() {
        let pdf = "classes/chem/files/U/P.pdf"
        XCTAssertEqual(WriteOnIt.existingBoard(pdf, subjects, exists: { $0 == "notebooks/Aa chem/Papers/U/P.board" }), "notebooks/Aa chem/Papers/U/P.board")
        XCTAssertEqual(WriteOnIt.existingBoard(pdf, subjects, holding: ["notebooks/Chem/R3.board"], exists: { _ in false }), "notebooks/Chem/R3.board")
        XCTAssertEqual(WriteOnIt.existingBoard(pdf, subjects, exists: { $0 == "classes/chem/files/U/P.board" }), "classes/chem/files/U/P.board")
        XCTAssertNil(WriteOnIt.existingBoard(pdf, subjects, exists: { _ in false }))
        XCTAssertEqual(WriteOnIt.subjectBoards(pdf, subjects, among: ["notebooks/Chem/a.board", "notebooks/Physics/b.board", "classes/chem/c.board", "x/d.board"]),
                       ["notebooks/Chem/a.board", "classes/chem/c.board"])
    }

    func testThePrintoutPointsBackAtThePdf() {
        let board = "notebooks/Chem/Papers/U/P.board", pdf = "classes/chem/files/U/P.pdf"
        let it = WriteOnIt.printout(board: board, pdf: pdf)
        XCTAssertEqual(it.json["src"]?.string, "../../../../../classes/chem/files/U/P.pdf")
        XCTAssertEqual(it.x, 0); XCTAssertEqual(it.y, 0)
        XCTAssertTrue(WriteOnIt.holds(board, items: [it], pdf: pdf))
        XCTAssertFalse(WriteOnIt.holds(board, items: [it], pdf: "classes/chem/files/U/Q.pdf"))
        XCTAssertEqual(WriteOnIt.printout(board: "a/P.board", pdf: "a/P.pdf").json["src"]?.string, "../P.pdf")
        XCTAssertEqual(WriteOnIt.notebookJSON(subject: "chem"), "{\"format\":\"nexus-notebook/1\",\"subject\":\"chem\"}\n")
    }

    func testAPaperFindsItsMarkschemeByNameOrInItsSheetFolder() {
        let files = ["Redox titrations.pdf", "Redox titrations MS.pdf", "Markscheme 2023.pdf", "Formula booklet.pdf"]
        XCTAssertEqual(WriteOnIt.markscheme(for: "a/Redox titrations.pdf", folderName: "files", names: files), "Redox titrations MS.pdf")
        XCTAssertNil(WriteOnIt.markscheme(for: "a/Formula booklet.pdf", folderName: "files", names: files))
        XCTAssertNil(WriteOnIt.markscheme(for: "a/Redox titrations MS.pdf", folderName: "files", names: files))
        let sheet = ["Energetics HL.pdf", "Answers.pdf"]
        XCTAssertEqual(WriteOnIt.markscheme(for: "u/Energetics — HL test, 40 mk/Energetics HL.pdf", folderName: "Energetics — HL test, 40 mk", names: sheet), "Answers.pdf")
        XCTAssertNil(WriteOnIt.markscheme(for: "u/files/Energetics HL.pdf", folderName: "files", names: sheet))
        XCTAssertEqual(WriteOnIt.markschemePath(for: "u/Energetics — HL test, 40 mk/Energetics HL.pdf", names: sheet), "u/Energetics — HL test, 40 mk/Answers.pdf")
        XCTAssertEqual(WriteOnIt.markschemePath(for: "x - past-test questions.pdf", names: ["x - past-test questions.pdf", "x - markscheme.pdf"]), "x - markscheme.pdf")
    }
}
