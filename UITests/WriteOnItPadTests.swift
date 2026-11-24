import XCTest

/// Write on it beyond a task's PDF (Nov 23 2026), as on the laptop: a Study sheet opens on its PDF page (the clean PDF, its subject,
/// the subject's cards for its unit, Markscheme in a second pane, Write on it), Write on it makes the paper's board in the
/// subject's notebook (Papers › unit) and opens it, the board has a Markscheme button and a clean-PDF icon beside page 1, the
/// sheet's row then says Your board, and search finds a PDF by its name. The screenshots ("write-…") are the preview. iPad only.
final class WriteOnItPadTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
        continueAfterFailure = true
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
    func labelled(_ label: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch }

    /// Taps what has this identifier, scrolling the list it is in until it can be tapped.
    func tap(_ id: String, _ why: String, in list: XCUIElement? = nil) {
        var e = el(id)
        if !e.waitForExistence(timeout: 8) { e = app.buttons[id].firstMatch }
        let l = list ?? app.collectionViews.firstMatch
        var tries = 0
        while !e.exists && tries < 4 { l.swipeDown(); tries += 1 }
        tries = 0
        while !(e.exists && e.isHittable) && tries < 8 { l.swipeUp(); tries += 1 }
        XCTAssertTrue(e.waitForExistence(timeout: 5), why)
        e.tap()
    }

    /// The sidebar's list (labelled "Sidebar"), not the first list on screen: a Study page has its own. Not "the list holding
    /// sidebar-Study": scrolled down to Search boards, the Study row isn't made, so that query finds nothing.
    var sidebar: XCUIElement { app.collectionViews["Sidebar"].firstMatch }

    func openAcidsSheet() {
        tap("sidebar-Study", "no Study row", in: sidebar)
        sleep(2)
        tap("study-page-chemistry-hl", "no Study page row for Chemistry HL", in: app.collectionViews.element(boundBy: 1))
        let search = el("study-sheets-search")
        XCTAssertTrue(search.waitForExistence(timeout: 10), "no sheets beside the Study page")
        search.tap()
        search.typeText("acids\n") // Return puts the keyboard away: left up, it covers the sidebar's foot and swipes type on it
        sleep(1)
        hideKeyboard()
    }

    func hideKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let hide = app.keyboards.buttons["Hide keyboard"].firstMatch
        if hide.exists { hide.tap() }
        sleep(1)
    }

    func testWriteOnASheet() {
        app.launchArguments = []
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 20) { sample.tap() }
        openAcidsSheet()
        shot("write-sheet-row")

        // the sheet's title opens its paper on the PDF page
        // the sheet's title ("Acids", from its folder "Acids — Paper 2 structured…"), else the row's first button
        let title = labelled("Acids")
        (title.waitForExistence(timeout: 8) ? title : el("study-sheet").buttons.firstMatch).tap()
        XCTAssertTrue(el("pdf-name").waitForExistence(timeout: 30), "the sheet's PDF page didn't open")
        XCTAssertTrue(el("pdf-subject").waitForExistence(timeout: 10), "the PDF page doesn't name its subject")
        XCTAssertTrue(el("pdf-related-cards").exists, "the subject's cards for the sheet's unit aren't there")
        sleep(2)
        shot("write-pdf-page")
        let ms = el("pdf-ms")
        XCTAssertTrue(ms.waitForExistence(timeout: 5), "no Markscheme on a paper that has one")
        ms.tap()
        XCTAssertTrue(el("pdf-ms-pane").waitForExistence(timeout: 10), "the markscheme didn't open beside the paper")
        sleep(2)
        shot("write-pdf-markscheme")

        // Write on it: the paper's board in the subject's notebook, opened
        el("write-on-it").tap()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 120), "the paper's board didn't open")
        sleep(3)
        let boardMs = el("board-ms")
        XCTAssertTrue(boardMs.waitForExistence(timeout: 10), "no Markscheme on the paper's board")
        XCTAssertTrue(el("printout-clean").waitForExistence(timeout: 10), "no clean-PDF icon beside page 1")
        shot("write-board")
        boardMs.tap()
        sleep(3)
        shot("write-board-markscheme")
        // beside the pane the bar is tight: "Draw ▾" stands for the name and the switch (they were squeezed to letters), and the
        // Markscheme button stays on screen
        XCTAssertTrue(el("board-mode-menu").waitForExistence(timeout: 5), "no Draw ▾ on the tight bar beside the markscheme")
        XCTAssertTrue(el("board-ms").isHittable, "the Markscheme button is off the bar beside the markscheme")
        // with the markscheme beside, page 1's corner may be off the board: the icon moves inside the page
        let clean = el("printout-clean")
        XCTAssertTrue(clean.waitForExistence(timeout: 10), "no clean-PDF icon with the markscheme beside")
        if clean.exists { clean.tap() }
        sleep(3)
        shot("write-board-clean-pdf")

        // back on Study: the sheet's row says Your board, and the PDF page has it as its main button
        let close = app.buttons.matching(NSPredicate(format: "label == 'Close the board'")).firstMatch
        if close.waitForExistence(timeout: 5) { close.tap() }
        sleep(2)
        let yours = labelled("Your board")
        var n = 0
        while !yours.exists && n < 4 { if !el("study-sheets-search").exists { openAcidsSheet() }; sleep(2); n += 1 }
        XCTAssertTrue(yours.waitForExistence(timeout: 10), "the sheet's row doesn't say Your board after writing on it")
        shot("write-sheet-row-after")

        // search finds a PDF by its name, and opens it on its page
        hideKeyboard()
        tap("sidebar-Search boards", "no Search boards row", in: sidebar)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field")
        field.tap()
        field.typeText("bonding")
        let hit = el("search-pdf")
        XCTAssertTrue(hit.waitForExistence(timeout: 30), "search didn't find the Bonding PDF")
        sleep(1)
        shot("write-search")
        hit.tap()
        XCTAssertTrue(el("write-on-it").waitForExistence(timeout: 30), "the searched PDF's page has no Write on it")
        sleep(2)
        shot("write-search-pdf")
        el("pdf-close").tap()
    }
}
