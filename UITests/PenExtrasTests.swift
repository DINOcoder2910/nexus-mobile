import XCTest

/// The pen panel's extras on the iPad (Sources/Boards/BoardController+PenExtras.swift), as on the laptop: Copy from a stroke
/// (the eyedropper after the sizes), touch and hold a size to set its width (Save as my default), the Select tool's colours and
/// sizes restyling lassoed ink with Undo, and Insert › New page. Light and dark; the screenshots ("extras-…") are the preview.
/// XCUITest drags only in straight lines, so `-NexusTestLassoBox` makes a drag with the Select tool pick the strokes in its box.
final class PenExtrasTests: XCTestCase {
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

    func launch(dark: Bool) {
        app = XCUIApplication()
        app.launchArguments = ["-NexusTestPdfBoard", "-NexusTestPenProbe", "-NexusTestLassoBox", "-board.fingersDraw", "YES",
                               "-board.dark", dark ? "always" : "never", "-board.penKind", "pen"]
        app.launch()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        hideSidebar()
        tap(until: { self.button("Pen").isSelected }) { self.button("Pen") }
        XCTAssertTrue(button("Pen").isSelected, "the Pen should be picked")
    }

    /// The sidebar floats over the board in landscape: put it away with the board bar's Sidebar button (as PenOptionsTests).
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
        XCTFail("the sidebar stayed over the board")
    }

    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            ?? app.buttons[label].firstMatch
    }

    func colours(_ label: String = "Colour") -> XCUIElementQuery { app.buttons.matching(NSPredicate(format: "label == %@", label)) }

    /// The board's canvas: the biggest scroll view. Not "hittable": while Copy from a stroke's cover is over it, isHittable is
    /// false, and the biggest hittable one was the bar's colour row (the Nov 23 failure, docs/ci-lessons.md).
    func board() -> XCUIElement {
        let all = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && !$0.frame.isEmpty }
        return all.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) ?? app.windows.firstMatch
    }

    func tap(until done: @escaping () -> Bool, _ element: @escaping () -> XCUIElement) {
        for attempt in 0..<3 {
            let e = element()
            if e.isHittable { e.tap() } else { print("UISTEP tap \(attempt): \(e.label) not hittable") }
            for _ in 0..<8 { if done() { return }; usleep(250_000) }
            print("UISTEP tap \(attempt) on \(e.label) didn't take")
        }
    }

    func picked(_ e: XCUIElement) -> Bool { (e.value as? String ?? "").lowercased().contains("picked") }

    /// A line across the board at `y` (0 to 1), slowly, as a hand writes.
    func line(_ y: CGFloat, from x0: CGFloat = 0.4, to x1: CGFloat = 0.7) {
        let from = board().coordinate(withNormalizedOffset: CGVector(dx: x0, dy: y))
        from.press(forDuration: 0.1, thenDragTo: board().coordinate(withNormalizedOffset: CGVector(dx: x1, dy: y)),
                   withVelocity: XCUIGestureVelocity(250), thenHoldForDuration: 0)
        usleep(400_000)
    }

    /// The probe's tool width for the last stroke ("probe <ink> stroke <w> tool <w>").
    func toolWidth() -> Double? {
        let p = app.staticTexts["pen-probe"].firstMatch
        guard p.waitForExistence(timeout: 3) else { return nil }
        let f = p.label.split(separator: " ").map(String.init)
        return f.count >= 6 ? Double(f[5]) : nil
    }

    func pick(colour i: Int, width: String) {
        tap(until: { self.picked(self.button(width)) }) { self.button(width) }
        let c = colours().element(boundBy: i)
        if c.isHittable { c.tap() }
        usleep(300_000)
    }

    func run(dark: Bool) {
        let theme = dark ? "dark" : "light"
        launch(dark: dark)
        // a red Bold line and a blue Fine one
        pick(colour: 2, width: "Bold")
        line(0.25)
        pick(colour: 1, width: "Fine")
        line(0.45)
        XCTAssertTrue(picked(colours().element(boundBy: 1)), "blue should be picked before copying")

        // Copy from a stroke: the note, then a tap on the red line, its card, Draw with it
        let copy = app.buttons["pen-copy-stroke"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "no Copy from a stroke")
        copy.tap()
        XCTAssertTrue(app.staticTexts["copy-stroke-note"].waitForExistence(timeout: 5), "no 'Tap any stroke' note")
        shot("extras-copy-note-\(theme)")
        board().coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.25)).tap()
        let words = app.staticTexts["copy-stroke-words"].firstMatch
        XCTAssertTrue(words.waitForExistence(timeout: 8), "the stroke's card didn't open")
        print("UISTEP copied: \(words.label)")
        XCTAssertTrue(words.label.hasPrefix("Pen ·") && words.label.hasSuffix("· red"), "the card says \(words.label)")
        shot("extras-copy-card-\(theme)")
        app.buttons["copy-stroke-draw"].firstMatch.tap()
        sleep(1)
        XCTAssertTrue(picked(colours().element(boundBy: 2)), "Draw with it should pick red")
        XCTAssertTrue(picked(button("Bold")), "Draw with it should pick the Bold size (the stroke's)")

        // hold a size: its width on a slider; Save as my default makes Thick draw wider
        pick(colour: 3, width: "Thick")
        line(0.6)
        let before = toolWidth() ?? 0
        button("Thick").press(forDuration: 1.2)
        let slider = app.sliders["size-edit-slider"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 8), "holding Thick didn't open its size")
        slider.adjust(toNormalizedSliderPosition: 0.75)
        sleep(1)
        print("UISTEP size: \(app.staticTexts["size-edit-value"].firstMatch.label)")
        shot("extras-size-edit-\(theme)")
        app.buttons["size-edit-save"].firstMatch.tap()
        sleep(1)
        line(0.7)
        let after = toolWidth() ?? 0
        print("UISTEP Thick before \(before) after \(after)")
        XCTAssertGreaterThan(after, before, "Save as my default should make Thick wider")
        // Reset sizes puts it back
        button("Thick").press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["size-edit-reset"].firstMatch.waitForExistence(timeout: 8), "no Reset sizes")
        app.buttons["size-edit-reset"].firstMatch.tap()
        sleep(1)
        line(0.8)
        XCTAssertEqual(toolWidth() ?? 0, before, accuracy: 0.05, "Reset sizes should put Thick back")

        // the Select tool: drag over the blue line (its box), then a colour and a size change it, with Undo
        tap(until: { self.button("Select").isSelected }) { self.button("Select") }
        let from = board().coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.41))
        from.press(forDuration: 0.1, thenDragTo: board().coordinate(withNormalizedOffset: CGVector(dx: 0.74, dy: 0.49)))
        let hint = app.staticTexts["lasso-hint"].firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 5), "no hint in the Select tool's row")
        let one = NSPredicate(format: "label BEGINSWITH '1 stroke picked'")
        XCTAssertTrue(app.staticTexts.matching(one).firstMatch.waitForExistence(timeout: 5), "the lasso should hold the blue line: \(hint.label)")
        let green = colours("Change to this colour").element(boundBy: 3)
        XCTAssertTrue(green.waitForExistence(timeout: 5), "no colours in the Select tool's row")
        green.tap()
        let toast = app.staticTexts["undo-toast-words"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "no note after the change")
        XCTAssertEqual(toast.label, "Changed 1 stroke to green")
        button("Change to Extra bold").tap()
        sleep(1)
        print("UISTEP restyle: \(toast.label)")
        XCTAssertTrue(toast.label.hasPrefix("Changed 1 stroke to "), toast.label)
        shot("extras-lasso-restyle-\(theme)")
        app.buttons["undo-toast-undo"].firstMatch.tap()
        sleep(1)
        shot("extras-lasso-undone-\(theme)")

        // Insert › New page: an empty board beside this one, opened in its place
        if !dark {
            tap(until: { self.button("New page").exists }) { self.button("Insert") }
            let page = button("New page")
            XCTAssertTrue(page.waitForExistence(timeout: 5), "no New page in Insert")
            shot("extras-insert-row")
            page.tap()
            let title = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Untitled'")).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 15), "the new page didn't open")
            sleep(2)
            shot("extras-new-page")
        }
        app.terminate()
    }

    func testPenExtrasLight() { run(dark: false) }
    func testPenExtrasDark() { run(dark: true) }
}
