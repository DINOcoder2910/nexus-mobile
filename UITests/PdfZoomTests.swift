import XCTest

/// Zoomed far into a PDF printout, the page must stay drawn, and stay drawn when zoomed back out (Nov 13 2026: on the iPad a page
/// went grey at deep zoom and stayed grey until scrolled far away). The app makes the board itself (`-NexusTestPdfBoard`,
/// Sources/Common/TestHooks.swift); the screenshots ("zoom-…") are printed in the ui-check log.
final class PdfZoomTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-NexusTestPdfBoard"]
        app.launch()
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name) [\(zoomLabel())]")
    }

    /// The zoom pill's "250%".
    func zoomLabel() -> String {
        let pills = app.buttons.allElementsBoundByIndex.map(\.label).filter { $0.hasSuffix("%") && Int($0.dropLast()) != nil }
        return pills.first ?? "?"
    }

    func zoom() -> Int { Int(zoomLabel().dropLast()) ?? 0 }

    /// The board's canvas: the biggest scroll view on screen.
    func board() -> XCUIElement {
        let all = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        return all.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) ?? app.windows.firstMatch
    }

    func testDeepZoomKeepsThePageDrawn() {
        let insert = app.buttons["Insert"].firstMatch
        XCTAssertTrue(insert.waitForExistence(timeout: 30), "the PDF board didn't open")
        sleep(3)
        // the sidebar floats over the board in landscape: put it away, as when you work on a board
        if app.staticTexts["Planner"].firstMatch.isHittable {
            let side = app.buttons["Sidebar"].firstMatch
            if side.exists { side.tap(); sleep(2) }
        }
        shot("zoom-1 at \(zoom())%")

        var tries = 0
        while zoom() < 480 && tries < 8 { board().pinch(withScale: 2.5, velocity: 3); sleep(1); tries += 1 }
        sleep(4)
        shot("zoom-2 deep at \(zoom())%")
        XCTAssertGreaterThanOrEqual(zoom(), 300, "couldn't zoom in")

        board().swipeUp(velocity: .slow)
        sleep(4)
        shot("zoom-3 deep, moved, at \(zoom())%")

        // back out with the zoom pill's 100% (a pinch out from the test doesn't take on the simulator)
        app.buttons[zoomLabel()].firstMatch.tap()
        let hundred = app.buttons["100%"].firstMatch
        if hundred.waitForExistence(timeout: 5) { hundred.tap() } else { app.collectionViews.buttons["100%"].firstMatch.tap() }
        sleep(4)
        XCTAssertLessThanOrEqual(zoom(), 110, "didn't zoom back out")
        shot("zoom-4 back out at \(zoom())%")
    }
}
