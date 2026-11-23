import XCTest
import UIKit

/// The laptop's Planner views and workstream edits on the iPad (WorkstreamsAndPlannerPhoneTests: the iPhone), on sample data:
/// 2 days, 3 days, the Month (and on the iPhone a day picked under it), the Show row hiding planned work and one subject; then a new
/// workstream from a subject's ⋯ menu, renamed, a decision added, recoloured, parked and back, moved to another group, and a person's
/// page with its sessions and a new one. Screenshots "plan-…" and "ws-…" ("phone-…" on the iPhone).
///
/// Named to run last: it adds a workstream and a People group to the simulator's sample folder, which the other tests share.
class WorkstreamsAndPlannerTests: XCTestCase {
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
    func count(_ id: String) -> Int { app.descendants(matching: .any).matching(identifier: id).count }
    /// An element with that id whose words include `text` (a row read as one: "Today, Meet on Fridays…").
    func row(_ id: String, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", id, text)).firstMatch
    }

    func launch(_ args: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 8) { sample.tap() }
        let ask = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
    }

    // MARK: the Planner

    func openPlanner() {
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
    }

    /// The span switch's button (inside the Planner, so the Calendar's "Month" can't answer).
    func span(_ title: String) {
        let b = el("plan-span").buttons[title].firstMatch
        var tries = 0
        while !(b.exists && b.isHittable) && tries < 6 { app.scrollViews.firstMatch.swipeDown(velocity: .fast); tries += 1 }
        XCTAssertTrue(b.waitForExistence(timeout: 5), "no \(title) in the span switch")
        b.tap()
        sleep(1)
    }

    func toTop() {
        var tries = 0
        while !(el("plan-show").exists && el("plan-show").isHittable) && tries < 8 { app.scrollViews.firstMatch.swipeDown(velocity: .fast); tries += 1 }
    }

    func testPlannerSpansMonthAndShow() {
        launch()
        openPlanner()
        // a run before may have left the Planner on another span or with something hidden
        if el("show-all").exists { el("show-all").tap(); sleep(1) }
        span("2 days")
        XCTAssertEqual(count("day-head"), 2, "2 days isn't two days")
        XCTAssertTrue(el("week-sum").label.contains("in these 2 days"), "the sum doesn't say 2 days: \(el("week-sum").label)")
        shot("plan-2days")
        span("3 days")
        XCTAssertEqual(count("day-head"), 3, "3 days isn't three days")
        shot("plan-3days")
        span("Month")
        XCTAssertTrue(el("month").waitForExistence(timeout: 5), "no Month grid")
        XCTAssertEqual(count("month-day"), 35, "the Month isn't five weeks")
        shot("plan-month")
        if phone {
            // a day of the grid shows its cards under it
            let first = app.descendants(matching: .any).matching(identifier: "month-day").element(boundBy: 0)
            first.tap()
            XCTAssertTrue(el("month-picked").waitForExistence(timeout: 5), "tapping a day didn't show its cards")
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            sleep(1)
            shot("plan-month-day")
            toTop()
        }
        // the Month steps a week
        let before = el("week-range").label
        el("week-next").tap()
        sleep(1)
        XCTAssertNotEqual(el("week-range").label, before, "› didn't move the Month")
        app.buttons["Today"].firstMatch.tap()
        sleep(1)

        span("Week")
        XCTAssertEqual(count("day-head"), 7, "Week isn't seven days")
        let cards = count("plan-card")
        XCTAssertGreaterThan(cards, 0, "the sample plans nothing this week")
        // Show: Planned off hides every planned card, Show everything brings them back
        toTop()
        el("show-plan").tap()
        sleep(1)
        XCTAssertEqual(count("plan-card"), 0, "Planned off left planned cards")
        XCTAssertEqual(el("show-plan").value as? String, "hidden")
        shot("plan-show-hidden")
        XCTAssertTrue(el("show-all").exists, "no Show everything while something is hidden")
        el("show-all").tap()
        sleep(1)
        XCTAssertEqual(count("plan-card"), cards, "Show everything didn't bring the cards back")
        // one subject off hides only its cards
        let pills = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'show-ws-'"))
        XCTAssertGreaterThan(pills.count, 0, "no subject pills")
        let pill = pills.element(boundBy: 0)
        if !pill.isHittable { el("plan-show").swipeLeft() }
        pill.tap()
        sleep(1)
        XCTAssertLessThan(count("plan-card"), cards, "hiding a subject hid none of its cards")
        shot("plan-show-subject")
        el("show-all").tap()
        sleep(1)
        XCTAssertEqual(count("plan-card"), cards)
    }

    // MARK: workstreams

    /// A subject's page: the iPad's sidebar row, the iPhone's Subjects tab.
    func openSubject(_ name: String, id: String) {
        if phone {
            let tab = app.tabBars.buttons["Subjects"].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Subjects tab")
            tab.tap()
            // back to the list if a subject is open
            var backs = 0
            while !el("subject-" + id).exists && app.navigationBars.buttons["BackButton"].exists && backs < 4 {
                app.navigationBars.buttons["BackButton"].tap(); backs += 1; sleep(1)
            }
            let row = el("subject-" + id)
            var tries = 0
            while !(row.exists && row.isHittable) && tries < 8 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
            XCTAssertTrue(row.exists, "no \(name) in Subjects")
            row.tap()
        } else {
            if el("subject-back").exists { el("subject-back").tap(); sleep(1) }
            let row = app.collectionViews.firstMatch.staticTexts[name].firstMatch
            var tries = 0
            while !(row.exists && row.isHittable) && tries < 10 { app.collectionViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
            XCTAssertTrue(row.waitForExistence(timeout: 10), "no \(name) in the sidebar")
            row.tap()
        }
        XCTAssertTrue(el("ws-menu").waitForExistence(timeout: 15), "\(name)'s page didn't open")
        sleep(1)
    }

    /// The ⋯ menu's item (and its submenu's).
    func menu(_ items: String...) {
        el("ws-menu").tap()
        for i in items {
            let b = app.buttons[i].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 5), "no \(i) in the menu")
            b.tap()
        }
        sleep(1)
    }

    /// Types into the open prompt (after clearing it) and presses `button`.
    func answer(_ text: String, _ button: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "no prompt")
        let field = alert.textFields.firstMatch
        field.tap()
        let old = (field.value as? String) ?? ""
        if !old.isEmpty && old != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2)) }
        field.typeText(text)
        alert.buttons[button].tap()
        sleep(2)
    }

    func testWorkstreamEdits() {
        launch(["-NexusTestPerson"])
        openSubject("Nexus", id: "nexus")
        // the menu as it opens
        el("ws-menu").tap()
        XCTAssertTrue(app.buttons["Rename…"].firstMatch.waitForExistence(timeout: 5), "the ⋯ menu has no Rename")
        shot("ws-menu")
        let make = app.buttons["New workstream in Projects…"].firstMatch
        XCTAssertTrue(make.exists, "no New workstream in the menu")
        make.tap()
        answer("Essay club", "Create")
        // its page opens
        XCTAssertTrue(app.navigationBars.staticTexts["Essay club"].firstMatch.waitForExistence(timeout: 10), "the new workstream's page didn't open")
        sleep(1)
        menu("Rename…")
        answer("Essay society", "Rename")
        XCTAssertTrue(app.staticTexts["Essay society"].firstMatch.waitForExistence(timeout: 8), "the rename didn't show")

        // a decision, under Decisions on its page
        let add = el("add-decision")
        var tries = 0
        while !(add.exists && add.isHittable) && tries < 6 { app.scrollViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(add.exists, "no Add a decision")
        add.tap()
        answer("Meet on Fridays, not Mondays: the room is free", "Add")
        XCTAssertTrue(row("decision", "Meet on Fridays, not Mondays").waitForExistence(timeout: 8), "the decision isn't on the page")
        shot("ws-decision")
        app.scrollViews.firstMatch.swipeDown(velocity: .fast)

        menu("Colour", "Teal")
        menu("Park")
        XCTAssertTrue(app.staticTexts["Parked"].firstMatch.waitForExistence(timeout: 8), "Park didn't show Parked")
        shot("ws-parked")
        menu("Un-park")
        XCTAssertFalse(app.staticTexts["Parked"].firstMatch.waitForExistence(timeout: 3), "Un-park left it parked")
        menu("Move to group", "Classes")
        XCTAssertTrue(app.staticTexts["Moved Essay society to Classes"].firstMatch.waitForExistence(timeout: 8), "no word of the move")
        shot("ws-moved")

        // a person: their sessions, and a new one with its note open to write in
        openSubject("Ms Lee", id: "ms-lee")
        let sessions = el("ws-sessions")
        tries = 0
        while !(sessions.exists && el("new-session").isHittable) && tries < 6 { app.scrollViews.firstMatch.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(row("session", "College list").exists, "the sample session isn't listed")
        XCTAssertTrue(row("decision", "Apply ED to Columbia").exists, "her decision isn't listed")
        shot("ws-person")
        el("new-session").tap()
        answer("Essays", "Create")
        XCTAssertTrue(app.navigationBars.staticTexts.matching(NSPredicate(format: "label ENDSWITH 'Essays'")).firstMatch.waitForExistence(timeout: 8), "the new session's note didn't open")
        shot("ws-session-note")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(row("session", "Essays").waitForExistence(timeout: 8), "the new session isn't listed")
    }
}

final class WorkstreamsAndPlannerPhoneTests: WorkstreamsAndPlannerTests {
    override class var forPhone: Bool { true }
}
