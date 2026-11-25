import SwiftUI
import NexusCore

/// Writing, the IB Paper 1 way (nexus app/spanishview.js writingSection / writeView): the prompts your tutor gives you (added by you;
/// Nexus never writes prompts), a piece written for one with the word count as the IB counts it, and Mark it: Claude marks it by the
/// official criteria and the examiners' rules (and your teacher's marked samples, if any), the caps are applied in code, and the piece is
/// saved as writing/<day> <words>.md with its marks.
@MainActor
@Observable
final class SpanishGradeRun {
    var busy = false
    var error = ""
    var grade: SpanishGrade.Grade?
    var path = ""
    var text = ""

    static func key(_ wsId: String, _ promptId: String) -> String { wsId + "|" + promptId }

    static func mark(_ store: NexusStore, _ wsId: String, _ prompt: SpanishGrade.Prompt) {
        let lib = SpanishLibrary.shared
        let k = key(wsId, prompt.id)
        let text = (lib.drafts[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, lib.grades[k]?.busy != true else { return }
        let count = SpanishGrade.wordCount(text)
        let g = SpanishGradeRun()
        g.busy = true
        g.text = text
        lib.grades[k] = g
        let guide = lib.guide(wsId, prompt: prompt).map(SpanishTextTypes.conventions) ?? ""
        let ask = SpanishGrade.gradePrompt(prompt: prompt, text: text, count: count, samples: lib.data(wsId).samples, guide: guide)
        Task {
            do {
                let reply = try await SpanishClaude.once(model: SpanishModel.current, system: SpanishGrade.system, prompt: ask, maxTokens: 6000, demo: { SpanishDemo.grade() })
                guard let grade = SpanishGrade.readGrade(SpanishCheck.jsonFrom(reply), count: count) else { throw ClaudeError("the answer had no marks") }
                g.grade = grade
                g.path = lib.savePiece(store, wsId, prompt: prompt, text: text, count: count, grade: grade) ?? ""
            } catch {
                g.error = "Could not mark it: " + error.localizedDescription
            }
            g.busy = false
        }
    }
}

/// The prompts, each with its pieces and a Write button.
struct SpanishPromptRows: View {
    let workstreamId: String
    var lib: SpanishLibrary { .shared }

    var body: some View {
        let d = lib.data(workstreamId)
        if let e = d.promptsError {
            Label(e, systemImage: "exclamationmark.triangle").font(.nx(.footnote)).foregroundStyle(Theme.late)
        }
        if d.prompts.isEmpty {
            Text("Add the prompts your tutor gives you. Nexus never writes prompts; it marks what you write exactly as the IB does.")
                .font(.nx(.callout)).foregroundStyle(.secondary)
                .accessibilityIdentifier("spanish-prompts-empty")
        }
        ForEach(d.prompts) { p in
            let mine = d.pieces.filter { $0.prompt == p.id }
            NavigationLink {
                SpanishWriteView(workstreamId: workstreamId, promptId: p.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.text).lineLimit(3).font(.nx(.callout))
                    let facts = [p.unit.isEmpty ? "" : Spanish.units.first { $0.code == p.unit }?.title ?? p.unit, p.types.joined(separator: ", "), p.source,
                                 mine.isEmpty ? "" : "\(mine.count) \(mine.count == 1 ? "piece" : "pieces")" + (mine.first?.total.map { ", last \($0)/15" } ?? "")].filter { !$0.isEmpty }
                    if !facts.isEmpty { Text(facts.joined(separator: " · ")).font(.nx(.caption)).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("spanish-prompt-\(p.id)")
        }
        NavigationLink {
            SpanishTextTypesList(workstreamId: workstreamId)
        } label: {
            Label(d.guides.isEmpty ? "Text type guides" : "Text type guides (\(d.guides.count))", systemImage: "text.book.closed")
        }
        .accessibilityIdentifier("spanish-text-types")
        Text(d.samples.isEmpty ? "Teacher-marked samples: none yet. Put marked pieces in \(Spanish.P.samples)/ (A, B and C in the front matter) and the marking matches your teacher's standard."
                               : "Marking matches \(d.samples.count) \(d.samples.count == 1 ? "piece" : "pieces") your teacher marked (\(Spanish.P.samples)/).")
            .font(.nx(.caption)).foregroundStyle(.secondary)
    }
}

/// Writing on the iPhone: its own page.
struct SpanishWritingList: View {
    let workstreamId: String
    @State private var adding = false

    var body: some View {
        List {
            Section {
                SpanishPromptRows(workstreamId: workstreamId)
            } header: {
                Text("IB Paper 1: 70–150 words · A Language /6 · B Message /6 · C Conceptual understanding /3").textCase(nil)
            }
        }
        .navigationTitle("Writing")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label("Add a prompt", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) { SpanishPromptSheet(workstreamId: workstreamId) }
    }
}

/// Add a prompt: its words, the unit, the text types offered (filled in from the words until you change them) and where it came from.
struct SpanishPromptSheet: View {
    let workstreamId: String
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var unit = Spanish.currentUnit?.code ?? ""
    @State private var types = ""
    @State private var typesTouched = false
    @State private var source = ""
    @FocusState private var focus: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("The prompt, exactly as your tutor gave it") {
                    TextField("The prompt", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focus)
                        .accessibilityIdentifier("spanish-prompt-text")
                        .onChange(of: text) { _, t in if !typesTouched { types = SpanishGrade.typesIn(t).joined(separator: ", ") } }
                }
                Section {
                    Picker("Unit", selection: $unit) {
                        Text("No unit").tag("")
                        ForEach(Spanish.units, id: \.code) { u in Text("\(u.code) \(u.title)").tag(u.code) }
                    }
                    TextField("Text types offered: correo electrónico, blog, diario", text: Binding(get: { types }, set: { types = $0; typesTouched = true }))
                    TextField("Where it came from (Ms. Panhausen, worksheet 3)", text: $source)
                }
            }
            .navigationTitle("Add a prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add the prompt") {
                        let ok = SpanishLibrary.shared.addPrompt(store, workstreamId, text: text.trimmingCharacters(in: .whitespacesAndNewlines), unit: unit,
                                                                 types: types.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, source: source.trimmingCharacters(in: .whitespaces))
                        if ok { store.toast = .init(message: "Prompt added"); dismiss() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focus = true }
        }
    }
}

/// The writing page: the prompt, the piece, the count the IB way as you type, Mark it, the marks, your pieces.
struct SpanishWriteView: View {
    let workstreamId: String
    let promptId: String
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    /// the iPad's side column: the text type's guide, or the marks
    @State private var side = "guide"
    @State private var guideOpen = false
    var lib: SpanishLibrary { .shared }

    var body: some View {
        SpanishHost(workstreamId: workstreamId) {
            if let p = lib.data(workstreamId).prompts.first(where: { $0.id == promptId }) {
                Group {
                    if size == .regular {
                        HStack(alignment: .top, spacing: 24) {
                            ScrollView { writing(p).padding(.vertical) }.frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Beside the piece", selection: $side) {
                                    Text("Text type").tag("guide")
                                    Text("Marks").tag("marks")
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("spanish-side")
                                ScrollView {
                                    Group {
                                        if side == "guide" { SpanishGuidePanel(workstreamId: workstreamId, prompt: p, put: { put(p, $0) }) } else { marks(p) }
                                    }
                                    .padding(.vertical)
                                }
                            }
                            .padding(.top)
                            .frame(maxWidth: 460)
                        }
                        .padding(.horizontal, 24)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) { writing(p); marks(p) }.padding()
                        }
                    }
                }
                .navigationTitle("Writing")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .primaryAction) { SpanishModelMenu() } }
                .spanishKeyboardDone()
                .onChange(of: lib.grades[SpanishGradeRun.key(workstreamId, p.id)]?.busy) { _, busy in if busy == true { side = "marks" } }
                .sheet(isPresented: $guideOpen) {
                    NavigationStack {
                        ScrollView { SpanishGuidePanel(workstreamId: workstreamId, prompt: p, put: { put(p, $0) }).padding() }
                            .navigationTitle("Text type")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { guideOpen = false }.accessibilityIdentifier("spanish-guide-done") } }
                    }
                    .presentationDetents([.medium, .large])
                }
            } else {
                EmptyNote(title: "This prompt is no longer in prompts.yaml.", icon: "questionmark.folder")
            }
        }
    }

    /// A sentence stem into the piece, at its end (an unfinished stem's "…" left for you to go on from).
    private func put(_ p: SpanishGrade.Prompt, _ stem: String) {
        let k = SpanishGradeRun.key(workstreamId, p.id)
        var t = lib.drafts[k] ?? ""
        var s = stem
        if s.hasSuffix("…") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty && !t.hasSuffix(" ") && !t.hasSuffix("\n") { t += " " }
        lib.drafts[k] = t + s + " "
    }

    private func writing(_ p: SpanishGrade.Prompt) -> some View {
        let k = SpanishGradeRun.key(workstreamId, p.id)
        let text = Binding(get: { lib.drafts[k] ?? "" }, set: { lib.drafts[k] = $0 })
        let c = SpanishGrade.wordCount(text.wrappedValue)
        let g = lib.grades[k]
        return VStack(alignment: .leading, spacing: 12) {
            Text(p.text)
                .font(.nx(.callout))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 3) }
            if !p.types.isEmpty { Text("Text types offered: " + p.types.joined(separator: ", ")).font(.nx(.caption)).foregroundStyle(.secondary) }
            if size != .regular {
                Button { SpanishKeyboard.hide(); guideOpen = true } label: {
                    Label(lib.guide(workstreamId, prompt: p).map { "Guide: " + $0.title } ?? "Text type guide", systemImage: "text.book.closed")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("spanish-guide-open")
            }
            // the tutor's box: each paragraph is read by the checker after a pause and its mistakes are underlined as he writes
            // (Live corrections), the laptop's SpanishBox; Return is a new line here, not send
            SpanishTextBox(text: text, placeholder: "Write your answer here", wsId: workstreamId, identifier: "spanish-piece", onSubmit: {},
                           maxLines: size == .regular ? 15 : 10, returnSends: false, fixed: true)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty { Text("Write your answer here").foregroundStyle(.tertiary).padding(.horizontal, 11).padding(.vertical, 8).allowsHitTesting(false).accessibilityHidden(true) }
                }
            HStack(spacing: 4) {
                Text("\(c.counted) words").bold()
                Text("counted · \(c.paragraphs) \(c.paragraphs == 1 ? "paragraph" : "paragraphs") · " + (c.band == "short" ? "under 70" : c.band == "long" ? "over 150" : "within 70–150"))
            }
            .font(.nx(.callout))
            .foregroundStyle(c.band == "ok" ? Color.primary : Theme.soon)
            .accessibilityIdentifier("spanish-count")
            if !c.skipped.isEmpty {
                Text("Not counted: " + c.skipped.map { "\($0.why) “\($0.line)”" }.joined(separator: ", ")).font(.nx(.caption)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button { SpanishKeyboard.hide(); SpanishGradeRun.mark(store, workstreamId, p) } label: {
                    if g?.busy == true { HStack { ProgressView(); Text("Marking…") } } else { Text("Mark it (IB Paper 1)") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(g?.busy == true || text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("spanish-mark")
                ClaudeModeChip(small: true)
            }
            Text("Marked by \(SpanishModel.label(SpanishModel.current)) with the official criteria and the examiners' rules\(lib.data(workstreamId).samples.isEmpty ? "" : " and your teacher's marked pieces").")
                .font(.nx(.caption)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func marks(_ p: SpanishGrade.Prompt) -> some View {
        let k = SpanishGradeRun.key(workstreamId, p.id)
        let mine = lib.data(workstreamId).pieces.filter { $0.prompt == p.id }
        VStack(alignment: .leading, spacing: 14) {
            if let g = lib.grades[k] {
                if !g.error.isEmpty { Label(g.error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.late).font(.nx(.callout)) }
                if let x = g.grade { SpanishGradeView(grade: x, path: g.path, text: g.text) }
            } else if size == .regular {
                Text("The marks show here: each criterion's mark, what was met and missed, the evidence from your piece and what to do next.")
                    .font(.nx(.callout)).foregroundStyle(.secondary)
            }
            if !mine.isEmpty {
                Text("Your pieces").font(.nx(.headline))
                ForEach(mine, id: \.path) { x in
                    SpanishFileLink(title: "\(x.written)\(x.total.map { " · \($0)/15" } ?? "") · \(x.words) words", path: x.path)
                }
            }
        }
    }
}

/// A file of the Spanish folder, shown read-only when tapped.
struct SpanishFileLink: View {
    let title: String
    let path: String
    @Environment(\.spanish) private var actions
    var body: some View {
        Button { actions.showFile(path, (path as NSString).lastPathComponent) } label: { Label(title, systemImage: "doc.text") }
            .font(.nx(.callout))
    }
}

/// The marks: the total, each criterion (met, missed, evidence, next), the examiner rules applied, the mistakes.
struct SpanishGradeView: View {
    let grade: SpanishGrade.Grade
    var path = ""
    /// the piece as marked, shown with its mistakes underlined
    var text = ""

    var body: some View {
        let x = grade
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(x.total)/15").font(.nx(.largeTitle, .bold)).accessibilityIdentifier("spanish-grade-total")
                VStack(alignment: .leading) {
                    Text("A \(x.A.mark)/6 · B \(x.B.mark)/6 · C \(x.C.mark)/3").font(.nx(.callout, .medium))
                    if !x.textType.isEmpty { Text("read as \(x.textType)").font(.nx(.caption)).foregroundStyle(.secondary) }
                }
            }
            if !x.overall.isEmpty { Text(x.overall).font(.nx(.callout)) }
            ForEach(SpanishGrade.criteria, id: \.key) { c in
                let k = x.mark(c.key)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(k.met, id: \.self) { m in Label(m, systemImage: "checkmark").foregroundStyle(Theme.accent) }
                        ForEach(k.missed, id: \.self) { m in Label(m, systemImage: "xmark").foregroundStyle(Theme.late) }
                        if !k.evidence.isEmpty { Text(k.evidence.map { "“\($0)”" }.joined(separator: "  ")).italic().foregroundStyle(.secondary) }
                        if !k.next.isEmpty { (Text("Next: ").bold() + Text(k.next.joined(separator: " "))) }
                    }
                    .font(.nx(.callout))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                } label: {
                    HStack { Text("\(c.key) \(c.name)").bold(); Spacer(); Text("\(k.mark)/\(c.max)").monospacedDigit() }
                }
            }
            if !text.isEmpty {
                Text("Your piece, its mistakes underlined").font(.nx(.caption, .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
                SpanishMarkedPiece(text: text, mistakes: x.mistakes)
            }
            if !x.applied.isEmpty { (Text("Examiner rules applied: ").bold() + Text(x.applied.joined(separator: " "))).font(.nx(.footnote)) }
            if !x.mistakes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(x.mistakes.enumerated()), id: \.offset) { _, m in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(m.wrong).strikethrough() + Text(" → ") + Text(m.right).bold()
                            Text(Spanish.skillName(m.skill)).font(.nx(.caption)).foregroundStyle(.secondary)
                        }
                        .font(.nx(.callout))
                    }
                }
            }
            if !path.isEmpty { SpanishFileLink(title: "Saved as \((path as NSString).lastPathComponent)", path: path) }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// The tutor's and the marking's model: Sonnet or Opus (the checker always uses Haiku).
struct SpanishModelMenu: View {
    @State private var model = SpanishModel.current
    var onChange: (String) -> Void = { _ in }
    var body: some View {
        Menu {
            Picker("Model", selection: Binding(get: { model }, set: { model = $0; SpanishModel.current = $0; onChange($0) })) {
                ForEach(SpanishModel.all, id: \.id) { m in Text(m.label).tag(m.id) }
            }
        } label: {
            Label(SpanishModel.label(model), systemImage: "cpu")
        }
        .accessibilityLabel("Model: \(SpanishModel.label(model))")
    }
}
