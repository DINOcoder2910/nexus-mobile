import SwiftUI
import NexusCore

/// Where a question of the bank opens (a paper and its question).
struct BankTarget: Hashable, Identifiable {
    var paper: String
    var q: String
    var id: String { paper + "#" + q }
}

/// The question bank (a subject's Study › Question bank), as the laptop's `Bank.tsx` has it: the papers first, the ones you're working
/// on pinned on top, each with how much of it is written on and done; below them the questions, each with its unit, type, marks,
/// command term and difficulty, filtered. A question opens on its own page (BankQuestionView). Sorting a paper is the laptop's: a paper
/// it hasn't sorted shows "Sort it on the laptop".
struct BankView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    let workstreamId: String
    /// One paper only (its questions), or every paper.
    var paper: String?

    @State private var filter = QuestionBank.Filter()
    @State private var recent = false
    @State private var open: BankTarget?
    @State private var openPaper: String?

    private var lib: BankLibrary { BankLibrary.shared }

    var body: some View {
        let b = lib.bank(workstreamId)
        List {
            if let b {
                content(b)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(paper.flatMap { p in b?.papers.first { $0.path == p }?.title } ?? "Question bank")
        .navigationBarTitleDisplayMode(.inline)
        .studyRefresh(store)
        .task(id: StudyLibrary.shared.study(workstreamId)?.sheets.sheets.count ?? -1) {
            if let s = StudyLibrary.shared.study(workstreamId) { lib.refresh(s, root: store.folder) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                if let s = StudyLibrary.shared.study(workstreamId) { lib.refresh(s, root: store.folder) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Order", selection: $recent) {
                        Text("Paper order").tag(false)
                        Text("Last worked on").tag(true)
                    }
                } label: { Label("Order", systemImage: "arrow.up.arrow.down") }
                .accessibilityIdentifier("bank-order")
            }
        }
        .navigationDestination(item: $open) { t in BankQuestionView(workstreamId: workstreamId, paper: t.paper, q: t.q) }
        .navigationDestination(item: $openPaper) { p in BankView(workstreamId: workstreamId, paper: p) }
        .alert("Question bank", isPresented: Binding(get: { lib.problem != nil }, set: { if !$0 { lib.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(lib.problem ?? "") }
    }

    @ViewBuilder
    private func content(_ b: BankLibrary.Bank) -> some View {
        let papers = paper.map { p in b.papers.filter { $0.path == p } } ?? b.papers
        let total = b.papers.reduce(0) { $0 + $1.questions }, sortedN = b.papers.filter(\.sorted).count
        Section {
            Text(b.papers.isEmpty ? "No papers yet: put them in the sheets folder, or upload one."
                 : "\(Self.plural(total, "question")) from \(Self.plural(sortedN, "paper")) sorted, of \(b.papers.count). The laptop sorts a paper (its decision model, and Claude for what it is unsure of); your marks, pins and places are kept on every device.")
                .font(.nx(.callout)).foregroundStyle(.secondary)
                .accessibilityIdentifier("bank-lede")
            if b.questionsBroken || b.marksBroken {
                Label("\(b.questionsBroken ? "questions.yaml" : "question-marks.yaml") isn't in the form Nexus writes, so it is only read here.", systemImage: "exclamationmark.triangle")
                    .font(.nx(.callout)).foregroundStyle(Theme.late)
            }
        }
        if paper == nil {
            let pinned = b.papers.filter(\.pinned)
            if !pinned.isEmpty {
                Section {
                    ForEach(pinned) { p in PaperCard(workstreamId: workstreamId, paper: p, today: Days.today(), open: { open = $0 }) }
                } header: { SectionTitle(title: "Working on") }
                .accessibilityIdentifier("bank-working")
            }
        }
        Section {
            ForEach(papers) { p in paperRow(p) }
        } header: { SectionTitle(title: paper == nil ? "Papers" : "This paper", count: papers.count) }
        let rows = lib.rows(workstreamId, { var f = filter; f.paper = paper ?? ""; return f }(), recent: recent)
        Section {
            filters(b)
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            if rows.isEmpty {
                Text(b.papers.contains(where: \.sorted) ? "No question matches." : "Once the laptop has sorted a paper, its questions show here, each with its unit, type, marks and how much you have written.")
                    .font(.nx(.callout)).foregroundStyle(.secondary)
            } else {
                ForEach(rows) { r in
                    Button { open = BankTarget(paper: r.paper, q: r.q) } label: { QuestionRowView(r: r) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("bank-q-" + r.q)
                }
            }
        } header: { SectionTitle(title: "Questions", count: rows.count) }
    }

    private func paperRow(_ p: BankLibrary.Paper) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button { openBoard(p) } label: {
                    Text(p.title).font(.nx(.body, .medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("bank-paper-title")
                if p.isClass { Chip(text: "class", color: Theme.soon) }
                if p.pinned { Chip(text: "working on", color: Theme.accent) }
                Spacer(minLength: 4)
                Button { lib.pin(store, workstreamId, paper: p.path, on: !p.pinned) } label: {
                    Image(systemName: p.pinned ? "pin.fill" : "pin").foregroundStyle(p.pinned ? Theme.accent : .secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!lib.canWrite(store))
                .accessibilityLabel(p.pinned ? "No longer working on it" : "Working on it")
                .accessibilityIdentifier("bank-pin")
            }
            let facts = Self.factsLine(p)
            if !facts.isEmpty { Text(facts).font(.nx(.caption)).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                if p.sorted {
                    Text("\(p.written) of \(p.questions) written on · \(p.done) done").font(.nx(.caption)).foregroundStyle(Kit.muted)
                        .accessibilityIdentifier("bank-paper-written")
                    if let l = p.lastWritten { Text("last written \(Self.when(l))").font(.nx(.caption)).foregroundStyle(Kit.faint) }
                } else {
                    Text(p.isPdf ? "Not sorted yet: sort it on the laptop (Study › Question bank)" : "No questions yet").font(.nx(.caption)).foregroundStyle(Kit.faint)
                }
            }
            if p.sorted {
                FlowRow(spacing: 6) {
                    if paper == nil {
                        Button { openPaper = p.path } label: { Chip(text: Self.plural(p.questions, "question"), icon: "list.bullet", color: Theme.accent) }
                            .buttonStyle(.borderless)
                            .fixedSize().accessibilityIdentifier("bank-paper-questions")
                    }
                    if let q = p.bookmark {
                        Button { open = BankTarget(paper: p.path, q: q) } label: { Chip(text: "Go on at \(QuestionBank.qName(q))", icon: "bookmark.fill", color: Theme.accent) }
                            .buttonStyle(.borderless)
                            .fixedSize().accessibilityIdentifier("bank-paper-continue")
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bank-paper")
    }

    /// The paper's board, or Write on it for a paper with none yet.
    private func openBoard(_ p: BankLibrary.Paper) {
        if let b = p.boards.first { store.openBoard = .init(path: b, focus: nil) } else if p.isPdf { store.writeOn(pdf: p.path) }
    }

    // MARK: the filters

    private func filters(_ b: BankLibrary.Bank) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a question", text: $filter.find)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("bank-find")
                if filter.any { Button("Clear") { filter = .init() }.font(.nx(.callout)).buttonStyle(.borderless) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
            if size == .regular {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Unit", $filter.unit, Self.unitOptions(b))
                        chip("Type", $filter.type, Self.typeOptions)
                        chip("Command", $filter.command, Self.commandOptions)
                        chip("Marked", $filter.mark, Self.markOptions)
                        chip("Written", $filter.written, Self.writtenOptions)
                        chip("Difficulty", $filter.difficulty, Self.difficultyOptions)
                        chip("From", $filter.source, Self.sourceOptions)
                        chip("Level", $filter.level, Self.levelOptions)
                    }
                }
            } else {
                filterMenu(b)
            }
        }
    }

    /// The iPhone's filters: one Filter menu with each filter as a submenu (as the practice sheets have it there).
    private func filterMenu(_ b: BankLibrary.Bank) -> some View {
        let n = [filter.unit, filter.type, filter.command, filter.mark, filter.written, filter.difficulty, filter.source, filter.level].filter { !$0.isEmpty }.count
        return Menu {
            Menu("Unit") { Picker("Unit", selection: $filter.unit) { ForEach(Self.unitOptions(b), id: \.id) { Text($0.label).tag($0.id) } } }
            Menu("Type") { Picker("Type", selection: $filter.type) { ForEach(Self.typeOptions, id: \.id) { Text($0.label).tag($0.id) } } }
            Menu("Command") { Picker("Command", selection: $filter.command) { ForEach(Self.commandOptions, id: \.id) { Text($0.label).tag($0.id) } } }
            Menu("Marked") { Picker("Marked", selection: $filter.mark) { ForEach(Self.markOptions, id: \.id) { Text($0.label).tag($0.id) } } }
            Menu("Written") { Picker("Written", selection: $filter.written) { ForEach(Self.writtenOptions, id: \.id) { Text($0.label).tag($0.id) } } }
            Menu("Difficulty") { Picker("Difficulty", selection: $filter.difficulty) { ForEach(Self.difficultyOptions, id: \.id) { Text($0.label).tag($0.id) } } }
            Menu("From") { Picker("From", selection: $filter.source) { ForEach(Self.sourceOptions, id: \.id) { Text($0.label).tag($0.id) } } }
            Menu("Level") { Picker("Level", selection: $filter.level) { ForEach(Self.levelOptions, id: \.id) { Text($0.label).tag($0.id) } } }
        } label: {
            Label(n == 0 ? "Filter" : "Filter (\(n))", systemImage: n == 0 ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.nx(.callout, n == 0 ? .regular : .semibold))
                .foregroundStyle(Theme.accent)
        }
        .accessibilityIdentifier("bank-filter")
    }

    typealias Options = [(id: String, label: String)]
    static func unitOptions(_ b: BankLibrary.Bank) -> Options {
        var out: Options = [(id: "", label: "Any unit")]
        for u in b.units { out.append((id: u.code, label: u.code + " " + u.title)) }
        return out
    }
    static let typeOptions: Options = [(id: "", label: "Any type")] + QuestionBank.types.map { t -> (id: String, label: String) in (id: t, label: QuestionBank.typeWord[t] ?? t) }
    static let commandOptions: Options = [(id: "", label: "Any command")] + QuestionFinder.commands.map { c -> (id: String, label: String) in (id: c, label: c.prefix(1).uppercased() + String(c.dropFirst())) }
    static let markOptions: Options = [(id: "", label: "Marked or not"), (id: "none", label: "Not marked yet"), (id: "done", label: "Done"), (id: "hard", label: "Hard"), (id: "review", label: "Review later")]
    static let writtenOptions: Options = [(id: "", label: "Written or not"), (id: "none", label: "Nothing written"), (id: "started", label: "Started"), (id: "plenty", label: "Written on")]
    static let difficultyOptions: Options = [(id: "", label: "Any difficulty"), (id: "easy", label: "Easy"), (id: "medium", label: "Medium"), (id: "hard", label: "Hard")]
    static let sourceOptions: Options = [(id: "", label: "Papers and class"), (id: "papers", label: "Papers"), (id: "class", label: "Class boards")]
    static let levelOptions: Options = [(id: "", label: "HL or SL"), (id: "SL", label: "SL"), (id: "HL", label: "HL")]

    private func chip(_ title: String, _ value: Binding<String>, _ options: Options) -> some View {
        let on = !value.wrappedValue.isEmpty
        let text = on ? (options.first { $0.id == value.wrappedValue }?.label ?? value.wrappedValue) : (options.first?.label ?? title)
        return Menu {
            Picker(title, selection: value) { ForEach(options, id: \.id) { Text($0.label).tag($0.id) } }
        } label: {
            HStack(spacing: 4) {
                Text(text).lineLimit(1)
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .font(.nx(.callout, on ? .semibold : .regular))
            .foregroundStyle(on ? Theme.accent : .primary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Theme.accent.opacity(0.14) : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
        .accessibilityIdentifier("bank-filter-" + title.lowercased())
    }

    static func plural(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

    /// "05 Reactivity 1 — Energetics · May 2023 · Paper 2 · HL · class 2026-11-20"
    static func factsLine(_ p: BankLibrary.Paper) -> String {
        var parts: [String] = []
        if let u = p.unit { parts.append(u) }
        parts.append(QuestionBank.paperFacts(p.facts))
        if p.isClass, let d = p.facts["classDate"]?.string { parts.append("class " + BankView.when(d)) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "today", "yesterday", "Mon 17 Nov"
    static func when(_ day: String) -> String {
        let today = Days.today()
        if day == today { return "today" }
        if Days.isIso(day), Days.between(day, today) == 1 { return "yesterday" }
        return Days.label(day)
    }
}

/// One question as the bank lists it: its number, its paper, what it was sorted as, how much is written, its mark.
struct QuestionRowView: View {
    let r: QuestionBank.Row

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(QuestionBank.qName(r.q)).font(.nx(.callout, .semibold)).monospacedDigit()
                .frame(minWidth: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(r.title).font(.nx(.callout)).lineLimit(1)
                    if r.bookmark { Image(systemName: "bookmark.fill").imageScale(.small).foregroundStyle(Theme.accent) }
                }
                Text(r.meta).font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            if r.written != "none" {
                Text(r.written == "some" ? "started" : "written").font(.nx(.caption)).foregroundStyle(Kit.muted)
            }
            if let m = r.mark { Chip(text: QuestionBank.markWord[m] ?? m, color: BankMarks.color(m), strong: true) }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

enum BankMarks {
    static func color(_ m: String) -> Color { m == "done" ? Theme.accent : m == "hard" ? Theme.late : Theme.soon }
}

/// A paper you're working on: how much is written, and Go on at its bookmark (or open it).
struct PaperCard: View {
    @Environment(NexusStore.self) private var store
    let workstreamId: String
    let paper: BankLibrary.Paper
    let today: String
    let open: (BankTarget) -> Void

    var body: some View {
        let p = paper
        VStack(alignment: .leading, spacing: 6) {
            Text(p.title).font(.nx(.body, .medium))
            let facts = [QuestionBank.paperFacts(p.facts), p.lastWritten.map { "last written \(BankView.when($0))" } ?? ""].filter { !$0.isEmpty }
            if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.nx(.caption)).foregroundStyle(.secondary) }
            ProgressView(value: p.questions > 0 ? Double(p.written) / Double(p.questions) : 0).tint(Theme.accent)
            HStack {
                Text("\(p.written) of \(p.questions) written on").font(.nx(.caption)).foregroundStyle(Kit.muted)
                Spacer()
                if let q = p.bookmark {
                    Button { open(BankTarget(paper: p.path, q: q)) } label: { Chip(text: "Go on at \(QuestionBank.qName(q))", icon: "bookmark.fill", color: Theme.accent) }
                        .buttonStyle(.borderless)
                } else if let b = p.boards.first {
                    Button { store.openBoard = .init(path: b, focus: nil) } label: { Chip(text: "Open", icon: "pencil.and.scribble", color: Theme.accent) }
                        .buttonStyle(.borderless)
                } else if let q = BankLibrary.shared.bank(workstreamId)?.questions[p.path]?.questions.keys.first {
                    Button { open(BankTarget(paper: p.path, q: q)) } label: { Chip(text: "Open", color: Theme.accent) }
                        .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bank-working-card")
    }
}

/// Study's home: the bank in a few lines (Open, the papers you're working on, what you marked Review later).
struct BankGlance: View {
    @Environment(NexusStore.self) private var store
    let workstreamId: String
    @Binding var open: BankTarget?

    var body: some View {
        let lib = BankLibrary.shared
        if let b = lib.bank(workstreamId), !b.papers.isEmpty {
            let review = lib.rows(workstreamId, { var f = QuestionBank.Filter(); f.mark = "review"; return f }())
            Section {
                NavigationLink {
                    BankView(workstreamId: workstreamId)
                } label: {
                    Label {
                        HStack {
                            Text("Question bank")
                            Spacer()
                            Text(BankView.plural(b.papers.reduce(0) { $0 + $1.questions }, "question")).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "list.number") }
                }
                .accessibilityIdentifier("study-bank")
                ForEach(b.papers.filter(\.pinned)) { p in PaperCard(workstreamId: workstreamId, paper: p, today: Days.today(), open: { open = $0 }) }
                if !review.isEmpty {
                    ForEach(review.prefix(5)) { r in
                        Button { open = BankTarget(paper: r.paper, q: r.q) } label: { QuestionRowView(r: r) }
                            .buttonStyle(.plain)
                    }
                }
            } header: {
                SectionTitle(title: "Question bank")
            } footer: {
                if review.isEmpty && !b.papers.contains(where: \.pinned) {
                    Text("Pin a paper you're working on and it stays here; questions marked Review later show here too.")
                }
            }
        }
    }
}
