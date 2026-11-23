import XCTest

/// The question bank on the iPhone (Nov 23 2026): the same as BankTests on the iPad, laid out for the phone (the markscheme in a sheet,
/// Mark as question in the board's Insert menu). `-NexusTestBank` gives Chemistry HL's bank as the laptop leaves it. Screenshots
/// ("phone-bank-…") are printed in the ui-check log. Skips on the iPad.
final class BankPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    func tap(_ id: String, _ why: String) {
        var e = el(id)
        if !e.waitForExistence(timeout: 8) { e = app.buttons[id].firstMatch }
        // a list only keeps the rows on screen: a row that is gone may be above (the page is still scrolled down), so look up first, then down
        let list = app.collectionViews.firstMatch
        var tries = 0
        while !e.exists && tries < 4 { list.swipeDown(); tries += 1 }
        tries = 0
        // into the top 70% of the screen, clear of the tab bar and the timer pill (docs/ci-lessons.md, Nov 22)
        while !(e.exists && e.isHittable && e.frame.maxY < app.frame.height * 0.7) && tries < 8 { list.swipeUp(velocity: .slow); tries += 1 }
        XCTAssertTrue(e.waitForExistence(timeout: 5), why)
        e.tap()
    }

    func testQuestionBankOnTheIPhone() {
        app.launchArguments = ["-NexusTestBank"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 20) {
            sample.tap()
            if sample.waitForExistence(timeout: 3) { sample.tap() }
        }
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "no More tab")
        more.tap()
        tap("sidebar-Study", "no Study row")
        sleep(2)
        tap("study-page-chemistry-hl", "no Study page row for Chemistry HL")
        XCTAssertTrue(el("study-theme-R1").waitForExistence(timeout: 10), "no units on the Study page")

        tap("study-bank", "no Question bank on the Study page")
        XCTAssertTrue(el("bank-lede").waitForExistence(timeout: 10), "the question bank didn't open")
        sleep(2)
        shot("phone-bank")
        app.collectionViews.firstMatch.swipeUp(velocity: .slow)
        sleep(1)
        shot("phone-bank-questions")

        tap("bank-paper-continue", "no Go on at for the bookmarked paper")
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 10), "the question's page didn't open")
        XCTAssertTrue(el("bq-clip").waitForExistence(timeout: 15), "no clip of the question from its board")
        sleep(3)
        shot("phone-bank-question")

        tap("bq-hard", "no Hard button")
        sleep(1)
        XCTAssertTrue(el("bq-hard").isSelected, "Hard isn't shown as the mark")
        shot("phone-bank-marked")

        if el("bq-ms").waitForExistence(timeout: 10) {
            tap("bq-ms", "no Markscheme button")
            XCTAssertTrue(el("bq-ms-pane").waitForExistence(timeout: 10), "the markscheme didn't open")
            sleep(3)
            shot("phone-bank-markscheme")
            let done = app.buttons["Close the markscheme"].firstMatch
            if done.exists { done.tap() } else { app.swipeDown(velocity: .fast) }
            sleep(1)
        } else {
            shot("phone-bank-no-markscheme")
            XCTFail("the Acids paper's markscheme wasn't found")
        }

        // the board's Insert menu: Mark as question
        tap("bq-board", "no Write on it")
        let insert = app.buttons["Insert"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 30), "the paper's board didn't open")
        sleep(3)
        insert.tap()
        let mark = app.buttons["Mark as question"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "Insert has no Mark as question")
        mark.tap()
        let box = el("question-box")
        XCTAssertTrue(box.waitForExistence(timeout: 5), "no box to draw round the question")
        sleep(1)
        box.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.30))
            .press(forDuration: 0.3, thenDragTo: box.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.40)))
        let added = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'is in the question bank'")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "no word that the question went into the bank")
        shot("phone-bank-marked-on-board")
        let close = app.navigationBars.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) { close.tap() }
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 15), "closing the board didn't come back to the question")
        sleep(1)
        shot("phone-bank-back-to-question")
    }
}
