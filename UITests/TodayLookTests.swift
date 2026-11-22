import XCTest
import UIKit

/// Today as the new laptop app has it (Nov 21 2026), on sample data: Key dates and From Study, Next up, the list beside the day's hours,
/// Slipped and Tomorrow; Today on Slipped plans a slipped task today again, and Accept gives a suggested time. The screenshots
/// ("look-today-…", "phone-look-today-…") are printed in the UI check log; `TodayLookPhoneTests` runs it on the iPhone.
class TodayLookTests: XCTestCase {
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

    func launch(dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = dark ? ["-NexusTestDark"] : []
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 8) { sample.tap() }
        if phone {
            let tab = app.tabBars.buttons["Today"].firstMatch
            if tab.waitForExistence(timeout: 5) { tab.tap() }
        }
        XCTAssertTrue(el("today-list").waitForExistence(timeout: 20), "Today isn't up")
        // the system's notifications question (the reminders ask on a first launch) would cover the screenshots
        let ask = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
        sleep(2)
    }

    /// Swipes Today up until `e` is on screen.
    func reach(_ e: XCUIElement, _ what: String) {
        var tries = 0
        while !(e.exists && e.isHittable) && tries < 8 { app.scrollViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(e.exists, "can't reach " + what)
    }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        launch(dark: dark)
        XCTAssertTrue(el("today-sum").exists, "no summary line")
        XCTAssertTrue(el("key-date").exists, "no Key dates card (the sample has a starred deadline)")
        shot("look-today-\(mode)")
        let day = el("day-card")
        reach(day, "the day's hours")
        shot("look-today-day-\(mode)")
        // the day's hours run to the end of the app's day (4 am), even with nothing planned that late (Nov 22)
        let end = day.staticTexts.matching(NSPredicate(format: "label == %@", "4 am")).firstMatch
        reach(end, "4 am at the foot of the day's hours")
        let slipped = el("slipped")
        reach(slipped, "Slipped")
        reach(el("tomorrow"), "Tomorrow")
        shot("look-today-bottom-\(mode)")
    }

    func testTodayLight() { run(dark: false) }
    func testTodayDark() { run(dark: true) }

    /// Slipped's Today puts the sample's slipped task ("Read 4.2 on waves", planned two days ago) back on today's list.
    func testSlippedBackToToday() throws {
        launch(dark: false)
        let slipped = el("slipped")
        reach(slipped, "Slipped")
        let today = slipped.buttons["to-today"].firstMatch
        // another test on this simulator (they share the sample folder) can already have planned it again
        if !today.waitForExistence(timeout: 5) && slipped.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Nothing slipped")).firstMatch.exists {
            shot("look-today-slipped-none")
            throw XCTSkip("Slipped is empty here: an earlier test already moved the sample's slipped task")
        }
        XCTAssertTrue(today.exists, "no Today button on Slipped")
        let before = app.otherElements["today-list"].firstMatch.descendants(matching: .staticText).count
        today.tap()
        sleep(2)
        let after = app.otherElements["today-list"].firstMatch.descendants(matching: .staticText).count
        XCTAssertGreaterThan(after, before, "the slipped task didn't join today's list")
        shot("look-today-slipped-moved")
    }
}

final class TodayLookPhoneTests: TodayLookTests {
    override class var forPhone: Bool { true }
}
