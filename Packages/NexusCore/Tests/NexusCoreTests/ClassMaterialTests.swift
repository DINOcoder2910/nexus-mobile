import XCTest
@testable import NexusCore

/// Class material from Schoology through the G14 (ClassMaterial.swift): the status the G14 answers, where the button shows, the words.
final class ClassMaterialTests: XCTestCase {
    func testStatusAsTheG14WritesIt() {
        let s = ClassMaterial.status("""
        {"last":"2026-11-23T08:10","signedOut":false,"error":null,"failed":[],"made":["notebooks/Chem/R3.2/R3.2.8.board"],"running":false,"ready":true,"roots":["notebooks/Chem","notebooks/Maths"]}
        """)
        XCTAssertEqual(s?.made, ["notebooks/Chem/R3.2/R3.2.8.board"])
        XCTAssertEqual(s?.roots, ["notebooks/Chem", "notebooks/Maths"])
        XCTAssertNil(s?.error)
        XCTAssertEqual(s?.last, "2026-11-23T08:10")
        XCTAssertNil(ClassMaterial.status("not json"))
    }

    func testTheButtonShowsOnTheNotebooksItFills() {
        let roots = ["notebooks/Chemistry HL/Chem HL Notes - G12"]
        XCTAssertTrue(ClassMaterial.shows(on: "notebooks/Chemistry HL/Chem HL Notes - G12", roots: roots))
        XCTAssertTrue(ClassMaterial.shows(on: "notebooks/Chemistry HL/Chem HL Notes - G12/R3.2 Redox", roots: roots))
        XCTAssertTrue(ClassMaterial.shows(on: "notebooks/Chemistry HL", roots: roots))
        XCTAssertFalse(ClassMaterial.shows(on: "notebooks/Chem", roots: roots))
        XCTAssertFalse(ClassMaterial.shows(on: "notebooks/Spanish", roots: roots))
        XCTAssertFalse(ClassMaterial.shows(on: "notebooks/Chemistry HL", roots: []))
    }

    func testWords() {
        var s = ClassMaterial.Status()
        XCTAssertEqual(ClassMaterial.words(s), "Nothing new on Schoology.")
        s.made = ["notebooks/C/R3.2/R3.2.8.board"]
        XCTAssertEqual(ClassMaterial.words(s), "New board: R3.2.8.")
        s.made = ["a/R3.2.8.board", "b/L1/Lesson 78 Limits.board", "c/x.board", "d/y.board"]
        XCTAssertEqual(ClassMaterial.words(s), "New boards: R3.2.8, Lesson 78 Limits and 2 more.")
        s.failed = ["x.pdf: 404"]
        XCTAssertTrue(ClassMaterial.words(s).hasSuffix(" One file didn't come."))
        s.running = true
        XCTAssertEqual(ClassMaterial.words(s), "Getting class material from Schoology…")
        s = ClassMaterial.Status()
        s.signedOut = true
        XCTAssertTrue(ClassMaterial.words(s).hasPrefix("Schoology signed you out."))
        s = ClassMaterial.Status()
        s.error = "the hub is down"
        XCTAssertEqual(ClassMaterial.words(s), "Couldn't get class material: the hub is down")
    }
}
