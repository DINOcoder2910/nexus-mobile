import XCTest
import UIKit

/// The pieces added after the new look (Nov 21 2026), on sample data with the Spanish demo: From Study's Oral practice card, the task
/// panel's checklist (under the one above, bring out, move up and down, a typed line read as capture reads it, delete), and a task's
/// PDF opened to write on. Screenshots "look-checklist-…", "look-write-on-…", "look-today-oral-…" ("phone-" on the iPhone, where
/// `ChecklistLookPhoneTests` runs it).
class ChecklistLookTests: XCTestCase {
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
    func all(_ id: String) -> XCUIElementQuery { app.descendants(matching: .any).matching(identifier: id) }

    func launch(dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-NexusSpanishDemo"] + (dark ? ["-NexusTestDark"] : [])
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 8) { sample.tap() }
        let ask = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
        XCTAssertTrue(el("today-sum").waitForExistence(timeout: 20), "Today isn't up")
        sleep(2)
    }

    func openTasks() {
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
        sleep(1)
    }

    /// The panel's ⋯ for the n-th subtask line, then one of its choices.
    func menu(_ n: Int, _ choice: String) {
        let m = all("check-menu").element(boundBy: n)
        XCTAssertTrue(m.waitForExistence(timeout: 5), "no ⋯ on subtask \(n)")
        m.tap()
        let b = app.buttons[choice].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 5), "no \(choice) in the subtask's menu")
        b.tap()
        sleep(1)
    }

    func line(_ n: Int) -> String { (all("check-line").element(boundBy: n).value as? String) ?? "" }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        launch(dark: dark)

        // From Study: the Spanish demo's oral three days ago
        let oral = el("study-oral")
        var tries = 0
        while !(oral.exists && oral.isHittable) && tries < 4 { app.scrollViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(oral.exists, "no Oral practice in From Study")
        XCTAssertTrue(oral.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "3 days ago")).firstMatch.exists, "the oral card doesn't say when the last one was")
        shot("look-today-oral-\(mode)")

        // the physics sheet's panel: its PDF, and its checklist
        openTasks()
        let card = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Physics HW sheet")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no Physics HW sheet card")
        card.tap()
        XCTAssertTrue(el("panel-title").waitForExistence(timeout: 8), "the panel didn't open")
        XCTAssertTrue(el("panel-write-on").waitForExistence(timeout: 5), "no Write on it for the sheet the task points at")
        XCTAssertTrue(el("task-file").exists, "no file chip")
        let subs = el("panel-subtasks")
        tries = 0
        while !(subs.exists && all("check-menu").element(boundBy: 1).isHittable) && tries < 8 { app.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertEqual(all("check-line").count, 2, "the checklist doesn't hold the two subtasks")
        XCTAssertEqual(line(0), "Q1–5"); XCTAssertEqual(line(1), "Q6–10")
        shot("look-checklist-\(mode)")

        // under the one above, then out again
        menu(1, "Under the one above")
        menu(1, "Bring out")       // its menu offers Bring out only when it is nested
        XCTAssertEqual(line(1), "Q6–10", "Q6–10 didn't come back out")
        // up, then down again
        menu(1, "Move up")
        XCTAssertEqual(line(0), "Q6–10", "Move up didn't move it")
        menu(0, "Move down")
        XCTAssertEqual(line(0), "Q1–5", "Move down didn't move it back")

        // a typed line, read as capture reads it
        let add = el("subtask-add")
        tries = 0
        while !(add.exists && add.isHittable) && tries < 6 { app.swipeUp(velocity: .slow); tries += 1 }
        add.tap()
        add.typeText("Q11–15 by fri 30m")
        sleep(1)
        shot("look-checklist-typing-\(mode)")
        add.typeText("\n")
        XCTAssertTrue(all("check-line").element(boundBy: 2).waitForExistence(timeout: 5), "the typed subtask wasn't added")
        XCTAssertEqual(line(2), "Q11–15", "the line's date and estimate stayed in its title")
        // Return on the empty add line puts the keyboard away
        add.typeText("\n")
        sleep(1)
        // nest it, to show the indent, then take it away again
        menu(2, "Under the one above")
        shot("look-checklist-nested-\(mode)")
        menu(2, "Delete")
        XCTAssertEqual(all("check-line").count, 2, "Delete didn't take the subtask out")

        // Write on it: the sheet's board beside the PDF
        let write = el("panel-write-on")
        tries = 0
        while !(write.exists && write.isHittable) && tries < 8 { app.swipeDown(velocity: .slow); tries += 1 }
        write.tap()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the sheet's board didn't open")
        sleep(4)
        shot("look-write-on-\(mode)")
    }

    func testChecklistLight() { run(dark: false) }
    func testChecklistDark() { run(dark: true) }
}

final class ChecklistLookPhoneTests: ChecklistLookTests {
    override class var forPhone: Bool { true }
}
