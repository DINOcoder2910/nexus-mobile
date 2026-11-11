import UIKit
import PencilKit
import NexusCore

/// The laptop and this iPad on one board at once (nexus docs/sync.md "Live on a board"): the laptop's words arrive without touching the
/// ink (or its undo), files sync just wrote are read at once instead of at the next 2-second check, a save first merges whatever the
/// laptop wrote meanwhile (NexusCore LiveBoard), the laptop typing in a block shows on it, and this iPad tells the hub when it draws.
final class LiveState {
    var badges: [String: UILabel] = [:]
    var observers: [NSObjectProtocol] = []
    deinit { for o in observers { NotificationCenter.default.removeObserver(o) } }
}

extension BoardController {

    func setUpLive() {
        let nc = NotificationCenter.default
        live.observers.append(nc.addObserver(forName: LivePresence.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.paintPresence() }
        })
        live.observers.append(nc.addObserver(forName: LivePresence.pulled, object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, let paths = n.object as? [String] else { return }
                if paths.contains(where: { $0.hasPrefix(self.path + "/") }) { self.checkOutside() }
            }
        })
        paintPresence()
    }

    // MARK: who is where

    func paintPresence() {
        guard isViewLoaded else { return }
        let p = LivePresence.shared.on(board: path)
        for (id, l) in live.badges where p.typing[id] == nil || itemViews[id] == nil { l.removeFromSuperview(); live.badges[id] = nil }
        for (id, device) in p.typing {
            guard let v = itemViews[id] else { continue }
            let l = live.badges[id] ?? {
                let l = UILabel()
                l.font = .systemFont(ofSize: 11, weight: .medium)
                l.textColor = .white
                l.backgroundColor = .systemBlue
                l.layer.cornerRadius = 9
                l.layer.masksToBounds = true
                l.textAlignment = .center
                textLayer.addSubview(l)
                live.badges[id] = l
                return l
            }()
            l.text = "Typing on " + (Self.isLaptop(device) ? "the laptop" : device)
            let s = l.intrinsicContentSize
            l.frame = CGRect(x: v.frame.minX - 2, y: v.frame.minY - 24, width: s.width + 14, height: 18)
        }
        if let d = p.drawing.first { navigationItem.prompt = (Self.isLaptop(d) ? "The laptop" : d) + " is drawing on this board" }
        else if navigationItem.prompt?.hasSuffix(" is drawing on this board") == true { navigationItem.prompt = nil }
    }

    static func isLaptop(_ device: String) -> Bool { device.range(of: "ipad", options: .caseInsensitive) == nil }

    /// Pencil down on the canvas: the laptop shows that this iPad is drawing here.
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        LivePresence.shared.tell(board: path, what: "drawing")
    }

    /// Typing in a block (the block editor calls this on each change): the laptop shows "Typing on the iPad" on it.
    func tellTyping(_ id: String?) {
        LivePresence.shared.tell(board: id == nil ? nil : path, block: id, what: "typing")
    }

    // MARK: outside changes without touching the ink

    /// Only blocks' words changed on disk (the laptop typing): read them into their blocks and keep the drawing as it is.
    /// -> false when something else changed too (tiles, board.json): the caller reads the whole board again.
    func takeOutsideWords(_ now: [String: String]) -> Bool {
        let changed = Set(now.keys).union(stamps.keys).filter { now[$0] != stamps[$0] }
        guard !changed.isEmpty, changed.allSatisfy({ $0.hasPrefix("text/") }) else { return false }
        var any = false
        for rel in changed {
            if let c = LiveBoard.textConflict(rel) { foldConflict(rel, c); any = true; continue }
            guard rel.hasSuffix(".md"), !rel.contains("~") else { continue } // another draft's words: nothing shown changes
            let id = String(rel.dropFirst(5).dropLast(3))
            guard content.items.contains(where: { $0.id == id && $0.type == "text" }) else { continue }
            let md = (try? String(contentsOf: boardURL.appendingPathComponent(rel), encoding: .utf8)) ?? ""
            if content.texts[id] != md { content.texts[id] = md; any = true }
            content.textsOnDisk[id] = md
        }
        stamps = now
        if any { rebuildItems(); paintPresence() }
        return true
    }

    /// A conflict copy of a block's words the hub left: folded into the block as a draft, then removed. The device named in it does
    /// this at once (its own words); another one after a minute, so the laptop and the iPad don't both fold the same copy.
    func foldConflict(_ rel: String, _ c: LiveBoard.Conflict) {
        guard !readOnly, let k = content.items.firstIndex(where: { $0.id == c.id && $0.type == "text" }) else { return }
        let mine = UserDefaults.standard.string(forKey: "sync.deviceName") ?? "iPad"
        if c.device != mine {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
            if let at = f.date(from: c.date + " " + c.time), Date().timeIntervalSince(at) < 60 { return }
        }
        let url = boardURL.appendingPathComponent(rel)
        guard let words = try? String(contentsOf: url, encoding: .utf8) else { return }
        if words != content.texts[c.id] {
            let d = LiveBoard.clashDraft(content.items[k], name: LiveBoard.clashName(c.device, c.time))
            do { try FolderAccess.write(boardURL.appendingPathComponent(d.file), words) } catch { return }
            content.items[k] = d.item
            dirty = true
            saveNow()
        }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: saving next to the laptop

    /// Before a save: what the laptop wrote meanwhile is merged in (tiles by id, words by line; a same-line clash keeps ours and
    /// makes theirs a draft). -> what to do after the save.
    func reconcileBeforeSave() throws -> LiveBoard.Reconciled {
        let board = boardURL
        return try LiveBoard.reconcile(content,
            read: { rel in try? String(contentsOf: board.appendingPathComponent(rel), encoding: .utf8) },
            write: { rel, text in try FolderAccess.write(board.appendingPathComponent(rel), text) },
            device: LivePresence.shared.lastOther ?? "the laptop")
    }

    /// After a save that merged the laptop's work: its strokes onto the canvas, its words into the blocks.
    func afterReconcile(_ r: LiveBoard.Reconciled) {
        if !r.mergedTiles.isEmpty {
            shifting = true
            canvas.drawing = ledger.drawing(content.strokes, offset: offset)
            strokeCount = canvas.drawing.strokes.count
            shifting = false
        }
        if !r.mergedTiles.isEmpty || !r.mergedTexts.isEmpty || !r.drafts.isEmpty { rebuildItems(); paintPresence() }
        if let d = r.drafts.first {
            tell("The same lines of a block changed on \(d.replacingOccurrences(of: "From ", with: "").components(separatedBy: " ").dropLast().joined(separator: " ")) at the same time. Yours stay; theirs are kept as the draft \"\(d)\".")
        }
    }

    /// The stamps after a save: the files this save wrote take their new stamp; any other file keeps the old one, so a write the
    /// laptop made meanwhile is still seen as new by the next check.
    func stampsAfterSave(wrote rels: Set<String>) -> [String: String] {
        let now = fileStamps()
        var out = stamps
        for rel in rels { out[rel] = now[rel] }
        return out
    }
}
