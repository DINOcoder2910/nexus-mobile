import SwiftUI
import NexusCore

/// Study: every workstream's memorize decks, with what is due (the sidebar's Study, and the Study section of a workstream's page).
struct StudyHome: View {
    @Environment(NexusStore.self) private var store
    private var lib: StudyLibrary { StudyLibrary.shared }

    var body: some View {
        List {
            let studies = lib.studies.filter { !$0.decks.isEmpty }
            if studies.isEmpty {
                Section {
                    EmptyNote(title: "No study decks yet",
                              detail: "Decks are the YAML files in a workstream's study/decks folder. Make them on the laptop (Study tab); they come here with sync.",
                              icon: "rectangle.on.rectangle.angled")
                        .listRowBackground(Color.clear)
                }
            } else {
                let due = lib.dueTotal
                Section {
                    Text(due == 0 ? "Nothing due right now." : "\(due) \(due == 1 ? "card" : "cards") due.")
                        .font(.title3.weight(.semibold))
                        .listRowBackground(Color.clear)
                }
                ForEach(studies) { s in
                    Section {
                        DeckRows(study: s)
                    } header: {
                        HStack(spacing: 8) {
                            Circle().fill(store.color(workstream: s.id)).frame(width: 9, height: 9)
                            SectionTitle(title: s.workstream.name)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Study")
        .refreshable { lib.load(store) }
        .studyRefresh(store)
    }
}

/// A workstream's decks as rows that open the deck.
struct DeckRows: View {
    let study: StudyLibrary.Study

    var body: some View {
        ForEach(study.decks) { f in
            if let deck = f.deck {
                NavigationLink {
                    DeckView(workstreamId: study.id, path: f.path)
                } label: {
                    DeckRowLabel(study: study, file: f, deck: deck)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.fileId).foregroundStyle(.secondary)
                    Label("This deck \(f.error ?? "could not be read").", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Theme.late)
                }
            }
        }
    }
}

private struct DeckRowLabel: View {
    let study: StudyLibrary.Study
    let file: StudyFolder.DeckFile
    let deck: StudyDeck

    var body: some View {
        let c = StudyLibrary.shared.counts(study, file)
        HStack(spacing: 10) {
            Image(systemName: deck.flip ? "character.bubble" : "rectangle.on.rectangle.angled")
                .foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.title).lineLimit(1)
                Text("\(deck.cards.count) \(deck.cards.count == 1 ? "card" : "cards")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if let c {
                if c.due > 0 { Chip(text: "\(c.due) due", color: Theme.accent, strong: true) }
                if c.new > 0 { Chip(text: "\(c.new) new") }
            }
        }
    }
}

extension View {
    /// Reads the decks again when they change on disk (sync, the Files app), every few seconds while the screen is open.
    func studyRefresh(_ store: NexusStore) -> some View {
        task(id: store.snapshot.loadedAt) {
            StudyLibrary.shared.refreshIfChanged(store)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                StudyLibrary.shared.refreshIfChanged(store)
            }
        }
    }
}

// MARK: a deck

/// One deck: how to review it (mode, direction, new cards), Start, and every card with how well it is known.
struct DeckView: View {
    @Environment(NexusStore.self) private var store
    let workstreamId: String
    let path: String

    @State private var prefs = DeckPrefs()
    @State private var session: SessionBox?
    @State private var clock = StudyLibrary.now

    struct SessionBox: Identifiable { let id = UUID(); var session: StudySession }

    private var lib: StudyLibrary { StudyLibrary.shared }
    private var study: StudyLibrary.Study? { lib.study(workstreamId) }
    private var file: StudyFolder.DeckFile? { study?.decks.first { $0.path == path } }

    var body: some View {
        Group {
            if let study, let deck = file?.deck {
                content(study, deck)
            } else {
                EmptyNote(title: "This deck is not in the folder", detail: "It may have been renamed or moved on the laptop.", icon: "questionmark.folder")
            }
        }
        .navigationTitle(file?.deck?.title ?? "Deck")
        .navigationBarTitleDisplayMode(.inline)
        .studyRefresh(store)
        .onAppear { if let d = file?.deck { prefs = DeckPrefs.of(workstreamId, d.id) } }
        .onChange(of: prefs) { _, p in if let d = file?.deck { DeckPrefs.set(p, workstreamId, d.id) } }
        .fullScreenCover(item: $session) { box in
            ReviewView(session: box.session, workstreamId: workstreamId) { more in
                session = nil
                clock = StudyLibrary.now
                if more { start(practise: false) }
            }
        }
    }

    private func dir(_ deck: StudyDeck) -> StudyDeck.Direction { deck.flip || !deck.reversible ? .forward : prefs.dir }
    private func ids(_ deck: StudyDeck) -> [String] { StudySession.cardIds(deck, tag: deck.flip ? prefs.tag : "") }

    @ViewBuilder
    private func content(_ study: StudyLibrary.Study, _ deck: StudyDeck) -> some View {
        let states = study.book.states(deck.id, dir(deck))
        let now = max(clock, StudyLibrary.now)
        let c = FSRS.counts(ids(deck), states, now)
        let startedToday = deck.flip ? StudySession.newToday(study.book.states(deck.id, .forward), now: now) : 0
        let newCap = deck.flip ? max(0, prefs.perDay - startedToday) : prefs.newLimit
        let n = c.due + min(c.new, newCap)
        let canWrite = lib.canWrite(store)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(deck.title).font(.title2.weight(.semibold))
                    if !deck.description.isEmpty { Text(deck.description).font(.callout).foregroundStyle(.secondary) }
                    HStack(spacing: 6) {
                        Chip(text: "\(c.due) due", color: c.due > 0 ? Theme.accent : .secondary, strong: c.due > 0)
                        Chip(text: "\(c.new) new")
                        if c.learning > 0 { Chip(text: "\(c.learning) learning") }
                        Chip(text: "\(c.known) known")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("How") {
                if deck.flip {
                    Picker("Shown first", selection: $prefs.show) {
                        ForEach(StudyDeck.Show.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    let tags = deck.tags()
                    if !tags.isEmpty {
                        Picker("Tag", selection: $prefs.tag) {
                            Text("Every card (\(deck.cards.count))").tag("")
                            ForEach(tags, id: \.tag) { t in Text("\(t.tag) (\(t.n))").tag(t.tag) }
                        }
                    }
                    Stepper(value: $prefs.perDay, in: 0...999) {
                        VStack(alignment: .leading) {
                            Text("\(prefs.perDay) new cards a day")
                            Text("\(startedToday) started today, \(c.new) not seen yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Picker("Mode", selection: $prefs.mode) {
                        ForEach(StudySession.Mode.allCases, id: \.rawValue) { Text(shortLabel($0)).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(prefs.sessionMode.detail).font(.caption).foregroundStyle(.secondary)
                    if deck.reversible {
                        Picker("Which way", selection: $prefs.direction) {
                            ForEach(StudyDeck.Direction.allCases, id: \.rawValue) { Text(deck.directionLabel($0)).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        Text("Each way keeps its own schedule.").font(.caption).foregroundStyle(.secondary)
                    }
                    Stepper(value: $prefs.newLimit, in: 0...999) {
                        VStack(alignment: .leading) {
                            Text("At most \(prefs.newLimit) new cards")
                            Text("\(c.new) not seen yet").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button { start(practise: false) } label: {
                    Text(n > 0 ? "Start: \(n) \(n == 1 ? "card" : "cards")" : "Nothing due").frame(maxWidth: .infinity).font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(n == 0 || !canWrite)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .keyboardShortcut(.return, modifiers: .command)
                Button(deck.flip ? "Review all, unscheduled" : "Practise all, unscheduled") { start(practise: true) }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } footer: {
                if !canWrite {
                    Text("This folder is read-only here, so reviews can't be saved. Practising still works.")
                } else if n == 0 {
                    Text(StudySession.nextDueText(states, ids: ids(deck), now: now))
                } else {
                    Text("Every way of grading goes into study/review.yaml, which the laptop reads too.")
                }
            }

            ForEach(Array(deck.sections().enumerated()), id: \.offset) { _, sec in
                Section(sec.title.isEmpty ? "Cards" : sec.title) {
                    ForEach(sec.cards) { card in CardRow(deck: deck, card: card, state: states[card.id], now: now) }
                }
            }
            if !deck.sources.isEmpty {
                Section("Sources") {
                    ForEach(Array(deck.sources.enumerated()), id: \.offset) { _, s in
                        if let u = URL(string: s.url), !s.url.isEmpty { Link(s.title, destination: u) } else { Text(s.title) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func shortLabel(_ m: StudySession.Mode) -> String { m == .flip ? "Flip" : m == .type ? "Type" : "Choose" }

    private func start(practise: Bool) {
        guard let study, let deck = file?.deck else { return }
        let now = StudyLibrary.now
        let started = deck.flip ? StudySession.newToday(study.book.states(deck.id, .forward), now: now) : 0
        let limit = deck.flip ? max(0, prefs.perDay - started) : prefs.newLimit
        if let s = StudySession(deck: deck, dir: prefs.dir, mode: prefs.sessionMode, show: prefs.showFirst, tag: prefs.tag, newLimit: limit,
                                practise: practise, states: study.book.states(deck.id, dir(deck)), now: now) {
            session = SessionBox(session: s)
        } else {
            store.toast = .init(message: "Nothing to review in this deck right now.")
        }
    }
}

/// A card in the deck's list: its two sides and how well it is known.
private struct CardRow: View {
    let deck: StudyDeck
    let card: StudyDeck.Card
    let state: SRSCard?
    let now: Int64

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.front)
                Text(card.back).foregroundStyle(.secondary)
                if !card.covers.isEmpty { Text(card.covers.joined(separator: ", ")).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 6)
            status
        }
        .font(.callout)
    }

    @ViewBuilder private var status: some View {
        if let s = state, s.state != .new {
            if s.due <= now { Chip(text: "due", color: Theme.accent, strong: true) }
            else if s.state == .review { Chip(text: FSRS.untilWords(s.due, now)) }
            else { Chip(text: "learning", color: Theme.soon) }
        } else {
            Chip(text: "new", color: Color.secondary.opacity(0.8))
        }
    }
}
