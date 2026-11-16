import SwiftUI
import NexusCore

/// History: every check, newest at the bottom; tick checks and Move them to a tutor chat (nexus app/spanishview.js historyPanel).
struct SpanishHistoryList: View {
    let workstreamId: String
    /// Opens a tutor chat with the picked checks.
    var onMove: ([SpanishCheck.Entry]) -> Void
    /// The iPad shows it inside the checker; the iPhone as its own page.
    var inline = false
    @State private var picked: Set<String> = []

    var body: some View {
        let all = SpanishLibrary.shared.data(workstreamId).entries
        let list = Array(all.suffix(300))
        VStack(alignment: .leading, spacing: 8) {
            if inline { bar(all.count, list.count) }
            if list.isEmpty {
                Text("Nothing checked yet.").foregroundStyle(.secondary).font(.callout)
            }
            ScrollViewReader { proxy in
                List {
                    ForEach(list) { e in row(e) }
                    if !inline { Text("Tick the checks to talk through with the tutor.").font(.caption).foregroundStyle(.secondary).listRowSeparator(.hidden) }
                }
                .listStyle(.plain)
                .onAppear { if let last = list.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .frame(minHeight: inline ? 280 : nil, maxHeight: inline ? 380 : .infinity)
        }
        .navigationTitle(inline ? "" : "History")
        .toolbar {
            if !inline {
                ToolbarItem(placement: .primaryAction) { moveButton }
                if !picked.isEmpty { ToolbarItem(placement: .cancellationAction) { Button("Clear") { picked = [] } } }
            }
        }
    }

    private func bar(_ total: Int, _ shown: Int) -> some View {
        HStack {
            Text("History").font(.headline)
            Text(total > shown ? "the last \(shown) of \(total)" : "\(total) \(total == 1 ? "check" : "checks")").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if !picked.isEmpty { Button("Clear") { picked = [] }.controlSize(.small) }
            moveButton.buttonStyle(.borderedProminent).controlSize(.small)
        }
    }

    private var moveButton: some View {
        Button {
            let entries = SpanishLibrary.shared.data(workstreamId).entries.filter { picked.contains($0.at) }
            picked = []
            onMove(entries)
        } label: {
            Label(picked.isEmpty ? "Move to chat" : "Move \(picked.count) to chat", systemImage: "paperplane")
        }
        .disabled(picked.isEmpty)
        .accessibilityIdentifier("spanish-move")
    }

    private func row(_ e: SpanishCheck.Entry) -> some View {
        let on = picked.contains(e.at)
        let marks = SpanishCheck.merge(e.text, [], SpanishCheck.AI(corrected: e.fixed, mistakes: e.mistakes.map { .init(wrong: $0.wrong, right: $0.right, skill: $0.skill, why: $0.why) }, good: [], structures: [], words: []))
        return Button {
            if on { picked.remove(e.at) } else { picked.insert(e.at) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? Theme.accent : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    SpanishSentence(text: e.text, marks: marks, font: .callout).allowsHitTesting(false)
                    if !e.mistakes.isEmpty && e.fixed != e.text {
                        (Text("Fixed  ").foregroundStyle(.secondary) + Text(e.fixed)).font(.footnote)
                    } else {
                        Label("No mistakes", systemImage: "checkmark").font(.footnote).foregroundStyle(Theme.accent)
                    }
                    if !e.question.isEmpty { Text("Answering: " + e.question).font(.caption).foregroundStyle(.secondary) }
                    Text(Self.when(e.at) + (e.source == "chat" ? " · tutor" : e.source == "board" ? " · board" : "")).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(e.id)
        .accessibilityLabel("\(on ? "Picked" : "Pick"): \(e.text)")
    }

    static func when(_ at: String) -> String {
        let day = String(at.prefix(10))
        let time = at.count >= 16 ? String(at.dropFirst(11).prefix(5)) : ""
        return (day == Days.today() ? "today" : day) + " " + time
    }
}

/// Skills: the course checklist with the numbers from the log (nexus app/spanishview.js skillsSection). A skill's status is changed here
/// (it is one line of skills.yaml), its notes open read-only, and Practise / Teach me opens a tutor chat on it.
struct SpanishSkillsList: View {
    let workstreamId: String
    var onPractise: (String) -> Void
    @Environment(NexusStore.self) private var store
    var lib: SpanishLibrary { .shared }

    static let statusLabel = ["taught": "taught", "reteach": "teach again", "not-yet": "not yet"]

    var body: some View {
        let d = lib.data(workstreamId)
        ForEach(Spanish.groups, id: \.id) { g in
            Section {
                ForEach(Spanish.skills.filter { $0.group == g.id }) { s in row(s, d) }
            } header: {
                Text(g.title).textCase(nil)
            }
        }
    }

    private func row(_ s: Spanish.Skill, _ d: SpanishLibrary.Data) -> some View {
        let st = d.stat(s.id)
        let status = d.status[s.id] ?? "taught"
        let note = (lib.workstream(workstreamId)?.folder ?? "") + "/" + Spanish.P.note(s.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).font(.callout.weight(.medium))
                Spacer()
                Menu {
                    Picker("Course status", selection: Binding(get: { status }, set: { lib.setStatus(store, workstreamId, skill: s.id, status: $0) })) {
                        Text("Taught").tag("taught")
                        Text("Teach again from scratch").tag("reteach")
                        Text("Not taught yet").tag("not-yet")
                    }
                } label: {
                    Chip(text: Self.statusLabel[status] ?? status, icon: nil, color: status == "taught" ? .secondary : status == "reteach" ? Theme.soon : Theme.claude)
                }
                .accessibilityLabel("\(s.name): \(Spanish.statusWords[status] ?? status). Change")
            }
            HStack(spacing: 8) {
                Text(st.map { "\($0.accuracy)% · \($0.tries) \($0.tries == 1 ? "try" : "tries") · \(SpanishCheck.statWords[$0.status] ?? $0.status)" } ?? "not practised yet")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(Theme.soon).frame(width: geo.size.width * CGFloat(st?.due ?? 0))
                    }
                }
                .frame(width: 60, height: 5)
                .accessibilityLabel("Needs practice: \(Int(((st?.due ?? 0) * 100).rounded()))%")
            }
            HStack(spacing: 14) {
                if d.noteFiles.contains(note) { SpanishFileLink(title: "Notes", path: note) }
                if status != "not-yet" {
                    Button(status == "reteach" ? "Teach me" : "Practise") {
                        onPractise(status == "reteach" ? "Teach me \(s.name.lowercased()) (\(s.id)) from scratch." : "Let's practise \(s.name.lowercased()) (\(s.id)).")
                    }
                    .font(.callout)
                }
            }
            .buttonStyle(.borderless)
            Text(s.rule).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("spanish-skill-\(s.id)")
    }
}
