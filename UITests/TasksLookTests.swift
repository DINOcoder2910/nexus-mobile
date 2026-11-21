import XCTest
import UIKit

/// The Tasks screen, the task panel and capture as the new laptop app has them (Nov 21 2026), on sample data: the lens tabs and
/// cards, a card's subtasks opened in place, the list view, the panel with its rows and checklist, and capture's preview.
/// The screenshots ("look-tasks-…", "phone-look-tasks-…") are printed in the UI check log; `TasksLookPhoneTests` runs it on the iPhone.
class TasksLookTests: XCTestCase {
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

    func openTasks(dark: Bool) {
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
            let row = app.buttons["Tasks"].firstMatch
            var tries = 0
            while !row.waitForExistence(timeout: 2) && tries < 6 { app.swipeUp(); tries += 1 }
            row.tap()
        } else {
            let row = app.staticTexts["Tasks"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20), "the sidebar isn't up")
            row.tap()
        }
        XCTAssertTrue(el("tasks").waitForExistence(timeout: 15), "the Tasks screen isn't up")
        sleep(2)
    }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        openTasks(dark: dark)
        XCTAssertTrue(el("lens-all").exists, "no All lens")
        XCTAssertTrue(el("tasks-sum").exists, "no summary line")
        XCTAssertTrue(el("task-card").waitForExistence(timeout: 5), "no task card")
        shot("look-tasks-\(mode)")

        // a card's subtasks open in place (the physics sheet's or Northwestern's)
        let bar = el("card-subcount")
        if bar.waitForExistence(timeout: 5) {
            bar.tap()
            sleep(1)
            let one = app.staticTexts["Q1–5"].firstMatch, other = app.staticTexts["Why Northwestern draft"].firstMatch
            XCTAssertTrue(one.waitForExistence(timeout: 5) || other.exists, "the card's subtasks didn't open")
            shot("look-tasks-subtasks-\(mode)")
        } else {
            XCTFail("no subtasks bar on a card")
        }

        // the list
        el("view-list").tap()
        sleep(1)
        XCTAssertTrue(el("task-row").waitForExistence(timeout: 5), "no list rows")
        shot("look-tasks-list-\(mode)")
        app.buttons["Cards"].firstMatch.tap()
        sleep(1)

        // the panel
        let open = app.staticTexts["Columbia short answers"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5), "no Columbia card")
        open.tap()
        XCTAssertTrue(el("panel-title").waitForExistence(timeout: 8), "the task panel didn't open")
        XCTAssertTrue(el("panel-est").exists, "no Estimate row")
        sleep(1)
        shot("look-panel-\(mode)")
        let subs = el("panel-subtasks")
        var tries = 0
        while !(subs.exists && subs.isHittable) && tries < 8 { app.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(subs.exists, "no Subtasks in the panel")
        shot("look-panel-foot-\(mode)")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)

        // capture: the words read as they are typed
        el("new-task").tap()
        let field = el("capture-field")
        XCTAssertTrue(field.waitForExistence(timeout: 8), "capture didn't open")
        field.tap()
        field.typeText("phys lab report by fri 2h; data table; graph")
        sleep(1)
        XCTAssertTrue(el("capture-preview").exists, "no preview")
        XCTAssertTrue(el("capture-chips").exists, "the preview read no fields")
        shot("look-capture-\(mode)")
        app.buttons["Cancel"].firstMatch.tap()
    }

    func testTasksLight() { run(dark: false) }
    func testTasksDark() { run(dark: true) }
}

final class TasksLookPhoneTests: TasksLookTests {
    override class var forPhone: Bool { true }
}
