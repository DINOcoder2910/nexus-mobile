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
    func text(_ contains: String) -> XCUIElement { app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", contains)).firstMatch }
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
        let row = app.buttons["Spanish"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "no Spanish row in More")
        row.tap()
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
        app.buttons["Check"].firstMatch.tap()
        XCTAssertTrue(text("Muy bien").waitForExistence(timeout: 25), "the tutor didn't answer the check")
        hideKeyboard()
        sleep(2)
        shot("phone-spanish-chat-answered")
        el("spanish-end-chat").tap()
        XCTAssertTrue(el("spanish-memory-save").waitForExistence(timeout: 15), "no memory review")
        sleep(1)
        shot("phone-spanish-memory")
        el("spanish-memory-save").tap()
        XCTAssertTrue(el("spanish-sentence").waitForExistence(timeout: 10), "didn't go back to Spanish after saving")
        sleep(1)
        shot("phone-spanish-after-chat")

        // Writing
        app.swipeUp()
        el("spanish-go-Writing").tap()
        sleep(1)
        shot("phone-spanish-writing")
        let prompt = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'spanish-prompt-2'")).firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5), "no prompt")
        prompt.tap()
        type("spanish-piece", "¡Hola Marta!\n\nLa semana pasada fui a la playa con mi familia. Fuimos en coche y el viaje fue muy largo, pero divertido. Nos quedamos en un hotel pequeño cerca del mar.\n\nCada día nadamos y comimos paella en un restaurante. Ayer compre una camiseta para mi hermano. Lo que más me gustó fue el atardecer en la playa porque fue muy bonito.\n\n¿Y tú? ¿Qué hiciste en las vacaciones?\n\nUn abrazo,\nAli")
        hideKeyboard()
        sleep(1)
        shot("phone-spanish-write")
        el("spanish-mark").tap()
        XCTAssertTrue(el("spanish-grade-total").waitForExistence(timeout: 20), "the piece wasn't marked")
        el("spanish-grade-total").swipeUp()
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
