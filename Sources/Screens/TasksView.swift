import SwiftUI
import NexusCore

/// Tasks, as the new laptop app has it (switch-over step 4b, Nov 21 2026; nexus `desktop/src/screens/Tasks.tsx`): every task, one lens
/// at a time (All, Deadlines, Waiting on, No date, Slipped, Done, Someday), as cards or a list, narrowed by subject, tag and words.
/// A card opens the task; its circle ticks it; its subtasks open in place (the count, or the checklist button to add one). The lenses
/// are NexusCore TaskLenses, the same as the laptop's. The view, the grouping and the lens are remembered.
struct TasksView: View {
    @Environment(NexusStore.self) private var store
    @State private var lens: Planning.Lens
    @AppStorage("tasksView") private var view = "cards"
    @AppStorage("tasksGroup") private var group = "none"
    @State private var find = ""
    @State private var subjects: Set<String> = []
    @State private var tags: Set<String> = []
    /// Cards whose subtasks are open.
    @State private var open: Set<String> = []
    /// The card whose add-a-subtask line has the focus.
    @State private var adding: String?
    @FocusState private var findFocused: Bool

    init(lens: Planning.Lens = .all) {
        _lens = State(initialValue: lens)
    }

    static func kicker(_ l: Planning.Lens) -> String {
        switch l {
        case .all: return "Open tasks"
        case .deadlines: return "Deadlines, key ones first"
        case .waiting: return "Waiting on someone, the longest wait first"
        case .noDate: return "No deadline, not waiting, not repeating"
        case .slipped: return "Past their deadline with no day planned"
        case .done: return "Ticked in the last 14 days, newest first"
        case .someday: return "Parked for someday"
        }
    }

    static func empty(_ l: Planning.Lens) -> String {
        switch l {
        case .all: return "No open tasks. Add one with New task."
        case .deadlines: return "No open task has a deadline. Add one with \"by fri\", or in a task's panel."
        case .waiting: return "Not waiting on anyone. Set Waiting on in a task's panel when the next move is someone else's."
        case .noDate: return "Every open task has a date or a reason."
        case .slipped: return "Nothing slipped."
        case .done: return "Nothing ticked in the last 14 days."
        case .someday: return "Nothing parked. Switch on Someday in a task's panel to park it here."
        }
    }

    private var wsKey: (NexusTask) -> String { { $0.workstream ?? "inbox" } }

    var body: some View {
        let p = store.planning
        let pool = TaskLenses.rows(p, lens)
        let words = find.lowercased().split(separator: " ").map(String.init)
        let rows = pool.filter { t in
            (subjects.isEmpty || subjects.contains(wsKey(t))) && (tags.isEmpty || t.tags.contains { tags.contains($0) })
                && words.allSatisfy { w in
                    [t.text, store.workstreamName(t), t.tags.joined(separator: " "), store.task(t.parent)?.text ?? "", t.waitingOn ?? ""]
                        .joined(separator: " ").lowercased().contains(w)
                }
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(p)
                lensTabs(p)
                toolbar(pool.count, rows.count)
                chips(pool)
                if rows.isEmpty {
                    Text(pool.isEmpty ? Self.empty(lens) : "Nothing matches. Clear the filters to see every task here.")
                        .font(.nx(.callout)).foregroundStyle(Kit.faint).padding(.vertical, 24)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("tasks-empty")
                } else {
                    ForEach(groups(rows), id: \.key) { g in
                        VStack(alignment: .leading, spacing: 10) {
                            if !g.name.isEmpty {
                                HStack(spacing: 7) {
                                    SubjectDot(color: store.color(workstream: g.workstream))
                                    Text(g.name).font(.nx(.subheadline, .semibold)).foregroundStyle(Kit.ink)
                                    Text("\(g.rows.count)").font(.nx(.subheadline)).foregroundStyle(Kit.faint)
                                }
                                .padding(.top, 8)
                            }
                            items(g.rows, p)
                        }
                    }
                }
                Button { store.capture = .init(workstream: subjects.count == 1 && !subjects.contains("inbox") ? subjects.first : nil, parent: nil, plan: nil) } label: {
                    Label("Add a task", systemImage: "plus").font(.nx(.body)).foregroundStyle(Kit.muted)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tasks-add")
            }
            .padding(.horizontal, Device.isPhone ? 16 : 32)
            .padding(.top, 8).padding(.bottom, 90)
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
        }
        .background(Kit.page)
        .scrollDismissesKeyboard(.interactively)
        .task(id: ShortcutCenter.shared.searchPending) {
            // Search tasks (a key, Settings › Shortcuts): into Find once the screen is up
            guard ShortcutCenter.shared.searchPending else { return }
            ShortcutCenter.shared.searchPending = false
            try? await Task.sleep(for: .milliseconds(250))
            findFocused = true
        }
        .refreshable { store.reload() }
        .navigationTitle(lens == .someday ? "Someday" : "Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("tasks")
    }

    // MARK: the header

    private func header(_ p: Planning) -> some View {
        let all = TaskLenses.count(p, .all), dl = TaskLenses.count(p, .deadlines), sl = TaskLenses.count(p, .slipped), wt = TaskLenses.count(p, .waiting)
        return VStack(alignment: .leading, spacing: 4) {
            Text(Self.kicker(lens)).font(.nx(.subheadline)).foregroundStyle(Kit.muted)
            HStack(alignment: .firstTextBaseline) {
                Text("Tasks").font(.nx(size: Device.isPhone ? 30 : 36, .bold, display: true)).foregroundStyle(Kit.ink)
                Spacer()
                Button { store.capture = .init(workstream: subjects.count == 1 && !subjects.contains("inbox") ? subjects.first : nil, parent: nil, plan: nil) } label: {
                    Label("New task", systemImage: "plus")
                }
                .buttonStyle(.kitPrimary)
                .accessibilityIdentifier("new-task")
            }
            (Text("\(all) open task\(all == 1 ? "" : "s")").fontWeight(.semibold).foregroundColor(Kit.ink)
                + Text(", \(dl) with a deadline, \(sl) slipped, \(wt) waiting on someone."))
                .font(.nx(.body)).foregroundStyle(Kit.muted)
                .accessibilityIdentifier("tasks-sum")
        }
    }

    private func lensTabs(_ p: Planning) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(Planning.Lens.allCases) { l in
                        let on = l == lens
                        Button { withAnimation(Kit.snap) { lens = l } } label: {
                            HStack(spacing: 5) {
                                Text(l.rawValue).foregroundStyle(on ? Kit.ink : Kit.muted)
                                Text("\(TaskLenses.count(p, l))").foregroundStyle(Kit.faint)
                            }
                            .font(.nx(.body, on ? .medium : .regular))
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { if on { Rectangle().fill(Kit.ink).frame(height: 2) } }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .accessibilityIdentifier("lens-\(l.rawValue)")
                    }
                }
            }
            Rectangle().fill(Kit.line).frame(height: 1)
        }
    }

    private func toolbar(_ total: Int, _ shown: Int) -> some View {
        let seg = { (on: Bool, title: String, action: @escaping () -> Void) in
            Button(action: { withAnimation(Kit.snap) { action() } }) {
                Text(title).font(.nx(.subheadline, on ? .medium : .regular)).foregroundStyle(on ? Kit.ink : Kit.muted)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(on ? Kit.page : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(on ? 0.06 : 0), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
        }
        let segs = HStack(spacing: 10) {
            HStack(spacing: 0) {
                seg(view == "cards", "Cards") { view = "cards" }
                seg(view == "list", "List") { view = "list" }.accessibilityIdentifier("view-list")
            }
            .padding(3).background(Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack(spacing: 0) {
                seg(group == "none", lens == .someday ? "In order" : "Lens order") { group = "none" }
                seg(group == "subject", "By subject") { group = "subject" }.accessibilityIdentifier("group-subject")
            }
            .padding(3).background(Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        let findField = HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Kit.faint)
            TextField("Find…", text: $find).font(.nx(.subheadline)).focused($findFocused).autocorrectionDisabled()
                .accessibilityIdentifier("tasks-find")
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        let count = Text(shown == total ? "\(total) task\(total == 1 ? "" : "s")" : "\(shown) of \(total)")
            .font(.nx(.footnote)).foregroundStyle(Kit.faint).fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { segs; Spacer(minLength: 8); findField.frame(width: 240); count }
            VStack(alignment: .leading, spacing: 10) { segs; HStack(spacing: 10) { findField; count } }
        }
    }

    // MARK: the subject and tag chips

    /// The subjects in the lens (in the order they come, with any picked one that has none now), and the tags with their counts.
    private func chipCounts(_ pool: [NexusTask]) -> (order: [String], counts: [String: Int], tags: [String: Int]) {
        var counts: [String: Int] = [:], order: [String] = [], tagCounts: [String: Int] = [:]
        for t in pool {
            let k = wsKey(t)
            if counts[k] == nil { order.append(k) }
            counts[k, default: 0] += 1
            for g in Set(t.tags) { tagCounts[g, default: 0] += 1 }
        }
        for k in subjects.sorted() where counts[k] == nil { order.append(k); counts[k] = 0 }
        for g in tags where tagCounts[g] == nil { tagCounts[g] = 0 }
        return (order, counts, tagCounts)
    }

    @ViewBuilder
    private func chips(_ pool: [NexusTask]) -> some View {
        let c = chipCounts(pool)
        let order = c.order, counts = c.counts, tagCounts = c.tags
        if order.count > 1 || !subjects.isEmpty {
            FlowRow(spacing: 8) {
                ForEach(order, id: \.self) { k in
                    let on = subjects.contains(k)
                    let ws = k == "inbox" ? nil : k
                    chip(on: on, dot: store.color(workstream: ws), title: store.workstream(ws)?.name ?? "Inbox", count: counts[k] ?? 0) {
                        if on { subjects.remove(k) } else { subjects.insert(k) }
                    }
                }
                if !subjects.isEmpty { Button("Clear") { subjects = [] }.font(.nx(.footnote)).foregroundStyle(Kit.muted).buttonStyle(.plain).padding(.vertical, 6) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("subject-chips")
        }
        if !tagCounts.isEmpty {
            FlowRow(spacing: 8) {
                Text("Tags").font(.nx(.footnote)).foregroundStyle(Kit.faint).padding(.vertical, 6)
                ForEach(tagCounts.keys.sorted(), id: \.self) { t in
                    let on = tags.contains(t)
                    chip(on: on, dot: nil, title: "#" + t, count: tagCounts[t] ?? 0) { if on { tags.remove(t) } else { tags.insert(t) } }
                }
                if !tags.isEmpty { Button("Clear") { tags = [] }.font(.nx(.footnote)).foregroundStyle(Kit.muted).buttonStyle(.plain).padding(.vertical, 6) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tag-chips")
        }
    }

    private func chip(on: Bool, dot: Color?, title: String, count: Int, action: @escaping () -> Void) -> some View {
        Button { withAnimation(Kit.snap) { action() } } label: {
            HStack(spacing: 6) {
                if let dot { SubjectDot(color: dot, size: 6) }
                Text(title).foregroundStyle(Kit.ink)
                Text("\(count)").foregroundStyle(Kit.faint)
            }
            .font(.nx(.footnote))
            .padding(.horizontal, 10).frame(height: 28)
            .background(on ? (dot ?? Theme.accent).opacity(0.16) : Kit.rests, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? (dot ?? Theme.accent).opacity(0.6) : .clear))
        }
        .buttonStyle(.plain)
    }

    // MARK: the cards and the list

    private struct TaskGroup { var key: String; var name: String; var workstream: String?; var rows: [NexusTask] }

    private func groups(_ rows: [NexusTask]) -> [TaskGroup] {
        guard group == "subject" else { return [TaskGroup(key: "all", name: "", workstream: nil, rows: rows)] }
        var out: [TaskGroup] = [], at: [String: Int] = [:]
        for t in rows {
            let k = wsKey(t)
            if let i = at[k] { out[i].rows.append(t) } else { at[k] = out.count; out.append(TaskGroup(key: k, name: store.workstreamName(t), workstream: t.workstream, rows: [t])) }
        }
        return out
    }

    @ViewBuilder
    private func items(_ rows: [NexusTask], _ p: Planning) -> some View {
        if view == "list" {
            VStack(spacing: 0) {
                ForEach(rows) { t in
                    TaskListRow(task: t, lens: lens, open: $open, adding: $adding)
                    Rectangle().fill(Kit.line).frame(height: 1)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("task-items")
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Device.isPhone ? 280 : 300), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(rows) { t in TaskCard(task: t, lens: lens, open: $open, adding: $adding) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("task-items")
        }
    }
}

// MARK: what a card says

/// What a card or row says under its title: the deadline (or when it was done), the next planned day, the estimate, who it waits
/// on, its repeat and its tags.
struct TaskFacts: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let lens: Planning.Lens
    var subject = true

    var body: some View {
        FlowRow(spacing: 10) {
            if subject {
                HStack(spacing: 5) { SubjectDot(color: store.color(task), size: 6); Text(store.workstreamName(task)).foregroundStyle(Kit.muted) }
            }
            ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                HStack(spacing: 3) {
                    if let i = f.icon { Image(systemName: i).font(.system(size: 10)) }
                    Text(f.text)
                }
                .foregroundStyle(f.color)
            }
        }
        .font(.nx(.footnote))
    }

    private var facts: [(text: String, color: Color, icon: String?)] {
        let today = store.today
        var out: [(String, Color, String?)] = []
        if lens == .done, let d = task.doneOn.map({ String($0.prefix(10)) }) {
            out.append(("done " + (d == today ? "today" : Days.label(d)), Kit.faint, nil))
        } else if let d = task.due {
            let w = TimeWords.due(d, today: today)
            out.append((w.text, w.late ? Theme.late : Days.between(today, d) <= 2 ? Theme.soon : Kit.muted, nil))
        }
        if lens != .done, let next = task.plannedDays.filter({ Days.isIso($0) && $0 >= today }).min() {
            out.append(("planned " + TimeWords.dayName(next, today: today), Theme.accent, nil))
        }
        let m = TodayPlan.minutes(task)
        if m > 0 { out.append((TimeWords.dur(m), Kit.muted, "clock")) }
        if let w = task.waitingOn {
            let since = task.waitingSince.map { " · \(max(0, Days.between($0, today)))d" } ?? ""
            out.append(("waiting on \(w)\(since)", Theme.planned, nil))
        }
        if let r = task.every { out.append((r.text.lowercased(), Kit.muted, "arrow.clockwise")) }
        for t in task.tags { out.append(("#" + t, Kit.faint, nil)) }
        return out.map { (text: $0.0, color: $0.1, icon: $0.2) }
    }
}

/// A card's title: "Parent › ", ★ and the title.
private func taskTitle(_ t: NexusTask, parent: NexusTask?, size: CGFloat) -> Text {
    (parent.map { Text($0.text + " › ").foregroundColor(Kit.faint) } ?? Text(""))
        + (t.key ? Text("★ ").foregroundColor(Theme.key) : Text(""))
        + Text(t.text).foregroundColor(Kit.ink).strikethrough(t.done, color: Kit.muted)
}

/// A task as a card: tick, title (its parent first when it is a subtask), the checklist button, its facts, and its subtasks' bar,
/// which opens them in place.
private struct TaskCard: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let lens: Planning.Lens
    @Binding var open: Set<String>
    @Binding var adding: String?

    var body: some View {
        let kids = store.snapshot.children(of: task)
        let done = kids.filter(\.done).count
        let shown = open.contains(task.id) || adding == task.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                TickRing(task: task)
                taskTitle(task, parent: store.task(task.parent), size: 16).font(.nx(size: 16, .medium)).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if store.canEdit(task) && lens != .done {
                    Button { withAnimation(Kit.snap) { open.insert(task.id); adding = task.id } } label: {
                        Image(systemName: "checklist").font(.system(size: 14)).foregroundStyle(Kit.faint).frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add a subtask")
                    .accessibilityIdentifier("card-addsub")
                }
            }
            TaskFacts(task: task, lens: lens).padding(.leading, 32)
            if !kids.isEmpty {
                Button { withAnimation(Kit.spring) { if open.contains(task.id) { open.remove(task.id); if adding == task.id { adding = nil } } else { open.insert(task.id) } } } label: {
                    HStack(spacing: 8) {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Kit.selected)
                                Capsule().fill(Theme.accent).frame(width: g.size.width * CGFloat(done) / CGFloat(max(kids.count, 1)))
                            }
                        }
                        .frame(height: 4)
                        HStack(spacing: 2) {
                            Text("\(done)/\(kids.count)")
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(shown ? 180 : 0))
                        }
                        .font(.nx(.caption)).foregroundStyle(Kit.faint)
                    }
                    .padding(.leading, 32).frame(height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(done) of \(kids.count) subtasks done")
                .accessibilityIdentifier("card-subcount")
            }
            if shown { SubtaskList(task: task, adding: $adding).padding(.leading, 28) }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(Kit.rests, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { store.open(task) }
        .contextMenu { TaskMenu(task: task, day: nil) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-card")
    }
}

/// A task as a list row: tick, title, facts, the subtasks' count, its subject.
private struct TaskListRow: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let lens: Planning.Lens
    @Binding var open: Set<String>
    @Binding var adding: String?

    var body: some View {
        let kids = store.snapshot.children(of: task)
        let shown = open.contains(task.id) || adding == task.id
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                TickRing(task: task)
                VStack(alignment: .leading, spacing: 3) {
                    taskTitle(task, parent: store.task(task.parent), size: 15).font(.nx(size: 15)).lineLimit(2)
                    HStack(spacing: 10) {
                        TaskFacts(task: task, lens: lens, subject: Device.isPhone)
                        if !kids.isEmpty {
                            Button { withAnimation(Kit.spring) { if open.contains(task.id) { open.remove(task.id) } else { open.insert(task.id) } } } label: {
                                HStack(spacing: 2) {
                                    Text("\(kids.filter(\.done).count)/\(kids.count)")
                                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).rotationEffect(.degrees(shown ? 180 : 0))
                                }
                                .font(.nx(.footnote)).foregroundStyle(Kit.faint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("row-subcount")
                        }
                    }
                }
                Spacer(minLength: 8)
                if !Device.isPhone {
                    HStack(spacing: 5) { SubjectDot(color: store.color(task), size: 6); Text(store.workstreamName(task)).lineLimit(1) }
                        .font(.nx(.footnote)).foregroundStyle(Kit.faint)
                }
            }
            if shown { SubtaskList(task: task, adding: $adding).padding(.leading, 32) }
        }
        .padding(.horizontal, 6).padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { store.open(task) }
        .contextMenu { TaskMenu(task: task, day: nil) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row")
    }
}

/// A task's subtasks in place: tick them, open one, and add one on the line below, read as capture reads a line ("q1-5 by thu 30m").
struct SubtaskList: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    @Binding var adding: String?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(store.snapshot.children(of: task)) { s in
                HStack(spacing: 8) {
                    TickRing(task: s).scaleEffect(0.8).frame(width: 18, height: 18)
                    Text(s.text).font(.nx(.subheadline)).foregroundStyle(s.done ? Kit.faint : Kit.ink).strikethrough(s.done, color: Kit.faint).lineLimit(2)
                    Spacer(minLength: 4)
                    if let d = s.due, !s.done {
                        let w = TimeWords.due(d, today: store.today)
                        Text(w.text).font(.nx(.caption)).foregroundStyle(w.late ? Theme.late : Kit.faint)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { store.open(s) }
            }
            if store.canEdit(task) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Kit.faint).frame(width: 18)
                    TextField("Add a subtask", text: $text)
                        .font(.nx(.subheadline)).focused($focused).autocorrectionDisabled().submitLabel(.next)
                        .onSubmit(add)
                        .accessibilityIdentifier("subtask-add")
                }
                .padding(.vertical, 4)
                if focused, let chips = preview, !chips.isEmpty {
                    Text(chips).font(.nx(.caption)).foregroundStyle(Theme.accent).padding(.leading, 26)
                }
            }
        }
        .onAppear { if adding == task.id { focused = true } }
        .onChange(of: focused) { if !focused && adding == task.id { adding = nil } }
    }

    /// What the line will set, said as the capture preview says it.
    private var preview: String? {
        let p = CaptureParse.parseLine(text, in: store.snapshot, today: store.today, commands: false)
        guard p.kind == .task, p.ok else { return nil }
        return CaptureParse.chips(p, landing: nil, today: store.today).map(\.text).joined(separator: " · ")
    }

    private func add() {
        let p = CaptureParse.parseLine(text, in: store.snapshot, today: store.today, commands: false)
        guard p.kind == .task, p.ok else { return }
        _ = store.add(title: p.title, workstream: task.workstream, parent: task, due: p.facts.due, plan: p.facts.planEntries, key: p.facts.key,
                      est: p.facts.est, extras: p.facts)
        text = ""
        focused = true
    }
}

// MARK: a task with its subtasks, as indented rows (shared with WorkstreamView)

enum TaskTree {
    /// One row of a tree: the task, how deep it sits under the row's root, and whether it has subtasks to fold.
    struct Row: Identifiable {
        var task: NexusTask
        var level: Int
        var hasKids: Bool
        var id: String { task.id }
    }

    /// The roots, each followed by the subtasks `keep` lets through (depth first, file order), skipping folded ones' subtasks.
    static func rows(_ roots: [NexusTask], in s: Snapshot, folded: Set<String>, keep: @escaping (NexusTask) -> Bool) -> [Row] {
        var out: [Row] = []
        func walk(_ t: NexusTask, _ level: Int) {
            let kids = s.children(of: t).filter(keep)
            out.append(Row(task: t, level: level, hasKids: !kids.isEmpty))
            if folded.contains(t.id) { return }
            for k in kids { walk(k, level + 1) }
        }
        for r in roots { walk(r, 0) }
        return out
    }
}

/// A tree row: indented by its level, with a chevron that folds its subtasks.
struct TaskTreeRow: View {
    let row: TaskTree.Row
    @Binding var folded: Set<String>
    var showWorkstream = false

    var body: some View {
        let isFolded = folded.contains(row.task.id)
        HStack(alignment: .top, spacing: 2) {
            if row.hasKids {
                Button {
                    // Adds the id when open, takes it out when folded.
                    withAnimation(.snappy) { folded.formSymmetricDifference([row.task.id]) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.nx(.caption, .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isFolded ? 0 : 90))
                        .frame(width: 22, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isFolded ? "Show subtasks" : "Hide subtasks")
            } else {
                Color.clear.frame(width: 22, height: 30)
            }
            // A root shows its crumb (a subtask whose parent is done); indented rows sit under their parent already.
            TaskRow(task: row.task, showWorkstream: showWorkstream, showCrumb: row.level == 0, compact: row.level > 0)
        }
        .padding(.leading, CGFloat(row.level) * 22)
    }
}
