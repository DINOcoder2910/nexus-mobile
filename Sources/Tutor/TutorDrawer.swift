import UIKit
import PencilKit
import NexusCore

/// The tutor drawing on a board, as the laptop's app/tutorboard.js does: each step Claude writes becomes ordinary board content (ink
/// strokes, text blocks, a graph's ink and labels), drawn like a pen while the sentence it goes with is said, so it saves, syncs and
/// opens on the laptop like anything else. Ink is animated on a layer above the board and then becomes PencilKit ink.
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
    /// 1 = as written; higher is faster (a stopped turn finishes at once).
    var pace: Double = 1
    var problems: [String] = []
    private let inkLayer = CALayer()

    init(board: BoardController) {
        self.board = board
    }

    /// A new turn at this frame.
    func turn(at f: [Double]) {
        frame = f
        flow = f
    }

    /// What an id names: this session's steps, then the board's own items.
    func lookup(_ id: String) -> TutorBox? {
        if let b = boxes[id] { return b }
        if let it = board.content.items.first(where: { $0.id == id }) { let r = board.box(of: it); return TutorBox(r.minX, r.minY, r.width, r.height) }
        return nil
    }

    /// What is already drawn, in the current turn's frame.
    func summary() -> String {
        var rel: [String: TutorBox] = [:]
        for (id, b) in boxes { rel[id] = TutorBox(b.x - frame[0], b.y - frame[1], b.w, b.h) }
        return TutorSteps.summarize(steps, boxes: rel)
    }

    // MARK: one step

    func draw(_ s: TutorStep) async {
        guard s.on != "screen", !board.readOnly else { return }
        steps.append(s)
        var res: (box: TutorBox?, strokes: [String], items: [String])?
        switch s.type {
        case "text", "math": res = await textBlock(s)
        case "graph": res = await graph(s)
        case "chem": res = await chem(s)
        case "erase": erase(s); return
        default: res = await inkStep(s)
        }
        guard let res, let box = res.box else { return }
        if let id = s.id { boxes[id] = box; drawn[id] = (res.strokes, res.items) }
        if TutorSteps.blockTypes.contains(s.type) { flow = [flow?[0] ?? box.x, box.y + box.h + TutorSteps.gap] }
        drewAll = box.union(drewAll)
        show(box)
    }

    private func miss(_ s: TutorStep) { problems.append(s.type + ": an id it names is not on the board") }

    private func inkStep(_ s: TutorStep) async -> (box: TutorBox?, strokes: [String], items: [String])? {
        let color = s.color ?? (s.type == "highlight" ? TutorDraw.highlight : "#1B1B1B"), width = s.width ?? TutorDraw.inkWidth
        var lines: [TutorDraw.Line] = []
        var label: (text: String, at: [Double])?
        if s.type == "arrow" || s.type == "line" {
            guard let ends = TutorSteps.resolveEnds(s, lookup, frame: frame) else { miss(s); return nil }
            let parts = TutorDraw.arrowLines(ends.0, ends.1, bend: s.bend ?? 0, both: s.both, width: width, head: s.type == "arrow")
            let shaft = parts[0]
            if s.dash { lines = TutorDraw.dashes(TutorDraw.densify(shaft, step: 2)).map { TutorDraw.Line(points: $0, color: color, width: width) } }
            else { lines.append(TutorDraw.Line(points: shaft, color: color, width: width)) }
            for hd in parts.dropFirst() { lines.append(TutorDraw.Line(points: hd, color: color, width: width, corners: true)) }
            if let l = s.label { label = (l, TutorDraw.labelAt(shaft)) }
        } else if s.type == "path" {
            let pts = s.points.map { [$0[0] + frame[0], $0[1] + frame[1]] }
            lines.append(TutorDraw.Line(points: s.smooth != false ? TutorDraw.smooth(pts, closed: s.closed) : (s.closed ? pts + [pts[0]] : pts), color: color, width: width, corners: s.smooth == false))
        } else {
            guard let tg = s.target, let t = TutorSteps.resolveTarget(tg, lookup, frame: frame) else { miss(s); return nil }
            let ls = TutorDraw.markLines(s.type, t)
            if s.type == "highlight" {
                lines = ls.map { TutorDraw.Line(points: $0, color: color, width: max(10, min(34, t.h + 4)), ink: TutorDraw.marker) }
            } else {
                lines = ls.enumerated().map { i, p in TutorDraw.Line(points: p, color: color, width: width, corners: s.type == "box" || (s.type == "point" && i > 0)) }
            }
            if let l = s.label { label = (l, [t.x + t.w / 2, t.y + t.h + 14]) }
        }
        var box: TutorBox?
        for l in lines { for p in l.points { box = TutorBox(p[0], p[1], 0, 0).union(box) } }
        var items: [String] = []
        if let label {
            let (id, b) = addLabel(label.text, at: label.at, anchor: "center", color: s.color, size: 13)
            items.append(id); box = b.union(box)
        }
        let strokes = await ink(lines, highlight: s.type == "highlight")
        for id in items { await reveal(id, seconds: 0.25) }
        let pad = s.type == "highlight" ? 0 : width / 2
        return (box.map { TutorBox($0.x - pad, $0.y - pad, $0.w + 2 * pad, $0.h + 2 * pad) }, strokes, items)
    }

    private func textBlock(_ s: TutorStep) async -> (box: TutorBox?, strokes: [String], items: [String])? {
        let id = BoardFormat.newId(taken: board.allIds)
        let md = s.type == "math" ? "$$" + (s.tex ?? "") + "$$" : (s.text ?? "")
        var fields: [(String, JSONValue)] = []
        let size = s.size ?? (s.type == "math" ? TutorSteps.mathSize : nil)
        if let size, size != TutorSteps.sizes["normal"] { fields.append(("size", .number(size))) }
        if let c = s.color { fields.append(("color", .string(c))) }
        if let w = s.w { fields.append(("w", .number(w))) }
        var it = BoardItem(id: id, type: "text", x: 0, y: 0, fields: fields)
        let measured = TextBlockRender.size(md, item: it)
        let dim = measured.width > 0 ? [Double(measured.width), Double(measured.height)] : TutorSteps.estimateSize(s)
        let p = TutorSteps.placeBlock(s.at, size: dim, lookup, frame: frame, flow: flow)
        it = it.with("x", .number(p[0].rounded())).with("y", .number(p[1].rounded()))
        board.changeItems("Tutor") { c in c.items.append(it); c.texts[id] = md }
        let b = TutorBox(p[0].rounded(), p[1].rounded(), dim[0], dim[1])
        show(b)
        let chars = Double(s.type == "math" ? (s.tex ?? "").count : (s.text ?? "").count)
        await reveal(id, seconds: (s.type == "math" ? min(1.6, max(0.5, 0.5 + chars * 0.012)) : min(2.5, max(0.35, chars * 0.022))) / pace)
        let r = board.box(of: board.content.items.first { $0.id == id } ?? it)
        return (TutorBox(r.minX, r.minY, r.width, r.height), [], [id])
    }

    private func graph(_ s: TutorStep) async -> (box: TutorBox?, strokes: [String], items: [String])? {
        let dim = TutorSteps.estimateSize(s), p = TutorSteps.placeBlock(s.at, size: dim, lookup, frame: frame, flow: flow)
        let box = TutorBox(p[0].rounded(), p[1].rounded(), dim[0], dim[1])
        let plan = TutorDraw.graphPlan(s, box: box)
        if let e = plan.error { problems.append("graph: " + e) }
        show(box)
        var items: [String] = []
        for l in plan.labels { items.append(addLabel(l.text, at: [l.x, l.y], anchor: l.anchor, color: l.color, size: l.size).id) }
        for id in items { hide(id) }
        let strokes = await ink(plan.lines)
        for id in items { await reveal(id, seconds: 0.15) }
        return (box, strokes, items)
    }

    /// Nexus's chemistry diagrams, drawn by the laptop's own study tools (Sources/Render) and kept as a PNG in the board's files/, as the
    /// laptop does (tutorboard.js _chem). When there is no diagram for it, the formula is written instead.
    private func chem(_ s: TutorStep) async -> (box: TutorBox?, strokes: [String], items: [String])? {
        switch await ChemRender.picture(kind: s.kind ?? "", molecule: s.molecule, compound: s.compound, bp: s.bp, lp: s.lp) {
        case .success(let pic):
            let w = s.w ?? TutorSteps.chemSize[s.kind ?? ""]?.0 ?? 220, hh = (w * pic.h / pic.w).rounded()
            let p = TutorSteps.placeBlock(s.at, size: [w, hh], lookup, frame: frame, flow: flow)
            let id = BoardFormat.newId(taken: board.allIds), rel = "files/tutor-" + id + ".png"
            do { try FolderAccess.writeData(board.boardURL.appendingPathComponent(rel), pic.png) } catch {
                problems.append("chem: " + error.localizedDescription)
                return await chemAsText(s)
            }
            let it = BoardItem(id: id, type: "image", x: p[0].rounded(), y: p[1].rounded(), fields: [("src", .string(rel)), ("w", .number(w)), ("h", .number(hh))])
            board.changeItems("Tutor") { c in c.items.append(it) }
            let b = TutorBox(it.x, it.y, w, hh)
            show(b)
            await reveal(id, seconds: 1.1 / pace)
            return (b, [], [id])
        case .failure(let e):
            problems.append("chem: " + e.message)
            return await chemAsText(s)
        }
    }

    /// The formula (with its subscripts) and what the diagram would have been.
    private func chemAsText(_ s: TutorStep) async -> (box: TutorBox?, strokes: [String], items: [String])? {
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

    /// Lines -> board strokes written one after another on the animation layer, then put on the canvas as PencilKit ink.
    /// Returns the strokes' fingerprints.
    private func ink(_ lines: [TutorDraw.Line], highlight: Bool = false) async -> [String] {
        let strokes = lines.filter { $0.points.count >= 2 }.map { TutorDraw.inkStroke($0, alpha: $0.ink == TutorDraw.marker ? 0.5 : nil) }
        guard !strokes.isEmpty else { return [] }
        if pace < 50 {
            let o = board.offset
            if inkLayer.superlayer == nil { board.world.layer.addSublayer(inkLayer) }
            for (st, l) in zip(strokes, lines.filter { $0.points.count >= 2 }) {
                let pts = st.points.map { CGPoint(x: $0[0] + o.x, y: $0[1] + o.y) }
                let shape = CAShapeLayer()
                shape.path = TutorDrawer.smoothPath(pts, corners: l.corners).cgPath
                shape.fillColor = nil
                shape.strokeColor = InkConvert.color(st.color).cgColor
                // the same width as the PencilKit ink that takes its place, so nothing jumps when it does
                shape.lineWidth = CGFloat(l.width)
                shape.lineCap = l.ink == TutorDraw.marker ? .butt : .round
                shape.lineJoin = .round
                shape.strokeEnd = 0
                inkLayer.addSublayer(shape)
                let secs = max(0.08, TutorDraw.strokeTime(st)) / pace
                let a = CABasicAnimation(keyPath: "strokeEnd")
                a.fromValue = 0; a.toValue = 1; a.duration = secs
                // a hand speeds up into a line and slows at its end
                a.timingFunction = CAMediaTimingFunction(controlPoints: 0.35, 0.05, 0.4, 1)
                shape.strokeEnd = 1
                shape.add(a, forKey: "write")
                // a short lift of the pen between strokes
                try? await Task.sleep(nanoseconds: UInt64((secs + min(0.12, 0.05 + secs * 0.15) / pace) * 1_000_000_000))
            }
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

    /// A small label (a line's, a mark's, a graph's), placed by its anchor. -> its id and box.
    @discardableResult
    private func addLabel(_ text: String, at: [Double], anchor: String, color: String?, size: Double) -> (id: String, box: TutorBox) {
        let id = BoardFormat.newId(taken: board.allIds)
        var fields: [(String, JSONValue)] = [("size", .number(size))]
        if let color { fields.append(("color", .string(color))) }
        let md = text.replacingOccurrences(of: #"([\\`*_\[\]#<>$|])"#, with: #"\\$1"#, options: .regularExpression)
        var it = BoardItem(id: id, type: "text", x: 0, y: 0, fields: fields)
        let sz = TextBlockRender.size(md, item: it)
        let w = Double(sz.width), h = Double(sz.height)
        let x = anchor == "right" ? at[0] - w : anchor == "center" ? at[0] - w / 2 : at[0]
        let y = anchor == "center" ? at[1] - h / 2 : at[1]
        it = it.with("x", .number(x.rounded())).with("y", .number(y.rounded()))
        board.changeItems("Tutor") { c in c.items.append(it); c.texts[id] = md }
        hide(id)
        return (id, TutorBox(x.rounded(), y.rounded(), w, h))
    }

    private func hide(_ id: String) { board.itemViews[id]?.alpha = 0 }

    /// A block faded in from the left, as if written.
    private func reveal(_ id: String, seconds: Double) async {
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
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        v.layer.mask = nil
    }

    /// Everything drawn so far shown at once (a stopped turn).
    func finishNow() {
        pace = 100
        for v in board.itemViews.values where v.alpha == 0 { v.alpha = 1 }
        inkLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
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
