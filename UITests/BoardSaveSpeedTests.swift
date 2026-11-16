import XCTest

/// A board as full as a long lesson's (4000 handwritten strokes over a PDF page) must save quickly: the iPad saves on the main
/// thread after every stroke, and in Nov 2026 a full board made the Pencil lag and taps go missing. The app makes the board itself
/// (`-NexusTestBigBoard`, Sources/Common/TestHooks.swift) and times ten saves (BoardController+Bench.swift); this prints them.
final class BoardSaveSpeedTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-NexusTestBigBoard"]
        app.launch()
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    func testAFullBoardSavesQuickly() {
        // the app writes the big board, opens it and saves it ten times (a minute or more in the simulator's debug build): the screen
        // can't be read while the app is busy, and the app's own breadcrumbs time each save, so the first look waits for all that
        sleep(100)
        let insert = app.buttons["Insert"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 60), "the big board didn't open")
        if app.staticTexts["Planner"].firstMatch.isHittable {
            let side = app.buttons["Sidebar"].firstMatch
            if side.exists { side.tap(); sleep(2) }
        }
        let bench = app.staticTexts["save-bench"].firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 30), "no save bench on the board")
        var tries = 0
        while bench.label.hasSuffix("waiting") && tries < 180 { sleep(1); tries += 1 }
        print("UISTEP BENCH \(bench.label)")
        shot("speed-1 full board after ten saves")
        // the app still answers: the Insert menu opens at once
        let t0 = Date()
        insert.tap()
        let text = app.buttons["Text"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "the Insert menu didn't open")
        print("UISTEP Insert menu opened in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        shot("speed-2 insert menu")
    }
}
