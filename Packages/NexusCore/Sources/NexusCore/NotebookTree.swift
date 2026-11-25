import Foundation

/// One notebook folder on its own (`Notebook.level`): what the sidebar's tree reads for each notebook it shows, and nothing deeper.
public struct NotebookLevel: Hashable {
    /// The folder, relative to the data folder ("notebooks/Chem/R3").
    public var path: String
    /// Its colour from `notebook.json` (`#RRGGBB`), or nil.
    public var color: String?
    /// The notebooks in it (their paths), then its boards, each in the notebook page's order.
    public var notebooks: [String]
    public var boards: [Notebook.BoardRef]

    public init(path: String, color: String? = nil, notebooks: [String] = [], boards: [Notebook.BoardRef] = []) {
        self.path = path; self.color = color; self.notebooks = notebooks; self.boards = boards
    }

    public var name: String { (path as NSString).lastPathComponent }
    /// 0 for a top-level notebook ("notebooks/Chem").
    public var depth: Int { max(0, path.split(separator: "/").count - 2) }
    public var isEmpty: Bool { notebooks.isEmpty && boards.isEmpty }
    /// The notebook with only this level filled in (its notebooks' own contents aren't read).
    public var shallow: Notebook {
        Notebook(name: name, path: path, depth: depth, color: color, boards: boards,
                 notebooks: notebooks.map { Notebook(name: ($0 as NSString).lastPathComponent, path: $0, depth: depth + 1) })
    }
}

/// The sidebar's notebook tree as a flat list of rows: notebooks, the notebooks inside them (any depth) and their boards, each
/// level opened and closed with its arrow. The order is `Notebook.list`'s, the notebook page's: in a notebook, its notebooks first,
/// then its boards, each in `notebook.json`'s `order` (OneNote's, from the laptop's import), the rest by name.
public struct NotebookTreeRow: Identifiable, Hashable {
    public enum Kind: Hashable { case notebook, board }
    public var kind: Kind
    public var name: String
    /// The folder, relative to the data folder ("notebooks/Chem/R3/Lesson 1.board").
    public var path: String
    /// 0 for a top-level notebook; a board is one deeper than its notebook.
    public var depth: Int
    /// A top-level notebook's colour (`#RRGGBB`), else nil.
    public var color: String?
    /// A notebook with notebooks or boards in it: it has an arrow.
    public var hasChildren: Bool
    /// A notebook shown open (its rows follow).
    public var isOpen: Bool
    /// A notebook's boards, those in the notebooks inside it too, once counted (`NotebookScan`); nil until then and for a board.
    public var boardCount: Int?
    public var id: String { path }

    public init(kind: Kind, name: String, path: String, depth: Int, color: String? = nil, hasChildren: Bool = false,
                isOpen: Bool = false, boardCount: Int? = nil) {
        self.kind = kind; self.name = name; self.path = path; self.depth = depth; self.color = color
        self.hasChildren = hasChildren; self.isOpen = isOpen; self.boardCount = boardCount
    }
}

/// One notebook on the way down to the one the sidebar is inside (`NotebookTree.crumbs`).
public struct NotebookCrumb: Hashable, Identifiable, Sendable {
    public var name: String
    public var path: String
    public var id: String { path }
}

public enum NotebookTree {
    /// The rows to show: every top-level notebook (`top`), and inside each open one its notebooks (and theirs, when open), then its
    /// boards. Lazy: `level` is asked only for the notebooks that get a row (to know their arrow and, when open, what follows), so a
    /// closed notebook's insides are never read, however many boards a data folder holds.
    public static func rows(top: [String], open: Set<String>, counts: [String: Int] = [:],
                            level: (String) -> NotebookLevel) -> [NotebookTreeRow] {
        var out: [NotebookTreeRow] = []
        func add(_ path: String) {
            let l = level(path)
            let isOpen = !l.isEmpty && open.contains(path)
            out.append(NotebookTreeRow(kind: .notebook, name: l.name, path: path, depth: l.depth,
                                       color: l.depth == 0 ? l.color : nil, hasChildren: !l.isEmpty, isOpen: isOpen,
                                       boardCount: counts[path]))
            guard isOpen else { return }
            l.notebooks.forEach(add)
            for b in l.boards {
                out.append(NotebookTreeRow(kind: .board, name: b.name, path: b.path, depth: l.depth + 1))
            }
        }
        top.forEach(add)
        return out
    }

    /// The same, read straight from a data folder (each level read once).
    public static func rows(root: URL, open: Set<String>, counts: [String: Int] = [:]) -> [NotebookTreeRow] {
        rows(top: Notebook.top(root), open: open, counts: counts) { Notebook.level(root, $0) }
    }

    /// The notebooks that hold `path` (a board or a notebook), outermost first: the ones to open so its row shows.
    /// "notebooks/A/B/x.board" -> ["notebooks/A", "notebooks/A/B"]. Nothing for a path outside `notebooks/`.
    public static func ancestors(of path: String) -> [String] {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 2, parts[0] == BoardFormat.notebooks else { return [] }
        return (2..<parts.count).map { parts[0..<$0].joined(separator: "/") }
    }

    /// The open notebooks as the app keeps them ("a|b|c": `|` can't be in a Windows name), and back (sorted).
    public static func parse(_ text: String) -> Set<String> {
        Set(text.split(separator: "|").map(String.init))
    }

    public static func join(_ open: Set<String>) -> String {
        open.sorted().joined(separator: "|")
    }

    /// `text` with `path` opened or closed.
    public static func setting(_ path: String, open isOpen: Bool, in text: String) -> String {
        var open = parse(text)
        if isOpen { open.insert(path) } else { open.remove(path) }
        return join(open)
    }

    /// `text` with the notebooks that hold `path` opened too; the same text when they already are.
    public static func revealing(_ path: String, in text: String) -> String {
        let open = parse(text)
        let more = open.union(ancestors(of: path))
        return more == open ? text : join(more)
    }

    /// `text` with the notebook `path` opened and the notebooks beside it closed, with whatever was open inside them, so one branch
    /// is open at each level and the tree stays short (a OneNote import's sections hold dozens of boards each). What is open inside
    /// `path` itself stays open.
    public static func opening(_ path: String, in text: String) -> String {
        let open = parse(text)
        let parent = (path as NSString).deletingLastPathComponent
        var out = open.filter { p in !(p.hasPrefix(parent + "/") && p != path && !p.hasPrefix(path + "/")) }
        out.insert(path)
        return out == open ? text : join(out)
    }

    /// `text` with the notebooks that hold `path` (a board or a notebook) opened, each closing the notebooks beside it (`opening`):
    /// a board opened from anywhere shows in the tree with only its own branch open. What is open inside its notebook stays open.
    public static func focusing(_ path: String, in text: String) -> String {
        var t = text
        for a in ancestors(of: path) { t = opening(a, in: t) }
        return t
    }

    /// The notebooks of an already read tree (`Notebook.list`) as rows, without their boards: Move to…'s tree. A notebook's rows
    /// follow it when it is open; each counts its boards (and those of the notebooks inside it).
    public static func rows(notebooks tree: [Notebook], open: Set<String>) -> [NotebookTreeRow] {
        var out: [NotebookTreeRow] = []
        func add(_ nb: Notebook) {
            let has = !nb.notebooks.isEmpty
            let isOpen = has && open.contains(nb.path)
            out.append(NotebookTreeRow(kind: .notebook, name: nb.name, path: nb.path, depth: nb.depth,
                                       color: nb.depth == 0 ? nb.color : nil, hasChildren: has, isOpen: isOpen,
                                       boardCount: nb.boardTotal))
            if isOpen { nb.notebooks.forEach(add) }
        }
        tree.forEach(add)
        return out
    }

    // MARK: stepping inside a notebook (the sidebar, Nov 25 2026)

    /// A notebook that holds one notebook and nothing else (a OneNote import's section group with one section): stepping in goes
    /// straight through it, and Back skips it.
    public static func passesThrough(_ l: NotebookLevel) -> Bool { l.boards.isEmpty && l.notebooks.count == 1 }

    /// The notebook the sidebar shows when stepping into `path`: `path` itself or, while it only holds one notebook, the one inside.
    public static func stepping(into path: String, level: (String) -> NotebookLevel) -> String {
        var p = path
        for _ in 0..<32 {
            let l = level(p)
            guard passesThrough(l), let only = l.notebooks.first else { break }
            p = only
        }
        return p
    }

    /// Where Back goes from the notebook `path`: the notebook that holds it, past the ones that only hold one notebook; nil for the
    /// full list (from a top-level notebook, or a path outside `notebooks/`).
    public static func steppingBack(from path: String, level: (String) -> NotebookLevel) -> String? {
        var a = ancestors(of: path)
        while let p = a.last, passesThrough(level(p)) { a.removeLast() }
        return a.last
    }

    /// The notebooks from the top one down to `path` itself, each with its name: the sidebar's crumbs inside a notebook.
    public static func crumbs(_ path: String) -> [NotebookCrumb] {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == BoardFormat.notebooks else { return [] }
        return (2...parts.count).map { NotebookCrumb(name: parts[$0 - 1], path: parts[0..<$0].joined(separator: "/")) }
    }

    /// `text` after a notebook or board moved or was renamed from `from` to `to`: the open notebooks at or under it follow it.
    public static func renaming(_ from: String, to: String, in text: String) -> String {
        let open = parse(text)
        let moved = Set(open.map { p -> String in
            if p == from { return to }
            if p.hasPrefix(from + "/") { return to + p.dropFirst(from.count) }
            return p
        })
        return moved == open ? text : join(moved)
    }
}

/// One walk of every notebook folder (never into a board): each notebook's board count (its own and its notebooks'), and a stamp
/// per folder (the folder's and its notebook.json's modified times), so a later look can tell which folders changed with one
/// `stat` each instead of reading them all again. The sidebar runs it away from the main thread.
public struct NotebookScan: Equatable, Sendable {
    /// Notebook path -> boards in it and in the notebooks inside it.
    public var counts: [String: Int] = [:]
    /// Folder path (`notebooks` itself too) -> its stamp.
    public var stamps: [String: String] = [:]
    /// Every board's path, in the order the walk met them (for finding one by name: NotebookFind).
    public var boards: [String] = []

    public init(counts: [String: Int] = [:], stamps: [String: String] = [:], boards: [String] = []) {
        self.counts = counts; self.stamps = stamps; self.boards = boards
    }

    /// Every notebook's path, by path.
    public var notebooks: [String] { counts.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    /// What finding by name looks through (NotebookFind).
    public var findEntries: [NotebookFind.Entry] { NotebookFind.entries(notebooks: notebooks, boards: boards) }

    public static func read(_ root: URL) -> NotebookScan {
        var scan = NotebookScan()
        let base = BoardFormat.notebooks
        scan.stamps[base] = stamp(root, base)
        @discardableResult
        func walk(_ rel: String) -> Int {
            scan.stamps[rel] = stamp(root, rel)
            var n = 0
            for name in Notebook.folders(root, rel) {
                if name.lowercased().hasSuffix(".board") { n += 1; scan.boards.append(rel + "/" + name) } else { n += walk(rel + "/" + name) }
            }
            scan.counts[rel] = n
            return n
        }
        for name in Notebook.folders(root, base) where !name.lowercased().hasSuffix(".board") { walk(base + "/" + name) }
        return scan
    }

    /// The folders whose stamp is no longer the one this scan saw (changed, or gone); empty when nothing changed. New folders show as
    /// their parent's change (a folder's modified time moves when something is added to it, removed or renamed in it).
    public func changed(_ root: URL) -> Set<String> {
        Set(stamps.compactMap { path, s in Self.stamp(root, path) == s ? nil : path })
    }

    /// The folders that differ between two scans (in one and not the other, or stamped differently).
    public func changed(from old: NotebookScan) -> Set<String> {
        var out = Set<String>()
        for (p, s) in stamps where old.stamps[p] != s { out.insert(p) }
        for p in old.stamps.keys where stamps[p] == nil { out.insert(p) }
        return out
    }

    static func stamp(_ root: URL, _ rel: String) -> String {
        let dir = root.appendingPathComponent(rel)
        func time(_ url: URL) -> String {
            guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "-" }
            return String((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) + ":" + String((a[.size] as? NSNumber)?.intValue ?? 0)
        }
        return time(dir) + "|" + time(dir.appendingPathComponent(NotebookMeta.file))
    }
}
