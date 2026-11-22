import XCTest
import UIKit

/// Today in the one task order (NexusCore DayOrder.swift, the laptop's dayorder.js), on sample data with today's order dragged on the
/// laptop (-NexusTestDayOrder, TestHooks.dayOrder): the timed task first ("Q1–5", 16:00), then the dragged order, which puts "Try the iPad
/// planner" before "Redox worksheet" although the file has them the other way round. `ui-check.yml` runs this class on the iPad and
/// `DayOrderPhoneTests` on the iPhone; their "dayorder-…" / "phone-dayorder-…" screenshots are printed into its log.
class DayOrderTests: XCTestCase {
    let app = XCUIApplication()
    var phone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    class var forPhone: Bool { false }

    override func setUpWithError() throws {
        try XCTSkipIf(phone != Self.forPhone, Self.forPhone ? "iPhone only" : "iPad only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = phone ? .portrait : .landscapeLeft
        app.launchArguments = ["-NexusTestDayOrder"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 5) { sample.tap() }
    }

    func shot(_ base: String) {
        let name = phone ? "phone-" + base : base
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testTodayFollowsTheDayOrder() {
        // in the list itself (Next up, the day's hours and Tomorrow can show the same titles)
        let list = app.otherElements["today-list"].firstMatch
        let timed = list.staticTexts["Q1–5"].firstMatch
        let dragged = list.staticTexts["Try the iPad planner"].firstMatch
        let other = list.staticTexts["Redox worksheet"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 20), "Today isn't up")
        // the system's notifications question (the reminders ask on a first launch) would cover the screenshot
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let ask = springboard.alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
        sleep(2)
        XCTAssertTrue(timed.exists && dragged.exists, "the plan's rows aren't all there")
        XCTAssertLessThan(timed.frame.minY, dragged.frame.minY, "the timed task comes first")
        XCTAssertLessThan(dragged.frame.minY, other.frame.minY, "the order dragged on the laptop wins over file order")
        shot("dayorder-today")
    }
}

final class DayOrderPhoneTests: DayOrderTests {
    override class var forPhone: Bool { true }
}
