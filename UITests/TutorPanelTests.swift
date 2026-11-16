import XCTest

/// The tutor's chat panel on a board (Nov 13 redesign), going through real turns with the demo tutor (-NexusTutorDemo: canned replies
/// and a steady pace instead of Claude and the voice). The screenshots named "tutor-…" are printed into the ui-check log, so a cloud
/// thread can see the panel as it is before asking for a ship.
final class TutorPanelTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func launch(_ extra: [String] = []) {
        app.launchArguments = ["-NexusTutorDemo"] + extra
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// A new notebook with a blank board, open.
    func openBoard(_ notebook: String) {
        let make = app.buttons["New notebook…"]
        var tries = 0
        while !make.isHittable && tries < 6 { app.collectionViews.firstMatch.swipeUp(); tries += 1 }
        XCTAssertTrue(make.waitForExistence(timeout: 10), "no New notebook… row")
        make.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText(notebook)
        alert.buttons["Make"].tap()
        let row = app.staticTexts[notebook].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the new notebook isn't in the sidebar")
        row.tap()
        let new = app.buttons["New"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()
        app.buttons["Blank board"].firstMatch.tap()
        let name = app.alerts.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.textFields.firstMatch.typeText("Algebra")
        name.buttons["Make"].tap()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 15), "the board didn't open")
    }

    func openTutor() {
        let button = app.buttons["Tutor: hold to ask, tap to type"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no tutor button on the board's bar")
        button.tap()
    }

    /// Waits until it has started answering (the talking bar is up) and then finished (the bar is gone again).
    func waitForAnswer(_ what: String) {
        let pause = app.buttons["Pause"].firstMatch
        _ = pause.waitForExistence(timeout: 20) // (already gone if it answered quickly)
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pause)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 90), .completed, "it didn't finish answering: " + what)
        sleep(1)
    }

    func testTutorChat() {
        launch()
        openBoard("Tutor test")
        openTutor()
        let explain = app.buttons["Explain what's on my board"].firstMatch
        XCTAssertTrue(explain.waitForExistence(timeout: 10), "the panel's welcome isn't there")
        sleep(1)
        shot("tutor-1-welcome")

        explain.tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 20), "no talking bar while it answers")
        sleep(7)
        shot("tutor-2-talking")
        waitForAnswer("explain")

        app.buttons["Try one"].firstMatch.tap()
        waitForAnswer("practice")
        let check = app.buttons["Check my work"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 10), "no your-turn card after a practice problem")
        shot("tutor-3-your-turn")

        app.buttons["Minimise the tutor"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Open the tutor"].firstMatch.waitForExistence(timeout: 10), "the pill isn't there")
        sleep(1)
        shot("tutor-4-pill")
        app.buttons["Open the tutor"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Minimise the tutor"].firstMatch.waitForExistence(timeout: 10), "the pill doesn't open the panel again")
    }

    /// The ask box keeps what you typed across a pause (Nov 16: typing, stopping a few seconds and typing on lost the first part),
    /// both while the tutor is quiet and while it talks (the panel redraws with every sentence then).
    func testTypingSurvivesAPause() {
        launch()
        openBoard("Tutor typing")
        openTutor()
        let box = app.descendants(matching: .any)["tutor-ask"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 10), "no ask box")

        box.tap()
        box.typeText("What is a mole")
        sleep(6)
        box.typeText(" and how do I use it")
        sleep(1)
        XCTAssertEqual(box.value as? String, "What is a mole and how do I use it", "the first part was lost after a pause (quiet)")
        shot("tutor-6-typed")

        // clear it, then the same while it talks
        app.buttons["Ask"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Pause"].firstMatch.waitForExistence(timeout: 20), "no talking bar while it answers")
        box.tap()
        box.typeText("Wait, why")
        sleep(6)
        box.typeText(" is it divided by two")
        sleep(1)
        XCTAssertEqual(box.value as? String, "Wait, why is it divided by two", "the first part was lost after a pause (talking)")
        shot("tutor-7-typed-while-talking")
        waitForAnswer("typed question")
        XCTAssertEqual(box.value as? String, "Wait, why is it divided by two", "the box lost its words when the answer ended")
    }

    /// Talking with a pause in it keeps the whole question (Nov 16). The demo's listening plays the recogniser's results for "What is a
    /// mole", a pause, then its text starting over with "And how do I use it?", as Apple's does.
    func testTalkingSurvivesAPause() {
        launch()
        openBoard("Tutor talking")
        openTutor()
        let mic = app.buttons["Talk to the tutor"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "no microphone in the panel")
        mic.tap() // (a tap: it listens until tapped again)
        let said = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'use it'")).firstMatch
        let found = said.waitForExistence(timeout: 15)
        sleep(1)
        shot("tutor-8-listening")
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
        print("UISTEP texts: " + labels.joined(separator: " | "))
        XCTAssertTrue(found, "the words after the pause never showed")
        XCTAssertTrue(app.staticTexts["What is a mole And how do I use it?"].firstMatch.exists, "what was said before the pause is gone")
        app.buttons["Send what you said"].firstMatch.tap()
        waitForAnswer("asked out loud")
        XCTAssertTrue(app.staticTexts["What is a mole And how do I use it?"].firstMatch.exists, "the asked question isn't the whole of it")
        shot("tutor-9-asked")
    }

    func testTutorChatDark() {
        launch(["-board.dark", "always"])
        openBoard("Tutor dark")
        openTutor()
        let explain = app.buttons["Explain what's on my board"].firstMatch
        XCTAssertTrue(explain.waitForExistence(timeout: 10))
        explain.tap()
        waitForAnswer("explain")
        app.buttons["Try one"].firstMatch.tap()
        waitForAnswer("practice")
        app.buttons["Hint"].firstMatch.tap()
        waitForAnswer("hint")
        sleep(1)
        shot("tutor-5-dark")
    }
}
