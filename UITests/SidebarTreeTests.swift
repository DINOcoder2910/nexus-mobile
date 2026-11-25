import XCTest

/// The sidebar's notebooks, one level at a time (Nov 25 2026; it was a tree of arrows from Nov 13, which went too many levels deep
/// in a OneNote import): the full list holds only the top notebooks; tapping one steps inside it, so the sidebar shows just that
/// notebook (Back, where it sits, its notebooks, then its boards, in notebook.json's order: OneNote's), and a notebook that only
/// holds one notebook is gone straight through. A board opens from its row and its row is the selected one, so another board is
/// one tap away, also after the sidebar was put away for the board. The app makes the notebooks itself
/// (`-NexusTestNestedNotebooks`, Sources/Common/TestHooks.swift). The screenshots ("sidebar-…") are printed in the ui-check log.
final class SidebarTreeTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the iPad's sidebar") }
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func launch(dark: Bool) {
        app.launchArguments = ["-NexusTestNestedNotebooks"] + (dark ? ["-NexusTestDark"] : [])
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 20), "the sidebar isn't up")
        sleep(2)
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The sidebar's list (the first one: the notebook page beside it is a scroll view, not a list).
    var sidebar: XCUIElement { app.collectionViews.firstMatch }

    /// A row of the sidebar by its name.
    func row(_ name: String) -> XCUIElement { sidebar.staticTexts[name].firstMatch }

    /// Swipes the sidebar up (then back down) until `el` can be tapped, clear of the footer icons.
    func reach(_ el: XCUIElement, _ what: String) {
        var tries = 0
        while !(el.exists && el.isHittable) && tries < 10 { sidebar.swipeUp(velocity: .slow); tries += 1 }
        var back = 0
        while !(el.exists && el.isHittable) && back < 12 { sidebar.swipeDown(velocity: .slow); back += 1 }
        let bottom = app.windows.firstMatch.frame.maxY
        if el.exists && el.frame.maxY > bottom - 140 { sidebar.swipeUp(velocity: .slow) }
        XCTAssertTrue(el.waitForExistence(timeout: 5) && el.isHittable, "can't reach " + what)
    }

    /// Taps a notebook's row and waits for the sidebar to be inside `lands` (that notebook, or the one it goes straight through to).
    func stepInto(_ name: String, lands: String? = nil) {
        let r = row(name)
        reach(r, name)
        let t0 = Date()
        r.tap()
        let back = app.buttons["notebook-back"].firstMatch
        let inside = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", lands ?? name), object: back)
        XCTAssertEqual(XCTWaiter().wait(for: [inside], timeout: 40), .completed, "didn't step inside " + (lands ?? name))
        print("UISTEP \(Date().timeIntervalSince1970) time step into \(name): \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
    }

    func y(_ name: String) -> CGFloat { row(name).frame.minY }

    func inOrder(_ names: [String]) {
        for name in names { XCTAssertTrue(row(name).waitForExistence(timeout: 5), name + " isn't in the sidebar") }
        for (a, b) in zip(names, names.dropFirst()) { XCTAssertLessThan(y(a), y(b), a + " should come before " + b) }
    }

    /// Opens a board from its row and shows the sidebar again over it (the board puts it away).
    func openFromSidebar(_ board: String) {
        let r = row(board)
        reach(r, board)
        r.tap()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 20), board + " didn't open")
        sleep(2)
        // the sidebar's own New task button shows whether the sidebar is up
        if !app.buttons["New task"].firstMatch.isHittable {
            let side = app.buttons["Sidebar"].firstMatch
            XCTAssertTrue(side.waitForExistence(timeout: 5), "no Sidebar button on the board")
            side.tap()
            sleep(2)
        }
        let cell = app.cells.containing(.staticText, identifier: board).firstMatch
        if !cell.waitForExistence(timeout: 5) {
            shot("sidebar-missing-\(board)")
            let rows = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label).joined(separator: " | ")
            XCTFail("no sidebar row for \(board) after opening it; texts: \(rows)")
            return
        }
        print("UISTEP \(board) row selected: \(cell.isSelected)")
    }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        launch(dark: dark)
        // the full list: the top notebooks only, no arrows
        reach(row("School"), "School")
        XCTAssertFalse(row("Chemistry").exists, "School's notebooks show in the full list")
        XCTAssertFalse(app.buttons["Expand School"].exists, "the notebooks still have arrows")
        sleep(1)
        shot("sidebar-notebooks-\(mode)")

        // inside School, then Chemistry, then R3 Energetics: each level alone, in OneNote's order (notebook.json): a notebook's
        // notebooks before its boards, R3 before R1, Week 2 before Week 1, Hess's law before Bond enthalpy
        stepInto("School")
        inOrder(["Chemistry", "Biology"])
        XCTAssertFalse(row("R3 Energetics").exists, "Chemistry's notebooks show inside School")
        XCTAssertFalse(row("Planner").exists, "the places still show as rows inside a notebook")
        stepInto("Chemistry")
        inOrder(["R3 Energetics", "R1 Structure", "Syllabus"])
        stepInto("R3 Energetics")
        inOrder(["Week 2", "Week 1", "Hess's law", "Bond enthalpy"])
        XCTAssertFalse(row("Calorimetry").exists, "Week 1's boards show inside R3 Energetics")
        // where it sits, above: Notebooks › School › Chemistry
        XCTAssertTrue(app.buttons["notebook-crumb-School"].firstMatch.exists, "no School in the crumbs")
        XCTAssertTrue(app.buttons["notebook-crumb-Chemistry"].firstMatch.exists, "no Chemistry in the crumbs")
        sleep(1)
        shot("sidebar-inside-\(mode)")

        // open a board from the sidebar, then switch to another without the notebook page
        stepInto("Week 1")
        inOrder(["Calorimetry", "Enthalpy of combustion"])
        openFromSidebar("Calorimetry")
        shot("sidebar-board-open-\(mode)")
        openFromSidebar("Enthalpy of combustion")
        XCTAssertTrue(row("Calorimetry").exists, "the sidebar left Week 1 when switching boards")

        // Back goes up one level; a crumb goes straight there
        app.buttons["notebook-back"].firstMatch.tap()
        let up = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'R3 Energetics'"), object: app.buttons["notebook-back"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [up], timeout: 20), .completed, "Back didn't go up to R3 Energetics")
        app.buttons["notebook-crumb-School"].firstMatch.tap()
        XCTAssertTrue(row("Biology").waitForExistence(timeout: 20), "the School crumb didn't go to School")
        app.buttons["notebook-back"].firstMatch.tap()
        XCTAssertTrue(row("Planner").waitForExistence(timeout: 20), "Back from a top notebook didn't return to the full list")

        // a notebook that only holds one notebook is gone straight through: Tutor › Mechanics › Textbook
        stepInto("Tutor", lands: "Textbook")
        inOrder(["A Kinematics", "B Forces"])
        let tutorCrumb = row("Tutor")
        XCTAssertTrue(tutorCrumb.exists, "the crumbs don't say Textbook is in Tutor")
        XCTAssertFalse(app.buttons["notebook-crumb-Tutor"].exists, "Tutor (one notebook inside) is a stop in the crumbs")
        sleep(1)
        shot("sidebar-through-\(mode)")
        app.buttons["notebook-back"].firstMatch.tap()
        XCTAssertTrue(row("Planner").waitForExistence(timeout: 20), "Back from Textbook didn't skip Mechanics and Tutor")
    }

    func testNestedNotebooksLight() { run(dark: false) }

    func testNestedNotebooksDark() { run(dark: true) }
}

/// The same on the iPhone's Subjects tab: the top notebooks only (no arrows), each pushing its page, whose notebooks push theirs.
/// Runs only on an iPhone simulator (ui-check.yml's iPhone step runs every "…PhoneTests" class there and prints its shots whose
/// name has "phone").
final class SidebarPhoneTests: XCTestCase {
    let app = XCUIApplication()

    func testPhoneNotebooksTree() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone only") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-NexusTestNestedNotebooks"]
        app.launch()
        let tab = app.tabBars.buttons["Subjects"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no Subjects tab")
        tab.tap()
        let school = app.staticTexts["School"].firstMatch
        var tries = 0
        while !(school.exists && school.isHittable) && tries < 8 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(school.waitForExistence(timeout: 5), "School isn't listed")
        XCTAssertFalse(app.buttons["Expand School"].exists, "the notebooks still have arrows")
        XCTAssertFalse(app.staticTexts["Chemistry"].exists, "School's notebooks show in the list")
        sleep(1)
        print("UISTEP \(Date().timeIntervalSince1970) sidebar-phone-tree")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "sidebar-phone-tree"
        a.lifetime = .keepAlways
        add(a)
        // School's page, then Chemistry's from its card
        school.tap()
        let chemistry = app.staticTexts["Chemistry"].firstMatch
        XCTAssertTrue(chemistry.waitForExistence(timeout: 15), "School's page doesn't show Chemistry")
        chemistry.tap()
        XCTAssertTrue(app.staticTexts["R3 Energetics"].firstMatch.waitForExistence(timeout: 15), "Chemistry's page didn't open")
    }
}
