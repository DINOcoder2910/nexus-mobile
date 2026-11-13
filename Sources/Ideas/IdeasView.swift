import SwiftUI
import NexusCore

/// The Ideas screen (the sidebar's Ideas row; on the iPhone in More): add an idea (type or dictate), Claude sorts the new ones into
/// topics, and on each idea Claude or Me. The laptop shows the same file on its Customize screen (nexus docs/guide.md "Ideas").
struct IdeasView: View {
    @Environment(NexusStore.self) private var store
    @State private var model = IdeasModel()
    @State private var draft = ""
    @State private var renaming: Idea?
    @State private var newTitle = ""
    @FocusState private var adding: Bool

    var body: some View {
        let g = Ideas.group(model.items)
        List {
            Section {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("An idea: an app, a project, something for your life…", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($adding)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .accessibilityIdentifier("ideas.input")
                    Button("Add", action: add)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.error != nil)
                        .accessibilityIdentifier("ideas.add")
                }
            } header: {
                Text(Ideas.countLine(model.items)).accessibilityIdentifier("ideas.count")
            } footer: {
                Text("Dump anything here: app ideas, projects, life stuff. Claude sorts new ones into topics a batch at a time and tidies the wording; what you wrote is always kept. On each idea pick Claude or Me. The same list is on the laptop (Customize › Ideas).")
            }
            Section {
                HStack(spacing: 10) {
                    if model.sorting { ProgressView().controlSize(.small) }
                    Text(model.statusLine).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Button { model.sort() } label: { Label("Sort now", systemImage: "sparkles") }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(model.sorting || g.waiting.isEmpty || model.error != nil)
                    ClaudeModeChip(small: true)
                }
                if let e = model.error { Text(e).font(.callout).foregroundStyle(Theme.late) }
            }
            if !g.waiting.isEmpty {
                Section { ForEach(g.waiting) { x in row(x, repeats: []) } } header: { Text("New · \(g.waiting.count)").foregroundStyle(Theme.accent) }
            }
            ForEach(g.topics) { t in
                Section("\(t.name) · \(t.rows.count)") { ForEach(t.rows) { r in row(r.idea, repeats: r.repeats) } }
            }
            if !g.done.isEmpty {
                Section("Done · \(g.done.count)") { ForEach(g.done) { r in row(r.idea, repeats: r.repeats) } }
            }
            if model.loaded && g.waiting.isEmpty && g.topics.isEmpty {
                Text(model.items.isEmpty ? "Nothing yet. Write down the first idea above." : "Nothing open.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .textCase(nil)
        .navigationTitle("Ideas")
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-NexusTestDark") ? .dark : nil)
        .task {
            model.attach(store)
            model.autoSort()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.reloadIfChanged()
            }
        }
        .onChange(of: store.toast?.id) { _, _ in model.reloadIfChanged() }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { if let r = renaming { model.rename(r, newTitle) }; renaming = nil }
        }
    }

    private func add() { if model.add(draft) { draft = "" } }

    @ViewBuilder
    private func row(_ x: Idea, repeats: [Idea]) -> some View {
        let done = x.done != nil
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Button { model.tick(x) } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(done ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "Not done" : "Done")
                VStack(alignment: .leading, spacing: 3) {
                    Text(x.shownTitle).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
                    if let n = x.note { Text(n).font(.subheadline).foregroundStyle(.secondary) }
                    if x.originalShown { Text("You wrote: “\(x.text)”").font(.footnote).italic().foregroundStyle(.secondary) }
                    let facts = factsOf(x)
                    if !facts.isEmpty { Text(facts).font(.caption).foregroundStyle(x.who == "claude" ? Theme.claude : .secondary) }
                    ForEach(repeats) { r in
                        HStack(spacing: 6) {
                            Text("Also: “\(r.text)”").font(.footnote).italic().foregroundStyle(.secondary)
                            Button("Not the same") { model.unmerge(r) }.font(.footnote).buttonStyle(.borderless)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !done { whoButtons(x) }
            }
            if let reply = x.reply {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude").font(.caption.weight(.semibold)).foregroundStyle(Theme.claude)
                    Text(reply).font(.subheadline).textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.claudeTint, in: RoundedRectangle(cornerRadius: 10))
                .padding(.leading, 36)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) { Button("Remove", role: .destructive) { model.remove(x) } }
        .swipeActions(edge: .leading) { Button(done ? "Not done" : "Done") { model.tick(x) }.tint(Theme.accent) }
        .contextMenu {
            Button { newTitle = x.shownTitle; renaming = x } label: { Label("Rename…", systemImage: "pencil") }
            Button { model.tick(x) } label: { Label(done ? "Not done" : "Done", systemImage: "checkmark.circle") }
            Button(role: .destructive) { model.remove(x) } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityIdentifier("idea." + x.id)
    }

    private func factsOf(_ x: Idea) -> String {
        var f: [String] = []
        if x.who == "claude" {
            if model.working.contains(x.id) { f.append("Claude is working on it…") }
            else if let s = x.sent { f.append(Ideas.goesToDoor(x) ? "Sent to the change door \(s)" : "Claude worked on it \(s)") }
            else { f.append(Ideas.goesToDoor(x) ? "For Claude: send it from the laptop" : "For Claude") }
        } else if x.who == "me" { f.append("Yours") }
        if let k = x.kind, let l = Ideas.kindLabel[k] { f.append(l) }
        if let from = x.from, from != Device.name { f.append("from \(from)") }
        return f.joined(separator: " · ")
    }

    private func whoButtons(_ x: Idea) -> some View {
        HStack(spacing: 2) {
            pick("Claude", on: x.who == "claude", tint: Theme.claude) { model.claude(x) }
            pick("Me", on: x.who == "me", tint: .primary) { model.me(x) }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .disabled(model.working.contains(x.id) || model.error != nil)
    }

    private func pick(_ label: String, on: Bool, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.footnote.weight(.semibold))
                .padding(.horizontal, 10).frame(height: 26)
                .foregroundStyle(on ? tint : .secondary)
                .background(on ? Color(uiColor: .systemBackground) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
