import SwiftUI
import NexusCore

/// The sidebar, the laptop's in iPad form: the places, the workstreams by group (Inbox and Someday last), the notebooks, Settings.
/// On the iPhone the same list is the More tab (`pushes`: its rows push onto the tab's stack) and, cut to the notebooks, the
/// Notebooks tab (`notebooksOnly`). The notebooks are a tree with their boards (NotebooksList).
struct Sidebar: View {
    @Environment(NexusStore.self) private var store
    @Binding var selection: Screen?
    var pushes = false
    var notebooksOnly = false
    var title = "Nexus"
    @AppStorage("closedGroups") private var closedGroups = ""
    /// The notebook tree's open notebooks (NotebooksList): the open board's notebooks are opened, so its row shows.
    @AppStorage("openNotebooks") private var openNotebooks = ""
    @State private var notebookActions = NotebookActions()

    var body: some View {
        let s = store.snapshot
        Group {
            if pushes {
                List { sections }.listStyle(.insetGrouped)
            } else {
                List(selection: listSelection) { sections }.listStyle(.sidebar)
            }
        }
        .notebookPrompts(notebookActions, store: store)
        .onChange(of: ShortcutCenter.shared.notebookRequest) { _, _ in
            if s.isDataFolder && !pushes { notebookActions.ask(.notebook, in: BoardFormat.notebooks) }
        }
        .onChange(of: store.openBoard?.path, initial: true) { _, p in
            guard let p else { return }
            RecentBoards.add(p)
            openNotebooks = NotebookTree.revealing(p, in: openNotebooks)
        }
        .navigationTitle(title)
        .toolbar {
            if !notebooksOnly {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.capture = .init(workstream: nil, parent: nil, plan: nil) } label: { Label("New task", systemImage: "square.and.pencil") }
                        .disabled(!s.isDataFolder)
                }
            } else if s.isDataFolder {
                ToolbarItem(placement: .primaryAction) {
                    Button { notebookActions.ask(.notebook, in: BoardFormat.notebooks) } label: { Label("New notebook", systemImage: "folder.badge.plus") }
                }
            }
        }
        .refreshable { store.reload() }
        // the study decks: read with the folder (their due count is the Study row's number)
        .task(id: store.snapshot.loadedAt) { StudyLibrary.shared.refreshIfChanged(store) }
    }

    @ViewBuilder
    private var sections: some View {
        let p = store.planning
        let s = store.snapshot
        if !notebooksOnly {
            Section {
                row(.today, "Today", "sun.max", count: p.planned(on: store.today).count)
                row(.planner, "Planner", "rectangle.split.3x1", count: nil)
                row(.calendar, "Calendar", "calendar", count: nil)
                row(.tasks, "Tasks", "checklist", count: nil)
                if s.isDataFolder && StudyLibrary.shared.hasDecks {
                    row(.study, "Study", "rectangle.on.rectangle.angled", count: StudyLibrary.shared.dueTotal)
                }
            }

            if s.isDataFolder {
                Section("Workstreams") {
                    ForEach(s.groups) { g in
                        DisclosureGroup(isExpanded: open(g.id)) {
                            ForEach(s.workstreams(in: g).filter { !$0.finished }) { w in
                                link(.workstream(w.id)) {
                                    HStack(spacing: 10) {
                                        Circle().fill(store.color(workstream: w.id)).frame(width: 9, height: 9)
                                        Text(w.name).lineLimit(1).foregroundStyle(w.parked ? .secondary : .primary)
                                        Spacer()
                                        let n = p.openCount(w.id)
                                        if n > 0 && !w.parked { Text("\(n)").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        } label: {
                            Text(g.label).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    row(.inbox, "Inbox", "tray", count: p.openCount(nil))
                    row(.someday, "Someday", "moon.zzz", count: nil)
                }
            }
        }

            if s.isDataFolder {
                let recent = RecentBoards.list(store.folder)
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent, id: \.self) { p in
                            Button { store.openBoard = .init(path: p, focus: nil) } label: {
                                Label(HandwritingIndex.nameAndPlace(p).name, systemImage: "scribble").foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }

            Section("Notebooks") {
                if s.isDataFolder { NotebooksList(actions: notebookActions, pushes: pushes) }
                row(.boardSearch, "Search boards", "text.magnifyingglass", count: nil)
            }

            if !notebooksOnly {
                Section {
                    row(.settings, "Settings", "gearshape", count: nil)
                } footer: {
                    if s.readOnlyReason != nil { Label("Read-only", systemImage: "lock").font(.caption) }
                }
            }
    }

    private func row(_ screen: Screen, _ title: String, _ icon: String, count: Int?) -> some View {
        link(screen) {
            Label(title, systemImage: icon)
                .badge(count ?? 0)
        }
    }

    /// A row that goes to a screen: on the iPad it selects it (the split view shows it), on the iPhone it pushes it.
    @ViewBuilder
    private func link<L: View>(_ screen: Screen, @ViewBuilder _ label: () -> L) -> some View {
        if pushes {
            NavigationLink(value: screen, label: label)
        } else {
            NavigationLink(value: SidebarItem.screen(screen), label: label)
        }
    }

    /// The iPad's selection: the open board's row while a board is open, else the screen's. Picking a board opens it; picking a
    /// screen shows it (and closes the board, also when it is the screen that was showing under the board).
    private var listSelection: Binding<SidebarItem?> {
        Binding<SidebarItem?>(get: {
            if let b = store.openBoard { return SidebarItem.board(b.path) }
            return selection.map { SidebarItem.screen($0) }
        }, set: { new in
            switch new {
            case .board(let p)?:
                if store.openBoard?.path != p { store.openBoard = .init(path: p, focus: nil) }
            case .screen(let s)?:
                if s == selection { store.openBoard = nil } else { selection = s }
            case nil:
                // the collapsed split view (a narrow window) going back to the sidebar
                selection = nil
                if store.openBoard != nil { store.openBoard = nil }
            }
        })
    }

    /// Groups are open unless closed; the closed ones are remembered.
    private func open(_ id: String) -> Binding<Bool> {
        Binding(get: { !closedGroups.split(separator: "|").contains(Substring(id)) },
                set: { isOpen in
                    var set = Set(closedGroups.split(separator: "|").map(String.init))
                    if isOpen { set.remove(id) } else { set.insert(id) }
                    closedGroups = set.sorted().joined(separator: "|")
                })
    }
}

/// What a row of the iPad's sidebar stands for: a screen, or a board (its row is the selected one while it is open).
enum SidebarItem: Hashable {
    case screen(Screen)
    case board(String)
}
