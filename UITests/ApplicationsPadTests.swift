import XCTest

/// Applications on the iPad (Nov 16 2026): from the sidebar, the Tracker side by side, a school's page in two columns with its menu and
/// the site check, and Research as a table. The screenshots ("pad-apps-…") are printed in the phone-check log. Skips itself on the iPhone.
final class ApplicationsPadTests: XCTestCase {
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

    func testApplicationsOnTheIPad() {
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 15), "the sidebar isn't up")
        let row = app.buttons["Applications"].firstMatch.exists ? app.buttons["Applications"].firstMatch : app.staticTexts["Applications"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the sidebar has no Applications")
        row.tap()

        XCTAssertTrue(app.descendants(matching: .any)["apps-tab"].waitForExistence(timeout: 10), "Applications didn't open")
        sleep(2)
        shot("pad-apps-tracker")

        let nw = app.descendants(matching: .any)["apps-school-northwestern"].firstMatch
        XCTAssertTrue(nw.waitForExistence(timeout: 10), "the tracker has no Northwestern")
        nw.tap()
        let menu = app.descendants(matching: .any)["school-more"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the school's page didn't open")
        sleep(2)
        shot("pad-apps-school")
        menu.tap()
        sleep(1)
        shot("pad-apps-school-menu")
        let check = app.buttons["Check the school's site"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5), "the menu has no site check")
        check.tap()
        sleep(2)
        shot("pad-apps-sitecheck")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)

        let back = app.buttons["Applications"].firstMatch
        back.tap()
        sleep(1)
        let research = app.buttons["Research"].firstMatch
        XCTAssertTrue(research.waitForExistence(timeout: 10), "no Research switch")
        research.tap()
        sleep(5)
        shot("pad-apps-research")
    }
}
