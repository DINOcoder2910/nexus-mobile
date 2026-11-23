import XCTest

/// Spanish › Oral on the iPhone, with the demo (-NexusSpanishDemo: three past orals in the sample's Spanish class, canned answers in
/// place of Claude, no microphone): the list with its marks, one oral, Add a recording made here (it waits for the laptop), the
/// listening test read line by line and sent. The board's underlines are in OralTests. The screenshots ("phone-oral-…") are
/// kept in the result bundle. Skips itself on the iPad.
final class OralPhoneTests: XCTestCase {
    var app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    /// Any element whose label holds the words (a list row's texts are one button's label).
    func text(_ contains: String) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch }

    /// Scrolls (down, then back up) until the element is on screen.
    func reveal(_ e: XCUIElement, _ what: String) {
        var swipes = 0
        while !(e.exists && e.isHittable) && swipes < 8 { app.swipeUp(velocity: .slow); swipes += 1 }
        while !(e.exists && e.isHittable) && swipes < 16 { app.swipeDown(velocity: .slow); swipes += 1 }
        XCTAssertTrue(e.waitForExistence(timeout: 5), "no \(what)")
    }

    func launch(_ more: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-NexusSpanishDemo"] + more
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 20) { sample.tap() }
        if sample.waitForExistence(timeout: 2) && sample.isHittable { sample.tap() }
    }

    func openOral() {
        launch()
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "no More tab")
        more.tap()
        let study = el("sidebar-Study")
        var tries = 0
        while !study.waitForExistence(timeout: 2) && tries < 8 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(study.waitForExistence(timeout: 10), "no Study row in More")
        study.tap()
        let page = el("study-page-spanish-ab")
        var down = 0
        while !page.waitForExistence(timeout: 3) && down < 6 { app.swipeUp(); down += 1 }
        XCTAssertTrue(page.waitForExistence(timeout: 10), "Study has no Spanish ab initio")
        page.tap()
        let link = el("study-spanish")
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the Study page has no Spanish link")
        link.tap()
        XCTAssertTrue(el("spanish-sentence").waitForExistence(timeout: 10), "the Spanish screen didn't open")
        let open = el("spanish-go-Oral practice")
        reveal(open, "Oral practice row")
        shot("phone-oral-spanish-row")
        open.tap()
        XCTAssertTrue(el("oral-row").waitForExistence(timeout: 15), "the Oral page lists no orals")
        sleep(1)
    }

    func testTheOralPage() {
        openOral()
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "oral-row").count, 3, "the demo's three orals aren't listed")
        XCTAssertTrue(el("oral-trend").exists, "no marks over time")
        reveal(text("Formative IO"), "the teacher's oral, listed by its title")
        XCTAssertTrue(text("23/30").exists, "the teacher's mark isn't shown")
        shot("phone-oral-list")

        // one oral: the practice oral Claude marked, with what the ears heard (by its summary: a recording added in an earlier run is newer)
        let practice = text("A clear description of the festival")
        reveal(practice, "the practice oral")
        practice.tap()
        XCTAssertTrue(el("oral-claude").waitForExistence(timeout: 10), "no Claude's marks on the practice oral")
        XCTAssertTrue(text("Claude: 20/30").exists, "Claude's total isn't shown")
        XCTAssertTrue(el("oral-listen").exists, "no listening summary")
        XCTAssertTrue(text("You spoke 62% of the time").exists, "the share of the talk isn't shown")
        shot("phone-oral-one")
        let back = app.navigationBars.buttons["Oral practice"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "no way back to the Oral page")
        back.tap()
        XCTAssertTrue(el("oral-add").waitForExistence(timeout: 10), "not back on the Oral page")

        // Add a recording, made here: it waits for the laptop
        el("oral-add").tap()
        let record = el("oral-i-record")
        XCTAssertTrue(record.waitForExistence(timeout: 10), "no Record it now")
        record.tap()
        let stop = el("oral-i-stop")
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "the recording didn't start")
        sleep(2)
        shot("phone-oral-add-recording")
        stop.tap()
        XCTAssertTrue(text("Recorded here").waitForExistence(timeout: 5), "the recording isn't named")
        let total = el("oral-i-total")
        reveal(total, "Total field")
        total.tap(); total.typeText("7")
        let max = el("oral-i-max")
        max.tap(); max.typeText("10")
        shot("phone-oral-add-form")
        el("oral-i-add").tap()
        let waiting = el("oral-waiting")
        reveal(waiting, "waiting note")
        XCTAssertTrue(text("Waiting for the laptop").waitForExistence(timeout: 10), "the new recording isn't marked as waiting")
        shot("phone-oral-waiting")

        // the listening test: every line read, then sent to the laptop
        let row = el("oral-test-row")
        reveal(row, "Listening test row")
        row.tap()
        for id in ["t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "control"] {
            let rec = el("oral-t-rec-\(id)")
            reveal(rec, "Record for \(id)")
            rec.tap()
            let s = el("oral-t-stop")
            XCTAssertTrue(s.waitForExistence(timeout: 10), "line \(id) didn't start recording")
            if id == "t5" { shot("phone-oral-test-recording") }
            s.tap()
        }
        let send = el("oral-t-send")
        reveal(send, "Send to the laptop")
        XCTAssertTrue(send.isEnabled, "Send isn't on with every line read")
        send.tap()
        let take = el("oral-t-take")
        reveal(take, "the sent take")
        shot("phone-oral-test-sent")
    }
}
