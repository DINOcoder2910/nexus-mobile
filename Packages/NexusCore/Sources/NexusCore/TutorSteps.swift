import Foundation

/// The tutor's drawing steps, the same as the laptop's `renderer/src/tutor/steps.js` (format `nexus-tutor-steps/1`, nexus
/// docs/data-format.md "Tutor steps"). Claude doesn't make pictures: it writes short steps ("arrow from here to there", "equation",
/// "graph of this function") and Nexus draws them like a pen. This is the contract between the two apps: what a step is (`check`,
/// `prompt`), how steps go with the spoken sentences (`beats`), where a step lands (the geometry), and the summary of what is already
/// drawn that a follow-up turn is told (`summarize`).
///
/// Board coordinates are board units (1 unit = 1 iPad point at 100 %, y down), relative to the turn's frame: the app puts the frame's
/// (0, 0) somewhere free on the board.
public enum TutorSteps {
    public static let format = "nexus-tutor-steps/1"
    public static let blockTypes = ["text", "math", "graph", "chem"]
    public static let lineTypes = ["arrow", "line", "path"]
    public static let markTypes = ["circle", "box", "underline", "highlight", "point"]
    /// (angle: a right-angle square or an arc at a corner)
    public static let stepTypes = blockTypes + lineTypes + markTypes + ["angle", "erase"]
    /// The ones that may be `brief`: shown while their sentence is said, then gone.
    public static let briefTypes = ["arrow", "line"] + markTypes + ["angle"]
    public static let screenTypes = ["point", "circle", "underline", "highlight"]
    public static let chemKinds = ["lewis", "vsepr", "cycle"]
    public static let sides = ["center", "top", "bottom", "left", "right", "topleft", "topright", "bottomleft", "bottomright"]
    /// Named colours (the board text's own, so a block and its ink match); `#RRGGBB` is taken too.
    public static let colors: [String: String] = ["ink": "#1B1B1B", "grey": "#6B6B6B", "blue": "#1F5FD1", "red": "#D93025", "green": "#188038",
                                                  "purple": "#8E44AD", "orange": "#C26A00", "yellow": "#F2C200"]
    public static let sizes: [String: Double] = ["small": 13, "normal": 16, "large": 22, "huge": 32]
    public static let mathSize: Double = 22
    public static let gap: Double = 24
    public static let graphW: Double = 380, graphH: Double = 260
    /// A text block put beside another wraps at this width.
    public static let sideNoteW: Double = 240
    /// A diagram's width and its height as a fraction of the width.
    public static let chemSize: [String: (Double, Double)] = ["lewis": (320, 340.0 / 460), "vsepr": (220, 1), "cycle": (520, 430.0 / 760)]
    static let maxCoord: Double = 100000

    // MARK: small readers, as steps.js has them

    static func num(_ v: JSONValue?) -> Double? {
        switch v {
        case .number(let n)?: return n.isFinite ? n : nil
        case .string(let s)?:
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, let n = Double(t), n.isFinite else { return nil }
            return n
        default: return nil
        }
    }
    /// JavaScript's Math.round (halves go up).
    static func jsRound(_ v: Double) -> Double { (v + 0.5).rounded(.down) }
    static func r2(_ v: Double) -> Double { jsRound(max(-maxCoord, min(maxCoord, v)) * 100) / 100 }
    static func str(_ v: JSONValue?, _ maxLen: Int) -> String? {
        guard let s = v?.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(s.prefix(maxLen))
    }
    static func pt(_ v: JSONValue?) -> [Double]? {
        guard let a = v?.array, a.count == 2 else { return nil }
        let n = a.compactMap { num($0) }
        return n.count == 2 ? n.map(r2) : nil
    }
    static func rect(_ v: JSONValue?) -> [Double]? {
        guard let a = v?.array, a.count == 4 else { return nil }
        let n = a.compactMap { num($0) }
        guard n.count == 4, n[2] >= 0, n[3] >= 0 else { return nil }
        return n.map(r2)
    }
    static func isId(_ s: String) -> Bool { s.range(of: #"^[A-Za-z0-9_-]{1,32}$"#, options: .regularExpression) != nil }
    public static func color(of v: JSONValue?) -> String? {
        guard let c = v?.string else { return nil }
        if let named = colors[c.lowercased()] { return named }
        if c.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil { return c.uppercased() }
        return nil
    }

    /// An id, or "$last" (the block drawn last) as "last".
    static func idOf(_ v: JSONValue?) -> String? {
        guard let s = v?.string else { return nil }
        if s == "$last" { return "last" }
        return isId(s) ? s : nil
    }
    /// Inside a block: { in: id, part: "text" } (those words or symbols of a text or maths block, as drawn) or { in: id, at: [x, y] } (a
    /// point of a graph, in the graph's own numbers); { in: id } alone is the whole block.
    static func inside(_ v: JSONValue?) -> TutorInside? {
        guard case .object? = v, let id = idOf(v?["in"]) else { return nil }
        if let part = v?["part"]?.string, !part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TutorInside(id: id, part: String(part.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)))
        }
        if let p = pt(v?["at"]) { return TutorInside(id: id, at: p) }
        return TutorInside(id: id)
    }
    static func ofPos(_ v: JSONValue?) -> TutorPos? {
        guard let of = v?["of"]?.string, isId(of) else { return nil }
        let side = v?["side"]?.string.flatMap { sides.contains($0) ? $0 : nil } ?? "center"
        return .of(of, side: side, dx: num(v?["dx"]).map(r2), dy: num(v?["dy"]).map(r2))
    }
    /// A position (`from`, `to`, an angle's `at`): [x, y]; an id; { of: id, side, dx, dy }; or a place inside a block.
    static func pos(_ v: JSONValue?) -> TutorPos? {
        switch v {
        case .string?: return idOf(v).map { .id($0) }
        case .array?: return pt(v).map { .point($0[0], $0[1]) }
        case .object?:
            if let i = v?["in"], i != .null { return inside(v).map { .inside($0) } }
            return ofPos(v)
        default: return nil
        }
    }
    /// A target (what a mark goes around): [x, y, w, h], [x, y], an id, a side of a block ({ of: id, side }), or a place inside a block.
    static func target(_ v: JSONValue?) -> TutorTarget? {
        switch v {
        case .string?: return idOf(v).map { .id($0) }
        case .array?:
            if let r = rect(v) { return .rect(r[0], r[1], r[2], r[3]) }
            if let p = pt(v) { return .point(p[0], p[1]) }
            return nil
        case .object?:
            if let i = v?["in"], i != .null { return inside(v).map { .inside($0) } }
            if case .of(let id, let side, let dx, let dy)? = ofPos(v) { return .of(id, side: side, dx: dx, dy: dy) }
            return nil
        default: return nil
        }
    }
    static func place(_ v: JSONValue?) -> TutorPlace? {
        if case .array? = v { return pt(v).map { .point($0[0], $0[1]) } }
        guard case .object? = v else { return nil }
        guard let rel = ["below", "above", "right", "left"].first(where: { k in v?[k]?.string.map(isId) == true }) else { return nil }
        return .beside(rel, v![rel]!.string!, gap: num(v?["gap"]).map { r2(max(0, $0)) })
    }
    static func sizeOf(_ v: JSONValue?) -> Double? {
        if let s = v?.string { return sizes[s.lowercased()] }
        if let n = num(v) { return max(10, min(64, n)) }
        return nil
    }

    // MARK: one step

    /// The raw object Claude wrote -> a clean step, or nil with the reason.
    public static func check(_ input: JSONValue) -> (step: TutorStep?, problem: String?) {
        var raw = input
        if case .object? = raw["step"] { raw = raw["step"]! } // a { step } event
        func bad(_ why: String) -> (step: TutorStep?, problem: String?) { (nil, why) }
        guard case .object = raw else { return bad("not an object") }
        let type = raw["type"]?.string?.lowercased() ?? ""
        guard stepTypes.contains(type) else { return bad("unknown type " + (raw["type"].map { $0.text } ?? "undefined")) }
        var s = TutorStep(type: type)
        if let idv = raw["id"], idv != .null {
            guard let id = idv.string, isId(id) else { return bad("bad id " + idv.text) }
            s.id = id
        }
        s.color = color(of: raw["color"])
        s.label = str(raw["label"], 80)

        // the screen overlay's marks (the laptop's): pixels of the screenshot
        if raw["on"]?.string == "screen" {
            guard screenTypes.contains(type) else { return bad(type + " is not drawn on the screen") }
            s.on = "screen"
            if let shot = raw["shot"]?.string, !shot.isEmpty { s.shot = String(shot.prefix(64)) }
            if let r = rect(raw["target"]) { s.target = .rect(r[0], r[1], r[2], r[3]) }
            else if let p = pt(raw["target"]) { s.target = .point(p[0], p[1]) }
            else if let a = raw["area"]?.string?.uppercased(), a.range(of: #"^[A-Z]{1,2}[0-9]{1,2}$"#, options: .regularExpression) != nil { s.area = a }
            else { return bad(type + " on the screen needs target [x, y] or [x, y, w, h], or area") }
            return (s, nil)
        }

        if blockTypes.contains(type) {
            if let at = raw["at"], at != .null {
                guard let p = place(at) else { return bad(type + ": bad at") }
                s.at = p
            }
            if let w = num(raw["w"]), w >= 40 { s.w = r2(min(w, 2000)) }
        }
        switch type {
        case "text":
            guard let text = str(raw["text"], 2000) else { return bad("text needs text") }
            s.text = text
            if let size = sizeOf(raw["size"]), size != sizes["normal"]! { s.size = size }
        case "math":
            guard let tex = str(raw["tex"], 600) else { return bad("math needs tex") }
            let t = tex.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^\$+|\$+$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return bad("math needs tex") }
            s.tex = t
            if let size = sizeOf(raw["size"]), size != mathSize { s.size = size }
        case "graph":
            let list: [JSONValue] = raw["fn"]?.string != nil ? [.object([("fn", raw["fn"]!)])] : (raw["fns"]?.array ?? [])
            s.fns = list.prefix(6).compactMap { f -> TutorFn? in
                let o: JSONValue = f.string != nil ? .object([("fn", f)]) : f
                guard let fn = str(o["fn"], 200) else { return nil }
                return TutorFn(fn: String(fn.prefix(200)), color: color(of: o["color"]), label: str(o["label"], 40))
            }
            s.graphPoints = (raw["points"]?.array ?? []).prefix(40).compactMap { p -> TutorGraphPoint? in
                guard let a = p.array, a.count >= 2, let x = num(a[0]), let y = num(a[1]) else { return nil }
                return TutorGraphPoint(x: r2(x), y: r2(y), label: a.count > 2 ? str(a[2], 40) : nil)
            }
            if s.fns.isEmpty && s.graphPoints.isEmpty { return bad("graph needs fn, fns or points") }
            for k in ["x", "y"] {
                if let a = raw[k]?.array, a.count == 2, let lo = num(a[0]), let hi = num(a[1]), lo < hi {
                    if k == "x" { s.xRange = [r2(lo), r2(hi)] } else { s.yRange = [r2(lo), r2(hi)] }
                }
            }
            s.xLabel = str(raw["xLabel"], 40)
            s.yLabel = str(raw["yLabel"], 40)
            if let h = num(raw["h"]), h >= 40 { s.h = r2(min(h, 2000)) }
        case "chem":
            let kind = raw["kind"]?.string?.lowercased() ?? ""
            guard chemKinds.contains(kind) else { return bad("chem needs kind: " + chemKinds.joined(separator: ", ")) }
            s.kind = kind
            if kind == "cycle" {
                guard let c = str(raw["compound"], 20) else { return bad("chem cycle needs compound") }
                s.compound = c.trimmingCharacters(in: .whitespaces)
            } else if kind == "vsepr", let bp = num(raw["bp"]), let lp = num(raw["lp"]) {
                s.bp = Int(jsRound(bp)); s.lp = Int(jsRound(lp))
            } else {
                guard let m = str(raw["molecule"], 60) else { return bad("chem " + kind + " needs molecule" + (kind == "vsepr" ? " (or bp and lp)" : "")) }
                s.molecule = m.trimmingCharacters(in: .whitespaces)
            }
        case "arrow", "line":
            guard let from = pos(raw["from"]), let to = pos(raw["to"]) else { return bad(type + " needs from and to") }
            s.from = from; s.to = to
            if let b = num(raw["bend"]), b != 0 { s.bend = jsRound(max(-1, min(1, b)) * 100) / 100 }
            if type == "arrow" && raw["both"]?.bool == true { s.both = true }
            if type == "line" && raw["dash"]?.bool == true { s.dash = true }
        case "path":
            let pts = (raw["points"]?.array ?? []).prefix(400).compactMap { pt($0) }
            guard pts.count >= 2 else { return bad("path needs 2 or more points") }
            // a path that ends where it starts is a closed one (its first point repeated would make a knot in the curve)
            let shut = pts.count > 3 && pts[0] == pts[pts.count - 1]
            s.points = shut ? Array(pts.dropLast()) : pts
            if raw["closed"]?.bool == true || (shut && raw["closed"]?.bool != false) { s.closed = true }
            if let sm = raw["smooth"]?.bool { s.smooth = sm }
        case "angle":
            guard let at = pos(raw["at"]), let from = pos(raw["from"]), let to = pos(raw["to"]) else {
                return bad("angle needs at (the corner), from and to (a point along each side)")
            }
            s.vertex = at; s.from = from; s.to = to
            if raw["right"]?.bool == true { s.right = true }
        case "erase":
            guard let t = raw["target"]?.string, isId(t) else { return bad("erase needs target: an earlier step id") }
            s.target = .id(t)
        default: // the marks
            guard let t = target(raw["target"]) else { return bad(type + " needs target: an id, [x, y, w, h], [x, y] or {\"in\": id, \"part\"|\"at\": ...}") }
            s.target = t
        }
        if lineTypes.contains(type) || markTypes.contains(type) || type == "angle", let w = num(raw["width"]), w > 0 { s.width = r2(min(w, 24)) }
        // brief: a gesture while a sentence is said (gone when the next one starts), not ink left on the board; a point is one unless "brief": false
        if briefTypes.contains(type) && (raw["brief"]?.bool == true || (type == "point" && raw["brief"]?.bool != false)) { s.brief = true }
        return (s, nil)
    }

    public static func normalize(_ raw: JSONValue) -> TutorStep? { check(raw).step }

    // MARK: speech and steps

    /// A turn's events in order -> beats: each sentence with the steps drawn while it is said (say nil for steps before the first).
    public static func beats(_ events: [TutorEvent]) -> [(say: String?, steps: [TutorStep])] {
        var out: [(say: String?, steps: [TutorStep])] = []
        for e in events {
            switch e {
            case .say(let text, _): out.append((text, []))
            case .step(let s):
                if out.isEmpty { out.append((nil, [])) }
                out[out.count - 1].steps.append(s)
            }
        }
        return out
    }

    // MARK: geometry. Boxes are board rectangles; `lookup` answers what an id names (earlier steps, the board's own items).

    public static func center(_ b: TutorBox) -> [Double] { [b.x + b.w / 2, b.y + b.h / 2] }
    public static func sidePoint(_ b: TutorBox, _ side: String = "center") -> [Double] {
        let fx: Double = side.contains("left") ? 0 : side.contains("right") ? 1 : 0.5
        let fy: Double = side.contains("top") ? 0 : side.contains("bottom") ? 1 : 0.5
        return [b.x + b.w * fx, b.y + b.h * fy]
    }
    /// Where the line from the box's centre toward p leaves the box (plus a small gap), so an arrow stops at its edge.
    public static func edgeToward(_ b: TutorBox, _ p: [Double], gap: Double = 6) -> [Double] {
        let c = center(b), dx = p[0] - c[0], dy = p[1] - c[1]
        if dx == 0 && dy == 0 { return c }
        let hw = b.w / 2 + gap, hh = b.h / 2 + gap
        let k = min(dx != 0 ? hw / abs(dx) : .infinity, dy != 0 ? hh / abs(dy) : .infinity)
        return k >= 1 ? p : [c[0] + dx * k, c[1] + dy * k]
    }
    /// A place inside a block -> its box on the board: the words' box (`lookup.part`, the drawer's: it finds them in the drawn block;
    /// else the whole block), or the graph point's ([x, y, 0, 0], `lookup.graphAt`). nil when the block is unknown.
    public static func insideBox(_ p: TutorInside, _ lookup: TutorLookup) -> TutorBox? {
        guard let b = lookup.get(p.id) else { return nil }
        if let part = p.part { return lookup.part?(p.id, part) ?? b }
        if let at = p.at {
            guard let q = lookup.graphAt?(p.id, at) else { return nil }
            return TutorBox(q[0], q[1], 0, 0)
        }
        return b
    }
    /// A position -> a board point; nil when an id is unknown. `toward`: the other end, for a bare id (or the words inside a block).
    public static func resolve(_ p: TutorPos, _ lookup: TutorLookup, frame: [Double] = [0, 0], toward: [Double]? = nil) -> [Double]? {
        switch p {
        case .point(let x, let y): return [x + frame[0], y + frame[1]]
        case .inside(let i):
            guard let b = insideBox(i, lookup) else { return nil }
            if let toward, b.w != 0 || b.h != 0 { return edgeToward(b, toward, gap: 3) }
            return center(b)
        case .id(let id):
            guard let b = lookup.get(id) else { return nil }
            return toward.map { edgeToward(b, $0) } ?? center(b)
        case .of(let id, let side, let dx, let dy):
            guard let b = lookup.get(id) else { return nil }
            let q = sidePoint(b, side)
            return [q[0] + (dx ?? 0), q[1] + (dy ?? 0)]
        }
    }
    public static func resolve(_ p: TutorPos, _ lookup: (String) -> TutorBox?, frame: [Double] = [0, 0], toward: [Double]? = nil) -> [Double]? {
        resolve(p, TutorLookup(get: lookup), frame: frame, toward: toward)
    }
    /// An arrow's or a line's two ends: an id end (or the words inside a block) aims at the other end (its centre, or its point).
    public static func resolveEnds(_ s: TutorStep, _ lookup: TutorLookup, frame: [Double] = [0, 0]) -> ([Double], [Double])? {
        guard let from = s.from, let to = s.to else { return nil }
        func rough(_ p: TutorPos) -> [Double]? {
            if case .id(let id) = p { return lookup.get(id).map(center) }
            return resolve(p, lookup, frame: frame)
        }
        func aims(_ p: TutorPos) -> Bool {
            switch p {
            case .id: return true
            case .inside(let i): return i.at == nil
            default: return false
            }
        }
        guard let a0 = rough(from), let b0 = rough(to) else { return nil }
        let a = aims(from) ? resolve(from, lookup, frame: frame, toward: b0) : a0
        let b = aims(to) ? resolve(to, lookup, frame: frame, toward: a0) : b0
        guard let a, let b else { return nil }
        return (a, b)
    }
    public static func resolveEnds(_ s: TutorStep, _ lookup: (String) -> TutorBox?, frame: [Double] = [0, 0]) -> ([Double], [Double])? {
        resolveEnds(s, TutorLookup(get: lookup), frame: frame)
    }
    public static func resolveTarget(_ t: TutorTarget, _ lookup: TutorLookup, frame: [Double] = [0, 0]) -> TutorBox? {
        switch t {
        case .id(let id): return lookup.get(id)
        case .inside(let i): return insideBox(i, lookup)
        case .of(let id, let side, let dx, let dy):
            return resolve(.of(id, side: side, dx: dx, dy: dy), lookup, frame: frame).map { TutorBox($0[0], $0[1], 0, 0) }
        case .rect(let x, let y, let w, let h): return TutorBox(x + frame[0], y + frame[1], w, h)
        case .point(let x, let y): return TutorBox(x + frame[0], y + frame[1], 0, 0)
        }
    }
    public static func resolveTarget(_ t: TutorTarget, _ lookup: (String) -> TutorBox?, frame: [Double] = [0, 0]) -> TutorBox? {
        resolveTarget(t, TutorLookup(get: lookup), frame: frame)
    }
    /// A block's top-left. size: [w, h]; flow: where the next block goes when `at` is left out (the left edge and the bottom of the
    /// last block, frame included).
    public static func placeBlock(_ at: TutorPlace?, size: [Double], _ lookup: (String) -> TutorBox?, frame: [Double] = [0, 0], flow: [Double]? = nil) -> [Double] {
        switch at {
        // (a point far below everything drawn so far is a board-wide y meant for an earlier turn: no empty band before it)
        case .point(let x, let y)?: return [x + frame[0], flow.map { min(y + frame[1], $0[1] + 2 * gap) } ?? y + frame[1]]
        case .beside(let rel, let id, let g)?:
            if let b = lookup(id) {
                let gp = g ?? gap
                switch rel {
                case "below": return [b.x, b.y + b.h + gp]
                case "above": return [b.x, b.y - gp - size[1]]
                case "right": return [b.x + b.w + gp, b.y]
                default: return [b.x - gp - size[0], b.y]
                }
            }
        case nil: break
        }
        return flow ?? frame
    }
    /// A block's top-left moved down, as little as it takes, until its box overlaps none of `taken`, `margin` apart: Claude places blocks
    /// without seeing them, so two would otherwise land on each other (a graph under a diagram, a label over a picture).
    public static func freeSpot(_ at: [Double], size: [Double], taken: [TutorBox], margin: Double = 10) -> [Double] {
        let x = at[0], w = size[0], h = size[1]
        var y = at[1]
        for _ in 0..<400 {
            var low: Double?
            for b in taken where x < b.x + b.w + margin && x + w + margin > b.x && y < b.y + b.h + margin && y + h + margin > b.y {
                low = max(low ?? -.infinity, b.y + b.h + margin)
            }
            guard let low else { break }
            y = low
        }
        return [x, y]
    }
    /// Where the next block without "at" goes once `box` is drawn (placed by `at`): under it when it went below the one before, at a
    /// point (a new column starts there) or followed the flow itself, so a column goes on; after a block put beside or above another (a
    /// side note), the flow keeps its column and goes below the lowest of the two.
    public static func nextFlow(_ flow: [Double]?, at: TutorPlace?, box: TutorBox) -> [Double] {
        let bottom = box.y + box.h + gap
        switch at {
        case nil, .point?: return [box.x, bottom]
        case .beside(let rel, _, _)? where rel == "below": return [box.x, bottom]
        default: return [flow?[0] ?? box.x, max(flow?[1] ?? bottom, bottom)]
        }
    }
    /// A rough size before the block is drawn (the board measures the real one).
    public static func estimateSize(_ s: TutorStep) -> [Double] {
        switch s.type {
        case "text":
            let px = s.size ?? sizes["normal"]!, lines = (s.text ?? "").components(separatedBy: "\n")
            let longest = Double(lines.map { $0.utf16.count }.max() ?? 0)
            let w = s.w ?? min(560, max(40, longest * px * 0.55))
            let per = max(1, floor(w / (px * 0.55)))
            let rows = lines.reduce(0.0) { $0 + max(1, ceil(Double($1.utf16.count) / per)) }
            return [jsRound(w), jsRound(rows * px * 1.5)]
        case "math":
            let px = s.size ?? mathSize
            return [jsRound(s.w ?? min(640, max(40, Double((s.tex ?? "").utf16.count) * px * 0.45))), jsRound(px * 2.2)]
        case "graph": return [s.w ?? graphW, s.h ?? graphH]
        case "chem":
            let (w, r) = chemSize[s.kind ?? ""] ?? (220, 1)
            return [s.w ?? w, jsRound((s.w ?? w) * r)]
        default: return [0, 0]
        }
    }

    // MARK: what is already drawn, for a follow-up turn

    /// One line a step with an id; boxes as drawn (in the turn's frame), or none.
    public static func summarize(_ steps: [TutorStep], boxes: [String: TutorBox] = [:]) -> String {
        var out: [(String, String)] = []
        for s in steps {
            guard let id = s.id, s.type != "erase" else { continue }
            var what: String
            switch s.type {
            case "text": what = s.text ?? ""
            case "math": what = s.tex ?? ""
            case "graph": what = s.fns.isEmpty ? "points" : s.fns.map(\.fn).joined(separator: ", ")
            case "chem": what = (s.kind ?? "") + " " + (s.molecule ?? s.compound ?? "\(s.bp.map(String.init) ?? "undefined")/\(s.lp.map(String.init) ?? "undefined")")
            default: what = s.label ?? ""
            }
            let at = boxes[id].map { b in " at " + [b.x, b.y, b.w, b.h].map { String(Int(jsRound($0))) }.joined(separator: ",") } ?? ""
            let short = String(what.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).prefix(60))
            out.append((id, id + " " + s.type + (s.on == "screen" ? " (screen)" : "") + (what.isEmpty ? "" : " \"" + short + "\"") + at))
        }
        let gone = Set(steps.filter { $0.type == "erase" }.compactMap { s -> String? in if case .id(let t)? = s.target { return t }; return nil })
        return out.filter { !gone.contains($0.0) }.map(\.1).joined(separator: "\n")
    }

    // MARK: the format, as Claude is told it (the laptop's STEPS_PROMPT, word for word)

    public static let prompt = #"""
Drawing steps: each step is one JSON object. Draw while you talk: put each step right after the sentence it goes with.
Board coordinates are units (about 1 px), y down, relative to this turn's area: (0, 0) is its top-left; keep within about 800 wide.
Every step may have "id" (letters, digits, _ or -; give one to anything you will point at later), "color" (ink, grey, blue, red, green, purple, orange, yellow, or #RRGGBB) and "label" (a few words).
Blocks (have a size). "at" is the top-left [x, y], or {"below"|"above"|"right"|"left": "<id>"}; leave "at" out to go below the block before.
- {"type":"text","text":"markdown","size":"small|normal|large|huge","w":300}
- {"type":"math","tex":"\\Delta H = \\sum \\Delta H_f(\\text{products}) - \\sum \\Delta H_f(\\text{reactants})"}  (LaTeX, no $; chemical symbols upright: \\mathrm{Zn^{2+}})
- {"type":"graph","fns":[{"fn":"x^2-3","label":"y = x² − 3"}],"x":[-4,4],"y":[-4,10],"points":[[0,-3,"min"]],"xLabel":"x","yLabel":"y","w":320,"h":220}  (fn uses x, + - * / ^, sin cos tan exp ln log sqrt abs, pi, e)
- {"type":"chem","kind":"lewis","molecule":"H2O"}, {"type":"chem","kind":"vsepr","molecule":"NH3"} (or "bp":3,"lp":1), {"type":"chem","kind":"cycle","compound":"NaCl"}  (Nexus's own chemistry diagrams)
Ink. A position is [x, y], an id (the edge of that thing facing the other end), or {"of":"<id>","side":"top|bottom|left|right|center|topleft|...","dx":0,"dy":0}.
- {"type":"arrow","from":"eq1","to":"g1","bend":0.3,"label":"gives"}  (bend -1..1 curves it; "both":true for a double arrow)
- {"type":"line","from":[0,40],"to":[200,40],"dash":true}
- {"type":"path","points":[[0,0],[30,-20],[60,0]],"closed":false}  (a freehand curve through the points; a closed path has straight sides unless "smooth":true)
- {"type":"circle"|"box"|"underline"|"highlight"|"point","target":"eq1"}  (target: an id, [x, y, w, h] or [x, y])
- {"type":"angle","at":[60,200],"from":[0,200],"to":[60,120],"right":true,"label":"θ"}  (at the corner, from and to a point along each side: a small square when "right":true, else an arc)
Inside a block, as a target or a position: {"in":"eq1","part":"(x+3)"} (those symbols or words of a text or math block, as written in it) or {"in":"g1","at":[2,-1]} (a point of graph g1 in its own x, y numbers); "last" is the block drawn last.
Gestures: "brief":true on a mark, arrow, line or angle shows it only while its sentence is said (a teacher pointing), then it goes; a point is always brief. Keep ink (no brief) for what should stay in the notes.
- {"type":"point","target":{"in":"g1","at":[0,-3]}}  (a pointer to it while you say "this minimum")
- {"type":"erase","target":"eq1"}  (takes an earlier step's drawing away)
On the screen (the screenshot, in its pixels): {"type":"point"|"circle"|"underline"|"highlight","on":"screen","target":[x, y] or [x, y, w, h],"label":"..."}; when unsure of the exact spot, "area":"C2" (a cell of the grid drawn on the screenshot) instead of "target".
"""#

    /// The format as the iPad tells it: no screen overlay. Chemistry diagrams stay: the iPad draws them with the laptop's own study tools
    /// (the app's Sources/Render).
    public static var iPadPrompt: String {
        prompt.components(separatedBy: "\n").filter { !$0.hasPrefix("On the screen") }.joined(separator: "\n")
    }
}

/// A rectangle on the board.
public struct TutorBox: Equatable {
    public var x, y, w, h: Double
    public init(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public func union(_ o: TutorBox?) -> TutorBox {
        guard let o else { return self }
        let x0 = min(x, o.x), y0 = min(y, o.y)
        return TutorBox(x0, y0, max(maxX, o.maxX) - x0, max(maxY, o.maxY) - y0)
    }
}

/// A position: [x, y], an id (the edge of that thing facing the other end), or a side of a thing with an offset.
public enum TutorPos: Equatable {
    case point(Double, Double)
    case id(String)
    case of(String, side: String, dx: Double?, dy: Double?)
    case inside(TutorInside)
}

/// A place inside a block: some of its words or symbols (`part`, as written in it), a point of a graph (`at`, in the graph's own
/// numbers), or the whole block. The id "last" names the block drawn last.
public struct TutorInside: Equatable {
    public var id: String
    public var part: String?
    public var at: [Double]?
    public init(id: String, part: String? = nil, at: [Double]? = nil) { self.id = id; self.part = part; self.at = at }
}

/// What ids name, for the geometry: `get` a box (earlier steps, the board's own items); `part` the box of some words inside a drawn block
/// (nil when they can't be found: the whole block is used); `graphAt` a graph's own point as a board point.
public struct TutorLookup {
    public var get: (String) -> TutorBox?
    public var part: ((String, String) -> TutorBox?)?
    public var graphAt: ((String, [Double]) -> [Double]?)?
    public init(get: @escaping (String) -> TutorBox?, part: ((String, String) -> TutorBox?)? = nil, graphAt: ((String, [Double]) -> [Double]?)? = nil) {
        self.get = get; self.part = part; self.graphAt = graphAt
    }
}

/// What a mark goes around: an id, [x, y, w, h], [x, y], a side point of a block, or a place inside a block.
public enum TutorTarget: Equatable {
    case id(String)
    case rect(Double, Double, Double, Double)
    case point(Double, Double)
    case of(String, side: String, dx: Double?, dy: Double?)
    case inside(TutorInside)
}

/// Where a block goes: its top-left, or beside (below, above, right, left) another thing.
public enum TutorPlace: Equatable {
    case point(Double, Double)
    case beside(String, String, gap: Double?)
}

public struct TutorFn: Equatable {
    public var fn: String
    public var color: String?
    public var label: String?
}

public struct TutorGraphPoint: Equatable {
    public var x: Double
    public var y: Double
    public var label: String?
}

/// One clean step (TutorSteps.check). Only the fields its type uses are set.
public struct TutorStep: Equatable {
    public var type: String
    public var id: String?
    public var color: String?
    public var label: String?
    public var on: String?
    public var shot: String?
    public var area: String?
    public var at: TutorPlace?
    public var w: Double?
    public var h: Double?
    public var text: String?
    public var size: Double?
    public var tex: String?
    public var fns: [TutorFn] = []
    public var graphPoints: [TutorGraphPoint] = []
    public var xRange: [Double]?
    public var yRange: [Double]?
    public var xLabel: String?
    public var yLabel: String?
    public var kind: String?
    public var compound: String?
    public var molecule: String?
    public var bp: Int?
    public var lp: Int?
    public var from: TutorPos?
    public var to: TutorPos?
    public var bend: Double?
    public var both = false
    public var dash = false
    public var points: [[Double]] = []
    public var closed = false
    /// A path's: nil (the default: a curve, but a closed path has straight sides), true or false as Claude wrote it.
    public var smooth: Bool?
    public var target: TutorTarget?
    public var width: Double?
    /// An angle's corner (its `at`), and whether it is a right angle.
    public var vertex: TutorPos?
    public var right = false
    /// A gesture: shown while its sentence is said, then gone (a point is one unless it says not).
    public var brief = false

    public init(type: String) { self.type = type }
}

/// What a reply streams out, in order: a sentence to say (numbered from 0) or a step to draw.
public enum TutorEvent: Equatable {
    case say(String, n: Int)
    case step(TutorStep)
}
