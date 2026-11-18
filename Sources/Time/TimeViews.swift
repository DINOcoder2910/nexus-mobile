import SwiftUI
import NexusCore

// The time tracking screens on the iPad and the iPhone: the running timer (a pill over the iPhone's tabs, a row at the top of the
// iPad's sidebar), the task panel's Time section, the session sheet (add or change one), the task picker, and the Time screen. Each
// device has its own layout; everything is reachable on both, the less-used parts (a session's times, adding by hand) behind a tap.

/// A running timer's clock, every second.
struct TimerClock: View {
    let entry: TimeLog.Entry
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(TimeLog.clock(entry.seconds(now: ctx.date))).monospacedDigit()
        }
    }
}

/// The running dot.
struct TimerDot: View {
    @State private var dim = false
    var body: some View {
        Circle().fill(Theme.accent).frame(width: 8, height: 8)
            .opacity(dim ? 0.35 : 1)
            .onAppear { withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true } }
            .accessibilityHidden(true)
    }
}

/// The running timer as a pill (the iPhone, over every tab): its task (tap opens it), its clock, Stop.
struct RunningTimerPill: View {
    @Environment(NexusStore.self) private var store
    private var tracker: TimeTracker { .shared }

    var body: some View {
        if let c = tracker.current {
            HStack(spacing: 10) {
                TimerDot()
                Button { if store.task(c.task) != nil { store.openTaskId = c.task } } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tracker.title(c, in: store.snapshot)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        TimerClock(entry: c).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                Button { tracker.stop(store: store) } label: {
                    Image(systemName: "stop.fill").font(.subheadline).frame(width: 34, height: 34).background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop the timer")
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .accessibilityIdentifier("timer-pill")
        }
    }
}

/// The running timer at the top of the iPad's sidebar (and the More list): its task, its clock, Stop.
struct SidebarTimerRow: View {
    @Environment(NexusStore.self) private var store
    private var tracker: TimeTracker { .shared }

    var body: some View {
        if let c = tracker.current {
            HStack(spacing: 10) {
                TimerDot()
                Button { if store.task(c.task) != nil { store.openTaskId = c.task } } label: {
                    Text(tracker.title(c, in: store.snapshot)).lineLimit(1).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                TimerClock(entry: c).font(.callout).foregroundStyle(.secondary)
                Button { tracker.stop(store: store) } label: { Image(systemName: "stop.circle.fill").font(.title3) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Stop the timer")
            }
            .accessibilityIdentifier("timer-row")
        }
    }
}

// MARK: - the task panel's Time section

struct TaskTimeSection: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let editable: Bool
    @State private var sheet: SessionSheet.Mode?
    private var tracker: TimeTracker { .shared }

    var body: some View {
        let s = store.snapshot
        let all = tracker.sessions(of: task.id, in: s)
        let spent = tracker.seconds(task.id, in: s)
        let own = tracker.seconds(task.id, in: s, subs: false)
        let est = store.planning.estimate(task)
        let mine = tracker.running.first { $0.task == task.id }
        let other = mine == nil ? tracker.current : nil
        Section {
            HStack(spacing: 12) {
                if let mine {
                    Button { tracker.stop(store: store) } label: {
                        HStack(spacing: 6) { Image(systemName: "stop.fill").imageScale(.small); TimerClock(entry: mine) }
                            .lineLimit(1).fixedSize()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("task-timer")
                } else {
                    Button { tracker.start(task, store: store) } label: { Label("Start timer", systemImage: "play.fill") }
                        .buttonStyle(.bordered)
                        .disabled(!task.hasId || store.snapshot.readOnlyReason != nil)
                        .accessibilityIdentifier("task-timer")
                }
                Spacer()
                if spent > 0 {
                    Text(TimeLog.spent(spent) + (est.map { " of \(hoursText($0))" } ?? "") + " spent")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                } else {
                    Text("Nothing yet").font(.callout).foregroundStyle(.secondary)
                }
            }
            if spent - own >= 60 {
                Text("\(TimeLog.spent(spent - own)) on its subtasks").font(.caption).foregroundStyle(.secondary)
            }
            if let other {
                Text("A timer runs on “\(tracker.title(other, in: s))”: starting this one stops it.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(all.prefix(8)) { e in
                Button { sheet = .change(e) } label: { SessionLine(entry: e, showTask: e.task != task.id) }
                    .buttonStyle(.plain)
                    .swipeActions { Button(role: .destructive) { tracker.remove(e, store: store) } label: { Label("Remove", systemImage: "trash") } }
            }
            if all.count > 8 { Text("\(all.count - 8) more on the Time screen").font(.caption).foregroundStyle(.secondary) }
            Button { sheet = .add(task.id, day: store.today) } label: { Label("Add time…", systemImage: "plus.circle") }
                .sheet(item: $sheet) { m in SessionSheet(mode: m) }
        } header: { Text("Time") }
    }
}

/// One session: "Mon 16 Nov · 14:05 – 14:50   45m   iPad".
struct SessionLine: View {
    @Environment(NexusStore.self) private var store
    let entry: TimeLog.Entry
    var showTask = true
    var showDay = true

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if showTask {
                    HStack(spacing: 6) {
                        Circle().fill(store.color(workstream: store.task(entry.task)?.workstream)).frame(width: 7, height: 7)
                        Text(TimeTracker.shared.title(entry, in: store.snapshot)).lineLimit(1)
                    }
                }
                Text((showDay ? dayWords(entry) + " · " : "") + "\(TimeLog.hm(entry.start)) – \(entry.end.map { TimeLog.hm($0) } ?? "now")")
                    .font(showTask ? .caption : .callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            if entry.running {
                TimerClock(entry: entry).font(.callout).foregroundStyle(Theme.accent)
            } else {
                Text(TimeLog.spent(entry.seconds())).font(.callout).monospacedDigit()
            }
            if entry.device != TimeTracker.device {
                Text(TimeLog.deviceName(entry.device)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func dayWords(_ e: TimeLog.Entry) -> String {
        guard let d = e.startDate else { return "" }
        return Days.label(Days.today(now: d))
    }
}

// MARK: - add or change a session

struct SessionSheet: View {
    enum Mode: Identifiable {
        case add(String, day: String)
        case change(TimeLog.Entry)
        var id: String { switch self { case .add(let t, let d): return "add|\(t)|\(d)"; case .change(let e): return e.id } }
    }
    let mode: Mode
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()
    @State private var running = false
    private var tracker: TimeTracker { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(taskTitle).font(.headline)
                }
                Section {
                    DatePicker("Start", selection: $start, in: ...Date())
                    if running {
                        LabeledContent("End", value: "still running")
                    } else {
                        DatePicker("End", selection: $end, in: ...Date().addingTimeInterval(60))
                        LabeledContent("Lasts", value: end > start ? (TimeLog.spent(end.timeIntervalSince(start)).isEmpty ? "under a minute" : TimeLog.spent(end.timeIntervalSince(start))) : "–")
                    }
                } footer: {
                    if case .add = mode { Text("Saved in this \(Device.name)'s time file; it syncs to the laptop.") }
                }
                if case .change(let e) = mode {
                    Section {
                        Button("Remove this session", role: .destructive) { tracker.remove(e, store: store); dismiss() }
                    }
                }
            }
            .navigationTitle(isAdd ? "Add time" : "A session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isAdd ? "Add" : "Save") { save() }.disabled(!running && end <= start) }
            }
            .onAppear(perform: fill)
        }
        .presentationDetents([.medium, .large])
    }

    private var isAdd: Bool { if case .add = mode { return true }; return false }
    private var taskTitle: String {
        switch mode {
        case .add(let id, _): return store.task(id)?.text ?? "A task"
        case .change(let e): return tracker.title(e, in: store.snapshot)
        }
    }

    private func fill() {
        switch mode {
        case .add(_, let day):
            if day == store.today {
                let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 300) * 300)
                end = now; start = now.addingTimeInterval(-30 * 60)
            } else {
                let d = Days.date(day) ?? Date()
                end = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: d) ?? d
                start = end.addingTimeInterval(-30 * 60)
            }
        case .change(let e):
            start = e.startDate ?? Date(); end = e.endDate ?? Date(); running = e.running
        }
    }

    private func save() {
        switch mode {
        case .add(let id, _):
            if let t = store.task(id) { tracker.add(t, from: start, to: end, store: store) }
        case .change(let e):
            tracker.change(e, from: start, to: running ? nil : end, store: store)
        }
        dismiss()
    }
}

/// "Add time…" on the Time screen: which task (open tasks, searchable), then the session sheet.
struct TaskPickSheet: View {
    let day: String
    var picked: (String) -> Void
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let q = query.lowercased()
            let open = store.snapshot.tasks.values.filter { !$0.done && $0.hasId && (q.isEmpty || $0.text.lowercased().contains(q)) }
                .sorted { $0.order < $1.order }.prefix(60)
            List(Array(open)) { t in
                Button { picked(t.id); dismiss() } label: {
                    HStack(spacing: 10) {
                        Circle().fill(store.color(t)).frame(width: 8, height: 8)
                        Text(t.text).lineLimit(1).foregroundStyle(.primary)
                        Spacer()
                        Text(store.workstreamName(t)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Which task?")
            .navigationTitle("Add time to a task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - the Time screen

struct TimeView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    @State private var week: String?
    @State private var day: String?
    @State private var pickTask = false
    @State private var sheet: SessionSheet.Mode?
    private var tracker: TimeTracker { .shared }

    var body: some View {
        let today = store.today
        let monday = week ?? Days.weekStart(today)
        let days = (0..<7).map { Days.add(monday, $0) }
        let shown = day.flatMap { days.contains($0) ? $0 : nil } ?? (days.contains(today) ? today : days[0])
        let all = tracker.entries
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            let per = days.map { TimeLog.daySeconds(all, $0, now: now) }
            List {
                Section {
                    header(days: days, per: per, today: today, now: now)
                    if let c = tracker.current { runningCard(c) }
                    weekBars(days: days, per: per, shown: shown, today: today)
                }
                if !tracker.problems.isEmpty {
                    Section { ForEach(tracker.problems, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.soon) } }
                }
                if size == .regular {
                    Section {
                        HStack(alignment: .top, spacing: 28) {
                            VStack(alignment: .leading, spacing: 4) { dayList(shown, all: all, today: today, now: now) }.frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 4) { byWorkstream(days: days, all: all, now: now) }.frame(maxWidth: 380)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    Section { dayList(shown, all: all, today: today, now: now) } header: { Text(shown == today ? "Today" : Days.label(shown)) }
                    Section { byWorkstream(days: days, all: all, now: now) } header: { Text(days.contains(today) ? "This week by workstream" : "That week by workstream") }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Time")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button { pickTask = true } label: { Label("Add time…", systemImage: "plus") }
                    Button { week = Days.add(monday, -7); day = nil } label: { Label("The week before", systemImage: "chevron.left") }
                    Button { week = Days.add(monday, 7); day = nil } label: { Label("The week after", systemImage: "chevron.right") }
                    if !days.contains(today) { Button { week = nil; day = nil } label: { Label("This week", systemImage: "calendar") } }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $pickTask) { TaskPickSheet(day: shown) { id in DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sheet = .add(id, day: shown) } } }
        .sheet(item: $sheet) { m in SessionSheet(mode: m) }
        .refreshable { store.reload() }
    }

    private func header(days: [String], per: [TimeInterval], today: String, now: Date) -> some View {
        let week = per.reduce(0, +)
        let todayS = days.firstIndex(of: today).map { per[$0] } ?? 0
        let thisWeek = days.contains(today)
        return VStack(alignment: .leading, spacing: 4) {
            Text(thisWeek ? "This week" : "\(Days.label(days[0])) – \(Days.label(days[6]))").font(.title2.weight(.bold))
            Text(thisWeek ? "\(TimeLog.spent(todayS).isEmpty ? "0m" : TimeLog.spent(todayS)) today · \(TimeLog.spent(week).isEmpty ? "0m" : TimeLog.spent(week)) this week"
                          : "\(TimeLog.spent(week).isEmpty ? "0m" : TimeLog.spent(week)) that week")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("time-hero")
        }
        .padding(.vertical, 4)
    }

    private func runningCard(_ c: TimeLog.Entry) -> some View {
        HStack(spacing: 12) {
            TimerDot()
            VStack(alignment: .leading, spacing: 2) {
                Button { if store.task(c.task) != nil { store.openTaskId = c.task } } label: {
                    Text(tracker.title(c, in: store.snapshot)).font(.headline).lineLimit(1).foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                Text(store.task(c.task).map { store.workstreamName($0) } ?? "not in the folder any more")
                    + Text(c.device != TimeTracker.device ? " · started on \(TimeLog.deviceWords(c.device))" : "")
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer()
            TimerClock(entry: c).font(.title2.weight(.semibold))
            Button { tracker.stop(store: store) } label: {
                HStack(spacing: 6) { Image(systemName: "stop.fill").imageScale(.small); Text("Stop") }.lineLimit(1).fixedSize()
            }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }

    private func weekBars(days: [String], per: [TimeInterval], shown: String, today: String) -> some View {
        let top = max(per.max() ?? 0, 3600)
        return HStack(alignment: .bottom, spacing: Device.isPhone ? 6 : 14) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                Button { day = d } label: {
                    VStack(spacing: 5) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(d == shown ? 0.22 : 0.1))
                            RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(d > today ? 0.4 : 1))
                                .frame(height: max(0, CGFloat(per[i] / top) * (Device.isPhone ? 72 : 96)))
                        }
                        .frame(width: Device.isPhone ? 24 : 30, height: Device.isPhone ? 72 : 96)
                        Text(String(Days.shortDay(d).prefix(Device.isPhone ? 1 : 3))).font(.caption2.weight(d == today ? .bold : .regular))
                            .foregroundStyle(d == today ? Theme.accent : .secondary)
                        Text(TimeLog.spent(per[i]).isEmpty ? "–" : TimeLog.spent(per[i])).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Days.label(d)): \(TimeLog.spent(per[i]).isEmpty ? "nothing" : TimeLog.spent(per[i]))")
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func dayList(_ shown: String, all: [TimeLog.Entry], today: String, now: Date) -> some View {
        let list = TimeLog.sessions(on: shown, all, now: now)
        if size == .regular {
            HStack {
                Text(shown == today ? "Today" : Days.label(shown)).font(.headline)
                Spacer()
                Text(TimeLog.spent(TimeLog.daySeconds(all, shown, now: now))).foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)
        }
        if list.isEmpty {
            Text(shown > today ? "That day is still to come." : "Nothing tracked that day.").font(.callout).foregroundStyle(.secondary)
        }
        ForEach(list) { e in
            Button { sheet = .change(e) } label: { SessionLine(entry: e, showDay: false) }
                .buttonStyle(.plain)
                .padding(.vertical, size == .regular ? 4 : 0)
                .swipeActions { Button(role: .destructive) { tracker.remove(e, store: store) } label: { Label("Remove", systemImage: "trash") } }
                .contextMenu {
                    Button { sheet = .change(e) } label: { Label("Change its times", systemImage: "clock") }
                    Button(role: .destructive) { tracker.remove(e, store: store) } label: { Label("Remove", systemImage: "trash") }
                }
        }
    }

    @ViewBuilder
    private func byWorkstream(days: [String], all: [TimeLog.Entry], now: Date) -> some View {
        let s = store.snapshot
        let groups = TimeLog.grouped(all, days: days, now: now) { e in s.tasks[e.task].map { $0.workstream ?? "" } ?? "__gone" }
        if size == .regular { Text(days.contains(store.today) ? "This week by workstream" : "That week by workstream").font(.headline).padding(.bottom, 4) }
        if groups.isEmpty {
            Text("Nothing tracked yet. Start a timer from a task: hold it for its menu, or open it.").font(.callout).foregroundStyle(.secondary)
        }
        let top = groups.first?.seconds ?? 1
        ForEach(groups, id: \.key) { g in
            HStack(spacing: 10) {
                Circle().fill(g.key == "__gone" ? Color.secondary : store.color(workstream: g.key.isEmpty ? nil : g.key)).frame(width: 8, height: 8)
                Text(g.key == "__gone" ? "Tasks no longer there" : g.key.isEmpty ? "Inbox" : (store.workstream(g.key)?.name ?? g.key)).lineLimit(1)
                Spacer(minLength: 8)
                GeometryReader { geo in
                    Capsule().fill(Color.secondary.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(g.key == "__gone" ? Color.secondary : store.color(workstream: g.key.isEmpty ? nil : g.key))
                                .frame(width: max(4, geo.size.width * CGFloat(g.seconds / top)))
                        }
                }
                .frame(width: size == .regular ? 120 : 70, height: 6)
                Text(TimeLog.spent(g.seconds)).font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 56, alignment: .trailing)
            }
            .padding(.vertical, 2)
        }
    }
}
