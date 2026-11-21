import XCTest

/// The sidebar with a folder the size of the OneNote import (Nov 16 2026: 1,440 boards in 12 notebooks of 10 sections,
/// `-NexusTestManyNotebooks`, Sources/Common/TestHooks.swift). The tree reads only the notebooks it shows and counts the boards
/// away from the main thread (NotebookTreeModel), so the sidebar comes up, opens a notebook and switches boards at once. The times
/// are printed (UISTEP) beside SidebarTreeTests' same measure on a small tree (a tap and a look cost seconds in the CI simulator,
/// so the limits here catch a freeze, and the comparison shows a slowdown); the screenshots ("sidebar-many-…") are printed in the
/// ui-check log.
final class SidebarSpeedTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the iPad's sidebar") }
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func reach(_ el: XCUIElement, _ what: String) {
        var tries = 0
        while !(el.exists && el.isHittable) && tries < 10 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(el.waitForExistence(timeout: 5) && el.isHittable, "can't reach " + what)
    }

    /// Seconds until `el` exists (after `action`), printed.
    @discardableResult
    func time(_ what: String, _ el: XCUIElement, limit: Double, _ action: () -> Void) -> Double {
        let t0 = Date()
        action()
        XCTAssertTrue(el.waitForExistence(timeout: 30), what + " never showed")
        let s = Date().timeIntervalSince(t0)
        print("UISTEP \(Date().timeIntervalSince1970) time \(what): \(String(format: "%.2f", s)) s")
        XCTAssertLessThan(s, limit, what + " took too long")
        return s
    }

    func testManyBoards() {
        app.launchArguments = ["-NexusTestManyNotebooks"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 60), "the sidebar isn't up")
        let first = app.buttons["Expand G12 Notebook 01"].firstMatch
        // the notebooks come after the sidebar's own rows (Today … Ideas, Claude), which can put them below the fold, where the
        // list makes no row until it scrolls: scroll to the first one rather than expect it on screen
        if !first.waitForExistence(timeout: 10) { reach(first, "G12 Notebook 01") }
        XCTAssertTrue(first.waitForExistence(timeout: 20), "the notebooks aren't listed")
        reach(first, "G12 Notebook 01")
        // the counts arrive from the walk away from the main thread (10 sections x 12 boards)
        XCTAssertTrue(app.staticTexts["120"].firstMatch.waitForExistence(timeout: 20), "the board counts never showed")
        // timed on the row's own arrow turning (always on screen); what opens under it may be below the fold
        time("open a notebook", app.buttons["Collapse G12 Notebook 01"].firstMatch, limit: 8) { first.tap() }
        let section = app.buttons["Expand Section 01"].firstMatch
        reach(section, "Section 01")
        time("open a section", app.buttons["Collapse Section 01"].firstMatch, limit: 8) { section.tap() }
        reach(app.staticTexts["Page 01"].firstMatch, "Page 01")
        sleep(1)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "sidebar-many-light"
        a.lifetime = .keepAlways
        add(a)

        // open a board from its row, then the next one
        let page = app.staticTexts["Page 03"].firstMatch
        reach(page, "Page 03")
        time("open a board", app.buttons["Insert"].firstMatch, limit: 10) { page.tap() }
        sleep(1)
        if !app.buttons["New task"].firstMatch.isHittable {
            let side = app.buttons["Sidebar"].firstMatch
            XCTAssertTrue(side.waitForExistence(timeout: 5), "no Sidebar button on the board")
            side.tap()
            sleep(1)
        }
        let next = app.staticTexts["Page 04"].firstMatch
        reach(next, "Page 04")
        let t0 = Date()
        next.tap()
        // the board takes over: the sidebar goes away
        let away = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: app.buttons["New task"].firstMatch)
        _ = XCTWaiter().wait(for: [away], timeout: 15)
        print("UISTEP \(Date().timeIntervalSince1970) time switch boards: \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        sleep(1)
        // back to the sidebar: the new board's row is the selected one
        if !app.buttons["New task"].firstMatch.isHittable {
            let side = app.buttons["Sidebar"].firstMatch
            XCTAssertTrue(side.waitForExistence(timeout: 5), "no Sidebar button on the board")
            side.tap()
            sleep(1)
        }
        // the Recent section can list Page 04 too, above the notebook's row: look for a selected row holding it
        let cell = app.cells.matching(NSPredicate(format: "selected == true")).containing(.staticText, identifier: "Page 04").firstMatch
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: cell)
        let ok = XCTWaiter().wait(for: [selected], timeout: 10) == .completed
        let b = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        b.name = "sidebar-many-board-open"
        b.lifetime = .keepAlways
        add(b)
        XCTAssertTrue(ok, "Page 04's row isn't the selected one")
    }
}
