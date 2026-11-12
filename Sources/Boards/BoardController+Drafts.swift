import UIKit
import NexusCore

/// A block's drafts (nexus docs/data-format.md "Drafts"): tabs on the open block, New draft (the old one stays editable unless you
/// lock it), Lock / Unlock, Make current, Rename, Delete, and seeing and bringing over what changed in the old draft since.
/// Which draft is shown is this iPad's own view; making one current swaps the files (text/<id>.md is always the current draft).
extension BoardController {
    /// The key of the words this iPad shows for a block (its own view of the drafts).
    func shownKey(_ id: String) -> String {
        guard let it = content.items.first(where: { $0.id == id }) else { return id }
        return BlockDrafts.key(it, viewingDraft[id])
    }

    /// The draft shown for a block (its id), or nil for a block without drafts.
    func shownDraft(_ id: String) -> String? {
        guard let it = content.items.first(where: { $0.id == id }) else { return nil }
        let all = BlockDrafts.list(it)
        if let d = viewingDraft[id], all.contains(where: { $0.id == d }) { return d }
        return BlockDrafts.current(it)
    }

    /// Reads any draft file of the block the board doesn't hold yet (a draft another part of the app wrote straight to disk, such as
    /// the laptop's words kept after a clash), so it is never shown empty or written over.
    func loadDraftFiles(_ id: String) {
        guard let it = content.items.first(where: { $0.id == id }) else { return }
        for key in BlockDrafts.fileKeys(it) where content.texts[key] == nil {
            guard let md = try? String(contentsOf: boardURL.appendingPathComponent(BoardFormat.textFile(key)), encoding: .utf8) else { continue }
            content.texts[key] = md
            content.textsOnDisk[key] = md
        }
    }

    /// The open block's session, on the board or in the Writing view.
    func session(for id: String) -> WritingSession? {
        if let w = writing, w.id == id { return w }
        if let w = writingFull, w.id == id { return w }
        return nil
    }

    func tellLocked(_ id: String) {
        let name = content.items.first { $0.id == id }.flatMap { it in BlockDrafts.list(it).first { $0.id == shownDraft(id) }?.name } ?? "This draft"
        tell("\(name) is locked. Unlock it from Drafts to type in it.", brief: true)
    }

    /// The typing in an open block so far becomes its own undo step, before a draft change.
    func commitTyping(_ id: String) {
        guard let w = session(for: id), w.text != w.startText else { return }
        content.texts[w.key] = w.text
        registerItemsUndo(w.before, "Typing")
        w.startText = w.text
        w.before = (content.items, content.texts)
    }

    /// A drafts change as one undo step; the open block shows the words it should now.
    func changeDrafts(_ id: String, _ name: String, _ body: (BoardContent) -> BoardContent?) -> Bool {
        commitTyping(id)
        loadDraftFiles(id)
        guard let next = body(content) else { return false }
        let before = (content.items, content.texts)
        content = next
        registerItemsUndo(before, name)
        addFeature("drafts")
        afterDrafts(id)
        return true
    }

    func afterDrafts(_ id: String) {
        rebuildItems()
        if let w = session(for: id) {
            if !w.fullscreen { itemViews[id]?.alpha = 0 }
            w.reload()
        }
        changed()
    }

    // MARK: the actions

    func viewDraft(_ id: String, _ draft: String) {
        commitTyping(id)
        loadDraftFiles(id)
        guard let it = content.items.first(where: { $0.id == id }) else { return }
        viewingDraft[id] = draft == BlockDrafts.current(it) ? nil : draft
        afterDrafts(id)
    }

    /// New draft: asks for a name, and offers to lock the one it is made from.
    func newDraft(_ id: String) {
        let from = shownDraft(id)
        let fromName = content.items.first { $0.id == id }.flatMap { it in BlockDrafts.list(it).first { $0.id == from }?.name } ?? "this draft"
        let a = UIAlertController(title: "New draft", message: "A copy of \(fromName) to keep working on. \(fromName) stays as it is, and you can still edit it; changes there can be brought over later.", preferredStyle: .alert)
        a.addTextField { f in f.placeholder = "Name (optional)"; f.autocapitalizationType = .sentences }
        let make: (Bool) -> Void = { [weak self, weak a] lock in
            guard let self else { return }
            let name = a?.textFields?.first?.text
            var made: String?
            _ = self.changeDrafts(id, "New draft") { c in
                guard let r = BlockDrafts.make(c, id: id, from: from, name: name, lockOld: lock) else { return nil }
                made = r.draft
                return r.content
            }
            if made != nil {
                self.viewingDraft[id] = nil
                self.afterDrafts(id)
            }
        }
        a.addAction(UIAlertAction(title: "Make draft", style: .default) { _ in make(false) })
        a.addAction(UIAlertAction(title: "Make draft and lock \(fromName)", style: .default) { _ in make(true) })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentOver(a)
    }

    func makeCurrentDraft(_ id: String, _ draft: String) {
        _ = changeDrafts(id, "Make draft current") { BlockDrafts.makeCurrent($0, id: id, draft: draft) }
        viewingDraft[id] = nil
        afterDrafts(id)
    }

    func lockDraft(_ id: String, _ draft: String, _ locked: Bool) {
        _ = changeDrafts(id, locked ? "Lock draft" : "Unlock draft") { BlockDrafts.setLocked($0, id: id, draft: draft, locked) }
    }

    func renameDraft(_ id: String, _ draft: String) {
        let old = content.items.first { $0.id == id }.flatMap { it in BlockDrafts.list(it).first { $0.id == draft }?.name } ?? ""
        let a = UIAlertController(title: "Rename draft", message: nil, preferredStyle: .alert)
        a.addTextField { f in f.text = old; f.autocapitalizationType = .sentences; f.clearButtonMode = .whileEditing }
        a.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self, weak a] _ in
            let name = a?.textFields?.first?.text ?? ""
            _ = self?.changeDrafts(id, "Rename draft") { BlockDrafts.rename($0, id: id, draft: draft, to: name) }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentOver(a)
    }

    func deleteDraft(_ id: String, _ draft: String) {
        let name = content.items.first { $0.id == id }.flatMap { it in BlockDrafts.list(it).first { $0.id == draft }?.name } ?? "this draft"
        let a = UIAlertController(title: "Delete \(name)?", message: "Its words go with it. Undo brings it back.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }
            if self.viewingDraft[id] == draft { self.viewingDraft[id] = nil }
            _ = self.changeDrafts(id, "Delete draft") { BlockDrafts.delete($0, id: id, draft: draft) }
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        presentOver(a)
    }

    /// Bring them over: the old draft's changes since this one was made, merged in.
    func bringOver(_ id: String, into draft: String) {
        let ok = changeDrafts(id, "Bring changes over") { BlockDrafts.bringOver($0, id: id, into: draft) }
        tell(ok ? "Brought the changes over." : "Some lines were changed in both drafts, so nothing was brought over. Compare them to copy what you need.", brief: ok)
    }

    func compareDraft(_ id: String, _ draft: String) {
        commitTyping(id)
        presentOver(DraftCompareController(board: self, id: id, draft: draft))
    }

    /// Presents over whatever is showing (the Writing view, when it is open).
    func presentOver(_ vc: UIViewController) {
        var top: UIViewController = self
        while let p = top.presentedViewController { top = p }
        if vc.modalPresentationStyle != .formSheet, !(vc is UIAlertController) { vc.modalPresentationStyle = .formSheet }
        top.present(vc, animated: true)
    }

    // MARK: the menu (the formatting row's Drafts button)

    func draftMenu(_ id: String) -> [UIMenuElement] {
        loadDraftFiles(id)
        guard let it = content.items.first(where: { $0.id == id }) else { return [] }
        let all = BlockDrafts.list(it)
        let cur = BlockDrafts.current(it)
        let shown = shownDraft(id)
        var out: [UIMenuElement] = []
        if !all.isEmpty {
            out.append(UIMenu(title: "Show", options: .displayInline, children: all.map { d in
                let a = UIAction(title: d.name, image: d.locked ? UIImage(systemName: "lock.fill") : nil, state: d.id == shown ? .on : .off) { [weak self] _ in
                    self?.viewDraft(id, d.id)
                }
                a.subtitle = d.id == cur ? "Current" : nil
                return a
            }))
        }
        out.append(UIAction(title: "New draft…", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.newDraft(id) })
        guard let d = all.first(where: { $0.id == shown }) else {
            out.append(UIAction(title: "Lock", image: UIImage(systemName: "lock")) { [weak self] _ in self?.lockDraft(id, "d1", true) })
            return out
        }
        var these: [UIMenuElement] = []
        if d.id != cur {
            these.append(UIAction(title: "Make this the current draft", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                self?.makeCurrentDraft(id, d.id)
            })
        }
        if let from = d.from, let fromDraft = all.first(where: { $0.id == from }) {
            let since = BlockDrafts.changedSince(content, id: id, draft: d.id) ?? []
            if !since.isEmpty {
                let n = since.count
                these.append(UIAction(title: "Bring over changes from \(fromDraft.name)", image: UIImage(systemName: "arrow.triangle.merge")) { [weak self] _ in
                    self?.bringOver(id, into: d.id)
                })
                let a = UIAction(title: "See changes in \(fromDraft.name)", image: UIImage(systemName: "eye")) { [weak self] _ in
                    self?.compareDraft(id, d.id)
                }
                a.subtitle = n == 1 ? "1 line since this draft was made" : "\(n) lines since this draft was made"
                these.append(a)
            } else {
                these.append(UIAction(title: "Compare with \(fromDraft.name)", image: UIImage(systemName: "eye")) { [weak self] _ in
                    self?.compareDraft(id, d.id)
                })
            }
        }
        these.append(UIAction(title: d.locked ? "Unlock \(d.name)" : "Lock \(d.name)", image: UIImage(systemName: d.locked ? "lock.open" : "lock")) { [weak self] _ in
            self?.lockDraft(id, d.id, !d.locked)
        })
        these.append(UIAction(title: "Rename…", image: UIImage(systemName: "pencil")) { [weak self] _ in self?.renameDraft(id, d.id) })
        if all.count > 1 {
            these.append(UIAction(title: "Delete \(d.name)…", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.deleteDraft(id, d.id)
            })
        }
        out.append(UIMenu(title: d.name, options: .displayInline, children: these))
        return out
    }
}
