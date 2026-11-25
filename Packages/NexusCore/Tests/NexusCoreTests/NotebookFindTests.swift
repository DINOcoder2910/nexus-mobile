import XCTest
@testable import NexusCore

/// Finding a notebook or board by name (the sidebar's find field, Move to…'s search) and the kept path lists (pinned, recent places).
final class NotebookFindTests: XCTestCase {
    let entries = NotebookFind.entries(
        notebooks: ["notebooks/Physics HL", "notebooks/Physics HL/A General Physics", "notebooks/Physics HL/A General Physics/A1 School",
                    "notebooks/Physics HL/A General Physics/Projectile motion", "notebooks/Chemistry HL",
                    "notebooks/Chemistry HL/Chem HL Notes - G12", "notebooks/Spanish ab initio", "notebooks/Others"],
        boards: ["notebooks/Physics HL/A General Physics/A1 School/Vectors.board",
                 "notebooks/Physics HL/A General Physics/A1 School/Motion graphs.board",
                 "notebooks/Physics HL/A General Physics/Projectile motion/Projectile worksheet.board",
                 "notebooks/Chemistry HL/Chem HL Notes - G12/Enthalpy of combustion.board",
                 "notebooks/Spanish ab initio/Él y ella.board",
                 "notebooks/Others/Mum’s list.board"])

    func names(_ q: String, recent: [String] = []) -> [String] { NotebookFind.search(q, in: entries, recent: recent).map(\.name) }

    func testEntriesKnowTheirNameAndPlace() {
        let b = entries.first { $0.name == "Vectors" }!
        XCTAssertEqual(b.kind, .board)
        XCTAssertEqual(b.place, "Physics HL › A General Physics › A1 School")
        XCTAssertEqual(b.depth, 3)
        let top = entries.first { $0.name == "Physics HL" }!
        XCTAssertEqual(top.place, "")
        XCTAssertEqual(top.depth, 0)
    }

    func testBestFirst() {
        // the name itself, then names starting with it, then a word of the name starting with it, then anywhere in a name
        XCTAssertEqual(names("projectile"), ["Projectile motion", "Projectile worksheet"],
                       "both start with it; the notebook before the board")
        XCTAssertEqual(names("motion"), ["Motion graphs", "Projectile motion", "Projectile worksheet"],
                       "starts with it, then a later word of the name, then a board in Projectile motion (by its place)")
        XCTAssertEqual(names("a1 school"), ["A1 School", "Motion graphs", "Vectors"],
                       "the notebook by its name, then its boards by their place")
        XCTAssertEqual(names("ion"), ["Projectile motion", "Enthalpy of combustion", "Motion graphs", "Projectile worksheet"],
                       "inside a word only: notebooks first, then the shallower; last the one matched by its place")
    }

    func testEveryWordMustMatchNameOrPlace() {
        XCTAssertEqual(names("chem enthalpy"), ["Enthalpy of combustion"], "chem is in its place, enthalpy in its name")
        XCTAssertEqual(names("chem vectors"), [])
        XCTAssertEqual(names("   "), [])
        XCTAssertEqual(names(""), [])
    }

    func testCaseAccentsAndApostrophes() {
        XCTAssertEqual(names("EL Y"), ["Él y ella"])
        XCTAssertEqual(names("mum's"), ["Mum’s list"], "a straight apostrophe finds a curly one")
        XCTAssertEqual(names("spanish  AB"), ["Spanish ab initio", "Él y ella"])
    }

    func testRecentComeFirstAmongEquals() {
        let worksheet = "notebooks/Physics HL/A General Physics/Projectile motion/Projectile worksheet.board"
        XCTAssertEqual(names("projectile", recent: [worksheet]), ["Projectile worksheet", "Projectile motion"])
        XCTAssertEqual(names("motion", recent: [worksheet]), ["Motion graphs", "Projectile motion", "Projectile worksheet"],
                       "a better match still wins over a recent one")
    }

    func testLimit() {
        XCTAssertEqual(NotebookFind.search("o", in: entries, limit: 2).count, 2)
        XCTAssertEqual(NotebookFind.search("o", in: entries, limit: 0).count, 0)
    }

    func testWordStart() {
        XCTAssertTrue(NotebookFind.atWordStart("g12", in: "chem hl notes - g12"))
        XCTAssertTrue(NotebookFind.atWordStart("notes", in: "chem hl notes - g12"))
        XCTAssertFalse(NotebookFind.atWordStart("otes", in: "chem hl notes - g12"))
        XCTAssertTrue(NotebookFind.atWordStart("tes", in: "otes tes"), "a later match at a word's start counts")
    }

    func testPathLists() {
        XCTAssertEqual(PathList.adding("c", to: "a|b|c", max: 3), "c|a|b")
        XCTAssertEqual(PathList.adding("d", to: "a|b|c", max: 3), "d|a|b")
        XCTAssertEqual(PathList.adding("a", to: "", max: 3), "a")
        XCTAssertEqual(PathList.toggling("b", in: "a|b"), "a")
        XCTAssertEqual(PathList.toggling("c", in: "a|b"), "a|b|c")
        XCTAssertEqual(PathList.removing("a", from: "a|b|a"), "b")
        XCTAssertEqual(PathList.parse("a|a|b"), ["a", "b"])
        XCTAssertEqual(PathList.renaming("notebooks/A", to: "notebooks/B/A", in: "notebooks/A|notebooks/A/x.board|notebooks/Z"),
                       "notebooks/B/A|notebooks/B/A/x.board|notebooks/Z")
        XCTAssertEqual(PathList.renaming("notebooks/Q", to: "notebooks/R", in: "notebooks/A"), "notebooks/A")
        XCTAssertEqual(PathList.renaming("notebooks/AB", to: "notebooks/C", in: ["notebooks/ABC", "notebooks/AB/x"]),
                       ["notebooks/ABC", "notebooks/C/x"], "only the folder itself and what is inside it")
    }
}
