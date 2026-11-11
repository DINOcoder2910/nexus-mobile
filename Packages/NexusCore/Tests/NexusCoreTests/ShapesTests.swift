import XCTest
@testable import NexusCore

/// Hold to make a shape, ported from the laptop's dev/unit-board.mjs ("hold to make a shape"), with the same strokes. The jitter
/// is the laptop's own (sin/cos of the point's index), so it is the same on every run and on both apps.
final class ShapesTests: XCTestCase {
    typealias Pt = SIMD2<Double>

    /// a wobbly hand: each point nudged by up to j
    func jit(_ p: [Pt], _ j: Double = 1.5) -> [Pt] {
        p.enumerated().map { (e) -> Pt in Pt(e.element.x + sin(Double(e.offset) * 1.7) * j, e.element.y + cos(Double(e.offset) * 2.3) * j) }
    }

    /// a polyline through vs, n points per edge
    func poly(_ vs: [Pt], _ n: Int = 20) -> [Pt] {
        var o: [Pt] = []
        for i in 0..<(vs.count - 1) {
            for k in 0..<n {
                let f = Double(k), m = Double(n)
                o.append(Pt(vs[i].x + (vs[i + 1].x - vs[i].x) * f / m, vs[i].y + (vs[i + 1].y - vs[i].y) * f / m))
            }
        }
        o.append(vs[vs.count - 1])
        return o
    }

    /// an ellipse round (100, 100), going a little past its start as a hand does
    func ell(_ rx: Double, _ ry: Double, _ over: Double = 0.05) -> [Pt] {
        (0...60).map { (i: Int) -> Pt in
            let t = 2 * Double.pi * (1 + over) * Double(i) / 60
            return Pt(100 + rx * cos(t), 100 + ry * sin(t))
        }
    }

    func kind(_ p: [Pt]) -> String? { Shapes.recognize(p)?.kind }

    func P(_ x: Double, _ y: Double) -> [Double] { [x, y, 1, 0, Double.pi / 2, 0, 3, 3, 1] }

    func testRecognisesEachShape() {
        XCTAssertEqual(kind(jit(poly([Pt(0, 0), Pt(200, 6)]))), "line")
        XCTAssertEqual(kind(jit(ell(60, 62))), "circle")
        XCTAssertEqual(kind(jit(ell(120, 50))), "ellipse")
        XCTAssertEqual(kind(jit(poly([Pt(0, 0), Pt(200, 0), Pt(200, 100), Pt(0, 100), Pt(2, 4)]))), "rectangle")
        XCTAssertEqual(kind(jit(poly([Pt(0, 100), Pt(60, 0), Pt(120, 100), Pt(3, 98)]))), "triangle")
        XCTAssertEqual(kind(jit(poly([Pt(100, 0), Pt(200, 100), Pt(100, 200), Pt(0, 100), Pt(98, 3)]))), "quad") // a tilted square
    }

    func testScribbleTickAndDotStayAsWritten() {
        XCTAssertNil(kind(jit(poly([Pt(0, 0), Pt(50, 80), Pt(90, 10), Pt(140, 90), Pt(200, 0)]))))
        XCTAssertNil(kind([Pt(0, 0), Pt(4, 5), Pt(12, -6)]))
        XCTAssertNil(kind([Pt(5, 5)]))
        XCTAssertNil(kind([]))
    }

    func testLineCloseToLevelIsMadeLevel() throws {
        let r = try XCTUnwrap(Shapes.recognize(poly([Pt(0, 0), Pt(200, 9)])))
        XCTAssertEqual(r.kind, "line")
        let last = try XCTUnwrap(r.points.last)
        XCTAssertLessThan(abs(last.y), 1e-9)
        XCTAssertTrue(r.points.allSatisfy { abs($0.y) < 1e-9 })
        XCTAssertEqual(r.points.first?.x, 0)
        XCTAssertEqual(last.x, hypot(200, 9), accuracy: 1e-9) // the same length, laid level
    }

    func testRectanglePointsFollowTheBox() throws {
        let p = jit(poly([Pt(0, 0), Pt(200, 0), Pt(200, 100), Pt(0, 100), Pt(2, 4)]))
        let r = try XCTUnwrap(Shapes.recognize(p))
        var x0 = Double.infinity, x1 = -Double.infinity
        for q in p { x0 = min(x0, q.x); x1 = max(x1, q.x) }
        XCTAssertEqual(r.points.first?.x ?? .nan, x0, accuracy: 1e-9) // starts at the box's top-left corner
        XCTAssertEqual(r.points.map(\.x).max() ?? .nan, x1, accuracy: 1e-9)
        let first = try XCTUnwrap(r.points.first), last = try XCTUnwrap(r.points.last)
        XCTAssertEqual(first.x, last.x, accuracy: 1e-9) // closed
        XCTAssertEqual(first.y, last.y, accuracy: 1e-9)
    }

    func testShapeKeepsTheStrokesFeelAndTime() throws {
        let shape = try XCTUnwrap(Shapes.recognize(jit(ell(60, 62))))
        let sp = Shapes.shapePoints(shape, written: [P(0, 0), [1, 1, 0.8, 0.5, 1.1, 0.4, 3.5, 3.5, 0.9], [2, 2, 1, 0, 1, 0.9, 3, 3, 1]])
        XCTAssertEqual(sp.count, shape.points.count)
        let feel: [Double] = [0.8, 0.5, 1.1, 3.5, 3.5, 0.9] // the middle written point's force, azimuth, altitude, w, h, opacity
        for q in sp {
            XCTAssertEqual(q.count, 9)
            let got: [Double] = [q[2], q[3], q[4], q[6], q[7], q[8]]
            XCTAssertEqual(got, feel)
        }
        XCTAssertEqual(sp[0][5], 0)
        XCTAssertEqual(sp[sp.count - 1][5], 0.9, accuracy: 1e-12)
        // timed evenly, rounded to the millisecond; positions rounded to hundredths
        let times = sp.map { $0[5] }
        XCTAssertEqual(times, times.sorted())
        XCTAssertEqual(sp[sp.count / 2][5], 0.9 * Double(sp.count / 2) / Double(sp.count - 1), accuracy: 0.0006)
        XCTAssertTrue(sp.allSatisfy { abs($0[0] * 100 - ($0[0] * 100).rounded()) < 1e-6 })
    }

    func testShapePointsWithNothingWritten() {
        let shape = Shapes.Recognized(kind: "line", points: [Pt(0, 0), Pt(1.234, -5.678)])
        let sp = Shapes.shapePoints(shape, written: [])
        XCTAssertEqual(sp.count, 2)
        XCTAssertEqual(sp[1][0], 1.23, accuracy: 1e-12)
        XCTAssertEqual(sp[1][1], -5.68, accuracy: 1e-12)
        XCTAssertEqual(Array(sp[1][2...]), [1, 0, Double.pi / 2, 0, 2, 2, 1])
    }

    /// a point at (x, y) written at time t
    func T(_ x: Double, _ y: Double, _ t: Double) -> [Double] { [x, y, 1, 0, Double.pi / 2, t, 3, 3, 1] }

    func testEndsInHoldFromTheStrokesOwnTimes() {
        // drawn in 0.3 s, then 0.6 s of tiny wobble at the end: a hold
        var held = (0...30).map { T(Double($0) * 5, 0, Double($0) * 0.01) }
        held += (1...12).map { T(150 + sin(Double($0)) * 1.2, cos(Double($0)) * 1.2, 0.3 + Double($0) * 0.05) }
        XCTAssertTrue(Shapes.endsInHold(held, still: 4, hold: 0.55))
        // the same stroke lifted without stopping
        let lifted = (0...30).map { T(Double($0) * 5, 0, Double($0) * 0.01) }
        XCTAssertFalse(Shapes.endsInHold(lifted, still: 4, hold: 0.55))
        // a slow stroke that keeps moving is not a hold
        let slow = (0...30).map { T(Double($0) * 5, 0, Double($0) * 0.1) }
        XCTAssertFalse(Shapes.endsInHold(slow, still: 4, hold: 0.55))
        // a pause in the middle that then moves on is not a hold at the end
        var paused = (0...10).map { T(Double($0) * 5, 0, Double($0) * 0.01) }
        paused += (1...12).map { T(50, 0, 0.1 + Double($0) * 0.05) }
        paused += (1...10).map { T(50 + Double($0) * 5, 0, 0.7 + Double($0) * 0.01) }
        XCTAssertFalse(Shapes.endsInHold(paused, still: 4, hold: 0.55))
        XCTAssertFalse(Shapes.endsInHold([T(0, 0, 0)], still: 4, hold: 0.55))
        XCTAssertFalse(Shapes.endsInHold([[0, 0], [1, 1]], still: 4, hold: 0.55))
    }
}
