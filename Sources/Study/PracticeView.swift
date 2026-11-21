import SwiftUI
import NexusCore

/// Practice classifying, as the laptop has it (studypractice.js): a deck's `practice:` list (every acid and base to sort into strong /
/// weak acid / base, say), every item once, shuffled, answered with the deck's options or by typing; a wrong answer shows the right one
/// and the rule card that explains it. It ends with the score and "Practise the missed ones". Unscheduled: nothing is written.
struct PracticeView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    let workstreamId: String
    let path: String

    @AppStorage("studyPracticeLevel") private var level = "all"
    @AppStorage("studyPracticeMode") private var mode = "options"

    enum Phase { case setup, ask, shown, end }
    @State private var phase = Phase.setup
    @State private var items: [String] = []
    @State private var idx = 0
    @State private var right = 0
    @State private var missed: [String] = []
    @State private var typed = ""
    @State private var picked: String?
    @State private var result: StudyDeck.Verdict?
    @State private var missedRound = false
    @FocusState private var typing: Bool

    private var deck: StudyDeck? { StudyLibrary.shared.study(workstreamId)?.decks.first { $0.path == path }?.deck }

    var body: some View {
        Group {
            if let k = deck, !k.practice.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        progress
                        switch phase {
                        case .setup: setup(k)
                        case .end: endView(k)
                        case .ask, .shown: itemView(k)
                        }
                    }
                    .padding(size == .regular ? 32 : 18)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            } else {
                EmptyNote(title: "This deck has nothing to practise", detail: nil, icon: "square.grid.2x2")
            }
        }
        .navigationTitle(missedRound ? "The missed ones" : "Practice classifying")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var progress: some View {
        if phase != .setup && !items.isEmpty {
            let done = min(idx + (phase == .shown ? 1 : 0), items.count)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(deck?.title ?? "").font(.nx(.subheadline, .semibold))
                    Spacer()
                    Text("\(done) of \(items.count) · \(right) right").font(.nx(.subheadline).monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityIdentifier("practice-count")
                }
                ProgressView(value: Double(done), total: Double(max(items.count, 1))).tint(Theme.accent)
            }
        }
    }

    // MARK: setup

    private func count(_ k: StudyDeck, _ lv: String) -> Int {
        let has = (StudyUnits.levels.first { $0.id == lv } ?? StudyUnits.levels[0]).has
        return k.practice.filter { has.contains($0.level) }.count
    }

    @ViewBuilder
    private func setup(_ k: StudyDeck) -> some View {
        let levels = StudyUnits.levels.filter { $0.id == "all" || count(k, $0.id) < count(k, "all") }
        let n = count(k, levels.contains { $0.id == level } ? level : "all")
        VStack(alignment: .leading, spacing: 14) {
            Text(k.title).font(.nx(.title2, .semibold))
            Text("Sort each one: \(StudyUnits.practiceOptions(k).joined(separator: " / "))").font(.nx(.headline))
            if levels.count > 1 {
                Text("Which").font(.nx(.subheadline)).foregroundStyle(.secondary)
                let which = Picker("Which", selection: $level) {
                    ForEach(levels, id: \.id) { lv in Text("\(lv.label) (\(count(k, lv.id)))").tag(lv.id) }
                }
                .labelsHidden()
                if size == .regular { which.pickerStyle(.segmented) } else { which.pickerStyle(.inline) }
            }
            Text("How").font(.nx(.subheadline)).foregroundStyle(.secondary)
            Picker("How", selection: $mode) {
                Text("Choose").tag("options")
                Text("Type it").tag("type")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Button { start(k) } label: {
                Text("Start: \(n) \(n == 1 ? "item" : "items"), shuffled").font(.nx(.headline)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(n == 0)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityIdentifier("practice-start")
            Text("Unscheduled: it does not change when cards are due.").font(.nx(.footnote)).foregroundStyle(.secondary)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func start(_ k: StudyDeck, ids: [String]? = nil) {
        let lv = levelsHave(k, level) ? level : "all"
        items = StudyUnits.practiceRound(k, level: lv, ids: ids, seed: String(StudyLibrary.now))
        idx = 0; right = 0; missed = []; typed = ""; picked = nil; result = nil
        missedRound = ids != nil
        phase = items.isEmpty ? .setup : .ask
        typing = mode == "type"
    }

    private func levelsHave(_ k: StudyDeck, _ lv: String) -> Bool { StudyUnits.levels.contains { $0.id == lv } }

    // MARK: an item

    @ViewBuilder
    private func itemView(_ k: StudyDeck) -> some View {
        if let item = k.practice.first(where: { $0.id == items[idx] }) {
            let opts = StudyUnits.practiceOptions(k)
            VStack(alignment: .leading, spacing: 16) {
                Text("Which is it? \(opts.joined(separator: " / "))").font(.nx(.subheadline)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name.isEmpty ? item.formula : item.name).font(.system(size: 30, weight: .semibold))
                        .accessibilityIdentifier("practice-prompt")
                    if !item.name.isEmpty && !item.formula.isEmpty { Text(item.formula).font(.title3.monospaced()).foregroundStyle(.secondary) }
                }
                if mode == "options" || (phase == .shown && typed.isEmpty) {
                    options(opts, item)
                } else if phase == .ask {
                    HStack(spacing: 10) {
                        TextField("strong acid, or sa / wa / sb / wb", text: $typed)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .focused($typing)
                            .onSubmit { answer(k, typed, typedIn: true) }
                            .accessibilityIdentifier("practice-type")
                        Button("Check") { answer(k, typed, typedIn: true) }.buttonStyle(.bordered)
                    }
                }
                if phase == .shown { shown(k, item) }
            }
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// The options: two by two on the iPad, one under another on the iPhone.
    private func options(_ opts: [String], _ item: StudyDeck.PracticeItem) -> some View {
        let cols = size == .regular && opts.count > 2 ? [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)] : [GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(Array(opts.enumerated()), id: \.offset) { i, o in
                let isRight = StudyDeck.check(o, item.answer) == .right
                let state: Int = phase == .shown ? (isRight ? 1 : o == picked ? -1 : 0) : 0
                Button { if let k = deck { answer(k, o, typedIn: false) } } label: {
                    HStack(spacing: 10) {
                        if size == .regular {
                            Text("\(i + 1)").font(.nx(.caption).monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 20, height: 20).background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 5))
                        }
                        Text(o).font(.nx(.body, .medium)).foregroundStyle(.primary)
                        Spacer(minLength: 4)
                        if state == 1 { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                        if state == -1 { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.late) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(state == 1 ? Theme.accent.opacity(0.14) : state == -1 ? Theme.late.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(state == 1 ? Theme.accent : state == -1 ? Theme.late : Color(uiColor: .separator), lineWidth: state == 0 ? 0.5 : 1.5))
                }
                .buttonStyle(.plain)
                .disabled(phase == .shown)
                .keyboardShortcut(i < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: []) : nil)
                .accessibilityIdentifier("practice-option-\(i)")
            }
        }
    }

    @ViewBuilder
    private func shown(_ k: StudyDeck, _ item: StudyDeck.PracticeItem) -> some View {
        let ok = result == .right
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(ok ? Theme.accent : Theme.late)
                Text(ok ? "Right." : "Not quite.").font(.nx(.headline))
                if !ok && !typed.isEmpty { Text("You wrote \(Text(typed).bold()).").foregroundStyle(.secondary) }
            }
            .accessibilityIdentifier("practice-result")
            if !ok { Text("It is a \(item.answer).").font(.nx(.body, .medium)) }
            if !item.note.isEmpty { Text(item.note).font(.nx(.callout)).foregroundStyle(.secondary) }
            if !ok, let rule = StudyUnits.ruleOf(k, item) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("The rule").font(.nx(.caption, .semibold)).foregroundStyle(.secondary)
                    (Text(rule.front).bold() + Text(" → ") + Text(rule.back)).font(.nx(.callout))
                    if !rule.note.isEmpty { Text(rule.note).font(.nx(.caption)).foregroundStyle(.secondary) }
                    if !rule.covers.isEmpty { Text("Covers: " + rule.covers.joined(separator: ", ")).font(.nx(.caption)).foregroundStyle(.secondary) }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            Button { next() } label: {
                Text(idx + 1 >= items.count ? "See the score" : "Next").font(.nx(.headline)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .accessibilityIdentifier("practice-next")
        }
    }

    private func answer(_ k: StudyDeck, _ value: String, typedIn: Bool) {
        guard phase == .ask, idx < items.count, let item = k.practice.first(where: { $0.id == items[idx] }) else { return }
        let r: StudyDeck.Verdict = typedIn ? StudyUnits.practiceCheck(value, item) : (StudyDeck.check(value, item.answer) == .right ? .right : .wrong)
        if r == .empty { return }
        result = r
        if typedIn { typed = value } else { picked = value; typed = "" }
        if r == .right { right += 1 } else { missed.append(item.id) }
        withAnimation(.snappy) { phase = .shown }
    }

    private func next() {
        idx += 1; typed = ""; picked = nil; result = nil
        withAnimation(.snappy) { phase = idx >= items.count ? .end : .ask }
        typing = phase == .ask && mode == "type"
    }

    // MARK: the end

    @ViewBuilder
    private func endView(_ k: StudyDeck) -> some View {
        let n = items.count
        let gone = missed.compactMap { id in k.practice.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 14) {
            Text("\(right) of \(n) right").font(.nx(.largeTitle, .semibold)).accessibilityIdentifier("practice-score")
            if n > 0 {
                Text("\(Int((Double(right) / Double(n) * 100).rounded()))%" + (gone.isEmpty ? "; none missed." : "; \(gone.count) to look at again."))
                    .foregroundStyle(.secondary)
            }
            if !gone.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(gone, id: \.id) { m in
                        (Text(m.name.isEmpty ? m.formula : m.name).bold()
                         + Text(!m.name.isEmpty && !m.formula.isEmpty ? " \(m.formula)" : "")
                         + Text(" → \(m.answer)").foregroundStyle(.secondary))
                            .font(.nx(.callout))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                Button { start(k, ids: gone.map(\.id)) } label: {
                    Text("Practise the missed ones (\(gone.count))").font(.nx(.headline)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("practice-missed")
            }
            Button { start(k) } label: { Text("Again, all of them").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
            Button("Change the settings") { phase = .setup }
                .frame(maxWidth: .infinity)
        }
    }
}
