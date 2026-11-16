import XCTest

/// Claude on the iPhone (Nov 16 2026): Today's ✦ menu (Plan with Claude, Ask Claude about today), the conversation as a sheet with its
/// commands behind the / button and the model behind ⋯, a change card accepted, and the Claude row in More. Launched with
/// -NexusClaudeDemo (canned replies on the sample data). The screenshots ("phone-claude-…") are printed in the claude-check and
/// phone-check logs. Skips itself on the iPad (ClaudeChatUITests).
final class ClaudeChatPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func launch() {
        app.launchArguments = ["-NexusClaudeDemo"]
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

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func openMenu() {
        let menu = el("today-claude")
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "no ✦ menu on Today")
        menu.tap()
    }

    func testPlanWithClaudeFromTodaysMenu() {
        launch()
        openMenu()
        sleep(2)
        shot("phone-claude-today-menu")
        app.buttons["Plan with Claude"].firstMatch.tap()
        XCTAssertTrue(el("plan-result").waitForExistence(timeout: 30), "Plan with Claude didn't finish")
        sleep(1)
        shot("phone-claude-plan-placed")
    }

    func testTheConversationSheet() {
        launch()
        openMenu()
        app.buttons["Ask Claude about today"].firstMatch.tap()
        let input = el("claude-input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the conversation didn't open")
        sleep(2)
        shot("phone-claude-empty")

        // the commands behind the / button
        el("claude-commands").tap()
        sleep(1)
        shot("phone-claude-commands")
        app.buttons["File my Inbox"].firstMatch.tap()
        let accept = app.buttons["change-accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 30), "no change card")
        sleep(1)
        shot("phone-claude-change")
        accept.tap()
        XCTAssertTrue(app.buttons["change-undo"].firstMatch.waitForExistence(timeout: 10), "the change wasn't saved")
        shot("phone-claude-saved")

        // the model and the rest behind ⋯
        el("claude-menu").tap()
        sleep(1)
        shot("phone-claude-menu")
    }

    func testClaudeInMore() {
        launch()
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let row = el("sidebar-claude")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no Claude row in More")
        shot("phone-claude-more")
        row.tap()
        XCTAssertTrue(el("claude-input").waitForExistence(timeout: 10))
        sleep(2)
        shot("phone-claude-screen")
    }
}
