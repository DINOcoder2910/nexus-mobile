import SwiftUI
import NexusCore

/// The sidebar in the new look (picked Nov 20 2026, project files new-look/mockups/sketch-sidebar-combined.png): the places at the
/// top, then the subjects (the workstreams, by group), each holding its own tasks, notebooks, study and files; then Recent and
/// every notebook. A subject's **arrow** opens it like a folder, right where it is (you stay on your page; several can be open);
/// tapping its **name** steps inside: the sidebar becomes just that subject, the places shrink to small icons on top, and the
/// subject's page opens; Back (or Esc) returns to the full list. Claude, Ideas, Time, Files, Settings and the guide sit as icons at
/// the foot. The notebooks are a tree with their boards (NotebooksList).
/// Quick to get around a big notebooks folder (Nov 24 2026: the sidebar had grown too long to scroll): **Find a notebook or board**
/// at the top (every notebook and board by name, from the tree's walk: NexusCore NotebookFind), **Pinned** notebooks and boards
/// (a row's menu › Pin to the top; each device its own), and the Notebooks section folds away like a group. Nov 25 2026 (a tree
/// of arrows still went too many levels deep in a OneNote import): the full list shows only the top notebooks, and tapping a
/// notebook **steps inside** it like a subject: the sidebar becomes that notebook alone (Back, the notebooks it holds, then its
/// boards), one level at a time, going straight through a notebook that only holds one notebook (NotebookTree.stepping).
/// On the iPhone the same list is the More tab (`pushes`: its rows push onto the tab's stack) and, cut to the subjects and the
/// notebooks, the Subjects tab (`subjectsTab`).
struct Sidebar: View {
    @Environment(NexusStore.self) private var store
    /// (Drop's count looks again when a file comes in)
    @Environment(SyncService.self) private var sync
    @Binding var selection: Screen?
    var pushes = false
    /// The iPhone's Subjects tab: the subjects (each opens its page), then every notebook.
    var subjectsTab = false
    var title = "Nexus"
    @AppStorage("closedGroups") private var closedGroups = ""
    /// The subjects opened with their arrow ("id|id"), and the ones whose Notebooks row is open ("nb:id").
    @AppStorage("openSubjects") private var openSubjects = ""
    /// The subject the sidebar has stepped inside (its name was tapped), or nil for the full list. Per window.
    @State private var inside: String?
    /// The notebook the sidebar has stepped inside (its row was tapped, its page opened), or "" for the list. Per window. It comes
    /// before a subject: Back from a top notebook returns to the subject the sidebar was inside, if any.
    @State private var inNotebook = ""
    @State private var notebookActions = NotebookActions()
    @State private var wsActions = WorkstreamActions()
    /// The notebook tree's view of the folder, read lazily (NotebookTreeModel).
    @State private var notebookTree = NotebookTreeModel()
    @Environment(\.scenePhase) private var phase
    /// What the find field at the top holds; while it holds something, the sidebar lists what it finds.
    @State private var find = ""
    @FocusState private var findFocused: Bool
    /// The pinned notebooks and boards ("a|b", in the order pinned; PinButton).
    @AppStorage(NotebookPins.key) private var pinned = ""

    var body: some View {
        let s = store.snapshot
        ScrollViewReader { proxy in
            Group {
                if pushes {
                    List { sections }.listStyle(.insetGrouped)
                } else {
                    List(selection: listSelection) {
                        if !inNotebook.isEmpty, s.isDataFolder, exists(inNotebook) {
                            notebookSections(inNotebook)
                        } else if let w = inside.flatMap({ store.workstream($0) }), s.isDataFolder {
                            insideSections(w)
                        } else {
                            sections
                        }
                    }
                    .listStyle(.sidebar)
                    .animation(Kit.spring, value: inside)
                    .animation(Kit.spring, value: inNotebook)
                }
            }
            .onChange(of: store.openBoard?.path, initial: true) { _, p in
                guard let p else { return }
                RecentBoards.add(p)
                // inside a notebook, a board opened from elsewhere (find, a link, the board's own page): the sidebar shows its notebook
                let home = (p as NSString).deletingLastPathComponent
                if !pushes, !inNotebook.isEmpty, home != inNotebook, home.hasPrefix(BoardFormat.notebooks + "/") { inNotebook = home }
                // a board opened from elsewhere (search, Recent, a link): its row comes into view, ready for the next tap
                if !pushes { DispatchQueue.main.async { proxy.scrollTo(p) } }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !pushes { footer }
        }
        .notebookPrompts(notebookActions, store: store)
        .workstreamPrompts(wsActions, store: store)
        .onAppear { wsActions.made = { id in if !pushes { selection = .subject(id) } } }
        // a subject's page opened from elsewhere (a workstream just made, a link) while the sidebar is inside another: it follows
        .onChange(of: selection) { _, new in
            if case .subject(let id)? = new, let i = inside, i != id { withAnimation(Kit.spring) { inside = id } }
            if case .subject(_)? = new, !inNotebook.isEmpty { withAnimation(Kit.spring) { inNotebook = "" } }
            // a notebook's page opened (its row, a card on another notebook's page, a found or pinned one): the sidebar steps inside it
            if case .notebook(let p)? = new, !pushes {
                let to = step(into: p)
                if to != p { selection = .notebook(to) }
            }
        }
        .onChange(of: ShortcutCenter.shared.notebookRequest) { _, _ in
            if s.isDataFolder && !pushes { notebookActions.ask(.notebook, in: BoardFormat.notebooks) }
        }
        // the app made, renamed, moved or deleted a notebook or board: the tree reads it all again; another writer (sync, another
        // window) or coming back to the app: it looks for what changed, away from the main thread
        .onChange(of: store.notebooksVersion) { _, _ in notebookTree.dropAll() }
        .onReceive(NotificationCenter.default.publisher(for: NexusStore.readAgain)) { _ in notebookTree.check() }
        .onChange(of: phase) { _, now in if now == .active { notebookTree.check() } }
        .navigationTitle(title)
        .toolbar {
            if !subjectsTab {
                ToolbarItem(placement: .primaryAction) {
                    Button { store.capture = .init(workstream: nil, parent: nil, plan: nil) } label: { Label("New task", systemImage: "square.and.pencil") }
                        .disabled(!s.isDataFolder)
                }
            } else if s.isDataFolder {
                ToolbarItem(placement: .primaryAction) {
                    Button { notebookActions.ask(.notebook, in: BoardFormat.notebooks) } label: { Label("New notebook", systemImage: "folder.badge.plus") }
                }
                // New workstream, in a group (the iPad has it on a hold of a group's name)
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Section("New workstream in…") {
                            ForEach(s.groups) { g in Button(g.label) { wsActions.ask(.create(group: g.id)) } }
                        }
                    } label: { Label("New workstream", systemImage: "plus") }
                    .disabled(s.readOnlyReason != nil)
                    .accessibilityIdentifier("new-workstream")
                }
            }
        }
        .refreshable { store.reload(); notebookTree.dropAll() }
        // the study decks: read with the folder (their due count is the Study row's number)
        .task(id: store.snapshot.loadedAt) { StudyLibrary.shared.refreshIfChanged(store) }
        // the Spanish workstreams (the Spanish row), read with the folder too
        .task(id: store.snapshot.loadedAt) { SpanishLibrary.shared.refreshIfChanged(store) }
    }

    // MARK: the full list

    /// The find field shows on the iPad's sidebar and the iPhone's Subjects tab (where the notebooks are), not in the iPhone's More.
    private var showsFind: Bool { store.snapshot.isDataFolder && (!pushes || subjectsTab) }

    @ViewBuilder
    private var sections: some View {
        if showsFind {
            Section { findField }
        }
        if showsFind && !NotebookFind.fold(find).isEmpty {
            findResults
        } else {
            listSections
        }
    }

    @ViewBuilder
    private var listSections: some View {
        let p = store.planning
        let s = store.snapshot
        // the iPhone's More: where this phone stands with the hub, on top (the iPad has it at the sidebar's foot)
        if pushes && !subjectsTab && sync.chip.tone != .hidden {
            Section { SyncChipView() }
        }
        if !subjectsTab {
            // the running timer, whichever device started it (TimeViews.swift)
            if s.isDataFolder && TimeTracker.shared.current != nil {
                Section { SidebarTimerRow() }
            }
            Section {
                row(.home, "Home", "house", count: nil)
                row(.today, "Today", "sun.max", count: p.todayPlan.count)
                row(.planner, "Planner", "rectangle.split.3x1", count: nil)
                row(.tasks, "Tasks", "checklist", count: nil)
                row(.calendar, "Calendar", "calendar", count: nil)
                if s.isDataFolder && s.workstreams.values.contains(where: { $0.kind == "school" }) {
                    row(.applications, "Applications", "graduationcap", count: nil)
                }
                if s.isDataFolder && StudyLibrary.shared.hasStudy {
                    row(.study, "Study", "rectangle.on.rectangle.angled", count: StudyLibrary.shared.dueTotal)
                }
                if s.isDataFolder {
                    row(.recordings, "Recordings", "waveform", count: RecordingsCount.review(store))
                        .accessibilityIdentifier("sidebar-recordings")
                    row(.drop, "Drop", "paperplane", count: DropCount.new(store, version: sync.dropVersion))
                        .accessibilityIdentifier("sidebar-drop")
                    row(.inbox, "Inbox", "tray", count: p.openCount(nil))
                    row(.someday, "Someday", "moon.zzz", count: nil)
                }
                // the iPad has these as icons at the foot; the iPhone's More lists them
                if pushes {
                    row(.ideas, "Ideas", "lightbulb", count: nil)
                    if s.isDataFolder {
                        row(.claude, "Claude", "sparkles", count: ClaudeChatSession.shared.conversation("main").pendingCount)
                            .accessibilityIdentifier("sidebar-claude")
                    }
                }
            }
        }

        if s.isDataFolder {
            ForEach(s.groups) { g in
                let list = s.workstreams(in: g).filter { !$0.finished }
                if !list.isEmpty {
                    Section(isExpanded: open(g.id)) {
                        ForEach(list) { w in subject(w) }
                    } header: {
                        Text(g.label).font(.nx(.subheadline, .semibold)).foregroundStyle(Kit.ink)
                            .contextMenu {
                                Button { wsActions.ask(.create(group: g.id)) } label: { Label("New workstream in \(g.label)…", systemImage: "plus") }
                                    .disabled(s.readOnlyReason != nil)
                            }
                    }
                }
            }
        }

        if s.isDataFolder {
            let pins = pinnedPaths
            if !pins.isEmpty {
                Section("Pinned") {
                    ForEach(pins, id: \.self) { p in
                        entryRow(NotebookFind.Entry(kind: p.lowercased().hasSuffix(".board") ? .board : .notebook, path: p))
                    }
                }
            }
        }

        if !subjectsTab, s.isDataFolder {
            let pins = Set(pinnedPaths)
            let recent = RecentBoards.list(store.folder).filter { !pins.contains($0) }
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

        // folds away like a group (remembered with them)
        Section(isExpanded: open(Self.notebooksSection)) {
            if s.isDataFolder { NotebooksList(actions: notebookActions, pushes: pushes, tree: notebookTree) }
            row(.boardSearch, "Search boards", "text.magnifyingglass", count: nil)
        } header: {
            Text("Notebooks")
        }

        if pushes && !subjectsTab {
            Section {
                if s.isDataFolder { row(.time, "Time", "timer", count: nil) }
                if s.isDataFolder { row(.files(""), "Files", "folder", count: nil) }
                row(.settings, "Settings", "gearshape", count: nil)
                row(.guide, "How Nexus works", "questionmark.circle", count: nil)
            } footer: {
                if s.readOnlyReason != nil { Label("Read-only", systemImage: "lock").font(.nx(.caption)) }
            }
        }
    }

    // MARK: find, pinned

    /// The closed-groups key the Notebooks section folds with (no group id starts with "_").
    static let notebooksSection = "_notebooks"

    /// The pinned paths that are still there.
    private var pinnedPaths: [String] {
        PathList.parse(pinned).filter { FileManager.default.fileExists(atPath: store.folder.appendingPathComponent($0).path) }
    }

    /// "Find a notebook or board": every notebook and board by its name (and where it sits), as you type.
    private var findField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.nx(.subheadline)).foregroundStyle(Kit.muted)
            TextField("Find a notebook or board", text: $find)
                .font(.nx(.body))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($findFocused)
                .onSubmit { if let first = findHits.first { openEntry(first) } }
                .accessibilityIdentifier("notebook-find")
            if !find.isEmpty {
                Button {
                    find = ""
                    findFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Kit.muted)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear the find field")
                .accessibilityIdentifier("notebook-find-clear")
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 36)
        .background(Kit.hover, in: RoundedRectangle(cornerRadius: Kit.controlRadius, style: .continuous))
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
    }

    /// The most the find field lists.
    private static let findLimit = 40

    private var findHits: [NotebookFind.Entry] {
        NotebookFind.search(find, in: notebookTree.findEntries, recent: RecentBoards.list(store.folder) + pinnedPaths, limit: Self.findLimit)
    }

    /// What the find field found: boards and notebooks with where each sits, best first.
    @ViewBuilder
    private var findResults: some View {
        let hits = findHits
        Section {
            if hits.isEmpty {
                Text(notebookTree.scanned ? "No notebook or board called “\(find.trimmingCharacters(in: .whitespaces))”" : "Reading the notebooks…")
                    .font(.nx(.subheadline))
                    .foregroundStyle(Kit.muted)
                    .accessibilityIdentifier("notebook-find-none")
            }
            ForEach(hits) { h in entryRow(h) }
        } header: {
            if !hits.isEmpty {
                Text(hits.count >= Self.findLimit ? "The first \(Self.findLimit): type more to narrow it" : hits.count == 1 ? "1 found" : "\(hits.count) found")
            }
        }
    }

    /// Opens a found or pinned board or notebook (on the iPad a notebook's page shows in place of the open board).
    private func openEntry(_ e: NotebookFind.Entry) {
        findFocused = false
        if e.kind == .board {
            store.openBoard = .init(path: e.path, focus: nil)
        } else if !pushes {
            store.openBoard = nil
            selection = .notebook(e.path)
        }
    }

    /// A found or pinned board or notebook: its name, and where it sits under it. Its menu is the tree row's (Pin, Move to…).
    @ViewBuilder
    private func entryRow(_ e: NotebookFind.Entry) -> some View {
        let showing = e.kind == .board && store.openBoard?.path == e.path
        let label = HStack(spacing: 10) {
            // Color's grey, not .secondary: in a button that is the tint's (green) secondary
            Image(systemName: e.kind == .board ? "scribble" : "book.closed")
                .font(.nx(.footnote)).foregroundStyle(Color.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.name).lineLimit(1).foregroundStyle(showing ? Theme.accent : Kit.ink)
                if !e.place.isEmpty {
                    Text(e.place).font(.nx(.caption)).foregroundStyle(Kit.muted).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        if e.kind == .notebook {
            Group {
                if pushes {
                    NavigationLink(value: Screen.notebook(e.path)) { label }
                } else {
                    Button { openEntry(e) } label: { label }
                }
            }
            .notebookRowMenu(notebookTree.notebook(e.path), actions: notebookActions, store: store)
        } else {
            Button { openEntry(e) } label: { label }
                .boardRowMenu(Notebook.BoardRef(name: e.name, path: e.path), actions: notebookActions)
        }
    }

    // MARK: a subject

    private func isOpen(_ key: String) -> Bool { openSubjects.split(separator: "|").contains(Substring(key)) }

    private func setOpen(_ key: String, _ on: Bool) {
        var set = openSubjects.split(separator: "|").map(String.init)
        set.removeAll { $0 == key }
        if on { set.append(key) }
        withAnimation(Kit.spring) { openSubjects = set.joined(separator: "|") }
    }

    /// A subject's row: its arrow (opens it as a folder, on the iPad), its colour and name (steps inside on the iPad, opens its page
    /// on the iPhone) and its open tasks; when open, its Tasks, Notebooks, Study and Files under it.
    @ViewBuilder
    private func subject(_ w: Workstream) -> some View {
        let school = w.kind == "school"
        let open = !pushes && !school && isOpen(w.id)
        let label = HStack(spacing: 10) {
            Circle().fill(store.color(workstream: w.id)).frame(width: 9, height: 9)
            Text(w.name).lineLimit(1).foregroundStyle(w.parked ? Kit.muted : Kit.ink)
            Spacer(minLength: 4)
            let n = store.planning.openCount(w.id)
            if n > 0 && !w.parked { Text("\(n)").font(.nx(.caption)).foregroundStyle(.secondary).monospacedDigit() }
        }
        .contentShape(Rectangle())
        if pushes {
            NavigationLink(value: school ? Screen.school(w.id) : Screen.subject(w.id)) { label }
                .contextMenu { WorkstreamMenu(workstream: w, actions: wsActions) }
                .accessibilityIdentifier("subject-" + w.id)
        } else {
            HStack(spacing: 2) {
                if school {
                    Color.clear.frame(width: NotebookTreeLine.arrowWidth, height: 1)
                } else {
                    arrow(open, name: w.name) { setOpen(w.id, !open) }
                }
                // no id on the iPad's row: on the row its arrow took the id too (a tap "on the row" opened it), and on the name it
                // would hide the name from tests that find the row by it; tests tap the name
                label
            }
            .contextMenu { WorkstreamMenu(workstream: w, actions: wsActions) }
            .tag(SidebarItem.screen(school ? .school(w.id) : .subject(w.id)))
            if open { subjectParts(w, indent: 1) }
        }
    }

    /// The arrow before a subject or its Notebooks row: turns as it opens.
    private func arrow(_ open: Bool, name: String, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Image(systemName: "chevron.right")
                .font(.nx(.caption, .semibold))
                .foregroundStyle(Color.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
                .frame(width: NotebookTreeLine.arrowWidth, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel((open ? "Collapse " : "Expand ") + name)
    }

    /// What a subject holds: its tasks, its notebooks (a tree, by name: NexusCore SubjectNotebooks), its study and its files.
    @ViewBuilder
    private func subjectParts(_ w: Workstream, indent: Int) -> some View {
        let pad = CGFloat(indent) * 18
        let lib = StudyLibrary.shared
        part(.workstream(w.id), "Tasks", "checklist", count: store.planning.openCount(w.id).nonZero, pad: pad)
        let nbs = subjectNotebooks(w)
        let nbOpen = isOpen("nb:" + w.id)
        HStack(spacing: 2) {
            Color.clear.frame(width: pad, height: 1)
            arrow(nbOpen, name: "Notebooks of " + w.name) { setOpen("nb:" + w.id, !nbOpen) }
            HStack(spacing: 10) {
                Image(systemName: "book.closed").foregroundStyle(.secondary).frame(width: 20)
                Text("Notebooks")
                Spacer(minLength: 4)
                let n = nbs.reduce(0) { $0 + (notebookTree.counts[$1] ?? 0) }
                if n > 0 { Text("\(n)").font(.nx(.caption)).foregroundStyle(.secondary).monospacedDigit() }
            }
            .contentShape(Rectangle())
            .onTapGesture { setOpen("nb:" + w.id, !nbOpen) }
        }
        if nbOpen {
            if nbs.isEmpty {
                HStack(spacing: 2) {
                    Color.clear.frame(width: pad + NotebookTreeLine.arrowWidth + 30, height: 1)
                    Button { notebookActions.ask(.notebook, in: BoardFormat.notebooks) } label: {
                        Text("New notebook…").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                // the subject's notebooks; tapping one steps inside it
                ForEach(notebookTree.rows(store.folder, top: nbs, open: [])) { r in
                    NotebookTreeLine(row: r, nb: notebookTree.notebook(r.path), pushes: false, actions: notebookActions)
                        .padding(.leading, pad + NotebookTreeLine.arrowWidth + 2)
                        .tag(SidebarItem.screen(.notebook(r.path)))
                }
            }
        }
        if lib.study(w.id) != nil {
            let due = lib.due(w.id)
            HStack(spacing: 2) {
                Color.clear.frame(width: pad + NotebookTreeLine.arrowWidth, height: 1)
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.on.rectangle.angled").foregroundStyle(.secondary).frame(width: 20)
                    Text("Study")
                    Spacer(minLength: 4)
                    if due > 0 { Text("\(due) due").font(.nx(.caption, .medium)).foregroundStyle(Theme.accent).monospacedDigit() }
                }
                .contentShape(Rectangle())
            }
            .tag(SidebarItem.screen(.studyPage(w.id)))
            .accessibilityIdentifier("subject-study-" + w.id)
        }
        part(.files(w.folder), "Files", "folder", count: nil, pad: pad)
    }

    private func part(_ screen: Screen, _ title: String, _ icon: String, count: Int?, pad: CGFloat) -> some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: pad + NotebookTreeLine.arrowWidth, height: 1)
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
                Text(title)
                Spacer(minLength: 4)
                if let count { Text("\(count)").font(.nx(.caption)).foregroundStyle(.secondary).monospacedDigit() }
            }
            .contentShape(Rectangle())
        }
        .tag(SidebarItem.screen(screen))
    }

    /// The notebooks a subject holds, by their names (NexusCore SubjectNotebooks).
    private func subjectNotebooks(_ w: Workstream) -> [String] {
        SubjectNotebooks.match(name: w.name, aliases: w.aliases, candidates: notebookTree.candidates(store.folder))
    }

    // MARK: inside a subject

    /// The sidebar stepped inside a subject: the places as small icons, Back with the subject's name, then what it holds.
    @ViewBuilder
    private func insideSections(_ w: Workstream) -> some View {
        Section {
            placeIcons
        }
        Section {
            Button {
                withAnimation(Kit.spring) { inside = nil }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.backward").font(.nx(.subheadline, .semibold)).foregroundStyle(Kit.muted)
                    Circle().fill(store.color(workstream: w.id)).frame(width: 10, height: 10)
                    Text(w.name).font(.nx(.title3, .semibold)).foregroundStyle(Kit.ink).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Back to every subject")
            .accessibilityValue(w.name)
            .accessibilityIdentifier("subject-back")
            HStack(spacing: 2) {
                Color.clear.frame(width: NotebookTreeLine.arrowWidth, height: 1)
                Label("Overview", systemImage: "square.grid.2x2")
            }
            .tag(SidebarItem.screen(.subject(w.id)))
            subjectParts(w, indent: 0)
        }
    }

    // MARK: inside a notebook

    private func exists(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: store.folder.appendingPathComponent(path).path, isDirectory: &dir) && dir.boolValue
    }

    /// Steps the sidebar inside the notebook `path` (straight through notebooks that only hold one): the notebook it shows, whose
    /// page should show too.
    @discardableResult
    private func step(into path: String) -> String {
        guard path.hasPrefix(BoardFormat.notebooks + "/") else { return path }
        let to = notebookTree.stepping(into: path, store.folder)
        if !find.isEmpty { find = ""; findFocused = false }
        if to != inNotebook { withAnimation(Kit.spring) { inNotebook = to } }
        return to
    }

    private func stepBack(from path: String) {
        let to = notebookTree.back(from: path, store.folder) ?? ""
        withAnimation(Kit.spring) { inNotebook = to }
    }

    /// The sidebar inside a notebook: the find field, the places as small icons, Back with the notebook's name and where it sits,
    /// its page, then the notebooks it holds and its boards. Nothing opens in place: a notebook steps further in, a board opens.
    @ViewBuilder
    private func notebookSections(_ path: String) -> some View {
        let l = notebookTree.shown(store.folder, path)
        let crumbs = NotebookTree.crumbs(path)
        let top = crumbs.first.map { notebookTree.shown(store.folder, $0.path) }
        Section { findField }
        if !NotebookFind.fold(find).isEmpty {
            findResults
        } else {
            Section { placeIcons }
            Section {
                Button { stepBack(from: path) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.backward").font(.nx(.subheadline, .semibold)).foregroundStyle(Kit.muted)
                        if let c = top?.color {
                            Circle().fill(Color(uiColor: InkConvert.color(c))).frame(width: 10, height: 10)
                        } else {
                            Image(systemName: "book.closed").font(.nx(.subheadline)).foregroundStyle(Kit.muted)
                        }
                        Text(l.name).font(.nx(.title3, .semibold)).foregroundStyle(Kit.ink).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Back")
                .accessibilityValue(l.name)
                .accessibilityIdentifier("notebook-back")
                if crumbs.count > 1 { crumbRow(crumbs.dropLast()) }
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).frame(width: 20)
                    Text("Notebook page")
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
                .tag(SidebarItem.screen(.notebook(path)))
            }
            if !l.notebooks.isEmpty {
                Section("Notebooks") {
                    ForEach(notebookTree.rows(store.folder, top: l.notebooks, open: [])) { r in
                        NotebookTreeLine(row: r, nb: notebookTree.notebook(r.path), pushes: false, actions: notebookActions)
                            .tag(SidebarItem.screen(.notebook(r.path)))
                    }
                }
            }
            Section {
                ForEach(l.boards) { b in
                    NotebookTreeLine(row: NotebookTreeRow(kind: .board, name: b.name, path: b.path, depth: 0), nb: nil, pushes: false, actions: notebookActions)
                        .tag(SidebarItem.board(b.path))
                        .id(b.path)
                }
                if l.isEmpty {
                    Text("Nothing in this notebook yet").font(.nx(.subheadline)).foregroundStyle(Kit.muted)
                }
                Button { notebookActions.ask(.notebook, in: path) } label: {
                    Label("New notebook in \(l.name)…", systemImage: "plus").foregroundStyle(.secondary)
                }
            } header: {
                if !l.boards.isEmpty { Text(l.boards.count == 1 ? "1 board" : "\(l.boards.count) boards") }
            }
        }
    }

    /// Where the notebook sits, above it: Notebooks › Tutor › Physics (as the page says it), each a tap back to it (a notebook that only holds one
    /// notebook is gone through, so it is named but not a stop).
    private func crumbRow(_ above: ArraySlice<NotebookCrumb>) -> some View {
        // on one line when it fits; else it scrolls, showing its end (the notebook just above), its start faded where it is cut
        ViewThatFits(in: .horizontal) {
            crumbLine(above)
            ScrollView(.horizontal, showsIndicators: false) { crumbLine(above) }
                .defaultScrollAnchor(.trailing)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                             .init(color: .black, location: 1)], startPoint: .leading, endPoint: .trailing))
        }
        .listRowBackground(Color.clear)
    }

    private func crumbLine(_ above: ArraySlice<NotebookCrumb>) -> some View {
        HStack(spacing: 4) {
            Button("Notebooks") { withAnimation(Kit.spring) { inNotebook = "" } }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("notebook-crumb-all")
            ForEach(above) { c in
                Image(systemName: "chevron.right").font(.nx(.caption2, .semibold)).foregroundStyle(Kit.muted)
                if NotebookTree.passesThrough(notebookTree.shown(store.folder, c.path)) {
                    Text(c.name).foregroundStyle(Kit.muted)
                } else {
                    Button(c.name) { withAnimation(Kit.spring) { inNotebook = c.path } }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("notebook-crumb-" + c.name)
                }
            }
        }
        .font(.nx(.footnote))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Home, Today, Planner, Tasks, Calendar and Inbox as small icons, so they stay one tap away inside a subject.
    private var placeIcons: some View {
        HStack(spacing: 4) {
            ForEach(Self.places) { place in
                let on = selection == place.screen && store.openBoard == nil
                Button { go(place.screen) } label: {
                    Image(systemName: place.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(on ? Theme.accent : Kit.muted)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(on ? Kit.accentWash : Kit.hover, in: RoundedRectangle(cornerRadius: Kit.controlRadius, style: .continuous))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(place.title)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
        .listRowBackground(Color.clear)
    }

    private static let places: [SidebarIcon] = [
        .init(screen: .home, title: "Home", icon: "house"), .init(screen: .today, title: "Today", icon: "sun.max"),
        .init(screen: .planner, title: "Planner", icon: "rectangle.split.3x1"), .init(screen: .tasks, title: "Tasks", icon: "checklist"),
        .init(screen: .calendar, title: "Calendar", icon: "calendar"), .init(screen: .inbox, title: "Inbox", icon: "tray"),
    ]

    // MARK: the foot

    /// Claude, Ideas, Time, Files, Settings and How Nexus works, as icons along the sidebar's foot (the iPad).
    private var footer: some View {
        let s = store.snapshot
        var items: [SidebarIcon] = []
        if s.isDataFolder { items.append(.init(screen: .claude, title: "Claude", icon: "sparkles", id: "sidebar-claude")) }
        items.append(.init(screen: .ideas, title: "Ideas", icon: "lightbulb"))
        if s.isDataFolder {
            items.append(.init(screen: .time, title: "Time", icon: "timer"))
            items.append(.init(screen: .files(""), title: "Files", icon: "folder"))
        }
        items.append(.init(screen: .settings, title: "Settings", icon: "gearshape"))
        items.append(.init(screen: .guide, title: "How Nexus works", icon: "questionmark.circle"))
        let pending = s.isDataFolder ? ClaudeChatSession.shared.conversation("main").pendingCount : 0
        return VStack(spacing: 0) {
            if s.readOnlyReason != nil {
                Label("Read-only", systemImage: "lock").font(.nx(.caption)).foregroundStyle(.secondary).padding(.bottom, 6)
            }
            // where this iPad stands with the hub (hidden while sync is off)
            if sync.chip.tone != .hidden {
                HStack {
                    SyncChipView { go(.settings) }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            HStack(spacing: 0) {
                ForEach(items) { item in
                    let screen = item.screen
                    let on = selection == screen && store.openBoard == nil
                    Button { go(screen) } label: {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(on ? Theme.accent : (screen == .claude ? Theme.claude : Kit.muted))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(on ? Kit.accentWash : .clear, in: RoundedRectangle(cornerRadius: Kit.controlRadius, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if screen == .claude && pending > 0 {
                                    Circle().fill(Theme.claude).frame(width: 7, height: 7).offset(x: -10, y: 7)
                                }
                            }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(item.title)
                    .accessibilityIdentifier(item.id)
                    .hoverEffect(.highlight)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(alignment: .top) {
            Kit.line.frame(height: 1)
        }
        .background(.bar)
    }

    // MARK: rows and selection

    private func go(_ s: Screen) {
        if selection == s { store.openBoard = nil } else { selection = s }
    }

    private func row(_ screen: Screen, _ title: String, _ icon: String, count: Int?) -> some View {
        link(screen) {
            Label(title, systemImage: icon)
                .badge(count ?? 0)
        }
        .accessibilityIdentifier("sidebar-" + title)
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
    /// screen shows it (and closes the board, also when it is the screen that was showing under the board). Picking a subject's
    /// name steps inside it.
    private var listSelection: Binding<SidebarItem?> {
        Binding<SidebarItem?>(get: {
            if let b = store.openBoard { return SidebarItem.board(b.path) }
            return selection.map { SidebarItem.screen($0) }
        }, set: { new in
            switch new {
            case .board(let p)?:
                if store.openBoard?.path != p { store.openBoard = .init(path: p, focus: nil) }
            case .screen(var s)?:
                if case .subject(let id) = s, inside != id { withAnimation(Kit.spring) { inside = id } }
                // a notebook's row steps inside it, also when its page is the one already showing
                if case .notebook(let p) = s { s = .notebook(step(into: p)) }
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

/// A place as a small icon (inside a subject, and the sidebar's foot).
struct SidebarIcon: Identifiable {
    var screen: Screen
    var title: String
    var icon: String
    var id: String

    init(screen: Screen, title: String, icon: String, id: String? = nil) {
        self.screen = screen
        self.title = title
        self.icon = icon
        self.id = id ?? "sidebar-" + title
    }
}

private extension Int {
    /// nil for 0, so a count of nothing shows nothing.
    var nonZero: Int? { self == 0 ? nil : self }
}

/// What a row of the iPad's sidebar stands for: a screen, or a board (its row is the selected one while it is open).
enum SidebarItem: Hashable {
    case screen(Screen)
    case board(String)
}
