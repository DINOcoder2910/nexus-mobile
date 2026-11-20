import SwiftUI
import NexusCore

/// A subject's page in the new look (project files new-look/mockups/ipad-sidebar-light.png, iphone-subjects-light.png): the subject
/// in its colour with where it stands (open tasks, the next key date, cards due), then Overview | Tasks | Notebooks | Study | Files.
/// Overview puts together what is next, the study units, the subject's notebooks (matched by name: NexusCore SubjectNotebooks) and
/// its files; each other tab is that part's own screen (the workstream's task tree, the notebooks, the Study page, the folder).
struct SubjectPage: View {
    let workstreamId: String
    let go: (Screen) -> Void
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    @State private var tab: Tab = .overview
    @State private var notebooks: [String] = []
    @State private var boards: [Notebook.BoardRef] = []
    @State private var actions = NotebookActions()

    enum Tab: Hashable { case overview, tasks, notebooks, study, files }

    private var lib: StudyLibrary { StudyLibrary.shared }

    var body: some View {
        if let w = store.workstream(workstreamId) {
            page(w)
        } else {
            EmptyNote(title: "This subject is not in the folder", detail: "It may have been renamed or moved on the laptop.", icon: "questionmark.folder")
        }
    }

    private func tabs(_ w: Workstream) -> [(Tab, String)] {
        var t: [(Tab, String)] = [(.overview, "Overview"), (.tasks, "Tasks"), (.notebooks, "Notebooks")]
        if lib.study(w.id) != nil { t.append((.study, "Study")) }
        t.append((.files, "Files"))
        return t
    }

    @ViewBuilder
    private func page(_ w: Workstream) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(w)
                .padding(.horizontal, size == .regular ? 28 : 16)
                .padding(.top, 4)
            Group {
                switch tab {
                case .overview: overview(w)
                case .tasks: WorkstreamView(workstreamId: w.id)
                case .notebooks: notebooksTab(w)
                case .study: StudyPage(workstreamId: w.id)
                case .files: FilesView(path: w.folder, go: go)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .background(Kit.page)
        .navigationTitle(w.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.capture = .init(workstream: w.id, parent: nil, plan: nil) } label: { Label("Task", systemImage: "plus") }
                    .disabled(store.snapshot.readOnlyReason != nil)
                let due = lib.due(w.id)
                if due > 0 {
                    Button { withAnimation(Kit.spring) { tab = .study } } label: { Text("Review \(due)") }
                        .buttonStyle(.kitPrimary)
                }
            }
        }
        .notebookPrompts(actions, store: store)
        .task(id: "\(w.id)|\(store.notebooksVersion)|\(store.snapshot.loadedAt)") { readNotebooks(w) }
    }

    // MARK: the head

    private func header(_ w: Workstream) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle().fill(store.color(workstream: w.id)).frame(width: 14, height: 14)
                Text(w.name).font(.nx(size: size == .regular ? 40 : 32, .bold, display: true, relativeTo: .largeTitle)).foregroundStyle(Kit.ink).lineLimit(2)
            }
            Text(summary(w)).font(.nx(.body)).foregroundStyle(Kit.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                KitSwitch(items: tabs(w), selection: $tab)
            }
            .padding(.bottom, 12)
        }
    }

    /// "6 open tasks, unit test in 6 days. 12 cards due."
    private func summary(_ w: Workstream) -> String {
        let p = store.planning
        let n = p.openCount(w.id)
        var parts = [n == 1 ? "1 open task" : "\(n) open tasks"]
        if let key = p.keyDates.first(where: { $0.workstream == w.id && ($0.due ?? "") >= store.today }), let due = key.due {
            let days = Days.between(store.today, due)
            parts.append(key.title + " " + (days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days"))
        }
        var line = parts.joined(separator: ", ") + "."
        let due = lib.due(w.id)
        if due > 0 { line += " \(due) card\(due == 1 ? "" : "s") due." }
        return line
    }

    // MARK: Overview

    private func overview(_ w: Workstream) -> some View {
        ScrollView {
            if size == .regular {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 24) { nextUp(w); studyCard(w) }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 24) { notebooksCard(w); filesCard(w) }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            } else {
                VStack(alignment: .leading, spacing: 22) { nextUp(w); notebooksCard(w); studyCard(w); filesCard(w) }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 90)
            }
        }
    }

    private func cardHead(_ title: String, link: String?, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.nx(.title3, .semibold)).foregroundStyle(Kit.ink)
            Spacer()
            if let link, let action {
                Button(link, action: action).font(.nx(.subheadline, .medium)).foregroundStyle(Theme.accent).buttonStyle(.borderless)
            }
        }
    }

    /// The subject's next tasks: planned soonest, then due soonest, then the file's order.
    private func next(_ w: Workstream) -> [NexusTask] {
        let open = store.planning.open.filter { $0.workstream == w.id }
        func when(_ t: NexusTask) -> String { ([t.plannedDays.min(), t.due].compactMap { $0 }.min()) ?? "9999" }
        return Array(open.sorted { (when($0), $0.order) < (when($1), $1.order) }.prefix(3))
    }

    private func nextUp(_ w: Workstream) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHead("Next up", link: "All") { withAnimation(Kit.spring) { tab = .tasks } }
            let list = next(w)
            VStack(spacing: 0) {
                if list.isEmpty {
                    Text("Nothing open here.").font(.nx(.callout)).foregroundStyle(Kit.muted).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Kit.line.frame(height: 1).padding(.leading, 52) }
                    TaskRow(task: t, showWorkstream: false)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { store.openTaskId = t.id }
                }
            }
            .kitSurface()
        }
    }

    @ViewBuilder
    private func studyCard(_ w: Workstream) -> some View {
        if let s = lib.study(w.id) {
            VStack(alignment: .leading, spacing: 10) {
                cardHead("Study", link: "Open") { withAnimation(Kit.spring) { tab = .study } }
                VStack(alignment: .leading, spacing: 12) {
                    let units = s.units ?? []
                    if units.isEmpty {
                        Text("Units show here once study/units.yaml lists them.").font(.nx(.callout)).foregroundStyle(Kit.muted)
                    } else {
                        let done = units.filter { $0.status == "done" }.count, part = units.filter { $0.status == "partial" }.count
                        HStack(spacing: 14) {
                            UnitRing(done: done, part: part, total: units.count)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Units covered").font(.nx(.headline)).foregroundStyle(Kit.ink)
                                Text("\(done) done\(part > 0 ? ", \(part) partly" : ""), of \(units.count)").font(.nx(.subheadline)).foregroundStyle(Kit.muted)
                            }
                        }
                        if let now = StudyUnits.current(units), let u = units.first(where: { $0.code == now }) {
                            HStack(spacing: 8) {
                                UnitChip(code: u.code, status: "now", color: store.color(workstream: w.id))
                                Text(u.title).font(.nx(.callout)).foregroundStyle(Kit.ink).lineLimit(1)
                            }
                        }
                    }
                    let due = lib.due(w.id)
                    if due > 0 {
                        Text("\(due) card\(due == 1 ? "" : "s") to review").font(.nx(.subheadline)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kitSurface()
            }
        }
    }

    private func notebooksCard(_ w: Workstream) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHead("Notebooks", link: notebooks.isEmpty ? nil : "All") { withAnimation(Kit.spring) { tab = .notebooks } }
            if boards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(notebooks.isEmpty ? "No notebook is named for \(w.name) yet. A notebook called \(w.name.components(separatedBy: " ")[0]) shows here."
                                           : "Its notebooks have no boards yet.")
                        .font(.nx(.callout)).foregroundStyle(Kit.muted)
                    if notebooks.isEmpty {
                        Button("New notebook…") { actions.ask(.notebook, in: BoardFormat.notebooks) }.buttonStyle(.kit)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .kitSurface()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: size == .regular ? 160 : 140), spacing: 14)], spacing: 14) {
                    ForEach(boards.prefix(4)) { b in BoardCard(b: b, actions: actions, share: {}) }
                }
            }
        }
    }

    private func filesCard(_ w: Workstream) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            cardHead("Files", link: "All") { withAnimation(Kit.spring) { tab = .files } }
            Button { withAnimation(Kit.spring) { tab = .files } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder").font(.system(size: 18)).foregroundStyle(Kit.muted)
                        .frame(width: 38, height: 38).background(Kit.hover, in: RoundedRectangle(cornerRadius: Kit.controlRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.folder.components(separatedBy: "/").last ?? w.folder).font(.nx(.callout, .medium)).foregroundStyle(Kit.ink)
                        Text(w.folder).font(.nx(.caption)).foregroundStyle(Kit.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.nx(.caption, .semibold)).foregroundStyle(Kit.faint)
                }
                .padding(12)
                .kitSurface()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Notebooks

    @ViewBuilder
    private func notebooksTab(_ w: Workstream) -> some View {
        if notebooks.count == 1 {
            NotebookPage(path: notebooks[0], go: go)
        } else {
            List {
                if notebooks.isEmpty {
                    Text("No notebook is named for \(w.name) yet.").foregroundStyle(.secondary)
                    Button("New notebook…") { actions.ask(.notebook, in: BoardFormat.notebooks) }
                }
                ForEach(notebooks, id: \.self) { p in
                    Button { go(.notebook(p)) } label: {
                        Label((p as NSString).lastPathComponent, systemImage: "book.closed").foregroundStyle(Kit.ink)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// The notebooks named for this subject, and their first boards (one listing per top notebook).
    private func readNotebooks(_ w: Workstream) {
        let root = store.folder
        let candidates = Notebook.top(root).flatMap { [$0] + Notebook.level(root, $0).notebooks }
        notebooks = SubjectNotebooks.match(name: w.name, aliases: w.aliases, candidates: candidates)
        boards = Array(notebooks.flatMap { Notebook.level(root, $0).boards }.prefix(8))
    }
}

/// How much of a subject's units is covered, as a ring: done in the accent, partly in amber.
struct UnitRing: View {
    let done: Int
    let part: Int
    let total: Int

    var body: some View {
        let t = CGFloat(max(total, 1))
        ZStack {
            Circle().stroke(Kit.hover, lineWidth: 5)
            Circle().trim(from: 0, to: CGFloat(done) / t).stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Circle().trim(from: CGFloat(done) / t, to: CGFloat(done + part) / t).stroke(Theme.soon, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(Int((CGFloat(done) + CGFloat(part) / 2) / t * 100))").font(.nx(size: 13, .semibold, display: true)).foregroundStyle(Kit.ink)
        }
        .frame(width: 46, height: 46)
        .accessibilityLabel("\(done) of \(total) units done")
    }
}
