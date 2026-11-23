import XCTest
@testable import NexusCore

/// Spanish › Text types read the way the laptop reads them (desktop/backend/src/texttypes.rs and its tests).
final class SpanishTextTypesTests: XCTestCase {
    let guide = """
    ---
    title: Correo electrónico formal
    english: Formal email
    group: professional
    register: Formal, usted
    matches: [correo electrónico, email, correo formal]
    ---

    ## Structure
    1. **Asunto**: the purpose in a few words.
    2. **Saludo**: *Estimada señora López:*

    ## Rules
    - Usted all the way through: le, su, usted.
    - No exclamation marks.

    ## Vocabulary
    ### Formal phrases
    - Atentamente · Yours sincerely
    - de antemano · in advance

    ## Sentence stems
    ### Purpose
    - Le escribo para solicitar… · I am writing to apply for…
    - Le ruego que me envíe más información. · Please send me more information. [verb.subjuntivo]
    - el sello · the stamp [not.a.skill]

    ## Exemplar
    > Escribe un correo electrónico a la directora.

    Estimada señora López:

    Le escribo para solicitar el puesto.

    Atentamente,
    Alex Pérez

    ### Why it works
    - The purpose comes first (B, C).
    - Usted throughout (C).

    ## Tips from Miss K
    Use the conditional.
    """

    func testAGuideReadWhole() {
        let g = SpanishTextTypes.parse(slug: "correo-formal", text: guide)
        XCTAssertEqual(g.title, "Correo electrónico formal")
        XCTAssertEqual(g.english, "Formal email")
        XCTAssertEqual(g.group, "professional")
        XCTAssertEqual(g.register, "Formal, usted")
        XCTAssertEqual(g.matches, ["correo electrónico", "email", "correo formal"])
        XCTAssertEqual(g.structure, ["**Asunto**: the purpose in a few words.", "**Saludo**: *Estimada señora López:*"])
        XCTAssertEqual(g.rules.count, 2)
        XCTAssertEqual(g.vocab, [.init(title: "Formal phrases", items: [.init(es: "Atentamente", en: "Yours sincerely", skill: ""), .init(es: "de antemano", en: "in advance", skill: "")])])
        XCTAssertEqual(g.stems.first?.items[1], .init(es: "Le ruego que me envíe más información.", en: "Please send me more information.", skill: "verb.subjuntivo"))
        XCTAssertEqual(g.stems.first?.items[2], .init(es: "el sello", en: "the stamp [not.a.skill]", skill: ""), "a tag that names no skill stays in the words")
        XCTAssertEqual(g.task, "Escribe un correo electrónico a la directora.")
        XCTAssertTrue(g.exemplar.hasPrefix("Estimada señora López:\n\nLe escribo") && g.exemplar.hasSuffix("Alex Pérez"))
        XCTAssertEqual(g.notes, ["The purpose comes first (B, C).", "Usted throughout (C)."])
        XCTAssertEqual(g.more, [.init(title: "Tips from Miss K", text: "Use the conditional.")])
    }

    func testConventionsMatchesAndOrder() {
        let g = SpanishTextTypes.parse(slug: "correo-formal", text: guide)
        XCTAssertEqual(SpanishTextTypes.conventions(g), "Correo electrónico formal (Formal email), register: Formal, usted\nStructure:\n- Asunto: the purpose in a few words.\n- Saludo: *Estimada señora López:*\nRules:\n- Usted all the way through: le, su, usted.\n- No exclamation marks.")
        let blog = SpanishTextTypes.parse(slug: "blog", text: "---\ntitle: Blog\nmatches: [blog]\n---\n")
        let own = SpanishTextTypes.parse(slug: "receta", text: "no front matter\n## Rules\n- one")
        XCTAssertEqual(own.title, "receta")
        XCTAssertEqual(own.group, "other")
        XCTAssertEqual(own.rules, ["one"])
        XCTAssertEqual(SpanishTextTypes.sorted([own, g, blog]).map(\.slug), ["blog", "correo-formal", "receta"])
        XCTAssertEqual(SpanishTextTypes.guidesFor(["Correo Electronico", "blog"], [g, blog, own]).map(\.slug), ["correo-formal", "blog"])
        XCTAssertTrue(SpanishTextTypes.practise(g).hasPrefix("I want to practise writing a formal email (Correo electrónico formal)."))
        XCTAssertTrue(SpanishTextTypes.tutorSection(g).contains("study/spanish/text-types/correo-formal.md"))
        XCTAssertTrue(SpanishTextTypes.forTutor(g).contains("Purpose: Le escribo para solicitar… (I am writing to apply for…); Le ruego que me envíe más información. (Please send me more information.) [verb.subjuntivo]"))
        XCTAssertFalse(SpanishTextTypes.forTutor(g).contains("Le escribo para solicitar el puesto."), "the exemplar is kept back")
    }

    func testAMessageFindsItsGuideAndTheMarkingGetsIt() {
        let g = SpanishTextTypes.parse(slug: "correo-formal", text: guide)
        let blog = SpanishTextTypes.parse(slug: "blog", text: "---\ntitle: Blog\nmatches: [blog, entrada de blog]\n---\n")
        XCTAssertEqual(SpanishTextTypes.mentioned("Can you help me with my BLOG post?", [g, blog])?.slug, "blog")
        XCTAssertEqual(SpanishTextTypes.mentioned("I have to write a correo electronico formal", [g, blog])?.slug, "correo-formal")
        XCTAssertNil(SpanishTextTypes.mentioned("emails and blogging", [g, blog]), "whole words only")
        let p = SpanishGrade.Prompt(id: "p1", text: "Escribe un correo.", unit: "", types: ["correo electrónico"], source: "", added: "2026-11-23")
        let c = SpanishGrade.wordCount("Hola")
        let plain = SpanishGrade.gradePrompt(prompt: p, text: "Hola", count: c)
        XCTAssertFalse(plain.contains("The text type the student says they wrote"), "no guide, the prompt as before")
        let with = SpanishGrade.gradePrompt(prompt: p, text: "Hola", count: c, guide: SpanishTextTypes.conventions(g))
        XCTAssertTrue(with.contains("## The text type the student says they wrote, with its conventions from their guide (judge C against these as well as the descriptors; if the piece is really another type, judge it as what it is)\nCorreo electrónico formal (Formal email), register: Formal, usted\nStructure:"))
    }
}
