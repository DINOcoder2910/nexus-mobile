import XCTest
import UIKit

/// Time tracking on the iPad and the iPhone, on sample data with time tracked this week here and on the laptop and a timer running
/// (-NexusTestTime, TestHooks.timeSessions). The screenshots named "time-…" are printed into the time-check log (time-check.yml),
/// so a cloud thread can show them before asking for a ship. Runs on whichever simulator the workflow picks.
final class TimeTrackingTests: XCTestCase {
    let app = XCUIApplication()
    var phone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = phone ? .portrait : .landscapeLeft
        app.launchArguments = ["-NexusTestTime"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 5) { sample.tap() }
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The Time screen: the iPad's sidebar row (at its foot, by Settings), the iPhone's More tab.
    func openTimeScreen() {
        if phone {
            app.tabBars.buttons["More"].tap()
        }
        let list = app.collectionViews.firstMatch
        let row = app.buttons["Time"].firstMatch
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 8 { list.swipeUp(); tries += 1 }
        XCTAssertTrue(row.exists, "no Time row")
        row.tap()
        XCTAssertTrue(app.staticTexts["time-hero"].firstMatch.waitForExistence(timeout: 10), "the Time screen didn't open")
    }

    func testTimeTracking() {
        // Today, with the running timer (the iPad's sidebar row, the iPhone's pill) and "… tracked" under the date
        XCTAssertTrue(app.staticTexts["Redox worksheet"].firstMatch.waitForExistence(timeout: 20), "Today isn't up")
        // the system's notifications question (the reminders ask on a first launch) would cover the screenshots
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let ask = springboard.alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
        sleep(2)
        XCTAssertTrue(app.buttons["Stop the timer"].firstMatch.waitForExistence(timeout: 5), "no running timer showing")
        shot("time-1-today")

        // a task's menu: Start timer / Stop timer
        let lab = app.staticTexts["Q1–5"].firstMatch
        if lab.waitForExistence(timeout: 5) {
            lab.press(forDuration: 1.2)
            sleep(1)
            XCTAssertTrue(app.buttons["Start timer"].firstMatch.waitForExistence(timeout: 5), "no Start timer in the menu")
            shot("time-2-menu")
            // start it: the Redox timer stops, this one runs
            app.buttons["Start timer"].firstMatch.tap()
            sleep(2)
        }

        // the task panel's Time section (open the running task from the timer)
        _ = app.buttons["Stop the timer"].firstMatch.waitForExistence(timeout: 5)
        let title = app.buttons["Q1–5"].firstMatch
        if title.exists && title.isHittable { title.tap() } else { app.staticTexts["Q1–5"].firstMatch.tap() }
        let timer = app.buttons["task-timer"].firstMatch
        var tries = 0
        while !(timer.exists && timer.isHittable) && tries < 12 { app.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(timer.exists, "no Time section in the task panel")
        // bring the section up near the top of the panel so its sessions show under it
        if timer.isHittable {
            let from = timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -220)))
        }
        sleep(1)
        shot("time-3-panel")
        // close the panel
        app.swipeDown(velocity: .fast)
        sleep(1)
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        if app.buttons["Close"].firstMatch.exists { app.buttons["Close"].firstMatch.tap() }
        sleep(1)

        // the Time screen: the week, the day's sessions, by workstream
        openTimeScreen()
        sleep(2)
        shot("time-4-screen")
        if phone {
            app.swipeUp()
            sleep(1)
            shot("time-5-screen-lower")
        }

        // a session's sheet: change its times or remove it
        let session = app.staticTexts["Q1–5"].firstMatch
        if session.exists && session.isHittable {
            session.tap()
            sleep(1)
            shot("time-6-session")
        }
    }
}
