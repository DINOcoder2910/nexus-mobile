import XCTest

/// The sidebar's notebook tree (Nov 13 2026): notebooks > notebooks inside them (any depth) > boards, each level with an arrow,
/// in notebook.json's order (OneNote's); a board opens from its row and its row is the selected one, so another board is one tap
/// away, also after the sidebar was put away for the board. The app makes the notebooks itself (`-NexusTestNestedNotebooks`,
/// Sources/Common/TestHooks.swift). The screenshots ("sidebar-…") are printed in the ui-check log.
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

    /// Swipes the sidebar up until `el` can be tapped.
    func reach(_ el: XCUIElement, _ what: String) {
        var tries = 0
        while !(el.exists && el.isHittable) && tries < 10 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(el.waitForExistence(timeout: 5) && el.isHittable, "can't reach " + what)
    }

    func expand(_ name: String) {
        let arrow = app.buttons["Expand " + name].firstMatch
        reach(arrow, "the arrow of " + name)
        arrow.tap()
        XCTAssertTrue(app.buttons["Collapse " + name].firstMatch.waitForExistence(timeout: 5), name + " didn't open")
    }

    func y(_ name: String) -> CGFloat { app.staticTexts[name].firstMatch.frame.minY }

    /// Opens a board from its row and shows the sidebar again over it (the board puts it away).
    func openFromSidebar(_ board: String) {
        let row = app.staticTexts[board].firstMatch
        reach(row, board)
        row.tap()
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
        print("UISTEP \(board) row selected: \(cell.isSelected)")
    }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        launch(dark: dark)
        // closed: the top level only
        reach(app.buttons["Expand School"].firstMatch, "School")
        XCTAssertFalse(app.staticTexts["Chemistry"].exists, "School's notebooks show while it is closed")
        expand("School")
        expand("Chemistry")
        expand("R3 Energetics")
        expand("Week 1")
        XCTAssertTrue(app.staticTexts["Calorimetry"].firstMatch.waitForExistence(timeout: 5), "Week 1's boards aren't listed")
        // OneNote's order (notebook.json), not by name: Week 2 before Week 1, its notebooks before its boards, Hess's law before Bond
        XCTAssertLessThan(y("Week 2"), y("Week 1"))
        XCTAssertLessThan(y("Week 1"), y("Calorimetry"))
        XCTAssertLessThan(y("Calorimetry"), y("Hess's law"))
        XCTAssertLessThan(y("Hess's law"), y("Bond enthalpy"))
        XCTAssertLessThan(y("R3 Energetics"), y("R1 Structure"))
        XCTAssertLessThan(y("Chemistry"), y("Biology"))
        // a board sits further in than its notebook
        XCTAssertGreaterThan(app.staticTexts["Calorimetry"].firstMatch.frame.minX, app.staticTexts["Week 1"].firstMatch.frame.minX)
        sleep(1)
        shot("sidebar-tree-\(mode)")

        // open a board from the sidebar, then switch to another without the notebook page
        openFromSidebar("Calorimetry")
        shot("sidebar-board-open-\(mode)")
        openFromSidebar("Bond enthalpy")
        XCTAssertTrue(app.staticTexts["Enthalpy of combustion"].firstMatch.exists, "the tree closed when switching boards")

        // closing a level hides what is inside it
        let collapse = app.buttons["Collapse Week 1"].firstMatch
        reach(collapse, "Week 1's arrow")
        collapse.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Enthalpy of combustion"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed, "Week 1's boards still show when it is closed")
        sleep(1)
        shot("sidebar-switched-\(mode)")
    }

    func testNestedNotebooksLight() { run(dark: false) }

    func testNestedNotebooksDark() { run(dark: true) }
}

/// The same tree on the iPhone: the Notebooks tab. Runs only on an iPhone simulator (ui-check.yml's iPhone step runs every
/// "…PhoneTests" class there and prints its shots whose name has "phone").
final class SidebarPhoneTests: XCTestCase {
    let app = XCUIApplication()

    func testPhoneNotebooksTree() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone only") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-NexusTestNestedNotebooks"]
        app.launch()
        let tab = app.tabBars.buttons["Notebooks"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no Notebooks tab")
        tab.tap()
        for name in ["School", "Chemistry", "R3 Energetics"] {
            let arrow = app.buttons["Expand " + name].firstMatch
            var tries = 0
            while !(arrow.exists && arrow.isHittable) && tries < 8 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
            XCTAssertTrue(arrow.waitForExistence(timeout: 5), "no arrow for " + name)
            arrow.tap()
        }
        XCTAssertTrue(app.staticTexts["Bond enthalpy"].firstMatch.waitForExistence(timeout: 5), "R3 Energetics' boards aren't listed")
        sleep(1)
        print("UISTEP \(Date().timeIntervalSince1970) sidebar-phone-tree")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "sidebar-phone-tree"
        a.lifetime = .keepAlways
        add(a)
        // a board opens from its row (over everything, as on the iPhone)
        app.staticTexts["Bond enthalpy"].firstMatch.tap()
        let tabsGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: tab)
        XCTAssertEqual(XCTWaiter().wait(for: [tabsGone], timeout: 20), .completed, "the board didn't open from its row")
    }
}
