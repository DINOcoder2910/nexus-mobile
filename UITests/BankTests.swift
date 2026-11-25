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
        let e = el(id)
        _ = e.waitForExistence(timeout: 8)
        // a list only keeps the rows near the screen. A row that is there but can't be tapped (off screen, or under the system's
        // notifications alert, which the first swipe answers) is scrolled toward: down when it is in the list's upper half. A row
        // that is gone may be above, so look up first (4 swipes), then down. Nov 23, PR #55: swiping only up lost the sidebar's
        // Study row, which the alert had made untappable while it was on screen.
        let l = list ?? app.collectionViews.firstMatch
        var downs = 0
        for _ in 0..<14 {
            if e.exists && e.isHittable { break }
            if e.exists {
                if e.frame.midY < l.frame.midY { l.swipeDown() } else { l.swipeUp() }
            } else if downs < 4 {
                l.swipeDown(); downs += 1
            } else {
                l.swipeUp()
            }
            sleep(1) // let the list settle: a tap while it glides only stops it (BankPhoneTests, Nov 24)
        }
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
        // the card's own id doesn't come through a List row on the iPad (a9e4986), so look for its section's title and its Go on chip
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Working on'")).firstMatch.exists,
                      "no Working on (the pinned Acids paper)")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Go on at'")).firstMatch.exists,
                      "the pinned Acids paper has no Go on at its bookmark")

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

        // the data booklet beside the question (the laptop's D): chemistry's first, physics' one tap away
        tap("bq-booklet", "no Data booklet button")
        XCTAssertTrue(el("bq-booklet-pane").waitForExistence(timeout: 10), "the data booklet didn't open beside the question")
        sleep(3)
        shot("pad-bank-booklet")
        let physics = el("bq-booklet-subjects").buttons["Physics HL"].firstMatch
        XCTAssertTrue(physics.waitForExistence(timeout: 5), "the booklet pane has no switch to physics' booklet")
        physics.tap()
        sleep(2)
        shot("pad-bank-booklet-physics")
        let maths = el("bq-booklet-subjects").buttons["Math AA HL"].firstMatch
        XCTAssertTrue(maths.waitForExistence(timeout: 5), "the booklet pane has no switch to maths' formula booklet")
        maths.tap()
        sleep(2)
        shot("pad-bank-booklet-maths")
        el("bq-booklet-subjects").buttons["Chemistry HL"].firstMatch.tap()
        tap("bq-booklet", "no Hide the data booklet button")
        sleep(1)

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
        // the board's toast (board-toast) says where it went, or why not
        let added = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'is in the question bank'")).firstMatch
        let toast = el("board-toast")
        XCTAssertTrue(added.waitForExistence(timeout: 10),
                      "no word that the question went into the bank (the toast: \(toast.exists ? toast.label : "none"))")
        shot("pad-bank-marked-on-board")

        // back from the board to the question
        // the board's own back button (BoardBar: "Close the board"); there is no navigation bar Close over a board
        let close = app.buttons["Close the board"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the board has no Close the board"); close.tap()
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 15), "closing the board didn't come back to the question")
        sleep(2)
        shot("pad-bank-back-to-question")

        // Solve full screen (the laptop's F): the board over the whole screen from the question; Close comes back to it
        tap("bq-solve", "no Solve full screen")
        let back = app.buttons["Close the board"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 30), "Solve full screen didn't open the board")
        sleep(3)
        shot("pad-bank-solve")
        // the data booklet beside the board while solving (the bar's Data booklet)
        let book = el("board-booklet")
        XCTAssertTrue(book.waitForExistence(timeout: 10), "solving, the board's bar has no Data booklet")
        book.tap()
        XCTAssertTrue(el("bq-booklet-pane").waitForExistence(timeout: 10), "the data booklet didn't open beside the board")
        sleep(3)
        shot("pad-bank-solve-booklet")
        back.tap()
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 15), "closing the full screen board didn't come back to the question")
    }
}
