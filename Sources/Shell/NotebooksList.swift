import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers
import NexusCore

/// The sidebar's notebooks, as the laptop's (nexus docs/data-format.md "The board redesign's additions", Notebooks): every plain folder
/// under `notebooks/` is a notebook, to any depth; a `<name>.board` folder in one is a board. The sidebar shows them as a tree
/// (NexusCore NotebookTree): each notebook with an arrow to open it, and inside it its notebooks, then its boards, in the notebook
/// page's order (notebook.json `order`, OneNote's, then by name). Tapping a notebook opens its page (NotebookPage); tapping a board
/// opens the board, and the open board's row is the one selected. Press and hold a notebook for Rename, Move, Colour, New notebook
/// inside, Delete, a board for Open in a new window, Rename, Move, Delete; drop a board on a notebook to move it there.
struct NotebooksList: View {
    @Environment(NexusStore.self) private var store
    @Bindable var actions: NotebookActions
    /// The iPhone's list (rows push onto the stack; a board opens over everything) rather than the iPad's selectable sidebar.
    var pushes = false
    /// The open notebooks' paths ("a|b"), remembered.
    @AppStorage("openNotebooks") private var openList = ""

    var body: some View {
        let _ = store.notebooksVersion
        let tree = Notebook.list(store.folder)
        let byPath = Dictionary(tree.flatMap(\.allNotebooks).map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        ForEach(NotebookTree.rows(tree, open: NotebookTree.parse(openList))) { r in
            NotebookTreeLine(row: r, nb: byPath[r.path], pushes: pushes, actions: actions) {
                withAnimation(.snappy(duration: 0.25)) { openList = NotebookTree.setting(r.path, open: !r.isOpen, in: openList) }
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
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
                Image(systemName: "book.closed").foregroundStyle(.secondary).font(.footnote).frame(width: 18)
            }
            Text(row.name).lineLimit(1)
            Spacer(minLength: 4)
            if row.boardCount > 0 { Text("\(row.boardCount)").font(.caption).foregroundStyle(.secondary) }
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
            Image(systemName: "scribble").foregroundStyle(.secondary).font(.footnote).frame(width: 18)
            Text(row.name).lineLimit(1)
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var board: some View {
        let ref = Notebook.BoardRef(name: row.name, path: row.path)
        if pushes {
            Button { store.openBoard = .init(path: row.path, focus: nil) } label: {
                HStack(spacing: 0) { lead; boardLabel }.foregroundStyle(.primary)
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
            self.contextMenu { NotebookMenu(nb: nb, actions: actions) }
                .dropDestination(for: String.self) { paths, _ in actions.move(paths, into: nb.path, store) }
        } else {
            self
        }
    }

    /// A board row's long-press menu (the card's main ones), and it can be dragged onto a notebook.
    func boardRowExtras(_ b: Notebook.BoardRef, actions: NotebookActions) -> some View {
        self.draggable(b.path)
            .contextMenu {
                NewWindowButton(start: .board(b.path))
                Button { actions.ask(.rename, in: b.path, name: b.name) } label: { Label("Rename…", systemImage: "pencil") }
                Button { actions.moving = b.path } label: { Label("Move to…", systemImage: "folder") }
                Divider()
                Button(role: .destructive) { actions.removing = b } label: { Label("Delete…", systemImage: "trash") }
            }
    }
}

/// A notebook's long-press menu (the sidebar's row and its card on a notebook page).
struct NotebookMenu: View {
    let nb: Notebook
    @Bindable var actions: NotebookActions

    var body: some View {
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
        store.openBoard = .init(path: rel, focus: nil)
    }

    /// New board from scanned pages: they become one PDF with its words readable (HandoutScan.swift), a printout down the board,
    /// the board and the PDF named after the handout's title.
    func newBoard(fromScan pages: [UIImage], in dir: String, _ store: NexusStore) {
        ScanPDF.make(pages) { [self] r in
            guard let r else { problem = "Couldn't make a PDF of the scan."; return }
            do { try newBoard(pdfData: r.data, named: r.name, in: dir, store) }
            catch { problem = "Couldn't make the board: \(error.localizedDescription)" }
        }
    }

    /// New board from a photo: the picture in the board's files, on the board at the top left.
    func newBoard(fromPhoto img: UIImage, in dir: String, _ store: NexusStore) {
        guard let data = img.jpegData(compressionQuality: 0.85) else { return }
        do {
            let rel = try makeBoard("Photo", in: dir, store)
            let board = store.folder.appendingPathComponent(rel, isDirectory: true)
            try FolderAccess.writeData(board.appendingPathComponent("files/photo.jpg"), data)
            let scale = min(1, 1000 / max(1, Double(img.size.width)))
            let it = BoardItem(id: "img1", type: "image", x: 60, y: 60, fields: [
                ("src", .string("files/photo.jpg")), ("w", .number((Double(img.size.width) * scale).rounded())), ("h", .number((Double(img.size.height) * scale).rounded())),
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
                Text(deleteMessage(actions.removingNotebook))
            }
            .sheet(isPresented: Binding(get: { actions.moving != nil }, set: { if !$0 { actions.moving = nil } })) {
                if let p = actions.moving { MoveSheet(path: p, actions: actions).environment(store) }
            }
            .alert("Couldn't do that", isPresented: Binding(get: { actions.problem != nil }, set: { if !$0 { actions.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(actions.problem ?? "") }
    }
}

private func deleteMessage(_ nb: Notebook?) -> String {
    guard let nb else { return "" }
    let b = nb.allBoards.count, n = nb.allNotebooks.count - 1
    var what: [String] = []
    if b > 0 { what.append(b == 1 ? "its 1 board" : "its \(b) boards") }
    if n > 0 { what.append(n == 1 ? "1 notebook inside it" : "\(n) notebooks inside it") }
    let head = what.isEmpty ? "It is empty." : "This deletes " + what.joined(separator: " and ") + ", with all their ink and text."
    return head + " They go from this iPad, and from your other devices when they sync."
}

/// Move to…: every notebook as a tree; tap one to move the board or notebook there.
struct MoveSheet: View {
    let path: String
    @Bindable var actions: NotebookActions
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let isBoard = path.lowercased().hasSuffix(".board")
        let all = Notebook.list(store.folder).flatMap(\.allNotebooks)
        NavigationStack {
            List {
                if !isBoard {
                    row("Notebooks (top level)", BoardFormat.notebooks, depth: -1)
                }
                ForEach(all) { nb in row(nb.name, nb.path, depth: nb.depth) }
            }
            .navigationTitle("Move “\(((path as NSString).lastPathComponent as NSString).deletingPathExtension)” to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ name: String, _ to: String, depth: Int) -> some View {
        let ok = Notebook.canMove(path, into: to)
        return Button {
            actions.move([path], into: to, store)
            actions.moving = nil
        } label: {
            Label(name, systemImage: depth < 0 ? "books.vertical" : "book.closed")
                .padding(.leading, CGFloat(max(0, depth)) * 18)
        }
        .disabled(!ok)
    }
}
