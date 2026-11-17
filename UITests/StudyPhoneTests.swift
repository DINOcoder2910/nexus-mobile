import XCTest

/// Study on the iPhone (Nov 16 2026): the same features as the iPad, laid out for the phone: the Study page as one list (the practice
/// sheets on their own screen, with a Filter menu), units, Practice classifying, the chemistry tools and Upload a sheet (the demo's
/// canned Claude answer, -NexusStudyUploadDemo). Screenshots ("phone-study-…") are printed in the phone-check log. Skips on the iPad.
final class StudyPhoneTests: XCTestCase {
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
        while !(e.exists && e.isHittable) && tries < 8 { list.swipeUp(); tries += 1 }
        XCTAssertTrue(e.waitForExistence(timeout: 5), why)
        e.tap()
    }

    func back() {
        let b = app.navigationBars.buttons.element(boundBy: 0)
        if b.exists { b.tap() }
        sleep(1)
    }

    func testStudyOnTheIPhone() {
        app.launchArguments = ["-NexusStudyUploadDemo"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "no More tab")
        more.tap()
        tap("sidebar-Study", "no Study row")
        sleep(2)
        shot("phone-study-home")

        tap("study-page-chemistry-hl", "no Study page row for Chemistry HL")
        XCTAssertTrue(el("study-theme-R1").waitForExistence(timeout: 10), "no units on the Study page")
        sleep(1)
        shot("phone-study-page")
        app.collectionViews.firstMatch.swipeUp()
        sleep(1)
        shot("phone-study-page-lower")

        tap("study-sheets", "no Practice sheets row")
        XCTAssertTrue(el("study-sheets-list").waitForExistence(timeout: 8), "no sheets list")
        sleep(1)
        shot("phone-study-sheets")
        let filter = el("study-sheets-filter")
        if filter.waitForExistence(timeout: 5) {
            filter.tap(); sleep(1)
            shot("phone-study-sheets-filter")
            app.buttons["Unit"].firstMatch.tap(); sleep(1)
            let r1 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'R1 '")).firstMatch
            if r1.waitForExistence(timeout: 3) { r1.tap(); sleep(1); shot("phone-study-sheets-r1") }
            else { app.tap() }
        }
        back()

        tap("study-theme-R1", "no R1 theme row")
        sleep(1)
        shot("phone-study-units")
        tap("study-unit-R1.2", "no R1.2 unit row")
        sleep(1)
        shot("phone-study-unit")
        back(); back()

        tap("study-practice-acids", "no Practice classifying row")
        XCTAssertTrue(el("practice-start").waitForExistence(timeout: 8), "Practice has no Start")
        el("practice-start").tap()
        XCTAssertTrue(el("practice-option-1").waitForExistence(timeout: 5), "no options")
        sleep(1)
        shot("phone-study-practice")
        el("practice-option-1").tap()
        sleep(1)
        shot("phone-study-practice-answer")
        back()

        for (tool, name) in [("vsepr", "phone-study-vsepr"), ("molecules", "phone-study-molecules")] {
            tap("study-tool-" + tool, "no \(tool) row")
            sleep(5)
            shot(name)
            back()
        }

        tap("study-upload", "no Upload a sheet button")
        let sort = el("upload-sort")
        XCTAssertTrue(sort.waitForExistence(timeout: 10), "the upload doesn't ask what the file is")
        sort.tap()
        // the form's top (Claude's summary): File it is at the bottom of a list that only makes the rows on screen
        XCTAssertTrue(el("upload-summary").waitForExistence(timeout: 30), "the upload's form didn't come up")
        sleep(1)
        shot("phone-study-upload-form")
        app.swipeUp(); sleep(1)
        shot("phone-study-upload-form-lower")
        let file = el("upload-file")
        var n = 0
        while !(file.exists && file.isHittable) && n < 8 { app.swipeUp(); n += 1 }
        XCTAssertTrue(file.exists, "no File it")
        file.tap()
        XCTAssertTrue(el("upload-undo").waitForExistence(timeout: 10), "no Undo after filing")
        sleep(1)
        shot("phone-study-upload-filed")
    }
}
