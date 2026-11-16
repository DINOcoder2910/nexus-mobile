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
        XCTAssertTrue(first.waitForExistence(timeout: 30), "the notebooks aren't listed")
        // the counts arrive from the walk away from the main thread (10 sections x 12 boards)
        XCTAssertTrue(app.staticTexts["120"].firstMatch.waitForExistence(timeout: 20), "the board counts never showed")
        reach(first, "G12 Notebook 01")
        time("open a notebook", app.buttons["Expand Section 01"].firstMatch, limit: 8) { first.tap() }
        let section = app.buttons["Expand Section 01"].firstMatch
        // its first board (the last ones are below the fold, where the list hasn't made their rows)
        time("open a section", app.staticTexts["Page 01"].firstMatch, limit: 8) { section.tap() }
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
        let cell = app.cells.containing(.staticText, identifier: "Page 04").firstMatch
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: cell)
        let ok = XCTWaiter().wait(for: [selected], timeout: 10) == .completed
        print("UISTEP \(Date().timeIntervalSince1970) time switch boards: \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
        sleep(2)
        let b = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        b.name = "sidebar-many-board-open"
        b.lifetime = .keepAlways
        add(b)
        XCTAssertTrue(ok, "Page 04's row isn't the selected one")
    }
}
