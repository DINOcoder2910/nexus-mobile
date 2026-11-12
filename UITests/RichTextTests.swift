import XCTest

/// Typing in a board block with the laptop's rich-text editor (Sources/Writing/RichEditor.swift): a block opens in the web view,
/// markdown-style typing becomes formatting as on the laptop, the format bar drives it, and the Writing view shows the same editor as a
/// page. Run in light and in dark (the board's "Always dark"); the screenshots are kept in the result bundle (ui-check.yml).
final class RichTextTests: XCTestCase {
    var app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func launch(dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-board.dark", dark ? "always" : "never", "-notes.richEditor", "YES"]
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

    func openBoard(_ notebook: String) {
        let make = app.buttons["New notebook…"]
        var tries = 0
        while !make.isHittable && tries < 6 { app.collectionViews.firstMatch.swipeUp(); tries += 1 }
        XCTAssertTrue(make.waitForExistence(timeout: 10), "no New notebook… row")
        make.tap()
        var alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText(notebook)
        alert.buttons["Make"].tap()
        let row = app.staticTexts[notebook].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let new = app.buttons["New"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()
        app.buttons["Blank board"].firstMatch.tap()
        alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Rich words")
        alert.buttons["Make"].tap()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 15), "the board didn't open")
        step("board open")
    }

    func typeABlock() {
        let text = app.buttons["Text"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 10), "no Text tool")
        text.tap()
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.28)).tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15), "the block didn't open in the rich-text editor")
        sleep(2)
        step("block opened (keyboard up on its own?)")
        web.tap()
        app.typeText("# Why chemistry\n")
        app.typeText("Bonds are **strong** and _fast_ to form: H2O and CO2 .\n")
        app.typeText("[ ] revise R3.2 redox\n")
        app.typeText("read the handout\n\n")
        app.typeText("> A quote from the textbook\n")
        // the format bar: bold on, a word, bold off
        let bold = app.buttons["Bold"].firstMatch
        XCTAssertTrue(bold.waitForExistence(timeout: 5), "no format bar over the keyboard")
        app.typeText("Then ")
        bold.tap()
        app.typeText("bold from the bar")
        bold.tap()
        app.typeText(" and back.")
        sleep(1)
        step("typed on the board")
    }

    func writingView() {
        let more = app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        let item = app.buttons["Writing view"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "no Writing view in More")
        item.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10), "the Writing view has no editor")
        sleep(2)
        step("writing view")
        app.typeText(" Typed in the Writing view.")
        sleep(1)
        step("writing view typed")
        let done = app.buttons["Done"].firstMatch
        done.tap()
        sleep(2)
        step("back on the board")
    }

    func testRichTextLight() {
        launch(dark: false)
        openBoard("Rich light")
        typeABlock()
        writingView()
    }

    func testRichTextDark() {
        launch(dark: true)
        openBoard("Rich dark")
        typeABlock()
        writingView()
    }
}
