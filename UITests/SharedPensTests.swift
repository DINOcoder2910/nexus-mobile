import XCTest

/// The pens shared with the laptop through the data folder's nexus-pens.json (Sources/Boards/BoardTools.swift, NexusCore Pens):
/// a board opened with the laptop's file (`-NexusTestSharedPens`, TestHooks.sharedPens) shows the pen red at Bold, draws Bold at the
/// width set on the laptop, the highlighter at Fine and the eraser on part of a stroke; a colour picked here is written to the file a
/// moment later, laid over it, keeping a part only the laptop knows. The iPhone's twin is SharedPensPhoneTests.
final class SharedPensTests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
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

    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            ?? app.buttons[label].firstMatch
    }
    func colours() -> XCUIElementQuery { app.buttons.matching(NSPredicate(format: "label == 'Colour'")) }
    func picked(_ e: XCUIElement) -> Bool { (e.value as? String ?? "").lowercased().contains("picked") }

    /// Taps the element until `done` holds (three tries, two seconds each).
    func tap(until done: @escaping () -> Bool, _ element: @escaping () -> XCUIElement) {
        for attempt in 0..<3 {
            let e = element()
            if e.isHittable { e.tap() } else { print("UISTEP tap \(attempt): \(e.label) not hittable") }
            for _ in 0..<8 { if done() { return }; usleep(250_000) }
        }
    }

    /// As PenOptionsTests: the floating sidebar put away so the bar's row is all on screen.
    func hideSidebar() {
        let width = app.windows.firstMatch.frame.width
        for _ in 0..<4 {
            let close = app.buttons.matching(NSPredicate(format: "label == 'Close the board'")).allElementsBoundByIndex.first { $0.exists && $0.frame.width > 0 }
            guard let close, close.frame.minX > width * 0.1 else { return }
            let sides = app.buttons.matching(identifier: "Sidebar").allElementsBoundByIndex.filter { $0.exists }
            guard let side = sides.max(by: { $0.frame.minX < $1.frame.minX }) else { return }
            side.tap()
            sleep(2)
        }
    }

    func board() -> XCUIElement {
        let all = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        return all.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) ?? app.windows.firstMatch
    }

    func file() -> String { app.staticTexts["pens-file"].firstMatch.label }

    func testTheLaptopsPensAndAChangeWrittenBack() {
        app.launchArguments = ["-NexusTestPdfBoard", "-NexusTestSharedPens", "-NexusTestPenProbe", "-board.fingersDraw", "YES", "-board.dark", "never",
                               "-board.penKind", "pen"]
        app.launch()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        hideSidebar()
        tap(until: { self.button("Pen").isSelected }) { self.button("Pen") }
        XCTAssertTrue(colours().count == 10, "the pen should have ten colours")

        // the laptop's pen: the third colour (red), at Bold
        XCTAssertTrue(picked(colours().element(boundBy: 2)), "the laptop's red should be picked: \(colours().element(boundBy: 2).value ?? "")")
        XCTAssertTrue(picked(button("Bold")), "the laptop's Bold should be picked")
        let y = 0.3
        board().coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: y))
            .press(forDuration: 0.1, thenDragTo: board().coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y + 0.03)), withVelocity: XCUIGestureVelocity(250), thenHoldForDuration: 0)
        let probe = app.staticTexts["pen-probe"].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "no probe")
        print("UISTEP probe \(probe.label)")
        // Bold set to 8 on the laptop (its own is 6): the pen draws 8 here too
        XCTAssertTrue(probe.label.hasSuffix("tool 8.00"), "Bold should draw at the laptop's 8: \(probe.label)")
        shot("pens-shared-pen")

        // the highlighter at the laptop's Fine, in its second colour
        tap(until: { self.colours().count == 8 }) { self.button("Highlighter") }
        XCTAssertTrue(picked(button("Fine")), "the laptop's Fine should be picked for the highlighter")
        XCTAssertTrue(picked(colours().element(boundBy: 1)), "the laptop's green should be picked for the highlighter")
        // the eraser on part of a stroke: its widths show
        tap(until: { self.button("Eraser").isSelected }) { self.button("Eraser") }
        XCTAssertTrue(app.buttons["Part of a stroke"].firstMatch.waitForExistence(timeout: 3) && app.buttons["Part of a stroke"].firstMatch.isSelected,
                      "the eraser should be on part of a stroke")

        // a colour picked here goes into the file, laid over it: the laptop's part it doesn't know stays, and so do its widths
        tap(until: { self.button("Pen").isSelected }) { self.button("Pen") }
        tap(until: { self.picked(self.colours().element(boundBy: 3)) }) { self.colours().element(boundBy: 3) }
        var n = 0
        while !file().contains("#188038FF") && n < 10 { sleep(1); n += 1 }
        print("UISTEP file \(file())")
        XCTAssertTrue(file().contains("\"pen\": { \"color\": \"#188038FF\", \"step\": 4 }"), "the green pen should be written: \(file())")
        XCTAssertTrue(file().contains("\"ring\""), "the laptop's own part should stay: \(file())")
        XCTAssertTrue(file().contains("\"eraser\": \"part\""), "the eraser should stay: \(file())")
        XCTAssertTrue(file().contains("8.0") || file().contains(" 8,") || file().contains(" 8 "), "the laptop's Bold should stay: \(file())")
        shot("pens-shared-written")
        app.terminate()
    }
}

/// The same file on the iPhone: its pen row shows the laptop's red at Bold. Skips itself on the iPad.
final class SharedPensPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testPhoneTakesTheLaptopsPens() {
        app.launchArguments = ["-NexusTestPdfBoard", "-NexusTestSharedPens", "-board.tool", "pen", "-board.penKind", "pen"]
        app.launch()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        let colours = app.buttons.matching(NSPredicate(format: "label == 'Colour'"))
        XCTAssertEqual(colours.count, 10)
        XCTAssertTrue((colours.element(boundBy: 2).value as? String ?? "").contains("picked"), "the laptop's red should be picked")
        XCTAssertTrue((app.buttons["Bold"].firstMatch.value as? String ?? "") == "Picked", "the laptop's Bold should be picked")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "phone-pens-shared"
        a.lifetime = .keepAlways
        add(a)
    }
}
