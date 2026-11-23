import XCTest

/// The question bank on the iPad (Nov 23 2026), as on the laptop: Study's Question bank (the papers, Working on, the questions with their
/// filters), a question's page (the question cut from its board, marks 1 2 3, the markscheme beside it), and Insert › Mark as question
/// on the paper's board. `-NexusTestBank` gives Chemistry HL's bank as the laptop leaves it (TestHooks.questionBank). The screenshots
/// ("pad-bank-…") are printed in the ui-check log. Skips itself on the iPhone; BankPhoneTests is its twin.
final class BankTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }

    /// Taps what has this identifier (or label), scrolling the list it is in until it can be tapped.
    func tap(_ id: String, _ why: String, in list: XCUIElement? = nil) {
        var e = el(id)
        if !e.waitForExistence(timeout: 8) { e = app.buttons[id].firstMatch }
        // a list only keeps the rows on screen: a row that is gone may be above (the page is still scrolled down), so look up first, then down
        let l = list ?? app.collectionViews.firstMatch
        var tries = 0
        while !e.exists && tries < 4 { l.swipeDown(); tries += 1 }
        tries = 0
        while !(e.exists && e.isHittable) && tries < 8 { l.swipeUp(); tries += 1 }
        XCTAssertTrue(e.waitForExistence(timeout: 5), why)
        e.tap()
    }

    func launch() {
        app.launchArguments = ["-NexusTestBank"]
        app.launch()
        // a cold simulator can drop the first tap (docs/ci-lessons.md, Nov 22)
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 20) {
            sample.tap()
            if sample.waitForExistence(timeout: 3) { sample.tap() }
        }
    }

    func testQuestionBankOnTheIPad() {
        launch()
        tap("sidebar-Study", "no Study row")
        sleep(2)
        tap("study-page-chemistry-hl", "no Study page row for Chemistry HL", in: app.collectionViews.element(boundBy: 1))
        XCTAssertTrue(el("study-theme-R1").waitForExistence(timeout: 10), "no units on the Study page")

        // Study's page: the bank in a few lines, the paper pinned as Working on
        tap("study-bank", "no Question bank on the Study page", in: app.collectionViews.firstMatch)
        XCTAssertTrue(el("bank-lede").waitForExistence(timeout: 10), "the question bank didn't open")
        sleep(2)
        shot("pad-bank")
        XCTAssertTrue(el("bank-working-card").exists, "the pinned Acids paper isn't under Working on")

        // a filter: only what is marked Review later
        tap("bank-filter-marked", "no Marked filter")
        let review = app.buttons["Review later"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5), "the Marked filter has no Review later")
        review.tap()
        sleep(1)
        shot("pad-bank-filter-review")
        let clear = app.buttons["Clear"].firstMatch
        if clear.exists { clear.tap(); sleep(1) }

        // Go on at Q2: the question cut from its board, with the handwriting under it
        tap("bank-paper-continue", "no Go on at for the bookmarked paper")
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 10), "the question's page didn't open")
        XCTAssertTrue(el("bq-clip").waitForExistence(timeout: 15), "no clip of the question from its board")
        sleep(3)
        shot("pad-bank-question")

        // 1 2 3: Done
        tap("bq-done", "no Done button")
        sleep(1)
        XCTAssertTrue(el("bq-done").isSelected, "Done isn't shown as the mark")
        shot("pad-bank-marked")

        // the markscheme beside the question
        if el("bq-ms").waitForExistence(timeout: 10) {
            tap("bq-ms", "no Markscheme button")
            XCTAssertTrue(el("bq-ms-pane").waitForExistence(timeout: 10), "the markscheme didn't open beside the question")
            sleep(3)
            shot("pad-bank-markscheme")
            tap("bq-ms", "no Hide the markscheme button")
            sleep(1)
        } else {
            shot("pad-bank-no-markscheme")
            XCTFail("the Acids paper's markscheme wasn't found")
        }

        // Write on it opens the paper's board; Insert › Mark as question boxes a question into the bank
        tap("bq-board", "no Write on it")
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the paper's board didn't open")
        sleep(3)
        shot("pad-bank-board")
        if el("board-mode-menu").exists { el("board-mode-menu").tap(); app.buttons["Insert"].firstMatch.tap(); sleep(1) } // a folded bar
        else { el("board-mode-insert").tap(); sleep(1) }
        tap("insert-question", "Insert has no Mark as question", in: app)
        let box = el("question-box")
        XCTAssertTrue(box.waitForExistence(timeout: 5), "no box to draw round the question")
        sleep(1)
        let from = box.coordinate(withNormalizedOffset: CGVector(dx: 0.30, dy: 0.30))
        from.press(forDuration: 0.3, thenDragTo: box.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.42)))
        let added = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'is in the question bank'")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 10), "no word that the question went into the bank")
        shot("pad-bank-marked-on-board")

        // back from the board to the question
        let close = app.navigationBars.buttons["Close"].firstMatch
        if close.waitForExistence(timeout: 5) { close.tap() }
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 15), "closing the board didn't come back to the question")
        sleep(2)
        shot("pad-bank-back-to-question")
    }
}
