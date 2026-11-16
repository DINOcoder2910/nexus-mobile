import XCTest

/// Spanish on the iPad, through every part with the demo (-NexusSpanishDemo: a Spanish workstream in the sample data, canned answers in
/// place of Claude and LanguageTool): check a sentence, a word's meaning, Add to vocab, History and Move to chat, the tutor's checker
/// card, End chat and the memory review, SpanishDict, Writing and its marks, Skills. The screenshots ("pad-spanish-…") are printed in
/// the spanish-check log. Skips itself on the iPhone.
final class SpanishPadTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "iPad only")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func shot(_ name: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(name)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func el(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    func text(_ contains: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch }
    func type(_ id: String, _ s: String) {
        let f = el(id)
        XCTAssertTrue(f.waitForExistence(timeout: 10), "no \(id)")
        f.tap()
        f.typeText(s)
    }
    /// Closes a popover by tapping outside it.
    func closePopover() {
        let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
        if dismiss.exists { dismiss.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.98)).tap() }
        sleep(1)
    }

    func openSpanish() {
        app.launchArguments = ["-NexusSpanishDemo"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        let row = app.staticTexts["Spanish"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no Spanish row in the sidebar")
        row.tap()
        XCTAssertTrue(el("spanish-sentence").waitForExistence(timeout: 10), "the Spanish screen didn't open")
        sleep(1)
    }

    func testEverySpanishPartOnTheIPad() {
        openSpanish()
        shot("pad-spanish-home")

        // check a sentence: the dictionary and LanguageTool first, then Claude
        type("spanish-sentence", "Ayer yo voy a la playa con mi amigos y comi un helado.")
        el("spanish-check").tap()
        XCTAssertTrue(text("Ayer yo fui a la playa").waitForExistence(timeout: 20), "the check didn't finish")
        sleep(1)
        shot("pad-spanish-checked")

        // a mark, then a word: its meaning, then Add to vocab
        let voy = app.buttons["voy, should be fui"].firstMatch
        XCTAssertTrue(voy.waitForExistence(timeout: 5), "no mark on voy")
        voy.tap()
        sleep(1)
        shot("pad-spanish-mark")
        closePopover()
        app.buttons["helado"].firstMatch.tap()
        XCTAssertTrue(text("ice cream").waitForExistence(timeout: 5), "no meaning for helado")
        shot("pad-spanish-word")
        app.buttons["Add to vocab"].firstMatch.tap()
        XCTAssertTrue(el("spanish-card-front").waitForExistence(timeout: 5), "no Add to vocab sheet")
        sleep(1)
        shot("pad-spanish-add-card")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)

        // History: pick two checks and move them to a chat
        el("spanish-history-toggle").tap()
        sleep(1)
        shot("pad-spanish-history")
        app.buttons["Pick: Me gusta los deportes."].firstMatch.tap()
        app.buttons["Pick: Ayer compre una camiseta para mi madre."].firstMatch.tap()
        el("spanish-move").tap()

        // the tutor: its answer streams, its question is a checker card
        let answer = el("spanish-answer")
        XCTAssertTrue(answer.waitForExistence(timeout: 20), "no checker card from the tutor")
        sleep(1)
        shot("pad-spanish-chat")
        answer.tap()
        answer.typeText("Fui a Madrid con mi familia.")
        app.buttons["Check"].firstMatch.tap()
        XCTAssertTrue(text("Muy bien").waitForExistence(timeout: 25), "the tutor didn't answer the check")
        sleep(2)
        shot("pad-spanish-chat-answered")

        // End chat: the memory review, then Save
        el("spanish-end-chat").tap()
        XCTAssertTrue(el("spanish-memory-save").waitForExistence(timeout: 15), "no memory review")
        sleep(1)
        shot("pad-spanish-memory")
        el("spanish-memory-save").tap()
        XCTAssertTrue(el("spanish-sentence").waitForExistence(timeout: 10), "didn't go back to Spanish after saving")
        sleep(2)
        shot("pad-spanish-after-chat")

        // SpanishDict beside the screen
        el("spanish-dict").tap()
        XCTAssertTrue(el("spanishdict-page").waitForExistence(timeout: 5), "no SpanishDict panel")
        shot("pad-spanish-dict")
        app.buttons["Close SpanishDict"].firstMatch.tap()

        // Writing: a prompt, a piece, the IB count, Mark it
        let prompt = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'spanish-prompt-2'")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "no prompt")
        prompt.tap()
        type("spanish-piece", "¡Hola Marta!\n\nLa semana pasada fui a la playa con mi familia. Fuimos en coche y el viaje fue muy largo, pero divertido. Nos quedamos en un hotel pequeño cerca del mar.\n\nCada día nadamos y comimos paella en un restaurante. Ayer compre una camiseta para mi hermano. Lo que más me gustó fue el atardecer en la playa porque fue muy bonito.\n\n¿Y tú? ¿Qué hiciste en las vacaciones?\n\nUn abrazo,\nAli")
        sleep(1)
        shot("pad-spanish-write")
        el("spanish-mark").tap()
        XCTAssertTrue(el("spanish-grade-total").waitForExistence(timeout: 20), "the piece wasn't marked")
        sleep(1)
        shot("pad-spanish-marked")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)

        // Skills
        el("spanish-all-skills").tap()
        sleep(2)
        shot("pad-spanish-skills")
    }

    /// Set up Spanish study from a workstream's … menu.
    func testSetUpFromAWorkstream() {
        openSpanish()
        let phys = app.staticTexts["Physics HL"].firstMatch
        XCTAssertTrue(phys.waitForExistence(timeout: 5))
        phys.tap()
        let more = app.navigationBars.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no … menu on the workstream")
        more.tap()
        let setup = app.buttons["Set up Spanish study"].firstMatch
        XCTAssertTrue(setup.waitForExistence(timeout: 5), "no Set up Spanish study")
        shot("pad-spanish-setup-menu")
        setup.tap()
        XCTAssertTrue(app.staticTexts["Spanish · Physics HL"].firstMatch.waitForExistence(timeout: 15), "the sidebar didn't get a second Spanish row")
        shot("pad-spanish-setup-done")
    }
}
