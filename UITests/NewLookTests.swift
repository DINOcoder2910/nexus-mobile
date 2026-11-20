import XCTest

/// The new look on the iPad (Nov 20 2026): the sidebar's subjects (open one as a folder, or step inside it), a subject's page,
/// Study's Units covered, the board's bar (Draw | Insert | View, folded into one bar) and the quick ring (tap, hold and slide,
/// double tap, tuck into the edge). The screenshots ("look-…") are printed in the UI check log; the iPhone's are in
/// NewLookPhoneTests.
final class NewLookTests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// Swipes the sidebar up until `e` can be tapped.
    func reach(_ e: XCUIElement, _ what: String) {
        var tries = 0
        while !(e.exists && e.isHittable) && tries < 10 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(e.waitForExistence(timeout: 5) && e.isHittable, "can't reach " + what)
    }

    // MARK: sidebar, subject, study

    func runSidebar(dark: Bool) {
        let mode = dark ? "dark" : "light"
        app = XCUIApplication()
        app.launchArguments = ["-NexusTestNestedNotebooks"] + (dark ? ["-NexusTestDark"] : [])
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 30), "the sidebar isn't up")
        sleep(2)
        shot("look-sidebar-\(mode)")

        // the arrow opens a subject as a folder: Tasks, Notebooks, Study, Files under it
        let arrow = app.buttons["Expand Chemistry HL"].firstMatch
        reach(arrow, "Chemistry HL's arrow")
        arrow.tap()
        XCTAssertTrue(el("subject-study-chemistry-hl").waitForExistence(timeout: 5), "Chemistry HL didn't open as a folder")
        sleep(1)
        shot("look-sidebar-folder-\(mode)")
        app.buttons["Collapse Chemistry HL"].firstMatch.tap()

        // the name steps inside the subject: only its parts, the places as icons on top, Back to every subject
        let row = el("subject-chemistry-hl")
        reach(row, "Chemistry HL's row")
        row.tap()
        XCTAssertTrue(el("subject-back").waitForExistence(timeout: 10), "didn't step inside Chemistry HL")
        sleep(2)
        shot("look-subject-\(mode)")
        el("subject-back").tap()
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 10), "Back didn't return to every subject")

        // Study's Units covered (the old layout, tidied)
        let study = el("sidebar-Study")
        reach(study, "the Study row")
        study.tap()
        let page = el("study-page-chemistry-hl")
        XCTAssertTrue(page.waitForExistence(timeout: 15), "no Chemistry HL on Study")
        page.tap()
        XCTAssertTrue(el("study-theme-R1").waitForExistence(timeout: 15), "no Units covered")
        sleep(2)
        shot("look-study-units-\(mode)")
    }

    func testSidebarSubjectStudyLight() { runSidebar(dark: false) }
    func testSidebarSubjectStudyDark() { runSidebar(dark: true) }

    // MARK: the board's bar and the quick ring

    func launchBoard(dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-NexusTestPdfBoard", "-board.fingersDraw", "YES", "-board.dark", dark ? "always" : "never"]
        app.launch()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        hideSidebar()
    }

    /// The sidebar floats over the board in landscape: put it away with the bar's Sidebar button (as in PenOptionsTests).
    func hideSidebar() {
        let width = app.windows.firstMatch.frame.width
        for _ in 0..<4 {
            let close = app.buttons.matching(NSPredicate(format: "label == 'Close the board'")).allElementsBoundByIndex.first { $0.exists && $0.frame.width > 0 }
            guard let close, close.frame.minX > width * 0.1 else { return }
            let sides = app.buttons.matching(identifier: "Sidebar").allElementsBoundByIndex.filter { $0.exists }
            guard let side = sides.max(by: { $0.frame.minX < $1.frame.minX }) else { return }
            side.tap()
            sleep(2)
        }
    }

    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            ?? app.buttons[label].firstMatch
    }

    func ringLabel() -> String { el("quick-ring").label }

    func testBoardBarAndRing() {
        launchBoard(dark: false)
        // the bar's modes
        if el("board-mode-menu").exists { el("board-mode-menu").tap(); button("Draw").tap(); sleep(1) } // folded by an earlier run
        XCTAssertTrue(el("board-mode-draw").waitForExistence(timeout: 5), "no Draw | Insert | View switch")
        button("Pen").tap()
        sleep(1)
        shot("look-board-draw-light")
        el("board-mode-insert").tap()
        XCTAssertTrue(button("PDF printout…").waitForExistence(timeout: 5), "Insert's row has no PDF printout")
        sleep(1)
        shot("look-board-insert-light")
        el("board-mode-view").tap()
        XCTAssertTrue(button("Ruler").waitForExistence(timeout: 5), "View's row has no Ruler")
        sleep(1)
        shot("look-board-view-light")
        el("board-mode-draw").tap()
        sleep(1)
        // folds into one bar, and opens again
        button("Fold the bar").tap()
        XCTAssertTrue(el("board-mode-menu").waitForExistence(timeout: 5), "the bar didn't fold")
        sleep(1)
        shot("look-board-folded-light")
        button("Open the bar").tap()
        XCTAssertTrue(el("board-mode-draw").waitForExistence(timeout: 5), "the bar didn't open again")

        // the quick ring: tap opens the fan
        let ring = el("quick-ring")
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "no quick ring")
        if el("quick-ring-tab").exists && el("quick-ring-tab").isHittable { el("quick-ring-tab").tap(); sleep(1) }
        print("UISTEP ring: \(ringLabel())")
        ring.tap()
        XCTAssertTrue(el("ring-item-0").waitForExistence(timeout: 5), "the fan didn't open")
        usleep(700_000)
        shot("look-ring-open-light")
        // tap a choice: the Highlighter
        el("ring-item-1").tap()
        sleep(1)
        XCTAssertTrue(ringLabel().contains("Highlighter"), "the ring didn't pick the Highlighter: \(ringLabel())")
        XCTAssertTrue(button("Highlighter").isSelected, "the bar doesn't show the Highlighter picked")
        shot("look-ring-picked-light")

        // hold and slide onto the middle choice (the ink's first colour), let go to pick it
        let window = app.windows.firstMatch.frame
        let c = CGPoint(x: ring.frame.midX, y: ring.frame.midY)
        let facing = atan2(window.midY - c.y, window.midX - c.x)
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.x, dy: c.y))
        let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: c.x + cos(facing) * 98, dy: c.y + sin(facing) * 98))
        start.press(forDuration: 0.7, thenDragTo: end)
        sleep(1)
        XCTAssertTrue(ringLabel().contains("Highlighter, Yellow"), "hold and slide didn't pick the first colour: \(ringLabel())")

        // a double tap goes back to the last tool (the Pen)
        ring.doubleTap()
        sleep(1)
        XCTAssertTrue(ringLabel().contains("Pen"), "double tap didn't go back to the Pen: \(ringLabel())")
        XCTAssertTrue(button("Pen").isSelected, "the bar doesn't show the Pen picked")

        // push it into the edge: it tucks away as a tab; tap the tab to bring it back
        let r = CGPoint(x: ring.frame.midX, y: ring.frame.midY)
        let from = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: r.x, dy: r.y))
        let to = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.maxX - 4, dy: r.y))
        from.press(forDuration: 0.05, thenDragTo: to)
        let tab = el("quick-ring-tab")
        XCTAssertTrue(tab.waitForExistence(timeout: 5) && tab.isHittable, "the ring didn't tuck into the edge")
        sleep(1)
        shot("look-ring-tucked-light")
        tab.tap()
        sleep(1)
        XCTAssertTrue(ring.isHittable, "the ring didn't come back from its tab")
    }

    func testBoardDark() {
        launchBoard(dark: true)
        if el("board-mode-menu").exists { el("board-mode-menu").tap(); button("Draw").tap(); sleep(1) }
        sleep(1)
        shot("look-board-draw-dark")
        let ring = el("quick-ring")
        if el("quick-ring-tab").exists && el("quick-ring-tab").isHittable { el("quick-ring-tab").tap(); sleep(1) }
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "no quick ring")
        ring.tap()
        XCTAssertTrue(el("ring-item-0").waitForExistence(timeout: 5), "the fan didn't open")
        usleep(700_000)
        shot("look-ring-open-dark")
        ring.tap() // closes it
    }
}

/// The new look on the iPhone: the Subjects tab, a subject's page, the board's bar and the quick ring. Screenshots "look-phone-…".
final class NewLookPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func testPhoneSubjects() {
        app.launchArguments = ["-NexusTestNestedNotebooks"]
        app.launch()
        let tab = app.tabBars.buttons["Subjects"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Subjects tab")
        tab.tap()
        sleep(2)
        shot("look-phone-subjects")
        let row = el("subject-chemistry-hl")
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 6 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(row.exists, "no Chemistry HL in Subjects")
        row.tap()
        sleep(2)
        shot("look-phone-subject")
    }

    func testPhoneBoardRing() {
        app.launchArguments = ["-NexusTestPdfBoard"]
        app.launch()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        shot("look-phone-board")
        let ring = el("quick-ring")
        if el("quick-ring-tab").exists && el("quick-ring-tab").isHittable { el("quick-ring-tab").tap(); sleep(1) }
        XCTAssertTrue(ring.waitForExistence(timeout: 5), "no quick ring")
        ring.tap()
        XCTAssertTrue(el("ring-item-0").waitForExistence(timeout: 5), "the fan didn't open")
        usleep(700_000)
        shot("look-phone-ring-open")
        el("ring-item-1").tap()
        sleep(1)
        XCTAssertTrue(el("quick-ring").label.contains("Highlighter"), "the ring didn't pick the Highlighter")
        ring.doubleTap()
        sleep(1)
    }
}
