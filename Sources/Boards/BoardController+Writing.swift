import UIKit
import PencilKit
import NexusCore

/// Typing on the board (piece 4 of the board redesign): a block opens in place, over the board, with the formatting row; its words
/// are saved as you type; closing it gives the board's undo one step for the whole typing. Make room pushes what is below a block
/// down, ink included (stroke ids kept), as one undo.
extension BoardController {
    /// A board point (units) on screen, in the view's coordinates.
    func viewPoint(board p: CGPoint) -> CGPoint {
        let z = canvas.zoomScale, o = canvas.contentOffset
        return CGPoint(x: (p.x + offset.x) * z - o.x, y: (p.y + offset.y) * z - o.y)
    }

    // MARK: opening and closing a block

    /// Opens a block for typing, with the caret at a board point (or at the end).
    func beginWriting(_ it: BoardItem, at point: CGPoint? = nil) {
        guard !readOnly, it.type == "text" else { return }
        if let w = writing {
            if w.id == it.id { return }
            endWriting()
        }
        guard let current = content.items.first(where: { $0.id == it.id }) else { return }
        selected = nil
        let session = WritingSession(board: self, item: current)
        syncStrokes()
        session.beforeStrokes = content.strokes
        pushedBottom[it.id] = box(of: current).maxY
        pushedBy[it.id] = 0
        writing = session
        itemViews[it.id]?.alpha = 0
        view.insertSubview(session.textView, aboveSubview: canvas)
        session.restyle()
        session.measure()
        session.place()
        session.textView.becomeFirstResponder()
        let len = (session.text as NSString).length
        if let point {
            let v = viewPoint(board: point)
            let inView = session.textView.convert(v, from: view)
            if let pos = session.textView.closestPosition(to: inView) {
                session.textView.selectedTextRange = session.textView.textRange(from: pos, to: pos)
            }
        } else {
            session.textView.selectedRange = NSRange(location: len, length: 0)
        }
        updateBar()
    }

    /// Closes the open block: an empty one goes; a changed one is one step of the board's undo.
    func endWriting() {
        guard let w = writing else { return }
        writing = nil
        w.textView.resignFirstResponder()
        w.textView.removeFromSuperview()
        finish(w)
        if !readOnly { canvas.becomeFirstResponder() }
        updateBar()
    }

    /// The typing in a block is over (on the board or in the Writing view): keep it as one undo step.
    func finish(_ w: WritingSession) {
        let id = w.id
        let text = w.text
        itemViews[id]?.alpha = 1
        let pushed = (pushedBy[id] ?? 0) > 0.5
        pushedBy[id] = nil
        pushedBottom[id] = nil
        func undoStep(_ name: String) {
            if pushed { registerBoardUndo(strokes: w.beforeStrokes, items: w.before, name) } else { registerItemsUndo(w.before, name) }
        }
        if content.items.contains(where: { $0.id == id }) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                content.items.removeAll { $0.id == id }
                content.texts[id] = nil
                // a new block left empty just goes, as on the laptop
                if !w.startText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { undoStep("Delete text") }
                rebuildItems()
                changed()
            } else if text != w.startText {
                content.texts[id] = text
                undoStep("Typing")
                rebuildItems()
                changed()
            } else {
                rebuildItems()
            }
        }
        saveNow()
    }

    /// The open block's words changed: keep them in the board's content, saved shortly (the laptop saves about every half second).
    func typed(_ id: String, _ text: String) {
        logTyping(id, text) // the version history's keystrokes (BoardController+History.swift)
        content.texts[id] = text
        changed()
        pushBelow(id)
    }

    /// Drafts can lock a block (piece 4's drafts); nothing is locked yet.
    func blockLocked(_ id: String) -> Bool {
        guard let it = content.items.first(where: { $0.id == id }) else { return false }
        guard let current = it.string("draft"), let drafts = it.json["drafts"]?.array else { return false }
        return drafts.contains { $0["id"]?.string == current && $0["locked"]?.bool == true }
    }

    // MARK: the block's fields

    /// Sets one field of a block (nil takes it off), as one undo step; the open block redraws.
    func setBlockField(_ id: String, _ key: String, _ value: JSONValue?) {
        guard let i = content.items.firstIndex(where: { $0.id == id }) else { return }
        let before = (content.items, content.texts)
        content.items[i] = content.items[i].with(key, value)
        registerItemsUndo(before, "Change text")
        addFeature("writing")
        afterBlockChange(id)
    }

    /// Size, colour or background, the laptop's way (TextLook.with).
    func setBlockLook(_ id: String, _ key: String, _ value: String?) {
        guard let i = content.items.firstIndex(where: { $0.id == id }) else { return }
        let before = (content.items, content.texts)
        content.items[i] = TextLook.with(content.items[i], key, value)
        registerItemsUndo(before, "Change text")
        afterBlockChange(id)
    }

    func afterBlockChange(_ id: String) {
        rebuildItems()
        if let w = writing, w.id == id {
            itemViews[id]?.alpha = 0
            w.lookChanged()
        }
        changed()
    }

    /// Notes a redesign feature on the board (board.json `features`) the first time it is written; the next save writes board.json.
    func addFeature(_ name: String) {
        guard let meta = content.meta else { return }
        let next = BoardFormat.withFeature(meta, name)
        if next != meta {
            content.meta = next
            changed()
        }
    }

    func deleteBlock(_ id: String) {
        guard let w = writing, w.id == id else {
            changeItems("Delete") { c in c.items.removeAll { $0.id == id }; c.texts[id] = nil }
            return
        }
        let before = w.before
        writing = nil
        w.textView.resignFirstResponder()
        w.textView.removeFromSuperview()
        content.items.removeAll { $0.id == id }
        content.texts[id] = nil
        registerItemsUndo(before, "Delete text")
        rebuildItems()
        changed()
        canvas.becomeFirstResponder()
        updateBar()
    }

    // MARK: making room

    /// Everything on the board with its box (units): strokes and items.
    func boardThings(except id: String) -> [(kind: String, id: String, box: CGRect)] {
        var out: [(kind: String, id: String, box: CGRect)] = []
        syncStrokes()
        for s in content.strokes {
            var r = CGRect.null
            for p in s.points where p.count >= 2 { r = r.union(CGRect(x: p[0], y: p[1], width: 0.1, height: 0.1)) }
            if !r.isNull { out.append(("stroke", s.id, r)) }
        }
        for it in content.items where it.id != id { out.append(("item", it.id, box(of: it))) }
        return out
    }

    /// The board's strokes as the canvas has them now (ids kept by the ledger).
    func syncStrokes() {
        content.strokes = ledger.strokes(canvas.drawing, offset: offset, taken: Set(content.items.map(\.id)))
    }

    /// Make room (the laptop's rule, docs/board-writing.md): the line is the top of the highest thing below the block's top that the
    /// block overlaps or comes within 16 of; everything whose top is at or below the line moves down by (block bottom + 16 − line).
    func makeRoom(_ id: String) {
        guard let it = content.items.first(where: { $0.id == id }) else { return }
        let b = box(of: it)
        let near = b.insetBy(dx: -16, dy: -16)
        let things = boardThings(except: id)
        guard let line = things.filter({ $0.box.minY > b.minY && $0.box.intersects(near) }).map({ $0.box.minY }).min() else {
            tell("Nothing to make room from.", brief: true)
            return
        }
        let by = b.maxY + 16 - line
        guard by > 0 else { return }
        shift(below: line, by: by, except: id, name: "Make room")
    }

    /// Push things below (the block's `push`): as it grows, what is under its old bottom moves down by the growth.
    func pushBelow(_ id: String) {
        guard let it = content.items.first(where: { $0.id == id }), it.json["push"]?.bool == true else { return }
        let b = box(of: it)
        let old = pushedBottom[id] ?? b.maxY
        pushedBottom[id] = b.maxY
        let grow = b.maxY - old
        guard abs(grow) > 0.5 else { return }
        // shrinking pulls things back only as far as they were pushed
        let by = grow > 0 ? grow : -min(-grow, pushedBy[id] ?? 0)
        guard abs(by) > 0.5 else { return }
        pushedBy[id] = max(0, (pushedBy[id] ?? 0) + by)
        shift(below: old, by: by, except: id, name: nil)
    }

    /// Puts `content.strokes` back on the canvas (the ledger keeps their ids).
    func redrawStrokes() {
        shifting = true
        canvas.drawing = ledger.drawing(content.strokes, offset: offset)
        strokeCount = canvas.drawing.strokes.count
        shifting = false
    }

    /// Undo for a change to ink and items together.
    func registerBoardUndo(strokes: [BoardStroke], items: ([BoardItem], [String: String]), _ name: String) {
        guard let um = canvas.undoManager else { return }
        um.registerUndo(withTarget: self) { me in
            me.syncStrokes()
            let nowStrokes = me.content.strokes
            let nowItems = (me.content.items, me.content.texts)
            me.content.strokes = strokes
            me.content.items = items.0
            me.content.texts = items.1
            me.redrawStrokes()
            me.registerBoardUndo(strokes: nowStrokes, items: nowItems, name)
            me.rebuildItems()
            me.writing?.place()
            me.changed()
        }
        um.setActionName(name)
    }

    // MARK: the Writing view and find (next)

    /// The Writing view: the block full screen, with its headings down the side and its word count. The same block on the board.
    func openWritingView(_ id: String) {
        endWriting()
        guard let it = content.items.first(where: { $0.id == id }) else { return }
        let session = WritingSession(board: self, item: it, fullscreen: true)
        syncStrokes()
        session.beforeStrokes = content.strokes
        let vc = WritingViewController(session: session)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    func openFind(_ id: String?) {
        let vc = FindReplaceController(board: self)
        vc.modalPresentationStyle = .formSheet
        present(vc, animated: true)
    }
}
