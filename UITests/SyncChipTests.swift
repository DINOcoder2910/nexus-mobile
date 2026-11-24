import XCTest

/// The sync chip (the Nexus repo's docs/sync.md "The sync chip"): at the foot of the iPad's sidebar and on top of the iPhone's More,
/// in the laptop's words, opening Settings. `-NexusTestSyncChip <state>` shows the chip as it would be with no hub; without it (every
/// other test: sync is off) there is no chip. Screenshots "sync-chip-…".
class SyncChipChecks: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }

    var pad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    func launch(_ state: String?) {
        app = XCUIApplication()
        app.launchArguments = state.map { ["-NexusTestSyncChip", $0] } ?? []
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 20) { sample.tap() }
        if pad {
            XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 20), "the sidebar isn't up")
        } else {
            let more = app.tabBars.buttons["More"]
            XCTAssertTrue(more.waitForExistence(timeout: 20), "no More tab")
            more.tap()
        }
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    var chip: XCUIElement { app.descendants(matching: .any)["sync-chip"].firstMatch }

    func checkTheChip() {
        XCUIDevice.shared.orientation = pad ? .landscapeLeft : .portrait
        let device = pad ? "ipad" : "iphone"
        for (state, words) in [("offline", "Offline · 3 waiting"), ("insync", "In sync"), ("syncing", "Syncing 3"), ("conflicts", "2 conflicts")] {
            launch(state)
            XCTAssertTrue(chip.waitForExistence(timeout: 15), "no sync chip for \(state)")
            XCTAssertEqual(chip.label, words)
            shot("sync-chip-\(device)-\(state)")
            app.terminate()
        }
        // a tap opens Settings, where Sync says more
        launch("problem")
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        XCTAssertEqual(chip.label, "Sync problem")
        chip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["Sync"].firstMatch.waitForExistence(timeout: 15) || app.staticTexts["Settings"].firstMatch.waitForExistence(timeout: 5),
                      "the chip didn't open Settings")
        shot("sync-chip-\(device)-opens-settings")
        app.terminate()
    }

    func checkNoChipWhileOff() {
        XCUIDevice.shared.orientation = pad ? .landscapeLeft : .portrait
        launch(nil)
        sleep(2)
        XCTAssertFalse(chip.exists, "sync is off in the sample: no chip")
    }
}

/// The iPad's chip, at the foot of the sidebar.
final class SyncChipTests: SyncChipChecks {
    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
        try super.setUpWithError()
    }

    func testTheChipSaysWhereSyncStands() { checkTheChip() }
    func testNoChipWhileSyncIsOff() { checkNoChipWhileOff() }
}

/// The iPhone's chip, on top of More.
final class SyncChipPhoneTests: SyncChipChecks {
    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
        try super.setUpWithError()
    }

    func testTheChipSaysWhereSyncStands() { checkTheChip() }
    func testNoChipWhileSyncIsOff() { checkNoChipWhileOff() }
}
