import XCTest
import PencilKit

/// The pens' colours and widths in the board's bar (Sources/Boards/BoardTools.swift, BoardBar.swift): ten pen colours and eight
/// highlighter colours, the laptop's, and six widths a tool, Extra fine to Extra bold. A line is written at each width in a different
/// colour, light and dark. The screenshots ("pens-…") are printed in the UI check log; the iPhone's are in PenOptionsPhoneTests.
final class PenOptionsTests: XCTestCase {
    var app = XCUIApplication()
    static let widths = ["Extra fine", "Fine", "Medium", "Thick", "Bold", "Extra bold"]

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

    func launch(dark: Bool, tool: String = "pen") {
        app = XCUIApplication()
        // fingers draw (the simulator has no Pencil); a fresh set of tools; each stroke's width shown in the probe label
        app.launchArguments = ["-NexusTestPdfBoard", "-NexusTestPenProbe", "-board.fingersDraw", "YES", "-board.dark", dark ? "always" : "never",
                               "-board.tool", tool, "-board.penKind", "pen"]
        app.launch()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        hideSidebar()
    }

    /// The sidebar floats over the board in landscape: put it away with the board bar's Sidebar button (the rightmost of the two).
    func hideSidebar() {
        let width = app.windows.firstMatch.frame.width
        for _ in 0..<3 {
            let planner = app.staticTexts["Planner"].firstMatch
            guard planner.exists, planner.frame.maxX > 0, planner.frame.minX < width * 0.3 else { return }
            let sides = app.buttons.matching(identifier: "Sidebar").allElementsBoundByIndex.filter { $0.exists }
            guard let side = sides.max(by: { $0.frame.minX < $1.frame.minX }) else { return }
            side.tap()
            sleep(2)
        }
    }

    func colours() -> XCUIElementQuery { app.buttons.matching(NSPredicate(format: "label == 'Colour'")) }

    /// The button with this label that can be tapped (the bar's compact layout keeps a hidden copy of the tool buttons).
    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            ?? app.buttons[label].firstMatch
    }

    /// The board's canvas: the biggest scroll view on screen.
    func board() -> XCUIElement {
        let all = app.scrollViews.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        return all.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) ?? app.windows.firstMatch
    }

    /// Taps the element until `done` holds (three tries, two seconds each).
    func tap(until done: @escaping () -> Bool, _ element: @escaping () -> XCUIElement) {
        for attempt in 0..<3 {
            let e = element()
            if e.isHittable { e.tap() } else { print("UISTEP tap \(attempt): \(e.label) not hittable") }
            for _ in 0..<8 { if done() { return }; usleep(250_000) }
            print("UISTEP tap \(attempt) on \(e.label) didn't take")
        }
    }

    /// The probe's "probe <ink> stroke <width> tool <width>" for the last stroke drawn.
    func probe() -> (ink: String, stroke: Double, tool: Double)? {
        let p = app.staticTexts["pen-probe"].firstMatch
        guard p.waitForExistence(timeout: 3) else { return nil }
        let f = p.label.split(separator: " ").map(String.init)
        guard f.count >= 6, let s = Double(f[3]), let t = Double(f[5]) else { return nil }
        return (f[1], s, t)
    }

    /// One line at each width, each in the next colour of the row, down the board; the widths written must grow.
    @discardableResult
    func writeLines(_ count: Int, ink: String) -> [Double] {
        var written: [Double] = [], strokes: [Double] = []
        for (i, w) in Self.widths.enumerated() {
            let wb = button(w)
            XCTAssertTrue(wb.waitForExistence(timeout: 5), "no \(w) width")
            // the bar is rebuilt now and then (a stroke landing, the zoom): a tap that lands as it is rebuilt is lost, so tap again
            tap(until: { (self.button(w).value as? String ?? "").contains("Picked") }) { self.button(w) }
            let c = colours().element(boundBy: i % count)
            if c.isHittable { c.tap() }
            let y = 0.18 + 0.1 * CGFloat(i)
            let from = board().coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: y))
            // slowly, as a hand writes: the pen's ink thins when it moves fast
            from.press(forDuration: 0.1, thenDragTo: board().coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y + 0.03)),
                       withVelocity: XCUIGestureVelocity(250), thenHoldForDuration: 0)
            usleep(300_000)
            let p = probe()
            print("UISTEP probe \(w): \(p.map { "\($0.ink) stroke \($0.stroke) tool \($0.tool)" } ?? "none")")
            XCTAssertTrue(p?.ink.hasSuffix(ink) ?? false, "\(w) wrote with \(p?.ink ?? "nothing"), not \(ink)")
            written.append(p?.tool ?? 0)
            strokes.append(p?.stroke ?? 0)
        }
        for i in written.indices.dropFirst() { XCTAssertGreaterThan(written[i], written[i - 1], "\(Self.widths[i]) isn't wider than \(Self.widths[i - 1]): \(written)") }
        // the strokes themselves: the highlighter's follow the width; the pen's, written with a simulated finger, come out about
        // the same at every width on the simulator (PencilKit's pen sets a finger's width itself), so they are only logged
        if ink == "marker" {
            for i in strokes.indices.dropFirst() { XCTAssertGreaterThan(strokes[i], strokes[i - 1], "the \(Self.widths[i]) stroke isn't wider: \(strokes)") }
        }
        return written
    }

    func testPenColoursAndWidths() {
        // what PencilKit allows each ink (the widths are kept inside these; BoardTools.drawnWidths)
        for (n, ink) in [("pen", PKInkingTool.InkType.pen), ("monoline", .monoline), ("fountain", .fountainPen), ("pencil", .pencil), ("marker", .marker)] {
            print("UISTEP width range \(n): \(ink.validWidthRange)")
        }
        launch(dark: false)
        XCTAssertEqual(colours().count, 10, "the pen should have ten colours")
        for w in Self.widths { XCTAssertTrue(app.buttons[w].firstMatch.exists, "no \(w) width") }
        writeLines(10, ink: "pen")
        shot("pens-pen-light")

        // the Highlighter, tapped where it shows in the bar
        let hl = button("Highlighter")
        XCTAssertTrue(hl.waitForExistence(timeout: 5), "no Highlighter tool")
        tap(until: { self.colours().count == 8 }) { self.button("Highlighter") }
        XCTAssertEqual(colours().count, 8, "tapping Highlighter should show its eight colours")
        if colours().count != 8 {
            // the tap didn't take: start on the highlighter instead, to see its row and widths all the same
            shot("pens-highlighter-picked")
            app.terminate()
            launch(dark: false, tool: "highlighter")
            XCTAssertEqual(colours().count, 8, "the highlighter should have eight colours")
        }
        writeLines(8, ink: "marker")
        shot("pens-highlighter-light")
        app.terminate()
    }

    func testPenColoursAndWidthsDark() {
        launch(dark: true)
        XCTAssertEqual(colours().count, 10)
        writeLines(10, ink: "pen")
        shot("pens-pen-dark")
        app.terminate()
    }
}

/// The same row on the iPhone: it scrolls sideways under the board's bar. Skips itself on the iPad.
final class PenOptionsPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    func testPhonePenRow() {
        app.launchArguments = ["-NexusTestPdfBoard", "-board.tool", "pen", "-board.penKind", "pen"]
        app.launch()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 30), "the board didn't open")
        sleep(3)
        let colours = app.buttons.matching(NSPredicate(format: "label == 'Colour'"))
        XCTAssertEqual(colours.count, 10)
        let first = colours.element(boundBy: 0)
        let from = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // a line at the Extra bold width
        let bold = app.buttons["Extra bold"].firstMatch
        XCTAssertTrue(bold.exists, "no Extra bold width")
        shot("phone-pens-row")
        var tries = 0
        while !bold.isHittable && tries < 4 { from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: -250, dy: 0))); tries += 1; sleep(1) }
        if bold.isHittable { bold.tap() }
        shot("phone-pens-row-scrolled")
    }
}
