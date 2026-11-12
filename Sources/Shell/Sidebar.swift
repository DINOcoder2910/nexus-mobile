import SwiftUI
import NexusCore

/// The sidebar, the laptop's in iPad form: the places, the workstreams by group (Inbox and Someday last), the notebooks, Settings.
struct Sidebar: View {
    @Environment(NexusStore.self) private var store
    @Binding var selection: Screen?
    @AppStorage("closedGroups") private var closedGroups = ""
    @State private var notebookActions = NotebookActions()

    var body: some View {
        let p = store.planning
        let s = store.snapshot
        List(selection: $selection) {
            Section {
                row(.today, "Today", "sun.max", count: p.planned(on: store.today).count)
                row(.planner, "Planner", "rectangle.split.3x1", count: nil)
                row(.calendar, "Calendar", "calendar", count: nil)
                row(.tasks, "Tasks", "checklist", count: nil)
            }

            if s.isDataFolder {
                Section("Workstreams") {
                    ForEach(s.groups) { g in
                        DisclosureGroup(isExpanded: open(g.id)) {
                            ForEach(s.workstreams(in: g).filter { !$0.finished }) { w in
                                NavigationLink(value: Screen.workstream(w.id)) {
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
                if s.isDataFolder { NotebooksList(actions: notebookActions) }
                row(.boardSearch, "Search boards", "text.magnifyingglass", count: nil)
            }

            Section {
                row(.settings, "Settings", "gearshape", count: nil)
            } footer: {
                if s.readOnlyReason != nil { Label("Read-only", systemImage: "lock").font(.caption) }
            }
        }
        .listStyle(.sidebar)
        .notebookPrompts(notebookActions, store: store)
        .onChange(of: ShortcutCenter.shared.notebookRequest) { _, _ in
            if s.isDataFolder { notebookActions.ask(.notebook, in: BoardFormat.notebooks) }
        }
        .onChange(of: store.openBoard?.path) { _, p in if let p { RecentBoards.add(p) } }
        .navigationTitle("Nexus")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.capture = .init(workstream: nil, parent: nil, plan: nil) } label: { Label("New task", systemImage: "square.and.pencil") }
                    .disabled(!s.isDataFolder)
            }
            ToolbarItem(placement: .topBarLeading) { NewWindowButton() }
        }
        .refreshable { store.reload() }
    }

    private func row(_ screen: Screen, _ title: String, _ icon: String, count: Int?) -> some View {
        NavigationLink(value: screen) {
            Label(title, systemImage: icon)
                .badge(count ?? 0)
        }
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
