import XCTest

/// Board links' look (the bridge, Sources/Boards/BoardController+Links.swift) on a board the app makes itself (`-NexusTestLinksBoard`,
/// Sources/Common/TestHooks.swift), light and dark, with Show all links on; then the Links list, whose Done must be readable. The
/// screenshots ("links-…") are printed in the ui-check log.
final class LinksTests: XCTestCase {
    var app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    func run(dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-NexusTestLinksBoard", "-board.links.showAll", "YES", "-board.dark", dark ? "always" : "never"]
        app.launch()
        let mode = dark ? "dark" : "light"
        let links = app.buttons["board.links.menu"].firstMatch
        XCTAssertTrue(links.waitForExistence(timeout: 30), "the links board didn't open")
        sleep(2)
        // the sidebar can still be over the board when the app opens straight into it: put it away
        if app.buttons["Today"].firstMatch.isHittable { app.buttons["Sidebar"].firstMatch.tap(); sleep(1) }
        shot("links-board-\(mode)")
        links.tap()
        let all = app.descendants(matching: .any)["All links…"].firstMatch
        if !all.waitForExistence(timeout: 10) { shot("links-menu-\(mode)") }
        XCTAssertTrue(all.exists, "no All links… in the Links menu")
        all.tap()
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "the Links list has no Done")
        sleep(1)
        shot("links-list-\(mode)")
        done.tap()
    }

    func testLinksLight() { run(dark: false) }
    func testLinksDark() { run(dark: true) }
}
