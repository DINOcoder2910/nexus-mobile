import SwiftUI
import NexusCore

/// What the sidebar's notebook tree knows about the folder, read lazily so a big data folder (a OneNote import: over a thousand
/// boards in hundreds of notebooks) never makes the sidebar slow:
/// - each notebook's own level (NexusCore `Notebook.level`, one folder listing) is read the first time its row shows, and kept;
/// - the board counts come from one walk of the notebook folders (`NotebookScan`), away from the main thread, shown when done;
/// - when the folder may have changed underneath (sync, another window), the scan's stamps are checked away from the main thread
///   (one `stat` per notebook), and only the levels that changed are read again.
/// The app's own changes (a notebook or board made, renamed, moved, deleted: `store.notebooksVersion`) drop everything at once.
@MainActor
@Observable
final class NotebookTreeModel {
    /// Goes up when what the rows show changed (a level read again, new counts): the tree draws again.
    private(set) var version = 0
    private(set) var counts: [String: Int] = [:]

    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var top: [String]?
    @ObservationIgnored private var levels: [String: NotebookLevel] = [:]
    @ObservationIgnored private var scan: NotebookScan?
    @ObservationIgnored private var checking: Task<Void, Never>?
    @ObservationIgnored private var again = false

    /// The rows for these open notebooks. Reads only the levels it hasn't kept (the rows that are new on screen).
    func rows(_ root: URL, open: Set<String>) -> [NotebookTreeRow] {
        _ = version
        use(root)
        let top = self.top ?? Notebook.top(root)
        self.top = top
        return NotebookTree.rows(top: top, open: open, counts: counts) { level($0) }
    }

    /// The rows for some notebooks only (a subject's, in the new look's sidebar), with their open notebooks inside.
    func rows(_ root: URL, top: [String], open: Set<String>) -> [NotebookTreeRow] {
        _ = version
        use(root)
        return NotebookTree.rows(top: top, open: open, counts: counts) { level($0) }
    }

    /// Where a subject's notebooks are looked for: every top notebook and the notebooks right inside it (a OneNote import's
    /// "School" notebook holds "Chemistry"). One folder listing per top notebook, kept.
    func candidates(_ root: URL) -> [String] {
        _ = version
        use(root)
        let top = self.top ?? Notebook.top(root)
        self.top = top
        return top.flatMap { [$0] + level($0).notebooks }
    }

    /// One notebook's level, read once.
    func level(_ path: String) -> NotebookLevel {
        if let l = levels[path] { return l }
        guard let root else { return NotebookLevel(path: path) }
        let l = Notebook.level(root, path)
        levels[path] = l
        return l
    }

    /// The notebook for a row's menu: its own level (Delete reads the rest when asked).
    func notebook(_ path: String) -> Notebook { level(path).shallow }

    /// The app changed the notebooks itself: read everything again.
    func dropAll() {
        levels = [:]
        top = nil
        version += 1
        check(full: true)
    }

    /// The folder may have changed underneath: look (away from the main thread) and read again only what changed.
    func check(full: Bool = false) {
        guard let root else { return }
        if checking != nil { again = true; if full { scan = nil }; return }
        let old = full ? nil : scan
        checking = Task.detached(priority: .utility) { [weak self] in
            // the stamps first (a stat per notebook): nothing more when nothing changed
            if let old, old.changed(root).isEmpty {
                await self?.done(root, nil)
                return
            }
            let now = NotebookScan.read(root)
            await self?.done(root, now)
        }
    }

    private func done(_ root: URL, _ now: NotebookScan?) {
        checking = nil
        if let now, root == self.root {
            var redraw = false
            if let old = scan {
                for p in now.changed(from: old) {
                    if p == BoardFormat.notebooks, top != nil { top = nil; redraw = true }
                    if levels.removeValue(forKey: p) != nil { redraw = true }
                }
            }
            scan = now
            if now.counts != counts { counts = now.counts; redraw = true }
            if redraw { version += 1 }
        }
        if again { again = false; check() }
    }

    private func use(_ root: URL) {
        guard root != self.root else { return }
        self.root = root
        levels = [:]
        top = nil
        scan = nil
        if !counts.isEmpty { counts = [:] }
        checking?.cancel()
        checking = nil
        // counted after this draw
        DispatchQueue.main.async { [weak self] in self?.check(full: true) }
    }
}
