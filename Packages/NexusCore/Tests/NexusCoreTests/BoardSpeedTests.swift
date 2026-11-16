import XCTest
@testable import NexusCore

/// A save on a big board (a long lesson: thousands of strokes) must not turn the whole board into text again: the iPad saves 600 ms
/// after every stroke, on the main thread, and that held up the Pencil (Nov 2026). The tile memo keeps each tile's text until what
/// it holds changes; these check it still writes exactly what the laptop's format says, and that an unchanged board costs little.
final class BoardSpeedTests: XCTestCase {
    /// `n` strokes of `points` points each, spread over a 6 x 6 tile area.
    static func bigBoard(strokes n: Int, points: Int) -> BoardContent {
        var c = BoardContent()
        for i in 0..<n {
            let x0 = Double((i * 97) % 6000), y0 = Double((i * 61) % 6000)
            var pts: [[Double]] = []
            for k in 0..<points { pts.append([x0 + Double(k) * 1.5, y0 + Double(k % 7), 0.6, 1.2, 1.1, Double(k) * 0.008, 2.4, 2.4, 1]) }
            c.strokes.append(BoardStroke(id: String(format: "s%05d", i), ink: "com.apple.ink.pen", color: "#000000FF", points: pts))
        }
        c.items.append(BoardItem(id: "txt01", type: "text", x: 100, y: 100, fields: [("w", .number(560))]))
        c.texts["txt01"] = "words"
        return c
    }

    /// What `changes` would say with no memo at all.
    static func plainTiles(_ c: BoardContent) -> [String: String] {
        var byKey: [String: (s: [BoardStroke], i: [BoardItem])] = [:]
        for s in c.strokes { byKey[s.tileKey, default: ([], [])].s.append(s) }
        for it in c.items { byKey[it.tileKey, default: ([], [])].i.append(it) }
        var out: [String: String] = [:]
        for key in Set(byKey.keys).union(c.tilesOnDisk.keys) {
            let t = byKey[key] ?? ([], [])
            let text = BoardFiles.tileJSON(strokes: t.s, items: t.i)
            if c.tilesOnDisk[key] != text { out[key] = text }
        }
        return out
    }

    func testMemoWritesWhatThePlainWayWrites() throws {
        var c = BoardSpeedTests.bigBoard(strokes: 300, points: 20)
        XCTAssertEqual(BoardFiles.changes(c).tiles, BoardSpeedTests.plainTiles(c))
        // as if saved: the disk holds what was written
        for (k, t) in BoardFiles.changes(c).tiles { c.tilesOnDisk[k] = t }
        XCTAssertTrue(BoardFiles.changes(c).tiles.isEmpty)

        // a stroke partly erased (its kept parts), one moved by a hair, one removed, one added, an item moved: each tile they touch,
        // and only those, comes back changed, with the same text the plain way makes
        c.strokes[3].ranges = [[0, 4.5], [9, 19]]
        c.strokes[10].points[0][0] += 0.01
        let gone = c.strokes.remove(at: 20)
        c.strokes.append(BoardStroke(id: "new01", ink: "com.apple.ink.pencil", color: "#FF0000FF", points: [[5, 5, 1, 0, 1.5, 0, 2, 2, 1]]))
        c.items[0] = c.items[0].with("x", .number(2100))
        let ch = BoardFiles.changes(c).tiles
        XCTAssertEqual(ch, BoardSpeedTests.plainTiles(c))
        let want = Set([c.strokes[3].tileKey, c.strokes[10].tileKey, gone.tileKey, "0_0", BoardFormat.tileKey(100, 100), BoardFormat.tileKey(2100, 100)])
        XCTAssertEqual(Set(ch.keys), want)
    }

    func testAStrokeReadFromAFileIsWrittenBackAsItWas() throws {
        // a stroke with a key this app doesn't know: kept, and a change to that key alone is still seen
        let text = BoardTests.fieldsLine + "\"strokes\":[\n{\"id\":\"aaaaa\",\"ink\":\"com.apple.ink.pen\",\"color\":\"#000000FF\",\"points\":[[1,2,1,0,1.571,0,2,2,1]],\"by\":\"laptop\"}\n],\n\"items\":[]}\n"
        var c = BoardContent()
        let t = try BoardFiles.parseTile(text)
        c.strokes = t.strokes
        c.tilesOnDisk["0_0"] = text
        XCTAssertTrue(BoardFiles.changes(c).tiles.isEmpty)
        c.strokes[0].raw = c.strokes[0].raw?.setting("by", .string("ipad"))
        XCTAssertEqual(BoardFiles.changes(c).tiles, BoardSpeedTests.plainTiles(c))
        XCTAssertEqual(BoardFiles.changes(c).tiles.count, 1)
    }

    func testABigUnchangedBoardIsQuickToCheck() throws {
        var c = BoardSpeedTests.bigBoard(strokes: 4000, points: 60)
        var t0 = Date()
        _ = BoardSpeedTests.plainTiles(c)
        let plain = Date().timeIntervalSince(t0)
        for (k, t) in BoardFiles.changes(c).tiles { c.tilesOnDisk[k] = t }
        // one new stroke, as after writing a letter
        c.strokes.append(BoardStroke(id: "new01", ink: "com.apple.ink.pen", color: "#000000FF", points: [[50, 50, 1, 0, 1.5, 0, 2, 2, 1]]))
        t0 = Date()
        let ch = BoardFiles.changes(c)
        let memo = Date().timeIntervalSince(t0)
        XCTAssertEqual(Array(ch.tiles.keys), ["0_0"])
        print("BOARDSPEED 4000 strokes x 60 points: every tile as text \(Int(plain * 1000)) ms; with the memo, one stroke added \(Int(memo * 1000)) ms")
        XCTAssertLessThan(memo, plain / 3)
    }

    func testOneNewStrokeOnAFullPageIsQuickAndExact() throws {
        // a page of writing: 1500 strokes in one tile
        var c = BoardContent()
        for i in 0..<1500 {
            let x0 = 40 + Double((i % 40) * 22), y0 = 40 + Double(i / 40) * 24
            var pts: [[Double]] = []
            for k in 0..<60 { let t = Double(k) / 59; pts.append([x0 + t * 14, y0 + sin(t * 9) * 6, 0.6, 1.2, 1.1, t * 0.4, 2.4, 2.4, 1]) }
            c.strokes.append(BoardStroke(id: String(format: "p%05d", i), ink: "com.apple.ink.pen", color: "#1A1A1AFF", points: pts))
        }
        XCTAssertEqual(Set(c.strokes.map(\.tileKey)).count, 1)
        // as if read from the files: written, primed as an opened board is
        for (k, t) in BoardSpeedTests.plainTiles(c) { c.tilesOnDisk[k] = t }
        c.tileMemo = TileMemo()
        c.tileMemo.prime(c)
        XCTAssertTrue(BoardFiles.changes(c).tiles.isEmpty)
        c.strokes.append(BoardStroke(id: "new01", ink: "com.apple.ink.pen", color: "#000000FF", points: [[50, 50, 1, 0, 1.5, 0, 2, 2, 1]]))
        var t0 = Date()
        let plain = BoardSpeedTests.plainTiles(c)
        let plainTime = Date().timeIntervalSince(t0)
        t0 = Date()
        let ch = BoardFiles.changes(c).tiles
        let memoTime = Date().timeIntervalSince(t0)
        XCTAssertEqual(ch, plain)
        print("BOARDSPEED a page of 1500 strokes, one added: the whole tile as text \(Int(plainTime * 1000)) ms; with stroke lines kept \(Int(memoTime * 1000)) ms")
        XCTAssertLessThan(memoTime, plainTime / 3)
        // a stroke in the middle erased in part and one removed: still exactly the plain text
        c.strokes[700].ranges = [[0, 20.5]]
        c.strokes.remove(at: 300)
        XCTAssertEqual(BoardFiles.changes(c).tiles, BoardSpeedTests.plainTiles(c))
    }
}
