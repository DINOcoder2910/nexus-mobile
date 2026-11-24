import XCTest
@testable import NexusCore

/// Spanish underlines on a board's typed blocks (SpanishBlock, the laptop's desktop/src/board/spanish.ts): paragraphs as plain words,
/// marks placed back in the markdown, the paragraphs already read, which blocks are checked.
final class SpanishBlockTests: XCTestCase {
    private func mark(_ s: Int, _ e: Int, _ wrong: String, _ right: String, kind: String = "error") -> SpanishCheck.Mark {
        SpanishCheck.Mark(s: s, e: e, wrong: wrong, right: right, skill: kind == "accent" ? "accent.stress" : "verb.preterite", kind: kind, why: "", by: "claude")
    }

    func testParagraphsLeaveOutTheMarks() {
        let md = "# Mis vacaciones\n\n**Yo** soy de *España* y me gusta mucho.\n\n- Ayer yo voy al cine con `code` amigos\n```\nno\n```"
        let ps = SpanishBlock.paragraphs(md)
        XCTAssertEqual(ps.map(\.text), ["Mis vacaciones", "Yo soy de España y me gusta mucho.", "Ayer yo voy al cine con  amigos"])
        let ns = md as NSString
        // every unit of a paragraph's words maps to the same unit in the markdown
        for p in ps {
            let u = Array(p.text.utf16)
            XCTAssertEqual(u.count, p.map.count)
            for (i, at) in p.map.enumerated() { XCTAssertEqual(ns.character(at: at), u[i]) }
        }
        XCTAssertTrue(SpanishBlock.worth("Mis vacaciones"))
        XCTAssertFalse(SpanishBlock.worth("Hola"))
        XCTAssertFalse(SpanishBlock.worth("12 + 3"))
    }

    func testMarksArePlacedInTheMarkdown() {
        let md = "Hola.\n\n**Ayer** yo voy al *cine* con mis amigos."
        let para = SpanishBlock.paragraphs(md)[1]
        XCTAssertEqual(para.text, "Ayer yo voy al cine con mis amigos.")
        var known = SpanishBlock.Known()
        known.set(para.text, [mark(8, 11, "voy", "fui"), mark(15, 19, "cine", "cine")])
        let placed = SpanishBlock.place(md, known: known.get)
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual((md as NSString).substring(with: placed[0].range), "voy")
        XCTAssertEqual((md as NSString).substring(with: placed[1].range), "cine")
        // a paragraph changed since it was read has no marks until it is read again
        XCTAssertTrue(SpanishBlock.place(md.replacingOccurrences(of: "voy", with: "fui"), known: known.get).isEmpty)
        // Correct this: one fix per range, in order
        let f = SpanishBlock.fixes(placed)
        XCTAssertEqual(f.map(\.fix), ["fui", "cine"])
    }

    func testTheCheckersAnswerAsMarks() {
        let ai = SpanishCheck.AI(corrected: "Ayer fui al cine.", mistakes: [.init(wrong: "voy", right: "fui", skill: "verb.preterite", why: "a finished past action"),
                                                                       .init(wrong: "nada", right: "algo", skill: "vocab", why: "not in the sentence"),
                                                                       .init(wrong: "cine", right: "cine", skill: "vocab", why: "the same")])
        let m = SpanishBlock.marks("  Ayer voy al cine.", ai)
        XCTAssertEqual(m.count, 1)
        XCTAssertEqual(m[0].wrong, "voy")
        XCTAssertEqual(m[0].s, 7)
        XCTAssertEqual(m[0].e, 10)
        XCTAssertTrue(SpanishBlock.marks("Ayer voy al cine.", nil).isEmpty)
    }

    func testWholeBlockSplitsBackIntoParagraphs() {
        let md = "Ayer voy al cine.\n\nMe gusta *mucho* la playa."
        let w = SpanishBlock.whole(md)
        XCTAssertEqual(w.text, "Ayer voy al cine.\nMe gusta mucho la playa.")
        let marks = [mark(5, 8, "voy", "fui"), mark(21, 26, "gusta", "encanta")]
        let parts = SpanishBlock.split(md, marks)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].marks.map(\.s), [5])
        XCTAssertEqual(parts[1].marks.map(\.s), [3])
        XCTAssertEqual(parts[1].marks.map(\.e), [8])
    }

    func testKnownKeepsTheNewestAndRoundTrips() {
        var k = SpanishBlock.Known()
        for i in 0..<(SpanishBlock.Known.max + 5) { k.set("frase \(i)", i == SpanishBlock.Known.max + 4 ? [mark(0, 5, "frase", "Frase", kind: "accent")] : []) }
        XCTAssertEqual(k.order.count, SpanishBlock.Known.max)
        XCTAssertFalse(k.has("frase 0"))
        XCTAssertTrue(k.has("frase 5"))
        let back = SpanishBlock.Known.decode(k.encode())
        XCTAssertEqual(back.order, k.order)
        XCTAssertEqual(back.get("frase \(SpanishBlock.Known.max + 4)")?.first?.right, "Frase")
        XCTAssertEqual(back.get("frase \(SpanishBlock.Known.max + 4)")?.first?.kind, "accent")
        XCTAssertNil(SpanishBlock.Known.decode("not json").get("x"))
    }

    func testWhichBlocksAreChecked() {
        let es = "Ayer yo fui al cine con mis amigos y me gustó mucho."
        func item(_ fields: [(String, JSONValue)]) -> BoardItem {
            BoardItem(id: "b1", type: "text", x: 0, y: 0, fields: fields)
        }
        XCTAssertEqual(SpanishBlock.langBy(item([]), es), "detected")
        XCTAssertEqual(SpanishBlock.langBy(item([("lang", .string("es"))]), "Hello there"), "set")
        XCTAssertNil(SpanishBlock.langBy(item([("lang", .string("en"))]), es))
        XCTAssertNil(SpanishBlock.langBy(item([]), "I went to the cinema with my friends and it was fun."))
        XCTAssertTrue(SpanishBlock.checking(item([]), es))
        XCTAssertFalse(SpanishBlock.checking(item([("check", .bool(false))]), es))
        XCTAssertFalse(SpanishBlock.checking(item([("practice", Practice.field(minutes: 15))]), es))
    }
}
