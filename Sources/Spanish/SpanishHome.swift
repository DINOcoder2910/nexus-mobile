import SwiftUI
import NexusCore

/// The Spanish screen (the laptop's Study › Spanish for a workstream whose study.yaml says `language: spanish`). Everything the laptop
/// has is here on both devices; each has its own layout:
/// - iPad: the checker at the top left with History opening under it, the tutor below it; Writing and Skills (the weakest first, all of
///   them a tap away) on the right; SpanishDict opens as a panel on the right; Add a card and the tutor's files sit in the bar.
/// - iPhone: the checker at the top, the tutor's chats under it, then History, Writing and Skills as pages; SpanishDict is a sheet; the
///   less used things (Add a card, SpanishDict, Teach me the imperative, the model, the tutor's files) are in the … menu.
struct SpanishHome: View {
    let workstreamId: String
    var body: some View {
        SpanishHost(workstreamId: workstreamId) { SpanishHomeContent(workstreamId: workstreamId) }
    }
}

enum SpanishRoute: Hashable { case history, chat, writing, skills }

struct SpanishHomeContent: View {
    let workstreamId: String
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.spanish) private var actions
    @State private var route: SpanishRoute?
    @State private var historyOpen = false
    @State private var allChats = false
    @State private var addingPrompt = false
    @State private var question = ""
    @State private var draft = ""
    @FocusState private var typing: Bool
    var lib: SpanishLibrary { .shared }
    var wide: Bool { size == .regular }

    var body: some View {
        Group {
            if let w = lib.workstream(workstreamId) {
                if wide { ipad(w) } else { iphone(w) }
            } else {
                notSetUp
            }
        }
        .navigationTitle(lib.workstream(workstreamId).map { "Spanish · \($0.name)" } ?? "Spanish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if lib.workstream(workstreamId) != nil { toolbar } }
        .spanishKeyboardDone()
        .navigationDestination(item: $route) { r in
            switch r {
            case .chat: SpanishChatView(workstreamId: workstreamId)
            case .writing: SpanishHost(workstreamId: workstreamId) { SpanishWritingList(workstreamId: workstreamId) }
            case .history: SpanishHistoryList(workstreamId: workstreamId, onMove: moveToChat)
            case .skills: SpanishHost(workstreamId: workstreamId) { SpanishSkillsPage(workstreamId: workstreamId, onPractise: { openChat(first: $0) }) }
            }
        }
        .sheet(isPresented: $addingPrompt) { SpanishPromptSheet(workstreamId: workstreamId) }
        .alert("Spanish", isPresented: Binding(get: { lib.problem != nil }, set: { if !$0 { lib.problem = nil } })) {
            Button("OK") { lib.problem = nil }
        } message: { Text(lib.problem ?? "") }
        .task(id: store.snapshot.loadedAt) { lib.refreshIfChanged(store) }
    }

    // MARK: the two layouts

    private func ipad(_ w: Workstream) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    card { checker(w) }
                    card { tutor(w) }
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 20) {
                    card { writing }
                    card { skills }
                }
                .frame(width: 360)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func iphone(_ w: Workstream) -> some View {
        List {
            Section { checker(w) } header: { Text("Check a sentence").textCase(nil) }
            Section { tutorRows } header: { Text("Tutor").textCase(nil) } footer: { Text("Explains in English, checks what you write, remembers what you have done.") }
            Section {
                let d = lib.data(workstreamId)
                go(.history, "History", "clock", d.entries.isEmpty ? "" : "\(d.entries.count)")
                go(.writing, "Writing", "pencil.and.list.clipboard", d.prompts.isEmpty ? "" : "\(d.prompts.count) \(d.prompts.count == 1 ? "prompt" : "prompts")")
                let sh = SpanishCheck.solidShare(d.stats, d.status)
                go(.skills, "Skills", "chart.bar", "\(sh.solid) of \(sh.of) solid")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { c() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func go(_ r: SpanishRoute, _ title: String, _ icon: String, _ note: String) -> some View {
        Button { route = r } label: {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(Color.primary)
                Spacer()
                Text(note).foregroundStyle(.secondary).font(.callout)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .accessibilityIdentifier("spanish-go-\(title)")
    }

    // MARK: the checker

    @ViewBuilder
    private func checker(_ w: Workstream) -> some View {
        let d = lib.data(workstreamId)
        let st = SpanishCheck.streak(d.entries)
        if wide {
            HStack(alignment: .firstTextBaseline) {
                Text("Check a sentence").font(.title3.weight(.semibold))
                Text(d.entries.isEmpty ? "" : st > 0 ? "\(st) clean \(st == 1 ? "sentence" : "sentences") in a row" : "\(d.entries.count) \(d.entries.count == 1 ? "sentence" : "sentences") checked")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { withAnimation { historyOpen.toggle() } } label: { Label("History", systemImage: "clock") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("spanish-history-toggle")
            }
        } else if !d.entries.isEmpty {
            Text(st > 0 ? "\(st) clean \(st == 1 ? "sentence" : "sentences") in a row" : "\(d.entries.count) \(d.entries.count == 1 ? "sentence" : "sentences") checked")
                .font(.caption).foregroundStyle(.secondary)
        }
        TextField("The question it answers (optional)", text: $question)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("spanish-question")
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Write in Spanish", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .textFieldStyle(.roundedBorder)
                .focused($typing)
                .onSubmit(check)
                .accessibilityIdentifier("spanish-sentence")
            Button("Check", action: check)
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("spanish-check")
            ClaudeModeChip(small: true).padding(.bottom, 6)
        }
        if let run = lib.current[workstreamId] {
            SpanishResultView(run: run).padding(.top, 4)
        } else {
            Text("Mistakes are underlined in red, accents in amber, what you did well in green. Tap any word for its meaning.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if wide && historyOpen {
            Divider()
            SpanishHistoryList(workstreamId: workstreamId, onMove: moveToChat, inline: true)
        }
    }

    private func check() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { typing = true; return }
        let run = SpanishCheckRun(text: t, question: question.trimmingCharacters(in: .whitespacesAndNewlines))
        lib.current[workstreamId] = run
        draft = ""
        SpanishKeyboard.hideOnPhone()
        Task { await run.run(store, wsId: workstreamId) }
    }

    // MARK: the tutor

    @ViewBuilder
    private func tutor(_ w: Workstream) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tutor").font(.title3.weight(.semibold))
            Text("explains in English, checks what you write, remembers what you have done").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            SpanishModelMenu().controlSize(.small)
        }
        tutorRows
        HStack(spacing: 6) {
            Text("What the tutor knows:").font(.caption).foregroundStyle(.secondary)
            fileButton("your profile", Spanish.P.profile)
            fileButton("the course", Spanish.P.course)
            fileButton("the skills", Spanish.P.skills)
        }
    }

    @ViewBuilder
    private var tutorRows: some View {
        let d = lib.data(workstreamId)
        let open = lib.chats[workstreamId].flatMap { $0.closed ? nil : $0 }
        let buttons = HStack(spacing: 10) {
            if let o = open {
                Button { route = .chat } label: { Label(o.title == "Tutor chat" ? "Back to the open chat" : "Back to: \(o.title)", systemImage: "arrow.right") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("spanish-continue")
            }
            if open == nil {
                Button { openChat() } label: { Label("New chat", systemImage: "plus") }.buttonStyle(.borderedProminent).accessibilityIdentifier("spanish-new-chat")
            } else {
                Button { openChat() } label: { Label("New chat", systemImage: "plus") }.buttonStyle(.bordered).accessibilityIdentifier("spanish-new-chat")
            }
            if wide {
                Button("Teach me the imperative") { openChat(first: Self.imperative) }.buttonStyle(.borderless)
            }
        }
        if wide { buttons } else { buttons.buttonStyle(.borderless) }
        if d.chats.isEmpty {
            Text("No chats yet. Each chat is kept as its own file, with a summary the tutor reads next time.").font(.footnote).foregroundStyle(.secondary)
        } else {
            let lim = allChats ? d.chats.count : (wide ? 5 : 3)
            ForEach(d.chats.prefix(lim)) { c in
                Button { openChat(path: c.path) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(c.title).font(.callout.weight(.medium)).foregroundStyle(Color.primary)
                            Spacer()
                            Text(String(c.started.prefix(10))).font(.caption).foregroundStyle(.secondary)
                        }
                        if !c.summary.isEmpty { Text(c.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, wide ? 4 : 0)
            }
            if d.chats.count > lim {
                Button("Show all \(d.chats.count)") { allChats = true }.font(.callout).buttonStyle(.borderless)
            }
        }
    }

    static let imperative = "Teach me the imperative from scratch: the positive commands first, then the negative ones."

    private func fileButton(_ title: String, _ rel: String) -> some View {
        Button(title) { actions.showFile((lib.workstream(workstreamId)?.folder ?? "") + "/" + rel, title.capitalized) }
            .font(.caption).buttonStyle(.borderless)
    }

    // MARK: Writing and Skills (the iPad's right column)

    @ViewBuilder
    private var writing: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Writing").font(.title3.weight(.semibold))
            Spacer()
            Button { addingPrompt = true } label: { Label("Add a prompt", systemImage: "plus") }.controlSize(.small).buttonStyle(.bordered)
        }
        Text("IB Paper 1: 70–150 words · A Language /6 · B Message /6 · C Conceptual understanding /3").font(.caption).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 10) { SpanishPromptRows(workstreamId: workstreamId) }
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private var skills: some View {
        let d = lib.data(workstreamId)
        let sh = SpanishCheck.solidShare(d.stats, d.status)
        HStack(alignment: .firstTextBaseline) {
            Text("Skills").font(.title3.weight(.semibold))
            Spacer()
            Button("All skills") { route = .skills }.controlSize(.small).accessibilityIdentifier("spanish-all-skills")
        }
        Text("\(sh.solid) of \(sh.of) taught skills solid · \(d.entries.count) \(d.entries.count == 1 ? "sentence" : "sentences") checked").font(.caption).foregroundStyle(.secondary)
        let weak = SpanishCheck.weakest(d.stats, 6)
        if weak.isEmpty {
            Text("Check a few sentences and the skills that need practice show here.").font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(weak, id: \.id) { s in
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Spanish.skillName(s.id)).font(.callout)
                    Text("\(s.stat.accuracy)% · \(SpanishCheck.statWords[s.stat.status] ?? s.stat.status)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(d.status[s.id] == "reteach" ? "Teach me" : "Practise") {
                    let name = Spanish.skillName(s.id).lowercased()
                    openChat(first: d.status[s.id] == "reteach" ? "Teach me \(name) (\(s.id)) from scratch." : "Let's practise \(name) (\(s.id)).")
                }
                .controlSize(.small).buttonStyle(.bordered)
                .disabled(d.status[s.id] == "not-yet")
            }
        }
    }

    // MARK: the bar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if wide {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { actions.addCard(SpanishCards.Draft(deck: lib.defaultDeck(workstreamId))) } label: { Label("Add a card", systemImage: "rectangle.stack.badge.plus") }
                    .accessibilityIdentifier("spanish-add-card")
                Button { actions.dict("") } label: { Label("SpanishDict", systemImage: "book") }
                    .accessibilityIdentifier("spanish-dict")
            }
        } else {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { actions.addCard(SpanishCards.Draft(deck: lib.defaultDeck(workstreamId))) } label: { Label("Add a card", systemImage: "rectangle.stack.badge.plus") }
                    Button { actions.dict("") } label: { Label("SpanishDict", systemImage: "book") }
                    Button { openChat(first: Self.imperative) } label: { Label("Teach me the imperative", systemImage: "graduationcap") }
                    Button { addingPrompt = true } label: { Label("Add a writing prompt", systemImage: "plus") }
                    Picker(selection: Binding(get: { SpanishModel.current }, set: { SpanishModel.current = $0 })) {
                        ForEach(SpanishModel.all, id: \.id) { m in Text(m.label).tag(m.id) }
                    } label: { Label("Tutor model", systemImage: "cpu") }
                    .pickerStyle(.menu)
                    Section("What the tutor knows") {
                        Button("Your profile") { actions.showFile(folder + "/" + Spanish.P.profile, "Your profile") }
                        Button("The course") { actions.showFile(folder + "/" + Spanish.P.course, "The course") }
                        Button("The skills") { actions.showFile(folder + "/" + Spanish.P.skills, "The skills") }
                    }
                } label: { Label("More", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("spanish-more")
            }
        }
    }

    private var folder: String { lib.workstream(workstreamId)?.folder ?? "" }

    // MARK: opening a chat

    private func openChat(path: String? = nil, first: String = "") {
        if let path {
            guard let f = lib.readChat(store, path) else { store.toast = .init(message: "That chat file is gone."); return }
            if lib.chats[workstreamId]?.path != path || lib.chats[workstreamId]?.closed == true { lib.chats[workstreamId] = SpanishChat(wsId: workstreamId, file: f) }
        } else {
            if let old = lib.chats[workstreamId], !old.closed, old.hasTutor { store.toast = .init(message: "The chat you had open is saved; End chat there to update your memory.") }
            lib.chats[workstreamId] = SpanishChat(wsId: workstreamId, model: SpanishModel.current)
        }
        route = .chat
        if !first.isEmpty { lib.chats[workstreamId]?.send(store, first) }
    }

    private func moveToChat(_ entries: [SpanishCheck.Entry]) {
        guard !entries.isEmpty else { return }
        historyOpen = false
        openChat(first: SpanishCheck.moveToChatText(entries))
    }

    // MARK: not a Spanish workstream (yet)

    @ViewBuilder
    private var notSetUp: some View {
        if let w = store.workstream(workstreamId) {
            VStack(spacing: 16) {
                EmptyNote(title: "\(w.name) has no Spanish study yet", detail: "Set up writes the checker's log, the tutor's memory, the course and the Spanish decks into its study folder.", icon: "character.bubble")
                Button("Set up Spanish study") {
                    let n = lib.setUp(store, w)
                    store.toast = .init(message: n > 0 ? "Spanish study is set up in \(w.name)." : "\(w.name) already has Spanish study.")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!lib.canWrite(store))
            }
        } else {
            EmptyNote(title: "This workstream is gone", icon: "questionmark.folder")
        }
    }
}

/// All the skills, on their own page (both devices).
struct SpanishSkillsPage: View {
    let workstreamId: String
    var onPractise: (String) -> Void
    var body: some View {
        let d = SpanishLibrary.shared.data(workstreamId)
        let sh = SpanishCheck.solidShare(d.stats, d.status)
        List {
            Section {
                Text("\(sh.solid) of \(sh.of) taught skills solid · \(d.entries.count) \(d.entries.count == 1 ? "sentence" : "sentences") checked. Tap a skill's status to change what has been taught.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            SpanishSkillsList(workstreamId: workstreamId, onPractise: onPractise)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Skills")
    }
}

/// The workstream page's Spanish row (or nothing, for a workstream without Spanish study).
struct SpanishWorkstreamSection: View {
    let workstreamId: String?
    var body: some View {
        if let id = workstreamId, SpanishLibrary.shared.workstream(id) != nil {
            Section {
                NavigationLink { SpanishHome(workstreamId: id) } label: {
                    Label("Spanish: check, tutor, writing, skills", systemImage: "character.bubble")
                }
            }
        }
    }
}

/// The workstream page's … menu: Set up Spanish study (as the laptop's).
struct SpanishSetupMenu: ViewModifier {
    let workstreamId: String?
    @Environment(NexusStore.self) private var store
    func body(content: Content) -> some View {
        content.toolbar {
            if let id = workstreamId, SpanishLibrary.shared.workstream(id) == nil, let w = store.workstream(id), store.snapshot.readOnlyReason == nil {
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        let n = SpanishLibrary.shared.setUp(store, w)
                        store.toast = .init(message: n > 0 ? "Spanish study is set up in \(w.name)." : "\(w.name) already has Spanish study.")
                    } label: { Label("Set up Spanish study", systemImage: "character.bubble") }
                }
            }
        }
    }
}

extension View {
    func spanishSetupMenu(_ workstreamId: String?) -> some View { modifier(SpanishSetupMenu(workstreamId: workstreamId)) }
}

/// The sidebar's Spanish row (one per Spanish workstream; the iPhone's More list is the same sidebar).
struct SpanishSidebarRows<R: View>: View {
    let row: (Screen, String, String) -> R
    var body: some View {
        let ws = SpanishLibrary.shared.workstreams
        ForEach(ws, id: \.id) { w in
            row(.spanish(w.id), ws.count == 1 ? "Spanish" : "Spanish · \(w.name)", "character.bubble")
        }
    }
}
