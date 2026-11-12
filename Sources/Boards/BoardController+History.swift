import UIKit
import PencilKit
import NexusCore

/// The board's version history log (NexusCore BoardHistory.swift, nexus docs/data-format.md Version history) and its picture
/// (thumb.png, for the notebook page's cards). After each save the recorder compares the board with the last save and appends what
/// changed to `history/<this iPad>-<month>.jsonl`; the picture is drawn again at most once a minute, and when the board closes.
final class BoardLog {
    let rec = HistoryRecorder()
    var last: BoardState?
    var thumbAt = Date.distantPast
    var thumbDirty = false
    var thumbWork: DispatchWorkItem?

    /// This device's name, as Settings › Sync has it (the log file is named by it).
    static var device: String {
        let n = (UserDefaults.standard.string(forKey: "sync.deviceName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "iPad" : n
    }

    /// The board was read (opened, or read again after another device wrote it): what is on it now is not this iPad's doing.
    func loaded(_ c: BoardContent, board: URL) {
        if last == nil {
            // the ids already in some log: erasing anything else writes it whole (`was`), so the player can show it before it went
            DispatchQueue.global(qos: .utility).async { [rec] in
                let ids = BoardHistory.knownIds(BoardHistory.readLogs(board: board))
                DispatchQueue.main.async { rec.known.formUnion(ids) }
            }
        } else {
            for it in c.items where it.type == "text" { rec.seen(id: it.id, md: c.texts[it.id] ?? "", d: BoardHistory.draftKey(it.json["draft"])) }
        }
        last = BoardState(c)
    }

    /// After a save: the lines for what changed, appended to this iPad's log file.
    func saved(_ c: BoardContent, board: URL, born: [String: Double]) {
        let now = BoardState(c)
        defer { last = now }
        guard let last, c.readOnly == nil else { return }
        rec.saved(from: last, to: now, born: born)
        let text = rec.take()
        guard !text.isEmpty else { return }
        let url = board.appendingPathComponent(BoardHistory.logFile(device: Self.device, ms: BoardHistory.now()))
        try? FolderAccess.append(url, text)
    }
}

extension BoardController {
    // MARK: the log

    func afterSave() {
        log.saved(content, board: boardURL, born: ledger.takeBorn())
        thumbSoon()
    }

    /// A keystroke in a text block (the typing editor calls this as you type, so the player shows the words letter by letter; a save
    /// alone logs only the change from one save to the next).
    func logTyping(_ id: String, _ md: String) {
        guard !readOnly, let it = content.items.first(where: { $0.id == id }) else { return }
        log.rec.typing(id: id, prev: content.texts[id], md: md, d: BoardHistory.draftKey(it.json["draft"]))
    }

    // MARK: the picture

    /// After a save: the picture now, or when the minute since the last one is up.
    func thumbSoon() {
        log.thumbDirty = true
        guard log.thumbWork == nil else { return }
        let wait = max(0, log.thumbAt.timeIntervalSinceNow + BoardThumb.every)
        if wait == 0 { writeThumb(); return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.log.thumbWork = nil
            if self.log.thumbDirty { self.writeThumb(); self.onSaved?(self.path) }
        }
        log.thumbWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    /// The board is closing: a picture still owed is written now.
    func boardClosing() {
        log.thumbWork?.cancel()
        log.thumbWork = nil
        if log.thumbDirty, !replay, FileManager.default.fileExists(atPath: boardURL.path) { writeThumb(); onSaved?(path) }
    }

    func writeThumb() {
        log.thumbDirty = false
        log.thumbAt = Date()
        guard let png = thumbPNG() else { return }
        try? FolderAccess.writeData(boardURL.appendingPathComponent(BoardThumb.file), png)
    }

    /// The board drawn 480 x 360 from the top left of what is on it (BoardThumb.frame): white paper, the items as they are on screen
    /// (PDF pages drawn where they are drawn), then the ink.
    func thumbPNG() -> Data? {
        let empty = content.items.isEmpty && canvas.drawing.strokes.isEmpty
        let b = empty ? nil : contentBounds()
        let fr = BoardThumb.frame(b.map { (Double($0.minX), Double($0.minY), Double($0.maxX), Double($0.maxY)) })
        let size = CGSize(width: BoardThumb.width, height: BoardThumb.height)
        let k = CGFloat(BoardThumb.width / fr.w)
        let rect = CGRect(x: CGFloat(fr.x) + offset.x, y: CGFloat(fr.y) + offset.y, width: CGFloat(fr.w), height: CGFloat(fr.h))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let hid = selection.isHidden
        selection.isHidden = true
        defer { selection.isHidden = hid }
        let img = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.saveGState()
            cg.scaleBy(x: k, y: k)
            cg.translateBy(x: -rect.minX, y: -rect.minY)
            world.layer.render(in: cg)
            cg.restoreGState()
            if !canvas.drawing.strokes.isEmpty {
                canvas.drawing.image(from: rect, scale: min(2, max(0.5, k * 2))).draw(in: CGRect(origin: .zero, size: size))
            }
        }
        return img.pngData()
    }

    // MARK: History

    /// The History view over the board (the board menu's Earlier versions): the board replayed from empty, Restore to here, Copy out.
    @objc func openHistory() {
        guard presentedViewController == nil else { return }
        saveNow()
        let vc = HistoryViewController(root: root, path: path, now: BoardState(content))
        vc.onRestore = { [weak self] state, when in self?.restore(state, when: when) }
        vc.onCopyOut = { [weak self] picked in self?.copyOut(picked) }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    /// The board put back as it was at a moment: one change, Undo takes it back.
    func restore(_ want: BoardState, when: Double) {
        guard !readOnly else { return }
        setBoard(want, name: "Restore")
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        toast("Back as it was on \(f.string(from: Date(timeIntervalSince1970: when / 1000))). Undo takes it back.")
    }

    /// What was picked on the old board, into this one (what is gone as it was, what changed since as a copy).
    func copyOut(_ picked: BoardState) {
        guard !readOnly else { return }
        saveNow()
        let cur = BoardState(content)
        let add = BoardHistory.copyOut(old: picked, current: cur) { taken in BoardFormat.newId(taken: taken) }
        let n = add.strokes.count + add.items.count
        guard n > 0 else { toast("That is on the board already, as it was."); return }
        var next = cur
        next.strokes += add.strokes
        next.items += add.items
        for (id, md) in add.texts { next.texts[id] = md }
        setBoard(next, name: "Copy out")
        toast(n == 1 ? "Copied 1 thing into the board" : "Copied \(n) things into the board")
    }

    /// The whole board set to `st` (strokes keep their ids), as one step Undo and Redo take back and forth.
    func setBoard(_ st: BoardState, name: String) {
        saveNow()
        let before = BoardState(content)
        applyBoard(st)
        registerBoardUndo(before, name)
        changed()
    }

    private func registerBoardUndo(_ snap: BoardState, _ name: String) {
        guard let um = canvas.undoManager else { return }
        um.registerUndo(withTarget: self) { me in
            let now = BoardState(me.content)
            me.applyBoard(snap)
            me.registerBoardUndo(now, name)
            me.changed()
        }
        um.setActionName(name)
    }

    func applyBoard(_ st: BoardState) {
        content.strokes = st.strokes
        content.items = st.items
        content.texts = st.texts
        if let id = selected, !st.items.contains(where: { $0.id == id }) { selected = nil }
        shifting = true
        canvas.drawing = ledger.drawing(st.strokes, offset: offset)
        strokeCount = canvas.drawing.strokes.count
        shifting = false
        rebuildItems()
        growIfNeeded()
    }

    // MARK: shown in the History view

    /// The replayed board at one moment (`writing`: strokes as far as they were written, drawn after the others).
    func showReplay(_ pk: [PKStroke], items: [BoardItem], texts: [String: String], itemsChanged: Bool) {
        shifting = true
        canvas.drawing = PKDrawing(strokes: pk)
        shifting = false
        if itemsChanged {
            content.items = items
            content.texts = texts
            rebuildItems()
        }
    }
}
