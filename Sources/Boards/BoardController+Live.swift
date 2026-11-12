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
        // copies first, then .jsonl files: the other device writes both, and its .jsonl then says the words its copy already brought
        for rel in changed.sorted(by: { ($0.hasSuffix(".jsonl") ? 1 : 0, $0) < ($1.hasSuffix(".jsonl") ? 1 : 0, $1) }) {
            if let c = LiveBoard.textConflict(rel) { foldConflict(rel, c); any = true; continue }
            if rel.hasSuffix(".jsonl"), !rel.contains("~") { if takeOutsideDoc(rel) { any = true }; continue }
            guard rel.hasSuffix(".md"), !rel.contains("~") else { continue } // another draft's words: nothing shown changes
            let id = String(rel.dropFirst(5).dropLast(3))
            guard content.items.contains(where: { $0.id == id && $0.type == "text" }) else { continue }
            let md = RichWords.body((try? String(contentsOf: boardURL.appendingPathComponent(rel), encoding: .utf8)) ?? "")
            let base = content.textsOnDisk[id]
            content.textsOnDisk[id] = md
            if let took = takeRemoteInOpenBlock(id: id, base: base, theirs: md) {
                // the block is open for typing: merged into it live, or (the same lines changed here) theirs kept as a draft
                if !took { keepAsDraft(id: id, words: md) }
                continue
            }
            if content.texts[id] != md { content.texts[id] = md; any = true }
        }
        stamps = now
        if any { rebuildItems(); paintPresence() }
        return true
    }

    /// A block's .jsonl written elsewhere (the hub's Google Docs bridge writes only that file; the laptop writes it beside the copy): it
    /// becomes the file this iPad's next save follows (ids, the Google link), and its words, when they differ, come in as the copy's do; the
    /// copy is then written again with the next save, as the laptop does (nexus app/board.js B.outside). -> whether a block's words changed.
    func takeOutsideDoc(_ rel: String) -> Bool {
        let id = String(rel.dropFirst(5).dropLast(6))
        guard content.items.contains(where: { $0.id == id && $0.type == "text" }),
              let jsonl = try? String(contentsOf: boardURL.appendingPathComponent(rel), encoding: .utf8),
              jsonl != content.docsOnDisk[id], let words = RichWords.shared.words(jsonl) else { return false }
        let base = content.docWords[id] ?? content.textsOnDisk[id]
        content.docsOnDisk[id] = jsonl
        content.docWords[id] = words
        content.docsStale.remove(id)
        let open = writing.map { $0.id == id && $0.key == id } ?? false
        let mine = open ? (writing?.text ?? "") : (content.texts[id] ?? "")
        if words == mine { return false }
        if let took = takeRemoteInOpenBlock(id: id, base: base, theirs: words) {
            if !took { keepAsDraft(id: id, words: words) }
            changed() // (the copy follows the .jsonl's words)
            return false
        }
        content.texts[id] = LiveBoard.mergeBlock(base: base, mine: mine, theirs: words) ?? words
        changed()
        return true
    }

    /// The block `id` is open for typing: merge the laptop's words into it (true), a clash (false: ours stay), or nil when that block
    /// isn't open. The board writing thread's WritingSession does the merge (`writing?.takeRemote(base:theirs:)`).
    func takeRemoteInOpenBlock(id: String, base: String?, theirs: String) -> Bool? {
        // only when the open block is showing its current draft (another draft's words are another file)
        guard let w = writing, w.id == id, w.key == id else { return nil }
        return w.takeRemote(base: base, theirs: theirs)
    }

    /// Keep `words` as a draft of block `id` (the laptop's, after a clash); the block's words stay as they are.
    func keepAsDraft(id: String, words: String) {
        guard !readOnly, let k = content.items.firstIndex(where: { $0.id == id }) else { return }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let name = LiveBoard.clashName(LivePresence.shared.lastOther ?? "the laptop", f.string(from: Date()))
        let d = LiveBoard.clashDraft(content.items[k], name: name)
        do { try FolderAccess.write(boardURL.appendingPathComponent(d.file), words) } catch { return }
        content.items[k] = d.item
        if BoardFormat.features.contains("drafts"), let m = content.meta { content.meta = BoardFormat.withFeature(m, "drafts") }
        changed()
        tell("The same lines of a block changed on the laptop at the same time. Yours stay; theirs are kept as the draft \"\(name)\".")
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
        guard let file = try? String(contentsOf: url, encoding: .utf8) else { return }
        // a rich block's conflict copy is a .jsonl: its words as the block holds them
        guard let words = c.ext == ".jsonl" ? RichWords.shared.words(file) : RichWords.body(file) else { return }
        let drafts = content.items[k].json["drafts"]?.array?.compactMap { $0["id"]?.string } ?? []
        if words != content.texts[c.id], !drafts.contains(where: { content.texts[c.id + "~" + $0] == words }) {
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
