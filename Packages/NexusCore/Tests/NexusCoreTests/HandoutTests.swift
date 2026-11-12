import XCTest
@testable import NexusCore

/// A scanned handout: its page size, where read lines go on the page, and the name it gets from its title.
final class HandoutTests: XCTestCase {
    typealias L = Handout.Line

    func testPagesAreLetterWideInThePicturesShape() {
        XCTAssertEqual(Handout.pageSize(width: 1800, height: 2546).w, 612)
        XCTAssertEqual(Handout.pageSize(width: 1800, height: 2546).h, 866) // A4's shape
        XCTAssertEqual(Handout.pageSize(width: 2000, height: 1000).h, 306) // landscape
        XCTAssertEqual(Handout.pageSize(width: 0, height: 0).h, 792)
    }

    func testALinesBoxTurnsTopDown() {
        // Vision: from the bottom left, 0...1
        let r = Handout.rect(L("Hi", x: 0.1, y: 0.8, w: 0.5, h: 0.05), pageW: 600, pageH: 800)
        XCTAssertEqual(r.x, 60, accuracy: 0.001)
        XCTAssertEqual(r.y, 120, accuracy: 0.001) // (1 - 0.8 - 0.05) * 800
        XCTAssertEqual(r.w, 300, accuracy: 0.001)
        XCTAssertEqual(r.h, 40, accuracy: 0.001)
    }

    func testTheTallestLineNearTheTopIsTheTitle() {
        let page = [
            L("Name: ____________   Date: ______", x: 0.05, y: 0.93, w: 0.9, h: 0.02),
            L("Redox reactions worksheet", x: 0.2, y: 0.85, w: 0.6, h: 0.04),
            L("1. Assign oxidation states to each element below.", x: 0.05, y: 0.75, w: 0.9, h: 0.02),
            L("Big Footer Words Here", x: 0.1, y: 0.05, w: 0.8, h: 0.06), // too low on the page
        ]
        XCTAssertEqual(Handout.title(page), "Redox reactions worksheet")
    }

    func testNearlyAsTallAndHigherUpWins() {
        let page = [
            L("IB Chemistry SL", x: 0.1, y: 0.92, w: 0.4, h: 0.030),
            L("Energetics review", x: 0.1, y: 0.86, w: 0.4, h: 0.032),
        ]
        XCTAssertEqual(Handout.title(page), "IB Chemistry SL")
    }

    func testFormLinesPageNumbersAndNumbersAreNotTitles() {
        XCTAssertFalse(Handout.readsAsTitle("Name: ________"))
        XCTAssertFalse(Handout.readsAsTitle("Date : 12/11/26"))
        XCTAssertFalse(Handout.readsAsTitle("Teacher"))
        XCTAssertFalse(Handout.readsAsTitle("Page 2 of 4"))
        XCTAssertFalse(Handout.readsAsTitle("2026-11-12 14:05"))
        XCTAssertFalse(Handout.readsAsTitle("Answer: ..............."))
        XCTAssertFalse(Handout.readsAsTitle("ab"))
        XCTAssertTrue(Handout.readsAsTitle("Names of the elements"))
        XCTAssertTrue(Handout.readsAsTitle("Page layout in Spanish"))
        XCTAssertTrue(Handout.readsAsTitle("R3.2 Electron transfer reactions"))
    }

    func testNoTitleGivesADatedName() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 14, minute: 5))!
        XCTAssertEqual(Handout.name([], at: d, calendar: cal), "Handout 2026-11-12 1405")
        XCTAssertEqual(Handout.name([L("Name:", x: 0, y: 0.9, w: 0.2, h: 0.03)], at: d, calendar: cal), "Handout 2026-11-12 1405")
        XCTAssertEqual(Handout.name([L("Unit 4: Oxidation", x: 0, y: 0.9, w: 0.5, h: 0.03)], at: d, calendar: cal), "Unit 4: Oxidation")
    }

    func testLongTitlesAreCutAtAWord() {
        let t = Handout.clean("  The   history of the periodic table and how Mendeleev predicted the missing elements.  ")
        XCTAssertLessThanOrEqual(t.count, 48)
        XCTAssertEqual(t, "The history of the periodic table and how")
        XCTAssertEqual(Handout.clean("Lab 3 — Titration."), "Lab 3 — Titration")
    }
}
