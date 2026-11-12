import UIKit
import PencilKit
import NexusCore

/// Marks on the board (nexus docs/data-format.md "Marks"): comments that hold on to words (typed or handwritten bubbles), ink
/// attached to text that follows its words, and ghosts for marks whose words are gone (Re-pin / Remove). Shown or hidden together,
/// on this iPad only.
extension BoardController {
    static let marksShownKey = "board.marksShown"

    var marksShown: Bool {
        get { UserDefaults.standard.object(forKey: BoardController.marksShownKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: BoardController.marksShownKey)
            rebuildItems()
        }
    }

    var deviceName: String { UserDefaults.standard.string(forKey: "sync.deviceName") ?? "iPad" }

    // MARK: where a mark is

    /// Where a mark's words are in their block (board units), or nil when it doesn't hold on to words. `ghost` when they are gone:
    /// the rect is then the line where it waits.
    func wordsRect(_ m: BoardItem) -> (rect: CGRect, ghost: Bool)? {
        guard let on = BoardMarks.on(m), let at = BoardMarks.anchor(m),
              let block = content.items.first(where: { $0.id == on && $0.type == "text" }) else { return nil }
        let md = content.texts[shownKey(on)] ?? ""
        let layout = TextBlockRender.layout(md, item: block)
        let found = Anchor.find(md, at)
        let range = found.map { NSRange(location: $0.from, length: max(1, $0.to - $0.from)) }
            ?? NSRange(location: min(Anchor.ghostAt(md, at), max(0, (md as NSString).length - 1)), length: (md as NSString).length > 0 ? 1 : 0)
        var r = layout.rect(of: range)
        if r.isNull { r = CGRect(x: 0, y: 0, width: 1, height: 16) }
        r = r.offsetBy(dx: block.x + layout.padding.x, dy: block.y + layout.padding.y)
        return (r, found == nil)
    }

    /// The bubble's spot (its top-left, board units): beside the words' first line, just right of the block; a ghost sits just
    /// above the line where it waits; a mark without words at its own x, y.
    func markSpot(_ m: BoardItem) -> (point: CGPoint, ghost: Bool) {
        guard let w = wordsRect(m), let on = BoardMarks.on(m), let block = content.items.first(where: { $0.id == on }) else {
            return (CGPoint(x: m.x, y: m.y), false)
        }
        let b = box(of: block)
        if w.ghost { return (CGPoint(x: w.rect.minX, y: w.rect.minY - MarkView.size - 2), true) }
        return (CGPoint(x: b.maxX + 6, y: w.rect.minY + max(0, (min(w.rect.height, 30) - MarkView.size) / 2)), false)
    }

    /// The words each block's comments sit on (for a faint underline in the block), in the block's markdown.
    func markedRanges(_ blockId: String) -> [NSRange] {
        guard marksShown else { return [] }
        let md = content.texts[shownKey(blockId)] ?? ""
        return BoardMarks.marks(on: blockId, content.items).compactMap { m in
            guard BoardMarks.kind(m) == "bubble", !BoardMarks.isDone(m), let at = BoardMarks.anchor(m), let f = Anchor.find(md, at) else { return nil }
            return NSRange(location: f.from, length: f.to - f.from)
        }
    }

    /// Lays out one mark's view (called from rebuildItems).
    func placeMark(_ m: BoardItem) {
        guard BoardMarks.kind(m) == "bubble" else {
            // ink marks are strokes on the canvas; nothing else to show
            itemViews[m.id]?.removeFromSuperview(); itemViews[m.id] = nil
            return
        }
        let v = (itemViews[m.id] as? MarkView) ?? MarkView(frame: .zero)
        if v.superview == nil { textLayer.addSubview(v); itemViews[m.id] = v }
        textLayer.bringSubviewToFront(v)
        let spot = markSpot(m)
        v.update(m, ghost: spot.ghost)
        v.isHidden = !marksShown
        v.frame.origin = CGPoint(x: spot.point.x + offset.x, y: spot.point.y + offset.y)
        markBoxes[m.id] = CGRect(origin: spot.point, size: v.frame.size)
    }

    // MARK: making comments

    /// Comment on words of a block (the open block's selection): makes the mark and opens it to type or write.
    func addComment(on blockId: String, range: NSRange) {
        guard !readOnly else { return }
        commitTyping(blockId)
        let md = content.texts[shownKey(blockId)] ?? ""
        let len = (md as NSString).length
        var r = NSRange(location: min(range.location, len), length: 0)
        r.length = min(range.length, len - r.location)
        if r.length == 0 { r = wordRange(md, at: r.location) }
        let id = BoardFormat.newId(taken: allIds)
        let at = Anchor.make(md, from: r.location, to: r.location + r.length)
        var m = BoardMarks.make(id: id, kind: "bubble", on: blockId, at: at, x: 0, y: 0, text: "", by: deviceName)
        content.items.append(m)
        let spot = markSpot(m)
        content.items.removeLast()
        m = m.with("x", .number(spot.point.x.rounded())).with("y", .number(spot.point.y.rounded()))
        changeItems("Comment") { $0.items.append(m) }
        addFeature("marks")
        if !marksShown { marksShown = true }
        openMark(id, new: true)
    }

    /// A comment pinned to a spot on the board (no words).
    func addComment(at p: CGPoint) {
        guard !readOnly else { return }
        let id = BoardFormat.newId(taken: allIds)
        let m = BoardMarks.make(id: id, kind: "bubble", on: nil, at: nil, x: p.x, y: p.y, text: "", by: deviceName)
        changeItems("Comment") { $0.items.append(m) }
        addFeature("marks")
        if !marksShown { marksShown = true }
        openMark(id, new: true)
    }

    /// The word around an offset (for a comment with nothing selected).
    func wordRange(_ md: String, at i: Int) -> NSRange {
        let s = md as NSString
        guard s.length > 0 else { return NSRange(location: 0, length: 0) }
        var a = min(i, s.length), b = min(i, s.length)
        let letters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’-"))
        func isWord(_ k: Int) -> Bool { k >= 0 && k < s.length && UnicodeScalar(s.character(at: k)).map { letters.contains($0) } == true }
        while isWord(a - 1) { a -= 1 }
        while isWord(b) { b += 1 }
        if a == b { // between words: the rest of the line
            let line = s.lineRange(for: NSRange(location: min(i, s.length - 1), length: 0))
            return NSRange(location: line.location, length: max(0, line.length - (s.substring(with: line).hasSuffix("\n") ? 1 : 0)))
        }
        return NSRange(location: a, length: b - a)
    }

    func openMark(_ id: String, new: Bool = false) {
        guard content.items.contains(where: { $0.id == id }) else { return }
        let vc = MarkController(board: self, id: id, new: new)
        if let v = itemViews[id], v.window != nil {
            vc.modalPresentationStyle = .popover
            vc.popoverPresentationController?.sourceView = v
            vc.popoverPresentationController?.sourceRect = v.bounds
            vc.preferredContentSize = CGSize(width: 380, height: 460)
        } else {
            vc.modalPresentationStyle = .formSheet
        }
        var top: UIViewController = self
        while let p = top.presentedViewController { top = p }
        top.present(vc, animated: true)
    }

    /// Changes one mark as one undo step.
    func changeMark(_ id: String, _ name: String, _ body: (BoardItem) -> BoardItem?) {
        guard let k = content.items.firstIndex(where: { $0.id == id }) else { return }
        let next = body(content.items[k])
        changeItems(name) { c in
            if let next { c.items[k] = next } else { c.items.remove(at: k) }
        }
    }

    /// Re-pin a ghost to the line where it waits.
    func repin(_ id: String) {
        guard let m = content.items.first(where: { $0.id == id }), let on = BoardMarks.on(m), let at = BoardMarks.anchor(m) else { return }
        let md = content.texts[shownKey(on)] ?? ""
        let s = md as NSString
        guard s.length > 0 else { tell("That block has no words to pin to.", brief: true); return }
        let line = s.lineRange(for: NSRange(location: min(Anchor.ghostAt(md, at), s.length - 1), length: 0))
        let end = line.location + line.length - (s.substring(with: line).hasSuffix("\n") ? 1 : 0)
        let next = Anchor.make(md, from: line.location, to: max(line.location, end))
        changeMark(id, "Re-pin") { $0.with("at", next.json) }
    }

    // MARK: keeping marks with their words

    /// After a block's words changed: its marks' anchors follow the words, and ink attached to them moves with them.
    func marksAfterTyping(_ blockId: String) {
        let md = content.texts[blockId] ?? ""
        let next = BoardMarks.refreshed(content.items, block: blockId, words: md)
        if next != content.items { content.items = next; changed() }
        followInkMarks()
    }

    /// Ink attached to text: where its words are now against where they were when the strokes were written; the strokes follow.
    func followInkMarks() {
        guard !canvas.isTracking else { return }
        var c = content
        var moved = false
        for m in content.items where BoardMarks.isMark(m) && BoardMarks.kind(m) == "ink" {
            guard let w = wordsRect(m), !w.ghost else { continue }
            let to = (x: Double(w.rect.minX).rounded(), y: Double(w.rect.minY).rounded())
            if to.x != m.x || to.y != m.y {
                if !moved { syncStrokes(); c = content }
                c = BoardMarks.follow(c, mark: m.id, to: to)
                moved = true
            }
        }
        guard moved else { return }
        content = c
        redrawStrokes()
        changed()
    }

    /// Attach to text (the Select tool's menu): the strokes become an ink mark on the words they are nearest to, and from then on
    /// move with those words. False when no block is near.
    @discardableResult
    func attachToText(_ strokeIds: Set<String>) -> Bool {
        syncStrokes()
        var bounds = CGRect.null
        for s in content.strokes where strokeIds.contains(s.id) {
            for p in s.points where p.count >= 2 { bounds = bounds.union(CGRect(x: p[0], y: p[1], width: 0.1, height: 0.1)) }
        }
        guard !bounds.isNull else { return false }
        // the nearest block (by distance between boxes)
        let blocks = content.items.filter { $0.type == "text" }
        func gap(_ r: CGRect) -> CGFloat {
            let dx = max(0, max(r.minX - bounds.maxX, bounds.minX - r.maxX)), dy = max(0, max(r.minY - bounds.maxY, bounds.minY - r.maxY))
            return hypot(dx, dy)
        }
        guard let block = blocks.min(by: { gap(box(of: $0)) < gap(box(of: $1)) }), gap(box(of: block)) < 200 else {
            tell("Draw the ink next to some words to attach it to them.", brief: true)
            return false
        }
        let md = content.texts[shownKey(block.id)] ?? ""
        let layout = TextBlockRender.layout(md, item: block)
        let origin = CGPoint(x: block.x + layout.padding.x, y: block.y + layout.padding.y)
        let mid = CGPoint(x: bounds.midX - origin.x, y: bounds.midY - origin.y)
        let from = layout.characterIndex(at: CGPoint(x: bounds.minX - origin.x, y: mid.y))
        let to = layout.characterIndex(at: CGPoint(x: bounds.maxX - origin.x, y: mid.y))
        var r = NSRange(location: min(from, to), length: abs(to - from))
        let a = wordRange(md, at: r.location), b = wordRange(md, at: r.location + r.length)
        r = NSUnionRange(a, b)
        guard r.length > 0 else { return false }
        let rect = layout.rect(of: r).offsetBy(dx: origin.x, dy: origin.y)
        let id = BoardFormat.newId(taken: allIds)
        let before = content.strokes
        let beforeItems = (content.items, content.texts)
        content = BoardMarks.attach(content, strokes: strokeIds, mark: id, on: block.id, words: md, from: r.location, to: r.location + r.length,
                                    x: Double(rect.minX).rounded(), y: Double(rect.minY).rounded(), by: deviceName)
        redrawStrokes()
        registerBoardUndo(strokes: before, items: beforeItems, "Attach to text")
        addFeature("marks")
        rebuildItems()
        changed()
        tell("Attached to “\(BoardMarks.anchor(content.items.last!)?.q ?? "")”. The ink now moves with those words.", brief: true)
        return true
    }

    func detachInk(_ markId: String) {
        syncStrokes()
        let before = content.strokes
        let beforeItems = (content.items, content.texts)
        content = BoardMarks.detach(content, mark: markId)
        redrawStrokes()
        registerBoardUndo(strokes: before, items: beforeItems, "Detach from text")
        rebuildItems()
        changed()
    }

    /// The ink mark a stroke belongs to, if any (for the Select tool: offer Detach instead of Attach).
    func inkMark(ofStroke id: String) -> String? {
        content.strokes.first { $0.id == id }.flatMap(BoardMarks.strokeMark)
    }

    // MARK: the comments list

    func openComments() {
        let list = CommentsListController(board: self)
        list.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak list] _ in list?.dismiss(animated: true) })
        let vc = UINavigationController(rootViewController: list)
        vc.modalPresentationStyle = .formSheet
        var top: UIViewController = self
        while let p = top.presentedViewController { top = p }
        top.present(vc, animated: true)
    }

    /// Scroll so a mark is in view and open it.
    func goToMark(_ id: String) {
        guard let m = content.items.first(where: { $0.id == id }) else { return }
        let p = markSpot(m).point
        let z = canvas.zoomScale
        scroll(toBoard: CGPoint(x: p.x - view.bounds.width / 2 / z, y: p.y - view.bounds.height / 3 / z))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.openMark(id) }
    }
}
