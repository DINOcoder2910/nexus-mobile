import SwiftUI
import NexusCore

/// Place tasks, as on the laptop's Calendar: the open tasks not planned yet, grouped by when they are due, with a search. On the
/// iPad it is a drawer beside the grid and a task drags onto a time; on either device a tap asks for a day and a time.
struct PlaceTasksList: View {
    @Environment(NexusStore.self) private var store
    /// The day a tap starts from (the day the Calendar is on).
    let day: String
    var close: (() -> Void)?

    @State private var find = ""
    @State private var placing: NexusTask?

    private static let most = 60

    private var pool: [NexusTask] {
        store.planning.bank.filter { $0.waitingOn == nil && store.canEdit($0) }
    }

    struct DueGroup: Identifiable {
        let label: String
        let tasks: [NexusTask]
        var id: String { label }
    }

    private var groups: [DueGroup] {
        let q = find.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = pool.filter { q.isEmpty || $0.text.lowercased().contains(q) || store.workstreamName($0).lowercased().contains(q) }
            .sorted { ($0.due ?? "9999", $0.order) < ($1.due ?? "9999", $1.order) }
        let today = store.today, week = Days.add(today, 7)
        let cut = Array(shown.prefix(Self.most))
        let late = cut.filter { ($0.due ?? "9999") < today }
        let soon = cut.filter { $0.due.map { $0 >= today && $0 <= week } ?? false }
        let later = cut.filter { $0.due.map { $0 > week } ?? false }
        let none = cut.filter { $0.due == nil }
        let all: [DueGroup] = [DueGroup(label: "Overdue", tasks: late), DueGroup(label: "Due this week", tasks: soon),
                            DueGroup(label: "Due later", tasks: later), DueGroup(label: "No due date", tasks: none)]
        return all.filter { !$0.tasks.isEmpty }
    }

    var body: some View {
        let all = pool
        let g = groups
        List {
            Section {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a task", text: $find).autocorrectionDisabled()
                    if !find.isEmpty {
                        Button { find = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }
            } footer: {
                Text(Device.isPhone ? "Tap a task to give it a day and a time." : "Drag a task onto a time, or tap it to pick one.")
            }
            if all.isEmpty {
                Text("Nothing unplanned. Everything open is planned, waiting, repeating or done.").foregroundStyle(.secondary)
            } else if g.isEmpty {
                Text("No task matches.").foregroundStyle(.secondary)
            }
            ForEach(g) { group in
                Section {
                    ForEach(group.tasks) { t in row(t) }
                } header: {
                    HStack {
                        Text(group.label).foregroundStyle(group.label == "Overdue" ? Theme.late : .secondary)
                        Spacer()
                        Text("\(group.tasks.count)").foregroundStyle(.secondary)
                    }
                }
            }
            if all.count > Self.most && find.isEmpty {
                Text("\(all.count - Self.most) more: type to find one.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Place tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let close { ToolbarItem(placement: .cancellationAction) { Button("Close", action: close) } }
        }
        .sheet(item: $placing) { t in
            PlaceAtTime(task: t, day: day).presentationDetents([.medium])
        }
    }

    private func row(_ t: NexusTask) -> some View {
        Button { placing = t } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(store.color(t)).frame(width: 4, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text((t.key ? "★ " : "") + t.text).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Text(store.workstreamName(t))
                        if let d = t.due { Text("· due " + Days.relative(d, today: store.today)) }
                        if let e = t.est { Text("· " + e) }
                    }
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(t.id) {
            Text(t.text).font(.callout).padding(8)
                .background(store.color(t).opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A day and a time for one task, then it is planned then (Undo on the bar).
private struct PlaceAtTime: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: NexusTask
    @State private var when: Date

    init(task: NexusTask, day: String) {
        self.task = task
        let base = Days.date(day) ?? Date()
        let c = Calendar.current
        let now = Date()
        // the next whole hour on today, 9:00 on another day
        let hour = Days.iso(now) == day ? min(23, c.component(.hour, from: now) + 1) : 9
        _when = State(initialValue: c.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(task.text).font(.headline) }
                DatePicker("Day", selection: $when, displayedComponents: .date)
                DatePicker("Time", selection: $when, displayedComponents: .hourAndMinute)
            }
            .navigationTitle("Plan it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Place") {
                        let c = Calendar.current
                        let day = Days.iso(when)
                        let time = DayLayout.hhmm(c.component(.hour, from: when) * 60 + c.component(.minute, from: when))
                        var plan = task.plan.filter { $0.day != day }
                        plan.append(PlanEntry(day: day, time: time))
                        plan.sort { $0.day < $1.day }
                        store.setPlan(task, plan)
                        dismiss()
                    }
                }
            }
        }
    }
}
