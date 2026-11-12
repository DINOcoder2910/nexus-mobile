import XCTest
@testable import NexusCore

/// Insert space's options: how much room a drag or a tap makes, and which things move for "Only this column".
final class InsertSpaceTests: XCTestCase {
    let dots = Paper(kind: .dots, size: 24)
    let lined = Paper(kind: .lined, size: 34)

    func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> InsertSpace.Box {
        InsertSpace.Box(minX: x, minY: y, maxX: x + w, maxY: y + h)
    }

    func testAmountSnapsToThePaper() {
        XCTAssertEqual(InsertSpace.amount(50, paper: dots, size: .snap), 48)
        XCTAssertEqual(InsertSpace.amount(-61, paper: dots, size: .snap), -72)
        XCTAssertEqual(InsertSpace.amount(10, paper: dots, size: .snap), 0)
        XCTAssertEqual(InsertSpace.amount(50.4, paper: dots, size: .free), 50)
        XCTAssertEqual(InsertSpace.amount(50.4, paper: .plain, size: .snap), 50)
        XCTAssertEqual(InsertSpace.amount(50, paper: lined, size: .snap, sideways: true), 50, "lined paper has no columns to snap to")
        XCTAssertEqual(InsertSpace.line(30, paper: dots, size: .snap), 24)
        XCTAssertEqual(InsertSpace.line(30, paper: dots, size: .free), 30)
    }

    func testTapAmounts() {
        XCTAssertEqual(InsertSpace.tapAmount(.half, screen: 800, paper: .plain, size: .snap), 400)
        XCTAssertEqual(InsertSpace.tapAmount(.half, screen: 800, paper: lined, size: .snap), 408)
        XCTAssertEqual(InsertSpace.tapAmount(.full, screen: 800, paper: .plain, size: .free), 800)
        XCTAssertEqual(InsertSpace.tapAmount(.threeLines, screen: 800, paper: lined, size: .snap), 102)
        XCTAssertEqual(InsertSpace.tapAmount(.threeLines, screen: 800, paper: .plain, size: .snap), 96)
        XCTAssertEqual(InsertSpace.tapAmount(.nothing, screen: 800, paper: .plain, size: .snap), 0)
    }

    func testSidewaysFollowsTheDrag() {
        XCTAssertTrue(InsertSpace.sideways(dx: 40, dy: 10, direction: .follow))
        XCTAssertFalse(InsertSpace.sideways(dx: 40, dy: 10, direction: .down))
        XCTAssertFalse(InsertSpace.sideways(dx: 10, dy: -40, direction: .follow))
    }

    /// Two stacks side by side: starting in the left one moves only the left one.
    func testColumnIsTheStackYouStartedIn() {
        let leftAbove = box(0, 0, 300, 40), leftBelow = box(20, 200, 250, 60), leftLower = box(200, 400, 200, 40)
        let rightBelow = box(500, 220, 300, 80)
        let boxes = [leftAbove, leftBelow, leftLower, rightBelow]
        let band = InsertSpace.band(seed: 100, line: 100, boxes: boxes)
        XCTAssertEqual(band, 0...400, "grows over the stack, and on to what overlaps it lower down")
        XCTAssertTrue(InsertSpace.moves(leftBelow, line: 100, band: band))
        XCTAssertTrue(InsertSpace.moves(leftLower, line: 100, band: band))
        XCTAssertFalse(InsertSpace.moves(rightBelow, line: 100, band: band))
        XCTAssertFalse(InsertSpace.moves(leftAbove, line: 100, band: band), "above the line never moves")
        XCTAssertTrue(InsertSpace.moves(rightBelow, line: 100), "everything below, without a band")
        XCTAssertNil(InsertSpace.band(seed: 2000, line: 100, boxes: boxes))
    }

    func testWideThingsFarAboveDontJoinTheColumns() {
        let title = box(0, -1000, 900, 50), left = box(0, 200, 300, 50), right = box(500, 200, 300, 50)
        XCTAssertEqual(InsertSpace.band(seed: 100, line: 100, boxes: [title, left, right]), 0...300)
    }

    func testSidewaysUsesTheRow() {
        let row = box(400, 0, 100, 100), other = box(400, 500, 100, 100), mine = box(0, 20, 100, 60)
        let band = InsertSpace.band(seed: 50, line: 200, boxes: [row, other, mine], sideways: true)
        XCTAssertEqual(band, 0...100)
        XCTAssertTrue(InsertSpace.moves(row, line: 200, sideways: true, band: band))
        XCTAssertFalse(InsertSpace.moves(other, line: 200, sideways: true, band: band))
        XCTAssertFalse(InsertSpace.moves(mine, line: 200, sideways: true, band: band))
    }
}
