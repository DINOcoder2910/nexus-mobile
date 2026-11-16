import XCTest

/// Claude on the iPad (Nov 16 2026): Plan with Claude on Today, the conversation as the column beside a screen and as its own screen,
/// a look-up, a change card accepted and undone. Launched with -NexusClaudeDemo (canned replies made from what the app sends, on the
/// sample data). The screenshots ("claude-…") are printed in the claude-check log. Skips itself on the iPhone (ClaudeChatPhoneTests).
final class ClaudeChatUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
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

    func testPlanWithClaudeOnToday() {
        launch()
        let plan = app.buttons["plan-with-claude"].firstMatch
        XCTAssertTrue(plan.waitForExistence(timeout: 15), "no Plan with Claude on Today")
        shot("claude-ipad-today")
        plan.tap()
        XCTAssertTrue(el("plan-result").waitForExistence(timeout: 30), "Plan with Claude didn't finish")
        sleep(1)
        shot("claude-ipad-plan-placed")
        // the placement is saved at once; Undo puts the run back
        let undo = app.buttons["plan-undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo after placing")
        undo.tap()
        sleep(1)
        shot("claude-ipad-plan-undone")
    }

    func testTheConversationBesideAScreen() {
        launch()
        let column = app.buttons["claude-column"].firstMatch
        XCTAssertTrue(column.waitForExistence(timeout: 15), "no Claude button in the toolbar")
        column.tap()
        let input = el("claude-input")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "the Claude column didn't open")
        sleep(2)
        shot("claude-ipad-column-empty")

        input.tap()
        input.typeText("What's in my Inbox? Give the field trip form a deadline.")
        app.buttons["claude-send"].firstMatch.tap()
        let accept = app.buttons["change-accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 30), "no change card")
        sleep(1)
        shot("claude-ipad-column-change")
        accept.tap()
        XCTAssertTrue(app.buttons["change-undo"].firstMatch.waitForExistence(timeout: 10), "the change wasn't saved")
        shot("claude-ipad-column-saved")
    }

    func testTheClaudeScreen() {
        launch()
        let row = el("sidebar-claude")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no Claude row in the sidebar")
        row.tap()
        let commands = el("command-file-inbox")
        XCTAssertTrue(commands.waitForExistence(timeout: 10), "no commands on an empty conversation")
        sleep(2)
        shot("claude-ipad-screen-empty")
        commands.tap()
        XCTAssertTrue(app.buttons["change-accept"].firstMatch.waitForExistence(timeout: 30), "File my Inbox proposed nothing")
        sleep(1)
        shot("claude-ipad-screen-file-inbox")
        app.buttons["change-reject"].firstMatch.tap()
        sleep(1)
        shot("claude-ipad-screen-rejected")
    }
}
