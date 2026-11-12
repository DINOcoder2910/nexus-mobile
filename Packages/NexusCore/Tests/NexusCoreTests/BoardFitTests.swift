import XCTest
@testable import NexusCore

/// "Show everything": the zoom and place that fit what is on a board on the screen.
final class BoardFitTests: XCTestCase {
    func testBigBoardZoomsOutToFitWithAMargin() {
        let v = BoardFit.fit(minX: 0, minY: 0, maxX: 1000, maxY: 500, width: 800, height: 600, minZoom: 0.2, maxZoom: 5)
        XCTAssertEqual(v.zoom, 0.72, accuracy: 0.0001, "the width decides: (800 - 2 × 40) / 1000")
        XCTAssertEqual(v.x, 500 - 400 / 0.72, accuracy: 0.0001)
        XCTAssertEqual(v.y, 250 - 300 / 0.72, accuracy: 0.0001)
        // the box is on screen, the margin clear of each side it fills
        XCTAssertEqual((0 - v.x) * v.zoom, 40, accuracy: 0.0001)
        XCTAssertLessThanOrEqual((500 - v.y) * v.zoom, 600 - 40)
    }

    func testSmallThingsStayAtActualSize() {
        let v = BoardFit.fit(minX: 0, minY: 0, maxX: 100, maxY: 100, width: 800, height: 600, minZoom: 0.2, maxZoom: 5)
        XCTAssertEqual(v, BoardFit.View(x: -350, y: -250, zoom: 1))
        let dot = BoardFit.fit(minX: 10, minY: 10, maxX: 10, maxY: 10, width: 800, height: 600, minZoom: 0.2, maxZoom: 5)
        XCTAssertEqual(dot.zoom, 1, "a box with no size doesn't divide by zero")
    }

    func testZoomStaysWithinTheBoardsLimits() {
        let v = BoardFit.fit(minX: 0, minY: 0, maxX: 100_000, maxY: 10, width: 800, height: 600, minZoom: 0.2, maxZoom: 5)
        XCTAssertEqual(v.zoom, 0.2)
        XCTAssertEqual(v.x, 50_000 - 400 / 0.2, accuracy: 0.0001)
        let tiny = BoardFit.fit(minX: 0, minY: 0, maxX: 100, maxY: 100, width: 50, height: 50, minZoom: 0.2, maxZoom: 5)
        XCTAssertEqual(tiny.zoom, 0.2, "a screen smaller than the margins still gives a zoom in range")
    }
}
