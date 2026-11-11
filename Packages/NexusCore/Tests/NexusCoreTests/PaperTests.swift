import XCTest
@testable import NexusCore

/// The paper pattern and the PDF space layout: the same cases as the laptop's dev/unit-board.mjs ("paper", "pdf space").
final class PaperTests: XCTestCase {
    func testPaperFromBoardJSON() throws {
        XCTAssertEqual(Paper(nil), .plain)
        XCTAssertEqual(Paper(try JSONValue.parse("{\"kind\":\"dots\",\"size\":32}")), Paper(kind: .dots, size: 32))
        XCTAssertEqual(Paper(try JSONValue.parse("{\"kind\":\"lined\"}")), Paper(kind: .lined, size: 34))
        XCTAssertEqual(Paper(try JSONValue.parse("{\"kind\":\"grid\",\"size\":-3}")), Paper(kind: .grid, size: 24))
        XCTAssertEqual(Paper(try JSONValue.parse("{\"kind\":\"hexagons\"}")), .plain)
        XCTAssertNil(Paper.plain.json)
        XCTAssertEqual(Paper(kind: .dots, size: 24).json?.text, "{\"kind\":\"dots\",\"size\":24}")
    }

    func testPatternAtFullSize() {
        let p = Paper(kind: .dots, size: 24).pattern(visible: (0, 0, 100, 50), zoom: 1)
        XCTAssertEqual(p.xs, [0, 24, 48, 72, 96])
        XCTAssertEqual(p.ys, [0, 24, 48])
        XCTAssertTrue(p.dots)
        XCTAssertEqual(p.alpha, 1)
        let lined = Paper(kind: .lined, size: 34).pattern(visible: (-10, -40, 100, 80), zoom: 1)
        XCTAssertEqual(lined.xs, [])
        XCTAssertEqual(lined.ys, [-34, 0, 34])
        XCTAssertEqual(Paper.plain.pattern(visible: (0, 0, 100, 100), zoom: 1).alpha, 0)
    }

    func testZoomedOutItThinsThenFades() {
        let dots = Paper(kind: .dots, size: 24)
        let quarter = dots.pattern(visible: (0, 0, 200, 10), zoom: 0.2) // 4.8 pt apart -> every 4th (19.2 pt)
        XCTAssertEqual(quarter.xs, [0, 96, 192])
        XCTAssertEqual(quarter.alpha, 1)
        let fading = dots.pattern(visible: (0, 0, 800, 10), zoom: 0.033) // every 16th: 12.7 pt apart, fading
        XCTAssertEqual(fading.xs, [0, 384, 768])
        XCTAssertEqual(fading.alpha, (24 * 16 * 0.033 - 10) / 6, accuracy: 1e-9)
        XCTAssertEqual(dots.pattern(visible: (0, 0, 800, 10), zoom: 0.02).alpha, 0)
    }

    func testGraphHasAStrongLineEveryFifth() {
        let g = Paper(kind: .graph).pattern(visible: (0, 0, 81, 1), zoom: 2)
        XCTAssertEqual(g.xs, [0, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80])
        XCTAssertEqual(g.strongX, [0, 5, 10])
        XCTAssertEqual(Paper(kind: .lined, size: 34).snap(50), 34)
        XCTAssertEqual(Paper.plain.snap(50), 50)
    }

    func testPdfSpace() {
        // square pages 100 wide, 10 apart, from y 0
        let base: [(String, JSONValue)] = [("w", .number(100)), ("gap", .number(10))]
        let sizes: [(w: Double, h: Double)] = [(w: 50, h: 50), (w: 50, h: 50), (w: 50, h: 50)]
        func item(_ space: String) -> BoardItem {
            BoardItem(id: "p", type: "pdf", x: 0, y: 0, fields: base + [("space", try! JSONValue.parse(space))])
        }
        // room after page 1
        var f = BoardFiles.pdfFrames(item("[{\"page\":1,\"at\":1,\"gap\":50}]"), sizes: sizes)
        XCTAssertEqual(f.map(\.y), [0, 160, 270])
        // page 2 opened at a quarter: two parts, the page's frame spans both
        let it = item("[{\"page\":2,\"at\":0.25,\"gap\":40}]")
        let seg = BoardFiles.pdfSegments(it, sizes: sizes)
        XCTAssertEqual(seg.count, 4)
        XCTAssertEqual(seg[1], BoardFiles.PdfSegment(page: 1, x: 0, y: 110, w: 100, h: 25, top: 0, bottom: 0.25))
        XCTAssertEqual(seg[2], BoardFiles.PdfSegment(page: 1, x: 0, y: 175, w: 100, h: 75, top: 0.25, bottom: 1))
        f = BoardFiles.pdfFrames(it, sizes: sizes)
        XCTAssertEqual(f[1].y, 110)
        XCTAssertEqual(f[1].h, 140)
        XCTAssertEqual(f[2].y, 260)
        // room above page 1, and broken entries ignored
        f = BoardFiles.pdfFrames(item("[{\"page\":1,\"at\":0,\"gap\":30},{\"page\":0,\"gap\":9},{\"page\":2,\"gap\":-1}]"), sizes: sizes)
        XCTAssertEqual(f.map(\.y), [30, 140, 250])
        // no space: as before
        XCTAssertEqual(BoardFiles.pdfFrames(BoardItem(id: "p", type: "pdf", x: 0, y: 0, fields: base), sizes: sizes).map(\.y), [0, 110, 220])
    }
}
