import XCTest

/// The Files picker for a PDF must open and close without freezing the app (Nov 12: pressing a PDF button showed an empty picker
/// and the whole app hung). Each test opens one of the app's PDF pickers, waits, cancels it, and checks the app still answers.
/// The cloud run (ui-check.yml) samples the app's main thread while this runs, so a hang shows where it is stuck.
final class PdfPickerTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        step("launched")
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap(); step("sample data made") }
    }

    func step(_ s: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(s)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = s
        a.lifetime = .keepAlways
        add(a)
    }

    /// A notebook to work in, opened on its page.
    func openNotebook(_ name: String) {
        let make = app.buttons["New notebook…"]
        var tries = 0
        while !make.isHittable && tries < 6 { app.collectionViews.firstMatch.swipeUp(); tries += 1 }
        XCTAssertTrue(make.waitForExistence(timeout: 10), "no New notebook… row")
        make.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText(name)
        alert.buttons["Make"].tap()
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the new notebook isn't in the sidebar")
        row.tap()
        step("notebook page")
    }

    /// The picker is up: wait a little, cancel it, and the app must answer again.
    func pickerCloses(_ what: String) {
        step(what + ": asked")
        sleep(6)
        step(what + ": after 6 s")
        let cancel = app.buttons["Cancel"].firstMatch
        let shown = cancel.waitForExistence(timeout: 20)
        step(what + ": cancel shown \(shown)")
        XCTAssertTrue(shown, "the picker never showed its Cancel button")
        let t0 = Date()
        cancel.tap()
        step(what + ": cancelled after \(Int(Date().timeIntervalSince(t0))) s")
    }

    func testNotebookFromAPdf() {
        openNotebook("PDF test")
        let new = app.buttons["New"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()
        app.buttons["From a PDF…"].firstMatch.tap()
        pickerCloses("From a PDF")
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        XCTAssertTrue(new.isHittable, "the notebook page doesn't answer after the picker")
        new.tap()
        XCTAssertTrue(app.buttons["Blank board"].firstMatch.waitForExistence(timeout: 10), "the New menu doesn't open after the picker")
        step("New menu works after")
    }

    func testBoardPdfPrintout() {
        openNotebook("Printout test")
        let new = app.buttons["New"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()
        app.buttons["Blank board"].firstMatch.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Board one")
        alert.buttons["Make"].tap()
        let insert = app.buttons["Insert"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 15), "the board's Insert button isn't there")
        step("board open")
        insert.tap()
        app.buttons["PDF printout…"].firstMatch.tap()
        pickerCloses("PDF printout")
        XCTAssertTrue(insert.waitForExistence(timeout: 10))
        insert.tap()
        XCTAssertTrue(app.buttons["PDF printout…"].firstMatch.waitForExistence(timeout: 10), "the Insert menu doesn't open after the picker")
        step("Insert menu works after")
    }
}
