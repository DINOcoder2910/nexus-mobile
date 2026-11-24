import XCTest
import UIKit

/// The iPhone's one Live Activity (Sources/LiveActivity/, the extension in Widgets/): on sample data with a timer running on "Redox
/// worksheet" (-NexusTestTime) and the recording demo (-NexusTestRecordings: no microphone). The card shows the timer on the Lock
/// Screen and in the Dynamic Island when the app is in front, a recording takes its big row with the timer on the line under it,
/// Settings › Lock Screen says what shows and how it looks, the line's Stop on the Lock Screen stops the timer in the app, and once
/// nothing runs the card shows the task up next, whose Start starts the timer. iPhone only (`ui-check.yml` runs every "…PhoneTests"
/// class on its iPhone simulator); the "phone-live-…" screenshots are printed into its log.
final class LiveActivityPhoneTests: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-NexusTestTime", "-NexusTestRecordings"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 5) { sample.tap() }
        let ask = springboard.alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
    }

    func shot(_ base: String) {
        let name = "phone-" + base
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// A row of More (Settings, Recordings), scrolled to.
    func openMoreRow(_ name: String) {
        app.tabBars.buttons["More"].tap()
        let row = app.buttons[name].firstMatch
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 8 { app.collectionViews.firstMatch.swipeUp(); tries += 1 }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "More has no \(name)")
        row.tap()
        sleep(2)
    }

    func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
    }

    /// Settings' "Showing now", scrolled to.
    func liveStatus() -> XCUIElement {
        let status = app.staticTexts["live-status"].firstMatch
        var tries = 0
        while !(status.exists && status.isHittable) && tries < 14 { app.swipeUp(velocity: .slow); tries += 1 }
        return status
    }

    /// The app's Live Activity log (Settings' Lock Screen, test runs only) into the test's output (the log's UISTEP lines).
    func printLog(_ when: String) {
        let log = app.staticTexts["live-log"].firstMatch
        if !log.exists { app.swipeUp(velocity: .slow) }
        print("UISTEP 0 live-log \(when): \(log.exists ? log.label : "(not found)")")
    }

    /// Waits until `e`'s label holds `text`.
    func waitLabel(_ e: XCUIElement, contains text: String, _ timeout: TimeInterval = 15) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [expectation(for: p, evaluatedWith: e)], timeout: timeout) == .completed
    }

    func testLiveActivities() {
        XCTAssertTrue(app.staticTexts["Redox worksheet"].firstMatch.waitForExistence(timeout: 20), "Today isn't up")
        XCTAssertTrue(app.buttons["Stop the timer"].firstMatch.waitForExistence(timeout: 10), "no running timer in the app")
        sleep(3)

        // Settings › Lock Screen: the running timer is on the Lock Screen
        openMoreRow("Settings")
        let status = liveStatus()
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Settings has no Lock Screen section")
        XCTAssertTrue(waitLabel(status, contains: "Timer: Redox worksheet"), "the timer isn't showing on the Live Activity (\(status.label))")
        shot("live-1-settings")
        printLog("at the start")
        let preview = app.buttons["live-preview"].firstMatch
        if !preview.isHittable { app.swipeUp(velocity: .slow) }
        preview.tap()
        XCTAssertTrue(app.otherElements["live-preview-lock"].firstMatch.waitForExistence(timeout: 10), "See how it looks didn't open")
        sleep(1)
        shot("live-2-preview")
        back()
        back()

        // home: the Dynamic Island shows the timer
        XCUIDevice.shared.press(.home)
        sleep(4)
        shot("live-3-island-timer")
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 15), "Nexus didn't come back")
        openMoreRow("Settings")
        _ = liveStatus()
        printLog("back from the home screen")
        back()

        // a recording joins it
        openMoreRow("Recordings")
        let start = app.buttons["rec-start-meeting"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 15), "the Recordings screen didn't open")
        start.tap()
        XCTAssertTrue(app.buttons["rec-stop"].firstMatch.waitForExistence(timeout: 10), "recording didn't start")
        sleep(3)
        back()
        openMoreRow("Settings")
        let both = liveStatus()
        XCTAssertTrue(waitLabel(both, contains: "Recording: Meeting"), "the recording isn't showing on the Live Activity (\(both.label))")
        XCTAssertTrue(both.label.contains("Timer: Redox worksheet"), "the timer went from the Live Activity (\(both.label))")
        printLog("after the recording started")
        back()
        XCUIDevice.shared.press(.home)
        sleep(6)
        shot("live-4-island-both")

        // Notification Centre shows the Lock Screen card
        pullDown()
        shot("live-5-lock-screen")

        // Stop on the timer's line stops the timer in Nexus (iOS runs the button in the app, in the background). The first press
        // on a Live Activity asks "Allow Live Activities from Nexus?" (Allow).
        let stop = springboard.buttons["Stop the timer"].firstMatch
        let found = stop.waitForExistence(timeout: 8)
        if found {
            var presses = 0
            // by coordinate: the springboard says a Live Activity's buttons aren't hittable (it draws them from another process)
            while stop.exists && presses < 4 {
                let allow = springboard.buttons["Allow"].firstMatch
                if allow.exists { allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(2) }
                // tapped at the place it was, not by the element: the card can change between the look and the tap (Nov 23, PR #59:
                // the first press had worked, and the button went during the second tap's lookup, failing the query)
                if stop.exists {
                    let f = stop.frame
                    springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
                }
                presses += 1
                sleep(4)
                if presses == 1 { shot("live-6-stack-open") }
            }
            shot("live-7-timer-stopped")
            XCTAssertFalse(stop.exists, "the timer is still on the Lock Screen after Stop")
        } else {
            print("UINOTE the Lock Screen card's Stop isn't in the springboard's elements on this simulator; stopping in the app instead")
        }
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 15), "Nexus didn't come back")
        sleep(2)
        if found {
            let pill = app.buttons["Stop the timer"].firstMatch
            let gone = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pill)], timeout: 15)
            XCTAssertEqual(gone, .completed, "Stop on the Lock Screen didn't stop the timer")
        } else {
            let pill = app.buttons["Stop the timer"].firstMatch
            if pill.waitForExistence(timeout: 5) { pill.tap() }
        }

        // stopping the recording too: the card shows the day (the task up next, or that the day is clear)
        // (More is at its list here: the test went back to it before leaving for the home screen; the iPhone shows the pill on it)
        let recStop = app.buttons["rec-pill-stop"].firstMatch
        XCTAssertTrue(recStop.waitForExistence(timeout: 10), "no recording pill to stop")
        recStop.tap()
        let stopped = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: recStop)], timeout: 15)
        XCTAssertEqual(stopped, .completed, "recording didn't stop")
        sleep(2)
        openMoreRow("Settings")
        let after = liveStatus()
        printLog("after both stopped")
        XCTAssertTrue(waitLabel(after, contains: "Next up: ", 6) || after.label.contains("Day: "), "the card doesn't show the day after both stopped (\(after.label))")
        XCTAssertFalse(after.label.contains("Timer: ") || after.label.contains("Recording: "), "the card still shows a timer or a recording (\(after.label))")
        let next = after.label.contains("Next up: ")
        back()
        XCUIDevice.shared.press(.home)
        sleep(3)
        shot("live-8-island-day")
        pullDown()
        shot("live-9-lock-screen-day")

        // Start on the next task starts the timer on it
        guard next else { return }
        let go = springboard.buttons["Start the timer on it"].firstMatch
        if go.waitForExistence(timeout: 8) {
            go.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            sleep(7)
            shot("live-10-started")
            XCUIDevice.shared.press(.home)
            sleep(1)
            app.activate()
            XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 15), "Nexus didn't come back")
            let pill = app.buttons["Stop the timer"].firstMatch
            XCTAssertTrue(pill.waitForExistence(timeout: 15), "Start on the Lock Screen didn't start the timer")
            openMoreRow("Settings")
            let started = liveStatus()
            XCTAssertTrue(waitLabel(started, contains: "Timer: "), "the card doesn't show the timer Start started (\(started.label))")
            printLog("after Start")
            back()
            // and stopped again in the app, so the tests after this one find the sample as it was (TestHooks starts its timer again)
            if pill.waitForExistence(timeout: 5) { pill.tap() }
        } else {
            print("UINOTE the card's Start isn't in the springboard's elements on this simulator")
        }
    }

    /// Notification Centre (it shows the Lock Screen's Live Activities), pulled down from the top.
    func pullDown() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.003))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.75)))
        sleep(3)
    }
}
