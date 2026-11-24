import XCTest

/// The question bank on the iPhone (Nov 23 2026): the same as BankTests on the iPad, laid out for the phone (the markscheme in a sheet,
/// Mark as question in the board's Insert sheet). `-NexusTestBank` gives Chemistry HL's bank as the laptop leaves it. Screenshots
/// ("phone-bank-…") are printed in the ui-check log. Skips on the iPad.
final class BankPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// The system's first-keyboard tip, if this test brought it up, is answered here, so it doesn't carry over the simulator
    /// into the next test that types (SpanishPhoneTests failed to type on 80e8744 and 7784cc5, Nov 23, PR #55).
    override func tearDownWithError() throws {
        let tip = app.buttons["Continue"].firstMatch
        if tip.exists { tip.tap() }
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
        while !e.exists && tries < 4 { list.swipeDown(); sleep(1); tries += 1 }
        tries = 0
        // into the top 70% of the screen, clear of the tab bar and the timer pill (docs/ci-lessons.md, Nov 22). Each swipe is let
        // settle: a tap while the list still glides only stops it (6de89d9, Nov 24: Go on at was tapped mid-glide and nothing opened)
        while !(e.exists && e.isHittable && e.frame.maxY < app.frame.height * 0.7) && tries < 8 {
            if e.exists && e.frame.maxY < list.frame.minY + 100 { list.swipeDown(velocity: .slow) } else { list.swipeUp(velocity: .slow) }
            sleep(1)
            tries += 1
        }
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

        // the data booklet (the laptop's D): a sheet over the question, chemistry's first
        tap("bq-booklet", "no Data booklet button")
        XCTAssertTrue(el("bq-booklet-pane").waitForExistence(timeout: 10), "the data booklet didn't open")
        sleep(3)
        shot("phone-bank-booklet")
        let closeBook = app.buttons["Close the booklet"].firstMatch
        XCTAssertTrue(closeBook.waitForExistence(timeout: 5), "the booklet has no Close"); closeBook.tap()
        sleep(1)

        // the board's Insert menu: Mark as question
        tap("bq-board", "no Write on it")
        // the iPhone's board has the tool pill (PhoneToolPill): + opens Insert's sheet, whose rows include Mark as question
        let insert = el("phone-tool-plus")
        XCTAssertTrue(insert.waitForExistence(timeout: 30), "the paper's board didn't open (no + in the tool pill)")
        sleep(3)
        insert.tap()
        XCTAssertTrue(el("phone-tool-sheet").waitForExistence(timeout: 10), "+ didn't open Insert's sheet")
        let mark = app.buttons["Mark as question"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 5), "Insert's sheet has no Mark as question")
        sleep(1)
        shot("phone-bank-insert")
        mark.tap()
        let box = el("question-box")
        XCTAssertTrue(box.waitForExistence(timeout: 5), "no box to draw round the question")
        sleep(1)
        // the system's first-keyboard tip ("Speed up your typing…") sits over everything and takes the drag (Nov 23, PR #55)
        let tip = app.buttons["Continue"].firstMatch
        if tip.exists { tip.tap(); sleep(1) }
        shot("phone-bank-box")
        box.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.30))
            .press(forDuration: 0.3, thenDragTo: box.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.40)))
        // the board's toast (board-toast) says where it went, or why not
        let added = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'is in the question bank'")).firstMatch
        let toast = el("board-toast")
        XCTAssertTrue(added.waitForExistence(timeout: 10),
                      "no word that the question went into the bank (the toast: \(toast.exists ? toast.label : "none"))")
        shot("phone-bank-marked-on-board")
        // the board's own back button (BoardBar: "Close the board"); there is no navigation bar Close over a board
        let close = app.buttons["Close the board"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the board has no Close the board"); close.tap()
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 15), "closing the board didn't come back to the question")
        sleep(1)
        shot("phone-bank-back-to-question")

        // Solve full screen (the laptop's F): the board over the whole phone from the question; Close comes back to it
        tap("bq-solve", "no Solve full screen")
        let back = app.buttons["Close the board"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 30), "Solve full screen didn't open the board")
        sleep(3)
        shot("phone-bank-solve")
        // the data booklet under the board while solving (⋯ › Data booklet; the panes stack on a phone)
        let boardMore = el("board-more")
        XCTAssertTrue(boardMore.waitForExistence(timeout: 10), "the board has no ⋯")
        boardMore.tap()
        // (the question page's own Data booklet, bq-booklet, is still under the board)
        let bookRow = app.buttons.matching(NSPredicate(format: "label == 'Data booklet' AND identifier != 'bq-booklet'")).firstMatch
        XCTAssertTrue(bookRow.waitForExistence(timeout: 5), "solving, the board's ⋯ has no Data booklet")
        bookRow.tap()
        XCTAssertTrue(el("bq-booklet-pane").waitForExistence(timeout: 10), "the data booklet didn't open under the board")
        sleep(3)
        shot("phone-bank-solve-booklet")
        back.tap()
        XCTAssertTrue(el("bq-count").waitForExistence(timeout: 15), "closing the full screen board didn't come back to the question")
    }
}
