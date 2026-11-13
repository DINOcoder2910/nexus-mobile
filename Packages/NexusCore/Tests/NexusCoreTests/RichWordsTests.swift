import XCTest
@testable import NexusCore

/// A block's words as the laptop keeps them (nexus docs/rich-text.md): text/<id>.jsonl beside the .md copy, read and written with the laptop's
/// own converters in JavaScriptCore (RichWords). `Fixtures/rich-block.jsonl` was written by the laptop's code (tools/richtext/core.js under
/// Node) with a Google Docs link in its header; `rich-block.md` is its words.
final class RichWordsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rich-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        RichWords.device = "iPad"
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func fixture(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func write(_ rel: String, _ text: String) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ rel: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8) }

    func ids(_ jsonl: String) -> [String] {
        jsonl.split(separator: "\n").dropFirst().compactMap { (try? JSONValue.parse(String($0)))?["id"]?.string }
    }

    // MARK: the converters

    func testTheLaptopsFileReadsTheSame() throws {
        let jsonl = try fixture("rich-block.jsonl"), md = try fixture("rich-block.md")
        XCTAssertEqual(RichWords.shared.words(jsonl), md, RichWords.shared.lastError ?? "")
        let r = RichWords.shared.read(jsonl: jsonl, file: md)
        XCTAssertEqual(r, RichWords.Read(md: md, how: "json", stale: false))
        // the same words write the same file back, byte for byte (ids, who wrote what, the Google link)
        XCTAssertEqual(RichWords.shared.write(md: md, prevJsonl: jsonl, prevMd: md), jsonl)
        XCTAssertEqual(RichWords.shared.header(jsonl)?["google"]?["doc"]?.string, "1AbC")
    }

    func testAnEditKeepsIdsAndTheHeader() throws {
        let jsonl = try fixture("rich-block.jsonl"), md = try fixture("rich-block.md")
        let edited = md.replacingOccurrences(of: "is _fast_", with: "is _slow_")
        let out = try XCTUnwrap(RichWords.shared.write(md: edited, prevJsonl: jsonl, prevMd: md), RichWords.shared.lastError ?? "")
        XCTAssertEqual(ids(out), ids(jsonl), "every paragraph keeps its id")
        XCTAssertEqual(RichWords.shared.header(out)?["google"]?["doc"]?.string, "1AbC", "the Google link stays")
        XCTAssertEqual(RichWords.shared.words(out), edited)
        let changed = out.split(separator: "\n").first { $0.contains("slow") }.map(String.init) ?? ""
        XCTAssertTrue(changed.contains("\"by\":\"iPad\""), "the changed paragraph is credited to the iPad: \(changed)")
        let kept = out.split(separator: "\n").first { $0.contains("Why chemistry") }.map(String.init) ?? ""
        XCTAssertTrue(kept.contains("\"by\":\"laptop\""), "the others keep their author")
    }

    func testABlockFromBeforeTheSwitch() {
        let r = RichWords.shared.read(jsonl: nil, file: "# Hello\n- [ ] one\n")
        XCTAssertEqual(r.how, "converted")
        XCTAssertEqual(r.md, "# Hello\n- [ ] one\n")
        XCTAssertTrue(r.stale)
        let j = RichWords.shared.write(md: r.md, prevJsonl: nil, prevMd: nil)
        XCTAssertEqual(j?.split(separator: "\n").count, 3, j ?? "")
    }

    func testACopyEditedOutsideNexusComesIn() throws {
        let jsonl = try fixture("rich-block.jsonl"), md = try fixture("rich-block.md")
        let edited = md + "\n\nA new line typed in another editor."
        let r = RichWords.shared.read(jsonl: jsonl, file: edited)
        XCTAssertEqual(r.how, "outside")
        XCTAssertEqual(r.md, edited)
        XCTAssertTrue(r.stale)
    }

    func testANewerJsonlWinsOverAStaleCopy() throws {
        let jsonl = try fixture("rich-block.jsonl"), md = try fixture("rich-block.md")
        let r = RichWords.shared.read(jsonl: jsonl, file: "Old words", jsonlNewer: true)
        XCTAssertEqual(r, RichWords.Read(md: md, how: "jsonl", stale: false))
    }

    func testTheCopysChecksumLine() {
        XCTAssertEqual(RichWords.body("Words\n\n<!-- nexus-copy 0123456789abcdef -->\n"), "Words")
        XCTAssertEqual(RichWords.body("Words\r\nmore"), "Words\nmore")
        XCTAssertEqual(RichWords.body("Plain"), "Plain")
    }

    func testSetHeader() throws {
        let jsonl = try fixture("rich-block.jsonl")
        let off = try XCTUnwrap(RichWords.shared.setHeader(jsonl, key: "google", json: nil))
        XCTAssertNil(RichWords.shared.header(off)?["google"])
        XCTAssertEqual(ids(off), ids(jsonl))
    }

    // MARK: on a board

    static let meta = "{\n  \"format\": \"nexus-board/1\",\n  \"created\": \"2026-11-11T09:30Z\",\n  \"tile\": 1024\n}\n"
    static let tile = BoardFiles.tileJSON(strokes: [], items: [BoardItem(id: "txt22", type: "text", x: 50, y: 50)])

    func testABoardWritesTheJsonlBesideTheCopy() throws {
        try write("B.board/board.json", Self.meta)
        try write("B.board/tiles/0_0.json", Self.tile)
        try write("B.board/text/txt22.md", "# Hello\n\nOne line.")
        let board = dir.appendingPathComponent("B.board")
        var c = try BoardFiles.load(board)
        XCTAssertEqual(c.texts["txt22"], "# Hello\n\nOne line.")
        XCTAssertTrue(c.docsStale.contains("txt22"), "a block from before the switch gets its .jsonl with the next save")
        c.texts["txt22"] = "# Hello\n\nOne line, typed on the iPad."
        c = try BoardFiles.save(c, to: board, write: { url, text in try text.write(to: url, atomically: true, encoding: .utf8) })
        let jsonl = try XCTUnwrap(read("B.board/text/txt22.jsonl"))
        XCTAssertEqual(RichWords.shared.words(jsonl), "# Hello\n\nOne line, typed on the iPad.")
        XCTAssertEqual(read("B.board/text/txt22.md"), "# Hello\n\nOne line, typed on the iPad.", "the copy stays plain, as the laptop writes it")
        XCTAssertFalse(c.docsStale.contains("txt22"))
        XCTAssertTrue(BoardFiles.changes(c).docs.allSatisfy { BoardFiles.docToWrite(c, id: $0) == nil }, "nothing more to write")

        // read again: the same words, ids kept on the next edit
        var again = try BoardFiles.load(board)
        XCTAssertEqual(again.texts["txt22"], "# Hello\n\nOne line, typed on the iPad.")
        XCTAssertEqual(again.docsOnDisk["txt22"], jsonl)
        again.texts["txt22"] = "# Hello again\n\nOne line, typed on the iPad."
        again = try BoardFiles.save(again, to: board, write: { url, text in try text.write(to: url, atomically: true, encoding: .utf8) })
        XCTAssertEqual(ids(try XCTUnwrap(read("B.board/text/txt22.jsonl"))), ids(jsonl))
    }

    func testTheGoogleBridgesJsonlIsMergedBeforeASave() throws {
        let jsonl = try fixture("rich-block.jsonl"), md = try fixture("rich-block.md")
        try write("B.board/board.json", Self.meta)
        try write("B.board/tiles/0_0.json", Self.tile)
        try write("B.board/text/txt22.md", md)
        try write("B.board/text/txt22.jsonl", jsonl)
        let board = dir.appendingPathComponent("B.board")
        var c = try BoardFiles.load(board)
        XCTAssertEqual(c.texts["txt22"], md)
        // the iPad types at the top; meanwhile Google's words arrive in the .jsonl only (the bridge never writes the copy)
        c.texts["txt22"] = md.replacingOccurrences(of: "# Why chemistry", with: "# Why chemistry, from the iPad")
        let google = try XCTUnwrap(RichWords.shared.write(md: md.replacingOccurrences(of: "> A quote", with: "> A quote from Google"), prevJsonl: jsonl, prevMd: md))
        try write("B.board/text/txt22.jsonl", google)
        let r = try LiveBoard.reconcile(c, read: { rel in self.read("B.board/" + rel) }, write: { rel, text in try self.write("B.board/" + rel, text) }, device: "Google Docs")
        let words = try XCTUnwrap(r.content.texts["txt22"])
        XCTAssertTrue(words.contains("from the iPad") && words.contains("A quote from Google"), words)
        c = try BoardFiles.save(r.content, to: board, write: { url, text in try text.write(to: url, atomically: true, encoding: .utf8) })
        let out = try XCTUnwrap(read("B.board/text/txt22.jsonl"))
        XCTAssertEqual(RichWords.shared.words(out), words)
        XCTAssertEqual(RichWords.shared.header(out)?["google"]?["doc"]?.string, "1AbC")
        XCTAssertEqual(read("B.board/text/txt22.md"), words)
    }

    func testAJsonlConflictCopy() {
        let c = LiveBoard.textConflict("text/t5n7c (conflict iPad 2026-11-12 0815).jsonl")
        XCTAssertEqual(c, .init(id: "t5n7c", device: "iPad", date: "2026-11-12", time: "08:15", ext: ".jsonl"))
        XCTAssertEqual(LiveBoard.textConflict("text/t5n7c (conflict iPad 2026-11-12 0815).md")?.ext, ".md")
    }
}
