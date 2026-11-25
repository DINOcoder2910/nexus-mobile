import XCTest
import UIKit

/// Drop on the iPad (this class) and the iPhone (DropPhoneTests), on sample data with Drop/ as a sync leaves it
/// (-NexusTestDrop, Sources/Common/TestHooks.swift `dropFiles`: a photo and a PDF from Duo, notes from the other iPad or iPhone, a
/// sheet from the G14, a photo sent from here): the sidebar counts the arrivals, the screen says who sent each file, a tap shows it,
/// holding gives Share and Delete, and Delete takes it away. "drop-…" / "phone-drop-…" screenshots are printed in ui-check's log.
class DropTests: XCTestCase {
    let app = XCUIApplication()
    var phone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    class var forPhone: Bool { false }

    override func setUpWithError() throws {
        try XCTSkipIf(phone != Self.forPhone, Self.forPhone ? "iPhone only" : "iPad only")
        continueAfterFailure = true
        XCUIDevice.shared.orientation = phone ? .portrait : .landscapeLeft
    }

    func launch(_ extra: [String] = []) {
        app.launchArguments = ["-NexusTestDrop"] + extra
        app.launch()
        // the hook makes the sample itself; a cold simulator may still show the first screen for a moment (ci-lessons, Nov 22)
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 5) { sample.tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let ask = springboard.alerts.firstMatch
        if ask.waitForExistence(timeout: 4) { ask.buttons.element(boundBy: 0).tap() }
    }

    func shot(_ base: String) {
        let name = phone ? "phone-" + base : base
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// Scrolls the screen's list until `e` shows (bounded, both ways).
    func reveal(_ e: XCUIElement, _ n: Int = 8) {
        var tries = 0
        while !(e.exists && e.isHittable) && tries < n { app.swipeUp(velocity: .slow); tries += 1 }
        tries = 0
        while !(e.exists && e.isHittable) && tries < n { app.swipeDown(velocity: .slow); tries += 1 }
    }

    /// The sidebar's Drop row (under More on the iPhone), shown, then opened.
    func openDrop(_ shotName: String? = nil) {
        if phone {
            let more = app.tabBars.buttons["More"]
            XCTAssertTrue(more.waitForExistence(timeout: 20), "no More tab")
            more.tap()
        }
        var row = app.buttons["sidebar-drop"].firstMatch
        if !row.waitForExistence(timeout: 15) { row = app.buttons["Drop"].firstMatch }
        let list = app.collectionViews.firstMatch
        var swipes = 0
        while !(row.exists && row.isHittable) && swipes < 8 { list.swipeUp(); swipes += 1 }
        XCTAssertTrue(row.exists, "no Drop row in the sidebar")
        if let shotName { shot(shotName) }
        row.tap()
        XCTAssertTrue(app.buttons["drop-photos"].firstMatch.waitForExistence(timeout: 15), "the Drop screen didn't open")
    }

    func item(_ name: String) -> XCUIElement { app.buttons["drop-item-\(name)"].firstMatch }

    func testDrop() {
        launch()
        openDrop("drop-1-sidebar")

        // who sent each file, and what is new
        let photo = item("IMG_0042.jpg")
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "the photo from Duo isn't listed")
        XCTAssertTrue(photo.label.contains("From Duo"), "the photo doesn't say it came from Duo: \(photo.label)")
        XCTAssertTrue(photo.label.contains("New"), "the photo from Duo isn't marked New: \(photo.label)")
        XCTAssertTrue(item("Redox notes.pdf").exists, "the PDF from Duo isn't listed")
        let other = phone ? "iPad" : "iPhone"
        let notes = item("Essay outline.txt")
        reveal(notes)
        XCTAssertTrue(notes.label.contains("From \(other)"), "the notes don't say they came from the \(other): \(notes.label)")
        let sheet = item("Physics data.csv")
        reveal(sheet)
        XCTAssertTrue(sheet.label.contains("From G14"), "the sheet doesn't say it came from the G14: \(sheet.label)")
        let mine = item("Whiteboard.jpg")
        reveal(mine)
        XCTAssertTrue(mine.label.contains("Sent from here"), "the photo sent from here says otherwise: \(mine.label)")
        XCTAssertFalse(mine.label.contains("New"), "what was sent from here is marked New")
        reveal(photo)
        shot("drop-2-list")

        // a tap shows it (Quick Look). Its controls live in Quick Look's own process, out of XCTest's reach (the Nov 22 run's
        // hierarchy had no Done while the screenshot showed the photo): look at the screenshot, swipe down to close it.
        photo.tap()
        sleep(4)
        shot("drop-3-look")
        let addPhotos = app.buttons["drop-photos"].firstMatch
        // always one swipe: XCTest may count the list as hittable under Quick Look's window (on the list it only refreshes)
        app.swipeDown(velocity: .fast)
        sleep(2)
        var closes = 0
        while !addPhotos.isHittable && closes < 3 {
            let done = app.buttons["Done"].firstMatch
            if done.exists && done.isHittable { done.tap() } else { app.swipeDown(velocity: .fast) }
            sleep(2)
            closes += 1
        }
        XCTAssertTrue(addPhotos.waitForExistence(timeout: 15) && addPhotos.isHittable, "didn't come back to Drop from the photo")

        // hold: Share and Delete; Delete takes it away
        reveal(mine)
        mine.press(forDuration: 1.2)
        let share = app.buttons["Share…"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "no Share in the menu")
        shot("drop-4-menu")
        let del = app.buttons["Delete…"].firstMatch
        XCTAssertTrue(del.exists, "no Delete in the menu")
        del.tap()
        let sure = app.buttons["Delete"].firstMatch
        XCTAssertTrue(sure.waitForExistence(timeout: 10), "Delete didn't ask first")
        sure.tap()
        var waits = 0
        while mine.exists && waits < 20 { usleep(500_000); waits += 1 }
        XCTAssertFalse(mine.exists, "the deleted photo is still listed")
        shot("drop-5-deleted")
    }

    func testDropDark() {
        launch(["-NexusTestDark"])
        openDrop("drop-6-sidebar-dark")
        XCTAssertTrue(item("IMG_0042.jpg").waitForExistence(timeout: 15), "the photo from Duo isn't listed")
        sleep(1)
        shot("drop-7-list-dark")
    }
}

final class DropPhoneTests: DropTests {
    override class var forPhone: Bool { true }
}
