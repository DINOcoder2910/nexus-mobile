import SwiftUI
import NexusCore

/// A review session, full screen: the prompt, then the answer and the four grades (Again, Hard, Good, Easy, each with when the card
/// would come back). Each grade is written to study/review.yaml at once. Keys with a keyboard: Space or Return shows the answer,
/// 1-4 pick a multiple-choice option and then grade, Return takes the suggested grade, ⌘Z takes the last grade back.
struct ReviewView: View {
    @Environment(NexusStore.self) private var store
    @State var session: StudySession
    let workstreamId: String
    /// Closes the session (true: start another one).
    let close: (Bool) -> Void

    @State private var typed = ""
    @FocusState private var typing: Bool

    private var lib: StudyLibrary { StudyLibrary.shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if session.phase == .end { endView } else { cardView }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(session.deck.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close(false) } label: { Label("Close", systemImage: "xmark") }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(session.deck.title).font(.headline).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(!session.canUndo)
                        .keyboardShortcut("z", modifiers: .command)
                }
            }
            .alert("Couldn't save", isPresented: Binding(get: { lib.problem != nil }, set: { if !$0 { lib.problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(lib.problem ?? "") }
        }
    }

    private var subtitle: String {
        var bits = [session.mode.label]
        if session.deck.reversible { bits.append(session.deck.directionLabel(session.dir)) }
        if let s = session.show { bits.append(s.label) }
        if !session.tag.isEmpty { bits.append("tag " + session.tag) }
        if session.practise { bits.append("unscheduled") }
        return bits.joined(separator: " · ")
    }

    // MARK: the card

    @ViewBuilder private var cardView: some View {
        let side = session.side
        ProgressView(value: Double(min(session.done, session.total)), total: Double(max(1, session.total)))
            .tint(Theme.accent)
        ScrollView {
            VStack(spacing: 20) {
                Text("\(session.done) done · \(session.queue.count + 1) to go")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(side?.prompt ?? "")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .padding(.vertical, 12)

                switch session.mode {
                case .type: typeArea(side)
                case .mcq: choiceArea
                case .flip: EmptyView()
                }

                if session.phase == .shown { answerArea(side) }
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        bottomBar
    }

    @ViewBuilder private func typeArea(_ side: StudyDeck.Side?) -> some View {
        if session.phase == .ask {
            HStack {
                TextField("Type the answer", text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.title3)
                    .focused($typing)
                    .submitLabel(.done)
                    .onSubmit(submit)
                Button("Check", action: submit).buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .onAppear { typing = true }
        } else if let r = session.result {
            let v = verdict(r)
            VStack(spacing: 6) {
                Label(v.0, systemImage: v.2).font(.headline).foregroundStyle(v.1)
                if r != .right, !session.typed.isEmpty {
                    Text("You wrote: \(session.typed)").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func verdict(_ r: StudyDeck.Verdict) -> (String, Color, String) {
        switch r {
        case .right: return ("Right", Theme.planned, "checkmark.circle.fill")
        case .case: return ("Right but for capitals", Theme.soon, "textformat")
        case .empty: return ("No answer", .secondary, "questionmark.circle")
        case .wrong: return ("Not quite", Theme.late, "xmark.circle.fill")
        }
    }

    @ViewBuilder private var choiceArea: some View {
        if let c = session.choices {
            VStack(spacing: 10) {
                ForEach(Array(c.options.enumerated()), id: \.offset) { i, o in
                    let shown = session.phase == .shown
                    let isRight = i == c.correct, isPicked = i == session.picked
                    Button { session.pick(i) } label: {
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
                                .frame(width: 22, height: 22).background(Color.secondary.opacity(0.12), in: Circle())
                            Text(o).font(.title3).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if shown && isRight { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.planned) }
                            else if shown && isPicked { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.late) }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(
                            shown && isRight ? Theme.planned.opacity(0.14) : shown && isPicked ? Theme.late.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground)))
                    }
                    .buttonStyle(.plain)
                    .disabled(shown)
                    .keyboardShortcut(i < 9 ? KeyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: []) : nil)
                }
            }
        }
    }

    @ViewBuilder private func answerArea(_ side: StudyDeck.Side?) -> some View {
        VStack(spacing: 10) {
            if session.mode != .mcq {
                Divider()
                Text(side?.answer ?? "")
                    .font(.system(.title, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            if let card = session.card {
                if !card.note.isEmpty { Text(card.note).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if !card.example.isEmpty { Text(card.example).font(.callout.italic()).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                if !card.covers.isEmpty { Text(card.covers.joined(separator: ", ")).font(.caption).foregroundStyle(.tertiary) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: the bar at the bottom: Show answer, or the grades

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 8) {
            if session.phase == .ask {
                if session.mode == .flip {
                    Button { session.reveal() } label: { Text("Show answer").font(.headline).frame(maxWidth: .infinity, minHeight: 34) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.space, modifiers: [])
                } else if session.mode == .type {
                    Button("I don't know: show the answer") { submit() }.font(.callout)
                } else {
                    Text("Pick one").font(.callout).foregroundStyle(.secondary)
                }
            } else {
                let previews = session.preview(StudyLibrary.now)
                let suggested = session.suggested ?? 3
                HStack(spacing: 8) {
                    ForEach(previews, id: \.grade.g) { p in
                        let on = p.grade.g == suggested
                        Button { grade(p.grade.g) } label: {
                            VStack(spacing: 2) {
                                Text(p.grade.label).font(.subheadline.weight(.semibold))
                                Text(p.inText).font(.caption2).opacity(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(color(p.grade.g))
                        .overlay { if on && session.mode != .flip { RoundedRectangle(cornerRadius: 9).stroke(color(p.grade.g), lineWidth: 2) } }
                        .keyboardShortcut(KeyEquivalent(Character(String(p.grade.g))), modifiers: [])
                    }
                }
                // Return: the suggested grade (Good when you grade yourself)
                Button("") { grade(suggested) }.keyboardShortcut(.return, modifiers: []).opacity(0).frame(height: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func color(_ g: Int) -> Color { g == 1 ? Theme.late : g == 2 ? Theme.soon : g == 3 ? Theme.planned : Theme.claude }

    // MARK: the end

    private var endView: some View {
        let s = session
        let states = s.states
        let ids = StudySession.cardIds(s.deck, tag: s.tag)
        let next = s.practise ? "" : StudySession.nextDueText(states, ids: ids, now: StudyLibrary.now)
        let left = s.practise ? FSRS.Counts() : FSRS.counts(ids, states, StudyLibrary.now)
        return VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 52)).foregroundStyle(Theme.accent)
            Text(s.practise ? "Practice done" : "Session done").font(.title.weight(.semibold))
            Text("\(s.done) \(s.done == 1 ? "card" : "cards") reviewed, \(s.right) right the first time.")
                .foregroundStyle(.secondary)
            if !next.isEmpty { Text(next).font(.callout).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                if !s.practise && (left.due > 0 || left.new > 0) {
                    Button("Review more") { close(true) }.buttonStyle(.bordered).controlSize(.large)
                }
                Button("Done") { close(false) }.buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding(24)
    }

    // MARK: actions

    private func submit() {
        guard session.phase == .ask, session.mode == .type else { return }
        session.submit(typed)
        typing = false
    }

    private func grade(_ g: Int) {
        guard session.phase == .shown else { return }
        let deckId = session.deck.id, dir = session.dir
        if let kept = session.grade(g, now: StudyLibrary.now) {
            lib.keep(store, workstream: workstreamId, deck: deckId, dir: dir, card: kept.card, state: kept.state)
        }
        typed = ""
        if session.mode == .type && session.phase == .ask { typing = true }
    }

    private func undo() {
        let deckId = session.deck.id, dir = session.dir
        if let back = session.undo() {
            lib.keep(store, workstream: workstreamId, deck: deckId, dir: dir, card: back.card, state: back.state)
        }
        typed = ""
    }
}
