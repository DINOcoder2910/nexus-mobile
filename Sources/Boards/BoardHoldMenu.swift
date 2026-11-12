import UIKit
import PencilKit
import NexusCore

/// Taps and holds on the board: a tap picks what is under it and does nothing on empty board; touching and holding something shows
/// its menu (a block, a picture, a shape, a PDF, a comment, tape, or ink, which can be attached to the words beside it). PencilKit's
/// own "Select All / Insert Space" callout is turned off, except with the Select tool, where it is the lasso's menu.
private var holdMenuKey: UInt8 = 0
private var holdSpotKey: UInt8 = 0

extension BoardController: UIEditMenuInteractionDelegate {
    /// What the menu is for: an item, or ink strokes (their ids).
    enum HoldTarget {
        case item(String)
        case ink(Set<String>)
    }

    private var holdMenu: UIEditMenuInteraction {
        if let m = objc_getAssociatedObject(self, &holdMenuKey) as? UIEditMenuInteraction { return m }
        let m = UIEditMenuInteraction(delegate: self)
        canvas.addInteraction(m)
        objc_setAssociatedObject(self, &holdMenuKey, m, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return m
    }

    private var holdTarget: HoldTarget? {
        get { objc_getAssociatedObject(self, &holdSpotKey) as? HoldTarget }
        set { objc_setAssociatedObject(self, &holdSpotKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Turns off PencilKit's own tap and hold callouts (they are its gestures on the canvas and its tiles, not ours), except with the
    /// Select tool. Called whenever the tool changes and on each tap, since PencilKit adds some of them lazily.
    func quietCanvasMenus() {
        let lasso = BoardTools.shared.tool == .lasso
        let skip: [UIView] = [world, overWorld]
        func walk(_ v: UIView) {
            for g in v.gestureRecognizers ?? [] where g.delegate !== self && g !== canvas.drawingGestureRecognizer
                && (g is UITapGestureRecognizer || g is UILongPressGestureRecognizer) {
                if g.isEnabled != lasso { g.isEnabled = lasso }
            }
            for s in v.subviews where !skip.contains(where: { $0 === s }) { walk(s) }
        }
        walk(canvas)
    }

    /// Touch and hold: pick what is there and show its menu; nothing on empty board.
    func showHoldMenu(_ g: UIGestureRecognizer) {
        let p = boardPoint(g)
        if let it = hitItem(p, pdf: true) {
            selected = it.id
            holdTarget = .item(it.id)
        } else if let ink = inkCluster(at: p) {
            selected = nil
            holdTarget = .ink(ink)
        } else {
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        holdMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: g.location(in: canvas)))
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let t = holdTarget else { return nil }
        switch t {
        case .item(let id): return UIMenu(children: itemHoldMenu(id))
        case .ink(let ids): return UIMenu(children: inkHoldMenu(ids))
        }
    }

    // MARK: menus

    func itemHoldMenu(_ id: String) -> [UIMenuElement] {
        guard let it = content.items.first(where: { $0.id == id }) else { return [] }
        var out: [UIMenuElement] = []
        let delete = UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.selected = id
            self?.deleteSelected()
        }
        switch it.type {
        case "text":
            if !readOnly {
                out.append(UIAction(title: "Type", image: UIImage(systemName: "character.cursor.ibeam")) { [weak self] _ in self?.edit(it) })
                out.append(UIAction(title: "Writing view", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.openWritingView(id) })
            }
            out.append(UIAction(title: "Copy words", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                guard let self else { return }
                UIPasteboard.general.string = self.content.texts[self.shownKey(id)] ?? ""
            })
            if !readOnly {
                let chip = it.json["chip"]?.bool == true
                out.append(UIAction(title: chip ? "Unfold" : "Fold into a chip", image: UIImage(systemName: chip ? "rectangle.expand.vertical" : "rectangle.compress.vertical")) { [weak self] _ in
                    self?.setBlockField(id, "chip", chip ? nil : .bool(true))
                })
                out.append(UIAction(title: "Cover with revision tape", image: UIImage(systemName: "rectangle.dashed")) { [weak self] _ in self?.tapeBlock(id) })
                out.append(UIAction(title: "Make room", image: UIImage(systemName: "arrow.down.to.line")) { [weak self] _ in self?.makeRoom(id) })
                out.append(UIMenu(title: "", options: .displayInline, children: [delete]))
            }
        case "mark":
            out.append(UIAction(title: "Open", image: UIImage(systemName: "text.bubble")) { [weak self] _ in self?.selected = nil; self?.openMark(id) })
            if BoardMarks.kind(it) == "ink", !readOnly {
                out.append(UIAction(title: "Detach from text", image: UIImage(systemName: "link.badge.plus")) { [weak self] _ in
                    self?.selected = nil
                    self?.detachInk(id)
                })
            }
            if !readOnly { out.append(delete) }
        case "tape":
            out.append(UIAction(title: peeking.contains(id) ? "Cover again" : "Peek", image: UIImage(systemName: "eye")) { [weak self] _ in self?.togglePeek(id) })
            if !readOnly {
                out.append(UIAction(title: "Remove tape", image: UIImage(systemName: "xmark"), attributes: .destructive) { [weak self] _ in
                    self?.selected = nil
                    self?.removeTape(id)
                })
            }
        default:
            if !readOnly { out.append(delete) }
        }
        return out
    }

    func inkHoldMenu(_ ids: Set<String>) -> [UIMenuElement] {
        guard !readOnly else { return [] }
        let marks = Set(ids.compactMap { inkMark(ofStroke: $0) })
        if let m = marks.first, marks.count == 1 {
            return [UIAction(title: "Detach from text", image: UIImage(systemName: "link.badge.plus")) { [weak self] _ in self?.detachInk(m) }]
        }
        return [UIAction(title: "Attach to text", subtitle: "It moves with the words beside it", image: UIImage(systemName: "link")) { [weak self] _ in
            self?.attachToText(ids)
        }]
    }

    // MARK: ink under a finger

    /// The ink under a point and the strokes touching it (a word or a drawing written in one go), or nil when there is none.
    func inkCluster(at p: CGPoint) -> Set<String>? {
        syncStrokes()
        let reach = 14 / max(canvas.zoomScale, 0.1)
        func box(_ s: BoardStroke) -> CGRect {
            var r = CGRect.null
            for q in s.points where q.count >= 2 { r = r.union(CGRect(x: q[0], y: q[1], width: 0.1, height: 0.1)) }
            return r
        }
        let all = content.strokes.map { ($0, box($0)) }.filter { !$0.1.isNull }
        guard let hit = all.first(where: { s, r in
            r.insetBy(dx: -reach, dy: -reach).contains(p) && s.points.contains { $0.count >= 2 && hypot($0[0] - p.x, $0[1] - p.y) < reach }
        }) else { return nil }
        var ids: Set<String> = [hit.0.id]
        var area = hit.1
        var grew = true
        while grew && ids.count < 400 {
            grew = false
            for (s, r) in all where !ids.contains(s.id) && r.intersects(area.insetBy(dx: -10, dy: -10)) {
                ids.insert(s.id)
                area = area.union(r)
                grew = true
            }
        }
        return ids
    }
}
