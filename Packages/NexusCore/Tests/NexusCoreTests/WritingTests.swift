import XCTest
@testable import NexusCore

/// Writing on a board: the live preview's marks (the laptop's editor.js rules), the formatting edits and chemistry.
final class LiveMarkdownTests: XCTestCase {
    func r(_ a: Int, _ len: Int) -> NSRange { NSRange(location: a, length: len) }

    func hidden(_ text: String, caret: Int? = nil) -> [String] {
        let ns = text as NSString
        let sel = caret.map { NSRange(location: $0, length: 0) }
        return LiveMarkdown.shown(LiveMarkdown.parse(text), selection: sel).filter { $0.show == .hidden }.map { ns.substring(with: $0.range) }
    }

    func testLinesAndKinds() {
        let lines = LiveMarkdown.parse("# Title\n## Part\n\n- one\n- [ ] two\n- [x] three\n3. four\n> said\n---\nplain")
        XCTAssertEqual(lines.map(\.kind), [.heading(1), .heading(2), .blank, .bullet, .task(false), .task(true), .ordered(3), .text, .rule, .text])
        XCTAssertEqual(lines[7].quote, 1)
        XCTAssertEqual(lines[3].range, r(17, 5))
        XCTAssertEqual(lines[3].content, 19)
    }

    func testAPlainLineAfterAListItemCarriesItOn() {
        let lines = LiveMarkdown.parse("- one\n  more\n\nafter")
        XCTAssertTrue(lines[1].continues)
        XCTAssertFalse(lines[3].continues)
    }

    func testFencedCodeIsNotMarkdown() {
        let lines = LiveMarkdown.parse("```\n# not a heading\n**no**\n```\n**yes**")
        XCTAssertEqual(lines.map(\.kind), [.fence, .code, .code, .fence, .text])
        XCTAssertTrue(lines[2].spans.isEmpty)
        XCTAssertEqual(lines[4].spans.map(\.kind), [.bold])
    }

    func testHeadingMarksHideOffTheCaretLine() {
        XCTAssertEqual(hidden("# Title\nbody"), ["# "])
        XCTAssertEqual(hidden("# Title\nbody", caret: 3), [])
        XCTAssertEqual(hidden("# Title\nbody", caret: 9), ["# "])
    }

    func testEmphasisMarksHideUnlessTheSelectionTouchesThem() {
        let t = "a **bold** and *it* c"
        XCTAssertEqual(hidden(t), ["**", "**", "*", "*"])
        XCTAssertEqual(hidden(t, caret: 5), ["*", "*"])
        XCTAssertEqual(hidden(t, caret: 0), ["**", "**", "*", "*"])
        // touching the span's edge reveals it, as CodeMirror does
        XCTAssertEqual(hidden(t, caret: 2), ["*", "*"])
    }

    func testBoldItalicAndTheirSpans() {
        let line = LiveMarkdown.parse("***both*** __b__ _i_ snake_case_word")[0]
        XCTAssertEqual(line.spans.map(\.kind), [.italic, .bold, .bold, .italic])
        XCTAssertEqual(line.spans[0].range, r(0, 10))
    }

    func testCodeLinksHighlightsAndTheRest() {
        let t = "`x*y*` [site](https://a.b) ==hi== ~~no~~ <u>u</u> <mark data-c=\"green\">g</mark> <span data-c=\"red\">r</span> $x^2$"
        let kinds = LiveMarkdown.parse(t)[0].spans.map(\.kind)
        XCTAssertEqual(kinds, [.code, .link("https://a.b"), .highlight("yellow"), .strike, .underline, .highlight("green"), .color("red"),
                               .math(display: false)])
        XCTAssertEqual(hidden("[site](https://a.b)"), ["[", "](https://a.b)"])
    }

    func testANexusTaskChip() {
        let line = LiveMarkdown.parse("do [Buy milk](nexus-task:k3m9q) now")[0]
        XCTAssertEqual(line.spans.map(\.kind), [.nexusTask("k3m9q")])
    }

    func testReviewSuggestions() {
        let t = "a {++new++} b {--old--} c {~~was~>is~~}"
        let spans = LiveMarkdown.parse(t)[0].spans
        let ns = t as NSString
        XCTAssertEqual(spans.map(\.kind), [.added, .deleted, .deleted, .added])
        XCTAssertEqual(spans.map { ns.substring(with: $0.range) }, ["new", "old", "was", "is"])
        XCTAssertEqual(hidden(t), ["{++", "++}", "{--", "--}", "{~~", "~>", "~~}"])
    }

    func testListGlyphs() {
        let shown = LiveMarkdown.shown(LiveMarkdown.parse("- one\n- [x] done\n---"), selection: nil)
        XCTAssertEqual(shown.map(\.show), [.glyph(.bullet), .hidden, .glyph(.checkbox(true)), .glyph(.rule)])
        // on the caret's line the bullet shows as "-", the checkbox stays a box
        let active = LiveMarkdown.shown(LiveMarkdown.parse("- one\n- [x] done"), selection: NSRange(location: 8, length: 0))
        XCTAssertEqual(active.map(\.show), [.glyph(.bullet), .faint, .glyph(.checkbox(true))])
    }

    func testQuoteMarks() {
        XCTAssertEqual(hidden("> > deep\nnot"), ["> ", "> "])
    }

    func testMathNeedsNoSpaceInside() {
        XCTAssertTrue(LiveMarkdown.parse("costs $5 and $6")[0].spans.isEmpty)
        XCTAssertEqual(LiveMarkdown.parse("$$E=mc^2$$")[0].spans.map(\.kind), [.math(display: true)])
        XCTAssertEqual(LiveMarkdown.parse("$$\nx\n$$").map(\.kind), [.mathFence, .math, .mathFence])
    }

    func testEscapedStarsStayStars() {
        XCTAssertTrue(LiveMarkdown.parse("2 \\* 3 \\* 4")[0].spans.isEmpty)
    }

    func testCountsReadTheWordsWithoutTheirMarks() {
        let c = LiveMarkdown.count("# Title\n- [ ] **buy** milk\n\nTwo words")
        XCTAssertEqual(c.words, 5)
        XCTAssertEqual(LiveMarkdown.visibleText("**a** b"), "a b")
        XCTAssertEqual(LiveMarkdown.count("").words, 0)
    }

    func testUTF16Ranges() {
        // an emoji is two UTF-16 units; ranges stay in UTF-16
        let t = "😀 **b**"
        XCTAssertEqual(LiveMarkdown.parse(t)[0].spans.first?.range, r(3, 5))
    }
}

final class MarkdownEditTests: XCTestCase {
    func r(_ a: Int, _ len: Int = 0) -> NSRange { NSRange(location: a, length: len) }

    func testWrapAndUnwrap() {
        XCTAssertEqual(MarkdownEdit.wrap("a word b", r(2, 4), "**"), MDEdit("a **word** b", r(2, 8)))
        XCTAssertEqual(MarkdownEdit.wrap("a **word** b", r(4, 4), "**"), MDEdit("a word b", r(2, 4)))
        XCTAssertEqual(MarkdownEdit.wrap("a **word** b", r(2, 8), "**"), MDEdit("a word b", r(2, 4)))
        XCTAssertEqual(MarkdownEdit.wrap("ab", r(1), "*"), MDEdit("a**b", r(2)))
        // one star of a bold run is not italic
        XCTAssertEqual(MarkdownEdit.wrap("**word**", r(2, 4), "*"), MDEdit("***word***", r(2, 6)))
    }

    func testHighlightColoursAndUnderline() {
        XCTAssertEqual(MarkdownEdit.highlight("x", r(0, 1), color: "yellow").text, "==x==")
        XCTAssertEqual(MarkdownEdit.highlight("x", r(0, 1), color: "green").text, "<mark data-c=\"green\">x</mark>")
        XCTAssertEqual(MarkdownEdit.wrap("x", r(0, 1), "<u>", "</u>").text, "<u>x</u>")
        XCTAssertEqual(MarkdownEdit.textColor("x", r(0, 1), color: "red").text, "<span data-c=\"red\">x</span>")
    }

    func testLink() {
        XCTAssertEqual(MarkdownEdit.link("see it", r(4, 2)), MDEdit("see [it]()", r(9)))
    }

    func testWordAtTheCaret() {
        XCTAssertEqual(MarkdownEdit.wordRange("see the site", at: 6), r(4, 3))
        XCTAssertEqual(MarkdownEdit.wordRange("see the site", at: 4), r(4, 3))   // at its start
        XCTAssertEqual(MarkdownEdit.wordRange("see the site", at: 7), r(4, 3))   // at its end
        XCTAssertEqual(MarkdownEdit.wordRange("**año**", at: 3), r(2, 3))
        XCTAssertNil(MarkdownEdit.wordRange("a  b", at: 2))
        XCTAssertNil(MarkdownEdit.wordRange("", at: 0))
        XCTAssertNil(MarkdownEdit.wordRange("x, ", at: 3))
        // an emoji is two UTF-16 units and not part of a word
        XCTAssertEqual(MarkdownEdit.wordRange("😀ab", at: 4), r(2, 2))
    }

    func testTheLinkButton() {
        // a selection is linked as Ctrl+K does
        XCTAssertEqual(MarkdownEdit.linkWords("see it", r(4, 2)), MDEdit("see [it]()", r(9)))
        // no selection: the word at the caret
        XCTAssertEqual(MarkdownEdit.linkWords("see it now", r(5)), MDEdit("see [it]() now", r(9)))
        // no word there: nothing, so no stray []()
        XCTAssertNil(MarkdownEdit.linkWords("see  it", r(4)))
        XCTAssertNil(MarkdownEdit.linkWords("", r(0)))
        // the address box
        XCTAssertEqual(MarkdownEdit.linkAddress("a  b", r(2), " https://x.y "), MDEdit("a [https://x.y](https://x.y) b", r(28)))
        XCTAssertNil(MarkdownEdit.linkAddress("a", r(1), "  "))
    }

    func testListsToggleAndSwap() {
        XCTAssertEqual(MarkdownEdit.toggleLinePrefix("a\nb", r(0, 3), "- ").text, "- a\n- b")
        XCTAssertEqual(MarkdownEdit.toggleLinePrefix("- a\n- b", r(0, 7), "- ").text, "a\nb")
        XCTAssertEqual(MarkdownEdit.toggleLinePrefix("- a", r(3), "- [ ] ").text, "- [ ] a")
        XCTAssertEqual(MarkdownEdit.toggleLinePrefix("- [x] a", r(3), "- [ ] ").text, "a")
        XCTAssertEqual(MarkdownEdit.toggleLinePrefix("  - a", r(3), "1. ").text, "  1. a")
        XCTAssertEqual(MarkdownEdit.toggleLinePrefix("said", r(0), "> ").text, "> said")
    }

    func testStyles() {
        XCTAssertEqual(MarkdownEdit.setStyle("words", r(0), .title).text, "# words")
        XCTAssertEqual(MarkdownEdit.setStyle("# words", r(3), .h1).text, "## words")
        XCTAssertEqual(MarkdownEdit.setStyle("## words", r(3), .h1).text, "words")
        XCTAssertEqual(MarkdownEdit.setStyle("#### words", r(5), .body).text, "words")
        XCTAssertEqual(MarkdownEdit.setStyle("words", r(0), .quote).text, "> words")
        XCTAssertEqual(MarkdownEdit.setStyle("> words", r(3), .quote).text, "words")
        XCTAssertEqual(MarkdownEdit.setStyle("a\nb", r(0, 3), .code).text, "```\na\nb\n```")
        XCTAssertEqual(MarkdownEdit.setStyle("```\na\nb\n```", r(4), .code).text, "a\nb")
        XCTAssertEqual(MarkdownEdit.style("x\n### h\n> q", at: 4), .h2)
        XCTAssertEqual(MarkdownEdit.style("x\n### h\n> q", at: 9), .quote)
        XCTAssertEqual(MarkdownEdit.style("###### deep", at: 3), .h3)
    }

    func testReturnCarriesAListOn() {
        XCTAssertEqual(MarkdownEdit.newline("- a", r(3)), MDEdit("- a\n- ", r(6)))
        XCTAssertEqual(MarkdownEdit.newline("- [x] a", r(7)), MDEdit("- [x] a\n- [ ] ", r(14)))
        XCTAssertEqual(MarkdownEdit.newline("  9. a", r(6)), MDEdit("  9. a\n  10. ", r(13)))
        XCTAssertEqual(MarkdownEdit.newline("> q", r(3)), MDEdit("> q\n> ", r(6)))
        // an empty item ends the list
        XCTAssertEqual(MarkdownEdit.newline("- a\n- ", r(6)), MDEdit("- a\n", r(4)))
        XCTAssertNil(MarkdownEdit.newline("plain", r(5)))
    }

    func testTabIndentsListLines() {
        XCTAssertEqual(MarkdownEdit.indent("- a", r(3), out: false), MDEdit("  - a", r(5)))
        XCTAssertEqual(MarkdownEdit.indent("  - a", r(5), out: true), MDEdit("- a", r(3)))
        XCTAssertNil(MarkdownEdit.indent("plain", r(0), out: false))
    }

    func testFindAndReplace() {
        XCTAssertEqual(MarkdownEdit.find("cafe", in: "Café and CAFE"), [r(0, 4), r(9, 4)])
        XCTAssertEqual(MarkdownEdit.replace("a", with: "b", in: "a a").text, "b b")
    }
}

final class ChemTests: XCTestCase {
    /// The laptop's table (nexus docs/board-writing.md, dev/unit-boardblocks.mjs CHEM).
    let table: [(String, String)] = [
        ("H2O", "H₂O"), ("CO2", "CO₂"), ("C6H12O6", "C₆H₁₂O₆"), ("Ca(OH)2", "Ca(OH)₂"), ("2H2O", "2H₂O"), ("Fe2O3", "Fe₂O₃"),
        ("CH3COOH", "CH₃COOH"), ("SO4^2-", "SO₄²⁻"), ("SO42-", "SO₄²⁻"), ("NH4+", "NH₄⁺"), ("MnO4-", "MnO₄⁻"), ("Cr2O72-", "Cr₂O₇²⁻"),
        ("PO4^3-", "PO₄³⁻"), ("CO32-", "CO₃²⁻"), ("Fe3+", "Fe³⁺"), ("Cu2+", "Cu²⁺"), ("O2-", "O²⁻"), ("Na+", "Na⁺"), ("Cl-", "Cl⁻"),
        ("OH-", "OH⁻"), ("H+", "H⁺"), ("Na1+", "Na⁺"), ("CH3COO-", "CH₃COO⁻"), ("e-", "e⁻"), ("2e-", "2e⁻"), ("H2", "H₂"), ("O2", "O₂"),
        ("Cl2", "Cl₂"), ("P4", "P₄"), ("S8", "S₈"), ("H2O(l)", "H₂O(l)"), ("CO2(g)", "CO₂(g)"), ("H2O2", "H₂O₂"), ("(OH)2", "(OH)₂"),
        ("Mg(NO3)2", "Mg(NO₃)₂"), ("[Cu(H2O)6]2+", "[Cu(H₂O)₆]²⁺"), ("Fe2(SO4)3", "Fe₂(SO₄)₃"),
    ]
    let unchanged = ["NaCl(aq)", "NaCl", "HCl", "CO", "P2", "B2", "S1", "A1", "Q3", "U2", "H1", "MP3", "Win10", "x2", "IB", "2", "hello", "Step2"]

    func testTheLaptopsTable() {
        for (typed, stored) in table { XCTAssertEqual(Chem.formula(typed), stored, typed) }
        for w in unchanged { XCTAssertNil(Chem.formula(w), w) }
    }

    func testConvertsWhenTheWordEnds() {
        let t = "Water is H2O "
        let c = Chem.convert(t, caret: (t as NSString).length)
        XCTAssertEqual(c?.with, "H₂O")
        XCTAssertEqual(c?.range, NSRange(location: 9, length: 3))
        XCTAssertEqual(Chem.convert("(see H2O)", caret: 9)?.with, "H₂O")
        XCTAssertNil(Chem.convert("`H2O` ", caret: 5))
        XCTAssertNil(Chem.convert("$H2O ", caret: 5))
        XCTAssertNil(Chem.convert("xH2O ", caret: 5))
    }
}
