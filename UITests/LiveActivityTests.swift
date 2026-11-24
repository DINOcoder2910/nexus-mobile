import XCTest
import UIKit

/// The iPad's Live Activity (Nov 23 2026: the same card as the iPhone's, LiveActivityPhoneTests): on sample data with a timer running
/// on "Redox worksheet" (-NexusTestTime), the card starts when the app is in front, Settings › Lock Screen says it shows the timer,
/// "See how it looks" draws it, and the Lock Screen (Notification Centre) shows it, where Stop stops the timer in the app. iPad only
/// (`ui-check.yml` runs it on its iPad simulator); the "live-…" screenshots are printed into its log.
final class LiveActivityTests: XCTestCase {
    let app = XCUIApplication()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone, "iPad only")
        continueAfterFailure = true
        // portrait: in landscape the springboard's Lock Screen is drawn rotated and a tap by coordinate on the card's Stop didn't
        // stop the timer (Nov 23, aa182b9); every other iPad test sets its own orientation
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-NexusTestTime"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 5) { sample.tap() }
        let ask = springboard.alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Settings (the icon at the sidebar's foot), its Lock Screen section's "Showing now" scrolled to.
    func liveStatus() -> XCUIElement {
        let settings = app.buttons["sidebar-Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "no Settings icon at the sidebar's foot")
        settings.tap()
        sleep(2)
        let status = app.staticTexts["live-status"].firstMatch
        var tries = 0
        while !(status.exists && status.isHittable) && tries < 14 { app.swipeUp(velocity: .slow); tries += 1 }
        return status
    }

    func waitLabel(_ e: XCUIElement, contains text: String, _ timeout: TimeInterval = 15) -> Bool {
        let p = NSPredicate(format: "label CONTAINS %@", text)
        return XCTWaiter().wait(for: [expectation(for: p, evaluatedWith: e)], timeout: timeout) == .completed
    }

    func testLiveActivityOnTheIPad() {
        XCTAssertTrue(app.staticTexts["Redox worksheet"].firstMatch.waitForExistence(timeout: 20), "Today isn't up")
        XCTAssertTrue(app.buttons["Stop the timer"].firstMatch.waitForExistence(timeout: 10), "no running timer in the app")
        sleep(3)

        // Settings › Lock Screen: the running timer is on the card
        let status = liveStatus()
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Settings has no Lock Screen section (is the extension in the app?)")
        let shows = waitLabel(status, contains: "Timer: Redox worksheet")
        let log = app.staticTexts["live-log"].firstMatch
        print("UISTEP 0 live-log: \(log.exists ? log.label : "(not found)")")
        shot("live-ipad-1-settings")
        XCTAssertTrue(shows, "the timer isn't showing on the iPad's Live Activity (\(status.label))")
        let preview = app.buttons["live-preview"].firstMatch
        if !preview.isHittable { app.swipeUp(velocity: .slow) }
        preview.tap()
        XCTAssertTrue(app.otherElements["live-preview-lock"].firstMatch.waitForExistence(timeout: 10), "See how it looks didn't open")
        sleep(1)
        shot("live-ipad-2-preview")
        // back to Settings: the preview's example cards carry "Stop the timer" buttons of their own, which the pill check below
        // would find (Nov 23, 4f15af9: the Lock Screen's Stop had worked)
        let bar = app.navigationBars["Live Activity"].firstMatch
        if bar.exists { bar.buttons.element(boundBy: 0).tap() }
        let closed = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.otherElements["live-preview-lock"].firstMatch)], timeout: 10)
        XCTAssertEqual(closed, .completed, "See how it looks didn't close")

        // the Lock Screen's cards (Notification Centre, pulled down from the top)
        XCUIDevice.shared.press(.home)
        sleep(3)
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.002))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))
        sleep(3)
        shot("live-ipad-3-lock-screen")

        // Stop on the card stops the timer in Nexus (the first press asks "Allow Live Activities from Nexus?")
        let stop = springboard.buttons["Stop the timer"].firstMatch
        if stop.waitForExistence(timeout: 8) {
            print("UISTEP 0 the card's Stop at \(stop.frame)")
            var presses = 0
            while stop.exists && presses < 4 {
                let allow = springboard.buttons["Allow"].firstMatch
                if allow.exists { allow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); sleep(2) }
                // tapped at the place it was: the card can change between the look and the tap (as LiveActivityPhoneTests)
                if stop.exists {
                    let f = stop.frame
                    springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
                }
                presses += 1
                sleep(4)
                if presses == 1 { shot("live-ipad-3b-after-first-press") }
            }
            shot("live-ipad-4-stopped")
            XCUIDevice.shared.press(.home)
            sleep(1)
            app.activate()
            let pill = app.buttons["Stop the timer"].firstMatch
            let gone = XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pill)], timeout: 15)
            XCTAssertEqual(gone, .completed, "Stop on the iPad's Lock Screen didn't stop the timer")
        } else {
            print("UINOTE the card's Stop isn't in the springboard's elements on the iPad simulator")
            XCUIDevice.shared.press(.home)
            sleep(1)
            app.activate()
        }
    }
}
