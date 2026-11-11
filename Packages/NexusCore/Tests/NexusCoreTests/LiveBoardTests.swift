import XCTest
@testable import NexusCore

/// The laptop and the iPad on one board at once (nexus docs/sync.md "Live on a board"): marks finding their words again (the table
/// `Fixtures/anchor-cases.json` is a copy of nexus `renderer/src/board/anchor-cases.json`, which the laptop's anchor.js passes too),
/// the hub's merges done before a save, conflict copies and drafts.
final class LiveBoardTests: XCTestCase {

    struct Cases: Decodable {
        struct Find: Decodable { var name: String; var text: String; var at: WordAnchor; var want: AnchorMatch?; var ghost: Int? }
        struct Make: Decodable { var text: String; var from: Int; var to: Int; var at: WordAnchor }
        var find: [Find]
        var make: [Make]
    }

    func cases() throws -> Cases {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("anchor-cases.json")
        return try JSONDecoder().decode(Cases.self, from: Data(contentsOf: url))
    }

    func testTheSharedAnchorTable() throws {
        let t = try cases()
        XCTAssertGreaterThanOrEqual(t.find.count, 10)
        for c in t.find {
            XCTAssertEqual(Anchor.find(c.text, c.at), c.want, c.name)
            if c.want == nil { XCTAssertEqual(Anchor.ghostAt(c.text, c.at), c.ghost, c.name + " (where the ghost waits)") }
        }
        for c in t.make { XCTAssertEqual(Anchor.make(c.text, from: c.from, to: c.to), c.at, c.text) }
    }

    func testRefreshAndSimilar() {
        let T = "abc def ghi\njkl"
        let a = Anchor.make(T, from: 4, to: 7)
        XCTAssertEqual(Anchor.refresh(T, a), a)
        XCTAssertEqual(Anchor.refresh("XX " + T, a), WordAnchor(q: "def", pre: "XX abc ", post: " ghi\njkl", i: 7))
        XCTAssertEqual(Anchor.refresh("nothing", a), a)
        XCTAssertEqual(Anchor.similar("loss of electrons", "loss of electrons"), 1)
        XCTAssertLessThan(Anchor.similar("OIL RIG", "It"), 0.3)
        XCTAssertGreaterThan(Anchor.similar("loss of electrons", "loss of an electron"), 0.7)
        XCTAssertEqual(WordAnchor(a.json), a)
    }

    func testLineMerge() {
        let base = "Essay\n\nFirst point.\nSecond point.\nThird point.\n"
        let mine = base.replacingOccurrences(of: "First point.", with: "First point, on the iPad.")
        let theirs = base.replacingOccurrences(of: "Third point.", with: "Third point, from the laptop.")
        XCTAssertEqual(LiveBoard.mergeBlock(base: base, mine: mine, theirs: theirs), "Essay\n\nFirst point, on the iPad.\nSecond point.\nThird point, from the laptop.\n")
        XCTAssertEqual(LiveBoard.mergeBlock(base: base, mine: base, theirs: theirs), theirs)
        XCTAssertEqual(LiveBoard.mergeBlock(base: base, mine: mine, theirs: base), mine)
        XCTAssertNil(LiveBoard.mergeBlock(base: base, mine: base.replacingOccurrences(of: "Second point.", with: "Second, iPad."), theirs: base.replacingOccurrences(of: "Second point.", with: "Second, laptop.")))
        // the hub's own cases (nexus dev/unit-hub.mjs)
        let Y = "tasks:\n  - id: a1\n    title: one\n  - id: b2\n    title: two\n  - id: c3\n    title: three\n"
        XCTAssertEqual(LiveBoard.mergeLines(base: Y, hub: Y + "  - id: d4\n    title: four\n", mine: Y + "  - id: e5\n    title: five\n"),
                       Y + "  - id: d4\n    title: four\n  - id: e5\n    title: five\n")
    }

    static func tile(_ ids: [String], items: [String] = []) -> String {
        BoardFiles.tileJSON(strokes: ids.map { BoardStroke(id: $0, ink: "com.apple.ink.pen", color: "#000000FF", points: [[10, 10, 1, 0, 1.5, 0, 2, 2, 1], [20, 20, 1, 0, 1.5, 0.1, 2, 2, 1]]) },
                            items: items.map { BoardItem(id: $0, type: "text", x: 100, y: 100) })
    }

    func testTileMergeByIdAsTheHub() {
        let base = Self.tile(["bbbbb"]), hub = Self.tile(["bbbbb", "hhhhh"]), mine = Self.tile(["bbbbb", "mmmmm"])
        XCTAssertEqual(LiveBoard.mergeTile(base: base, hub: hub, mine: mine), Self.tile(["bbbbb", "hhhhh", "mmmmm"]))
        XCTAssertEqual(LiveBoard.mergeTile(base: base, hub: Self.tile([]), mine: Self.tile(["bbbbb", "mmmmm"])), Self.tile(["mmmmm"]), "erased on the laptop, kept here only what is new")
        XCTAssertNil(LiveBoard.mergeTile(base: base, hub: "{nope", mine: mine))
    }

    func testConflictCopiesAndDrafts() throws {
        XCTAssertEqual(LiveBoard.textConflict("text/t5n7c (conflict iPad 2026-11-12 0815).md"), .init(id: "t5n7c", device: "iPad", date: "2026-11-12", time: "08:15"))
        XCTAssertEqual(LiveBoard.textConflict("text/t5n7c (conflict Zephyrus Duo 16 2026-11-12 0815 2).md")?.device, "Zephyrus Duo 16")
        XCTAssertNil(LiveBoard.textConflict("text/t5n7c.md"))
        XCTAssertNil(LiveBoard.textConflict("text/t5n7c~d2.md"))
        let now = Date(timeIntervalSince1970: 1_794_471_330) // 2026-11-12T08:15:30Z
        let d = LiveBoard.clashDraft(BoardItem(id: "t5n7c", type: "text", x: 1, y: 2), name: "From Zephyrus Duo 16 08:15", now: now)
        XCTAssertEqual(d.file, "text/t5n7c~d2.md")
        XCTAssertEqual(d.item.json["draft"]?.string, "d1")
        XCTAssertEqual(d.item.json["drafts"]?.array?.compactMap { $0["name"]?.string }, ["Draft 1", "From Zephyrus Duo 16 08:15"])
        XCTAssertEqual(d.item.json["drafts"]?.array?.first?["made"]?.string, "2026-11-12T08:15:30Z")
    }

    func testReconcileBeforeASave() throws {
        // the iPad read a board, drew a stroke and typed; meanwhile the laptop drew in the same tile and typed in the same block
        var c = BoardContent()
        c.meta = try JSONValue.parse(BoardFormat.boardJSON()); c.metaOnDisk = c.meta
        let item = BoardItem(id: "t5n7c", type: "text", x: 100, y: 100)
        let base = Self.tile(["bbbbb"], items: ["t5n7c"])
        c.tilesOnDisk["0_0"] = base
        c.textsOnDisk["t5n7c"] = "One\nTwo\nThree"
        c.items = [item]
        c.strokes = (try BoardFiles.parseTile(Self.tile(["bbbbb", "ipad1"]))).strokes
        c.texts["t5n7c"] = "One, on the iPad\nTwo\nThree"
        var disk = ["tiles/0_0.json": Self.tile(["bbbbb", "lap01"], items: ["t5n7c"]), "text/t5n7c.md": "One\nTwo\nThree, on the laptop"]
        var r = try LiveBoard.reconcile(c, read: { disk[$0] }, write: { disk[$0] = $1 }, device: "Zephyrus Duo 16")
        XCTAssertEqual(r.mergedTiles, ["0_0"])
        XCTAssertEqual(r.content.strokes.map(\.id).sorted(), ["bbbbb", "ipad1", "lap01"], "the laptop's stroke is kept")
        XCTAssertEqual(r.content.texts["t5n7c"], "One, on the iPad\nTwo\nThree, on the laptop", "different lines: both")
        XCTAssertEqual(BoardFiles.changes(r.content).tiles["0_0"], Self.tile(["bbbbb", "lap01", "ipad1"], items: ["t5n7c"]))
        // the same line on both: the iPad's words stay, the laptop's become a draft
        disk["text/t5n7c.md"] = "One, on the laptop\nTwo\nThree"
        disk["tiles/0_0.json"] = base
        r = try LiveBoard.reconcile(c, read: { disk[$0] }, write: { disk[$0] = $1 }, device: "Zephyrus Duo 16")
        XCTAssertEqual(r.content.texts["t5n7c"], "One, on the iPad\nTwo\nThree")
        XCTAssertEqual(r.drafts.count, 1)
        XCTAssertEqual(disk["text/t5n7c~d2.md"], "One, on the laptop\nTwo\nThree")
        XCTAssertEqual(r.content.items.first?.json["drafts"]?.array?.count, 2)
        XCTAssertEqual(BoardFiles.changes(r.content).texts["t5n7c"], "One, on the iPad\nTwo\nThree", "and the iPad's are written over the laptop's")
        // nothing written by anyone else: nothing to do
        r = try LiveBoard.reconcile(c, read: { [base] rel in rel == "tiles/0_0.json" ? base : "One\nTwo\nThree" }, write: { _, _ in XCTFail("no draft") }, device: "x")
        XCTAssertTrue(r.mergedTiles.isEmpty && r.mergedTexts.isEmpty && r.drafts.isEmpty)
    }

    func testPresenceOnABoard() {
        let list = [HubPresence(device: "Zephyrus Duo 16", board: "n/a.board", block: "t1", what: "typing"),
                    HubPresence(device: "Zephyrus Duo 16", board: "n/b.board", block: "t2", what: "typing")]
        let p = LiveBoard.on(list, board: "n/a.board")
        XCTAssertEqual(p.typing, ["t1": "Zephyrus Duo 16"])
        XCTAssertEqual(p.drawing, [])
    }
}
