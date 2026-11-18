import XCTest

/// Applications on the iPhone (Nov 16 2026): from More, the Tracker (runway, essays, write order), a school's page with its menu and
/// the site check, and Research. The screenshots ("phone-apps-…") are printed in the phone-check log. Skips itself on the iPad.
final class ApplicationsPhoneTests: XCTestCase {
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

    func testApplicationsOnThePhone() {
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "no More tab")
        more.tap()
        let row = app.buttons["Applications"].firstMatch
        if !row.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "More has no Applications")
        row.tap()

        // the tracker
        XCTAssertTrue(app.descendants(matching: .any)["apps-tab"].waitForExistence(timeout: 10), "Applications didn't open")
        sleep(2)
        shot("phone-apps-tracker")
        app.swipeUp()
        sleep(1)
        shot("phone-apps-tracker-lower")
        app.swipeDown()
        app.swipeDown()
        sleep(1)

        // a school's page, its menu and the site check
        let nw = app.descendants(matching: .any)["apps-school-northwestern"].firstMatch
        XCTAssertTrue(nw.waitForExistence(timeout: 10), "the tracker has no Northwestern")
        nw.tap()
        let menu = app.descendants(matching: .any)["school-more"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "the school's page didn't open")
        sleep(2)
        shot("phone-apps-school")
        app.swipeUp()
        sleep(1)
        shot("phone-apps-school-lower")
        app.swipeUp()
        sleep(1)
        shot("phone-apps-school-end")
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        menu.tap()
        sleep(1)
        shot("phone-apps-school-menu")
        let check = app.buttons["Check the school's site"].firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5), "the menu has no site check")
        check.tap()
        sleep(2)
        shot("phone-apps-sitecheck")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        // Research: every school of the database and the list
        let research = app.buttons["Research"].firstMatch
        XCTAssertTrue(research.waitForExistence(timeout: 10), "no Research switch")
        research.tap()
        sleep(5)
        shot("phone-apps-research")
        let filters = app.buttons["Filters"].firstMatch
        if filters.waitForExistence(timeout: 3) {
            filters.tap()
            sleep(1)
            shot("phone-apps-filters")
        }
    }
}
