import XCTest
import UIKit

/// The last iPad and iPhone extras, on the UI check's made-up hub (Sources/Common/TestHooks+Extras.swift; nothing reaches a network):
/// - a block linked to a Google Doc ("Redox notes"): the board's Google Docs panel with the hub's status and the Doc's versions, Sync now;
/// - a task's Activity (the Redox worksheet's panel): the hub's history in the laptop's words ("Renamed from “Redox sheet”");
/// - Settings › Home Screen widgets: the widget key to copy;
/// - on the iPhone, the board's tool pill (the Nov 20 mockup): the picked tool tapped again opens its sheet, + holds Insert.
/// iPad here, the iPhone in ExtrasPhoneTests below; the "extras-…" screenshots are printed into the ui-check log.
class ExtrasTests: XCTestCase {
    var app = XCUIApplication()
    class var forPhone: Bool { false }
    var device: String { Self.forPhone ? "phone" : "ipad" }

    override func setUpWithError() throws {
        let phone = UIDevice.current.userInterfaceIdiom == .phone
        try XCTSkipIf(phone != Self.forPhone, Self.forPhone ? "iPhone only" : "iPad only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = Self.forPhone ? .portrait : .landscapeLeft
    }

    func launch(_ args: [String], dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = args + (dark ? ["-NexusTestDark"] : [])
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 8) { sample.tap() }
    }

    func shot(_ name: String) {
        let full = "extras-\(device)-" + name
        print("UISTEP \(Date().timeIntervalSince1970) \(full)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = full
        a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func text(containing words: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    func gone(_ e: XCUIElement, _ timeout: TimeInterval = 5) -> Bool {
        XCTWaiter().wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: e)], timeout: timeout) == .completed
    }

    /// Swipes up (then down) until `e` is on screen and can be tapped, bounded.
    func reveal(_ e: XCUIElement) {
        var n = 0
        while !(e.exists && e.isHittable) && n < 8 { app.swipeUp(velocity: .slow); n += 1 }
        n = 0
        while !(e.exists && e.isHittable) && n < 8 { app.swipeDown(velocity: .slow); n += 1 }
    }

    // MARK: Google Docs

    func googleDocs(dark: Bool) {
        let mode = dark ? "dark" : "light"
        launch(["-NexusTestExtras"], dark: dark)
        // the hook opens the board, then the block's panel
        let head = el("gdocs-head")
        let up = head.waitForExistence(timeout: 60)
        shot("gdocs-\(mode)")
        XCTAssertTrue(up, "the Google Docs panel didn't open")
        XCTAssertEqual(head.label, "Redox notes", "the panel doesn't name the linked Doc")
        XCTAssertTrue(text(containing: "In step").waitForExistence(timeout: 15), "the panel doesn't show the hub's last round")
        let versions = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You'")).firstMatch
        reveal(versions)
        XCTAssertTrue(versions.waitForExistence(timeout: 15), "the Doc's recent edits didn't show")
        shot("gdocs-versions-\(mode)")
        let sync = el("gdocs-sync")
        reveal(sync)
        XCTAssertTrue(sync.exists, "no Sync now")
        if sync.exists { sync.tap() }
        sleep(2)
        XCTAssertEqual(el("gdocs-head").label, "Redox notes", "Sync now lost the link")
        let done = app.navigationBars["Google Docs"].buttons["Done"].firstMatch
        if done.exists { done.tap() }
        sleep(1)
    }

    // MARK: Activity and widgets

    func activity(dark: Bool) {
        let mode = dark ? "dark" : "light"
        launch(["-NexusTestExtrasTask"], dark: dark)
        let toggle = el("panel-activity-toggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 40), "the Redox worksheet's panel didn't open")
        reveal(toggle)
        toggle.tap()
        let renamed = text(containing: "Renamed from")
        let shown = renamed.waitForExistence(timeout: 20)
        reveal(renamed)
        shot("activity-\(mode)")
        XCTAssertTrue(shown, "the Activity didn't show the hub's history")
        XCTAssertTrue(renamed.label.contains("Redox sheet"), "the rename doesn't name the old title: \(renamed.label)")
        XCTAssertTrue(renamed.label.contains("Claude"), "the rename doesn't say who: \(renamed.label)")
        XCTAssertTrue(text(containing: "Added").exists, "no Added row")
    }

    func openSettings() {
        if Self.forPhone {
            app.tabBars.buttons["More"].tap()
            let row = app.buttons["Settings"].firstMatch
            var n = 0
            while !(row.exists && row.isHittable) && n < 8 { app.collectionViews.firstMatch.swipeUp(); n += 1 }
            row.tap()
        } else {
            let settings = app.buttons["sidebar-Settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 10), "no Settings icon at the sidebar's foot")
            settings.tap()
        }
        sleep(2)
    }

    func widgets(dark: Bool) {
        let mode = dark ? "dark" : "light"
        // close the task panel
        for name in ["Done", "Close"] where app.buttons[name].firstMatch.exists { app.buttons[name].firstMatch.tap(); sleep(1); break }
        openSettings()
        let copy = el("widget-copy-key")
        var n = 0
        while !(copy.exists && copy.isHittable) && n < 16 { app.swipeUp(velocity: .slow); n += 1 }
        XCTAssertTrue(copy.exists, "Settings has no Home Screen widgets section (is the extension in the app?)")
        guard copy.exists else { shot("widgets-missing-\(mode)"); return }
        copy.tap()
        XCTAssertTrue(app.buttons["Widget key copied"].firstMatch.waitForExistence(timeout: 5), "the key wasn't copied")
        XCTAssertTrue(el("widget-on").waitForExistence(timeout: 5), "no Keep the widgets up to date")
        shot("widgets-\(mode)")
    }

    func testGoogleDocsLight() { googleDocs(dark: false) }
    func testGoogleDocsDark() { googleDocs(dark: true) }
    func testActivityAndWidgetsLight() { activity(dark: false); widgets(dark: false) }
    func testActivityAndWidgetsDark() { activity(dark: true); widgets(dark: true) }
}

final class ExtrasPhoneTests: ExtrasTests {
    override class var forPhone: Bool { true }

    /// The board's tool pill: the pen picked, tapped again for its sheet (kind, Width, Colour), the eraser's sheet, and + for Insert.
    func pill(dark: Bool) {
        let mode = dark ? "dark" : "light"
        launch(["-NexusTestExtras", "-board.tool", "pen", "-board.penKind", "pen"], dark: dark)
        // the hook opens the block's Google Docs panel over the board: close it first
        // (its look on the iPhone: the iPad's own test checks the rest of the panel)
        if el("gdocs-head").waitForExistence(timeout: 60) {
            sleep(1)
            shot("gdocs-\(mode)")
            XCTAssertEqual(el("gdocs-head").label, "Redox notes", "the panel doesn't name the linked Doc")
            let done = app.navigationBars["Google Docs"].buttons["Done"].firstMatch
            if done.exists { done.tap() }
            sleep(2)
        }
        let pill = el("phone-tool-pill")
        XCTAssertTrue(pill.waitForExistence(timeout: 20), "no tool pill on the iPhone's board")
        shot("pill-\(mode)")
        let pen = app.buttons["phone-tool-pen"].firstMatch
        XCTAssertTrue(pen.exists && pen.isSelected, "the pen isn't shown picked in the pill")
        pen.tap()
        let sheet = el("phone-tool-sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the picked pen tapped again didn't open its sheet")
        sleep(1)
        shot("pill-pen-sheet-\(mode)")
        XCTAssertTrue(el("phone-tool-widths").exists, "the pen's sheet has no widths")
        XCTAssertTrue(el("phone-tool-colours").exists, "the pen's sheet has no colours")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Colour'")).count, 10)
        let done = el("phone-tool-sheet-done")
        if done.exists { done.tap() }
        XCTAssertTrue(gone(sheet), "Done didn't close the sheet")
        // the eraser: one tap picks it, the next opens its sheet
        let eraser = app.buttons["phone-tool-eraser"].firstMatch
        eraser.tap()
        sleep(1)
        XCTAssertTrue(eraser.isSelected, "the eraser wasn't picked")
        eraser.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the eraser's sheet didn't open")
        sleep(1)
        shot("pill-eraser-sheet-\(mode)")
        if done.exists { done.tap() }
        _ = gone(sheet)
        // + : Insert
        let plus = el("phone-tool-plus")
        XCTAssertTrue(plus.exists, "no + in the pill")
        plus.tap()
        sleep(1)
        shot("pill-insert-\(mode)")
        XCTAssertTrue(app.buttons["Insert space"].firstMatch.exists || app.staticTexts["Insert space"].firstMatch.exists, "+ has no Insert space")
    }

    // the panel is checked and pictured by pill() on the iPhone: one launch less each
    override func testGoogleDocsLight() {}
    override func testGoogleDocsDark() {}
    func testPillLight() { pill(dark: false) }
    func testPillDark() { pill(dark: true) }
}
