import XCTest

/// The iPhone's screenshot tour for the new-look design pass (Nov 20 2026; TourPadTests is the iPad's): each tab, the screens in
/// More, a workstream page, Study, and a board with its compact bar and menus. It checks nothing beyond getting there: a screen it
/// can't reach is logged and skipped. The screenshots ("tour-phone-…") are printed in the ui-check log. Skips itself on the iPad.
final class TourPhoneTests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
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

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func launch(_ args: [String]) {
        app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        _ = app.tabBars.buttons["Today"].waitForExistence(timeout: 15)
        sleep(2)
    }

    func tab(_ name: String) {
        let t = app.tabBars.buttons[name]
        if t.waitForExistence(timeout: 5) { t.tap(); sleep(2) } else { print("UISTEP tour: no \(name) tab") }
    }

    func find(_ name: String) -> XCUIElement? {
        func look() -> XCUIElement? {
            for e in [el(name), app.buttons[name].firstMatch, app.staticTexts[name].firstMatch] where e.exists && e.isHittable { return e }
            return nil
        }
        if let e = look() { return e }
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 { list.swipeUp(); if let e = look() { return e } }
        for _ in 0..<10 { list.swipeDown(); if let e = look() { return e } }
        print("UISTEP tour: no \(name)")
        return nil
    }

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists && b.isHittable { b.tap() }
        sleep(1)
    }

    /// Opens a row of the More tab, shoots it, and comes back to More.
    func more(_ name: String, _ shotName: String) {
        tab("More")
        guard let e = find(name) else { return }
        e.tap()
        sleep(2)
        shot(shotName)
        back()
    }

    func tour(_ suffix: String) {
        tab("Today"); shot("tour-phone-today" + suffix)
        tab("Calendar"); shot("tour-phone-calendar" + suffix)
        tab("Inbox"); shot("tour-phone-inbox" + suffix)
        tab("Notebooks"); shot("tour-phone-notebooks" + suffix)
        tab("More"); shot("tour-phone-more-top" + suffix)
        for _ in 0..<3 { app.collectionViews.firstMatch.swipeUp() }
        sleep(1)
        shot("tour-phone-more-bottom" + suffix)
        more("sidebar-Home", "tour-phone-home" + suffix)
        more("sidebar-Planner", "tour-phone-planner" + suffix)
        more("sidebar-Tasks", "tour-phone-tasks" + suffix)
        more("Chemistry HL", "tour-phone-workstream" + suffix)
        more("sidebar-Study", "tour-phone-study" + suffix)
    }

    func testTourLight() {
        launch([])
        tour("")
        tab("More")
        if let s = find("sidebar-Study") {
            s.tap(); sleep(2)
            if let p = find("study-page-chemistry-hl") { p.tap(); sleep(3); shot("tour-phone-study-page")
                if let t = find("study-theme-R1") { t.tap(); sleep(2); shot("tour-phone-study-units") }
            }
        }
        more("sidebar-Applications", "tour-phone-applications")
        more("sidebar-Ideas", "tour-phone-ideas")
        more("sidebar-Settings", "tour-phone-settings")
    }

    func testTourDark() {
        launch(["-NexusTestDark"])
        tour("-dark")
    }

    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            ?? app.buttons[label].firstMatch
    }

    func testTourBoard() {
        launch(["-NexusTestPdfBoard", "-board.fingersDraw", "YES", "-board.dark", "never", "-board.penKind", "pen"])
        guard app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30) || app.buttons["Pen"].firstMatch.waitForExistence(timeout: 5)
        else { print("UISTEP tour: the board didn't open"); shot("tour-phone-board-missing"); return }
        sleep(3)
        shot("tour-phone-board")
        for (label, name) in [("Pen", "pen"), ("Highlighter", "highlighter"), ("Text", "text")] {
            let b = button(label)
            if b.exists && b.isHittable { b.tap(); sleep(1); shot("tour-phone-board-tool-" + name) }
        }
        for (label, name) in [("Insert", "insert-menu"), ("Board menu", "board-menu")] {
            let b = button(label)
            if b.exists && b.isHittable {
                b.tap(); sleep(1); shot("tour-phone-board-" + name)
                app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(1)
            }
        }
    }
}
