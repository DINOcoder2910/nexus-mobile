import SwiftUI
import NexusCore

// Spanish › Text types, as the laptop's (nexus desktop/src/screens/study/SpanishTypes.tsx): a guide for every IB ab initio text type,
// one markdown file each in study/spanish/text-types/ (the laptop writes its own the first time; then they are the user's files, read
// here). The list by group, one guide (structure, rules, an exemplar with its word count, sentence stems and vocabulary, grammar not
// taught yet flagged from skills.yaml, Practise with the tutor), and the guide beside a piece in Writing (pick the type, tick off the
// structure, tap a stem to put it in).

enum SpanishGuideText {
    /// a guide's line with its **bold** and *italics*
    static func md(_ s: String) -> Text {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
    }
}

/// The guides, by group. Reached from Writing's prompts.
struct SpanishTextTypesList: View {
    let workstreamId: String
    var lib: SpanishLibrary { .shared }

    var body: some View {
        let d = lib.data(workstreamId)
        List {
            Section {
                Text("How each text type is built, its rules, words and sentence stems, and an exemplar that keeps to what you have been taught. Writing's marking and the tutor use the same guides.")
                    .font(.nx(.callout)).foregroundStyle(.secondary)
            }
            ForEach(SpanishTextTypes.groups, id: \.id) { grp in
                let gs = d.guides.filter { $0.group == grp.id }
                if !gs.isEmpty {
                    Section(grp.title) {
                        ForEach(gs) { g in
                            NavigationLink {
                                SpanishGuideView(workstreamId: workstreamId, slug: g.slug)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(g.title).font(.nx(.body, .semibold))
                                    Text(g.english + (g.register.isEmpty ? "" : " · " + g.register)).font(.nx(.caption)).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
                            .accessibilityIdentifier("spanish-guide-\(g.slug)")
                        }
                    }
                }
            }
            if d.guides.isEmpty {
                Section {
                    Text("There are no guides in \(SpanishTextTypes.dir) yet. The laptop writes them the first time you open Spanish › Text types there; they come here with the next sync.")
                        .font(.nx(.callout)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("spanish-guides-empty")
                }
            } else {
                Section {
                    Text("They are files in \(SpanishTextTypes.dir): change one, or add your own as a markdown file there.").font(.nx(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Text types")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One guide: the structure, the rules, the exemplar with its IB word count and why it works, the sentence stems and the vocabulary.
struct SpanishGuideView: View {
    let workstreamId: String
    let slug: String
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    @State private var practising = false
    var lib: SpanishLibrary { .shared }

    var body: some View {
        SpanishHost(workstreamId: workstreamId) {
            if let g = lib.data(workstreamId).guides.first(where: { $0.slug == slug }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        head(g)
                        if size == .regular {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 18) { structure(g); rules(g) }.frame(maxWidth: .infinity, alignment: .leading)
                                exemplar(g).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            HStack(alignment: .top, spacing: 20) {
                                SpanishGuideItems(title: "Sentence stems", groups: g.stems, status: lib.data(workstreamId).status).frame(maxWidth: .infinity, alignment: .leading)
                                SpanishGuideItems(title: "Vocabulary", groups: g.vocab, status: lib.data(workstreamId).status).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            structure(g)
                            rules(g)
                            exemplar(g)
                            SpanishGuideItems(title: "Sentence stems", groups: g.stems, status: lib.data(workstreamId).status)
                            SpanishGuideItems(title: "Vocabulary", groups: g.vocab, status: lib.data(workstreamId).status)
                        }
                        ForEach(g.more, id: \.title) { m in
                            card { Text(m.title).font(.nx(.headline)); SpanishGuideText.md(m.text).font(.nx(.callout)) }
                        }
                    }
                    .padding(size == .regular ? 24 : 16)
                    .frame(maxWidth: 1100, alignment: .leading)
                }
                .navigationTitle(g.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { practise(g) } label: { Label("Practise with the tutor", systemImage: "sparkles") }
                            .accessibilityIdentifier("spanish-guide-practise")
                    }
                }
                .sheet(isPresented: $practising) {
                    NavigationStack {
                        SpanishChatView(workstreamId: workstreamId)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") { practising = false }.accessibilityIdentifier("spanish-guide-chat-close")
                                }
                            }
                    }
                }
            } else {
                EmptyNote(title: "This guide is no longer in \(SpanishTextTypes.dir).", icon: "questionmark.folder")
            }
        }
    }

    /// A new chat that carries the guide, its first message the laptop's "I want to practise writing …"
    private func practise(_ g: SpanishTextTypes.Guide) {
        if let old = lib.chats[workstreamId], !old.closed, old.hasTutor { store.toast = .init(message: "The chat you had open is saved; End chat there to update your memory.") }
        let c = SpanishChat(wsId: workstreamId, model: SpanishModel.current)
        c.guide = SpanishTextTypes.tutorSection(g)
        lib.chats[workstreamId] = c
        c.send(store, SpanishTextTypes.practise(g))
        practising = true
    }

    private func head(_ g: SpanishTextTypes.Guide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(g.title).font(.nx(.title2, .bold))
            HStack(spacing: 8) {
                Text(g.english).foregroundStyle(.secondary)
                if !g.register.isEmpty {
                    Text(g.register).font(.nx(.caption, .medium)).foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                        .accessibilityIdentifier("spanish-guide-register")
                }
            }
            .font(.nx(.callout))
        }
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { c() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func structure(_ g: SpanishTextTypes.Guide) -> some View {
        if !g.structure.isEmpty {
            card {
                Text("Structure").font(.nx(.headline))
                ForEach(Array(g.structure.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)").font(.nx(.caption, .semibold)).foregroundStyle(Theme.accent).frame(width: 18)
                        SpanishGuideText.md(s).font(.nx(.callout))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("spanish-guide-structure")
        }
    }

    @ViewBuilder
    private func rules(_ g: SpanishTextTypes.Guide) -> some View {
        if !g.rules.isEmpty {
            card {
                Text("Rules").font(.nx(.headline))
                ForEach(Array(g.rules.enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark").font(.nx(.caption)).foregroundStyle(Theme.accent)
                        SpanishGuideText.md(s).font(.nx(.callout))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func exemplar(_ g: SpanishTextTypes.Guide) -> some View {
        if !g.exemplar.isEmpty {
            let c = SpanishGrade.wordCount(g.exemplar)
            let skipped = c.skipped.map(\.why).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            card {
                Text("Exemplar").font(.nx(.headline))
                if !g.task.isEmpty {
                    Text(g.task).font(.nx(.callout)).foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }
                }
                Text(g.exemplar).font(.nx(.body))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("spanish-guide-exemplar")
                (Text("\(c.counted)").bold() + Text(" words counted the IB way" + (skipped.isEmpty ? "" : " (not counting the \(skipped.joined(separator: ", ")))")))
                    .font(.nx(.caption)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("spanish-guide-count")
                if !g.notes.isEmpty {
                    Text("Why it works").font(.nx(.caption, .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                    ForEach(Array(g.notes.enumerated()), id: \.offset) { _, n in
                        HStack(alignment: .firstTextBaseline, spacing: 6) { Text("•"); SpanishGuideText.md(n) }.font(.nx(.callout))
                    }
                }
            }
        }
    }
}

/// Sentence stems or vocabulary, by group; a line tagged with a skill not taught yet is marked (learn it as a set phrase). With `put`,
/// tapping a line puts it into the piece.
struct SpanishGuideItems: View {
    let title: String
    let groups: [SpanishTextTypes.Group]
    let status: [String: String]
    var put: ((String) -> Void)?

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.nx(.headline))
                ForEach(Array(groups.enumerated()), id: \.offset) { gi, grp in
                    VStack(alignment: .leading, spacing: 4) {
                        if !grp.title.isEmpty { Text(grp.title).font(.nx(.caption, .semibold)).foregroundStyle(.secondary).textCase(.uppercase) }
                        ForEach(Array(grp.items.enumerated()), id: \.offset) { ii, it in
                            row(it).accessibilityIdentifier("spanish-\(title == "Vocabulary" ? "word" : "stem")-\(gi)-\(ii)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ it: SpanishTextTypes.Item) -> some View {
        let st = it.skill.isEmpty ? "" : (status[it.skill] ?? "taught")
        let later = !st.isEmpty && st != "taught"
        let line = VStack(alignment: .leading, spacing: 2) {
            Text(it.es).font(.nx(.callout, .medium)).foregroundStyle(later ? Theme.soon : Color.primary)
            if !it.en.isEmpty { Text(it.en).font(.nx(.caption)).foregroundStyle(.secondary) }
            if !it.skill.isEmpty {
                Text(later ? "\(Spanish.skillName(it.skill)): not taught yet" : Spanish.skillName(it.skill))
                    .font(.nx(.caption2, .medium)).foregroundStyle(later ? Theme.soon : Color.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((later ? Theme.soon : Color.secondary).opacity(0.12), in: Capsule())
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        if let put {
            Button { put(it.es) } label: { line }.buttonStyle(.plain)
                .accessibilityHint("Puts it into your text")
        } else {
            line
        }
    }
}

/// Beside a piece in Writing (the iPad's side column, a sheet on the iPhone): the text type (the ones the prompt offers first), its
/// register, the structure as a checklist, the rules, the stems (tap one to put it in) and the vocabulary.
struct SpanishGuidePanel: View {
    let workstreamId: String
    let prompt: SpanishGrade.Prompt
    var put: (String) -> Void
    @State private var done: Set<Int> = []
    var lib: SpanishLibrary { .shared }

    var body: some View {
        let d = lib.data(workstreamId)
        let offered = SpanishTextTypes.guidesFor(prompt.types, d.guides)
        let picked = lib.guide(workstreamId, prompt: prompt)
        let key = SpanishGradeRun.key(workstreamId, prompt.id)
        VStack(alignment: .leading, spacing: 14) {
            if d.guides.isEmpty {
                Text("No text type guides yet: the laptop writes them to \(SpanishTextTypes.dir) the first time you open Spanish › Text types there.")
                    .font(.nx(.callout)).foregroundStyle(.secondary)
            } else {
                Picker("Text type", selection: Binding(get: { picked?.slug ?? "" }, set: { lib.guidePicks[key] = $0; done = [] })) {
                    if picked == nil { Text("Pick one").tag("") }
                    ForEach(offered) { g in Text(g.title).tag(g.slug) }
                    ForEach(d.guides.filter { g in !offered.contains { $0.slug == g.slug } }) { g in Text(g.title).tag(g.slug) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("spanish-guide-pick")
                if let g = picked {
                    if !g.register.isEmpty { Text(g.register).font(.nx(.caption, .medium)).foregroundStyle(Theme.accent) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Structure \(done.count)/\(g.structure.count)").font(.nx(.caption, .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                        ForEach(Array(g.structure.enumerated()), id: \.offset) { i, s in
                            Button {
                                if done.contains(i) { done.remove(i) } else { done.insert(i) }
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: done.contains(i) ? "checkmark.square.fill" : "square").foregroundStyle(done.contains(i) ? Theme.accent : Color.secondary)
                                    SpanishGuideText.md(s).font(.nx(.callout)).strikethrough(done.contains(i)).foregroundStyle(done.contains(i) ? Color.secondary : Color.primary)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("spanish-guide-step-\(i)")
                        }
                    }
                    DisclosureGroup("Rules") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(g.rules.enumerated()), id: \.offset) { _, s in
                                HStack(alignment: .firstTextBaseline, spacing: 6) { Image(systemName: "checkmark").font(.nx(.caption)).foregroundStyle(Theme.accent); SpanishGuideText.md(s) }
                            }
                        }
                        .font(.nx(.callout)).padding(.top, 4)
                    }
                    Text("Tap a sentence stem to put it in").font(.nx(.caption)).foregroundStyle(.secondary)
                    SpanishGuideItems(title: "Sentence stems", groups: g.stems, status: d.status, put: put)
                    DisclosureGroup("Vocabulary") { SpanishGuideItems(title: "Vocabulary", groups: g.vocab, status: d.status).padding(.top, 4) }
                    NavigationLink { SpanishGuideView(workstreamId: workstreamId, slug: g.slug) } label: { Text("The full guide, with its exemplar") }
                        .font(.nx(.callout))
                        .accessibilityIdentifier("spanish-guide-full")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spanish-guide-panel")
    }
}

/// The piece as marked: each mistake underlined in red where it is, its fix in the list below.
struct SpanishMarkedPiece: View {
    let text: String
    let mistakes: [SpanishCheck.LogMistake]

    var body: some View {
        Self.parts(text, mistakes).reduce(Text("")) { t, p in
            t + (p.wrong ? Text(p.text).underline(true, color: Theme.late).foregroundColor(Theme.late) : Text(p.text))
        }
        .font(.nx(.body))
        .textSelection(.enabled)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
        .accessibilityIdentifier("spanish-graded-piece")
    }

    /// The piece cut where each mistake's words are (the first place each is found, never overlapping one already found).
    static func parts(_ text: String, _ mistakes: [SpanishCheck.LogMistake]) -> [(text: String, wrong: Bool)] {
        var taken: [Range<String.Index>] = []
        for m in mistakes where !m.wrong.isEmpty {
            var from = text.startIndex
            while from < text.endIndex, let r = text.range(of: m.wrong, range: from..<text.endIndex) {
                if !taken.contains(where: { $0.overlaps(r) }) { taken.append(r); break }
                from = r.upperBound
            }
        }
        var out: [(text: String, wrong: Bool)] = []
        var at = text.startIndex
        for r in taken.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if at < r.lowerBound { out.append((String(text[at..<r.lowerBound]), false)) }
            out.append((String(text[r]), true))
            at = r.upperBound
        }
        if at < text.endIndex { out.append((String(text[at...]), false)) }
        return out
    }
}
