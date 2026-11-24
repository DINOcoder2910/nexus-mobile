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
    func text(_ contains: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch }
    func type(_ id: String, _ s: String) {
        let f = el(id)
        XCTAssertTrue(f.waitForExistence(timeout: 10), "no \(id)")
        f.tap()
        f.typeText(s)
    }
    /// Hides the on-screen keyboard with its own hide key (the bottom-right key).
    func hideKeyboard() {
        guard app.keyboards.count > 0 else { return }
        let keys = app.keyboards.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'hide keyboard' OR label CONTAINS[c] 'dismiss'"))
        if keys.count > 0 { keys.firstMatch.tap() }
        sleep(1)
    }

    /// Closes a popover by tapping outside it.
    func closePopover() {
        let dismiss = app.otherElements["PopoverDismissRegion"].firstMatch
        if dismiss.exists { dismiss.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.98)).tap() }
        sleep(1)
    }

    func openSpanish(_ more: [String] = []) {
        app.launchArguments = ["-NexusSpanishDemo"] + more
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        // Spanish opens from its class's Study page (the sidebar has no Spanish row of its own)
        let study = el("sidebar-Study")
        XCTAssertTrue(study.waitForExistence(timeout: 20), "no Study row in the sidebar")
        study.tap()
        let page = el("study-page-spanish-ab")
        var down = 0
        while !page.waitForExistence(timeout: 3) && down < 6 { app.swipeUp(); down += 1 }
        if !page.waitForExistence(timeout: 10) { shot("pad-spanish-no-study-page") }
        XCTAssertTrue(page.waitForExistence(timeout: 10), "Study has no Spanish ab initio")
        page.tap()
        let link = el("study-spanish")
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the Study page has no Spanish link")
        link.tap()
        XCTAssertTrue(el("spanish-sentence").waitForExistence(timeout: 10), "the Spanish screen didn't open")
        sleep(1)
    }

    func testEverySpanishPartOnTheIPad() {
        openSpanish(["-debug.blockDump", "YES"])
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
        app.buttons["playa"].firstMatch.tap()
        XCTAssertTrue(text("beach").waitForExistence(timeout: 5), "no meaning for playa")
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
        sleep(1)
        print("UISTEP move enabled: \(el("spanish-move").isEnabled)")
        shot("pad-spanish-picked")
        el("spanish-move").tap()

        // the tutor: its answer streams, its question is a checker card
        let answer = el("spanish-answer")
        if !answer.waitForExistence(timeout: 20) { shot("pad-spanish-zz-no-card") }
        XCTAssertTrue(answer.exists, "no checker card from the tutor")
        sleep(1)
        shot("pad-spanish-chat")
        answer.tap()
        answer.typeText("Fui a Madrid con mi familia.")
        el("spanish-answer-check").tap()
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
        // the text type's guide beside the piece: the one the prompt offers, a step of its structure ticked
        XCTAssertTrue(el("spanish-guide-panel").waitForExistence(timeout: 10), "no text type guide beside the piece")
        XCTAssertTrue(el("spanish-guide-step-0").waitForExistence(timeout: 5), "the guide has no structure")
        el("spanish-guide-step-0").tap()
        type("spanish-piece", "¡Hola Marta!\n\nLa semana pasada fui a la playa con mi familia. Fuimos en coche y el viaje fue muy largo, pero divertido. Nos quedamos en un hotel pequeño cerca del mar.\n\nCada día nadamos y comimos paella en un restaurante. Ayer compre una camiseta para mi hermano. Lo que más me gustó fue el atardecer en la playa porque fue muy bonito.\n\n¿Y tú? ¿Qué hiciste en las vacaciones?\n\nUn abrazo,\nAli")
        hideKeyboard()
        // the piece is read as it is written: its mistake (compre) is underlined, as in the tutor's box
        let dump = el("esbox")
        var seen = ""
        for _ in 0..<20 {
            if dump.exists { seen = dump.label; if seen.range(of: "box:[1-9]", options: .regularExpression) != nil { break } }
            sleep(1)
        }
        print("UISTEP ESBOX \(seen)")
        shot("pad-spanish-write-underlined")
        XCTAssertTrue(seen.range(of: "box:[1-9]", options: .regularExpression) != nil, "the essay box has no underlines: \(seen)")
        // a sentence stem tapped goes into the piece
        let stem = el("spanish-stem-0-0")
        var down = 0
        while !stem.isHittable && down < 5 { el("spanish-guide-panel").swipeUp(); down += 1 }
        stem.tap()
        sleep(1)
        XCTAssertTrue((el("spanish-piece").value as? String ?? "").contains("¿Qué tal todo?"), "the stem didn't go into the piece")
        shot("pad-spanish-write")
        el("spanish-mark").tap()
        XCTAssertTrue(el("spanish-grade-total").waitForExistence(timeout: 20), "the piece wasn't marked")
        XCTAssertTrue(el("spanish-graded-piece").waitForExistence(timeout: 5), "the marked piece isn't shown with its mistakes")
        sleep(1)
        shot("pad-spanish-marked")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)

        // Text types: the guides, one with its exemplar, Practise with the tutor
        let types = el("spanish-text-types")
        var more = 0
        while !types.isHittable && more < 6 { app.swipeUp(); more += 1 }
        types.tap()
        let guide = el("spanish-guide-correo-informal")
        XCTAssertTrue(guide.waitForExistence(timeout: 10), "the demo's guide isn't listed")
        shot("pad-spanish-types")
        guide.tap()
        XCTAssertTrue(el("spanish-guide-exemplar").waitForExistence(timeout: 10), "the guide has no exemplar")
        sleep(1)
        shot("pad-spanish-guide")
        el("spanish-guide-practise").tap()
        XCTAssertTrue(el("spanish-chat-input").waitForExistence(timeout: 10), "Practise didn't open a chat")
        sleep(4)
        shot("pad-spanish-guide-practise")
        el("spanish-guide-chat-close").tap()
        sleep(1)
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
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
        // the link sits under the new Spanish decks, below the fold of a list that only makes the rows on screen
        let link = el("workstream-spanish")
        var down = 0
        while !link.waitForExistence(timeout: 3) && down < 8 { app.swipeUp(); down += 1 }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the workstream page didn't get its Spanish link")
        shot("pad-spanish-setup-done")
    }
}
