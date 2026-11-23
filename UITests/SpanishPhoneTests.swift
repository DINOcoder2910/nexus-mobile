import XCTest

/// Spanish on the iPhone, through every part with the demo (-NexusSpanishDemo): the same features as the iPad in the iPhone's own layout
/// (History, Writing and Skills as pages, the less used parts in the … menu, SpanishDict as a sheet). The screenshots
/// ("phone-spanish-…") are printed in the spanish-check log. Skips itself on the iPad.
final class SpanishPhoneTests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone only")
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
    func text(_ contains: String) -> XCUIElement { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch }
    func type(_ id: String, _ s: String) {
        let f = el(id)
        XCTAssertTrue(f.waitForExistence(timeout: 10), "no \(id)")
        f.tap()
        f.typeText(s)
    }
    func back() { app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1) }
    func hideKeyboard() {
        guard app.keyboards.count > 0 else { return }
        let done = app.buttons["spanish-keyboard-done"].firstMatch
        if done.exists { done.tap() } else { app.navigationBars.firstMatch.tap() }
    }

    func openSpanish() {
        app.launchArguments = ["-NexusSpanishDemo"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: 15), "no More tab")
        more.tap()
        // Spanish opens from its class's Study page (More has no Spanish row of its own)
        let study = el("sidebar-Study")
        var tries = 0
        while !study.waitForExistence(timeout: 2) && tries < 8 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(study.waitForExistence(timeout: 10), "no Study row in More")
        study.tap()
        let page = el("study-page-spanish-ab")
        var down = 0
        while !page.waitForExistence(timeout: 3) && down < 6 { app.swipeUp(); down += 1 }
        if !page.waitForExistence(timeout: 10) { shot("phone-spanish-no-study-page") }
        XCTAssertTrue(page.waitForExistence(timeout: 10), "Study has no Spanish ab initio")
        page.tap()
        let link = el("study-spanish")
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the Study page has no Spanish link")
        link.tap()
        XCTAssertTrue(el("spanish-sentence").waitForExistence(timeout: 10), "the Spanish screen didn't open")
        sleep(1)
    }

    func testEverySpanishPartOnTheIPhone() {
        openSpanish()
        shot("phone-spanish-home")

        type("spanish-sentence", "Ayer yo voy a la playa con mi amigos y comi un helado.")
        el("spanish-check").tap()
        XCTAssertTrue(text("Ayer yo fui a la playa").waitForExistence(timeout: 20), "the check didn't finish")
        hideKeyboard()
        sleep(1)
        shot("phone-spanish-checked")
        app.buttons["playa"].firstMatch.tap()
        XCTAssertTrue(text("beach").waitForExistence(timeout: 5), "no meaning for playa")
        shot("phone-spanish-word")
        app.buttons["SpanishDict"].firstMatch.tap()
        XCTAssertTrue(el("spanishdict-page").waitForExistence(timeout: 5), "no SpanishDict sheet")
        sleep(1)
        shot("phone-spanish-dict")
        app.buttons["Close SpanishDict"].firstMatch.tap()
        sleep(1)

        // the … menu: Add a card, SpanishDict, Teach me the imperative, a prompt, the model, the tutor's files
        el("spanish-more").tap()
        sleep(1)
        shot("phone-spanish-menu")
        app.buttons["Add a card"].firstMatch.tap()
        XCTAssertTrue(el("spanish-card-front").waitForExistence(timeout: 5), "no Add a card sheet")
        shot("phone-spanish-add-card")
        app.buttons["Cancel"].firstMatch.tap()
        sleep(1)

        // History, then Move to chat
        app.swipeUp()
        el("spanish-go-History").tap()
        sleep(1)
        shot("phone-spanish-history")
        app.buttons["Pick: Me gusta los deportes."].firstMatch.tap()
        app.buttons["Pick: Ayer compre una camiseta para mi madre."].firstMatch.tap()
        sleep(1)
        print("UISTEP move enabled: \(el("spanish-move").isEnabled)")
        shot("phone-spanish-picked")
        el("spanish-move").tap()
        let answer = el("spanish-answer")
        if !answer.waitForExistence(timeout: 20) { shot("phone-spanish-zz-no-card") }
        XCTAssertTrue(answer.exists, "no checker card from the tutor")
        sleep(1)
        shot("phone-spanish-chat")
        answer.tap()
        answer.typeText("Fui a Madrid con mi familia.")
        el("spanish-answer-check").tap()
        if !text("Muy bien").waitForExistence(timeout: 25) { shot("phone-spanish-zz-no-answer") }
        XCTAssertTrue(text("Muy bien").exists, "the tutor didn't answer the check")
        hideKeyboard()
        sleep(2)
        shot("phone-spanish-chat-answered")
        el("spanish-end-chat").tap()
        XCTAssertTrue(el("spanish-memory-save").waitForExistence(timeout: 15), "no memory review")
        sleep(1)
        shot("phone-spanish-memory")
        el("spanish-memory-save").tap()
        // back on Spanish, which may still be scrolled to the history the sentence was picked from (the list makes only the rows
        // on screen): scroll up to the sentence box
        let sentence = el("spanish-sentence")
        var up = 0
        while !sentence.waitForExistence(timeout: 3) && up < 6 { app.swipeDown(); up += 1 }
        XCTAssertTrue(sentence.waitForExistence(timeout: 10), "didn't go back to Spanish after saving")
        sleep(1)
        shot("phone-spanish-after-chat")

        // Writing
        app.swipeUp()
        el("spanish-go-Writing").tap()
        sleep(1)
        shot("phone-spanish-writing")
        // Text types (under the prompts): the guides, one with its structure, Practise with the tutor, back to the prompts
        let types = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'spanish-text-types' OR label BEGINSWITH 'Text type guides'")).firstMatch
        var more = 0
        while !types.waitForExistence(timeout: 2) && more < 4 { app.swipeUp(); more += 1 }
        if !types.exists { shot("phone-spanish-no-text-types") }
        XCTAssertTrue(types.exists, "no Text type guides under the prompts")
        types.tap()
        let guide = el("spanish-guide-correo-informal")
        XCTAssertTrue(guide.waitForExistence(timeout: 10), "the demo's guide isn't listed")
        shot("phone-spanish-types")
        guide.tap()
        XCTAssertTrue(el("spanish-guide-structure").waitForExistence(timeout: 10), "the guide has no structure")
        sleep(1)
        shot("phone-spanish-guide")
        el("spanish-guide-practise").tap()
        XCTAssertTrue(el("spanish-chat-input").waitForExistence(timeout: 10), "Practise didn't open a chat")
        sleep(4)
        shot("phone-spanish-guide-practise")
        el("spanish-guide-chat-close").tap()
        sleep(1)
        back()
        back()
        app.swipeDown()
        let prompt = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'spanish-prompt-2'")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "no prompt")
        prompt.tap()
        type("spanish-piece", "¡Hola Marta!\n\nLa semana pasada fui a la playa con mi familia. Fuimos en coche y el viaje fue muy largo, pero divertido. Nos quedamos en un hotel pequeño cerca del mar.\n\nCada día nadamos y comimos paella en un restaurante. Ayer compre una camiseta para mi hermano. Lo que más me gustó fue el atardecer en la playa porque fue muy bonito.\n\n¿Y tú? ¿Qué hiciste en las vacaciones?\n\nUn abrazo,\nAli")
        hideKeyboard()
        sleep(1)
        // the text type's guide as a sheet: a step ticked, a stem put into the piece
        el("spanish-guide-open").tap()
        XCTAssertTrue(el("spanish-guide-step-0").waitForExistence(timeout: 10), "the guide sheet has no structure")
        el("spanish-guide-step-0").tap()
        sleep(1)
        shot("phone-spanish-guide-sheet")
        let stem = el("spanish-stem-0-0")
        var down = 0
        while !stem.isHittable && down < 5 { app.swipeUp(); down += 1 }
        stem.tap()
        el("spanish-guide-done").tap()
        sleep(1)
        XCTAssertTrue((el("spanish-piece").value as? String ?? "").contains("¿Qué tal todo?"), "the stem didn't go into the piece")
        shot("phone-spanish-write")
        // Mark it sits below the longer piece: lift it clear of the tab bar first (a press there lands on Today)
        let mark = el("spanish-mark")
        var lift = 0
        while mark.frame.maxY > app.frame.height * 0.7 && lift < 4 { app.swipeUp(); lift += 1 }
        mark.tap()
        XCTAssertTrue(el("spanish-grade-total").waitForExistence(timeout: 20), "the piece wasn't marked")
        XCTAssertTrue(el("spanish-graded-piece").waitForExistence(timeout: 5), "the marked piece isn't shown with its mistakes")
        app.swipeUp()
        sleep(1)
        shot("phone-spanish-marked")
        back()
        back()

        // Skills
        app.swipeUp()
        el("spanish-go-Skills").tap()
        sleep(2)
        shot("phone-spanish-skills")
    }
}
