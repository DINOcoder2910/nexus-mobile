import XCTest
@testable import NexusCore

/// The board files must be what the laptop's renderer/src/board/format.js writes, byte for byte.
final class BoardTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("board-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ rel: String, _ text: String) throws {
        let url = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ rel: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8) }

    static let fieldsLine = "{\"format\":\"nexus-board-tile/1\",\"pointFields\":[\"x\",\"y\",\"force\",\"azimuth\",\"altitude\",\"t\",\"w\",\"h\",\"opacity\"],\n"

    // MARK: numbers and JSON

    func testNumbersAsJavaScriptPrintsThem() {
        let cases: [(Double, String)] = [
            (100, "100"), (2.4, "2.4"), (-0.5, "-0.5"), (1.571, "1.571"), (0, "0"), (-0.0, "0"),
            (0.1 + 0.2, "0.30000000000000004"), (0.00001, "0.00001"), (0.000001, "0.000001"), (1e-7, "1e-7"),
            (1.5e-7, "1.5e-7"), (1e21, "1e+21"), (1e20, "100000000000000000000"), (1.2345678901234568e20, "123456789012345680000"),
            (-1234.5678, "-1234.5678"), (1e15, "1000000000000000"), (2.5e15, "2500000000000000"), (1.5707963267948966, "1.5707963267948966"),
        ]
        for (n, want) in cases { XCTAssertEqual(JSONValue.format(n), want, "\(n)") }
    }

    func testJSONRoundTripKeepsKeyOrderAndEscapes() throws {
        let text = "{\"b\":1,\"a\":[true,false,null,\"x\\\"y\\\\z\\n\\u0001é\"],\"c\":{\"z\":-2.5,\"y\":\"😀\"}}"
        let v = try JSONValue.parse(text)
        XCTAssertEqual(v.text, text)
        XCTAssertEqual(try JSONValue.parse("\"\\ud83d\\ude00\"").string, "😀")
        XCTAssertEqual(v["c"]?["z"]?.number, -2.5)
        XCTAssertEqual(v.setting("a", nil).setting("d", .number(3)).text, "{\"b\":1,\"c\":{\"z\":-2.5,\"y\":\"😀\"},\"d\":3}")
        XCTAssertThrowsError(try JSONValue.parse("{\"a\":1"))
        XCTAssertThrowsError(try JSONValue.parse("[1] x"))
    }

    // MARK: tiles

    func testTileJSONIsTheLaptopsLayout() {
        let s = BoardStroke(id: "abcde", ink: "com.apple.ink.pen", color: "#000000FF", points: [[10, 20, 1, 0, 1.571, 0, 2.4, 2.4, 1]])
        let text = BoardItem(id: "t2222", type: "text", x: 100.456, y: 5, fields: [("w", .number(560)), ("_md", .string("hidden"))])
        let shape = BoardItem(id: "s1111", type: "shape", x: 3, y: 4, fields: [("shape", .string("ellipse")), ("w", .number(50)), ("h", .number(20.004))])
        let out = BoardFiles.tileJSON(strokes: [s], items: [text, shape])
        XCTAssertEqual(out, expectedTwoItems())
        XCTAssertEqual(BoardFiles.tileJSON(strokes: [], items: []), BoardTests.fieldsLine + "\"strokes\":[],\n\"items\":[]}\n")
    }

    func expectedTwoItems() -> String {
        BoardTests.fieldsLine
            + "\"strokes\":[\n{\"id\":\"abcde\",\"ink\":\"com.apple.ink.pen\",\"color\":\"#000000FF\",\"points\":[[10,20,1,0,1.571,0,2.4,2.4,1]]}\n],\n"
            + "\"items\":[\n{\"id\":\"s1111\",\"type\":\"shape\",\"x\":3,\"y\":4,\"shape\":\"ellipse\",\"w\":50,\"h\":20},\n"
            + "{\"id\":\"t2222\",\"type\":\"text\",\"x\":100.46,\"y\":5,\"w\":560}\n]}\n"
    }

    /// A tile as the laptop wrote it (a stroke with a key the iPad doesn't know, items in id order) reads and writes back unchanged.
    func testTileRoundTripIsByteForByte() throws {
        let tile = BoardTests.fieldsLine
            + "\"strokes\":[\n{\"id\":\"k7mpq\",\"ink\":\"com.apple.ink.marker\",\"color\":\"#FFD60A80\",\"points\":[[1.5,2.25,0.8,1.2,0.9,0,20,20,1],[30,40,1,0,1.571,0.05,20,20,1]],\"ranges\":[[0,0.5]],\"from\":\"laptop\"},\n"
            + "{\"ink\":\"com.apple.ink.pen\",\"id\":\"b2b2b\",\"color\":\"#000000FF\",\"points\":[[5,5,1,0,1.571,0,2.5,2.5,1]]}\n],\n"
            + "\"items\":[\n{\"id\":\"img22\",\"type\":\"image\",\"x\":10,\"y\":10,\"w\":300,\"h\":200,\"src\":\"files/a b.png\"},\n"
            + "{\"id\":\"p3333\",\"type\":\"pdf\",\"x\":60,\"y\":60,\"src\":\"../Book.pdf\",\"w\":820,\"gap\":24,\"page\":2}\n]}\n"
        let t = try BoardFiles.parseTile(tile)
        XCTAssertEqual(t.strokes.count, 2)
        XCTAssertEqual(t.strokes[0].ranges ?? [], [[0, 0.5]])
        XCTAssertEqual(t.items.map(\.type), ["image", "pdf"])
        XCTAssertEqual(BoardFiles.tileJSON(strokes: t.strokes, items: t.items), tile)

        // a stroke that changed is written in the laptop's order, its unknown key kept
        var moved = t.strokes[0]
        moved.points[0][0] = 2
        let line = moved.json.text
        XCTAssertEqual(line, "{\"id\":\"k7mpq\",\"ink\":\"com.apple.ink.marker\",\"color\":\"#FFD60A80\",\"points\":[[2,2.25,0.8,1.2,0.9,0,20,20,1],[30,40,1,0,1.571,0.05,20,20,1]],\"ranges\":[[0,0.5]],\"from\":\"laptop\"}")
    }

    func testTileWithOtherPointFieldsIsRemapped() throws {
        let tile = "{\"format\":\"nexus-board-tile/1\",\"pointFields\":[\"y\",\"x\",\"force\"],\"strokes\":[{\"id\":\"aaaaa\",\"ink\":\"x\",\"color\":\"red\",\"points\":[[2,1,0.5],[\"bad\"]]}],\"items\":[{\"id\":\"q\",\"type\":\"nope\",\"x\":0,\"y\":0},{\"id\":\"r\",\"type\":\"shape\",\"x\":0,\"y\":0,\"shape\":\"star\"}]}"
        let t = try BoardFiles.parseTile(tile)
        XCTAssertEqual(t.strokes.count, 1)
        XCTAssertEqual(t.strokes[0].points, [[1, 2, 0.5, 0, Double.pi / 2, 0, 2, 2, 1]])
        XCTAssertEqual(t.strokes[0].color, "#000000FF")
        XCTAssertEqual(t.items.count, 2, "an item of a type a newer Nexus made is kept")
        XCTAssertTrue(t.items[0].isForeign)
        XCTAssertEqual(t.items[1].shape, "rect")
    }

    func testTileKeys() {
        XCTAssertEqual(BoardFormat.tileKey(0, 0), "0_0")
        XCTAssertEqual(BoardFormat.tileKey(1023.9, 1024), "0_1")
        XCTAssertEqual(BoardFormat.tileKey(-0.5, -1025), "-1_-2")
        XCTAssertEqual(BoardFormat.keyOfFile("-1_3.json"), "-1_3")
        XCTAssertNil(BoardFormat.keyOfFile("a_3.json"))
        XCTAssertNil(BoardFormat.keyOfFile("1_3.txt"))
        let id = BoardFormat.newId(taken: [])
        XCTAssertEqual(id.count, 5)
        XCTAssertTrue(id.allSatisfy { "abcdefghijkmnopqrstuvwxyz23456789".contains($0) })
    }

    // MARK: a board folder

    func makeBoard() throws -> URL {
        try write("B.board/board.json", "{\n  \"format\": \"nexus-board/1\",\n  \"created\": \"2026-11-11T09:30Z\",\n  \"tile\": 1024\n}\n")
        let a = BoardFiles.tileJSON(strokes: [BoardStroke(id: "aaaaa", ink: "com.apple.ink.pen", color: "#000000FF", points: [[10, 10, 1, 0, 1.571, 0, 2, 2, 1]])],
                                    items: [BoardItem(id: "txt22", type: "text", x: 50, y: 50, fields: [("w", .number(560))])])
        let b = BoardFiles.tileJSON(strokes: [BoardStroke(id: "bbbbb", ink: "com.apple.ink.pen", color: "#000000FF", points: [[-100, 2000, 1, 0, 1.571, 0, 2, 2, 1]])], items: [])
        try write("B.board/tiles/0_0.json", a)
        try write("B.board/tiles/-1_1.json", b)
        try write("B.board/text/txt22.md", "# Hello\n- [ ] one\n")
        return dir.appendingPathComponent("B.board")
    }

    func testLoadAndNothingChanged() throws {
        let board = try makeBoard()
        let c = try BoardFiles.load(board)
        XCTAssertNil(c.readOnly)
        XCTAssertEqual(c.created, "2026-11-11T09:30Z")
        XCTAssertEqual(Set(c.strokes.map(\.id)), ["aaaaa", "bbbbb"])
        XCTAssertEqual(c.items.map(\.id), ["txt22"])
        XCTAssertEqual(c.texts["txt22"], "# Hello\n- [ ] one\n")
        let ch = BoardFiles.changes(c)
        XCTAssertTrue(ch.tiles.isEmpty)
        XCTAssertTrue(ch.texts.isEmpty)
        XCTAssertTrue(ch.removedTexts.isEmpty)
    }

    func testOnlyTouchedTilesAreWritten() throws {
        let board = try makeBoard()
        var c = try BoardFiles.load(board)
        let before = read("B.board/tiles/-1_1.json")
        // a new stroke far away, and the stroke in 0_0 erased
        c.strokes.removeAll { $0.id == "aaaaa" }
        c.strokes.append(BoardStroke(id: "ccccc", ink: "com.apple.ink.pencil", color: "#FF0000FF", points: [[5000, 5000, 1, 0, 1.571, 0, 3, 3, 1]]))
        c.texts["txt22"] = "# Hello\n- [x] one\n"
        let ch = BoardFiles.changes(c)
        XCTAssertEqual(Set(ch.tiles.keys), ["0_0", "4_4"])
        var written: [String] = []
        c = try BoardFiles.save(c, to: board, write: { url, text in
            written.append(url.path.replacingOccurrences(of: board.path + "/", with: ""))
            try text.write(to: url, atomically: true, encoding: .utf8)
        })
        XCTAssertEqual(Set(written), ["tiles/0_0.json", "tiles/4_4.json", "text/txt22.md"])
        XCTAssertEqual(read("B.board/tiles/-1_1.json"), before)
        // 0_0 keeps its text item, the stroke is gone
        XCTAssertEqual(read("B.board/tiles/0_0.json"), BoardTests.fieldsLine + "\"strokes\":[],\n\"items\":[\n{\"id\":\"txt22\",\"type\":\"text\",\"x\":50,\"y\":50,\"w\":560}\n]}\n")
        XCTAssertEqual(read("B.board/text/txt22.md"), "# Hello\n- [x] one\n")
        XCTAssertTrue(BoardFiles.changes(c).tiles.isEmpty)

        // the text block removed: its tile is written empty and its markdown deleted
        c.items.removeAll()
        c.texts["txt22"] = nil
        c = try BoardFiles.save(c, to: board, write: { url, text in try text.write(to: url, atomically: true, encoding: .utf8) })
        XCTAssertEqual(read("B.board/tiles/0_0.json"), BoardTests.fieldsLine + "\"strokes\":[],\n\"items\":[]}\n")
        XCTAssertNil(read("B.board/text/txt22.md"))
        let again = try BoardFiles.load(board)
        XCTAssertEqual(Set(again.strokes.map(\.id)), ["bbbbb", "ccccc"])
    }

    func testBrokenTileIsNeverWrittenOver() throws {
        let board = try makeBoard()
        try write("B.board/tiles/3_3.json", "{\"strokes\":[ half a sync conflict")
        var c = try BoardFiles.load(board)
        XCTAssertEqual(c.strokes.count, 2)
        XCTAssertNil(BoardFiles.changes(c).tiles["3_3"])
        c.strokes.append(BoardStroke(id: "ddddd", ink: "com.apple.ink.pen", color: "#000000FF", points: [[1, 1, 1, 0, 1.571, 0, 2, 2, 1]]))
        XCTAssertNil(BoardFiles.changes(c).tiles["3_3"])
    }

    func testNewerFormatIsReadOnly() throws {
        try write("N.board/board.json", "{\"format\":\"nexus-board/2\"}")
        let c = try BoardFiles.load(dir.appendingPathComponent("N.board"))
        XCTAssertNotNil(c.readOnly)
        var wrote = false
        _ = try BoardFiles.save(c, to: dir.appendingPathComponent("N.board"), write: { _, _ in wrote = true })
        XCTAssertFalse(wrote)
        try write("X.board/board.json", "{\"format\":\"something else\"}")
        XCTAssertThrowsError(try BoardFiles.load(dir.appendingPathComponent("X.board")))
    }

    func testUnknownFeaturesAreReadOnly() throws {
        try write("F.board/board.json", "{\"format\":\"nexus-board/1\",\"features\":[\"cards\",\"links\",\"cards\"],\"paper\":{\"kind\":\"dots\"}}")
        let c = try BoardFiles.load(dir.appendingPathComponent("F.board"))
        XCTAssertEqual(c.readOnly, "This board uses cards, links from a newer Nexus. Update the iPad app to edit it.")
        var wrote = false
        _ = try BoardFiles.save(c, to: dir.appendingPathComponent("F.board"), write: { _, _ in wrote = true })
        XCTAssertFalse(wrote)
        XCTAssertEqual(BoardFormat.unknownFeatures(try JSONValue.parse("{\"features\":[\"space\"]}"), known: ["space"]), [])
        try write("E.board/board.json", "{\"format\":\"nexus-board/1\",\"features\":[]}")
        XCTAssertNil(try BoardFiles.load(dir.appendingPathComponent("E.board")).readOnly)
    }

    /// board.json changes (a feature, the paper) are written as the laptop writes them, keeping keys this app doesn't know.
    func testMetaIsWrittenWhenItChanges() throws {
        try write("M.board/board.json", "{\n  \"format\": \"nexus-board/1\",\n  \"created\": \"2026-11-12T09:00Z\",\n  \"tile\": 1024,\n  \"later\": {\"a\": [1, 2]}\n}\n")
        let board = dir.appendingPathComponent("M.board")
        var c = try BoardFiles.load(board)
        var writes: [String: String] = [:]
        let w: (URL, String) throws -> Void = { url, text in writes[url.lastPathComponent] = text; try text.write(to: url, atomically: true, encoding: .utf8) }
        c = try BoardFiles.save(c, to: board, write: w)
        XCTAssertNil(writes["board.json"], "nothing changed, nothing written")
        let m = BoardFormat.withFeature(c.meta!, "space")
        XCTAssertEqual(BoardFormat.withFeature(m, "space"), m)
        c.meta = m.setting("paper", .object([("kind", .string("dots")), ("size", .number(24))]))
        c = try BoardFiles.save(c, to: board, write: w)
        XCTAssertEqual(writes["board.json"], "{\n  \"format\": \"nexus-board/1\",\n  \"created\": \"2026-11-12T09:00Z\",\n  \"tile\": 1024,\n  \"later\": {\n    \"a\": [\n      1,\n      2\n    ]\n  },\n  \"features\": [\n    \"space\"\n  ],\n  \"paper\": {\n    \"kind\": \"dots\",\n    \"size\": 24\n  }\n}\n")
        XCTAssertEqual(try BoardFiles.load(board).meta, c.meta)
        XCTAssertEqual(JSONValue.object([]).pretty, "{}")
        XCTAssertEqual(JSONValue.array([]).pretty, "[]")
    }

    /// An item a newer Nexus made is kept and written back exactly as the laptop writes it (JSON.stringify of what was read).
    func testForeignItemsAreKeptAsTheyWere() throws {
        let mark = "{\"id\":\"m1abc\",\"type\":\"mark\",\"kind\":\"bubble\",\"x\":4,\"y\":5,\"on\":\"txt22\",\"at\":{\"q\":\"hola\",\"pre\":\"\"},\"done\":false}"
        let tile = "{\"format\":\"nexus-board-tile/1\",\"pointFields\":[\"x\",\"y\",\"force\",\"azimuth\",\"altitude\",\"t\",\"w\",\"h\",\"opacity\"],\n\"strokes\":[],\n\"items\":[\n" + mark + "\n]}\n"
        let t = try BoardFiles.parseTile(tile)
        XCTAssertEqual(t.items.count, 1)
        XCTAssertTrue(t.items[0].isForeign)
        XCTAssertFalse(BoardItem(id: "a", type: "text", x: 0, y: 0).isForeign)
        XCTAssertEqual(BoardFiles.tileJSON(strokes: t.strokes, items: t.items), tile)
    }

    func testInkTestBoardBecomesARealOneOnItsFirstSave() throws {
        try write("Old.board/board.json", "{\"name\":\"Old\",\"format\":\"nexus-board-test/1\",\"pdf\":\"Book.pdf\",\"originX\":120,\"originY\":80}")
        try write("Old.board/strokes.json", "{\"format\":\"nexus-ink/1\",\"pointFields\":[\"x\",\"y\",\"force\",\"azimuth\",\"altitude\",\"t\",\"w\",\"h\",\"opacity\"],\"strokes\":[{\"ink\":\"com.apple.ink.pen\",\"color\":\"#000000FF\",\"points\":[[200,300,1,0,1.571,0,2,2,1]]},{\"ink\":\"com.apple.ink.pen\",\"color\":\"#000000FF\",\"points\":[[2000,300,1,0,1.571,0,2,2,1]]}]}")
        let board = dir.appendingPathComponent("Old.board")
        let c = try BoardFiles.load(board)
        XCTAssertEqual(c.strokes.map(\.id), ["i0", "i1"])
        XCTAssertEqual(c.items.count, 1)
        XCTAssertEqual(c.items[0].src, "Book.pdf")
        XCTAssertEqual(c.items[0].x, 120)
        XCTAssertEqual(c.items[0].w, 820)
        _ = try BoardFiles.save(c, to: board, write: { url, text in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        })
        XCTAssertEqual(try JSONValue.parse(read("Old.board/board.json") ?? "")["format"]?.string, "nexus-board/1")
        XCTAssertNotNil(read("Old.board/tiles/0_0.json"))
        XCTAssertNotNil(read("Old.board/tiles/1_0.json"))
        let again = try BoardFiles.load(board)
        XCTAssertEqual(again.strokes.map(\.id).sorted(), ["i0", "i1"])
        XCTAssertEqual(again.items.first?.id, "pdf1")
    }

    func testBoardJSON() {
        let d = Date(timeIntervalSince1970: 1_794_389_400) // 2026-11-11 09:30 UTC
        XCTAssertEqual(BoardFormat.boardJSON(created: d), "{\n  \"format\": \"nexus-board/1\",\n  \"created\": \"2026-11-11T09:30Z\",\n  \"tile\": 1024\n}\n")
    }

    // MARK: paths and names

    func testResolveStaysInTheDataFolder() {
        let root = URL(fileURLWithPath: "/data")
        let board = URL(fileURLWithPath: "/data/notebooks/Chem/R3.board")
        XCTAssertEqual(BoardFiles.resolve("files/a.png", board: board, root: root)?.path, "/data/notebooks/Chem/R3.board/files/a.png")
        XCTAssertEqual(BoardFiles.resolve("../Book.pdf", board: board, root: root)?.path, "/data/notebooks/Chem/Book.pdf")
        XCTAssertEqual(BoardFiles.resolve("./../../x.pdf", board: board, root: root)?.path, "/data/notebooks/x.pdf")
        XCTAssertNil(BoardFiles.resolve("../../../../etc/passwd", board: board, root: root))
        XCTAssertNil(BoardFiles.resolve("/etc/passwd", board: board, root: root))
        XCTAssertNil(BoardFiles.resolve("C:/x.pdf", board: board, root: root))
        XCTAssertNil(BoardFiles.resolve("a\\b.png", board: board, root: root))
        XCTAssertNil(BoardFiles.resolve("", board: board, root: root))
    }

    func testFreeName() {
        XCTAssertEqual(BoardFormat.freeName("Chem", taken: []), "Chem")
        XCTAssertEqual(BoardFormat.freeName("Chem", taken: ["chem"]), "Chem 2")
        XCTAssertEqual(BoardFormat.freeName("Chem", taken: ["chem", "Chem 2"]), "Chem 3")
        XCTAssertEqual(BoardFormat.freeName("R3: redox?", taken: [], suffix: ".board"), "R3 redox.board")
        XCTAssertEqual(BoardFormat.freeName("Lab", taken: ["Lab.board"], suffix: ".board"), "Lab 2.board")
        XCTAssertEqual(BoardFormat.freeName("  ...  ", taken: []), "Untitled")
        XCTAssertEqual(BoardFormat.freeName("Notes.", taken: []), "Notes")
    }

    func testPdfFrames() {
        let item = BoardItem(id: "p", type: "pdf", x: 60, y: 100, fields: [("w", .number(820)), ("gap", .number(24))])
        let f = BoardFiles.pdfFrames(item, sizes: [(w: 612, h: 792), (w: 792, h: 612)])
        XCTAssertEqual(f.count, 2)
        XCTAssertEqual(f[0].y, 100)
        XCTAssertEqual(f[0].h, 820 * 792 / 612, accuracy: 1e-9)
        XCTAssertEqual(f[1].y, 100 + 820 * 792 / 612 + 24, accuracy: 1e-9)
        XCTAssertEqual(f[1].x, 60)
    }

    func testNotebookList() throws {
        for p in ["notebooks/Chem/R3 redox/Lesson 1.board", "notebooks/Chem/R3 redox/Lesson 10.board", "notebooks/Chem/R3 redox/Lesson 2.board",
                  "notebooks/Chem/Loose.board", "notebooks/Chem/R1 energy", "notebooks/Spanish/Verbs.board", "notebooks/Stray.board"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(p), withIntermediateDirectories: true)
        }
        try write("notebooks/Chem/readme.md", "not a folder")
        let nbs = Notebook.list(dir)
        XCTAssertEqual(nbs.map(\.name), ["Chem", "Spanish"])
        let chem = nbs[0]
        XCTAssertEqual(chem.boards.map(\.name), ["Loose"])
        XCTAssertEqual(chem.sections.map(\.name), ["R1 energy", "R3 redox"])
        XCTAssertEqual(chem.sections[1].boards.map(\.name), ["Lesson 1", "Lesson 2", "Lesson 10"])
        XCTAssertEqual(chem.sections[1].boards[0].path, "notebooks/Chem/R3 redox/Lesson 1.board")
        XCTAssertEqual(nbs[1].boards.map(\.path), ["notebooks/Spanish/Verbs.board"])
    }
}
