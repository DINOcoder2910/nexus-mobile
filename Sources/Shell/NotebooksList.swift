import SwiftUI
import NexusCore

/// The sidebar's notebooks, as the laptop's: `notebooks/<notebook>/<section>/<board>.board` (a board may also sit straight in a
/// notebook). A notebook's + makes a section or a board, a section's + a board; press and hold to rename, or to delete a board.
struct NotebooksList: View {
    @Environment(NexusStore.self) private var store
    @Bindable var actions: NotebookActions
    @AppStorage("openNotebooks") private var openList = ""

    var body: some View {
        let _ = store.notebooksVersion
        let notebooks = Notebook.list(store.folder)
        ForEach(notebooks) { nb in
            DisclosureGroup(isExpanded: open(nb.path)) {
                ForEach(nb.boards) { boardRow($0) }
                ForEach(nb.sections) { s in
                    DisclosureGroup(isExpanded: open(s.path)) {
                        ForEach(s.boards) { boardRow($0) }
                        if s.boards.isEmpty {
                            Button { actions.ask(.board, in: s.path) } label: {
                                Label("New board…", systemImage: "plus").foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        HStack {
                            Label(s.name, systemImage: "folder")
                            Spacer()
                            Button { actions.ask(.board, in: s.path) } label: { Image(systemName: "plus") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("New board in \(s.name)")
                        }
                        .contextMenu { renameButton(s.path, s.name) }
                    }
                }
                if nb.boards.isEmpty && nb.sections.isEmpty {
                    Button { actions.ask(.section, in: nb.path) } label: {
                        Label("New section…", systemImage: "plus").foregroundStyle(.secondary)
                    }
                }
            } label: {
                HStack {
                    Label(nb.name, systemImage: "book.closed")
                    Spacer()
                    Menu {
                        Button { actions.ask(.section, in: nb.path) } label: { Label("New section…", systemImage: "folder.badge.plus") }
                        Button { actions.ask(.board, in: nb.path) } label: { Label("New board…", systemImage: "scribble") }
                    } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("New section or board in \(nb.name)")
                }
                .contextMenu { renameButton(nb.path, nb.name) }
            }
        }
        Button { actions.ask(.notebook, in: BoardFormat.notebooks) } label: {
            Label("New notebook…", systemImage: "plus").foregroundStyle(.secondary)
        }
    }

    private func boardRow(_ b: Notebook.BoardRef) -> some View {
        Button { store.openBoard = .init(path: b.path, focus: nil) } label: {
            Label(b.name, systemImage: "scribble").foregroundStyle(.primary)
        }
        .contextMenu {
            renameButton(b.path, b.name)
            Button(role: .destructive) { actions.removing = b } label: { Label("Delete board…", systemImage: "trash") }
        }
    }

    private func renameButton(_ path: String, _ name: String) -> some View {
        Button { actions.ask(.rename, in: path, name: name) } label: { Label("Rename…", systemImage: "pencil") }
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

/// Making, renaming and deleting notebooks, sections and boards (plain folders and `.board` folders in the data folder).
@Observable
final class NotebookActions {
    enum Kind { case notebook, section, board, rename }

    struct Ask: Identifiable {
        let id = UUID()
        var kind: Kind
        /// Where it goes (the parent folder), or what is renamed.
        var path: String
    }

    var asking: Ask?
    var name = ""
    var removing: Notebook.BoardRef?
    var problem: String?

    func ask(_ kind: Kind, in path: String, name: String = "") {
        self.name = name
        asking = Ask(kind: kind, path: path)
    }

    var title: String {
        switch asking?.kind {
        case .notebook: return "New notebook"
        case .section: return "New section"
        case .board: return "New board"
        case .rename: return "Rename"
        case nil: return ""
        }
    }

    var hint: String {
        switch asking?.kind {
        case .notebook: return "Its name, for example Chemistry"
        case .section: return "Its name, for example R3.2 Redox"
        case .board: return "Its name, for example Lesson 4"
        default: return ""
        }
    }

    private func names(in dir: URL) -> Set<String> {
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
            case .notebook, .section:
                let dir = store.folder.appendingPathComponent(a.path, isDirectory: true)
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let n = BoardFormat.freeName(want, taken: names(in: dir))
                try fm.createDirectory(at: dir.appendingPathComponent(n, isDirectory: true), withIntermediateDirectories: true)
                store.boardsChanged(listChanged: true)
            case .board:
                let dir = store.folder.appendingPathComponent(a.path, isDirectory: true)
                let n = BoardFormat.freeName(want, taken: names(in: dir), suffix: ".board")
                try FolderAccess.write(dir.appendingPathComponent(n).appendingPathComponent("board.json"), BoardFormat.boardJSON())
                store.boardsChanged(listChanged: true)
                store.openBoard = .init(path: a.path + "/" + n, focus: nil)
            case .rename:
                let from = store.folder.appendingPathComponent(a.path, isDirectory: true)
                let parent = from.deletingLastPathComponent()
                let isBoard = a.path.lowercased().hasSuffix(".board")
                var taken = names(in: parent)
                taken.remove(from.lastPathComponent)
                let n = BoardFormat.freeName(want, taken: taken, suffix: isBoard ? ".board" : "")
                guard n != from.lastPathComponent else { return }
                try fm.moveItem(at: from, to: parent.appendingPathComponent(n, isDirectory: true))
                store.boardsChanged(listChanged: true)
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    func delete(_ b: Notebook.BoardRef, _ store: NexusStore) {
        removing = nil
        do {
            try FileManager.default.removeItem(at: store.folder.appendingPathComponent(b.path, isDirectory: true))
            store.boardsChanged(listChanged: true)
        } catch { problem = error.localizedDescription }
    }
}

extension View {
    /// The name prompt, the delete question and any problem for the notebooks list (on the sidebar's list, once).
    func notebookPrompts(_ actions: NotebookActions, store: NexusStore) -> some View {
        @Bindable var actions = actions
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
                Text("Its ink, typed text and images are deleted from this \(Device.name). PDF printouts beside it stay.")
            }
            .alert("Couldn't do that", isPresented: Binding(get: { actions.problem != nil }, set: { if !$0 { actions.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(actions.problem ?? "") }
    }
}
