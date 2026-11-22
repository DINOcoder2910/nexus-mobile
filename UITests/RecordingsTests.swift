import XCTest
import UIKit

/// Recordings on the iPad (this class) and the iPhone (RecordingsPhoneTests), on sample data with a class and a meeting already
/// recorded and prepared (-NexusTestRecordings, Sources/Recordings/RecordingDemo.swift: no microphone, speech model or Claude):
/// the list, a class to review with its teaching notes, accepting a meeting (its tasks land in the subject), recording from the
/// list with the pill on other screens, and the quick page the Action button opens. "rec-…" / "phone-rec-…" screenshots are printed
/// in ui-check's log.
class RecordingsTests: XCTestCase {
    let app = XCUIApplication()
    var phone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    class var forPhone: Bool { false }

    override func setUpWithError() throws {
        try XCTSkipIf(phone != Self.forPhone, Self.forPhone ? "iPhone only" : "iPad only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = phone ? .portrait : .landscapeLeft
    }

    func launch(_ extra: [String] = []) {
        app.launchArguments = ["-NexusTestRecordings"] + extra
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 5) { sample.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let ask = springboard.alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
    }

    func shot(_ base: String) {
        let name = phone ? "phone-" + base : base
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func openRecordings() {
        if phone { app.tabBars.buttons["More"].tap() }
        let list = app.collectionViews.firstMatch
        let row = app.buttons["Recordings"].firstMatch
        var tries = 0
        while !(row.exists && row.isHittable) && tries < 8 { list.swipeUp(); tries += 1 }
        XCTAssertTrue(row.exists, "no Recordings row")
        row.tap()
        XCTAssertTrue(app.buttons["rec-start-meeting"].firstMatch.waitForExistence(timeout: 15), "the Recordings screen didn't open")
    }

    /// Scrolls the screen's list until `e` shows (bounded, both ways).
    func reveal(_ e: XCUIElement, _ n: Int = 8) {
        var tries = 0
        while !(e.exists && e.isHittable) && tries < n { app.swipeUp(velocity: .slow); tries += 1 }
        tries = 0
        while !(e.exists && e.isHittable) && tries < n { app.swipeDown(velocity: .slow); tries += 1 }
    }

    func testRecordings() {
        launch()
        openRecordings()
        let lesson = app.buttons["rec-row-Redox: writing half-equations"].firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 15), "the seeded class isn't listed")
        XCTAssertTrue(app.buttons["rec-row-Counsellor letter with Ms Rivera"].firstMatch.exists, "the seeded meeting isn't listed")
        sleep(1)
        shot("rec-1-list")

        // the class: what Claude prepared, the teaching notes, the pictures and the transcript
        lesson.tap()
        XCTAssertTrue(app.buttons["rec-accept"].firstMatch.waitForExistence(timeout: 15) || app.staticTexts["Summary"].firstMatch.waitForExistence(timeout: 5),
                      "the class's review didn't open")
        sleep(1)
        shot("rec-2-class-review")
        let how = app.staticTexts["How it was taught"].firstMatch
        reveal(how)
        XCTAssertTrue(how.exists, "no teaching notes")
        shot("rec-3-class-teaching")
        // the pinned moments: what Claude said about each, a Lost me explained
        let lost = app.buttons["rec-moment-lost"].firstMatch
        reveal(lost, 12)
        XCTAssertTrue(lost.exists, "no Lost me moment")
        shot("rec-3b-moments")
        let words = app.staticTexts["Transcript"].firstMatch
        reveal(words, 12)
        shot("rec-4-class-transcript")
        back()

        // the meeting: accept it; its tasks go into Applications overview
        let meeting = app.buttons["rec-row-Counsellor letter with Ms Rivera"].firstMatch
        XCTAssertTrue(meeting.waitForExistence(timeout: 10))
        meeting.tap()
        // Accept is at the foot of the review: a list only makes the rows on screen, so scroll to it first
        let accept = app.buttons["rec-accept"].firstMatch
        XCTAssertTrue(app.staticTexts["Summary"].firstMatch.waitForExistence(timeout: 15) || accept.waitForExistence(timeout: 5), "the meeting's review didn't open")
        sleep(1)
        shot("rec-5-meeting-review")
        reveal(accept, 12)
        XCTAssertTrue(accept.exists, "no Accept on the meeting")
        accept.tap()
        // the filed page replaces the review, and the list may still be scrolled to where Accept was: find its sections
        let filed = app.staticTexts["Tasks added"].firstMatch
        _ = app.staticTexts["Summary"].firstMatch.waitForExistence(timeout: 15)
        sleep(1)
        reveal(filed, 10)
        XCTAssertTrue(filed.exists, "accepting didn't file the tasks")
        let added = app.staticTexts["Send Ms Rivera the activities list"].firstMatch
        reveal(added, 6)
        XCTAssertTrue(added.exists, "the added task isn't shown")
        sleep(1)
        shot("rec-6-meeting-filed")
        back()

        // recording: the bar shows, Stop makes a new recording that Claude prepares
        let start = app.buttons["rec-start-meeting"].firstMatch
        reveal(start)
        start.tap()
        XCTAssertTrue(app.buttons["rec-stop"].firstMatch.waitForExistence(timeout: 10), "recording didn't start")
        sleep(1)
        shot("rec-7-recording")
        // on another screen the pill shows the recording, with its own Stop
        if phone { app.tabBars.buttons["Today"].tap() } else { app.buttons["Today"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["rec-pill-stop"].firstMatch.waitForExistence(timeout: 10), "no recording pill on Today")
        sleep(1)
        shot("rec-7b-pill")
        if phone { app.tabBars.buttons["More"].tap() } else { app.buttons["Recordings"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["rec-stop"].firstMatch.waitForExistence(timeout: 10), "back on Recordings, no Stop")
        app.buttons["rec-stop"].firstMatch.tap()
        XCTAssertTrue(app.buttons["rec-start-meeting"].firstMatch.waitForExistence(timeout: 10), "recording didn't stop")
        let ready = app.staticTexts["Ready to review"].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 20), "the new recording isn't ready to review")
        shot("rec-8-after-stop")
    }

    /// Recording a class: what the teacher says pins itself, with a pop-up (Undo, Snap); the live buttons pin the moment.
    func testClassMoments() {
        launch()
        openRecordings()
        let start = app.buttons["rec-start-class"].firstMatch
        reveal(start)
        start.tap()
        XCTAssertTrue(app.buttons["rec-stop"].firstMatch.waitForExistence(timeout: 10), "the class didn't start recording")
        XCTAssertTrue(app.otherElements["rec-popup"].firstMatch.waitForExistence(timeout: 15) || app.buttons["rec-popup-undo"].firstMatch.waitForExistence(timeout: 3),
                      "no pop-up for “this comes up every year”")
        shot("rec-11-live-popup")
        let lost = app.buttons["rec-pin-lost"].firstMatch
        XCTAssertTrue(lost.exists, "no Lost me button")
        lost.tap()
        let count = app.staticTexts["rec-pin-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 5), "no count of pinned moments")
        XCTAssertTrue(count.label.hasPrefix("2 moments pinned"), "pins: \(count.label)")
        sleep(7) // the pop-up goes by itself
        shot("rec-12-live-buttons")
        app.buttons["rec-stop"].firstMatch.tap()
        XCTAssertTrue(app.buttons["rec-start-class"].firstMatch.waitForExistence(timeout: 10), "recording didn't stop")
    }

    func testQuickPage() {
        launch(["-NexusTestQuick"])
        XCTAssertTrue(app.buttons["quick-done"].firstMatch.waitForExistence(timeout: 20), "the quick page didn't open")
        XCTAssertTrue(app.buttons["rec-start-meeting"].firstMatch.exists, "no Record on the quick page")
        XCTAssertTrue(app.otherElements["quick-stat-done"].firstMatch.exists || app.staticTexts["Done today"].firstMatch.exists, "no numbers on the quick page")
        sleep(1)
        shot("rec-9-quick")
        app.swipeUp(velocity: .slow)
        sleep(1)
        shot("rec-10-quick-lower")
        app.swipeDown(velocity: .slow)
        app.buttons["quick-done"].firstMatch.tap()
    }

    func back() {
        let named = app.navigationBars.buttons["Recordings"].firstMatch
        if named.exists { named.tap() } else {
            let b = app.navigationBars.buttons.element(boundBy: 0)
            if b.exists { b.tap() }
        }
        sleep(1)
    }
}

final class RecordingsPhoneTests: RecordingsTests {
    override class var forPhone: Bool { true }
}
