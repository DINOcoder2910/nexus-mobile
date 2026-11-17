import XCTest

/// Insert space follows the drag (Sources/Boards/SpaceLive.swift): on a board as full as a long lesson's (4000 handwritten strokes
/// over a PDF page), the app drags Insert space itself, one step per screen refresh (`-NexusTestSpaceDrag`,
/// BoardController+SpaceBench.swift), holding still at each stage. This takes a picture at each stage (mid-drag: the ink and the
/// PDF page already moved, the room open); the timings (the start of a drag, each step, the worst frame, letting go) go to
/// `diagnostics/space-bench.txt`, which the UI check prints.
///
/// It never reads the app's elements: on a board this full that query times out. The bench and the test talk by Darwin
/// notifications instead (`app.nexus.spacebench.<phase>` from the app, every second; `.go` from the test, and the bench starts
/// on its own a minute after it is ready if that never arrives), and the pictures are of the screen.
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

    /// Whether the bench said `stage` within `seconds` (it says its stage again every second, so a fresh short wait each time
    /// can't miss it).
    func heard(_ stage: String, within seconds: TimeInterval) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        repeat {
            let e = XCTDarwinNotificationExpectation(notificationName: "app.nexus.spacebench.\(stage)")
            if XCTWaiter().wait(for: [e], timeout: max(1, min(5, end.timeIntervalSinceNow))) == .completed { return true }
        } while Date() < end
        return false
    }

    /// Waits for the bench to reach a stage; says so in the log either way.
    @discardableResult
    func reach(_ stage: String, seconds: TimeInterval = 120) -> Bool {
        let ok = heard(stage, within: seconds)
        print("UISTEP SPACE \(ok ? "at" : "never reached") \(stage)")
        XCTAssertTrue(ok, "the bench didn't reach \(stage)")
        return ok
    }

    /// The app's first launch asks to send notifications: that alert would sit over the pictures.
    func answerAlert() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for name in ["Allow", "Don\u{2019}t Allow", "Don't Allow"] {
            let b = springboard.buttons[name].firstMatch
            if b.waitForExistence(timeout: 2) { b.tap(); print("UISTEP SPACE answered the alert"); return }
        }
    }

    func testInsertSpaceFollowsTheDrag() {
        // the app writes the big board and opens it (a minute or more in the simulator's debug build); answer the alert meanwhile
        var opened = false
        for _ in 0..<20 where !opened {
            answerAlert()
            opened = heard("ready", within: 20)
        }
        if !opened { shot("space-0 no bench") }
        XCTAssertTrue(opened, "the big board didn't open")
        guard opened else { return }
        answerAlert()
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName("app.nexus.spacebench.go" as CFString), nil, nil, true)
        let pictures = [("before", "space-1 before"), ("adding", "space-2 dragging down, not let go"), ("added", "space-3 let go"),
                        ("taking", "space-4 dragging up, not let go"), ("taken", "space-5 let go"),
                        ("dark", "space-6 dark board, dragging")]
        for (stage, name) in pictures {
            guard reach(stage, seconds: stage == "before" ? 240 : 120) else { shot("\(name) (late)"); return }
            sleep(stage == "before" ? 3 : 1)
            shot(name)
        }
        reach("done")
    }
}
