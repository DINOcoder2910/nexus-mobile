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
    public static func arrowLines(_ a: [Double], _ b: [Double], bend: Double = 0, both: Bool = false, width: Double = inkWidth, head: Bool = true) -> [[[Double]]] {
        let L = dist(a, b) == 0 ? 1 : dist(a, b)
        var shaft: [[Double]]
        if bend != 0 {
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
    /// Where a label goes beside a line: its middle, pushed off it to the upper side.
    public static func labelAt(_ shaft: [[Double]], off: Double = 16) -> [Double] {
        let mi = (shaft.count - 1) / 2
        let m = shaft[mi], n = shaft[min(shaft.count - 1, mi + 1)]
        let a = shaft.count == 2 ? shaft[0] : m, b = shaft.count == 2 ? shaft[1] : n
        let L = dist(a, b) == 0 ? 1 : dist(a, b), nx = -(b[1] - a[1]) / L, ny = (b[0] - a[0]) / L, s: Double = ny > 0 ? -1 : 1
        let mid = shaft.count == 2 ? [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2] : m
        return [mid[0] + nx * off * s, mid[1] + ny * off * s]
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
            let c = TutorSteps.center(b), rx = max(14, w / 2 * 1.32 + pad), ry = max(12, hh / 2 * 1.32 + pad)
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
        /// left, center or right: which side of the label sits at x.
        public var anchor: String
    }

    public struct GraphPlan {
        public var lines: [Line]
        public var labels: [GraphLabel]
        public var error: String?
        public var xRange: [Double]
        public var yRange: [Double]
    }

    static func nice(_ span: Double) -> Double {
        let p = pow(10, floor(log10(span / 6))), m = span / 6 / p
        return p * (m < 1.5 ? 1 : m < 3.5 ? 2 : m < 7.5 ? 5 : 10)
    }
    static func fmt(_ v: Double) -> String { JSONValue.format(TutorSteps.jsRound(v * 1000) / 1000).replacingOccurrences(of: "-", with: "−") }

    /// A graph step drawn in its box on the board.
    public static func graphPlan(_ step: TutorStep, box: TutorBox) -> GraphPlan {
        let padL = 30.0, padB = 22.0, padT = 10.0, padR = 12.0
        let X0 = box.x + padL, X1 = box.x + box.w - padR, Y0 = box.y + padT, Y1 = box.y + box.h - padB
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
        let ax = xa <= 0 && xb >= 0 ? sx(0) : X0, ay = ya <= 0 && yb >= 0 ? sy(0) : Y1
        for l in arrowLines([X0 - 4, ay], [X1 + 8, ay], width: 1.5) { lines.append(Line(points: l, color: ink, width: 1.5, corners: true)) }
        for l in arrowLines([ax, Y1 + 4], [ax, Y0 - 6], width: 1.5) { lines.append(Line(points: l, color: ink, width: 1.5, corners: true)) }
        let tx = nice(xb - xa), ty = nice(yb - ya)
        var v = ceil(xa / tx) * tx
        while v <= xb + 1e-9 { if abs(v) > tx / 2 || ax != sx(0) { lines.append(Line(points: [[sx(v), ay - 3], [sx(v), ay + 3]], color: ink, width: 1.2)) }; v += tx }
        v = ceil(ya / ty) * ty
        while v <= yb + 1e-9 { if abs(v) > ty / 2 || ay != sy(0) { lines.append(Line(points: [[ax - 3, sy(v)], [ax + 3, sy(v)]], color: ink, width: 1.2)) }; v += ty }
        labels.append(GraphLabel(text: fmt(ceil(xa / tx) * tx), x: sx(ceil(xa / tx) * tx), y: ay + 6, size: 11, color: grey, anchor: "center"))
        labels.append(GraphLabel(text: fmt(floor(xb / tx) * tx), x: sx(floor(xb / tx) * tx), y: ay + 6, size: 11, color: grey, anchor: "center"))
        labels.append(GraphLabel(text: fmt(floor(yb / ty) * ty), x: ax - 6, y: sy(floor(yb / ty) * ty) - 7, size: 11, color: grey, anchor: "right"))
        labels.append(GraphLabel(text: fmt(ceil(ya / ty) * ty), x: ax - 6, y: sy(ceil(ya / ty) * ty) - 7, size: 11, color: grey, anchor: "right"))
        if let l = step.xLabel { labels.append(GraphLabel(text: l, x: X1 + 10, y: ay - 18, size: 13, color: ink, anchor: "right")) }
        if let l = step.yLabel { labels.append(GraphLabel(text: l, x: ax + 8, y: Y0 - 10, size: 13, color: ink, anchor: "left")) }
        let cols = ["#1F5FD1", "#D93025", "#188038", "#8E44AD", "#C26A00", "#1B1B1B"]
        let slack = (yb - ya) * 0.02
        for (k, pts) in samples.enumerated() {
            let fn = compiled[k].0
            let color = fn.color ?? step.color ?? cols[k % cols.count]
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
            if let label = fn.label, let last = pts.reversed().first(where: { $0[1].isFinite && $0[1] >= ya && $0[1] <= yb }) {
                labels.append(GraphLabel(text: label, x: min(sx(last[0]), X1) - 8, y: max(Y0 + 2 + Double(k) * 18, min(Y1 - 20, sy(last[1]) - 8)),
                                         size: 13, color: color, anchor: "right"))
            }
        }
        for p in step.graphPoints {
            let P = [sx(p.x), sy(p.y)]
            if P[0] < X0 - 1 || P[0] > X1 + 1 || P[1] < Y0 - 1 || P[1] > Y1 + 1 { continue }
            let dot = (0...16).map { k -> [Double] in let t = 2 * Double.pi * Double(k) / 16; return [P[0] + 2.5 * cos(t), P[1] + 2.5 * sin(t)] }
            lines.append(Line(points: dot, color: step.color ?? ink, width: 3))
            if let l = p.label { labels.append(GraphLabel(text: l, x: P[0] + 7, y: P[1] - 20, size: 13, color: step.color ?? ink, anchor: "left")) }
        }
        return GraphPlan(lines: lines, labels: labels, error: errors.isEmpty ? nil : errors.joined(separator: "; "), xRange: [xa, xb], yRange: [ya, yb])
    }
}
