import Foundation

/// What a tutor step draws, the same as the laptop's `renderer/src/tutor/draw.js`: the ink of arrows, lines, paths, marks and graphs as
/// board strokes, and a graph's labels as text. Every line is ordinary board ink (PencilKit's point format), monoline for a clean pen and
/// the marker for a highlight, with each point's time set as if written at a steady hand's speed, so it is like any other ink and the
/// app animates it by revealing points up to a time. Also the graph's function reader (`compileFn`): a small safe expression language.
public enum TutorDraw {
    public static let speed: Double = 900 // board units a second a line is written at
    public static let inkWidth: Double = 2.5
    public static let highlight = "#FFE14D"
    public static let monoline = "com.apple.ink.monoline"
    public static let marker = "com.apple.ink.marker"
    typealias P = [Double]

    static func r2(_ v: Double) -> Double { TutorSteps.jsRound(v * 100) / 100 }
    static func r3(_ v: Double) -> Double { TutorSteps.jsRound(v * 1000) / 1000 }
    static func dist(_ a: P, _ b: P) -> Double { hypot(b[0] - a[0], b[1] - a[1]) }

    // MARK: polylines

    /// Points every `step` units along a polyline; with corners kept (each vertex tripled) the curve the board draws passes through them.
    public static func densify(_ poly: [[Double]], step: Double = 4, corners: Bool = false) -> [[Double]] {
        guard poly.count >= 2 else { return poly }
        var out = [poly[0]]
        if corners { out += [poly[0], poly[0]] }
        for i in 1..<poly.count {
            let a = poly[i - 1], b = poly[i], n = max(1, Int(ceil(dist(a, b) / step)))
            for k in 1...n { let f = Double(k) / Double(n); out.append([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]) }
            if corners { out += [b, b] }
        }
        return out
    }
    public static func length(_ poly: [[Double]]) -> Double {
        guard poly.count > 1 else { return 0 }
        return (1..<poly.count).reduce(0) { $0 + dist(poly[$1 - 1], poly[$1]) }
    }
    /// A Catmull–Rom curve through the points.
    public static func smooth(_ points: [[Double]], closed: Bool = false, per: Int = 10) -> [[Double]] {
        let P = closed ? points + [points[0]] : points
        guard P.count >= 3 else { return P }
        func at(_ i: Int) -> [Double] { closed ? P[((i + P.count - 1) % (P.count - 1) + (P.count - 1)) % (P.count - 1)] : P[max(0, min(P.count - 1, i))] }
        var out: [[Double]] = []
        for i in 0..<(P.count - 1) {
            let p0 = at(i - 1), p1 = P[i], p2 = P[i + 1], p3 = closed && i + 2 >= P.count ? P[1] : at(i + 2)
            for k in 0..<per {
                let t = Double(k) / Double(per), t2 = t * t, t3 = t2 * t
                out.append((0...1).map { d in
                    let a = 2 * p1[d] + (-p0[d] + p2[d]) * t
                    let b = (2 * p0[d] - 5 * p1[d] + 4 * p2[d] - p3[d]) * t2
                    let c = (-p0[d] + 3 * p1[d] - 3 * p2[d] + p3[d]) * t3
                    return 0.5 * (a + b + c)
                })
            }
        }
        out.append(P[P.count - 1])
        return out
    }
    /// A polyline cut into dashes.
    public static func dashes(_ poly: [[Double]], on: Double = 10, off: Double = 7) -> [[[Double]]] {
        guard let first = poly.first else { return [] }
        var out: [[[Double]]] = [], cur: [[Double]]? = [first], left = on, drawing = true
        for i in 1..<max(1, poly.count) {
            var a = poly[i - 1]; let b = poly[i]; var seg = dist(a, b)
            while seg > left {
                let f = left / seg, m = [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f]
                if drawing { cur?.append(m); if let c = cur { out.append(c) }; cur = nil } else { cur = [m] }
                drawing.toggle(); seg -= left; left = drawing ? on : off; a = m
            }
            left -= seg
            if drawing { cur?.append(b) }
        }
        if drawing, let c = cur, c.count > 1 { out.append(c) }
        return out
    }

    // MARK: strokes

    /// How a line is drawn: colour `#RRGGBB`, width, ink id, corners kept, opacity, points spacing, speed.
    public struct Line: Equatable {
        public var points: [[Double]]
        public var color: String = "#1B1B1B"
        public var width: Double = TutorDraw.inkWidth
        public var ink: String = TutorDraw.monoline
        public var corners = false
        public var dash = false
        public var curve = false
        public init(points: [[Double]], color: String = "#1B1B1B", width: Double = TutorDraw.inkWidth, ink: String = TutorDraw.monoline, corners: Bool = false) {
            self.points = points; self.color = color; self.width = width; self.ink = ink; self.corners = corners
        }
    }

    /// A polyline -> a board stroke (no id yet), its point times from 0 at `speed`.
    public static func inkStroke(_ l: Line, step: Double = 3, alpha: Double? = nil) -> BoardStroke {
        let w = l.width, pts = densify(l.points, step: step, corners: l.corners)
        var t = 0.0
        var out: [[Double]] = []
        for (i, p) in pts.enumerated() {
            if i > 0 { t += dist(pts[i - 1], p) / speed }
            out.append([r2(p[0]), r2(p[1]), 1, 0, r3(Double.pi / 2), r3(t), w, w, 1])
        }
        let a = alpha.map { String(format: "%02X", Int(TutorSteps.jsRound(max(0, min(1, $0)) * 255))) } ?? "FF"
        return BoardStroke(id: "", ink: l.ink, color: String(l.color.prefix(7)).uppercased() + a, points: out)
    }
    public static func strokeTime(_ s: BoardStroke) -> Double { s.points.last.map { $0.count > 5 ? $0[5] : 0 } ?? 0 }
    /// The stroke as written up to time t (for the animation): nil before it starts.
    public static func strokeUpTo(_ s: BoardStroke, _ t: Double) -> BoardStroke? {
        if t >= strokeTime(s) { return s }
        guard let n = s.points.firstIndex(where: { $0[5] > t }), n >= 2 else { return nil }
        var c = s; c.points = Array(s.points[0..<n]); return c
    }

    // MARK: arrows and lines

    /// a, b: board points -> [shaft, heads...] polylines.
    /// outX: round the right of a column, out to x = outX and back (a bracket of an arrow; `columnArrow`).
    public static func arrowLines(_ a: [Double], _ b: [Double], bend: Double = 0, both: Bool = false, width: Double = inkWidth, head: Bool = true, outX: Double? = nil) -> [[[Double]]] {
        let L = dist(a, b) == 0 ? 1 : dist(a, b)
        var shaft: [[Double]]
        if let outX {
            let c1 = [outX, a[1]], c2 = [outX, b[1]]
            shaft = (0...24).map { i in
                let t = Double(i) / 24, u = 1 - t
                return [u * u * u * a[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t * t * t * b[0],
                        u * u * u * a[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t * t * t * b[1]]
            }
        } else if bend != 0 {
            let mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2, nx = -(b[1] - a[1]) / L, ny = (b[0] - a[0]) / L
            let c = [mx + nx * bend * L * 0.5, my + ny * bend * L * 0.5]
            shaft = (0...24).map { i in
                let t = Double(i) / 24, u = 1 - t
                return [u * u * a[0] + 2 * u * t * c[0] + t * t * b[0], u * u * a[1] + 2 * u * t * c[1] + t * t * b[1]]
            }
        } else { shaft = [a, b] }
        var out = [shaft]
        if head {
            let s = min(L * 0.35, 10 + width * 2)
            func headAt(_ tip: [Double], _ from: [Double]) -> [[Double]] {
                let d = dist(from, tip) == 0 ? 1 : dist(from, tip), ux = (tip[0] - from[0]) / d, uy = (tip[1] - from[1]) / d
                return [[tip[0] - ux * s - uy * s * 0.5, tip[1] - uy * s + ux * s * 0.5], tip, [tip[0] - ux * s + uy * s * 0.5, tip[1] - uy * s - ux * s * 0.5]]
            }
            out.append(headAt(b, shaft[shaft.count - 2]))
            if both { out.append(headAt(a, shaft[1])) }
        }
        return out
    }
    /// Does the segment a-b pass through the box (shrunk by `inset`)?
    public static func crossesBox(_ a: [Double], _ b: [Double], _ box: TutorBox, inset: Double = 2) -> Bool {
        let x0 = box.x + inset, y0 = box.y + inset, x1 = box.x + box.w - inset, y1 = box.y + box.h - inset
        if x1 <= x0 || y1 <= y0 { return false }
        var t0 = 0.0, t1 = 1.0
        let dx = b[0] - a[0], dy = b[1] - a[1]
        for (p, q) in [(-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])] {
            if p == 0 { if q < 0 { return false }; continue }
            let r = q / p
            if p < 0 { if r > t1 { return false }; if r > t0 { t0 = r } } else { if r < t0 { return false }; if r < t1 { t1 = r } }
        }
        return t0 < t1
    }
    public struct ColumnArrow: Equatable {
        public var from: [Double]
        public var to: [Double]
        public var outX: Double
    }
    /// An arrow from one block to another in the same column (one above the other): too close for a straight arrow to show, or one would
    /// go through the blocks between them -> its ends on the blocks' right sides and how far right it bows, else nil. others: the other
    /// blocks' boxes.
    public static func columnArrow(_ A: TutorBox, _ B: TutorBox, others: [TutorBox] = []) -> ColumnArrow? {
        let overlap = min(A.x + A.w, B.x + B.w) - max(A.x, B.x)
        if overlap < min(A.w, B.w) * 0.3 { return nil }
        let up = B.y < A.y, gap = up ? A.y - (B.y + B.h) : B.y - (A.y + A.h)
        let a = [A.x + A.w / 2, up ? A.y : A.y + A.h], b = [B.x + B.w / 2, up ? B.y + B.h : B.y]
        let between = others.filter { crossesBox(a, b, $0) }
        if gap >= 60 && between.isEmpty { return nil }
        let from = [A.x + A.w + 6, A.y + A.h / 2], to = [B.x + B.w + 8, B.y + B.h / 2]
        let right = ([from[0], to[0]] + between.map { $0.x + $0.w + 6 }).max()!
        return ColumnArrow(from: from, to: to, outX: right + 24 + min(40, abs(to[1] - from[1]) * 0.12))
    }
    /// An arrow's tail moved back along it until the arrow is at least `min` long (pointing at the same spot from the same side).
    public static func longEnough(_ from: [Double], _ to: [Double], min m: Double = 56) -> [Double] {
        let L = dist(from, to)
        if L >= m { return from }
        let ux = L > 0.5 ? (from[0] - to[0]) / L : -0.6, uy = L > 0.5 ? (from[1] - to[1]) / L : -0.8
        return [to[0] + ux * m, to[1] + uy * m]
    }
    /// Where a label goes beside a line: its middle, pushed off it to the upper side (side -1: the other). size [w, h]: the label's, so
    /// its near edge (not its middle) is `off` from the line.
    public static func labelAt(_ shaft: [[Double]], off: Double = 16, size: [Double]? = nil, side: Double = 0) -> [Double] {
        let mi = (shaft.count - 1) / 2
        let m = shaft[mi], n = shaft[min(shaft.count - 1, mi + 1)]
        let a = shaft.count == 2 ? shaft[0] : m, b = shaft.count == 2 ? shaft[1] : n
        let L = dist(a, b) == 0 ? 1 : dist(a, b), nx = -(b[1] - a[1]) / L, ny = (b[0] - a[0]) / L
        let s: Double = (ny > 0 ? -1 : 1) * (side < 0 ? -1 : 1)
        let mid = shaft.count == 2 ? [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2] : m
        var off = off
        if let size { off += abs(nx) * size[0] / 2 + abs(ny) * size[1] / 2 }
        return [mid[0] + nx * off * s, mid[1] + ny * off * s]
    }
    /// A label written as maths ("y = e^x", "a_2", "\\theta"): drawn as maths instead of showing its ^ and _.
    public static func isMathLabel(_ t: String) -> Bool { t.contains("^") || t.contains("_") || t.contains("\\") }

    static let mathSplit = try! NSRegularExpression(pattern: #"(\$\$?[^$]+\$\$?|`[^`]*`|\]\([^)]*\))"#)
    static let mathRun = try! NSRegularExpression(pattern: #"(^|[\s(=+\-−,:;])((?:[A-Za-z]{1,2}[0-9]*|[0-9]+(?:\.[0-9]+)?|\([^()\s]{1,20}\))(?:[\^_](?:\{[^{}]{1,30}\}|\([^()]{1,20}\)|-?[A-Za-z0-9]+(?:\.[0-9]+)?)[A-Za-z]{0,2})+)(?=$|[\s),.;:!?=+\-−])"#)
    static let mathBrace = try! NSRegularExpression(pattern: #"([\^_])(-?[0-9]{2,}(?:\.[0-9]+)?|-[A-Za-z0-9]+)"#)
    /// Every match of `re` in `s` replaced by what `with` makes of its groups (nil for a group that took no part).
    static func replace(_ re: NSRegularExpression, in s: String, with: ([String?]) -> String) -> String {
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { k -> String? in let r = m.range(at: k); return r.location == NSNotFound ? nil : ns.substring(with: r) }
            out += with(groups)
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
    /// A text block's maths written plainly ("the range of e^x", "a_n", "x^{2}+1") put in $…$ so it is drawn as maths, not with its ^
    /// and _; what is already in $…$, code and links stays as it is.
    public static func mathRuns(_ text: String) -> String {
        let ns = text as NSString
        var out = "", last = 0
        func plain(_ part: String) -> String {
            replace(mathRun, in: part) { g in
                (g[1] ?? "") + "$" + replace(mathBrace, in: g[2] ?? "") { h in (h[1] ?? "") + "{" + (h[2] ?? "") + "}" } + "$" // (2^10: 2^{10})
            }
        }
        for m in mathSplit.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += plain(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            out += ns.substring(with: m.range)
            last = m.range.location + m.range.length
        }
        return out + plain(ns.substring(from: last))
    }

    // MARK: marks around a box: a hand-drawn loop, a box, a line under it, a marker swipe over it, an arrow pointing at it

    /// The laptop's little random-number maker (same numbers for the same box on both apps).
    struct Wobble {
        var s: UInt64
        init(_ seed: UInt32) { s = UInt64(seed == 0 ? 1 : seed) }
        mutating func next() -> Double { s = (s &* 1664525 &+ 1013904223) & 0xFFFF_FFFF; return Double(s) / 4294967296 }
    }
    static func seedOf(_ b: TutorBox) -> UInt32 {
        let v = TutorSteps.jsRound(b.x * 7 + b.y * 13 + b.w * 3 + b.h * 5)
        return UInt32(truncatingIfNeeded: Int64(v))
    }

    public static func markLines(_ type: String, _ b: TutorBox, pad: Double = 8) -> [[[Double]]] {
        let x = b.x, y = b.y, w = b.w, hh = b.h
        switch type {
        case "circle":
            // clear of the box's corners; round a big block (a picture, a graph: their corners are empty) it stays close, not a loop over
            // its neighbours; a wide line (an equation) gets an oval only a little wider than it
            let k: Double = w > 120 && hh > 120 ? 1.08 : 1.32, wide = w > 3 * hh
            let c = TutorSteps.center(b), rx = max(14, wide ? w / 2 + pad + hh * 0.35 : w / 2 * k + pad), ry = max(12, wide ? hh / 2 * 1.32 + pad : hh / 2 * k + pad)
            var rnd = Wobble(seedOf(b))
            let start = -Double.pi * 0.6, sweep = Double.pi * 2 + 0.45, n = 72
            var out: [[Double]] = []
            for i in 0...n {
                let f = Double(i) / Double(n), t = start + sweep * f, k = 1 + f * 0.06 + (rnd.next() - 0.5) * 0.015
                out.append([c[0] + rx * k * cos(t), c[1] + ry * k * sin(t)])
            }
            return [out]
        case "box":
            return [[[x - pad, y - pad], [x + w + pad, y - pad], [x + w + pad, y + hh + pad], [x - pad, y + hh + pad], [x - pad, y - pad]]]
        case "underline":
            let yy = y + hh + max(3, pad / 2)
            return [[[x - 2, yy + 1], [x + w * 0.5, yy + 2.5], [x + w + 4, yy]]]
        case "highlight":
            let yy = y + hh / 2
            return [[[x - 2, yy], [x + max(w, 8) + 2, yy]]]
        case "point":
            let c = TutorSteps.center(b), from = [x - 44, y - 34]
            return arrowLines(from, w != 0 || hh != 0 ? TutorSteps.edgeToward(b, from, gap: 4) : c)
        default: return []
        }
    }

    // MARK: an angle

    /// An angle at corner `at` between the sides toward `from` and `to`: a small square for a right angle, else an arc across the smaller
    /// angle. -> lines (polylines) and where its label goes (on the bisector, outside the mark).
    public static func angleLines(_ at: [Double], _ from: [Double], _ to: [Double], right: Bool = false, r rr: Double? = nil) -> (lines: [[[Double]]], label: [Double]) {
        func u(_ p: [Double]) -> [Double] { let d = dist(at, p) == 0 ? 1 : dist(at, p); return [(p[0] - at[0]) / d, (p[1] - at[1]) / d] }
        let a = u(from), b = u(to), short = min(dist(at, from), dist(at, to))
        let r = rr ?? max(10, min(right ? 16 : 26, short * 0.4))
        var bis = [a[0] + b[0], a[1] + b[1]]
        let bl = hypot(bis[0], bis[1])
        bis = bl > 1e-6 ? [bis[0] / bl, bis[1] / bl] : [-a[1], a[0]]
        if right {
            let p1 = [at[0] + a[0] * r, at[1] + a[1] * r], p3 = [at[0] + b[0] * r, at[1] + b[1] * r], p2 = [p1[0] + b[0] * r, p1[1] + b[1] * r]
            return ([[p1, p2, p3]], [at[0] + bis[0] * (r * 1.41 + 14), at[1] + bis[1] * (r * 1.41 + 14)])
        }
        let t0 = atan2(a[1], a[0]), t1 = atan2(b[1], b[0])
        var d = t1 - t0
        while d > Double.pi { d -= 2 * Double.pi }
        while d < -Double.pi { d += 2 * Double.pi }
        let n = max(6, Int(ceil(abs(d) * r / 4)))
        let arc = (0...n).map { i -> [Double] in let t = t0 + d * Double(i) / Double(n); return [at[0] + r * cos(t), at[1] + r * sin(t)] }
        return ([arc], [at[0] + bis[0] * (r + 14), at[1] + bis[1] * (r + 14)])
    }

    // MARK: functions of x for graphs

    public struct FnError: Error, CustomStringConvertible { public var description: String }

    /// + - * / ^ (and **), unary minus, implicit products (2x, 3(x+1), x sin x), |x|, pi, e, and sin cos tan asin acos atan sinh cosh
    /// tanh exp ln log (base 10) log2 sqrt abs floor ceil sign. -> f(x) (NaN where undefined); throws on anything else. Never eval.
    public static func compileFn(_ src: String) throws -> (Double) -> Double {
        var s = src.replacingOccurrences(of: #"^\s*(?:y|f\s*\(\s*x\s*\))\s*="#, with: "", options: .regularExpression)
        for (a, b) in [("−", "-"), ("×", "*"), ("·", "*"), ("÷", "/"), ("**", "^"), ("²", "^2"), ("³", "^3"), ("π", "pi")] { s = s.replacingOccurrences(of: a, with: b) }
        let toks = try FnParser.tokens(s)
        guard !toks.isEmpty else { throw FnError(description: "empty") }
        var p = FnParser(toks: toks)
        let f = try p.expr()
        if p.i < p.toks.count { throw FnError(description: "unexpected " + p.toks[p.i].desc) }
        return { x in let v = f(x); return v.isFinite ? v : .nan }
    }

    static let fns: [String: (Double) -> Double] = [
        "sin": sin, "cos": cos, "tan": tan, "asin": asin, "acos": acos, "atan": atan, "sinh": sinh, "cosh": cosh, "tanh": tanh,
        "exp": exp, "ln": log, "log": log10, "log2": log2, "sqrt": { $0.squareRoot() }, "abs": { Swift.abs($0) }, "floor": { Foundation.floor($0) },
        "ceil": { Foundation.ceil($0) }, "sign": { $0 > 0 ? 1 : $0 < 0 ? -1 : $0 },
    ]

    struct FnParser {
        enum Tok { case n(Double), id(String), op(Character)
            var desc: String { switch self { case .n(let v): return JSONValue.format(v); case .id(let s): return s; case .op(let c): return String(c) } }
        }
        typealias F = (Double) -> Double
        var toks: [Tok]
        var i = 0

        static func tokens(_ s: String) throws -> [Tok] {
            var out: [Tok] = []
            let cs = Array(s)
            var k = 0
            while k < cs.count {
                let c = cs[k]
                if c.isWhitespace { k += 1; continue }
                if c.isASCII && (c.isNumber || (c == "." && k + 1 < cs.count && cs[k + 1].isASCII && cs[k + 1].isNumber)) {
                    var j = k
                    while j < cs.count, cs[j].isASCII, cs[j].isNumber { j += 1 }
                    if j < cs.count, cs[j] == "." { j += 1; while j < cs.count, cs[j].isASCII, cs[j].isNumber { j += 1 } }
                    if j < cs.count, cs[j] == "e" || cs[j] == "E" {
                        var e = j + 1
                        if e < cs.count, cs[e] == "+" || cs[e] == "-" { e += 1 }
                        if e < cs.count, cs[e].isASCII, cs[e].isNumber { j = e; while j < cs.count, cs[j].isASCII, cs[j].isNumber { j += 1 } }
                    }
                    out.append(.n(Double(String(cs[k..<j])) ?? .nan)); k = j; continue
                }
                if c.isASCII && c.isLetter {
                    var j = k
                    while j < cs.count, cs[j].isASCII, cs[j].isLetter || cs[j].isNumber { j += 1 }
                    out.append(.id(String(cs[k..<j]).lowercased())); k = j; continue
                }
                out.append(.op(c)); k += 1
            }
            return out
        }

        func isOp(_ o: Character) -> Bool { if i < toks.count, case .op(let c) = toks[i] { return c == o }; return false }
        func startsAtom() -> Bool {
            guard i < toks.count else { return false }
            switch toks[i] { case .n, .id: return true; case .op(let c): return c == "(" }
        }
        mutating func expr() throws -> F {
            var f = try term()
            while isOp("+") || isOp("-") {
                let plus = isOp("+"); i += 1
                let a = f, b = try term()
                f = plus ? { a($0) + b($0) } : { a($0) - b($0) }
            }
            return f
        }
        mutating func term() throws -> F {
            var f = try unary()
            while true {
                if isOp("*") || isOp("/") {
                    let times = isOp("*"); i += 1
                    let a = f, b = try unary()
                    f = times ? { a($0) * b($0) } : { a($0) / b($0) }
                } else if startsAtom() {
                    let a = f, b = try power()
                    f = { a($0) * b($0) }
                } else { return f }
            }
        }
        mutating func unary() throws -> F {
            if isOp("-") { i += 1; let a = try unary(); return { -a($0) } }
            if isOp("+") { i += 1; return try unary() }
            return try power()
        }
        mutating func power() throws -> F {
            let a = try atom()
            if isOp("^") { i += 1; let b = try unary(); return { pow(a($0), b($0)) } }
            return a
        }
        mutating func atom() throws -> F {
            guard i < toks.count else { throw FnError(description: "ends too soon") }
            let t = toks[i]; i += 1
            switch t {
            case .n(let v): return { _ in v }
            case .op("("):
                let f = try expr()
                guard isOp(")") else { throw FnError(description: "missing )") }
                i += 1; return f
            case .op("|"):
                let f = try expr()
                guard isOp("|") else { throw FnError(description: "missing |") }
                i += 1; return { Swift.abs(f($0)) }
            case .id(let id):
                if id == "x" { return { $0 } }
                if id == "pi" { return { _ in Double.pi } }
                if id == "e" { return { _ in M_E } }
                if let fn = TutorDraw.fns[id] {
                    let arg: F
                    if isOp("(") {
                        i += 1; arg = try expr()
                        guard isOp(")") else { throw FnError(description: "missing )") }
                        i += 1
                    } else { arg = try power() }
                    if isOp("^") { i += 1; let b = try unary(); return { pow(fn(arg($0)), b($0)) } }
                    return { fn(arg($0)) }
                }
                // a run of letters like "xsinx" or "2pix": products of what it is made of
                if let parts = FnParser.split(id) {
                    i -= 1
                    toks.replaceSubrange(i...i, with: parts.map { Tok.id($0) })
                    return try atom()
                }
                throw FnError(description: "unknown name " + id)
            case .op(let c): throw FnError(description: "unexpected " + String(c))
            }
        }
        static func split(_ id: String) -> [String]? {
            let names = (["x", "pi", "e"] + Array(TutorDraw.fns.keys)).sorted { $0.count > $1.count }
            var out: [String] = []
            var rest = Substring(id)
            while !rest.isEmpty {
                guard let n = names.first(where: { rest.hasPrefix($0) }) else { return nil }
                out.append(n); rest = rest.dropFirst(n.count)
            }
            return out.count > 1 ? out : nil
        }
    }

    // MARK: a graph

    public struct GraphLabel: Equatable {
        public var text: String
        public var x: Double
        public var y: Double
        public var size: Double
        public var color: String
        /// left, center, right or leftmid: which side of the label sits at x (and for center and leftmid, y is its middle, else its top).
        public var anchor: String
    }

    /// Where the plot sits in its box, and its ranges: a graph's own point -> a board point (`graphPoint`).
    public struct GraphGeom: Equatable {
        public var X0, X1, Y0, Y1: Double
        public var x: [Double]
        public var y: [Double]
    }

    public struct GraphPlan {
        public var lines: [Line]
        public var labels: [GraphLabel]
        public var error: String?
        public var xRange: [Double]
        public var yRange: [Double]
        public var geom: GraphGeom
    }

    static func nice(_ span: Double) -> Double {
        let p = pow(10, floor(log10(span / 6))), m = span / 6 / p
        return p * (m < 1.5 ? 1 : m < 3.5 ? 2 : m < 7.5 ? 5 : 10)
    }
    static func fmt(_ v: Double) -> String { JSONValue.format(TutorSteps.jsRound(v * 1000) / 1000).replacingOccurrences(of: "-", with: "−") }
    /// A multiple of π/2 as a trig axis writes it: π/2, π, 3π/2, −π.
    static func piFmt(_ v: Double) -> String {
        let n = Int(TutorSteps.jsRound(v / (Double.pi / 2)))
        if n == 0 { return "0" }
        let s = n < 0 ? "−" : "", a = Swift.abs(n)
        return s + (a % 2 == 1 ? (a == 1 ? "" : String(a)) + "π/2" : (a == 2 ? "" : String(a / 2)) + "π")
    }
    /// A label's box [x, y, w, h] as the board places it (x by its anchor; y its top, a centred one's middle), its size guessed from its text.
    static func labelBox(_ l: GraphLabel, w: Double? = nil, h: Double? = nil) -> TutorBox {
        let w = w ?? Double(l.text.utf16.count) * l.size * 0.55, h = h ?? l.size * 1.4
        return TutorBox(l.anchor == "right" ? l.x - w : l.anchor == "center" ? l.x - w / 2 : l.x,
                        l.anchor == "center" || l.anchor == "leftmid" ? l.y - h / 2 : l.y, w, h)
    }
    /// A graph's own point (its numbers) -> the board point, from the plan's geometry.
    public static func graphPoint(_ g: GraphGeom, _ p: [Double]) -> [Double] {
        [g.X0 + (p[0] - g.x[0]) / (g.x[1] - g.x[0]) * (g.X1 - g.X0), g.Y1 - (p[1] - g.y[0]) / (g.y[1] - g.y[0]) * (g.Y1 - g.Y0)]
    }

    /// A graph step drawn in its box on the board.
    public static func graphPlan(_ step: TutorStep, box: TutorBox) -> GraphPlan {
        let xLabelW = step.xLabel.map { min(90, Double($0.utf16.count) * 13 * 0.55) + 8 } ?? 0 // (the x axis's name goes past its arrow head)
        let bx = box.x, by = box.y, bw = box.w, bh = box.h
        let padL = 30.0, padB = 22.0, padT = 10.0, padR = 12.0 + xLabelW
        let X0 = bx + padL, X1 = bx + bw - padR, Y0 = by + padT, Y1 = by + bh - padB
        let xa = step.xRange?[0] ?? -5, xb = step.xRange?[1] ?? 5
        var compiled: [(TutorFn, (Double) -> Double)] = []
        var errors: [String] = []
        for f in step.fns {
            do { compiled.append((f, try compileFn(f.fn))) } catch { errors.append(f.fn + ": " + String(describing: error)) }
        }
        let N = 240
        let samples: [[[Double]]] = compiled.map { _, f in (0...N).map { k in let x = xa + (xb - xa) * Double(k) / Double(N); return [x, f(x)] } }
        var ya: Double, yb: Double
        if let yr = step.yRange { ya = yr[0]; yb = yr[1] } else {
            let ys = (samples.flatMap { $0.map { $0[1] } }.filter { $0.isFinite } + step.graphPoints.map(\.y)).sorted()
            if ys.isEmpty { ya = -5; yb = 5 } else {
                let lo = ys[Int(floor(Double(ys.count) * 0.03))], hi = ys[max(0, Int(ceil(Double(ys.count) * 0.97)) - 1)]
                let m = max(1e-6, hi - lo) * 0.1
                ya = min(lo - m, 0 <= hi && 0 >= lo - m * 3 ? min(0, lo - m) : lo - m)
                yb = hi + m
                if ya == yb { ya -= 1; yb += 1 }
            }
        }
        func sx(_ x: Double) -> Double { X0 + (x - xa) / (xb - xa) * (X1 - X0) }
        func sy(_ y: Double) -> Double { Y1 - (y - ya) / (yb - ya) * (Y1 - Y0) }
        var lines: [Line] = [], labels: [GraphLabel] = []
        let grey = "#6B6B6B", ink = "#1B1B1B"
        // axes: through 0 when 0 is in range, else along the edge; small arrow heads at the positive ends
        let ax = xa <= 0 && xb >= 0 ? sx(0) : X0, ay = ya <= 0 && yb >= 0 ? sy(0) : Y1
        for l in arrowLines([X0 - 4, ay], [X1 + 8, ay], width: 1.5) { lines.append(Line(points: l, color: ink, width: 1.5, corners: true)) }
        for l in arrowLines([ax, Y1 + 4], [ax, Y0 - 6], width: 1.5) { lines.append(Line(points: l, color: ink, width: 1.5, corners: true)) }
        // ticks; a trig graph's x axis in steps of π/2 (π, 2π when that is too many)
        let trig = compiled.contains { f in ["sin", "cos", "tan"].contains { f.0.fn.contains($0) } } && xb - xa >= Double.pi / 2
        let tx = trig ? (xb - xa > 7 * Double.pi ? Double.pi * 2 : xb - xa > 3.5 * Double.pi ? Double.pi : Double.pi / 2) : nice(xb - xa), ty = nice(yb - ya)
        let xfmt: (Double) -> String = trig ? piFmt : fmt
        var v = ceil(xa / tx) * tx
        while v <= xb + 1e-9 { if abs(v) > tx / 2 || ax != sx(0) { lines.append(Line(points: [[sx(v), ay - 3], [sx(v), ay + 3]], color: ink, width: 1.2)) }; v += tx }
        v = ceil(ya / ty) * ty
        while v <= yb + 1e-9 { if abs(v) > ty / 2 || ay != sy(0) { lines.append(Line(points: [[ax - 3, sy(v)], [ax + 3, sy(v)]], color: ink, width: 1.2)) }; v += ty }
        // tick numbers: every tick that has room (not on top of the one before), 0 once at the corner where the axes cross
        let TICK = 12.0
        func room(_ prev: Double?, _ at: Double, _ need: Double) -> Bool { prev == nil || abs(at - prev!) >= need }
        var lastX: Double?, lastY: Double?
        v = ceil(xa / tx) * tx
        while v <= xb + 1e-9 {
            defer { v += tx }
            if abs(v) < tx / 2 && ax == sx(0) { continue }
            let t = xfmt(v), X = sx(v)
            if !room(lastX, X, Double(t.utf16.count) * TICK * 0.6 + 8) || X > X1 - 4 { continue } // (none under the arrow head)
            labels.append(GraphLabel(text: t, x: X, y: ay + 5 + TICK * 0.7, size: TICK, color: grey, anchor: "center")); lastX = X
        }
        v = ceil(ya / ty) * ty
        while v <= yb + 1e-9 {
            defer { v += ty }
            if abs(v) < ty / 2 && ay == sy(0) { continue }
            let Y = sy(v)
            if !room(lastY, Y, TICK + 4) || Y < Y0 + 6 { continue } // (none beside the arrow head)
            labels.append(GraphLabel(text: fmt(v), x: ax - 6, y: Y - TICK * 0.75, size: TICK, color: grey, anchor: "right")); lastY = Y
        }
        if ax == sx(0) && ay == sy(0) { labels.append(GraphLabel(text: "0", x: ax - 5, y: ay + 3, size: TICK, color: grey, anchor: "right")) }
        if let l = step.xLabel { labels.append(GraphLabel(text: l, x: X1 + 14, y: ay, size: 13, color: ink, anchor: "leftmid")) }
        if let l = step.yLabel { labels.append(GraphLabel(text: l, x: ax + 8, y: Y0 - 10, size: 13, color: ink, anchor: "left")) }
        // curves: split where they leave the range or jump (an asymptote)
        let cols = ["#1F5FD1", "#D93025", "#188038", "#8E44AD", "#C26A00", "#1B1B1B"]
        let slack = (yb - ya) * 0.02
        func colorOf(_ k: Int) -> String { compiled[k].0.color ?? step.color ?? cols[k % cols.count] }
        for (k, pts) in samples.enumerated() {
            let color = colorOf(k)
            var run: [[Double]] = []
            func flush() { if run.count > 1 { var l = Line(points: run, color: color, width: 2.5); l.curve = true; lines.append(l) }; run = [] }
            for p in pts {
                let x = p[0], y = p[1]
                if !y.isFinite || y < ya - slack || y > yb + slack { flush(); continue }
                let P = [sx(x), sy(y)]
                if let last = run.last, abs(P[1] - last[1]) > (Y1 - Y0) * 0.6 { flush() }
                run.append(P)
            }
            flush()
        }
        // a label goes where it covers the least: curves, the axes, labels already placed, outside the box
        let ink2 = lines.filter(\.curve).flatMap(\.points)
        var placed = labels.map { labelBox($0) }
        func bestOf(_ text: String, _ color: String, _ spots: [(Double, Double, String, Double)]) {
            let size = 13.0, w = Double(text.utf16.count) * size * 0.55, h = size * 1.4
            var best: (score: Double, l: GraphLabel, b: TutorBox)?
            for (x, y, anchor, extra) in spots {
                let l = GraphLabel(text: text, x: x, y: y, size: size, color: color, anchor: anchor), b = labelBox(l, w: w, h: h)
                var score = extra
                for q in ink2 where q[0] > b.x - 3 && q[0] < b.x + b.w + 3 && q[1] > b.y - 3 && q[1] < b.y + b.h + 3 { score += 1 }
                if ay > b.y - 2 && ay < b.y + b.h + 2 { score += 20 } // (across the x axis)
                if ax > b.x - 2 && ax < b.x + b.w + 2 { score += 20 } // (across the y axis)
                for o in placed where b.x < o.x + o.w + 4 && b.x + b.w + 4 > o.x && b.y < o.y + o.h + 2 && b.y + b.h + 2 > o.y { score += 30 }
                if b.x < bx || b.x + b.w > bx + bw || b.y < by - 4 || b.y + b.h > by + bh { score += 8 }
                if best == nil || score < best!.score { best = (score, l, b) }
            }
            if let best { labels.append(best.l); placed.append(best.b) }
        }
        // a curve's name beside it, near its end or three quarters along, on whichever side is clear
        for (k, pts) in samples.enumerated() {
            guard let name = compiled[k].0.label else { continue }
            let inside = pts.filter { $0[1].isFinite && $0[1] >= ya && $0[1] <= yb }
            if inside.isEmpty { continue }
            var spots: [(Double, Double, String, Double)] = []
            for (f, extra) in [(0.97, 0.0), (0.75, 2.0), (0.5, 4.0)] {
                let q = inside[min(inside.count - 1, Int(floor(Double(inside.count) * f)))], P = [min(sx(q[0]), X1 - 4), sy(q[1])]
                spots += [(P[0] - 6, P[1] - 24, "right", extra), (P[0] - 6, P[1] + 8, "right", extra), (P[0] + 6, P[1] - 24, "left", extra + 1), (P[0] + 6, P[1] + 8, "left", extra + 1)]
            }
            bestOf(name, colorOf(k), spots)
        }
        // a point: a dot in the colour of the curve it is on (the nearest), its name on the side of it the curve and the axes leave free
        for p in step.graphPoints {
            let P = [sx(p.x), sy(p.y)]
            if P[0] < X0 - 1 || P[0] > X1 + 1 || P[1] < Y0 - 1 || P[1] > Y1 + 1 { continue }
            var near = -1, gap = Double.infinity
            for (k, f) in compiled.enumerated() { let y = f.1(p.x); if y.isFinite && abs(sy(y) - P[1]) < gap { gap = abs(sy(y) - P[1]); near = k } }
            let pc = step.color ?? (near >= 0 && gap < 10 ? colorOf(near) : ink)
            let dot = (0...16).map { k -> [Double] in let t = 2 * Double.pi * Double(k) / 16; return [P[0] + 3 * cos(t), P[1] + 3 * sin(t)] }
            lines.append(Line(points: dot, color: pc, width: 3))
            guard let name = p.label else { continue }
            let h = 13 * 1.4
            bestOf(name, pc, [(P[0] + 7, P[1] - h - 2, "left", 0), (P[0] - 7, P[1] - h - 2, "right", 0), (P[0] + 7, P[1] + 3, "left", 0),
                              (P[0] - 7, P[1] + 3, "right", 0), (P[0] + 10, P[1] - h / 2, "left", 0), (P[0] - 10, P[1] - h / 2, "right", 0)])
        }
        return GraphPlan(lines: lines, labels: labels, error: errors.isEmpty ? nil : errors.joined(separator: "; "), xRange: [xa, xb], yRange: [ya, yb],
                         geom: GraphGeom(X0: X0, X1: X1, Y0: Y0, Y1: Y1, x: [xa, xb], y: [ya, yb]))
    }
}
