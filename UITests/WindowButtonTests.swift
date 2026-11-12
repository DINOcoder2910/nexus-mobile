import XCTest

/// The sidebar has no "New window" button (Nov 12: it was too easy to press by accident, and windows piled up). New windows come
/// from the system instead: hold the app's icon › New Window. The screenshots (ui-check.yml's "shots") show the sidebar as it is.
final class WindowButtonTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testSidebarHasNoNewWindowButton() {
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 15), "the sidebar isn't up")
        sleep(2)
        shot("sidebar")
        XCTAssertFalse(app.buttons["New window"].exists, "the sidebar still has a New window button")
        XCTAssertTrue(app.buttons["New task"].firstMatch.exists, "the sidebar's New task button is gone too")
    }
}
