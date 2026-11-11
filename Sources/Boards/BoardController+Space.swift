import UIKit
import PencilKit
import NexusCore

/// Moving what is on the board up or down to make or close space: Make room and Push things below (typing) and the Insert space
/// tool. On a PDF page, Insert space opens the page up at the line by default (board.json `space`, docs/data-format.md "Space in a
/// PDF"); the tool row's other choice moves the whole page down instead. Dragging up takes empty space away again.
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
        var moved = false
        for i in content.strokes.indices {
            let s = content.strokes[i]
            let top = s.points.map { $0.count >= 2 ? $0[1] : .infinity }.min() ?? .infinity
            guard Double(line) <= top else { continue }
            content.strokes[i].points = s.points.map { p in
                var q = p
                if q.count >= 2 { q[1] = InkConvert.r2(q[1] + Double(by)) }
                return q
            }
            moved = true
        }
        for i in content.items.indices where !except.contains(content.items[i].id) {
            let it = content.items[i]
            guard box(of: it).minY >= line else { continue }
            content.items[i] = it.with("y", .number((it.y + Double(by)).rounded()))
            moved = true
        }
        return moved
    }

    // MARK: PDF pages

    /// A PDF printout the line crosses: the piece of a page it falls on, or else the piece just above it (the line is in room).
    struct PdfSpot {
        let id: String
        let printout: PdfPrintout
        let inside: BoardFiles.PdfSegment?
        let above: BoardFiles.PdfSegment?
    }

    func pdfSpot(_ y: CGFloat) -> PdfSpot? {
        for (id, p) in pdfs.sorted(by: { $0.key < $1.key }) {
            let b = p.box
            guard y > b.minY, y < b.maxY else { continue }
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

    /// Room for `by` at `line` (board units): everything below moves down; a PDF page under the line opens up there.
    func insertSpace(at line: CGFloat, by: CGFloat) {
        guard !readOnly, by >= 1 else { return }
        syncStrokes()
        let beforeStrokes = content.strokes
        let beforeItems = (content.items, content.texts)
        var line = line
        var except = Set<String>()
        var opened = false
        if let spot = pdfSpot(line), let i = content.items.firstIndex(where: { $0.id == spot.id }) {
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
        moveBelow(line, by: by, except: except)
        redrawStrokes()
        registerBoardUndo(strokes: beforeStrokes, items: beforeItems, "Insert space")
        rebuildItems()
        if opened { addFeature("space") }
        writing?.place()
        growIfNeeded()
        changed()
    }

    /// Takes away up to `want` of empty space just above `line`: everything below moves up. Only empty space goes (nothing is
    /// pushed over anything), and on a PDF only room that was opened in it.
    func removeSpace(at line: CGFloat, want: CGFloat) {
        guard !readOnly, want >= 1 else { return }
        syncStrokes()
        let beforeStrokes = content.strokes
        let beforeItems = (content.items, content.texts)
        var except = Set<String>()
        var can = want
        var pdfPlace: (index: Int, page: Int, at: Double)?
        let spot = pdfSpot(line)
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
        // the lowest thing above the line
        var bottom = -CGFloat.infinity
        for s in content.strokes {
            let ys = s.points.compactMap { $0.count >= 2 ? CGFloat($0[1]) : nil }
            guard let top = ys.min(), top < line, let low = ys.max() else { continue }
            bottom = max(bottom, low)
        }
        for it in content.items where !except.contains(it.id) {
            let b = box(of: it)
            if b.minY < line { bottom = max(bottom, b.maxY) }
        }
        if let spot {
            for s in spot.printout.segments where CGFloat(s.y) < line { bottom = max(bottom, CGFloat(s.y + s.h)) }
        }
        if bottom > -CGFloat.infinity { can = min(can, line - bottom - 2) }
        can = can.rounded(.down)
        guard can >= 1 else { toast("No empty space above to take away"); return }
        if let p = pdfPlace {
            content.items[p.index] = withSpace(content.items[p.index], page: p.page, at: p.at, gap: -Double(can))
        }
        moveBelow(line, by: -can, except: except)
        redrawStrokes()
        registerBoardUndo(strokes: beforeStrokes, items: beforeItems, "Remove space")
        rebuildItems()
        writing?.place()
        changed()
    }

    // MARK: the tool

    /// Drag down (Pencil or a finger) to add space at the line where you start, up to take it away. Snaps to the paper's lines.
    @objc func spacePanned(_ g: UIPanGestureRecognizer) {
        let z = canvas.zoomScale
        switch g.state {
        case .began:
            let t = g.translation(in: canvas)
            let now = boardPoint(g)
            var y = now.y - t.y / z
            if paper.kind != .plain { y = CGFloat(paper.snap(Double(y))) }
            spaceStart = y
            showSpaceGuide(from: y, by: t.y / z)
        case .changed:
            guard let y = spaceStart else { return }
            showSpaceGuide(from: y, by: g.translation(in: canvas).y / z)
        case .ended:
            guard let y = spaceStart else { return }
            spaceStart = nil
            hideSpaceGuide()
            let by = (g.translation(in: canvas).y / z).rounded()
            if by >= 4 { insertSpace(at: y, by: by) } else if by <= -4 { removeSpace(at: y, want: -by) }
        default:
            spaceStart = nil
            hideSpaceGuide()
        }
    }

    func setUpSpaceGuide() {
        spaceGuide.isUserInteractionEnabled = false
        spaceGuide.frame = view.bounds
        spaceGuide.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        spaceBand.fillColor = UIColor.systemBlue.withAlphaComponent(0.1).cgColor
        spaceLine.strokeColor = UIColor.systemBlue.cgColor
        spaceLine.lineWidth = 1.5
        spaceLine.lineDashPattern = [6, 4]
        spaceGuide.layer.addSublayer(spaceBand)
        spaceGuide.layer.addSublayer(spaceLine)
        spaceLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        spaceLabel.textColor = .white
        spaceLabel.backgroundColor = .systemBlue
        spaceLabel.layer.cornerRadius = 6
        spaceLabel.clipsToBounds = true
        spaceLabel.textAlignment = .center
        spaceGuide.addSubview(spaceLabel)
        spaceGuide.isHidden = true
        view.addSubview(spaceGuide)
    }

    func showSpaceGuide(from y: CGFloat, by: CGFloat) {
        let z = canvas.zoomScale
        let sy = (y + offset.y) * z - canvas.contentOffset.y
        let ey = sy + by * z
        let w = view.bounds.width
        spaceBand.path = UIBezierPath(rect: CGRect(x: 0, y: min(sy, ey), width: w, height: abs(ey - sy))).cgPath
        let line = UIBezierPath()
        line.move(to: CGPoint(x: 0, y: sy))
        line.addLine(to: CGPoint(x: w, y: sy))
        spaceLine.path = line.cgPath
        let amount = Int(abs(by).rounded())
        let onPdf = pdfSpot(y)?.inside != nil
        let what = by >= 0 ? (onPdf && BoardTools.shared.spaceOpensPage ? "Open up the page" : "Insert space") : "Take space away"
        spaceLabel.text = "  \(what) · \(amount)  "
        spaceLabel.sizeToFit()
        spaceLabel.frame.size.height = 24
        spaceLabel.center = CGPoint(x: w / 2, y: max(sy, ey) + 18)
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
