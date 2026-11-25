import XCTest

/// Getting around a big notebooks folder quickly (Nov 24 2026: the sidebar and Move to… were too long to scroll): the sidebar's
/// "Find a notebook or board" field at the top, a notebook's row stepping inside it, Pin to the top, and Move to… with its search,
/// its Recent places and its tree opened where the board is. On the nested notebooks of `-NexusTestNestedNotebooks` (made again at
/// each launch, Sources/Common/TestHooks.swift). The screenshots ("sidebar-…") are printed in the ui-check log.
final class NotebookFindTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the iPad's sidebar") }
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The sidebar's list (by its own label, not by a row scrolling can take away).
    var sidebar: XCUIElement { app.collectionViews["Sidebar"].exists ? app.collectionViews["Sidebar"] : app.collectionViews.firstMatch }

    /// Swipes the sidebar up (then back down, for a row above the screen) until `el` can be tapped, clear of the footer icons.
    func reach(_ el: XCUIElement, _ what: String) {
        var tries = 0
        while !(el.exists && el.isHittable) && tries < 10 { sidebar.swipeUp(velocity: .slow); tries += 1 }
        var back = 0
        while !(el.exists && el.isHittable) && back < 12 { sidebar.swipeDown(velocity: .slow); back += 1 }
        let bottom = app.windows.firstMatch.frame.maxY
        if el.exists && el.frame.maxY > bottom - 140 { sidebar.swipeUp(velocity: .slow) }
        XCTAssertTrue(el.waitForExistence(timeout: 5) && el.isHittable, "can't reach " + what)
    }

    /// Swipes the sidebar back down until `el` exists (rows above the screen aren't made).
    func reachUp(_ el: XCUIElement) {
        var tries = 0
        while !el.exists && tries < 8 { sidebar.swipeDown(velocity: .slow); tries += 1 }
    }

    /// A found, pinned or Recent row: a button of the sidebar whose label starts with the name (then where it sits). Not the
    /// notebook page's card of the same name beside it ("Verbs, Edited 3 minutes ago").
    func entry(_ name: String) -> XCUIElement {
        sidebar.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// Taps a field until it has the keyboard, then types (a tap on a settling screen can be dropped).
    func enter(_ text: String, into field: XCUIElement) {
        var tries = 0
        repeat {
            field.tap()
            tries += 1
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            sleep(1)
        } while tries < 5
        field.typeText(text)
    }

    /// The sidebar again over the open board (opening a board puts it away).
    func showSidebar() {
        sleep(1)
        if !app.buttons["New task"].firstMatch.isHittable {
            let side = app.buttons["Sidebar"].firstMatch
            XCTAssertTrue(side.waitForExistence(timeout: 5), "no Sidebar button on the board")
            side.tap()
            sleep(2)
        }
    }

    /// A row's hold menu, then one of its rows.
    func hold(_ row: XCUIElement, _ item: String) {
        row.press(forDuration: 1.3)
        let b = app.buttons[item].firstMatch
        if !b.waitForExistence(timeout: 5) {
            row.press(forDuration: 1.6)
        }
        XCTAssertTrue(b.waitForExistence(timeout: 5), "no " + item + " in the menu")
        b.tap()
    }

    func run(dark: Bool) {
        let mode = dark ? "dark" : "light"
        app.launchArguments = ["-NexusTestNestedNotebooks"] + (dark ? ["-NexusTestDark"] : [])
        app.launch()
        XCTAssertTrue(app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 20), "the sidebar isn't up")
        sleep(2)

        // 1. Find, at the top: a board deep inside, with where it sits
        let field = app.textFields["notebook-find"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no find field at the top of the sidebar")
        enter("calor", into: field)
        let calorimetry = entry("Calorimetry")
        XCTAssertTrue(calorimetry.waitForExistence(timeout: 20), "Calorimetry wasn't found")
        XCTAssertTrue(calorimetry.label.contains("Week 1"), "the found board doesn't say where it is: " + calorimetry.label)
        sleep(1)
        shot("sidebar-find-\(mode)")
        calorimetry.tap()
        XCTAssertTrue(app.buttons["Insert"].firstMatch.waitForExistence(timeout: 20), "Calorimetry didn't open from the find field")
        showSidebar()

        // 2. Clearing the field brings the sidebar back; a notebook's row steps inside it (Nov 25 2026: no tree of arrows)
        let clear = app.buttons["notebook-find-clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "no Clear in the find field")
        clear.tap()
        XCTAssertTrue(app.staticTexts["Planner"].firstMatch.waitForExistence(timeout: 10), "the places didn't come back")
        let spanish = sidebar.staticTexts["Spanish"].firstMatch
        reach(spanish, "the Spanish notebook")
        spanish.tap()
        let back = app.buttons["notebook-back"].firstMatch
        let inside = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Spanish'"), object: back)
        XCTAssertEqual(XCTWaiter().wait(for: [inside], timeout: 40), .completed, "didn't step inside Spanish")
        XCTAssertFalse(sidebar.staticTexts["School"].exists, "the other notebooks still show inside Spanish")
        sleep(1)
        shot("sidebar-step-in-\(mode)")

        // 3. Move to…: where it is now, the tree opened there, the search
        let vocab = sidebar.staticTexts["Vocab"].firstMatch
        reach(vocab, "Vocab")
        hold(vocab, "Move to…")
        let now = app.staticTexts["move-now-in"].firstMatch
        XCTAssertTrue(now.waitForExistence(timeout: 10), "Move to… didn't open")
        XCTAssertTrue(now.label.contains("Spanish"), "Move to… doesn't say where it is now: " + now.label)
        let schoolArrow = app.buttons["move-arrow-School"].firstMatch
        XCTAssertTrue(schoolArrow.waitForExistence(timeout: 5), "School isn't in Move to…'s tree")
        XCTAssertFalse(app.buttons["move-to-Chemistry"].exists, "Move to… opened every notebook")
        schoolArrow.tap()
        let chemArrow = app.buttons["move-arrow-Chemistry"].firstMatch
        XCTAssertTrue(chemArrow.waitForExistence(timeout: 10), "School didn't open in Move to…")
        chemArrow.tap()
        XCTAssertTrue(app.buttons["move-to-R3 Energetics"].firstMatch.waitForExistence(timeout: 10), "Chemistry didn't open in Move to…")
        sleep(1)
        shot("sidebar-move-\(mode)")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search in Move to…")
        enter("week 2", into: search)
        let week2 = app.buttons["move-place-Week 2"].firstMatch
        XCTAssertTrue(week2.waitForExistence(timeout: 10), "Week 2 wasn't found in Move to…")
        XCTAssertTrue(week2.label.contains("R3 Energetics"), "the found notebook doesn't say where it is: " + week2.label)
        sleep(1)
        shot("sidebar-move-find-\(mode)")
        week2.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: now)
        XCTAssertEqual(XCTWaiter().wait(for: [closed], timeout: 15), .completed, "Move to… didn't close after the move")
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: sidebar.staticTexts["Vocab"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: 20), .completed, "Vocab is still in Spanish")

        // 4. Pin a board: back in the full list it shows in Pinned, with where it sits
        let verbs = sidebar.staticTexts["Verbs"].firstMatch
        reach(verbs, "Verbs")
        hold(verbs, "Pin to the top")
        reach(back, "Back")
        back.tap()
        XCTAssertTrue(app.staticTexts["Planner"].firstMatch.waitForExistence(timeout: 20), "Back didn't return to the full list")
        let pinned = entry("Verbs")
        if !pinned.waitForExistence(timeout: 5) { reachUp(pinned) }
        XCTAssertTrue(pinned.waitForExistence(timeout: 5), "Verbs isn't in Pinned")
        XCTAssertTrue(pinned.label.contains("Spanish"), "the pinned board doesn't say where it is: " + pinned.label)
        sleep(1)
        shot("sidebar-pinned-\(mode)")

        // 5. The next Move to… (from the pinned row) offers Week 2 in Recent
        reach(pinned, "the pinned Verbs")
        hold(pinned, "Move to…")
        XCTAssertTrue(app.staticTexts["move-now-in"].firstMatch.waitForExistence(timeout: 10), "Move to… didn't open again")
        XCTAssertTrue(app.buttons["move-place-Week 2"].firstMatch.waitForExistence(timeout: 5), "Week 2 isn't in Move to…'s Recent")
        sleep(1)
        shot("sidebar-move-recent-\(mode)")
        app.buttons["Cancel"].firstMatch.tap()
    }

    func testFindPinAndMoveLight() { run(dark: false) }

    func testFindPinAndMoveDark() { run(dark: true) }
}

/// The same on the iPhone: the find field at the top of the Subjects tab, Move to… from a found board, and a found board opening.
final class NotebookFindPhoneTests: XCTestCase {
    let app = XCUIApplication()

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func enter(_ text: String, into field: XCUIElement) {
        var tries = 0
        repeat {
            field.tap()
            tries += 1
            if (field.value(forKey: "hasKeyboardFocus") as? Bool) == true { break }
            sleep(1)
        } while tries < 5
        field.typeText(text)
    }

    func entry(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    func testPhoneFindAndMove() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone only") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-NexusTestNestedNotebooks"]
        app.launch()
        let tab = app.tabBars.buttons["Subjects"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "no Subjects tab")
        tab.tap()
        let field = app.textFields["notebook-find"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no find field at the top of Subjects")
        enter("vocab", into: field)
        let vocab = entry("Vocab")
        XCTAssertTrue(vocab.waitForExistence(timeout: 20), "Vocab wasn't found")
        sleep(1)
        shot("sidebar-phone-find")

        // Move to… from the found board, by its search
        vocab.press(forDuration: 1.3)
        let moveItem = app.buttons["Move to…"].firstMatch
        XCTAssertTrue(moveItem.waitForExistence(timeout: 5), "no Move to… in the found board's menu")
        moveItem.tap()
        XCTAssertTrue(app.staticTexts["move-now-in"].firstMatch.waitForExistence(timeout: 10), "Move to… didn't open")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no search in Move to…")
        enter("week 1", into: search)
        let week1 = app.buttons["move-place-Week 1"].firstMatch
        XCTAssertTrue(week1.waitForExistence(timeout: 10), "Week 1 wasn't found in Move to…")
        sleep(1)
        shot("sidebar-phone-move-find")
        week1.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["move-now-in"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 15), .completed, "Move to… didn't close after the move")
        // found again, now in Week 1
        let movedVocab = entry("Vocab")
        let there = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'Week 1'"), object: movedVocab)
        XCTAssertEqual(XCTWaiter().wait(for: [there], timeout: 20), .completed, "Vocab didn't move to Week 1: " + movedVocab.label)

        // a found board opens over everything
        movedVocab.tap()
        let tabsGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == false"), object: tab)
        XCTAssertEqual(XCTWaiter().wait(for: [tabsGone], timeout: 20), .completed, "the found board didn't open")
    }
}
