import XCTest

/// Scanning a handout twice (Nov 14: the second scan never started, so a handout had to come in from photos). The simulator has no
/// document camera, so `-NexusTestFakeScanner` puts a stand-in camera in its place: "Finish fake scan" hands back one printed page.
/// A notebook's New › From a scan… makes a board; on that board, Insert › Scan a handout… must open the camera again, twice.
final class ScanTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-NexusTestFakeScanner"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        step("launched")
    }

    func step(_ s: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(s)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = s
        a.lifetime = .keepAlways
        add(a)
    }

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
    }

    /// The camera must come up; then finish (one page) or cancel it.
    func camera(_ what: String, finish: Bool) {
        let done = app.buttons["Finish fake scan"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 30), "\(what): the camera didn't open")
        step("scan-\(what) camera")
        (finish ? done : app.buttons["Cancel fake scan"].firstMatch).tap()
        XCTAssertFalse(app.alerts["The camera didn't open"].exists, "\(what): the app said the camera didn't open")
    }

    func testScanAgainAndAgain() {
        openNotebook("Scan test")
        let new = app.buttons["New"].firstMatch
        XCTAssertTrue(new.waitForExistence(timeout: 10))
        new.tap()
        app.buttons["From a scan…"].firstMatch.tap()
        camera("1 new board", finish: true)

        // the scan's board opens by itself, named from the page's title. The page's words are read first (a few seconds on the
        // runner), and the runner's simulator can stop answering for most of a minute while accessibility loads (Nov 20: 54 s
        // right after this scan), so it gets a long wait and a picture of what was there if it never came.
        sleep(3)
        step("scan-1 after the camera")
        let insert = app.buttons["Insert"].firstMatch
        if !insert.waitForExistence(timeout: 120) {
            step("scan-1 no board")
            for a in app.alerts.allElementsBoundByIndex { print("UISTEP alert: \(a.label)") }
            XCTFail("the board made from the scan didn't open")
            return
        }
        sleep(2)
        step("scan-board from the first scan")

        for (i, finish) in [(2, true), (3, false), (4, true)] {
            XCTAssertTrue(insert.waitForExistence(timeout: 10))
            insert.tap()
            let item = app.buttons["Scan a handout…"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 10), "scan \(i): no Scan a handout… in Insert")
            item.tap()
            camera("\(i) on the board", finish: finish)
            if finish {
                let reading = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Reading the handout'")).firstMatch
                XCTAssertTrue(reading.waitForExistence(timeout: 30), "scan \(i): the board never started reading it")
                sleep(3)
                step("scan-\(i) added")
            }
        }

        // and the app still answers
        insert.tap()
        XCTAssertTrue(app.buttons["Scan a handout…"].firstMatch.waitForExistence(timeout: 10), "the Insert menu doesn't open after scanning")
        step("scan-insert menu after")
    }
}
