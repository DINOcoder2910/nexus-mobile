import SwiftUI
import NexusCore

/// Today: what you planned (times first), repeats that fall today, deadlines that need you, what slipped, and the key dates ahead.
/// Wide (landscape) it is two columns: the plan on the left, the rest on the right.
struct TodayView: View {
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var cal
    @State private var dropTargeted = false
    @State private var eventSheet: EventSheet?

    var body: some View {
        let p = store.planning
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(p)
                    if !p.keyDates.isEmpty { keyStrip(p) }
                    if geo.size.width > 860 {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 18) { planCard(p) }.frame(maxWidth: .infinity)
                            VStack(spacing: 18) { sideCards(p) }.frame(width: min(420, geo.size.width * 0.4))
                        }
                    } else {
                        planCard(p)
                        sideCards(p)
                    }
                }
                .padding(20)
                .padding(.bottom, 60)
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
            }
            .refreshable { store.reload() }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Today")
        .eventSheet($eventSheet, store: cal)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.capture = .init(workstream: nil, parent: nil, plan: store.today) } label: { Label("Add for today", systemImage: "plus") }
            }
        }
    }

    // MARK: parts

    private func header(_ p: Planning) -> some View {
        let planned = p.planned(on: store.today)
        let hours = p.load(on: store.today)
        let open = planned.filter { !$0.done }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text(longDate(store.today)).font(.largeTitle.weight(.bold))
            Text([open == 0 ? "Nothing left on the plan" : "\(open) planned",
                  hours > 0 ? hoursText(hours) : nil,
                  p.slipped.isEmpty ? nil : "\(p.slipped.count) slipped"].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            if cal.eventsOnPlan, let next = cal.next(today: store.today) {
                Button { eventSheet = .show(next.event) } label: {
                    Label(next.start <= Date() ? "Now: \(next.title)" : "Next: \(next.title) at \(next.start.formatted(date: .omitted, time: .shortened))",
                          systemImage: "calendar")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(next.color)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func keyStrip(_ p: Planning) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(p.keyDates.prefix(6)) { t in
                    let n = Days.between(store.today, t.due!)
                    Button { store.open(t) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n < 0 ? "\(-n)d late" : n == 0 ? "Today" : n == 1 ? "Tomorrow" : "in \(n) days")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(n < 0 ? Theme.late : n <= 2 ? Theme.soon : .secondary)
                            Text("★ " + t.text).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                            Text(store.workstreamName(t)).font(.caption).foregroundStyle(store.color(t))
                        }
                        .frame(width: 190, alignment: .leading)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func planCard(_ p: Planning) -> some View {
        let today = store.today
        let planned = p.planned(on: today)
        let doneToday = p.s.order.compactMap { p.s.tasks[$0] }.filter { $0.done && $0.doneOn == today && $0.plannedDays.contains(today) }
        let repeats = p.repeatsToday
        return Card(title: "Plan", count: planned.count, icon: "sun.max") {
            if planned.isEmpty && repeats.isEmpty {
                Text(doneToday.isEmpty ? "Nothing planned yet. Drag a task here from Slipped, or plan one from Tasks." : "All done for today.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(planned) { t in rowDivider(TaskRow(task: t, day: today)) }
            if !repeats.isEmpty {
                Text("Repeats today").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
                ForEach(repeats) { t in rowDivider(TaskRow(task: t)) }
            }
            if !doneToday.isEmpty {
                DisclosureGroup("Done today · \(doneToday.count)") {
                    ForEach(doneToday) { t in TaskRow(task: t, day: today, compact: true) }
                }
                .font(.callout).foregroundStyle(.secondary).padding(.top, 6)
            }
            Button { store.capture = .init(workstream: nil, parent: nil, plan: today) } label: {
                Label("Add a task for today", systemImage: "plus").font(.callout)
            }
            .padding(.top, 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.accent, lineWidth: dropTargeted ? 2 : 0))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids {
                guard let t = store.task(id), !t.plannedDays.contains(today) else { continue }
                let past = t.plannedDays.filter { $0 < today }.max()
                store.move(t, from: past, to: today)
            }
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    @ViewBuilder
    private func sideCards(_ p: Planning) -> some View {
        let today = store.today
        eventsCard(today)
        let due = p.dueNow
        if !due.isEmpty {
            Card(title: "Deadlines", count: due.count, icon: "flag") {
                ForEach(due) { t in rowDivider(TaskRow(task: t, compact: true)) }
            }
        }
        let slipped = p.slipped
        if !slipped.isEmpty {
            Card(title: "Slipped", count: slipped.count, icon: "arrow.uturn.backward") {
                ForEach(slipped) { t in
                    HStack(alignment: .top) {
                        TaskRow(task: t, compact: true)
                        if store.canEdit(t) {
                            Button("Today") { store.move(t, from: t.plannedDays.max(), to: today) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    Divider()
                }
                if slipped.count > 1 {
                    Button("Move all to today") { for t in slipped where store.canEdit(t) { store.move(t, from: t.plannedDays.max(), to: today) } }
                        .font(.callout)
                }
            }
        }
        let tomorrow = p.planned(on: Days.add(today, 1))
        if !tomorrow.isEmpty {
            Card(title: "Tomorrow", count: tomorrow.count, icon: "sunrise") {
                ForEach(tomorrow) { t in rowDivider(TaskRow(task: t, day: Days.add(today, 1), compact: true)) }
            }
        }
        if store.snapshot.problems.count > 0 {
            Card(title: "Things to check", count: store.snapshot.problems.count, icon: "exclamationmark.triangle") {
                ForEach(store.snapshot.problems) { pr in
                    Text("\(pr.file): \(pr.message)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The day's events from the device's calendars (the laptop shows them on Today's timeline). Asks once, quietly, if
    /// Nexus may read them; says nothing more if the answer was no.
    @ViewBuilder
    private func eventsCard(_ today: String) -> some View {
        if cal.eventsOnPlan && cal.canRead {
            let events = cal.events(on: today)
            Card(title: "Calendar", count: events.count, icon: "calendar") {
                if events.isEmpty {
                    Text("No events today.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
                }
                ForEach(events) { e in
                    Button { eventSheet = .show(e.event) } label: { EventLine(thing: CalThing(event: e, day: today)) }
                        .buttonStyle(.plain)
                        .opacity(!e.allDay && e.end < Date() ? 0.5 : 1)
                }
            }
        } else if cal.notAsked {
            Card(title: "Calendar", icon: "calendar") {
                Text("Show today's events from this \(Device.name)'s calendars here.").font(.callout).foregroundStyle(.secondary)
                Button("Show my calendars") { Task { await cal.requestAccess() } }.font(.callout)
            }
        }
    }

    private func rowDivider<V: View>(_ v: V) -> some View {
        VStack(spacing: 0) { v; Divider().padding(.leading, 32) }
    }

    private func longDate(_ iso: String) -> String {
        guard let d = Days.date(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: d)
    }
}

/// A rounded group of rows with a small header: the iPad's version of the laptop's panels.
struct Card<Content: View>: View {
    var title: String
    var count: Int?
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).foregroundStyle(.secondary) }
                Text(title).font(.headline)
                if let count, count > 0 { Text("\(count)").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(.bottom, 4)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
