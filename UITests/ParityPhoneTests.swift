import XCTest

/// On the iPhone every feature the iPad has must be reachable (Nov 16 2026): the Calendar's Week view, drawn narrow, and a board's
/// Split screen (the iPad's Side by side, stacked: the board on top, Today or the Calendar below). The screenshots ("phone-…") are
/// printed in the phone-check log. Skips itself on the iPad.
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
        sleep(2)
        app.tap() // lets the interruption monitor answer a permission alert
        // the view menu shows the current view's name (Day on a fresh phone)
        let menu = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Day", "3 days", "Week", "Month", "List"])).firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "no view menu")
        menu.tap()
        let week = app.buttons["Week"].firstMatch
        XCTAssertTrue(week.waitForExistence(timeout: 5), "the iPhone's view menu has no Week")
        week.tap()
        sleep(2)
        shot("phone-week")
        // seven day headers, each opening its day
        app.swipeLeft()
        sleep(2)
        shot("phone-week-next")
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
