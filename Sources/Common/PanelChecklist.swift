import SwiftUI
import NexusCore

/// The task panel's subtasks as the laptop's checklist (desktop `Subtasks.tsx`): every subtask under the task, indented by how deep
/// it sits, each line typed into and read the way capture reads one ("q1-5 by thu 30m" is due Thursday, half an hour). With a
/// keyboard: Return keeps the line and goes to the add line, Backspace on an empty line takes it out, Tab and Shift-Tab nest it
/// under the one above or bring it back out, Option-Up / Option-Down move it. By touch, the ⋯ at a line's end (or holding it) has
/// the same moves. Every move is one Undo.
struct PanelChecklist: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    @FocusState private var focus: String?
    @State private var draft = ""
    @State private var addText = ""
    private static let add = "+add"

    var body: some View {
        let s = store.snapshot
        let rows = TaskTree.rows(s.children(of: task), in: s, folded: [], keep: { _ in true })
        let editable = store.canEdit(task)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { r in
                line(r, editable: editable)
                if focus == r.id, let chips = chips(draft), draft != r.task.text {
                    Text(chips).font(.nx(.caption)).foregroundStyle(Theme.accent)
                        .padding(.leading, CGFloat(r.level) * 22 + 30).padding(.bottom, 4)
                }
            }
            if editable { addLine }
        }
        .animation(Kit.snap, value: rows.map { "\($0.id)/\($0.level)" })
        .onChange(of: focus) { old, new in
            if let old, old != Self.add, let t = store.task(old) { commit(t, draft) }
            if let new, new != Self.add, let t = store.task(new) { draft = t.text }
        }
    }

    // MARK: a line

    private func line(_ r: TaskTree.Row, editable: Bool) -> some View {
        let t = r.task
        return HStack(spacing: 8) {
            TickRing(task: t).scaleEffect(0.8).frame(width: 18, height: 18)
            if editable && t.hasId {
                TextField("Subtask", text: Binding(get: { focus == t.id ? draft : t.text }, set: { draft = $0 }), axis: .vertical)
                    .font(.nx(.subheadline)).foregroundStyle(t.done ? Kit.faint : Kit.ink).strikethrough(t.done, color: Kit.faint)
                    .lineLimit(1...3)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: t.id)
                    .onSubmit { commit(t, draft); focus = Self.add }
                    .onKeyPress(.tab, phases: .down) { press in
                        commit(t, draft)
                        if press.modifiers.contains(.shift) { store.unnest(t) } else { store.nest(t) }
                        return .handled
                    }
                    .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
                        guard press.modifiers.contains(.option) else { return .ignored }
                        commit(t, draft)
                        store.shift(t, by: press.key == .upArrow ? -1 : 1)
                        return .handled
                    }
                    .onKeyPress(.delete, phases: .down) { _ in
                        guard draft.isEmpty else { return .ignored }
                        focus = nil
                        store.delete(t)
                        return .handled
                    }
                    .accessibilityIdentifier("check-line")
            } else {
                Text(t.text).font(.nx(.subheadline)).foregroundStyle(t.done ? Kit.faint : Kit.ink).strikethrough(t.done, color: Kit.faint).lineLimit(3)
            }
            Spacer(minLength: 4)
            if let d = t.due, !t.done {
                let w = TimeWords.due(d, today: store.today)
                Text(w.text).font(.nx(.caption)).foregroundStyle(w.late ? Theme.late : Kit.faint)
            }
            if let e = t.est, !t.done { Text(e).font(.nx(.caption)).foregroundStyle(Kit.faint) }
            if editable && t.hasId {
                Menu { moves(t, level: r.level) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Kit.faint).frame(width: 28, height: 26)
                }
                .accessibilityLabel("Subtask options")
                .accessibilityIdentifier("check-menu")
            }
        }
        .padding(.leading, CGFloat(r.level) * 22)
        .padding(.vertical, 5)
        .contextMenu { if editable && t.hasId { moves(t, level: r.level) } }
    }

    /// Open, the four moves (each only when it can happen), Delete.
    @ViewBuilder
    private func moves(_ t: NexusTask, level: Int) -> some View {
        let sib = store.editor.siblings(t, in: store.snapshot)
        let i = sib.firstIndex { $0.id == t.id } ?? 0
        Button { store.open(t) } label: { Label("Open", systemImage: "arrow.up.right.square") }
        Divider()
        if i > 0 { Button { store.nest(t) } label: { Label("Under the one above", systemImage: "arrow.right.to.line") } }
        if level > 0 { Button { store.unnest(t) } label: { Label("Bring out", systemImage: "arrow.left.to.line") } }
        if i > 0 { Button { store.shift(t, by: -1) } label: { Label("Move up", systemImage: "arrow.up") } }
        if i + 1 < sib.count { Button { store.shift(t, by: 1) } label: { Label("Move down", systemImage: "arrow.down") } }
        Divider()
        Button(role: .destructive) { store.delete(t) } label: { Label("Delete", systemImage: "trash") }
    }

    // MARK: the add line

    private var addLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Kit.faint).frame(width: 18)
                TextField("Add a subtask", text: $addText)
                    .font(.nx(.subheadline)).focused($focus, equals: Self.add).autocorrectionDisabled().submitLabel(.next)
                    .onSubmit(addIt)
                    .accessibilityIdentifier("subtask-add")
            }
            .padding(.vertical, 5)
            if focus == Self.add, let c = chips(addText) {
                Text(c).font(.nx(.caption)).foregroundStyle(Theme.accent).padding(.leading, 26)
            }
        }
    }

    private func addIt() {
        // Return on an empty line ends adding (the keyboard goes)
        if addText.trimmingCharacters(in: .whitespaces).isEmpty { focus = nil; return }
        let p = CaptureParse.parseLine(addText, in: store.snapshot, today: store.today, commands: false)
        guard p.kind == .task, p.ok else { return }
        _ = store.add(title: p.title, workstream: task.workstream, parent: task, due: p.facts.due, plan: p.facts.planEntries, key: p.facts.key,
                      est: p.facts.est, extras: p.facts)
        addText = ""
        focus = Self.add
    }

    // MARK: reading a line

    /// What a line will set, as the capture preview says it (nil when it sets nothing beyond its words).
    private func chips(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let p = CaptureParse.parseLine(text, in: store.snapshot, today: store.today, commands: false)
        guard p.kind == .task, p.ok else { return nil }
        let c = CaptureParse.chips(p, landing: nil, today: store.today).map(\.text)
        return c.isEmpty ? nil : c.joined(separator: " · ")
    }

    /// A changed line: its words become the title, and what it read (a deadline, an estimate, ★) is set too.
    private func commit(_ t: NexusTask, _ text: String) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, typed != t.text, store.task(t.id) != nil else { return }
        let p = CaptureParse.parseLine(typed, in: store.snapshot, today: store.today, commands: false)
        let title = p.kind == .task && p.ok ? p.title : typed
        if title != t.title { store.setTitle(t, title) }
        guard p.kind == .task, p.ok, let now = store.task(t.id) else { return }
        if let d = p.facts.due, d != now.due { store.setDue(now, d) }
        if let e = p.facts.est, e != now.est, let n = store.task(t.id) { store.setEstimate(n, e) }
        if p.facts.key, !now.key, let n = store.task(t.id) { store.setKey(n, true) }
    }
}
