import XCTest

/// Ideas (Sources/Ideas/): the screen from the sidebar on the iPad and from More on the iPhone, on the UI check's ideas
/// (-NexusTestIdeas: IdeasModel.seed), adding one, and Settings › Usage. Screenshots named "ideas-…" are printed in the ui-check log.
final class IdeasTests: XCTestCase {
    var app = XCUIApplication()

    override func setUp() { continueAfterFailure = false }

    func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-NexusTestIdeas"] + extra
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func openIdeasFromSidebar() {
        let row = app.staticTexts["Ideas"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no Ideas row in the sidebar")
        row.tap()
        XCTAssertTrue(app.staticTexts["New · 2"].firstMatch.waitForExistence(timeout: 15), "the seeded ideas didn't show")
    }

    func testIdeasIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        openIdeasFromSidebar()
        XCTAssertTrue(app.staticTexts["You wrote: “an app that reminds me to stretch every hour when im at the desk”"].firstMatch.exists)
        shot("ideas-ipad-list-light")
        let field = app.textViews["ideas.input"].exists ? app.textViews["ideas.input"] : app.textFields["ideas.input"]
        field.tap()
        field.typeText("Make a playlist for the long drive")
        app.buttons["ideas.add"].tap()
        XCTAssertTrue(app.staticTexts["New · 3"].firstMatch.waitForExistence(timeout: 10), "the idea wasn't added")
        shot("ideas-ipad-added-light")
        // Settings › Usage
        app.staticTexts["Settings"].firstMatch.tap()
        let credits = app.staticTexts["Anthropic API credits"].firstMatch
        for _ in 0..<12 where !(credits.exists && credits.isHittable) { app.swipeUp() }
        XCTAssertTrue(credits.exists, "no Usage section in Settings")
        XCTAssertTrue(app.staticTexts["usage.plan.none"].exists)
        shot("ideas-ipad-settings-usage-light")
    }

    func testIdeasIPadDark() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        XCUIDevice.shared.orientation = .landscapeLeft
        launch(["-NexusTestDark"])
        openIdeasFromSidebar()
        shot("ideas-ipad-list-dark")
    }
}

/// The iPhone: Ideas is in More (the sidebar as a list).
final class IdeasPhoneTests: XCTestCase {
    func testIdeasPhone() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone only") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-NexusTestIdeas"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        let more = app.tabBars.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let row = app.staticTexts["Ideas"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Ideas row in More")
        row.tap()
        XCTAssertTrue(app.staticTexts["New · 2"].firstMatch.waitForExistence(timeout: 15), "the seeded ideas didn't show")
        let shot = { (name: String) in
            print("UISTEP \(Date().timeIntervalSince1970) \(name)")
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; self.add(a)
        }
        shot("ideas-phone-list")
        app.swipeUp()
        shot("ideas-phone-list-lower")
    }
}
