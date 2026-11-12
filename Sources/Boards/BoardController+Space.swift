import UIKit
import PencilKit
import NexusCore

/// Moving what is on the board to make or close space: Make room and Push things below (typing) and the Insert space tool. On a
/// PDF page, Insert space opens the page up at the line by default (board.json `space`, docs/data-format.md "Space in a PDF"); the
/// tool row's other choice keeps pages whole and puts the room between them. The tool's options (NexusCore InsertSpace, the
/// approved redesign's table): everything past the line or only this column, down or following the drag (sideways makes room to
/// the right), whole lines of the paper or free, closing that stops at content or not, what a tap adds, and what comes after.
extension BoardController {
    /// Moves every stroke and item whose top is at or below `line` down by `by` (strokes keep their ids). One undo step when named.
    func shift(below line: CGFloat, by: CGFloat, except id: String, name: String?) {
        syncStrokes()
        let beforeStrokes = content.strokes
        let beforeItems = (content.items, content.texts)
        guard moveBelow(line, by: by, except: [id]) else { return }
        redrawStrokes()
        if let name { registerBoardUndo(strokes: beforeStrokes, items: beforeItems, name) }
        rebuildItems()
        writing?.place()
        changed()
    }

    /// The moving itself, on `content` (strokes must be in step with the canvas first). True when anything moved.
    @discardableResult
    func moveBelow(_ line: CGFloat, by: CGFloat, except: Set<String>) -> Bool {
        moveAfter(line, by: by, except: except, sideways: false, band: nil)
    }

    /// Moves everything that starts at or past `line` (down, or right when `sideways`) by `by`, only within `band` when given.
    @discardableResult
    func moveAfter(_ line: CGFloat, by: CGFloat, except: Set<String>, sideways: Bool, band: ClosedRange<CGFloat>?) -> Bool {
        let band = band.map { Double($0.lowerBound)...Double($0.upperBound) }
        let axis = sideways ? 0 : 1
        var moved = false
        for i in content.strokes.indices {
            let s = content.strokes[i]
            guard let b = strokeBox(s), InsertSpace.moves(b, line: Double(line), sideways: sideways, band: band) else { continue }
            content.strokes[i].points = s.points.map { p in
                var q = p
                if q.count >= 2 { q[axis] = InkConvert.r2(q[axis] + Double(by)) }
                return q
            }
            moved = true
        }
        for i in content.items.indices where !except.contains(content.items[i].id) {
            let it = content.items[i]
            guard InsertSpace.moves(spaceBox(box(of: it)), line: Double(line), sideways: sideways, band: band) else { continue }
            content.items[i] = sideways ? it.with("x", .number((it.x + Double(by)).rounded()))
                                        : it.with("y", .number((it.y + Double(by)).rounded()))
            moved = true
        }
        return moved
    }

    func strokeBox(_ s: BoardStroke) -> InsertSpace.Box? {
        let pts = s.points.filter { $0.count >= 2 }
        guard let first = pts.first else { return nil }
        var b = InsertSpace.Box(minX: first[0], minY: first[1], maxX: first[0], maxY: first[1])
        for p in pts {
            b.minX = min(b.minX, p[0]); b.maxX = max(b.maxX, p[0])
            b.minY = min(b.minY, p[1]); b.maxY = max(b.maxY, p[1])
        }
        return b
    }

    func spaceBox(_ r: CGRect) -> InsertSpace.Box {
        InsertSpace.Box(minX: Double(r.minX), minY: Double(r.minY), maxX: Double(r.maxX), maxY: Double(r.maxY))
    }

    /// For "Only this column": the column (or row, sideways) the touch at `p` is in, from what is on the board; nil when empty.
    func spaceColumn(at p: CGPoint, line: CGFloat, sideways: Bool) -> ClosedRange<CGFloat>? {
        syncStrokes()
        var boxes = content.strokes.compactMap(strokeBox)
        boxes += content.items.filter { !BoardLinks.isLink($0) }.map { spaceBox(box(of: $0)) }
        guard let r = InsertSpace.band(seed: Double(sideways ? p.y : p.x), line: Double(line), boxes: boxes, sideways: sideways) else { return nil }
        return CGFloat(r.lowerBound)...CGFloat(r.upperBound)
    }

    // MARK: PDF pages

    /// A PDF printout the line crosses: the piece of a page it falls on, or else the piece just above it (the line is in room).
    struct PdfSpot {
        let id: String
        let printout: PdfPrintout
        let inside: BoardFiles.PdfSegment?
        let above: BoardFiles.PdfSegment?
    }

    /// The printout under `y` (only one that overlaps `band`, when one is given).
    func pdfSpot(_ y: CGFloat, band: ClosedRange<CGFloat>? = nil) -> PdfSpot? {
        for (id, p) in pdfs.sorted(by: { $0.key < $1.key }) {
            let b = p.box
            guard y > b.minY, y < b.maxY else { continue }
            if let band, b.maxX < band.lowerBound || b.minX > band.upperBound { continue }
            if let s = p.segments.first(where: { CGFloat($0.y) <= y && y < CGFloat($0.y + $0.h) }) {
                return PdfSpot(id: id, printout: p, inside: s, above: nil)
            }
            let above = p.segments.filter { CGFloat($0.y + $0.h) <= y }.max { $0.y < $1.y }
            return PdfSpot(id: id, printout: p, inside: nil, above: above)
        }
        return nil
    }

    /// The printout with `gap` more room at (page from 1, at); a gap that comes to nothing is taken out of the list.
    func withSpace(_ it: BoardItem, page: Int, at: Double, gap: Double) -> BoardItem {
        var list = it.json["space"]?.array ?? []
        let at = (at * 10000).rounded() / 10000
        if let i = list.firstIndex(where: { Int($0["page"]?.number ?? 0) == page && abs(($0["at"]?.number ?? 1) - at) < 0.0005 }) {
            let g = ((list[i]["gap"]?.number ?? 0) + gap).rounded()
            if g < 1 { list.remove(at: i) } else { list[i] = list[i].setting("gap", .number(g)) }
        } else if gap >= 1 {
            list.append(.object([("page", .number(Double(page))), ("at", .number(at)), ("gap", .number(gap.rounded()))]))
        }
        return it.with("space", list.isEmpty ? nil : .array(list))
    }

    /// The room already at (page, at) on a printout.
    func spaceGap(_ it: BoardItem, page: Int, at: Double) -> Double {
        let list = it.json["space"]?.array ?? []
        return list.first(where: { Int($0["page"]?.number ?? 0) == page && abs(($0["at"]?.number ?? 1) - at) < 0.0005 })?["gap"]?.number ?? 0
    }

    // MARK: Insert space

    /// Room for `by` at `line` (board units): everything past it moves down (or right, `sideways`), only within `band` when given.
    /// Going down, a PDF page under the line opens up there (or, kept whole, the room goes above the page).
    func insertSpace(at line: CGFloat, by: CGFloat, sideways: Bool = false, band: ClosedRange<CGFloat>? = nil) {
        guard !readOnly, by >= 1 else { return }
        syncStrokes()
        let beforeStrokes = content.strokes
        let beforeItems = (content.items, content.texts)
        var line = line
        var except = Set<String>()
        var opened = false
        if !sideways, let spot = pdfSpot(line, band: band), let i = content.items.firstIndex(where: { $0.id == spot.id }) {
            let it = content.items[i]
            var place: (page: Int, at: Double)?
            if let s = spot.inside {
                let near: CGFloat = 12
                if !BoardTools.shared.spaceOpensPage || line - CGFloat(s.y) < near {
                    place = (s.page + 1, s.top) // above this page (or this piece of it)
                    line = CGFloat(s.y)
                } else if CGFloat(s.y + s.h) - line < near {
                    place = (s.page + 1, s.bottom)
                    line = CGFloat(s.y + s.h)
                } else {
                    place = (s.page + 1, s.top + Double(line - CGFloat(s.y)) / Double(spot.printout.pageHeight(s)))
                }
            } else if let a = spot.above {
                place = (a.page + 1, a.bottom) // in room already there: more of it
            }
            if let place {
                content.items[i] = withSpace(it, page: place.page, at: place.at, gap: Double(by))
                except.insert(spot.id)
                opened = true
            }
        }
        let moved = moveAfter(line, by: by, except: except, sideways: sideways, band: band)
        guard moved || opened else { toast(band == nil ? "Nothing past the line to move" : "Nothing in this column to move"); return }
        redrawStrokes()
        registerBoardUndo(strokes: beforeStrokes, items: beforeItems, "Insert space")
        rebuildItems()
        if opened { addFeature("space") }
        writing?.place()
        growIfNeeded()
        changed()
    }

    /// Takes away up to `want` of space just before `line`: everything past it moves back. Stopping at content (the default), only
    /// empty space goes and nothing is pushed over anything; on a PDF only room that was opened in it goes either way.
    func removeSpace(at line: CGFloat, want: CGFloat, sideways: Bool = false, band: ClosedRange<CGFloat>? = nil) {
        guard !readOnly, want >= 1 else { return }
        syncStrokes()
        let beforeStrokes = content.strokes
        let beforeItems = (content.items, content.texts)
        let stop = BoardTools.shared.spaceClosing == .stopAtContent
        var except = Set<String>()
        var can = want
        var pdfPlace: (index: Int, page: Int, at: Double)?
        let spot = sideways ? nil : pdfSpot(line, band: band)
        if let spot {
            guard spot.inside == nil, let a = spot.above, let i = content.items.firstIndex(where: { $0.id == spot.id }) else {
                toast("That's on a PDF page: there's no empty space to take away")
                return
            }
            let room = spaceGap(content.items[i], page: a.page + 1, at: a.bottom)
            guard room >= 1 else { toast("Only room opened in the PDF can be taken away"); return }
            can = min(can, CGFloat(room))
            except.insert(spot.id)
            pdfPlace = (i, a.page + 1, a.bottom)
        }
        if stop {
            // the last thing before the line (in the band, when there is one)
            let dband = band.map { Double($0.lowerBound)...Double($0.upperBound) }
            func inBand(_ b: InsertSpace.Box) -> Bool {
                guard let dband else { return true }
                let (lo, hi) = sideways ? (b.minY, b.maxY) : (b.minX, b.maxX)
                return hi >= dband.lowerBound && lo <= dband.upperBound
            }
            var end = -CGFloat.infinity
            var boxes = content.strokes.compactMap(strokeBox)
            boxes += content.items.filter { !except.contains($0.id) && !BoardLinks.isLink($0) }.map { spaceBox(box(of: $0)) }
            for b in boxes where inBand(b) {
                let (start, stopAt) = sideways ? (b.minX, b.maxX) : (b.minY, b.maxY)
                if CGFloat(start) < line { end = max(end, CGFloat(stopAt)) }
            }
            if let spot {
                for s in spot.printout.segments where CGFloat(s.y) < line { end = max(end, CGFloat(s.y + s.h)) }
            }
            if end > -CGFloat.infinity { can = min(can, line - end - 2) }
        }
        can = can.rounded(.down)
        guard can >= 1 else { toast("No empty space before the line to take away"); return }
        if let p = pdfPlace {
            content.items[p.index] = withSpace(content.items[p.index], page: p.page, at: p.at, gap: -Double(can))
        }
        moveAfter(line, by: -can, except: except, sideways: sideways, band: band)
        redrawStrokes()
        registerBoardUndo(strokes: beforeStrokes, items: beforeItems, "Remove space")
        rebuildItems()
        writing?.place()
        changed()
    }

    // MARK: the tool

    /// Drag down (Pencil or a finger) to add space at the line where you start, up to take it away; sideways too when the option
    /// lets it. The line and the amount snap to the paper unless Size is Free.
    @objc func spacePanned(_ g: UIPanGestureRecognizer) {
        let z = canvas.zoomScale
        let tools = BoardTools.shared
        switch g.state {
        case .began:
            let t = g.translation(in: canvas)
            let now = boardPoint(g)
            let start = CGPoint(x: now.x - t.x / z, y: now.y - t.y / z)
            let side = InsertSpace.sideways(dx: Double(t.x), dy: Double(t.y), direction: tools.spaceDirection)
            let at = CGFloat(InsertSpace.line(Double(side ? start.x : start.y), paper: paper, size: tools.spaceSize, sideways: side))
            spaceSideways = side
            spaceStart = at
            spaceBandRange = tools.spaceMoves == .column ? spaceColumn(at: start, line: at, sideways: side) : nil
            if tools.spaceMoves == .column, spaceBandRange == nil {
                spaceStart = nil
                toast("Nothing in this column to move")
                return
            }
            showSpaceGuide(from: at, by: spaceAmount(side ? t.x / z : t.y / z))
        case .changed:
            guard let at = spaceStart else { return }
            let t = g.translation(in: canvas)
            showSpaceGuide(from: at, by: spaceAmount(spaceSideways ? t.x / z : t.y / z))
        case .ended:
            guard let at = spaceStart else { return }
            spaceStart = nil
            hideSpaceGuide()
            let t = g.translation(in: canvas)
            let by = spaceAmount(spaceSideways ? t.x / z : t.y / z)
            if by >= 4 { insertSpace(at: at, by: by, sideways: spaceSideways, band: spaceBandRange) }
            else if by <= -4 { removeSpace(at: at, want: -by, sideways: spaceSideways, band: spaceBandRange) }
            else { return }
            spaceUsed()
        default:
            spaceStart = nil
            hideSpaceGuide()
        }
    }

    /// A drag's length as the room it makes (whole lines or squares when snapping).
    func spaceAmount(_ raw: CGFloat) -> CGFloat {
        CGFloat(InsertSpace.amount(Double(raw), paper: paper, size: BoardTools.shared.spaceSize, sideways: spaceSideways))
    }

    /// A tap without dragging: the set amount of room at that line (half a screen by default).
    @objc func spaceTapped(_ g: UITapGestureRecognizer) {
        let tools = BoardTools.shared
        let by = CGFloat(InsertSpace.tapAmount(tools.spaceTap, screen: Double(visibleBoard.height), paper: paper, size: tools.spaceSize))
        guard by >= 1 else { return }
        let p = boardPoint(g)
        let at = CGFloat(InsertSpace.line(Double(p.y), paper: paper, size: tools.spaceSize))
        var band: ClosedRange<CGFloat>?
        if tools.spaceMoves == .column {
            guard let b = spaceColumn(at: p, line: at, sideways: false) else { toast("Nothing in this column to move"); return }
            band = b
        }
        insertSpace(at: at, by: by, band: band)
        spaceUsed()
    }

    /// After one use: back to the pen you had (the default), or stay on Insert space.
    func spaceUsed() {
        let tools = BoardTools.shared
        guard tools.spaceAfter == .pen, tools.tool == .space else { return }
        let back = tools.previousTool.inks && tools.previousTool != .shapes ? tools.previousTool : .pen
        selectTool(back)
    }

    func setUpSpaceGuide() {
        spaceGuide.isUserInteractionEnabled = false
        spaceGuide.frame = view.bounds
        spaceGuide.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let green = UIColor(red: 0.13, green: 0.6, blue: 0.33, alpha: 1)
        spaceBand.fillColor = green.withAlphaComponent(0.1).cgColor
        spaceLine.strokeColor = green.cgColor
        spaceLine.lineWidth = 1.5
        spaceLine.lineDashPattern = [6, 4]
        spaceLine.fillColor = UIColor.clear.cgColor
        spaceGuide.layer.addSublayer(spaceBand)
        spaceGuide.layer.addSublayer(spaceLine)
        spaceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        spaceLabel.textColor = .white
        spaceLabel.backgroundColor = green
        spaceLabel.layer.cornerRadius = 6
        spaceLabel.clipsToBounds = true
        spaceLabel.textAlignment = .center
        spaceGuide.addSubview(spaceLabel)
        spaceGuide.isHidden = true
        view.addSubview(spaceGuide)
    }

    /// The line where the room goes, the band it opens (or closes), and what will happen, on screen while dragging. With only this
    /// column moving, the line and band span just the column.
    func showSpaceGuide(from at: CGFloat, by: CGFloat) {
        let z = canvas.zoomScale, o = canvas.contentOffset
        let side = spaceSideways
        let toScreenX = { (x: CGFloat) in (x + self.offset.x) * z - o.x }
        let toScreenY = { (y: CGFloat) in (y + self.offset.y) * z - o.y }
        let s0 = side ? toScreenX(at) : toScreenY(at), s1 = s0 + by * z
        // across the drag: the whole screen, or the column
        var a0: CGFloat = 0, a1: CGFloat = side ? view.bounds.height : view.bounds.width
        if let band = spaceBandRange {
            a0 = side ? toScreenY(band.lowerBound) : toScreenX(band.lowerBound)
            a1 = side ? toScreenY(band.upperBound) : toScreenX(band.upperBound)
            a0 -= 12; a1 += 12
        }
        let rect = side ? CGRect(x: min(s0, s1), y: a0, width: abs(s1 - s0), height: a1 - a0)
                        : CGRect(x: a0, y: min(s0, s1), width: a1 - a0, height: abs(s1 - s0))
        spaceBand.path = UIBezierPath(rect: rect).cgPath
        let line = UIBezierPath()
        line.move(to: side ? CGPoint(x: s0, y: a0) : CGPoint(x: a0, y: s0))
        line.addLine(to: side ? CGPoint(x: s0, y: a1) : CGPoint(x: a1, y: s0))
        spaceLine.path = line.cgPath
        let amount = Int(abs(by).rounded())
        let what: String
        if by < 0 {
            what = "Take space away"
        } else if side {
            what = spaceBandRange == nil ? "Room to the right" : "Room to the right, this row"
        } else {
            let pdf = pdfSpot(at, band: spaceBandRange)
            if pdf?.inside != nil {
                what = BoardTools.shared.spaceOpensPage ? "Open up the page" : "Room between pages: the page stays whole"
            } else {
                what = spaceBandRange == nil ? "Insert space" : "Insert space, this column"
            }
        }
        spaceLabel.text = "  \(what) · \(amount)  "
        spaceLabel.sizeToFit()
        spaceLabel.frame.size.height = 24
        spaceLabel.center = side ? CGPoint(x: max(s0, s1) + spaceLabel.bounds.width / 2 + 8, y: (a0 + a1) / 2)
                                 : CGPoint(x: (max(0, a0) + min(view.bounds.width, a1)) / 2, y: max(s0, s1) + 18)
        spaceGuide.isHidden = false
        view.bringSubviewToFront(spaceGuide)
        view.bringSubviewToFront(bar)
    }

    func hideSpaceGuide() {
        spaceGuide.isHidden = true
        spaceBand.path = nil
        spaceLine.path = nil
    }
}
