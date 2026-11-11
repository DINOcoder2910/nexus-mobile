import Foundation

/// Hold to make a shape (pure, ported from the laptop's renderer/src/board/shapes.js, tested in ShapesTests): a stroke written
/// and then held still becomes the shape it was meant to be: a straight line, a circle or ellipse, a rectangle (or any four-sided
/// shape), a triangle. The result is a list of board points along the ideal shape; the board turns it into ink of the same pen,
/// colour and width, so it stays a stroke (drawn as any other).
/// Apple keeps its own shape recognition to its apps (Notes, Freeform), so a PencilKit canvas does not do this by itself.
public enum Shapes {
    public struct Recognized: Equatable {
        /// line | circle | ellipse | rectangle | quad | triangle
        public var kind: String
        public var points: [SIMD2<Double>]

        public init(kind: String, points: [SIMD2<Double>]) {
            self.kind = kind
            self.points = points
        }
    }

    typealias Pt = SIMD2<Double>

    static func dist(_ a: Pt, _ b: Pt) -> Double { hypot(a.x - b.x, a.y - b.y) }

    static func pathLength(_ p: [Pt]) -> Double {
        var L = 0.0
        if p.count > 1 { for i in 1..<p.count { L += dist(p[i - 1], p[i]) } }
        return L
    }

    /// distance from p to the segment a-b
    static func segDist(_ p: Pt, _ a: Pt, _ b: Pt) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y, l2 = dx * dx + dy * dy
        let t = l2 != 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)) : 0
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    /// Ramer–Douglas–Peucker: the corners of the polyline p[lo...hi] at tolerance eps, as indices into p (the laptop compares the
    /// written points by identity to find one again; an index is the same thing here)
    static func rdpIndices(_ p: [Pt], _ lo: Int, _ hi: Int, _ eps: Double) -> [Int] {
        if hi - lo + 1 < 3 { return Array(lo...hi) }
        var worst = 0.0, at = lo
        for i in (lo + 1)..<hi {
            let d = segDist(p[i], p[lo], p[hi])
            if d > worst { worst = d; at = i }
        }
        if worst <= eps { return [lo, hi] }
        let a = rdpIndices(p, lo, at, eps), b = rdpIndices(p, at, hi, eps)
        return Array(a.dropLast()) + b
    }

    static func rdp(_ p: [Pt], _ eps: Double) -> [Pt] {
        if p.isEmpty { return [] }
        return rdpIndices(p, 0, p.count - 1, eps).map { p[$0] }
    }

    /// points every `step` units along a polyline
    static func along(_ poly: [Pt], _ step: Double) -> [Pt] {
        guard let first = poly.first else { return [] }
        var out: [Pt] = [first]
        if poly.count < 2 { return out }
        for i in 1..<poly.count {
            let a = poly[i - 1], b = poly[i]
            let n = max(1, Int((dist(a, b) / step).rounded()))
            for k in 1...n {
                let f = Double(k), m = Double(n)
                out.append(Pt(a.x + (b.x - a.x) * f / m, a.y + (b.y - a.y) * f / m))
            }
        }
        return out
    }

    /// a line close to level or upright is made exactly so
    static func snapAngle(_ a: Pt, _ b: Pt, within: Double = 5 * Double.pi / 180) -> Pt {
        let ang = atan2(b.y - a.y, b.x - a.x), L = dist(a, b)
        for k in -4...4 {
            let q = Double(k) * Double.pi / 2
            if abs(ang - q) < within { return Pt(a.x + L * cos(q), a.y + L * sin(q)) }
        }
        return b
    }

    /// pts: the points as written -> the shape it was meant to be, or nil (a dot, a tick, a scribble stay as written)
    public static func recognize(_ pts: [SIMD2<Double>], step: Double = 3) -> Recognized? {
        var p: [Pt] = []
        for i in 0..<pts.count where i == 0 || dist(pts[i], pts[i - 1]) > 0.01 { p.append(pts[i]) }
        if p.count < 2 { return nil }
        let L = pathLength(p)
        var x0 = Double.infinity, y0 = Double.infinity, x1 = -Double.infinity, y1 = -Double.infinity
        for q in p { x0 = min(x0, q.x); y0 = min(y0, q.y); x1 = max(x1, q.x); y1 = max(y1, q.y) }
        let diag = hypot(x1 - x0, y1 - y0)
        if L < 12 || diag < 10 { return nil } // a dot or a tick
        let a = p[0], b = p[p.count - 1], chord = dist(a, b)
        // a line: everything close to the chord, and not doubled back
        var dev = 0.0
        for q in p { dev = max(dev, segDist(q, a, b)) }
        if chord > 0.8 * L && dev < max(3, 0.06 * chord) {
            return Recognized(kind: "line", points: along([a, snapAngle(a, b)], step))
        }
        // closed shapes: the ends meet (or nearly)
        if chord > max(0.25 * diag, min(18, 0.15 * L)) || L < 1.9 * diag { return nil } // (a loop's length is at least twice its size)
        let ring = p + [a]
        let cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, rx = max(1, (x1 - x0) / 2), ry = max(1, (y1 - y0) / 2)
        var res = 0.0
        for q in p {
            let u = (q.x - cx) / rx, v = (q.y - cy) / ry
            res += abs((u * u + v * v).squareRoot() - 1)
        }
        res /= Double(p.count) // 0 on a perfect axis-aligned ellipse
        let corners = closedCorners(ring, 0.07 * diag)
        if corners.count == 3 {
            return Recognized(kind: "triangle", points: along(corners + [corners[0]], step))
        }
        if corners.count == 4 && res > 0.06 {
            // close to level: a rectangle the size of the box; otherwise the four corners as written
            var level = true
            for i in 0..<4 {
                let c = corners[i], d = corners[(i + 1) % 4]
                let ang = abs(atan2(d.y - c.y, d.x - c.x)).truncatingRemainder(dividingBy: Double.pi / 2)
                if !(min(ang, Double.pi / 2 - ang) < 12 * Double.pi / 180) { level = false; break }
            }
            let box: [Pt] = [Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)]
            let quad = level ? box : corners
            return Recognized(kind: level ? "rectangle" : "quad", points: along(quad + [quad[0]], step))
        }
        if res < 0.16 {
            let isRound = abs(rx - ry) < 0.12 * max(rx, ry), R = (rx + ry) / 2
            let ex = isRound ? R : rx, ey = isRound ? R : ry
            let start = atan2(a.y - cy, a.x - cx)
            let n = max(24, Int((Double.pi * (ex + ey) / step).rounded(.up)))
            var out: [Pt] = []
            for i in 0...n {
                let t = start + 2 * Double.pi * Double(i) / Double(n)
                out.append(Pt(cx + ex * cos(t), cy + ey * sin(t)))
            }
            return Recognized(kind: isRound ? "circle" : "ellipse", points: out)
        }
        return nil
    }

    /// the corners of a closed ring: RDP from its start, then again from the corner opposite (so the start is not taken for a
    /// corner), merging corners that sit on a straight edge
    static func closedCorners(_ ring: [Pt], _ eps: Double) -> [Pt] {
        if ring.isEmpty { return [] }
        let first = Array(rdpIndices(ring, 0, ring.count - 1, eps).dropLast())
        if first.count < 3 { return first.map { ring[$0] } }
        var k = first[0]
        for i in first where dist(ring[i], ring[0]) > dist(ring[k], ring[0]) { k = i }
        let rot = Array(ring[k...]) + Array(ring[1..<(k + 1)])
        var c = Array(rdp(rot, eps).dropLast())
        // drop a corner whose neighbours are nearly in line with it
        var changed = true
        while changed && c.count > 3 {
            changed = false
            for i in 0..<c.count {
                let prev = c[(i + c.count - 1) % c.count], next = c[(i + 1) % c.count]
                if segDist(c[i], prev, next) < eps * 0.9 { c.remove(at: i); changed = true; break }
            }
        }
        return c
    }

    /// JavaScript's Math.round (halves go up, also below zero), so both apps write the same numbers
    static func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }

    /// the shape's points as ink points ([x, y, force, azimuth, altitude, t, w, h, opacity]), each with the written stroke's own feel
    /// (its middle point's pressure, tilt, size, opacity), timed evenly over the time it was written in
    public static func shapePoints(_ shape: Recognized, written: [[Double]]) -> [[Double]] {
        let fallback: [Double] = [0, 0, 1, 0, Double.pi / 2, 0, 2, 2, 1]
        let mid = written.isEmpty ? fallback : written[written.count >> 1]
        func feel(_ i: Int) -> Double { i < mid.count ? mid[i] : fallback[i] }
        var T = 0.0
        if let last = written.last, last.count > 5 { T = last[5] }
        let n = shape.points.count
        func r2(_ v: Double) -> Double { jsRound(v * 100) / 100 }
        func r3(_ v: Double) -> Double { jsRound(v * 1000) / 1000 }
        var out: [[Double]] = []
        out.reserveCapacity(n)
        for (i, q) in shape.points.enumerated() {
            let t = n > 1 ? T * Double(i) / Double(n - 1) : 0
            out.append([r2(q.x), r2(q.y), feel(2), feel(3), feel(4), r3(t), feel(6), feel(7), feel(8)])
        }
        return out
    }

    /// Whether a written stroke's own points show it ended in a hold: its last points stay within `still` units of the end for at
    /// least `hold` seconds (`t`, index 5). The iPad's third way of noticing a hold, for when the Pencil's touches don't tell.
    public static func endsInHold(_ written: [[Double]], still: Double, hold: Double) -> Bool {
        guard written.count >= 2, let last = written.last, last.count > 5 else { return false }
        var since = last[5]
        for p in written.reversed() {
            guard p.count > 5 else { return false }
            if hypot(p[0] - last[0], p[1] - last[1]) > still { break }
            since = p[5]
        }
        return last[5] - since >= hold
    }
}
