import XCTest
import UIKit

/// Today's two edges (Nov 22 2026, from Murtaza's iPad screenshot): a task tonight that runs past 10 pm stays inside the day's hours
/// (the hours run to the app's end of day, 4 am, instead of the block hanging over Tomorrow), and Tomorrow's strip labels never overlap (measured in the
/// strip's real width; one that fits neither row is left out, one with room always shows). Sample data plus -NexusTestDayEdges (TestHooks.dayEdges):
/// "Physics IA lock in" at 21:30 for 3h today, five tasks crowded into tomorrow morning and "Evening run" at 7 pm. The "edges-…" screenshots are
/// printed in the UI check log.
class TodayEdgesTests: XCTestCase {
    var app = XCUIApplication()
    var phone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    override func setUpWithError() throws {
        try XCTSkipIf(phone, "iPad only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// A text by its words (an id on a block goes to its texts, so a plain subscript can miss it).
    func text(_ scope: XCUIElement, _ words: String) -> XCUIElement {
        scope.staticTexts.matching(NSPredicate(format: "label == %@", words)).firstMatch
    }

    /// Swipes Today up until `e` is on screen.
    func reach(_ e: XCUIElement, _ what: String) {
        var swipes = 0
        while !(e.exists && e.isHittable) && swipes < 8 { app.scrollViews.firstMatch.swipeUp(velocity: .slow); swipes += 1 }
        XCTAssertTrue(e.exists, "can't reach " + what)
    }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        app = XCUIApplication()
        app.launchArguments = ["-NexusTestDayEdges"] + (dark ? ["-NexusTestDark"] : [])
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 8) { sample.tap() }
        XCTAssertTrue(el("today-list").waitForExistence(timeout: 20), "Today isn't up")
        let ask = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
        sleep(2)

        let day = el("day-card")
        reach(day, "the day's hours")
        let late = text(day, "Physics IA lock in")
        reach(late, "tonight's late task")
        let midnight = text(day, "12 am")
        XCTAssertTrue(midnight.waitForExistence(timeout: 5), "the day's hours don't reach midnight for a task that runs past 10 pm")
        let ten = text(day, "10 pm")
        if ten.exists && midnight.exists {
            XCTAssertGreaterThan(midnight.frame.minY, ten.frame.minY, "12 am isn't below 10 pm")
            XCTAssertLessThanOrEqual(midnight.frame.maxY, day.frame.maxY + 1, "12 am sits outside the day card")
        }
        shot("edges-day-\(mode)")

        let tomorrow = el("tomorrow")
        reach(tomorrow, "Tomorrow")
        sleep(1)
        let labels = tomorrow.staticTexts.matching(identifier: "tomorrow-label").allElementsBoundByIndex.map { ($0.label, $0.frame) }
        let said = labels.map { $0.0 }.joined(separator: ", ")
        // The strip runs 8 am to the 4 am end of the day (20 hours in about 370 points on a landscape iPad), so the five morning tasks
        // (8:30 to 1 pm) start within about 90 points: two of their labels fit, one on each row, and the rest are left out. The evening
        // task has room, so its label always shows. (Before Nov 22 the strip ended at 10 pm and the morning fit four labels.)
        XCTAssertTrue(labels.contains { $0.0 == "Chemistry practice" }, "the first morning task has no label in Tomorrow's strip (shown: \(said))")
        XCTAssertTrue(labels.contains { $0.0 == "Evening run" }, "the evening task, alone with room, has no label in Tomorrow's strip (shown: \(said))")
        XCTAssertGreaterThanOrEqual(labels.count, 3, "Tomorrow's strip shows \(labels.count) labels (\(said)): the crowded morning should fill both rows, plus the evening's")
        XCTAssertGreaterThanOrEqual(Set(labels.map { Int($0.1.minY.rounded()) }).count, 2, "Tomorrow's crowded labels don't use the strip's second row (shown: \(said))")
        for l in labels {
            XCTAssertTrue(l.1.minX >= tomorrow.frame.minX - 1 && l.1.maxX <= tomorrow.frame.maxX + 1, "Tomorrow's label \"\(l.0)\" runs outside the card")
        }
        for i in labels.indices {
            for j in labels.indices where j > i {
                let overlap = labels[i].1.insetBy(dx: 1, dy: 1).intersects(labels[j].1.insetBy(dx: 1, dy: 1))
                XCTAssertFalse(overlap, "Tomorrow's labels \"\(labels[i].0)\" and \"\(labels[j].0)\" overlap")
            }
        }
        shot("edges-tomorrow-\(mode)")
    }

    func testDayEdgesLight() { run(dark: false) }
    func testDayEdgesDark() { run(dark: true) }
}
