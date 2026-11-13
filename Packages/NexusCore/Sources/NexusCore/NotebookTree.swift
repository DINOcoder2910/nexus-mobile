import Foundation

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
    /// A notebook's boards, those in the notebooks inside it too; 0 for a board.
    public var boardCount: Int
    public var id: String { path }

    public init(kind: Kind, name: String, path: String, depth: Int, color: String? = nil, hasChildren: Bool = false,
                isOpen: Bool = false, boardCount: Int = 0) {
        self.kind = kind; self.name = name; self.path = path; self.depth = depth; self.color = color
        self.hasChildren = hasChildren; self.isOpen = isOpen; self.boardCount = boardCount
    }
}

public enum NotebookTree {
    /// The rows to show: every top-level notebook, and inside each open one its notebooks (and theirs, when open), then its boards.
    public static func rows(_ tree: [Notebook], open: Set<String>) -> [NotebookTreeRow] {
        var out: [NotebookTreeRow] = []
        func add(_ nb: Notebook) {
            let kids = !nb.notebooks.isEmpty || !nb.boards.isEmpty
            let isOpen = kids && open.contains(nb.path)
            out.append(NotebookTreeRow(kind: .notebook, name: nb.name, path: nb.path, depth: nb.depth,
                                       color: nb.depth == 0 ? nb.color : nil, hasChildren: kids, isOpen: isOpen,
                                       boardCount: nb.allBoards.count))
            guard isOpen else { return }
            nb.notebooks.forEach(add)
            for b in nb.boards {
                out.append(NotebookTreeRow(kind: .board, name: b.name, path: b.path, depth: nb.depth + 1))
            }
        }
        tree.forEach(add)
        return out
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
}
