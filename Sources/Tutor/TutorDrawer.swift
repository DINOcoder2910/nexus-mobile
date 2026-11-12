import UIKit
import PencilKit
import NexusCore

/// The tutor drawing on a board, as the laptop's app/tutorboard.js does: each step Claude writes becomes ordinary board content (ink
/// strokes, text blocks, a graph's ink and labels), drawn like a pen while the sentence it goes with is said, so it saves, syncs and
/// opens on the laptop like anything else. Ink is animated on a layer above the board (the pen's tip showing where it writes) and then
/// becomes PencilKit ink. Gestures (brief marks and the pointer) are drawn on a layer above the board that is never saved: they show
/// while their sentence is said and go when the next one starts (`spoken`).
@MainActor
final class TutorDrawer {
    unowned let board: BoardController
    /// This session's steps, and what each id names on the board (board units).
    private(set) var steps: [TutorStep] = []
    private(set) var boxes: [String: TutorBox] = [:]
    /// What each step drew: the fingerprints of its strokes and its item ids (for erase).
    private var drawn: [String: (strokes: [String], items: [String])] = [:]
    /// The turn's (0, 0) on the board, and where the next block goes.
    private(set) var frame: [Double] = [0, 0]
    private var flow: [Double]?
    private(set) var drewAll: TutorBox?
    /// What "last" and a place inside a block find: a graph's geometry, a text block's item, a block without an id, the last block.
    private var graphs: [String: TutorDraw.GraphGeom] = [:]
    private var blockItems: [String: String] = [:]
    private var anon: [String: TutorBox] = [:]
    private var lastBlock: String?
    /// Frames round blocks (no block lands on them); ink drawn and labels placed (the next label goes where it covers least); how many
    /// angles each corner has (a second one is a wider arc).
    private var marks: [TutorBox] = []
    private var inkPts: [[Double]] = []
    private var labels: [TutorBox] = []
    private var corners: [String: Int] = [:]
    /// 1 = as written; higher is faster (a stopped turn finishes at once).
    var pace: Double = 1
    var problems: [String] = []
    private let inkLayer = CALayer()
    /// The gestures' layer, the gestures shown while the sentence now being said goes on, and the sentence.
    private let gestureLayer = CALayer()
    private var brief: [Gesture] = []
    private var beat = -1
    private var pointer: CALayer?
    private var pointerGen = 0
    private var pen: CALayer?

    /// A gesture's colour (the pointer, a brief mark): a teacher's laser, clear on the light board and the dark one.
    static let gestureColor = "#F76707"
    /// A chemistry picture cropped to its drawing is never narrower than this: its letters stay readable.
    static let chemMin: [String: Double] = ["lewis": 260, "vsepr": 200, "cycle": 600]

    private final class Gesture {
        let layer: CALayer
        let at: CFTimeInterval
        let pointer: Bool
        let gen: Int
        init(_ layer: CALayer, pointer: Bool = false, gen: Int = 0) { self.layer = layer; at = CACurrentMediaTime(); self.pointer = pointer; self.gen = gen }
    }

    private struct Drawn {
        var box: TutorBox?
        var strokes: [String] = []
        var items: [String] = []
        var geom: TutorDraw.GraphGeom?
        /// A graph drawn into another: that graph's key.
        var into: String?
    }

    init(board: BoardController) {
        self.board = board
    }

    /// A new turn at this frame: the last turn's gestures go.
    func turn(at f: [Double]) {
        frame = f
        flow = f
        pace = 1
        clearBrief(force: true)
    }

    // MARK: what ids name

    /// What an id names: this session's steps, then the board's own items ("last": the block drawn last).
    func lookup(_ id0: String) -> TutorBox? {
        var id: String? = id0
        if id0 == "last" && boxes["last"] == nil { id = lastBlock }
        guard let id else { return nil }
        if let b = boxes[id] { return b }
        if let b = anon[id] { return b }
        if let it = board.content.items.first(where: { $0.id == id }) { let r = board.box(of: it); return TutorBox(r.minX, r.minY, r.width, r.height) }
        return nil
    }

    /// The lookup with places inside a block: words of a drawn text or maths block, a point of a graph.
    private var places: TutorLookup {
        TutorLookup(get: { [unowned self] in self.lookup($0) },
                    part: { [unowned self] id, text in
                        let key = id == "last" ? self.lastBlock : id
                        let iid = key.flatMap { k in self.blockItems[k] ?? (self.board.content.items.contains { $0.id == k } ? k : nil) }
                        let r = iid.flatMap { self.partBox($0, text) }
                        if r == nil { self.problems.append("\"" + text + "\" is not in " + (key ?? "null")) }
                        return r
                    },
                    graphAt: { [unowned self] id, p in
                        let key = id == "last" ? self.lastBlock : id
                        return key.flatMap { self.graphs[$0] }.map { TutorDraw.graphPoint($0, p) }
                    })
    }

    /// What is already drawn, in the current turn's frame.
    func summary() -> String {
        var rel: [String: TutorBox] = [:]
        for (id, b) in boxes { rel[id] = TutorBox(b.x - frame[0], b.y - frame[1], b.w, b.h) }
        return TutorSteps.summarize(steps, boxes: rel)
    }

    // MARK: the sentences

    /// The voice has started sentence n: the gestures made while the one before was said go.
    func spoken(_ n: Int) {
        guard n != beat else { return }
        beat = n
        clearBrief()
    }

    /// The turn is over: its last gestures stay a moment, then go.
    func ended() {
        guard pace < 50 else { return }
        let n = beat
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.beat == n else { return }
            self.clearBrief()
        }
    }

    // MARK: one step

    func draw(_ s: TutorStep) async {
        guard s.on != "screen", !board.readOnly else { return }
        steps.append(s)
        var res: Drawn?
        switch s.type {
        case "text", "math": res = await textBlock(s)
        case "graph": res = await graph(s)
        case "chem": res = await chem(s)
        case "erase": erase(s); return
        default:
            if s.brief { res = await gesture(s) } else { res = await inkStep(s) }
        }
        guard let res, let box = res.box else { return }
        if let id = s.id, !s.brief { boxes[id] = box; drawn[id] = (res.strokes, res.items) }
        if TutorSteps.blockTypes.contains(s.type) && res.into == nil {
            flow = TutorSteps.nextFlow(flow, at: s.at, box: box)
            // (what "last" and a place inside a block find; a side note is not "last": the column's line before it is)
            let key = s.id ?? "#\(steps.count)"
            if s.id == nil { anon[key] = box }
            if case .beside(let rel, _, _)? = s.at, rel == "right" || rel == "left" {} else { lastBlock = key }
            if s.type == "text" || s.type == "math", let first = res.items.first { blockItems[key] = first }
            if let g = res.geom { graphs[key] = g }
        }
        if let into = res.into, let g = res.geom { graphs[into] = g }
        if (s.type == "box" || s.type == "circle") && !s.brief { marks.append(box) } // (a frame round a block: no block lands on it)
        if s.brief { return }
        drewAll = box.union(drewAll)
        show(box)
    }

    private func miss(_ s: TutorStep) { problems.append(s.type + ": an id it names is not on the board") }

    /// How much a label at box b would cover: ink points (this session's and `own`) under it, blocks and labels it overlaps.
    private func crowd(_ b: TutorBox, own: [[Double]] = []) -> Double {
        func inside(_ p: [Double]) -> Bool { p[0] > b.x - 2 && p[0] < b.x + b.w + 2 && p[1] > b.y - 2 && p[1] < b.y + b.h + 2 }
        var n = 0.0
        for p in inkPts where inside(p) { n += 2 }
        for p in own where inside(p) { n += 2 }
        for o in Array(boxes.values) + Array(anon.values) + labels where b.x < o.x + o.w && b.x + b.w > o.x && b.y < o.y + o.h && b.y + b.h > o.y { n += 30 }
        return n
    }

    /// Ink drawn and labels placed, remembered for the next label's place.
    private func remember(_ lines: [TutorDraw.Line], labels placed: [TutorBox] = []) {
        for l in lines {
            let pts = TutorDraw.densify(l.points, step: 6)
            for i in stride(from: 0, to: pts.count, by: 2) { inkPts.append(pts[i]) }
        }
        if inkPts.count > 20000 { inkPts.removeFirst(inkPts.count - 20000) }
        labels += placed
    }

    /// Where a block goes: as Claude asked (placeBlock), then moved down clear of anything already on the board.
    private func place(_ at: TutorPlace?, size: [Double]) -> [Double] {
        var taken: [TutorBox] = []
        for it in board.content.items where !BoardLinks.isLink(it) && it.type != "pdf" {
            let r = board.box(of: it); taken.append(TutorBox(r.minX, r.minY, r.width, r.height))
        }
        // a PDF: its pages (the whole printout is one tall box)
        for p in board.pdfs.values { for f in p.frames { taken.append(TutorBox(f.minX, f.minY, f.width, f.height)) } }
        // and graphs, whose ink is no item, and frames round blocks; other ink is not in the way (a label put on a drawn triangle or
        // circle is meant to be there)
        for k in graphs.keys { if let b = boxes[k] ?? anon[k] { taken.append(b) } }
        taken += marks
        // (a point far below: no lower than just under the ink)
        let low = flow != nil ? drewAll?.maxY : nil
        return TutorSteps.freeSpot(TutorSteps.placeBlock(at, size: size, lookup, frame: frame, flow: flow, low: low), size: size, taken: taken)
    }

    /// A label: where it goes by its anchor; a line's shaft or the box a mark marks, when it may go where it covers least instead.
    private struct Label { var text: String; var at: [Double]; var anchor: String; var shaft: [[Double]]? = nil; var around: TutorBox? = nil }
    private struct Shape { var lines: [TutorDraw.Line]; var label: Label?; var width: Double; var target: TutorBox? }

    /// What a line, a mark or an angle step draws (board points), or nil when it names nothing drawn.
    private func shape(_ s: TutorStep) -> Shape? {
        let L = places, width = s.width ?? TutorDraw.inkWidth
        // (a frame round a coloured block takes its colour)
        var own: String?
        if s.color == nil, s.type == "box" || s.type == "circle", case .id(let t)? = s.target { own = steps.first { $0.id == t }?.color }
        let color = s.color ?? own ?? (s.type == "highlight" ? TutorDraw.highlight : "#1B1B1B")
        var lines: [TutorDraw.Line] = []
        var label: Label?
        var target: TutorBox?
        var same: (TutorInside, TutorInside)?
        if case .inside(let a)? = s.from, case .inside(let b)? = s.to, a.part != nil, b.part != nil, a.id == b.id { same = (a, b) }
        if s.type == "arrow" || s.type == "line", let pair = same {
            // from one part of a line to another part of it: over the top, not through its words
            guard let a = TutorSteps.resolveTarget(.inside(pair.0), L, frame: frame), let b = TutorSteps.resolveTarget(.inside(pair.1), L, frame: frame) else { return nil }
            let p = [a.x + a.w / 2, a.y - 3], q = [b.x + b.w / 2, b.y - 3]
            let parts = TutorDraw.arrowLines(p, q, bend: q[0] >= p[0] ? -0.7 : 0.7, both: s.both, width: width, head: s.type == "arrow")
            lines.append(TutorDraw.Line(points: parts[0], color: color, width: width))
            for hd in parts.dropFirst() { lines.append(TutorDraw.Line(points: hd, color: color, width: width, corners: true)) }
            if let l = s.label { label = Label(text: l, at: [(p[0] + q[0]) / 2, (parts[0].map { $0[1] }.min() ?? p[1]) - 13], anchor: "center") }
        } else if s.type == "arrow" || s.type == "line" {
            // between two blocks of one column: round their right side (a straight one would be a stub, or would cross the blocks between)
            var A: TutorBox?, B: TutorBox?
            if case .id(let a)? = s.from { A = lookup(a) }
            if case .id(let b)? = s.to { B = lookup(b) }
            var col: TutorDraw.ColumnArrow?
            if let A, let B, s.bend == nil {
                col = TutorDraw.columnArrow(A, B, others: (Array(boxes.values) + Array(anon.values)).filter { $0 != A && $0 != B && $0.w > 0 })
            }
            guard var ends = col.map({ ($0.from, $0.to) }) ?? TutorSteps.resolveEnds(s, L, frame: frame) else { return nil }
            if s.type == "arrow" && col == nil { ends.0 = TutorDraw.longEnough(ends.0, ends.1) } // (two blocks next to each other: a stub of an arrow)
            let parts = TutorDraw.arrowLines(ends.0, ends.1, bend: s.bend ?? 0, both: s.both, width: width, head: s.type == "arrow", outX: col?.outX)
            let shaft = parts[0]
            if s.dash { lines = TutorDraw.dashes(TutorDraw.densify(shaft, step: 2)).map { TutorDraw.Line(points: $0, color: color, width: width) } }
            else { lines.append(TutorDraw.Line(points: shaft, color: color, width: width)) }
            for hd in parts.dropFirst() { lines.append(TutorDraw.Line(points: hd, color: color, width: width, corners: true)) }
            if let l = s.label {
                label = col != nil ? Label(text: l, at: [shaft.map { $0[0] }.max()! + 6, (ends.0[1] + ends.1[1]) / 2], anchor: "leftmid")
                    : Label(text: l, at: TutorDraw.labelAt(shaft), anchor: "center", shaft: shaft)
            }
        } else if s.type == "path" {
            let pts = s.points.map { [$0[0] + frame[0], $0[1] + frame[1]] }
            let straight = s.smooth == false || (s.closed && s.smooth != true) // (a closed shape is a polygon unless asked to be smooth)
            lines.append(TutorDraw.Line(points: straight ? (s.closed ? pts + [pts[0]] : pts) : TutorDraw.smooth(pts, closed: s.closed), color: color, width: width, corners: straight))
        } else if s.type == "angle" {
            guard let v = s.vertex, let at = TutorSteps.resolve(v, L, frame: frame) else { return nil }
            guard let f = s.from, let t = s.to, let from = TutorSteps.resolve(f, L, frame: frame, toward: at), let to = TutorSteps.resolve(t, L, frame: frame, toward: at) else { return nil }
            // (a second angle at the same corner: a wider arc)
            let key = "\(Int(TutorSteps.jsRound(at[0] / 4))),\(Int(TutorSteps.jsRound(at[1] / 4)))", n = corners[key] ?? 0
            if !s.brief { corners[key] = n + 1 }
            let g = TutorDraw.angleLines(at, from, to, right: s.right, more: Double(n * 10))
            lines = g.lines.map { TutorDraw.Line(points: $0, color: color, width: s.width ?? 2, corners: s.right) }
            if let l = s.label { label = Label(text: l, at: g.label, anchor: "center") }
        } else if s.type == "circle", let r = s.r { // (a true circle in a diagram)
            guard let v = s.vertex, let c = TutorSteps.resolve(v, L, frame: frame) else { return nil }
            let pts = (0...96).map { i -> [Double] in let t = 2 * Double.pi * Double(i) / 96; return [c[0] + r * cos(t), c[1] + r * sin(t)] }
            lines.append(TutorDraw.Line(points: pts, color: color, width: width, corners: true))
            if let l = s.label { label = Label(text: l, at: [c[0], c[1] + r + 14], anchor: "center") }
        } else {
            guard let tg = s.target, let t = TutorSteps.resolveTarget(tg, L, frame: frame) else { return nil }
            if s.type == "highlight" && t.h > 40 { // (a tall block: a marker frame round it, not a stripe through its middle)
                lines = TutorDraw.markLines("box", t, pad: 6).map { TutorDraw.Line(points: $0, color: color, width: 8, ink: TutorDraw.marker, corners: true) }
            } else {
                let ls = TutorDraw.markLines(s.type, t)
                if s.type == "highlight" {
                    lines = ls.map { TutorDraw.Line(points: $0, color: color, width: max(10, min(34, t.h + 4)), ink: TutorDraw.marker) } // (a line's height)
                } else {
                    lines = ls.enumerated().map { i, p in TutorDraw.Line(points: p, color: color, width: width, corners: s.type == "box" || (s.type == "point" && i > 0)) }
                }
            }
            if let l = s.label { label = Label(text: l, at: [t.x + t.w / 2, t.y + t.h + 14], anchor: "center", around: t) }
            target = t
        }
        return Shape(lines: lines, label: label, width: width, target: target)
    }

    private func inkStep(_ s: TutorStep) async -> Drawn? {
        guard let sh = shape(s) else { miss(s); return nil }
        var box: TutorBox?
        for l in sh.lines { for p in l.points { box = TutorBox(p[0], p[1], 0, 0).union(box) } }
        var items: [String] = [], labelBoxes: [TutorBox] = []
        if let label = sh.label {
            let m = await measureLabel(label.text, color: s.color, size: 13)
            var b = TutorDrawer.anchored(label.at, label.anchor, m.w, m.h)
            // where it covers least: a line's beside it on either side (the upper first) or past its tip; a mark's under, over or beside
            // what it marks; scored against the ink drawn (and this step's own), the blocks and the labels already placed
            let w = m.w, hh = m.h
            var cands: [(Double, Double, Double)] = []
            if let shaft = label.shaft {
                for side in [1.0, -1.0] { let at = TutorDraw.labelAt(shaft, off: 6, size: [w, hh], side: side); cands.append((at[0] - w / 2, at[1] - hh / 2, side < 0 ? 1 : 0)) }
                let tip = shaft[shaft.count - 1], prev = shaft[max(0, shaft.count - 3)]
                let d0 = hypot(tip[0] - prev[0], tip[1] - prev[1]), d = d0 == 0 ? 1 : d0
                cands.append((tip[0] + (tip[0] - prev[0]) / d * (8 + w / 2) - w / 2, tip[1] + (tip[1] - prev[1]) / d * (8 + hh / 2) - hh / 2, 3))
            } else if let t = label.around {
                let cx = t.x + t.w / 2, cy = t.y + t.h / 2
                cands += [(cx - w / 2, t.y + t.h + 8, 0), (cx - w / 2, t.y - hh - 8, 1), (t.x + t.w + 10, cy - hh / 2, 2), (t.x - w - 10, cy - hh / 2, 2)]
            }
            if !cands.isEmpty {
                let own = sh.lines.flatMap(\.points)
                var best: (Double, Double, Double)?
                for (x, y, extra) in cands {
                    let score = extra + crowd(TutorBox(x, y, w, hh), own: own)
                    if best == nil || score < best!.2 { best = (x, y, score) }
                }
                if let best { b = TutorBox(TutorSteps.jsRound(best.0), TutorSteps.jsRound(best.1), w, hh) }
            }
            items.append(addLabel(m, box: b))
            box = b.union(box)
            labelBoxes.append(b)
        }
        let strokes = await ink(sh.lines)
        remember(sh.lines, labels: labelBoxes)
        for id in items { await reveal(id, seconds: 0.25) }
        let pad = s.type == "highlight" ? 0 : sh.width / 2
        return Drawn(box: box.map { TutorBox($0.x - pad, $0.y - pad, $0.w + 2 * pad, $0.h + 2 * pad) }, strokes: strokes, items: items)
    }

    private func textBlock(_ s: TutorStep) async -> Drawn? {
        let id = BoardFormat.newId(taken: board.allIds)
        // ("e^x" in a sentence as maths)
        let md = s.type == "math" ? "$$" + (s.tex ?? "") + "$$" : TutorDraw.mathRuns(s.text ?? "")
        var fields: [(String, JSONValue)] = []
        let size = s.size ?? (s.type == "math" ? TutorSteps.mathSize : nil)
        if let size, size != TutorSteps.sizes["normal"] { fields.append(("size", .number(size))) }
        if let c = s.color { fields.append(("color", .string(c))) }
        if let w = s.w { fields.append(("w", .number(w))) }
        else if s.type == "text", (s.size ?? 0) <= TutorSteps.sizes["normal"]!, case .beside(let rel, _, _)? = s.at, rel == "right" || rel == "left",
                TutorSteps.estimateSize(s)[0] > TutorSteps.sideNoteW {
            fields.append(("w", .number(TutorSteps.sideNoteW))) // (a note put beside something wraps instead of running into the next column)
        }
        var it = BoardItem(id: id, type: "text", x: 0, y: 0, fields: fields)
        let measured = await measure(md, it)
        let dim = measured.width > 0 ? [Double(measured.width), Double(measured.height)] : TutorSteps.estimateSize(s)
        let p = place(s.at, size: dim)
        let x = TutorSteps.jsRound(p[0]), y = TutorSteps.jsRound(p[1])
        it = it.with("x", .number(x)).with("y", .number(y))
        board.changeItems("Tutor") { c in c.items.append(it); c.texts[id] = md }
        let b = TutorBox(x, y, dim[0], dim[1])
        show(b)
        let chars = Double(s.type == "math" ? (s.tex ?? "").count : (s.text ?? "").count)
        await reveal(id, seconds: (s.type == "math" ? min(1.6, max(0.5, 0.5 + chars * 0.012)) : min(2.5, max(0.35, chars * 0.022))) / pace, tip: b)
        let r = board.box(of: board.content.items.first { $0.id == id } ?? it)
        return Drawn(box: TutorBox(r.minX, r.minY, r.width, r.height), items: [id])
    }

    private func graph(_ s: TutorStep) async -> Drawn? {
        // more curves on a graph already drawn: in its axes, coloured on from its curves
        let key = s.into.flatMap { $0 == "last" ? lastBlock : $0 }
        var into: (geom: TutorDraw.GraphGeom, box: TutorBox)?
        if let key, let g = graphs[key], let b = boxes[key] ?? anon[key] { into = (g, b) }
        if let k = s.into, into == nil { problems.append("graph: " + k + " is not a graph on the board; drawn as a new one") }
        let box: TutorBox
        if let into { box = into.box } else {
            let dim = TutorSteps.estimateSize(s), p = place(s.at, size: dim)
            box = TutorBox(TutorSteps.jsRound(p[0]), TutorSteps.jsRound(p[1]), dim[0], dim[1])
        }
        let plan = TutorDraw.graphPlan(s, box: box, into: into?.geom)
        if let e = plan.error { problems.append("graph: " + e) }
        show(box)
        var items: [String] = [], placed: [TutorBox] = []
        for l in plan.labels {
            let m = await measureLabel(l.text, color: l.color, size: l.size)
            let b = TutorDrawer.anchored([l.x, l.y], l.anchor, m.w, m.h)
            items.append(addLabel(m, box: b)); placed.append(b)
        }
        let strokes = await ink(plan.lines)
        remember(plan.lines, labels: placed)
        for id in items { await reveal(id, seconds: 0.15) }
        return Drawn(box: box, strokes: strokes, items: items, geom: plan.geom, into: into != nil ? key : nil)
    }

    /// Nexus's chemistry diagrams, drawn by the laptop's own study tools (Sources/Render) and kept as a PNG in the board's files/, as the
    /// laptop does (tutorboard.js _chem). When there is no diagram for it, the formula is written instead.
    private func chem(_ s: TutorStep) async -> Drawn? {
        switch await ChemRender.picture(kind: s.kind ?? "", molecule: s.molecule, compound: s.compound, bp: s.bp, lp: s.lp) {
        case .success(let pic):
            // its width: as asked, else the scale the diagram has at its usual size (chemSize is the whole drawing area's width)
            let usual = TutorSteps.chemSize[s.kind ?? ""]?.0 ?? 220
            let w = s.w ?? max(TutorDrawer.chemMin[s.kind ?? ""] ?? 0, TutorSteps.jsRound(usual * pic.w / (pic.full > 0 ? pic.full : pic.w)))
            let hh = TutorSteps.jsRound(w * pic.h / pic.w)
            let p = place(s.at, size: [w, hh])
            let id = BoardFormat.newId(taken: board.allIds), rel = "files/tutor-" + id + ".png"
            do { try FolderAccess.writeData(board.boardURL.appendingPathComponent(rel), pic.png) } catch {
                problems.append("chem: " + error.localizedDescription)
                return await chemAsText(s)
            }
            let it = BoardItem(id: id, type: "image", x: TutorSteps.jsRound(p[0]), y: TutorSteps.jsRound(p[1]), fields: [("src", .string(rel)), ("w", .number(w)), ("h", .number(hh))])
            board.changeItems("Tutor") { c in c.items.append(it) }
            let b = TutorBox(it.x, it.y, w, hh)
            show(b)
            await reveal(id, seconds: 1.1 / pace)
            return Drawn(box: b, items: [id])
        case .failure(let e):
            problems.append("chem: " + e.message)
            return await chemAsText(s)
        }
    }

    /// The formula (with its subscripts) and what the diagram would have been.
    private func chemAsText(_ s: TutorStep) async -> Drawn? {
        let sub: [Character: Character] = ["0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉"]
        let what = s.molecule ?? s.compound ?? "\(s.bp ?? 0) bonding, \(s.lp ?? 0) lone pairs"
        let formula = String(what.map { sub[$0] ?? $0 })
        let name = s.kind == "lewis" ? "Lewis structure" : s.kind == "vsepr" ? "shape (VSEPR)" : "Born–Haber cycle"
        var t = TutorStep(type: "text")
        t.id = s.id; t.at = s.at; t.color = s.color; t.size = TutorSteps.sizes["large"]
        t.text = "**\(formula)**: \(name)"
        return await textBlock(t)
    }

    private func erase(_ s: TutorStep) {
        guard case .id(let target)? = s.target, let d = drawn[target] else { miss(s); return }
        let gone = Set(d.strokes)
        if !gone.isEmpty {
            let kept = board.canvas.drawing.strokes.filter { !gone.contains(InkConvert.fingerprint(InkConvert.boardStroke($0, offset: board.offset, id: ""))) }
            board.canvas.drawing = PKDrawing(strokes: kept)
        }
        if !d.items.isEmpty {
            let ids = Set(d.items)
            board.changeItems("Tutor") { c in c.items.removeAll { ids.contains($0.id) }; for id in ids { c.texts[id] = nil } }
        }
        drawn[target] = nil; boxes[target] = nil
    }

    // MARK: ink, written like a pen

    /// Lines -> board strokes written one after another on the animation layer (the pen's tip on its end), then put on the canvas as
    /// PencilKit ink. Returns the strokes' fingerprints.
    private func ink(_ lines: [TutorDraw.Line]) async -> [String] {
        let lines = lines.filter { $0.points.count >= 2 }
        let strokes = lines.map { TutorDraw.inkStroke($0, alpha: $0.ink == TutorDraw.marker ? 0.5 : nil) }
        guard !strokes.isEmpty else { return [] }
        if pace < 50 {
            let o = board.offset
            if inkLayer.superlayer == nil { board.world.layer.addSublayer(inkLayer) }
            for (st, l) in zip(strokes, lines) {
                let pts = st.points.map { CGPoint(x: $0[0] + o.x, y: $0[1] + o.y) }
                let path = TutorDrawer.smoothPath(pts, corners: l.corners).cgPath
                let shape = CAShapeLayer()
                shape.path = path
                shape.fillColor = nil
                shape.strokeColor = InkConvert.color(st.color).cgColor
                // the same width as the PencilKit ink that takes its place, so nothing jumps when it does
                shape.lineWidth = CGFloat(l.width)
                shape.lineCap = l.ink == TutorDraw.marker ? .butt : .round
                shape.lineJoin = .round
                shape.strokeEnd = 0
                inkLayer.addSublayer(shape)
                let secs = max(0.08, TutorDraw.strokeTime(st)) / pace
                // a hand speeds up into a line and slows at its end
                let timing = CAMediaTimingFunction(controlPoints: 0.35, 0.05, 0.4, 1)
                let a = CABasicAnimation(keyPath: "strokeEnd")
                a.fromValue = 0; a.toValue = 1; a.duration = secs
                a.timingFunction = timing
                shape.strokeEnd = 1
                shape.add(a, forKey: "write")
                penAlong(path, end: pts.last ?? .zero, seconds: secs, timing: timing)
                // a short lift of the pen between strokes
                try? await Task.sleep(nanoseconds: UInt64((secs + min(0.12, 0.05 + secs * 0.15) / pace) * 1_000_000_000))
            }
            penUp()
        }
        // the real ink, all at once (one change to the drawing)
        var pks = board.canvas.drawing.strokes
        var prints: [String] = []
        for st in strokes {
            for k in InkConvert.pkStrokes(st, offset: board.offset) {
                pks.append(k)
                prints.append(InkConvert.fingerprint(InkConvert.boardStroke(k, offset: board.offset, id: "")))
            }
        }
        board.canvas.drawing = PKDrawing(strokes: pks)
        // the animation's lines go once the canvas has drawn the ink under them (no flicker)
        let drawnLayers = inkLayer.sublayers ?? []
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { drawnLayers.forEach { $0.removeFromSuperlayer() } }
        return prints
    }

    /// A smooth curve through the points (Catmull-Rom as cubic Béziers); straight segments where the line has corners (boxes, arrow heads).
    static func smoothPath(_ p: [CGPoint], corners: Bool) -> UIBezierPath {
        let path = UIBezierPath()
        guard let first = p.first else { return path }
        path.move(to: first)
        if corners || p.count < 3 {
            for q in p.dropFirst() { path.addLine(to: q) }
            return path
        }
        for i in 0..<(p.count - 1) {
            let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.count - 1, i + 2)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, controlPoint1: c1, controlPoint2: c2)
        }
        return path
    }

    // MARK: text

    struct Measured { var md: String; var fields: [(String, JSONValue)]; var w: Double; var h: Double }

    /// A block's size as the board draws it, once its formulas' pictures are ready (measured before, a formula is its TeX's width).
    private func measure(_ md: String, _ it: BoardItem) async -> CGSize {
        let first = TextBlockRender.size(md, item: it)
        guard md.contains("$") else { return first }
        try? await Task.sleep(nanoseconds: 30_000_000) // (the pictures asked for start being drawn)
        let start = Date()
        while MathRender.shared.busy && Date().timeIntervalSince(start) < 3 { try? await Task.sleep(nanoseconds: 50_000_000) }
        return TextBlockRender.size(md, item: it)
    }

    /// A small label (a line's, a mark's, a graph's): a label written as maths ("y = e^x") is drawn as maths.
    private func measureLabel(_ text: String, color: String?, size: Double) async -> Measured {
        var fields: [(String, JSONValue)] = [("size", .number(size))]
        if let color { fields.append(("color", .string(color))) }
        let md = TutorDraw.isMathLabel(text) ? "$" + text.replacingOccurrences(of: "$", with: "") + "$"
            : text.replacingOccurrences(of: #"([\\`*_\[\]#<>$|])"#, with: #"\\$1"#, options: .regularExpression)
        let sz = await measure(md, BoardItem(id: "", type: "text", x: 0, y: 0, fields: fields))
        let w = sz.width > 0 ? Double(sz.width) : Double(text.count) * size * 0.55, h = sz.height > 0 ? Double(sz.height) : size * 1.5
        return Measured(md: md, fields: fields, w: w, h: h)
    }

    /// Where a label of this size goes by its anchor: x by left / center / right; y its top, or its middle for center and leftmid.
    static func anchored(_ at: [Double], _ anchor: String, _ w: Double, _ h: Double) -> TutorBox {
        let x = anchor == "right" ? at[0] - w : anchor == "center" ? at[0] - w / 2 : at[0]
        let y = anchor == "center" || anchor == "leftmid" ? at[1] - h / 2 : at[1]
        return TutorBox(TutorSteps.jsRound(x), TutorSteps.jsRound(y), w, h)
    }

    /// The label put on the board at its box (hidden until revealed). -> its id.
    private func addLabel(_ m: Measured, box: TutorBox) -> String {
        let id = BoardFormat.newId(taken: board.allIds)
        let it = BoardItem(id: id, type: "text", x: box.x, y: box.y, fields: m.fields)
        board.changeItems("Tutor") { c in c.items.append(it); c.texts[id] = m.md }
        hide(id)
        return id
    }

    private func hide(_ id: String) { board.itemViews[id]?.alpha = 0 }

    /// A block faded in from the left, as if written (the pen's tip across it when `tip` is its box).
    private func reveal(_ id: String, seconds: Double, tip: TutorBox? = nil) async {
        guard let v = board.itemViews[id] else { return }
        if pace >= 50 || seconds < 0.02 { v.alpha = 1; v.layer.mask = nil; return }
        let mask = CAGradientLayer()
        mask.frame = v.bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5); mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        mask.locations = [0, 0, 0.05]
        v.layer.mask = mask
        v.alpha = 1
        let a = CABasicAnimation(keyPath: "locations")
        a.fromValue = [0, 0, 0.05]; a.toValue = [0, 1, 1]; a.duration = seconds
        mask.locations = [0, 1, 1]
        mask.add(a, forKey: "write")
        if let b = tip {
            let line = UIBezierPath()
            line.move(to: worldPoint([b.x, b.y + b.h / 2])); line.addLine(to: worldPoint([b.x + b.w, b.y + b.h / 2]))
            penAlong(line.cgPath, end: worldPoint([b.x + b.w, b.y + b.h / 2]), seconds: seconds, timing: CAMediaTimingFunction(name: .linear))
        }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if tip != nil { penUp() }
        v.layer.mask = nil
    }

    /// Everything drawn so far shown at once (a stopped turn); its gestures go.
    func finishNow() {
        pace = 100
        for v in board.itemViews.values where v.alpha == 0 { v.alpha = 1 }
        inkLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        clearBrief(force: true)
    }

    // MARK: following the drawing

    /// Keeps what was just drawn in view: pans when it is out of sight.
    func show(_ b: TutorBox) {
        let v = board.visibleBoard
        if b.x >= v.minX, b.y >= v.minY, b.maxX <= v.maxX, b.maxY <= v.maxY { return }
        let W = v.width, H = v.height
        let nx = b.w + 96 > W ? b.x - 48 : b.maxX > v.maxX ? b.maxX + 48 - W : b.x < v.minX ? b.x - 48 : v.minX
        let ny = b.h + 96 > H ? b.y - 48 : b.maxY > v.maxY ? b.maxY + 48 - H : b.y < v.minY ? b.y - 48 : v.minY
        board.glide(toBoard: CGPoint(x: nx, y: ny))
    }
}

// MARK: - gestures: the pointer, brief marks and the pen's tip, over the board and never saved

extension TutorDrawer {
    /// The layer the gestures are drawn on: above the ink and the blocks, in the board's world (board point + offset).
    private var gestures: CALayer {
        if gestureLayer.superlayer !== board.overWorld.layer {
            gestureLayer.zPosition = 1000
            board.overWorld.layer.addSublayer(gestureLayer)
        }
        return gestureLayer
    }

    private func worldPoint(_ p: [Double]) -> CGPoint { CGPoint(x: p[0] + board.offset.x, y: p[1] + board.offset.y) }

    private var still: Bool { UIAccessibility.isReduceMotionEnabled }

    /// A brief step: drawn on over the board while its sentence is said, gone when the next starts. A point is the pointer.
    private func gesture(_ s: TutorStep) async -> Drawn? {
        guard let sh = shape(s) else { miss(s); return nil }
        let color = s.color ?? TutorDrawer.gestureColor
        if s.type == "point", let t = sh.target { return await pointTo(t, color: color, label: s.label) }
        let g = CALayer()
        gestures.addSublayer(g)
        var box: TutorBox?
        var total = 0.0
        let now = CACurrentMediaTime()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for l in sh.lines {
            let pts = l.corners || l.points.count < 3 ? l.points : TutorDraw.smooth(l.points, closed: false, per: 4)
            let path = UIBezierPath()
            path.move(to: worldPoint(pts[0]))
            for q in pts.dropFirst() { path.addLine(to: worldPoint(q)) }
            let p = CAShapeLayer()
            p.path = path.cgPath
            p.fillColor = nil
            let marker = l.ink == TutorDraw.marker
            p.strokeColor = InkConvert.color(marker ? (s.color ?? TutorDraw.highlight) : color).cgColor
            p.lineWidth = CGFloat(l.width)
            p.lineCap = .round
            p.lineJoin = .round
            if marker { p.opacity = 0.42 }
            let dur = max(0.12, TutorDraw.length(pts) / TutorDraw.speed) / pace
            if pace < 50 && !still {
                let a = CABasicAnimation(keyPath: "strokeEnd")
                a.fromValue = 0; a.toValue = 1; a.duration = dur
                a.beginTime = now + total
                a.fillMode = .backwards
                a.timingFunction = CAMediaTimingFunction(name: .linear)
                p.add(a, forKey: "draw")
            }
            total += dur
            g.addSublayer(p)
            for q in pts { box = TutorBox(q[0], q[1], 0, 0).union(box) }
        }
        if let label = sh.label { g.addSublayer(gestureText(label.text, at: label.at, start: label.anchor == "leftmid", color: color)) }
        CATransaction.commit()
        brief.append(Gesture(g))
        if pace < 50 { try? await Task.sleep(nanoseconds: UInt64(min(total + 0.06, 2) * 1_000_000_000)) }
        return Drawn(box: box)
    }

    /// The pointer: a dot that glides to what is being talked about and rings it; one per session (in a fast drawing, one per point).
    private func pointTo(_ t: TutorBox, color: String, label: String?) async -> Drawn {
        let p = t.w != 0 || t.h != 0 ? [t.x + t.w / 2, t.y + t.h + 6] : [t.x, t.y] // (under a block's middle, on a point itself)
        let ui = InkConvert.color(color)
        var P = pace < 50 ? pointer : nil
        if P == nil || P?.superlayer == nil {
            let made = CALayer()
            made.name = "pointer"
            func circle(_ r: CGFloat) -> CAShapeLayer {
                let c = CAShapeLayer()
                c.path = UIBezierPath(ovalIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)).cgPath
                return c
            }
            let halo = circle(15); halo.fillColor = ui.withAlphaComponent(0.2).cgColor
            let ring = circle(9); ring.fillColor = nil; ring.strokeColor = ui.cgColor; ring.lineWidth = 2; ring.opacity = 0; ring.name = "ring"
            let dot = circle(5.5); dot.fillColor = ui.cgColor
            for c in [halo, ring, dot] { made.addSublayer(c) }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            made.position = worldPoint([p[0], p[1] + 30])
            made.opacity = 0
            gestures.addSublayer(made)
            CATransaction.commit()
            P = made
            if pace < 50 { pointer = made }
        }
        guard let P else { return Drawn(box: TutorBox(p[0] - 15, p[1] - 15, 30, 30)) }
        pointerGen += 1
        let to = worldPoint(p)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if pace < 50 && !still {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(cgPoint: P.presentation()?.position ?? P.position)
            move.toValue = NSValue(cgPoint: to)
            move.duration = 0.45 / pace
            move.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.7, 0.3, 1)
            P.add(move, forKey: "glide")
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = P.presentation()?.opacity ?? P.opacity; appear.toValue = 1; appear.duration = 0.2 / pace
            P.add(appear, forKey: "show")
        }
        P.position = to
        P.opacity = 1
        // the ring: a ping round it, twice
        if !still, let ring = P.sublayers?.first(where: { $0.name == "ring" }) {
            let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 6.0 / 9; grow.toValue = 24.0 / 9
            let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 0.9; fade.toValue = 0
            let ping = CAAnimationGroup(); ping.animations = [grow, fade]; ping.duration = 0.8; ping.repeatCount = 2
            ping.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(ping, forKey: "ping")
        }
        CATransaction.commit()
        if t.w != 0 || t.h != 0 { // (a block or a part of one: a soft glow over it too)
            let r = CAShapeLayer()
            r.path = UIBezierPath(roundedRect: CGRect(x: t.x - 4 + board.offset.x, y: t.y - 3 + board.offset.y, width: t.w + 8, height: t.h + 6), cornerRadius: 6).cgPath
            r.fillColor = ui.cgColor
            r.opacity = 0.14
            if !still {
                let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = 0; a.toValue = 0.14; a.duration = 0.25
                r.add(a, forKey: "in")
            }
            gestures.insertSublayer(r, at: 0)
            brief.append(Gesture(r))
        }
        if let label {
            let l = gestureText(label, at: [p[0] + 12, p[1] + 13], start: true, color: color)
            gestures.addSublayer(l)
            brief.append(Gesture(l))
        }
        brief.removeAll { $0.layer === P }
        brief.append(Gesture(P, pointer: true, gen: pointerGen))
        if pace < 50 { try? await Task.sleep(nanoseconds: 450_000_000) }
        return Drawn(box: TutorBox(p[0] - 15, p[1] - 15, 30, 30))
    }

    /// A gesture's words: 13 pt semibold in its colour, with a halo of the board's colour so they read over ink.
    private func gestureText(_ s: String, at p: [Double], start: Bool, color: String) -> CATextLayer {
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let size = (s as NSString).size(withAttributes: [.font: font])
        let t = CATextLayer()
        t.string = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: InkConvert.color(color)])
        t.contentsScale = max(2, board.view.window?.screen.scale ?? 2) * 2
        let at = worldPoint(p)
        t.frame = CGRect(x: start ? at.x : at.x - size.width / 2, y: at.y - size.height / 2, width: ceil(size.width) + 1, height: ceil(size.height))
        t.shadowColor = UIColor.systemBackground.resolvedColor(with: board.traitCollection).cgColor
        t.shadowOpacity = 1
        t.shadowRadius = 1.5
        t.shadowOffset = .zero
        return t
    }

    /// The gestures go, each shown at least a moment; force: at once (a new turn, a stopped one).
    private func clearBrief(force: Bool = false) {
        if !force && pace >= 50 { return }
        let now = CACurrentMediaTime()
        for g in brief {
            let left = force ? 0 : max(0, 0.9 - (now - g.at))
            if force { g.layer.removeFromSuperlayer(); continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + left) { [weak self] in
                guard let self else { return }
                if g.pointer && g.gen != self.pointerGen { return } // (pointed somewhere else since: it stays)
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.3)
                g.layer.opacity = 0
                CATransaction.commit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in
                    guard let self else { return }
                    if g.pointer && g.gen != self.pointerGen { return }
                    g.layer.removeFromSuperlayer()
                    if g.pointer && self.pointer === g.layer { self.pointer = nil }
                }
            }
        }
        brief = []
        if force {
            pointer = nil
            pointerGen += 1
            gestureLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            pen = nil
        }
    }

    // MARK: the pen's tip

    /// The pen's tip, seen while the tutor writes (a drawing that appears with no hand teaches no better than a finished one): it moves
    /// along `path` (world points) in step with the ink and stays at its end.
    private func penAlong(_ path: CGPath, end: CGPoint, seconds: Double, timing: CAMediaTimingFunction) {
        guard pace < 50 else { return }
        let dot: CALayer
        if let pen, pen.superlayer != nil { dot = pen } else {
            let c = CAShapeLayer()
            c.path = UIBezierPath(ovalIn: CGRect(x: -4, y: -4, width: 8, height: 8)).cgPath
            c.fillColor = InkConvert.color(TutorDrawer.gestureColor).cgColor
            c.opacity = 0
            gestures.addSublayer(c)
            pen = c
            dot = c
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let a = CAKeyframeAnimation(keyPath: "position")
        a.path = path
        a.calculationMode = .paced
        a.duration = seconds
        a.timingFunction = timing
        dot.add(a, forKey: "write")
        dot.position = end
        dot.opacity = 1
        CATransaction.commit()
    }

    /// The pen lifted.
    private func penUp() {
        guard let pen else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        pen.opacity = 0
        CATransaction.commit()
    }

    // MARK: words inside a drawn block

    /// Characters made alike: minus signs, ×, a product's dots, a prime.
    private static func norm(_ c: String) -> String {
        c == "−" || c == "–" ? "-" : c == "×" ? "*" : c == "⋅" || c == "·" || c == "∙" ? "." : c == "′" ? "'" : c
    }
    /// TeX's symbol names read as the symbols drawn (\pm as ±), as the laptop's tutorboard.js has them.
    private static let texSymbols: [String: String] = [
        "pm": "±", "mp": "∓", "times": "×", "cdot": "⋅", "div": "÷", "to": "→", "rightarrow": "→", "Rightarrow": "⇒", "leftarrow": "←",
        "rightleftharpoons": "⇌", "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "approx": "≈", "infty": "∞",
        "degree": "°", "circ": "∘", "partial": "∂", "int": "∫", "sum": "∑",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "Delta": "Δ", "theta": "θ", "lambda": "λ", "mu": "μ", "pi": "π", "rho": "ρ",
        "sigma": "σ", "omega": "ω", "Omega": "Ω", "phi": "φ"]
    private static let texName = try! NSRegularExpression(pattern: #"\\([a-zA-Z]+)"#)
    private static let braceGroup = try! NSRegularExpression(pattern: #"\{([^{}]*)\}"#)
    private static let stackCmd = try! NSRegularExpression(pattern: #"\\(d?frac|tfrac|sqrt|binom)\s*(\{[^{}]*\}\s*)*"#)
    /// What a formula's TeX has that is never drawn as characters: colours, environments' names.
    private static let unseen = try! NSRegularExpression(pattern: #"\\(textcolor|color|begin|end)\s*\{[^{}]*\}"#)

    /// TeX's characters as drawn: symbol names as their symbols; other commands, braces, $, ^, _, & and spaces left out.
    private static func texChars(_ t: String) -> [String] {
        let ns = t as NSString
        var named = "", last = 0
        for m in texName.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            named += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            named += texSymbols[ns.substring(with: m.range(at: 1))] ?? ""
            last = m.range.location + m.range.length
        }
        named += ns.substring(from: last)
        return named.replacingOccurrences(of: #"[{}$\s^_&]"#, with: "", options: .regularExpression).map { norm(String($0)) }
    }
    /// The pieces to find: the whole part, or for \frac{a}{b} / \sqrt{x} the pieces between the braces, then the rest run by run (their
    /// boxes are joined).
    private static func pieces(_ tex: String) -> [[String]] {
        guard tex.range(of: #"\\(d?frac|tfrac|sqrt|binom)\b"#, options: .regularExpression) != nil else { return [texChars(tex)].filter { !$0.isEmpty } }
        let ns = tex as NSString, all = NSRange(location: 0, length: ns.length)
        var out: [[String]] = []
        for m in braceGroup.matches(in: tex, range: all) { out.append(texChars(ns.substring(with: m.range(at: 1)))) }
        for r in stackCmd.stringByReplacingMatches(in: tex, range: all, withTemplate: "\u{1}").components(separatedBy: "\u{1}") { out.append(texChars(r)) }
        return out.filter { !$0.isEmpty }
    }
    private static func find(_ want: [String], in hay: [String]) -> Int? {
        guard !want.isEmpty, hay.count >= want.count else { return nil }
        for i in 0...(hay.count - want.count) where Array(hay[i..<(i + want.count)]) == want { return i }
        return nil
    }
    /// Whether `hay` has every character of `want` (as many times), in any order.
    private static func holds(_ hay: [String], _ want: [String]) -> Bool {
        var n: [String: Int] = [:]
        for c in hay { n[c, default: 0] += 1 }
        for c in want { guard let k = n[c], k > 0 else { return false }; n[c] = k - 1 }
        return true
    }
    /// TeX laid out in two dimensions (a fraction, a root, a sum's limits): its characters are not in a row.
    private static let stacked = ["\\frac", "\\dfrac", "\\tfrac", "\\over", "\\sqrt", "\\begin", "\\sum", "\\int", "\\prod", "\\lim", "\\binom",
                                  "\\stackrel", "\\overset", "\\underset", "\\\\"]

    /// Some words of a drawn text or maths block ("(x+3)", "2x", "\pm", a word) -> their box on the board, or nil when they are not in
    /// it. The block's visible words are searched with spaces ignored, TeX's symbol names read as the symbols drawn and minus signs, ×
    /// and · made alike; a fraction's or a root's pieces are found one by one and their boxes joined (TextKit's glyphs). Maths is a
    /// picture, so there the box is a best estimate: the pieces found in a formula's TeX give where they come in it when the formula is
    /// one row, else the formula's picture; a formula that has the part's characters, though not in a row, gives its picture. Nothing
    /// only when the part's characters can't be in the block at all.
    private func partBox(_ iid: String, _ text: String) -> TutorBox? {
        guard let v = board.itemViews[iid] as? TextBlockView, let tl = v.layout?.text,
              let it = board.content.items.first(where: { $0.id == iid }) else { return nil }
        let want = TutorDrawer.pieces(text)
        guard !want.isEmpty else { return nil }
        let origin = board.box(of: it).origin, storage = tl.storage, ns = storage.string as NSString
        func onBoard(_ r: CGRect) -> TutorBox {
            TutorBox(r.minX + tl.padding.x + origin.x, r.minY + tl.padding.y + origin.y, r.width, r.height)
        }
        // the words as shown (marks hidden, formulas left out)
        var hay: [String] = [], at: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byComposedCharacterSequences) { sub, range, _, _ in
            guard let sub, !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sub != "\u{200B}" else { return }
            if storage.attribute(BlockStyler.hiddenKey, at: range.location, effectiveRange: nil) != nil { return }
            if storage.attribute(BlockStyler.mathKey, at: range.location, effectiveRange: nil) != nil { return }
            hay.append(TutorDrawer.norm(sub)); at.append(range)
        }
        var r = CGRect.null, all = true
        for w in want {
            guard let i = TutorDrawer.find(w, in: hay) else { all = false; break }
            for k in i..<(i + w.count) { let q = tl.rect(of: at[k]); if !q.isNull { r = r.union(q) } }
        }
        if all && !r.isNull { return onBoard(r) }
        // in a formula's TeX
        var found: TutorBox?, loose: TutorBox?
        storage.enumerateAttribute(BlockStyler.mathKey, in: NSRange(location: 0, length: storage.length), options: []) { value, range, stop in
            guard let box = value as? BlockStyler.MathBox, let pic = tl.manager.mathRect(box, at: range.location) else { return }
            let rest = ns.substring(from: range.location)
            let open = rest.hasPrefix("$$") ? "$$" : rest.hasPrefix("$") ? "$" : ""
            guard !open.isEmpty else { return }
            let body = String(rest.dropFirst(open.count))
            let tex0 = body.range(of: open).map { String(body[..<$0.lowerBound]) } ?? body
            let tex = TutorDrawer.unseen.stringByReplacingMatches(in: tex0, range: NSRange(location: 0, length: (tex0 as NSString).length), withTemplate: "")
            let src = TutorDrawer.texChars(tex)
            var spans: [(Int, Int)] = []
            for w in want { guard let i = TutorDrawer.find(w, in: src) else { break }; spans.append((i, w.count)) }
            if spans.count == want.count {
                var q = pic
                if !TutorDrawer.stacked.contains(where: { tex.contains($0) }), !src.isEmpty {
                    let n = CGFloat(src.count), lo = CGFloat(spans.map(\.0).min()!), hi = CGFloat(spans.map { $0.0 + $0.1 }.max()!)
                    q = CGRect(x: pic.minX + pic.width * lo / n, y: pic.minY, width: pic.width * (hi - lo) / n, height: pic.height)
                }
                found = onBoard(q)
                stop.pointee = true
            } else if loose == nil && TutorDrawer.holds(src, want.flatMap { $0 }) {
                loose = onBoard(pic)
            }
        }
        return found ?? loose
    }
}

extension BoardController {
    /// Scrolls smoothly so this board point is at the top-left of the screen.
    func glide(toBoard p: CGPoint) {
        growIfNeeded()
        updateContentSize()
        let z = canvas.zoomScale
        let target = CGPoint(x: max(0, (p.x + offset.x) * z), y: max(0, (p.y + offset.y) * z))
        UIView.animate(withDuration: 0.36, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.canvas.contentOffset = target
        } completion: { _ in self.syncWorld() }
    }
}
