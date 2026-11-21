import XCTest
@testable import NexusCore

/// The new look's pure parts: which notebooks a subject holds in the sidebar (SubjectNotebooks) and the unit studied now on the
/// Study page (StudyUnits.current).
final class NewLookTests: XCTestCase {
    func testASubjectHoldsTheNotebooksNamedForIt() {
        XCTAssertTrue(SubjectNotebooks.belongs("Chemistry", to: "Chemistry HL"))
        XCTAssertTrue(SubjectNotebooks.belongs("Chem", to: "Chemistry HL"))
        XCTAssertTrue(SubjectNotebooks.belongs("Chemistry HL", to: "Chemistry HL"))
        XCTAssertTrue(SubjectNotebooks.belongs("Maths", to: "Maths AA HL"))
        XCTAssertTrue(SubjectNotebooks.belongs("Math", to: "Maths AA HL"))
        XCTAssertTrue(SubjectNotebooks.belongs("Spanish", to: "Spanish ab initio"))
        XCTAssertTrue(SubjectNotebooks.belongs("English A", to: "English A"))
        XCTAssertTrue(SubjectNotebooks.belongs("Bio", to: "Biology SL", aliases: ["Bio"]))
        // another subject's notebook, a word the subject hasn't, a short word that only begins it
        XCTAssertFalse(SubjectNotebooks.belongs("Physics", to: "Chemistry HL"))
        XCTAssertFalse(SubjectNotebooks.belongs("Chemistry lab reports", to: "Chemistry HL"))
        XCTAssertFalse(SubjectNotebooks.belongs("Ch", to: "Chemistry HL"))
        XCTAssertFalse(SubjectNotebooks.belongs("", to: "Chemistry HL"))
    }

    func testMatchKeepsOrderAndLeavesOutWhatIsInside() {
        let c = ["notebooks/Chemistry", "notebooks/Chemistry/Chem past papers", "notebooks/Physics", "notebooks/School/Chem"]
        XCTAssertEqual(SubjectNotebooks.match(name: "Chemistry HL", candidates: c), ["notebooks/Chemistry", "notebooks/School/Chem"])
        XCTAssertEqual(SubjectNotebooks.match(name: "Economics", candidates: c), [])
    }

    private func units(_ yaml: String) -> [StudyUnits.Unit] {
        guard case .ok(let u) = StudyUnits.parseUnits(yaml) else { XCTFail("units"); return [] }
        return u
    }

    func testTheUnitStudiedNowFollowsTheLastDoneOne() {
        let u = units("""
        - { code: S1.4, title: a, status: done }
        - { code: R1.1, title: b, status: partial }
        - { code: R3.1, title: c, status: done }
        - { code: R3.2, title: d, status: not-yet }
        - { code: R3.4, title: e, status: not-yet }
        """)
        XCTAssertEqual(StudyUnits.current(u), "R3.2")
        XCTAssertNil(StudyUnits.current(units("- { code: R1.1, title: a, status: partial }\n")))
        XCTAssertNil(StudyUnits.current(units("- { code: R1.1, title: a, status: done }\n")))
        // a partly done unit after the last done one is the one now
        XCTAssertEqual(StudyUnits.current(units("- { code: R1.1, title: a, status: done }\n- { code: R1.2, title: b, status: partial }\n")), "R1.2")
    }
}
