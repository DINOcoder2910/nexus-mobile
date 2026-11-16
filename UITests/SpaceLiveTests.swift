import XCTest

/// Insert space follows the drag (Sources/Boards/SpaceLive.swift): on a board as full as a long lesson's (4000 handwritten strokes
/// over a PDF page), the app drags Insert space itself, one step per screen refresh (`-NexusTestSpaceDrag`,
/// BoardController+SpaceBench.swift), holding still at each stage. This takes a picture at each stage (mid-drag: the ink and the
/// PDF page already moved, the room open) and prints the timings: the start of a drag, each step, the worst frame, letting go.
final class SpaceLiveTests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-NexusTestBigBoard", "-NexusTestSpaceDrag"]
        app.launch()
    }

    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
    }

    /// Waits for the bench's label to reach `phase`; returns its text.
    @discardableResult
    func wait(for phase: String, _ bench: XCUIElement, seconds: Int = 120) -> String {
        var tries = 0
        while !bench.label.contains("phase \(phase)") && tries < seconds { sleep(1); tries += 1 }
        XCTAssertTrue(bench.label.contains("phase \(phase)"), "the bench didn't reach \(phase): \(bench.label)")
        return bench.label
    }

    func testInsertSpaceFollowsTheDrag() {
        let bench = app.staticTexts["space-bench"].firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 300), "the big board didn't open")
        if app.staticTexts["Planner"].firstMatch.exists, app.staticTexts["Planner"].firstMatch.isHittable {
            let side = app.buttons["Sidebar"].firstMatch
            if side.exists { side.tap() }
        }
        wait(for: "before", bench, seconds: 240)
        sleep(2)
        shot("space-1 before")
        wait(for: "adding", bench)
        shot("space-2 dragging down, not let go")
        wait(for: "added", bench)
        shot("space-3 let go")
        wait(for: "taking", bench)
        shot("space-4 dragging up, not let go")
        wait(for: "taken", bench)
        shot("space-5 let go")
        wait(for: "dark", bench)
        shot("space-6 dark board, dragging")
        let text = wait(for: "done", bench)
        for line in text.split(separator: "\n") { print("UISTEP SPACE \(line)") }
    }
}
