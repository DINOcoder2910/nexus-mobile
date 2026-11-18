import UIKit
import PencilKit
import NexusCore

/// Insert space following the drag, as in OneNote: while you drag, everything that will move is shown moving with you (the ink, typed
/// text, pictures, shapes, comments, tape, and a PDF page opening at the line), and letting go does exactly what was shown.
///
/// Built to stay smooth on a full board (thousands of strokes): nothing in the board's files or its canvas changes while you drag.
/// When the drag starts, the canvas's own strokes that move (only those near the screen) are handed to a second, see-through canvas
/// laid over the board's, and the board's canvas hides that region with a mask (strokes that stay but reach into it go on a third,
/// still canvas). Each move after that only slides the moving canvas and the item views, which costs the same on any board. On
/// letting go the board moves for real in one step (one undo step, as before), and the moving canvas stays up until the board's
/// canvas has drawn the result, so nothing flickers.
final class SpaceLive: NSObject, PKCanvasViewDelegate {
    /// One way the drag can go (adding room, or taking it away): the plan, and what is shown moving for it.
    struct Side {
        let plan: BoardController.SpacePlan
        /// Canvas strokes (indices into `strokes`) that move, and those that stay but reach into the hidden region.
        let moving: [Int], still: [Int]
        /// Items that move as a whole (ids).
        let items: [String]
        /// Where the board's canvas hides its own copy of the moving ink (canvas units).
        let hidden: CGRect

        func sameInk(_ o: Side) -> Bool { moving == o.moving && still == o.still && hidden == o.hidden }
    }

    /// The line where the drag started (board units, snapped), which way it goes, and the column (or row) when only that moves.
    let line: CGFloat
    let sideways: Bool
    let band: ClosedRange<CGFloat>?
    /// The canvas's strokes when the drag started, and which stroke of the files each one is.
    let strokes: [PKStroke]
    let ids: [String]
    /// Made the first time the drag goes that way.
    var add: Side?, take: Side?
    /// The side whose ink is on the overlay canvases.
    var shown: Side?
    /// The room shown now (board units; negative takes it away), and the drag's length before what can be done was worked out.
    var by: CGFloat = 0
    var raw: CGFloat = 0
    let movingInk = PKCanvasView(), stillInk = PKCanvasView()
    let mask = CAShapeLayer()
    /// Item views moved, and where they were; PDF printouts shown changed, and as they were.
    var centers: [String: CGPoint] = [:]
    var pdfWas: [String: BoardItem] = [:]
    /// What the items show now: (side's line and plan kind, amount), so a move that changes nothing costs nothing.
    var itemsShown: (adding: Bool, by: CGFloat)?
    /// Overlay canvases still drawing their strokes; the board's canvas is masked once they have.
    var pending = 0
    var masked = false
    /// Let go: waiting for the board's canvas to draw the result before the overlays go.
    var letGo = false
    weak var board: BoardController?

    init(line: CGFloat, sideways: Bool, band: ClosedRange<CGFloat>?, strokes: [PKStroke], ids: [String]) {
        self.line = line
        self.sideways = sideways
        self.band = band
        self.strokes = strokes
        self.ids = ids
        super.init()
        for c in [movingInk, stillInk] {
            c.isUserInteractionEnabled = false
            c.drawingGestureRecognizer.isEnabled = false
            c.backgroundColor = .clear
            c.isOpaque = false
            c.contentInsetAdjustmentBehavior = .never
            c.showsVerticalScrollIndicator = false
            c.showsHorizontalScrollIndicator = false
            c.bouncesZoom = false
            c.delegate = self
        }
        mask.fillRule = .evenOdd
        mask.fillColor = UIColor.black.cgColor
    }

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        guard pending > 0 else { return }
        pending -= 1
        if pending == 0 { board?.maskSpaceInk() }
    }
}

extension BoardController {
    // MARK: the drag

    /// The drag starts at `line` (board units): works out what moves and puts it on the overlay. False when nothing can (only this
    /// column moves and there is nothing in it).
    @discardableResult
    func beginSpaceDrag(at line: CGFloat, from start: CGPoint, sideways: Bool) -> Bool {
        finishSpaceLive()
        syncStrokes()
        let tools = BoardTools.shared
        let band = tools.spaceMoves == .column ? spaceColumn(at: start, line: line, sideways: sideways) : nil
        if tools.spaceMoves == .column, band == nil {
            toast("Nothing in this column to move")
            return false
        }
        spaceSideways = sideways
        spaceBandRange = band
        spaceStart = line
        let strokes = canvas.drawing.strokes
        let live = SpaceLive(line: line, sideways: sideways, band: band, strokes: strokes,
                             ids: ledger.lastIds.count == strokes.count ? ledger.lastIds : [])
        live.board = self
        spaceLive = live
        for c in [live.stillInk, live.movingInk] {
            c.overrideUserInterfaceStyle = canvas.overrideUserInterfaceStyle
            c.minimumZoomScale = canvas.minimumZoomScale
            c.maximumZoomScale = canvas.maximumZoomScale
        }
        view.insertSubview(live.stillInk, aboveSubview: canvas)
        view.insertSubview(live.movingInk, aboveSubview: live.stillInk)
        placeSpaceInk()
        // the ink for adding goes up at once, so it is drawn by the time the drag has gone anywhere
        let side = spaceSide(live, adding: true)
        live.add = side
        showSpaceInk(side)
        return true
    }

    /// The drag is `raw` long (board units, already snapped): shows what letting go now would do.
    func moveSpaceDrag(_ raw: CGFloat) {
        guard let live = spaceLive, !live.letGo else { return }
        live.raw = raw
        var side: SpaceLive.Side?
        if raw >= 4 {
            if live.add == nil { live.add = spaceSide(live, adding: true) }
            side = live.add
        } else if raw <= -4 {
            if live.take == nil { live.take = spaceSide(live, adding: false) }
            side = live.take
        }
        let by = side.map { CGFloat(InsertSpace.applied(Double(raw), limit: Double($0.plan.limit))) } ?? 0
        if let side, by != 0, let shown = live.shown, !shown.sameInk(side) { showSpaceInk(side) }
        live.by = by
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let z = canvas.zoomScale
        live.movingInk.transform = live.sideways ? CGAffineTransform(translationX: by * z, y: 0) : CGAffineTransform(translationX: 0, y: by * z)
        showSpaceItems(by == 0 ? nil : side, by: by)
        CATransaction.commit()
        var note: String?
        if raw <= -4, by == 0 { note = side?.plan.problem ?? "No empty space before the line to take away" }
        showSpaceGuide(from: side?.plan.line ?? live.line, by: by, note: note)
    }

    /// Let go after a drag `raw` long: does what was shown. True when the drag was long enough to count as a use of the tool.
    @discardableResult
    func endSpaceDrag(_ raw: CGFloat) -> Bool {
        guard let live = spaceLive, !live.letGo else { return false }
        moveSpaceDrag(raw)
        let by = live.by
        // the items go back to where they were, and doing it puts them in their new places (all before the screen is drawn again)
        showSpaceItems(nil, by: 0)
        hideSpaceGuide()
        spaceStart = nil
        let was = offset
        var done = false
        if by != 0, let side = by > 0 ? live.add : live.take {
            done = doSpace(side.plan, by: by)
        } else if raw <= -4 {
            toast(live.take?.plan.problem ?? "No empty space before the line to take away")
        }
        if done, offset == was, live.shown != nil {
            // the overlay stays until the board's canvas has drawn the moved ink (or a moment has passed)
            live.letGo = true
            placeSpaceInk()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak live] in
                guard let self, let live, self.spaceLive === live else { return }
                self.finishSpaceLive()
            }
        } else {
            finishSpaceLive()
        }
        return abs(raw) >= 4
    }

    /// The drag was cancelled: everything as it was.
    func cancelSpaceDrag() {
        guard let live = spaceLive else { spaceStart = nil; hideSpaceGuide(); return }
        if !live.letGo { showSpaceItems(nil, by: 0) }
        spaceStart = nil
        hideSpaceGuide()
        finishSpaceLive()
    }

    /// Takes the overlay away and shows the board's canvas whole again.
    func finishSpaceLive() {
        guard let live = spaceLive else { return }
        spaceLive = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if canvas.layer.mask === live.mask { canvas.layer.mask = nil }
        CATransaction.commit()
        for c in [live.movingInk, live.stillInk] {
            c.delegate = nil
            c.removeFromSuperview()
        }
    }

    /// The board's canvas drew (PencilKit): after letting go, that was the moved ink, so the overlay can go.
    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        guard canvasView === canvas, let live = spaceLive, live.letGo else { return }
        finishSpaceLive()
    }

    // MARK: what moves

    /// What moves for the drag going one way, worked out once (strokes must be in step with the canvas).
    func spaceSide(_ live: SpaceLive, adding: Bool) -> SpaceLive.Side {
        let plan = adding ? addPlan(at: live.line, sideways: live.sideways, band: live.band)
                          : removePlan(at: live.line, sideways: live.sideways, band: live.band)
        let m = spaceMovers(plan.line, except: plan.except, sideways: live.sideways, band: live.band)
        var movingIds = Set<String>()
        var boxes: [InsertSpace.Box] = []
        for i in m.strokes {
            movingIds.insert(content.strokes[i].id)
            if let b = strokeBox(content.strokes[i]) { boxes.append(b) }
        }
        let h = InsertSpace.hidden(line: Double(plan.line), band: live.band.map { Double($0.lowerBound)...Double($0.upperBound) },
                                   moving: boxes, sideways: live.sideways)
        let far: CGFloat = 10_000_000
        let from = CGFloat(h.from)
        let lo = h.across.map { CGFloat($0.lowerBound) } ?? -far, hi = h.across.map { CGFloat($0.upperBound) } ?? far
        let hidden = live.sideways ? CGRect(x: from + offset.x, y: lo + offset.y, width: far, height: hi - lo)
                                   : CGRect(x: lo + offset.x, y: from + offset.y, width: hi - lo, height: far)
        // only ink near the screen goes on the overlay (a screen's worth around it, more along the drag): what is further away
        // can't come into view, and leaving it out keeps the start of a drag quick on a full board
        let z = canvas.zoomScale
        let seen = CGRect(x: canvas.contentOffset.x / z, y: canvas.contentOffset.y / z, width: canvas.bounds.width / z, height: canvas.bounds.height / z)
        let near = seen.insetBy(dx: -seen.width, dy: -seen.height)
        var moving: [Int] = [], still: [Int] = []
        let known = live.ids.count == live.strokes.count
        for (i, k) in live.strokes.enumerated() {
            let r = k.renderBounds
            guard r.intersects(near), r.intersects(hidden) else { continue }
            let moves: Bool
            if known {
                moves = movingIds.contains(live.ids[i])
            } else {
                // (never expected: the ledger always names every stroke after a sync) judge the stroke by its own box
                let b = InsertSpace.Box(minX: Double(r.minX - offset.x), minY: Double(r.minY - offset.y),
                                        maxX: Double(r.maxX - offset.x), maxY: Double(r.maxY - offset.y))
                moves = InsertSpace.moves(b, line: Double(plan.line), sideways: live.sideways,
                                          band: live.band.map { Double($0.lowerBound)...Double($0.upperBound) })
            }
            if moves { moving.append(i) } else { still.append(i) }
        }
        return SpaceLive.Side(plan: plan, moving: moving, still: still, items: m.items.map { content.items[$0].id }, hidden: hidden)
    }

    // MARK: the overlay

    /// Puts a side's ink on the overlay canvases; the board's canvas hides that region once they have drawn it.
    func showSpaceInk(_ side: SpaceLive.Side) {
        guard let live = spaceLive else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if canvas.layer.mask === live.mask { canvas.layer.mask = nil }
        CATransaction.commit()
        live.masked = false
        live.shown = side
        live.pending = 0
        live.movingInk.drawing = PKDrawing(strokes: side.moving.map { live.strokes[$0] })
        live.stillInk.drawing = PKDrawing(strokes: side.still.map { live.strokes[$0] })
        live.pending = (side.moving.isEmpty ? 0 : 1) + (side.still.isEmpty ? 0 : 1)
        if live.pending == 0 { maskSpaceInk(); return }
        // in case PencilKit doesn't say it has drawn
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak live] in
            guard let self, let live, self.spaceLive === live, live.pending > 0 else { return }
            live.pending = 0
            self.maskSpaceInk()
        }
    }

    /// Hides the moving ink's region on the board's canvas (the overlay shows it).
    func maskSpaceInk() {
        guard let live = spaceLive, let side = live.shown else { return }
        let z = canvas.zoomScale
        let size = canvas.contentSize
        let m = max(view.bounds.width, view.bounds.height) * 2
        let outer = CGRect(x: -m, y: -m, width: size.width + 2 * m, height: size.height + 2 * m)
        let h = CGRect(x: side.hidden.minX * z, y: side.hidden.minY * z, width: side.hidden.width * z, height: side.hidden.height * z).intersection(outer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        live.mask.frame = outer
        let path = UIBezierPath(rect: CGRect(origin: .zero, size: outer.size))
        if !h.isNull, !h.isEmpty { path.append(UIBezierPath(rect: h.offsetBy(dx: m, dy: m))) }
        live.mask.path = path.cgPath
        canvas.layer.mask = live.mask
        CATransaction.commit()
        live.masked = true
    }

    /// Keeps the overlay canvases over the board's (same zoom and scroll; a screen longer along the drag, so taking space away
    /// brings up what is below the screen).
    func placeSpaceInk() {
        guard let live = spaceLive else { return }
        let z = canvas.zoomScale
        let f = canvas.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for c in [live.movingInk, live.stillInk] {
            let t = c.transform
            c.transform = .identity
            c.frame = CGRect(x: f.minX, y: f.minY, width: f.width * (live.sideways ? 2 : 1), height: f.height * (live.sideways ? 1 : 2))
            if abs(c.zoomScale - z) > 0.0001 { c.zoomScale = z }
            if c.contentSize != canvas.contentSize { c.contentSize = canvas.contentSize }
            if c.contentOffset != canvas.contentOffset { c.contentOffset = canvas.contentOffset }
            c.transform = t
        }
        live.movingInk.transform = live.sideways ? CGAffineTransform(translationX: live.by * z, y: 0) : CGAffineTransform(translationX: 0, y: live.by * z)
        CATransaction.commit()
        if live.masked { maskSpaceInk() }
    }

    /// Moves the item views (and changes the PDF printouts) as `side` would by `by`; nil puts them all back.
    func showSpaceItems(_ side: SpaceLive.Side?, by: CGFloat) {
        guard let live = spaceLive else { return }
        if let s = live.itemsShown, side.map({ $0.plan.adding == s.adding && by == s.by }) ?? (s.by == 0) { return }
        live.itemsShown = side.map { ($0.plan.adding, by) } ?? (true, 0)
        let wanted = Set(side?.items ?? [])
        var openedId: String?
        if let p = side?.plan.pdf, p.index < content.items.count { openedId = content.items[p.index].id }
        var touched: [PdfPrintout] = []
        // back first: what this side doesn't move
        for (id, c) in live.centers where !wanted.contains(id) {
            itemViews[id]?.center = c
            live.centers[id] = nil
        }
        for (id, it) in live.pdfWas where !wanted.contains(id) && id != openedId {
            if let p = pdfs[id] { p.update(it); p.place(in: pdfLayer, offset: offset); touched.append(p) }
            live.pdfWas[id] = nil
        }
        guard let side else { refreshPdfs(touched); return }
        let dx = live.sideways ? by : 0, dy = live.sideways ? 0 : by
        for id in side.items {
            if let p = pdfs[id] {
                let was = live.pdfWas[id] ?? content.items.first { $0.id == id }
                guard let was else { continue }
                live.pdfWas[id] = was
                p.update(live.sideways ? was.with("x", .number(was.x + Double(by))) : was.with("y", .number(was.y + Double(by))))
                p.place(in: pdfLayer, offset: offset)
                touched.append(p)
            } else if let v = itemViews[id] {
                let c = live.centers[id] ?? v.center
                live.centers[id] = c
                v.center = CGPoint(x: c.x + dx, y: c.y + dy)
            }
        }
        if let id = openedId, let p = pdfs[id], let pdf = side.plan.pdf {
            let was = live.pdfWas[id] ?? content.items[pdf.index]
            live.pdfWas[id] = was
            p.update(by == 0 ? was : withSpace(was, page: pdf.page, at: pdf.at, gap: Double(by)))
            p.place(in: pdfLayer, offset: offset)
            touched.append(p)
        }
        refreshPdfs(touched)
    }

    /// Pages that came into view on a moved printout are drawn.
    private func refreshPdfs(_ list: [PdfPrintout]) {
        guard !list.isEmpty else { return }
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        for p in list { p.refresh(visible: visibleBoard, zoom: canvas.zoomScale, screenScale: scale) }
    }
}
