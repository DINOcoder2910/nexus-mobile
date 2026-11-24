import XCTest
import UIKit

/// The Planner as the new laptop app has it (Nov 21 2026), on sample data: the week's days with their loads, the Events and
/// Deadlines rows, a lane per subject, and the task bank with its filters; the bank button hides it. The screenshots
/// ("look-planner-…", "phone-look-planner-…") are printed in the UI check log; `PlannerLookPhoneTests` runs it on the iPhone.
class PlannerLookTests: XCTestCase {
    var app = XCUIApplication()
    var phone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    class var forPhone: Bool { false }

    override func setUpWithError() throws {
        try XCTSkipIf(phone != Self.forPhone, Self.forPhone ? "iPhone only" : "iPad only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = phone ? .portrait : .landscapeLeft
    }

    func shot(_ base: String) {
        let name = phone ? "phone-" + base : base
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func openPlanner(dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = dark ? ["-NexusTestDark"] : []
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 8) { sample.tap() }
        let ask = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
        if phone {
            let more = app.tabBars.buttons["More"]
            XCTAssertTrue(more.waitForExistence(timeout: 15), "no More tab")
            more.tap()
            let row = app.buttons["Planner"].firstMatch
            var tries = 0
            while !row.waitForExistence(timeout: 2) && tries < 6 { app.swipeUp(); tries += 1 }
            row.tap()
        } else {
            let row = app.staticTexts["Planner"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20), "the sidebar isn't up")
            row.tap()
        }
        XCTAssertTrue(el("planner").waitForExistence(timeout: 15), "the Planner isn't up")
        sleep(2)
        // the span and the Show row are kept on the device: back to the whole week, everything shown
        if el("show-all").exists { el("show-all").tap() }
        let week = el("plan-span").buttons["Week"].firstMatch
        if week.exists && week.isHittable { week.tap() }
        sleep(1)
    }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        openPlanner(dark: dark)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "day-head").count, 7, "the week isn't seven days")
        XCTAssertTrue(el("week-sum").exists, "no week summary")
        if !phone { XCTAssertTrue(el("lane").exists, "no subject lane (the sample plans tasks this week)") }
        XCTAssertTrue(el("plan-card").exists, "no planned card")
        shot("look-planner-\(mode)")
        let bank = el("bank")
        var tries = 0
        while !(bank.exists && el("bank-card").isHittable) && tries < 10 { app.scrollViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(el("bank-card").exists, "no task in the bank")
        shot("look-planner-bank-\(mode)")
    }

    func testPlannerLight() { run(dark: false) }
    func testPlannerDark() { run(dark: true) }

    /// Drags the iPhone's filter strip sideways along All's row (from the middle of the screen, clear of the back-swipe edge).
    func slideFilters(by dx: CGFloat) {
        let row = el("bank-filter-All").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let mid = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: row.screenPoint.y))
        mid.press(forDuration: 0.05, thenDragTo: mid.withOffset(CGVector(dx: dx, dy: 0)))
        sleep(1)
    }

    /// The bank's filters narrow it, and its button hides it.
    func testBankFiltersAndHides() {
        openPlanner(dark: false)
        let toggle = el("bank-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Task bank button")
        let noDate = el("bank-filter-No date"), all = el("bank-filter-All")
        var tries = 0
        while !(all.exists && all.isHittable) && tries < 10 { app.scrollViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        sleep(2)   // a tap on a scroll view still gliding only stops it
        // the iPhone's filters scroll sideways and No date starts past the edge: bring it fully in before pressing it
        if phone { slideFilters(by: -250) }
        noDate.tap()
        sleep(1)
        if !noDate.isSelected { noDate.tap(); sleep(1) }
        shot("look-planner-bank-no-date")
        XCTAssertTrue(noDate.isSelected, "No date didn't turn on")
        // the sample's personal statement has a deadline; Columbia's short answers have none
        XCTAssertFalse(el("bank").staticTexts["Finalise the personal statement"].exists, "No date kept a task with a deadline")
        XCTAssertTrue(el("bank").staticTexts["Columbia short answers"].waitForExistence(timeout: 5), "No date lost a task without one")
        if phone { slideFilters(by: 250) }
        all.tap()
        sleep(1)
        XCTAssertTrue(all.isSelected, "All didn't turn back on")
        // back to the top, and hide the bank
        tries = 0
        while !toggle.isHittable && tries < 10 { app.scrollViews.firstMatch.swipeDown(velocity: .fast); tries += 1 }
        toggle.tap()
        sleep(1)
        XCTAssertFalse(el("bank").exists, "the bank button didn't hide the bank")
        toggle.tap()
        XCTAssertTrue(el("bank").waitForExistence(timeout: 5), "the bank didn't come back")
    }
}

final class PlannerLookPhoneTests: PlannerLookTests {
    override class var forPhone: Bool { true }
}
