import SwiftUI
import NexusCore

/// The one task row every screen uses: the tick ring in its workstream's colour, the title, and the facts that matter as chips.
/// Tap opens the task panel; long-press gives the menu; it can be dragged onto a Planner day.
struct TaskRow: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    /// The day the row is shown on (Today, a Planner day): its time shows, and the menu can take it off that day.
    var day: String? = nil
    var showWorkstream = true
    var showCrumb = true
    var compact = false

    var body: some View {
        let p = store.planning
        HStack(alignment: .top, spacing: 10) {
            TickRing(task: task)
            VStack(alignment: .leading, spacing: 3) {
                if showCrumb, let crumb = p.crumb(task) {
                    Text(crumb).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(task.text)
                    .font(compact ? .subheadline : .body)
                    .strikethrough(task.done, color: .secondary)
                    .foregroundStyle(task.done ? .secondary : .primary)
                    .lineLimit(compact ? 2 : 3)
                chips(p)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, compact ? 2 : 4)
        .contentShape(Rectangle())
        .onTapGesture { store.open(task) }
        .contextMenu { TaskMenu(task: task, day: day) }
        .draggable(task.id) {
            Text(task.text).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func chips(_ p: Planning) -> some View {
        let today = store.today
        let items = facts(p, today: today)
        if !items.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { ForEach(items.indices, id: \.self) { items[$0] } }
                HStack(spacing: 5) { ForEach(items.prefix(3).indices, id: \.self) { items[$0] } }
            }
        }
    }

    private func facts(_ p: Planning, today: String) -> [Chip] {
        var out: [Chip] = []
        if let day, let time = task.time(on: day) { out.append(Chip(text: time, icon: "clock", color: Theme.planned, strong: true)) }
        if task.key { out.append(Chip(text: "★", color: Theme.key, strong: true)) }
        if !task.done, let due = task.due {
            let n = Days.between(today, due)
            out.append(Chip(text: Days.relative(due, today: today), icon: "flag", color: n < 0 ? Theme.late : n <= 1 ? Theme.soon : .secondary, strong: n <= 0))
        }
        if let pr = p.progress(task) { out.append(Chip(text: "\(pr.done)/\(pr.total)", icon: "checklist")) }
        if let h = p.estimate(task) { out.append(Chip(text: hoursText(h), icon: "hourglass")) }
        if let w = task.waitingOn {
            let since = task.waitingSince.map { " · \(Days.between($0, today))d" } ?? ""
            out.append(Chip(text: "Waiting on \(w)\(since)", icon: "hourglass.bottomhalf.filled", color: Theme.soon))
        }
        if let r = task.every { out.append(Chip(text: r.text, icon: "repeat")) }
        if day == nil, !task.done, let next = task.plannedDays.filter({ $0 >= today }).min() {
            out.append(Chip(text: next == today ? "Today" : Days.relative(next, today: today), icon: "calendar", color: Theme.planned))
        }
        if showWorkstream { out.append(Chip(text: store.workstreamName(task), icon: "circle.fill", color: store.color(task))) }
        return out
    }
}

/// The ring: tap to tick (with its open subtasks) or untick.
struct TickRing: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask

    var body: some View {
        let color = store.color(task)
        Button {
            withAnimation(.snappy) { store.toggleDone(task) }
        } label: {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.8)
                if task.done {
                    Circle().fill(color)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 22, height: 22)
            .padding(.top, 1)
            .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .disabled(!store.canEdit(task))
        .accessibilityLabel(task.done ? "Mark not done" : "Mark done")
    }
}

/// Long-press menu of a task, the iPad's version of the laptop card's menu.
struct TaskMenu: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    var day: String?

    var body: some View {
        let today = store.today
        Button { store.open(task) } label: { Label("Open", systemImage: "arrow.up.right.square") }
        if store.canEdit(task) {
            Button { store.toggleDone(task) } label: { Label(task.done ? "Not done" : "Done", systemImage: task.done ? "circle" : "checkmark.circle") }
            Divider()
            if !task.plannedDays.contains(today) {
                Button { store.plan(task, on: today) } label: { Label("Plan for today", systemImage: "sun.max") }
            }
            if !task.plannedDays.contains(Days.add(today, 1)) {
                Button { store.plan(task, on: Days.add(today, 1)) } label: { Label("Plan for tomorrow", systemImage: "sunrise") }
            }
            if let day, task.plannedDays.contains(day) {
                Button { store.unplan(task, from: day) } label: { Label("Take off \(day == today ? "today" : Days.label(day))", systemImage: "calendar.badge.minus") }
            }
            Button { store.setKey(task, !task.key) } label: { Label(task.key ? "Not a key date" : "Key date ★", systemImage: task.key ? "star.slash" : "star") }
            Button { store.capture = .init(workstream: task.workstream, parent: task.id) } label: { Label("Add a subtask", systemImage: "plus") }
            Button { store.setSomeday(task, !task.ownSomeday) } label: { Label(task.ownSomeday ? "Back from Someday" : "Someday", systemImage: "moon.zzz") }
        }
    }
}

extension View {
    /// Swipe right: done. Swipe left: plan for today (or take it off `day`).
    func taskSwipes(_ task: NexusTask, store: NexusStore, day: String? = nil) -> some View {
        self
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if store.canEdit(task) {
                    Button { store.toggleDone(task) } label: { Label(task.done ? "Not done" : "Done", systemImage: "checkmark") }.tint(store.color(task))
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if store.canEdit(task) {
                    if let day, task.plannedDays.contains(day) {
                        Button { store.unplan(task, from: day) } label: { Label("Off", systemImage: "calendar.badge.minus") }.tint(.gray)
                    } else if !task.plannedDays.contains(store.today) {
                        Button { store.plan(task, on: store.today) } label: { Label("Today", systemImage: "sun.max") }.tint(Theme.planned)
                    }
                }
            }
    }
}
