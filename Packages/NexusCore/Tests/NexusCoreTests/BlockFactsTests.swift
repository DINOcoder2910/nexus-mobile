import XCTest
@testable import NexusCore

final class BlockFactsTests: XCTestCase {
    func testCountsLeaveOutMarksAndTakenOutWords() {
        XCTAssertEqual(BlockFacts.wordCount("Hello {--there--} {++dear++} [friend](https://x.y)"), 3)
        XCTAssertEqual(BlockFacts.charCount("**ab** c"), 3)
    }

    func testLanguage() {
        XCTAssertEqual(BlockFacts.lang(nil, "Hola, ¿cómo estás? Yo estoy muy bien, gracias."), "es")
        XCTAssertEqual(BlockFacts.lang(nil, "The cat sat on the mat and it was happy."), "en")
        XCTAssertNil(BlockFacts.lang(nil, "H2O"))
        XCTAssertEqual(BlockFacts.lang(BoardItem(id: "b", type: "text", x: 0, y: 0, fields: [("lang", .string("es"))]), "the"), "es")
    }

    func testChip() {
        let c = BlockFacts.chip(nil, "# Shopping\n- [x] milk\n- [ ] eggs")
        XCTAssertEqual(c.title, "Shopping")
        XCTAssertEqual(c.line, "3 words · 1 of 2 done")
        XCTAssertEqual(c.kind, "checklist")
        XCTAssertEqual(BlockFacts.chip(nil, "").title, "Empty block")
    }
}
