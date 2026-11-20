import XCTest

/// A screenshot tour of the iPad app for the new-look design pass (Nov 20 2026, step 3 of the switch-over plan): every place in the
/// sidebar, a workstream page, Study, a notebook, Settings, and a board with its bar, menus and tool rows, light and dark. It checks
/// nothing beyond getting there: a screen it can't reach is logged and skipped, so one missing row doesn't lose the rest of the tour.
/// The screenshots ("tour-pad-…") are printed in the ui-check log. Run alone with a commit message holding [ui-only: TourPadTests].
/// Skips itself on the iPhone (TourPhoneTests is the iPhone's tour).
final class TourPadTests: XCTestCase {
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

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func launch(_ args: [String]) {
        app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        _ = app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 15)
        sleep(2)
    }

    /// The sidebar's list (the first collection view, the split view's left column).
    func sidebar() -> XCUIElement { app.collectionViews.firstMatch }

    /// Finds a row by identifier, button or text, scrolling the sidebar down then back up; nil (and a log line) when it isn't there.
    func find(_ name: String) -> XCUIElement? {
        func look() -> XCUIElement? {
            for e in [el(name), app.buttons[name].firstMatch, app.staticTexts[name].firstMatch] where e.exists && e.isHittable { return e }
            return nil
        }
        if let e = look() { return e }
        for _ in 0..<5 { sidebar().swipeUp(); if let e = look() { return e } }
        for _ in 0..<8 { sidebar().swipeDown(); if let e = look() { return e } }
        print("UISTEP tour: no \(name)")
        return nil
    }

    func open(_ name: String, _ shotName: String, wait: UInt32 = 2) {
        guard let e = find(name) else { return }
        e.tap()
        sleep(wait)
        shot(shotName)
    }

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists && b.isHittable { b.tap() }
        sleep(1)
    }

    func places(_ suffix: String) {
        open("sidebar-Home", "tour-pad-home" + suffix)
        open("sidebar-Today", "tour-pad-today" + suffix)
        open("sidebar-Planner", "tour-pad-planner" + suffix)
        open("sidebar-Calendar", "tour-pad-calendar" + suffix)
        open("sidebar-Tasks", "tour-pad-tasks" + suffix)
        open("sidebar-Applications", "tour-pad-applications" + suffix)
        open("sidebar-Study", "tour-pad-study" + suffix)
        open("Chemistry HL", "tour-pad-workstream" + suffix)
    }

    func testTourLight() {
        launch([])
        shot("tour-pad-sidebar-top")
        places("")
        // the Chemistry page's Study, its units and a deck
        if let s = find("study-page-chemistry-hl") ?? find("Study") { s.tap(); sleep(2); shot("tour-pad-workstream-study") }
        open("sidebar-Study", "tour-pad-study-again")
        if let p = find("study-page-chemistry-hl") { p.tap(); sleep(3); shot("tour-pad-study-page") }
        if let t = find("study-theme-R1") { t.tap(); sleep(2); shot("tour-pad-study-units"); back() }
        if let p = find("study-practice-acids") { p.tap(); sleep(2); shot("tour-pad-study-practice"); back() }
        open("sidebar-Ideas", "tour-pad-ideas")
        open("sidebar-Claude", "tour-pad-claude")
        open("Inbox", "tour-pad-inbox")
        // the lower half of the sidebar: Recent, Notebooks, the foot
        for _ in 0..<4 { sidebar().swipeUp() }
        sleep(1)
        shot("tour-pad-sidebar-bottom")
        open("sidebar-Time", "tour-pad-time")
        open("sidebar-Files", "tour-pad-files")
        open("sidebar-Settings", "tour-pad-settings")
        open("sidebar-How Nexus works", "tour-pad-guide")
        open("sidebar-Search boards", "tour-pad-board-search")
    }

    func testTourDark() {
        launch(["-NexusTestDark"])
        shot("tour-pad-sidebar-top-dark")
        places("-dark")
    }

    /// The board's bar sits right of the floating sidebar in landscape: put the sidebar away (the bar's rightmost Sidebar button).
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

    func dismissMenu() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        sleep(1)
    }

    func boardTour(_ suffix: String, dark: Bool) {
        launch(["-NexusTestPdfBoard", "-board.fingersDraw", "YES", "-board.dark", dark ? "always" : "never", "-board.penKind", "pen"]
               + (dark ? ["-NexusTestDark"] : []))
        guard app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30) else { print("UISTEP tour: the board didn't open"); return }
        sleep(3)
        shot("tour-pad-board-with-sidebar" + suffix)
        hideSidebar()
        let pen = button("Pen")
        if pen.exists && pen.isHittable { pen.tap(); sleep(1) }
        // a few strokes, so the ink shows
        let canvas = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) ?? app.windows.firstMatch
        for i in 0..<3 {
            let y = 0.35 + 0.08 * CGFloat(i)
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: y))
                .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: y + 0.02)),
                       withVelocity: XCUIGestureVelocity(300), thenHoldForDuration: 0)
        }
        sleep(1)
        shot("tour-pad-board-pen" + suffix)
        guard !dark else { return }
        for (label, name) in [("Highlighter", "highlighter"), ("Eraser", "eraser"), ("Select", "lasso"), ("Text", "text"), ("Shapes", "shapes")] {
            let b = button(label)
            if b.exists && b.isHittable { b.tap(); sleep(1); shot("tour-pad-board-tool-" + name) } else { print("UISTEP tour: no \(label) tool") }
        }
        for (label, name) in [("Insert", "insert-menu"), ("Background", "background-menu"), ("Board menu", "board-menu")] {
            let b = button(label)
            if b.exists && b.isHittable { b.tap(); sleep(1); shot("tour-pad-board-" + name); dismissMenu() } else { print("UISTEP tour: no \(label)") }
        }
        let tools = button("Tools")
        if tools.exists && tools.isHittable { tools.tap(); sleep(2); shot("tour-pad-board-tools-panel"); dismissMenu() }
    }

    func testTourBoardLight() { boardTour("", dark: false) }
    func testTourBoardDark() { boardTour("-dark", dark: true) }
}
