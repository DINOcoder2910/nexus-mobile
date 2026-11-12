import SwiftUI
import NexusCore

/// Tasks: every task at full width, seen through the laptop's lenses (All, Deadlines, Waiting on, No date, Slipped, Done, Someday).
/// All groups the open tasks by workstream, each with its open subtasks folded under it; the other lenses are flat lists.
struct TasksView: View {
    @Environment(NexusStore.self) private var store
    @State private var lens: Planning.Lens
    @State private var query = ""
    @State private var searching = false
    /// Tasks whose subtasks are folded away (everything is open by default).
    @State private var folded: Set<String> = []

    init(lens: Planning.Lens = .all) {
        _lens = State(initialValue: lens)
    }

    var body: some View {
        let p = store.planning
        List {
            if lens == .all {
                allSections(p)
            } else {
                flatSection(p.tasks(lens))
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .top, spacing: 0) { lensBar(p) }
        .searchable(text: $query, isPresented: $searching, prompt: "Search tasks")
        .task(id: ShortcutCenter.shared.searchPending) {
            // Search tasks (a key, Settings › Shortcuts): into the search field once the screen is up
            guard ShortcutCenter.shared.searchPending else { return }
            ShortcutCenter.shared.searchPending = false
            try? await Task.sleep(for: .milliseconds(250))
            searching = true
        }
        .refreshable { store.reload() }
        .navigationTitle(lens == .someday ? "Someday" : "Tasks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.capture = .init(workstream: nil, parent: nil, plan: nil)
                } label: {
                    Label("Add a task", systemImage: "plus")
                }
            }
        }
    }

    // MARK: the lens bar

    private func lensBar(_ p: Planning) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Planning.Lens.allCases) { l in
                    lensButton(l, count: p.tasks(l).count)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func lensButton(_ l: Planning.Lens, count: Int) -> some View {
        let on = l == lens
        return Button {
            withAnimation(.snappy) { lens = l }
        } label: {
            HStack(spacing: 5) {
                Text(l.rawValue)
                if count > 0 { Text("\(count)").foregroundStyle(.secondary) }
            }
            .font(.subheadline.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? Theme.accent : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(on ? Theme.accent.opacity(0.15) : Color.secondary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: All: one section per workstream

    /// One workstream's part of the All lens (id nil = the Inbox).
    private struct Bucket: Identifiable {
        var id: String
        var workstream: String?
        var name: String
        var rows: [TaskTree.Row]
        var count: Int
    }

    private func buckets(_ p: Planning) -> [Bucket] {
        let s = store.snapshot
        let tops = p.tasks(.all)
        let q = trimmedQuery
        // Sections in the sidebar's order: groups, their workstreams, then the Inbox.
        var keys: [String?] = s.groups.flatMap { g in s.workstreams(in: g).map { Optional($0.id) } }
        keys.append(nil)
        var out: [Bucket] = []
        for key in keys {
            let rows: [TaskTree.Row]
            let count: Int
            if q.isEmpty {
                let roots = tops.filter { $0.workstream == key }
                rows = TaskTree.rows(roots, in: s, folded: folded, keep: { !$0.done && s.counts($0) })
                count = roots.count
            } else {
                // Searching: every matching open task of the workstream, at any depth, flat with its crumb.
                let hits = p.open.filter { $0.workstream == key && matches($0) }
                rows = hits.map { TaskTree.Row(task: $0, level: 0, hasKids: false) }
                count = hits.count
            }
            guard !rows.isEmpty else { continue }
            out.append(Bucket(id: key ?? "\u{0}inbox", workstream: key, name: store.workstream(key)?.name ?? "Inbox", rows: rows, count: count))
        }
        return out
    }

    @ViewBuilder
    private func allSections(_ p: Planning) -> some View {
        let list = buckets(p)
        if list.isEmpty {
            Section { emptyRow }
        }
        ForEach(list) { b in
            Section {
                ForEach(b.rows) { r in
                    TaskTreeRow(row: r, folded: $folded)
                        .taskSwipes(r.task, store: store)
                }
            } header: {
                HStack(spacing: 6) {
                    Circle().fill(store.color(workstream: b.workstream)).frame(width: 8, height: 8)
                    SectionTitle(title: b.name, count: b.count)
                }
            }
        }
    }

    // MARK: the other lenses: flat

    @ViewBuilder
    private func flatSection(_ tasks: [NexusTask]) -> some View {
        let shown = tasks.filter { matches($0) }
        if shown.isEmpty {
            Section { emptyRow }
        } else {
            Section {
                ForEach(shown) { t in
                    TaskRow(task: t, showWorkstream: true)
                        .taskSwipes(t, store: store)
                }
            } header: {
                SectionTitle(title: lens == .done ? "Done in the last 14 days" : lens.rawValue, count: shown.count)
            }
        }
    }

    // MARK: search and empty states

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private func matches(_ t: NexusTask) -> Bool {
        let q = trimmedQuery
        return q.isEmpty || t.text.localizedCaseInsensitiveContains(q)
    }

    private var emptyRow: some View {
        empty
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private var empty: EmptyNote {
        let q = trimmedQuery
        if !q.isEmpty { return EmptyNote(title: "No tasks match “\(q)”", detail: nil, icon: "magnifyingglass") }
        switch lens {
        case .all: return EmptyNote(title: "Nothing open", detail: "Add a task with + or capture one on the laptop.", icon: "checkmark.circle")
        case .deadlines: return EmptyNote(title: "No deadlines", detail: "Tasks with a deadline show here, key ones first.", icon: "flag")
        case .waiting: return EmptyNote(title: "Not waiting on anyone", detail: nil, icon: "hourglass")
        case .noDate: return EmptyNote(title: "Every task has a date", detail: "Tasks with no deadline, plan or repeat show here.", icon: "calendar")
        case .slipped: return EmptyNote(title: "Nothing slipped", detail: "Tasks planned for a day that passed show here.", icon: "checkmark.circle")
        case .done: return EmptyNote(title: "Nothing ticked in the last 14 days", detail: nil, icon: "checkmark.circle")
        case .someday: return EmptyNote(title: "Nothing parked for later", detail: "Tasks you send to Someday wait here.", icon: "moon.zzz")
        }
    }
}

// MARK: a task with its subtasks, as indented rows (shared with WorkstreamView)

enum TaskTree {
    /// One row of a tree: the task, how deep it sits under the row's root, and whether it has subtasks to fold.
    struct Row: Identifiable {
        var task: NexusTask
        var level: Int
        var hasKids: Bool
        var id: String { task.id }
    }

    /// The roots, each followed by the subtasks `keep` lets through (depth first, file order), skipping folded ones' subtasks.
    static func rows(_ roots: [NexusTask], in s: Snapshot, folded: Set<String>, keep: @escaping (NexusTask) -> Bool) -> [Row] {
        var out: [Row] = []
        func walk(_ t: NexusTask, _ level: Int) {
            let kids = s.children(of: t).filter(keep)
            out.append(Row(task: t, level: level, hasKids: !kids.isEmpty))
            if folded.contains(t.id) { return }
            for k in kids { walk(k, level + 1) }
        }
        for r in roots { walk(r, 0) }
        return out
    }
}

/// A tree row: indented by its level, with a chevron that folds its subtasks.
struct TaskTreeRow: View {
    let row: TaskTree.Row
    @Binding var folded: Set<String>
    var showWorkstream = false

    var body: some View {
        let isFolded = folded.contains(row.task.id)
        HStack(alignment: .top, spacing: 2) {
            if row.hasKids {
                Button {
                    // Adds the id when open, takes it out when folded.
                    withAnimation(.snappy) { folded.formSymmetricDifference([row.task.id]) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFolded ? 0 : 90))
                        .frame(width: 22, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isFolded ? "Show subtasks" : "Hide subtasks")
            } else {
                Color.clear.frame(width: 22, height: 30)
            }
            // A root shows its crumb (a subtask whose parent is done); indented rows sit under their parent already.
            TaskRow(task: row.task, showWorkstream: showWorkstream, showCrumb: row.level == 0, compact: row.level > 0)
        }
        .padding(.leading, CGFloat(row.level) * 22)
    }
}
