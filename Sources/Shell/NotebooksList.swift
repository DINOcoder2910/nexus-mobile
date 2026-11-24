import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers
import NexusCore

/// The sidebar's notebooks, as the laptop's (nexus docs/data-format.md "The board redesign's additions", Notebooks): every plain folder
/// under `notebooks/` is a notebook, to any depth; a `<name>.board` folder in one is a board. The sidebar shows them as a tree
/// (NexusCore NotebookTree): each notebook with an arrow to open it, and inside it its notebooks, then its boards, in the notebook
/// page's order (notebook.json `order`, OneNote's, then by name). Tapping a notebook opens its page (NotebookPage); tapping a board
/// opens the board, and the open board's row is the one selected. Press and hold a notebook for Pin, Rename, Move, Colour, New
/// notebook inside, Delete, a board for Open in a new window, Pin, Rename, Move, Delete; drop a board on a notebook to move it there.
/// Opening a notebook closes the ones beside it (NotebookTree.opening), so one branch is open at a time.
struct NotebooksList: View {
    @Environment(NexusStore.self) private var store
    @Bindable var actions: NotebookActions
    /// The iPhone's list (rows push onto the stack; a board opens over everything) rather than the iPad's selectable sidebar.
    var pushes = false
    /// The open notebooks' paths ("a|b"), remembered.
    @AppStorage("openNotebooks") private var openList = ""

    /// What the tree has read of the folder (lazily: only the levels that show; counts away from the main thread).
    let tree: NotebookTreeModel

    var body: some View {
        ForEach(tree.rows(store.folder, open: NotebookTree.parse(openList))) { r in
            NotebookTreeLine(row: r, nb: r.kind == .notebook ? tree.notebook(r.path) : nil, pushes: pushes, actions: actions) {
                // opening one closes the notebooks beside it (one branch open at a time), so the tree stays short
                withAnimation(.snappy(duration: 0.25)) {
                    openList = r.isOpen ? NotebookTree.setting(r.path, open: false, in: openList) : NotebookTree.opening(r.path, in: openList)
                }
            }
            // the iPad's selection: a notebook's page, or the board (selected while it is open)
            .tag(r.kind == .board ? SidebarItem.board(r.path) : SidebarItem.screen(.notebook(r.path)))
        }
        Button { actions.ask(.notebook, in: BoardFormat.notebooks) } label: {
            Label("New notebook…", systemImage: "plus").foregroundStyle(.secondary)
        }
    }
}

/// One row of the notebook tree: indented by its depth, an arrow when it has anything inside, then the notebook or the board.
struct NotebookTreeLine: View {
    let row: NotebookTreeRow
    /// The notebook itself (for its menu); nil for a board.
    let nb: Notebook?
    let pushes: Bool
    @Bindable var actions: NotebookActions
    let toggle: () -> Void
    @Environment(NexusStore.self) private var store

    /// Each level's step in, and the arrow's width (kept empty where there is no arrow, so the names line up).
    static let step: CGFloat = 14
    static let arrowWidth: CGFloat = 22

    var body: some View {
        if row.kind == .board { board } else { notebook }
    }

    private var lead: some View {
        HStack(spacing: 2) {
            if row.depth > 0 { Color.clear.frame(width: CGFloat(row.depth) * Self.step, height: 1) }
            if row.hasChildren {
                Button(action: toggle) {
                    // Color's grey, not .secondary: in a button that is the tint's (green) secondary
                    Image(systemName: "chevron.right")
                        .font(.nx(.caption, .semibold))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(row.isOpen ? 90 : 0))
                        .frame(width: Self.arrowWidth, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel((row.isOpen ? "Collapse " : "Expand ") + row.name)
            } else {
                Color.clear.frame(width: Self.arrowWidth, height: 1)
            }
        }
    }

    // MARK: a notebook

    private var notebookLabel: some View {
        HStack(spacing: 8) {
            if let c = row.color {
                Circle().fill(Color(uiColor: InkConvert.color(c))).frame(width: 9, height: 9).frame(width: 18)
            } else {
                Image(systemName: "book.closed").foregroundStyle(.secondary).font(.nx(.footnote)).frame(width: 18)
            }
            Text(row.name).lineLimit(1)
            Spacer(minLength: 4)
            if let n = row.boardCount, n > 0 { Text("\(n)").font(.nx(.caption)).foregroundStyle(.secondary).monospacedDigit() }
        }
        .contentShape(Rectangle())
    }

    private var notebook: some View {
        HStack(spacing: 0) {
            lead
            if pushes {
                NavigationLink(value: Screen.notebook(row.path)) { notebookLabel }
            } else {
                notebookLabel
            }
        }
        .notebookRowExtras(nb, actions: actions, store: store)
    }

    // MARK: a board

    private var boardLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "scribble").foregroundStyle(Color.secondary).font(.nx(.footnote)).frame(width: 18)
            Text(row.name).lineLimit(2)  // OneNote page names run long: two lines before they are cut
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var board: some View {
        let ref = Notebook.BoardRef(name: row.name, path: row.path)
        if pushes {
            Button { store.openBoard = .init(path: row.path, focus: nil) } label: {
                HStack(spacing: 0) { lead; boardLabel }.foregroundStyle(Color.primary)
            }
            .boardRowExtras(ref, actions: actions)
        } else {
            HStack(spacing: 0) { lead; boardLabel }
                .boardRowExtras(ref, actions: actions)
        }
    }
}

private extension View {
    /// A notebook row's long-press menu, and a board dropped on it moves there.
    @ViewBuilder
    func notebookRowExtras(_ nb: Notebook?, actions: NotebookActions, store: NexusStore) -> some View {
        if let nb {
            self.notebookRowMenu(nb, actions: actions, store: store)
        } else {
            self
        }
    }

    /// A board row's long-press menu (the card's main ones), and it can be dragged onto a notebook.
    func boardRowExtras(_ b: Notebook.BoardRef, actions: NotebookActions) -> some View {
        self.boardRowMenu(b, actions: actions)
    }
}

extension View {
    /// A notebook's long-press menu (the tree's row, a found or pinned one), and a board dropped on it moves there.
    func notebookRowMenu(_ nb: Notebook, actions: NotebookActions, store: NexusStore) -> some View {
        self.contextMenu { NotebookMenu(nb: nb, actions: actions) }
            .dropDestination(for: String.self) { paths, _ in actions.move(paths, into: nb.path, store) }
    }

    /// A board's long-press menu (the card's main ones), and it can be dragged onto a notebook.
    func boardRowMenu(_ b: Notebook.BoardRef, actions: NotebookActions) -> some View {
        self.draggable(b.path)
            .contextMenu {
                NewWindowButton(start: .board(b.path))
                PinButton(path: b.path)
                Button { actions.ask(.rename, in: b.path, name: b.name) } label: { Label("Rename…", systemImage: "pencil") }
                Button { actions.moving = b.path } label: { Label("Move to…", systemImage: "folder") }
                Divider()
                Button(role: .destructive) { actions.removing = b } label: { Label("Delete…", systemImage: "trash") }
            }
    }
}

/// The pinned notebooks and boards: the sidebar's Pinned section, above Recent ("a|b" in this device's settings, in the order
/// pinned; they follow a move or a rename, RecentBoards.renamed).
enum NotebookPins {
    static let key = "pinnedNotebooks"
}

/// Pin to the top / Unpin, in a notebook's or a board's menu.
struct PinButton: View {
    let path: String
    @AppStorage(NotebookPins.key) private var pinned = ""

    var body: some View {
        let on = PathList.parse(pinned).contains(path)
        Button {
            withAnimation(Kit.spring) { pinned = PathList.toggling(path, in: pinned) }
        } label: {
            Label(on ? "Unpin" : "Pin to the top", systemImage: on ? "pin.slash" : "pin")
        }
    }
}

/// The notebooks moved into lately (Move to…'s Recent; this device's own), newest first.
enum MovePlaces {
    static let key = "recentMovePlaces"

    static func list(_ root: URL) -> [String] {
        PathList.parse(UserDefaults.standard.string(forKey: key) ?? "").filter {
            $0 == BoardFormat.notebooks || FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path)
        }
    }

    static func add(_ path: String) {
        UserDefaults.standard.set(PathList.adding(path, to: UserDefaults.standard.string(forKey: key) ?? "", max: 8), forKey: key)
    }
}

/// A notebook's long-press menu (the sidebar's row and its card on a notebook page).
struct NotebookMenu: View {
    let nb: Notebook
    @Bindable var actions: NotebookActions

    var body: some View {
        PinButton(path: nb.path)
        Button { actions.ask(.rename, in: nb.path, name: nb.name) } label: { Label("Rename…", systemImage: "pencil") }
        Button { actions.moving = nb.path } label: { Label("Move to…", systemImage: "folder") }
        if nb.depth == 0 {
            Menu {
                Button { actions.setColour(nb.path, nil) } label: { Label("None", systemImage: nb.color == nil ? "checkmark" : "circle") }
                ForEach(NotebookMeta.colors.indices, id: \.self) { i in
                    let c = NotebookMeta.colors[i]
                    Button { actions.setColour(nb.path, c.hex) } label: { Label(c.name, systemImage: nb.color?.uppercased() == c.hex.uppercased() ? "checkmark" : "circle.fill") }
                }
            } label: { Label("Colour", systemImage: "paintpalette") }
        }
        Button { actions.ask(.notebook, in: nb.path) } label: { Label("New notebook inside…", systemImage: "folder.badge.plus") }
        Button(role: .destructive) { actions.removingNotebook = nb } label: { Label("Delete…", systemImage: "trash") }
    }
}

/// The boards opened last (newest first, at most five), for the sidebar's Recent.
enum RecentBoards {
    static let key = "recentBoards"
    static func list(_ root: URL) -> [String] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).filter {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0).appendingPathComponent("board.json").path)
        }.prefix(5).map { $0 }
    }
    static func add(_ path: String) {
        var l = UserDefaults.standard.stringArray(forKey: key) ?? []
        l.removeAll { $0 == path }
        l.insert(path, at: 0)
        UserDefaults.standard.set(Array(l.prefix(12)), forKey: key)
    }
    static func renamed(_ from: String, _ to: String) {
        let l = (UserDefaults.standard.stringArray(forKey: key) ?? []).map { p -> String in
            if p == from { return to }
            if p.hasPrefix(from + "/") { return to + p.dropFirst(from.count) }
            return p
        }
        UserDefaults.standard.set(l, forKey: key)
        // the pinned ones and Move to…'s recent places follow it too
        for k in [NotebookPins.key, MovePlaces.key] {
            let text = UserDefaults.standard.string(forKey: k) ?? ""
            let followed = PathList.renaming(from, to: to, in: text)
            if followed != text { UserDefaults.standard.set(followed, forKey: k) }
        }
        // the sidebar's open notebooks follow a renamed or moved notebook
        let open = UserDefaults.standard.string(forKey: "openNotebooks") ?? ""
        let moved = NotebookTree.renaming(from, to: to, in: open)
        if moved != open { UserDefaults.standard.set(moved, forKey: "openNotebooks") }
    }
}

/// Making, renaming, moving, colouring and deleting notebooks and boards (plain folders and `.board` folders in the data folder).
@Observable
final class NotebookActions {
    enum Kind { case notebook, board, rename }

    struct Ask: Identifiable {
        let id = UUID()
        var kind: Kind
        /// Where it goes (the parent folder), or what is renamed.
        var path: String
    }

    var asking: Ask?
    var name = ""
    var removing: Notebook.BoardRef?
    var removingNotebook: Notebook?
    /// A notebook or board being moved (the Move to… sheet).
    var moving: String?
    var problem: String?

    func ask(_ kind: Kind, in path: String, name: String = "") {
        self.name = name
        asking = Ask(kind: kind, path: path)
    }

    var title: String {
        switch asking?.kind {
        case .notebook: return "New notebook"
        case .board: return "New board"
        case .rename: return "Rename"
        case nil: return ""
        }
    }

    var hint: String {
        switch asking?.kind {
        case .notebook: return "Its name, for example Chemistry"
        case .board: return "Its name, for example Lesson 4"
        default: return ""
        }
    }

    static func names(in dir: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    }

    /// Does what was asked; a new board opens.
    func finish(_ store: NexusStore) {
        guard let a = asking else { return }
        asking = nil
        let fm = FileManager.default
        let want = name.trimmingCharacters(in: .whitespaces)
        do {
            switch a.kind {
            case .notebook:
                let dir = store.folder.appendingPathComponent(a.path, isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let n = BoardFormat.freeName(want, taken: Self.names(in: dir))
                try fm.createDirectory(at: dir.appendingPathComponent(n, isDirectory: true), withIntermediateDirectories: true)
                store.boardsChanged(listChanged: true)
            case .board:
                let rel = try makeBoard(want, in: a.path, store)
                store.openBoard = .init(path: rel, focus: nil)
            case .rename:
                let from = store.folder.appendingPathComponent(a.path, isDirectory: true)
                let parent = from.deletingLastPathComponent()
                let isBoard = a.path.lowercased().hasSuffix(".board")
                var taken = Self.names(in: parent)
                taken.remove(from.lastPathComponent)
                let n = BoardFormat.freeName(want, taken: taken, suffix: isBoard ? ".board" : "")
                guard n != from.lastPathComponent else { return }
                try fm.moveItem(at: from, to: parent.appendingPathComponent(n, isDirectory: true))
                RecentBoards.renamed(a.path, (a.path as NSString).deletingLastPathComponent + "/" + n)
                store.boardsChanged(listChanged: true)
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// A new empty board in the notebook `dir` (relative); returns its path.
    @discardableResult
    func makeBoard(_ want: String, in dir: String, _ store: NexusStore, items: [BoardItem] = []) throws -> String {
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        let n = BoardFormat.freeName(want, taken: Self.names(in: url), suffix: ".board")
        let board = url.appendingPathComponent(n, isDirectory: true)
        try FolderAccess.write(board.appendingPathComponent("board.json"), BoardFormat.boardJSON())
        if !items.isEmpty {
            var c = BoardContent()
            c.items = items
            _ = try BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
        }
        store.boardsChanged(listChanged: true)
        return dir + "/" + n
    }

    /// New board from a PDF: the PDF goes beside the board (as on the laptop) and its pages down the board.
    func newBoard(fromPDF url: URL, in dir: String, _ store: NexusStore) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            try newBoard(pdfData: data, named: url.deletingPathExtension().lastPathComponent, in: dir, store)
        } catch { problem = "Couldn't bring the PDF in: \(error.localizedDescription)" }
    }

    func newBoard(pdfData data: Data, named name: String, in dir: String, _ store: NexusStore) throws {
        let folder = store.folder.appendingPathComponent(dir, isDirectory: true)
        let pdf = BoardFormat.freeName(name, taken: Self.names(in: folder), suffix: ".pdf")
        try FolderAccess.writeData(folder.appendingPathComponent(pdf), data)
        let it = BoardItem(id: "pdf1", type: "pdf", x: 60, y: 60, fields: [
            ("src", .string("../" + pdf)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
        ])
        let rel = try makeBoard(name, in: dir, store, items: [it])
        HangWatch.note("notebook: board made from a PDF, opening it")
        store.openBoard = .init(path: rel, focus: nil)
    }

    /// New board from scanned pages: they become one PDF with its words readable (HandoutScan.swift), a printout down the board,
    /// the board and the PDF named after the handout's title.
    func newBoard(fromScan pages: [UIImage], in dir: String, _ store: NexusStore) {
        ScanPDF.make(pages) { [self] r in
            guard let r else { HangWatch.note("scan: no PDF"); problem = "Couldn't make a PDF of the scan."; return }
            HangWatch.note("scan: PDF made, words on \(r.readPages) of \(pages.count) pages")
            do { try newBoard(pdfData: r.data, named: r.name, in: dir, store) }
            catch { problem = "Couldn't make the board: \(error.localizedDescription)" }
        }
    }

    /// New board from a photo: the picture in the board's files, on the board at the top left.
    func newBoard(fromPhoto img: BoardImage.Prepared, in dir: String, _ store: NexusStore) {
        do {
            let rel = try makeBoard("Photo", in: dir, store)
            let board = store.folder.appendingPathComponent(rel, isDirectory: true)
            let file = "files/photo" + img.ext
            try FolderAccess.writeData(board.appendingPathComponent(file), img.data)
            let scale = min(1, 1000 / max(1, Double(img.size.width)))
            let it = BoardItem(id: "img1", type: "image", x: 60, y: 60, fields: [
                ("src", .string(file)), ("w", .number((Double(img.size.width) * scale).rounded())), ("h", .number((Double(img.size.height) * scale).rounded())),
            ])
            var c = BoardContent()
            c.items = [it]
            _ = try BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
            store.boardsChanged(listChanged: true)
            store.openBoard = .init(path: rel, focus: nil)
        } catch { problem = "Couldn't make the board: \(error.localizedDescription)" }
    }

    /// Moves boards or notebooks into the notebook `to` (a drop, or Move to…). True when something moved.
    @discardableResult
    func move(_ paths: [String], into to: String, _ store: NexusStore) -> Bool {
        var moved = false
        for from in paths where Notebook.canMove(from, into: to) {
            // a board goes only into a notebook, never straight into notebooks/
            if from.lowercased().hasSuffix(".board"), to == BoardFormat.notebooks { continue }
            let src = store.folder.appendingPathComponent(from, isDirectory: true)
            let dir = store.folder.appendingPathComponent(to, isDirectory: true)
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            let isBoard = from.lowercased().hasSuffix(".board")
            let base = isBoard ? String(src.lastPathComponent.dropLast(6)) : src.lastPathComponent
            let n = BoardFormat.freeName(base, taken: Self.names(in: dir), suffix: isBoard ? ".board" : "")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: src, to: dir.appendingPathComponent(n, isDirectory: true))
                RecentBoards.renamed(from, to + "/" + n)
                moved = true
                MovePlaces.add(to)
            } catch { problem = error.localizedDescription }
        }
        if moved { store.boardsChanged(listChanged: true) }
        return moved
    }

    /// A copy of a board beside it ("Lesson 4 2"); its history stays with the original.
    func duplicate(_ b: Notebook.BoardRef, _ store: NexusStore) {
        let src = store.folder.appendingPathComponent(b.path, isDirectory: true)
        let dir = src.deletingLastPathComponent()
        let n = BoardFormat.freeName(b.name, taken: Self.names(in: dir), suffix: ".board")
        do {
            try FileManager.default.copyItem(at: src, to: dir.appendingPathComponent(n, isDirectory: true))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(n).appendingPathComponent(BoardHistory.dir))
            store.boardsChanged(listChanged: true)
        } catch { problem = error.localizedDescription }
    }

    /// A top-level notebook's colour (`notebook.json`, other fields kept); nil takes it off.
    func setColour(_ path: String, _ hex: String?) {
        guard let store = Self.store else { return }
        let url = store.folder.appendingPathComponent(path).appendingPathComponent(NotebookMeta.file)
        let old = try? String(contentsOf: url, encoding: .utf8)
        do {
            try FolderAccess.write(url, NotebookMeta.json(old, color: hex))
            store.boardsChanged(listChanged: true)
        } catch { problem = error.localizedDescription }
    }

    /// A board's paper (board.json `paper`), from the card's Background menu.
    func setPaper(_ b: Notebook.BoardRef, _ kind: Paper.Kind, _ store: NexusStore) {
        let url = store.folder.appendingPathComponent(b.path).appendingPathComponent("board.json")
        do {
            let meta = try JSONValue.parse(FolderAccess.read(url))
            guard meta["format"]?.string == BoardFormat.format else { problem = "This board can't take a background yet: open it once first."; return }
            try FolderAccess.write(url, BoardFormat.metaText(meta.setting("paper", Paper(kind: kind).json)))
            store.boardsChanged(listChanged: true)
        } catch { problem = error.localizedDescription }
    }

    func delete(_ b: Notebook.BoardRef, _ store: NexusStore) {
        removing = nil
        do {
            try FileManager.default.removeItem(at: store.folder.appendingPathComponent(b.path, isDirectory: true))
            store.boardsChanged(listChanged: true)
        } catch { problem = error.localizedDescription }
    }

    func delete(_ nb: Notebook, _ store: NexusStore) {
        removingNotebook = nil
        do {
            try FileManager.default.removeItem(at: store.folder.appendingPathComponent(nb.path, isDirectory: true))
            store.boardsChanged(listChanged: true)
        } catch { problem = error.localizedDescription }
    }

    /// The store, for actions started from a menu that has none at hand (set by `notebookPrompts`).
    static weak var store: NexusStore?
}

extension View {
    /// The name prompt, the delete questions, Move to… and any problem for the notebooks (once on each screen that offers them).
    func notebookPrompts(_ actions: NotebookActions, store: NexusStore) -> some View {
        @Bindable var actions = actions
        NotebookActions.store = store
        return self
            .alert(actions.title, isPresented: Binding(get: { actions.asking != nil }, set: { if !$0 { actions.asking = nil } })) {
                TextField(actions.hint, text: $actions.name)
                Button(actions.asking?.kind == .rename ? "Rename" : "Make") { actions.finish(store) }
                Button("Cancel", role: .cancel) { actions.asking = nil }
            }
            .alert("Delete “\(actions.removing?.name ?? "")”?", isPresented: Binding(get: { actions.removing != nil }, set: { if !$0 { actions.removing = nil } })) {
                Button("Delete", role: .destructive) { if let b = actions.removing { actions.delete(b, store) } }
                Button("Cancel", role: .cancel) { actions.removing = nil }
            } message: {
                Text("Its ink, typed text, images and history are deleted from this \(Device.name), and from your other devices when they sync. PDF printouts beside it stay.")
            }
            .alert("Delete the notebook “\(actions.removingNotebook?.name ?? "")”?", isPresented: Binding(get: { actions.removingNotebook != nil }, set: { if !$0 { actions.removingNotebook = nil } })) {
                Button("Delete", role: .destructive) { if let nb = actions.removingNotebook { actions.delete(nb, store) } }
                Button("Cancel", role: .cancel) { actions.removingNotebook = nil }
            } message: {
                Text(deleteMessage(actions.removingNotebook, root: store.folder))
            }
            .sheet(isPresented: Binding(get: { actions.moving != nil }, set: { if !$0 { actions.moving = nil } })) {
                if let p = actions.moving { MoveSheet(path: p, actions: actions).environment(store) }
            }
            .alert("Couldn't do that", isPresented: Binding(get: { actions.problem != nil }, set: { if !$0 { actions.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(actions.problem ?? "") }
    }
}

private func deleteMessage(_ shown: Notebook?, root: URL) -> String {
    guard let shown else { return "" }
    // the sidebar's notebook has only its own level read: the whole of it, now that it is asked
    let nb = Notebook.read(root, shown.path)
    let b = nb.allBoards.count, n = nb.allNotebooks.count - 1
    var what: [String] = []
    if b > 0 { what.append(b == 1 ? "its 1 board" : "its \(b) boards") }
    if n > 0 { what.append(n == 1 ? "1 notebook inside it" : "\(n) notebooks inside it") }
    let head = what.isEmpty ? "It is empty." : "This deletes " + what.joined(separator: " and ") + ", with all their ink and text."
    return head + " They go from this iPad, and from your other devices when they sync."
}

/// Move to… (Nov 24 2026: the list of every notebook, all open, was too long to scroll): a search field over every notebook by name
/// and place, the notebooks moved into lately (Recent), then the notebooks as a tree opened where the board or notebook is now
/// (one branch open at a time, as the sidebar's), with Notebooks (top level) for a notebook. Tap a name to move it there; where it
/// is now, itself and what is inside it can't be picked.
struct MoveSheet: View {
    let path: String
    @Bindable var actions: NotebookActions
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// The tree's open notebooks; at first the ones that hold the board or notebook being moved.
    @State private var open: Set<String> = []
    @State private var started = false

    private var isBoard: Bool { path.lowercased().hasSuffix(".board") }
    /// The notebook it is in now.
    private var here: String { (path as NSString).deletingLastPathComponent }
    private var itemName: String {
        let last = (path as NSString).lastPathComponent
        return isBoard ? String(last.dropLast(6)) : last
    }

    var body: some View {
        let tree = store.notebooks()
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if NotebookFind.fold(query).isEmpty {
                        Text(here == BoardFormat.notebooks ? "Now at the top level" : "Now in " + NotebookFind.Entry(kind: .notebook, path: here).placeAndName)
                            .font(.nx(.footnote))
                            .foregroundStyle(Kit.muted)
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("move-now-in")
                        let recent = MovePlaces.list(store.folder).filter { allowed($0) }.prefix(5)
                        if !recent.isEmpty {
                            Section("Recent") {
                                ForEach(Array(recent), id: \.self) { p in placeRow(p) }
                            }
                        }
                        Section("All notebooks") {
                            if !isBoard { placeRow(BoardFormat.notebooks) }
                            ForEach(NotebookTree.rows(notebooks: tree, open: open)) { r in treeRow(r) }
                        }
                    } else {
                        let hits = NotebookFind.search(query, in: NotebookFind.entries(notebooks: tree.flatMap(\.allNotebooks).map(\.path), boards: []),
                                                       recent: MovePlaces.list(store.folder), limit: 40)
                        Section {
                            if hits.isEmpty {
                                Text("No notebook called “\(query.trimmingCharacters(in: .whitespaces))”")
                                    .font(.nx(.subheadline)).foregroundStyle(Kit.muted)
                                    .accessibilityIdentifier("move-none")
                            }
                            ForEach(hits) { h in placeRow(h.path) }
                        }
                    }
                }
                .onAppear {
                    guard !started else { return }
                    started = true
                    open = Set(NotebookTree.ancestors(of: path))
                    // the tree opens where it is now: that row comes into view
                    DispatchQueue.main.async { proxy.scrollTo(here, anchor: .center) }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a notebook")
            .navigationTitle("Move “\(itemName)” to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    /// May it go into `to`? Not where it is now, into itself or below itself, and a board never straight into notebooks/.
    private func allowed(_ to: String) -> Bool {
        Notebook.canMove(path, into: to) && !(isBoard && to == BoardFormat.notebooks)
    }

    private func move(to: String) {
        actions.move([path], into: to, store)
        actions.moving = nil
    }

    private func toggle(_ p: String) {
        withAnimation(Kit.spring) {
            if open.contains(p) {
                open.remove(p)
            } else {
                open = NotebookTree.parse(NotebookTree.opening(p, in: NotebookTree.join(open)))
            }
        }
    }

    /// A notebook by its name with where it sits under it (Recent, the search, the top level).
    private func placeRow(_ p: String) -> some View {
        let top = p == BoardFormat.notebooks
        let e = NotebookFind.Entry(kind: .notebook, path: p)
        let ok = allowed(p)
        return Button { move(to: p) } label: {
            HStack(spacing: 10) {
                Image(systemName: top ? "books.vertical" : "book.closed").foregroundStyle(Color.secondary).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(top ? "Notebooks (top level)" : e.name).lineLimit(1).foregroundStyle(ok ? Kit.ink : Kit.muted)
                    if !top && !e.place.isEmpty {
                        Text(e.place).font(.nx(.caption)).foregroundStyle(Kit.muted).lineLimit(1).truncationMode(.head)
                    }
                }
                Spacer(minLength: 4)
                if p == here { Text("Here now").font(.nx(.caption)).foregroundStyle(Kit.muted) }
            }
            .contentShape(Rectangle())
        }
        .disabled(!ok)
        .accessibilityIdentifier("move-place-" + (top ? "top" : e.name))
    }

    /// A notebook in the tree: its arrow (when it holds notebooks), then its name to move there, and how many boards it holds.
    private func treeRow(_ r: NotebookTreeRow) -> some View {
        let ok = allowed(r.path)
        return HStack(spacing: 2) {
            if r.depth > 0 { Color.clear.frame(width: CGFloat(r.depth) * NotebookTreeLine.step, height: 1) }
            if r.hasChildren {
                Button { toggle(r.path) } label: {
                    Image(systemName: "chevron.right")
                        .font(.nx(.caption, .semibold))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(r.isOpen ? 90 : 0))
                        .frame(width: NotebookTreeLine.arrowWidth, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel((r.isOpen ? "Collapse " : "Expand ") + r.name)
                .accessibilityIdentifier("move-arrow-" + r.name)
            } else {
                Color.clear.frame(width: NotebookTreeLine.arrowWidth, height: 1)
            }
            Button { move(to: r.path) } label: {
                HStack(spacing: 8) {
                    if let c = r.color {
                        Circle().fill(Color(uiColor: InkConvert.color(c))).frame(width: 9, height: 9).frame(width: 18)
                    } else {
                        Image(systemName: "book.closed").foregroundStyle(Color.secondary).font(.nx(.footnote)).frame(width: 18)
                    }
                    Text(r.name).lineLimit(1).foregroundStyle(ok ? Kit.ink : Kit.muted)
                    Spacer(minLength: 4)
                    if r.path == here {
                        Text("Here now").font(.nx(.caption)).foregroundStyle(Kit.muted)
                    } else if let n = r.boardCount, n > 0 {
                        Text("\(n)").font(.nx(.caption)).foregroundStyle(Color.secondary).monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!ok)
            .accessibilityIdentifier("move-to-" + r.name)
        }
        .id(r.path)
    }
}
