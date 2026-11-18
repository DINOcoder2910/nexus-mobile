import XCTest

/// Study on the iPad (Nov 16 2026): a chemistry workstream's Study page (units, Memorize, tools, the practice sheets beside them), a
/// theme's units and a unit, Practice classifying, the VSEPR chart, Enthalpies and Molecules on their own screens, and Upload a sheet
/// with the demo's canned Claude answer (-NexusStudyUploadDemo). The screenshots ("pad-study-…") are printed in the phone-check log.
/// Skips itself on the iPhone.
final class StudyPadTests: XCTestCase {
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

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
        sleep(1)
    }

    func testStudyOnTheIPad() {
        app.launchArguments = ["-NexusStudyUploadDemo"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        tap("sidebar-Study", "no Study row")
        sleep(2)
        shot("pad-study-home")

        tap("study-page-chemistry-hl", "no Study page row for Chemistry HL", in: app.collectionViews.element(boundBy: 1))
        XCTAssertTrue(el("study-theme-R1").waitForExistence(timeout: 10), "no units on the Study page")
        sleep(2)
        shot("pad-study-page")

        // the sheets beside: search narrows them
        let search = el("study-sheets-search")
        if search.waitForExistence(timeout: 5) {
            search.tap(); search.typeText("hess"); sleep(1)
            shot("pad-study-sheets-search")
            app.buttons["Clear filters"].firstMatch.tap()
            sleep(1)
        }

        tap("study-theme-R1", "no R1 theme row", in: app.collectionViews.firstMatch)
        sleep(1)
        shot("pad-study-units")
        tap("study-unit-R1.2", "no R1.2 unit row")
        sleep(1)
        shot("pad-study-unit")
        back(); back()

        tap("study-practice-acids", "no Practice classifying row", in: app.collectionViews.firstMatch)
        XCTAssertTrue(el("practice-start").waitForExistence(timeout: 8), "Practice has no Start")
        sleep(1)
        shot("pad-study-practice-setup")
        el("practice-start").tap()
        XCTAssertTrue(el("practice-option-1").waitForExistence(timeout: 5), "no options")
        el("practice-option-1").tap()
        XCTAssertTrue(el("practice-next").waitForExistence(timeout: 5), "no Next after answering")
        sleep(1)
        shot("pad-study-practice-answer")
        back()

        for (tool, name) in [("vsepr", "pad-study-vsepr"), ("enthalpies", "pad-study-enthalpies"), ("molecules", "pad-study-molecules")] {
            tap("study-tool-" + tool, "no \(tool) row", in: app.collectionViews.firstMatch)
            // the tool is a web page: wait for its words, not a fixed time (the first page of a run loads slowest)
            XCTAssertTrue(app.webViews.firstMatch.staticTexts.firstMatch.waitForExistence(timeout: 30), "the \(tool) page stayed blank")
            sleep(2)
            shot(name)
            back()
        }

        tap("study-upload", "no Upload a sheet button")
        let sort = el("upload-sort")
        XCTAssertTrue(sort.waitForExistence(timeout: 10), "the upload doesn't ask what the file is")
        sleep(1)
        shot("pad-study-upload-describe")
        sort.tap()
        // the form's top (Claude's summary): File it is at the bottom of a list that only makes the rows on screen
        XCTAssertTrue(el("upload-summary").waitForExistence(timeout: 30), "the upload's form didn't come up")
        sleep(1)
        shot("pad-study-upload-form")
        let file = el("upload-file")
        var n = 0
        while !(file.exists && file.isHittable) && n < 8 { app.swipeUp(); n += 1 }
        XCTAssertTrue(file.exists, "no File it")
        file.tap()
        XCTAssertTrue(el("upload-undo").waitForExistence(timeout: 10), "no Undo after filing")
        sleep(1)
        shot("pad-study-upload-filed")
        app.buttons["Done"].firstMatch.tap()
        sleep(2)
        shot("pad-study-page-after")
    }
}
