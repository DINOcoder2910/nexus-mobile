import SwiftUI
import UIKit
import PDFKit
import UniformTypeIdentifiers
import NexusCore

/// The sidebar's notebooks, as the laptop's (nexus docs/data-format.md "The board redesign's additions", Notebooks): every plain folder
/// under `notebooks/` is a notebook, to any depth; a `<name>.board` folder in one is a board. The sidebar shows the notebooks (a
/// top-level one with its colour); tapping one opens its page (NotebookPage), which shows its notebooks and its boards as cards.
/// Press and hold a notebook for Rename, Move, Colour, New notebook inside, Delete; drop a board's card on one to move it there.
struct NotebooksList: View {
    @Environment(NexusStore.self) private var store
    @Bindable var actions: NotebookActions

    var body: some View {
        let _ = store.notebooksVersion
        ForEach(Notebook.list(store.folder)) { NotebookRow(nb: $0, actions: actions) }
        Button { actions.ask(.notebook, in: BoardFormat.notebooks) } label: {
            Label("New notebook…", systemImage: "plus").foregroundStyle(.secondary)
        }
    }
}

/// One notebook in the sidebar, with the notebooks inside it below a disclosure arrow.
struct NotebookRow: View {
    let nb: Notebook
    @Bindable var actions: NotebookActions
    @Environment(NexusStore.self) private var store
    @AppStorage("openNotebooks") private var openList = ""

    var body: some View {
        if nb.notebooks.isEmpty {
            link
        } else {
            DisclosureGroup(isExpanded: open(nb.path)) {
                ForEach(nb.notebooks) { NotebookRow(nb: $0, actions: actions) }
            } label: { link }
        }
    }

    private var link: some View {
        NavigationLink(value: Screen.notebook(nb.path)) {
            HStack(spacing: 10) {
                if nb.depth == 0, let c = nb.color {
                    Circle().fill(Color(uiColor: InkConvert.color(c))).frame(width: 9, height: 9)
                } else {
                    Image(systemName: "book.closed").foregroundStyle(.secondary).font(.footnote)
                }
                Text(nb.name).lineLimit(1)
                Spacer()
                let n = nb.allBoards.count
                if n > 0 { Text("\(n)").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .contextMenu { NotebookMenu(nb: nb, actions: actions) }
        .dropDestination(for: String.self) { paths, _ in actions.move(paths, into: nb.path, store) }
    }

    private func open(_ path: String) -> Binding<Bool> {
        Binding(get: { openList.split(separator: "|").contains(Substring(path)) },
                set: { isOpen in
                    var set = Set(openList.split(separator: "|").map(String.init))
                    if isOpen { set.insert(path) } else { set.remove(path) }
                    openList = set.sorted().joined(separator: "|")
                })
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

    /// New board from scanned pages: they become one PDF (a printout down the board).
    func newBoard(fromScan pages: [UIImage], in dir: String, _ store: NexusStore) {
        let doc = PDFDocument()
        for (i, img) in pages.enumerated() { if let p = PDFPage(image: img) { doc.insert(p, at: i) } }
        guard doc.pageCount > 0, let data = doc.dataRepresentation() else { return }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        do { try newBoard(pdfData: data, named: "Scan " + f.string(from: Date()), in: dir, store) }
        catch { problem = "Couldn't make the board: \(error.localizedDescription)" }
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
