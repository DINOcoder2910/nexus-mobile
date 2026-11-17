import XCTest

/// The iPad's side of "every feature on both devices" (Nov 16 2026): Home, Files, How Nexus works and Share into Nexus from the
/// sidebar. The screenshots ("pad-…") run in the UI check. Skips itself on the iPhone.
final class ParityPadTests: XCTestCase {
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

    func side(_ name: String) {
        let row = app.buttons[name].firstMatch.exists ? app.buttons[name].firstMatch : app.staticTexts[name].firstMatch
        if !row.waitForExistence(timeout: 3) { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar has no \(name)")
        row.tap()
        sleep(2)
    }

    func testSidebarHasTheNewPlaces() {
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 15), "the sidebar isn't up")

        side("Home")
        XCTAssertTrue(app.descendants(matching: .any)["home-fig-slipped"].waitForExistence(timeout: 10), "Home has no figures")
        shot("pad-home")

        side("Files")
        shot("pad-files")

        side("How Nexus works")
        shot("pad-guide")

        side("Settings")
        let share = app.buttons["Share into Nexus"].firstMatch
        var tries = 0
        while !share.waitForExistence(timeout: 2) && tries < 8 { app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)).press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.2))); tries += 1 }
        XCTAssertTrue(share.waitForExistence(timeout: 10), "Settings has no Share into Nexus")
        share.tap()
        sleep(2)
        shot("pad-share")
    }
}
