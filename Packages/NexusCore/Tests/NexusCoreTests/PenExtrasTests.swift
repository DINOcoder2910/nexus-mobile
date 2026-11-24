import XCTest
@testable import NexusCore

/// The pen panel's extras (PenExtras in Pens.swift): copying a pen from a stroke, sizes set on the iPad going to the laptop, and
/// restyling lassoed ink. The laptop's dropper and restyle are desktop/src/board/Board.tsx; these follow its rules.
final class PenExtrasTests: XCTestCase {
    func testAStrokesWidthIsTheMiddleOfItsPoints() {
        XCTAssertEqual(PenExtras.width([2, 9, 5, 5.5, 6]), 5.5)
        XCTAssertEqual(PenExtras.width([3]), 3)
        XCTAssertEqual(PenExtras.width([]), 0)
        XCTAssertEqual(PenExtras.width([0, .nan, 4]), 4, "points with no width are left out")
    }

    func testTheNearestStepIsByRatio() {
        let pen: [Double] = [1, 1.5, 3, 4.5, 6, 10]
        XCTAssertEqual(PenExtras.nearestStep(5.5, in: pen), 4)
        XCTAssertEqual(PenExtras.nearestStep(0.3, in: pen), 0)
        XCTAssertEqual(PenExtras.nearestStep(40, in: pen), 5)
        XCTAssertEqual(PenExtras.nearestStep(2.1, in: pen), 1, "2.1 is nearer 1.5 than 3 by ratio")
        XCTAssertEqual(PenExtras.nearestStep(2.2, in: pen), 2)
    }

    func testColoursAreNamedAfterTheNearestOne() {
        XCTAssertEqual(PenExtras.colorName("#D93025"), "red")
        XCTAssertEqual(PenExtras.colorName("#2F6FEBFF"), "blue")
        XCTAssertEqual(PenExtras.colorName("#C0392B"), "red")
        XCTAssertEqual(PenExtras.colorName("#1B1B1B"), "black")
        XCTAssertEqual(PenExtras.colorName("#FFE066"), "yellow")
        XCTAssertEqual(PenExtras.colorName("#0097A7"), "teal")
        XCTAssertEqual(PenExtras.colorName("nope"), "this colour")
    }

    func testTheWordsTheBoardShows() {
        XCTAssertEqual(PenExtras.widthText(5.5), "5.5 px")
        XCTAssertEqual(PenExtras.widthText(4), "4 px")
        XCTAssertEqual(PenExtras.widthText(0.75), "0.75 px")
        XCTAssertEqual(PenExtras.strokeText(ink: "Pen", width: 5.5, color: "#D93025"), "Pen · 5.5 px · red")
        XCTAssertEqual(PenExtras.restyleText(count: 4, color: "#2F6FEB", width: 5), "Changed 4 strokes to blue, 5 px")
        XCTAssertEqual(PenExtras.restyleText(count: 1, color: nil, width: 3), "Changed 1 stroke to 3 px")
        XCTAssertEqual(PenExtras.restyleText(count: 2, color: "#188038", width: nil), "Changed 2 strokes to green")
    }

    func testALassoHoldsTheStrokesMostlyInsideIt() {
        let square: [SIMD2<Double>] = [[0, 0], [100, 0], [100, 100], [0, 100]]
        XCTAssertTrue(PenExtras.inside([50, 50], square))
        XCTAssertFalse(PenExtras.inside([150, 50], square))
        let inside: [SIMD2<Double>] = [[10, 10], [20, 20], [30, 30]]
        let half: [SIMD2<Double>] = [[90, 50], [95, 50], [105, 50], [110, 50]]
        let out: [SIMD2<Double>] = [[90, 50], [105, 50], [110, 50], [120, 50]]
        XCTAssertTrue(PenExtras.lassoed(inside, by: square))
        XCTAssertTrue(PenExtras.lassoed(half, by: square), "half inside counts")
        XCTAssertFalse(PenExtras.lassoed(out, by: square))
        XCTAssertFalse(PenExtras.lassoed(inside, by: [[0, 0], [1, 1]]), "two points aren't a lasso")
    }

    func testASizeSetOnTheIPadReachesTheLaptopInItsUnits() {
        let own: [Double] = [2.4, 3, 4, 6, 8, 12]
        // the pencil's Extra bold made 18 on the iPad (1.5 times its own) is the laptop's 6 made 1.5 times
        let mine: [Double] = [2.4, 3, 4, 6, 8, 18]
        let laptop = Pens.unscaled(mine, ink: "pencil", own: own)
        XCTAssertEqual(laptop, [0.6, 1, 2, 3, 4, 9])
        // and back: the laptop's file read on the iPad gives the iPad's own sizes again
        XCTAssertEqual(Pens.scaled(laptop, ink: "pencil", own: own), mine)
        // through the file
        var set = Pens.Shared(); set.widths["pencil"] = laptop!
        XCTAssertEqual(Pens.read(Pens.merge(nil, set)).widths["pencil"], [0.6, 1, 2, 3, 4, 9])
        XCTAssertNil(Pens.unscaled([1, 2], ink: "pen", own: own))
        XCTAssertNil(Pens.unscaled(mine, ink: "shapes", own: own))
        XCTAssertEqual(Pens.unscaled([0.01, 1, 1, 1, 1, 900], ink: "pen", own: [1, 1, 1, 1, 1, 1])?.first, 0.2, "kept inside the file's range")
    }

    func testASizeIsSetInsideTheInksRange() {
        XCTAssertEqual(PenExtras.settable(4.04, range: 0.88...25.7), 4)
        XCTAssertEqual(PenExtras.settable(0.1, range: 0.88...25.7), 0.9)
        XCTAssertEqual(PenExtras.settable(500, range: 7.5...60), 60)
    }
}
