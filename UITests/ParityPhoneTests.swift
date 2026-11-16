import XCTest

/// On the iPhone every feature the iPad has must be reachable (Nov 16 2026): the Calendar's Week view, drawn narrow, and a board's
/// Split screen (the iPad's Side by side, stacked: the board on top, Today or the Calendar below). The screenshots ("phone-…") are
/// printed in the UI check log. Skips itself on the iPad.
final class ParityPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    /// Lets the calendar's permission ask through, if the system shows it.
    func allowCalendar() {
        addUIInterruptionMonitor(withDescription: "calendar") { alert in
            for label in ["Allow Full Access", "Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
    }

    func testCalendarHasAWeekView() {
        allowCalendar()
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        let calTab = app.tabBars.buttons["Calendar"]
        XCTAssertTrue(calTab.waitForExistence(timeout: 15), "no Calendar tab")
        calTab.tap()
        // the view menu (the calendar button at the top right; its label is the current view's name)
        let menu = app.descendants(matching: .any)["calendar-view"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no view menu")
        sleep(1)
        menu.tap()
        sleep(2)
        shot("phone-calendar-menu")
        let week = app.buttons.matching(NSPredicate(format: "label == 'Week' AND identifier != 'calendar-view'")).firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5), "the iPhone's view menu has no Week")
        week.tap()
        sleep(2)
        shot("phone-week")
        // the next week
        let later = app.buttons["Later"].firstMatch
        if later.exists && later.isHittable { later.tap() } else { app.swipeLeft() }
        sleep(2)
        shot("phone-week-next")
    }

    /// Home, Files, How Nexus works and Share into Nexus, from the More tab.
    func testMoreHasTheNewPlaces() {
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "no More tab")
        more.tap()

        func openRow(_ name: String) {
            let row = app.buttons[name].firstMatch
            var tries = 0
            while !row.waitForExistence(timeout: 2) && tries < 8 { app.swipeUp(); tries += 1 }
            XCTAssertTrue(row.waitForExistence(timeout: 10), "More has no \(name)")
            row.tap()
            sleep(2)
        }
        func back() {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
        }

        openRow("Home")
        XCTAssertTrue(app.descendants(matching: .any)["home-fig-slipped"].waitForExistence(timeout: 10), "Home has no figures")
        shot("phone-home")
        app.swipeUp()
        sleep(1)
        shot("phone-home-lower")
        back()

        openRow("Files")
        XCTAssertTrue(app.navigationBars["Files"].waitForExistence(timeout: 10), "Files didn't open")
        shot("phone-files")
        let nb = app.buttons["file-notebooks"].firstMatch
        if nb.exists { nb.tap(); sleep(2); shot("phone-files-folder"); back() }
        back()

        openRow("How Nexus works")
        shot("phone-guide")
        back()

        openRow("Settings")
        openRow("Share into Nexus")
        shot("phone-share")
    }

    func testBoardSplitScreen() {
        app.launchArguments = ["-NexusTestPdfBoard"]
        app.launch()
        let insert = app.buttons["Insert"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        shot("phone-board")

        for (screen, name) in [("Today", "phone-split-today"), ("Calendar", "phone-split-calendar")] {
            let title = app.buttons["Zoom test"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 10), "no board name button")
            title.tap()
            let split = app.buttons["Split screen"].firstMatch
            XCTAssertTrue(split.waitForExistence(timeout: 5), "the board's menu has no Split screen")
            split.tap()
            let pick = app.buttons[screen].firstMatch
            XCTAssertTrue(pick.waitForExistence(timeout: 5), "Split screen has no \(screen)")
            pick.tap()
            sleep(3)
            shot(name)
        }
        let close = app.buttons["Close this pane"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the second pane has no close button")
        close.tap()
        sleep(2)
        XCTAssertFalse(app.buttons["Close this pane"].exists, "the second pane didn't close")
    }
}
