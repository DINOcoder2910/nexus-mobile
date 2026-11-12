import EventKit
import SwiftUI
import NexusCore

/// How the Calendar shows time: the laptop's Day, 3 days, Week, Month and a list (its Agenda). The iPhone has no Week (seven
/// columns don't fit a phone's width).
enum CalMode: String, CaseIterable, Identifiable {
    case day, three, week, month, list
    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Day"
        case .three: return "3 days"
        case .week: return "Week"
        case .month: return "Month"
        case .list: return "List"
        }
    }

    static var available: [CalMode] { Device.isPhone ? [.day, .three, .month, .list] : allCases }
}

/// Something drawn on the calendar: an event from the device's calendars, a task planned at a time, or a deadline.
struct CalThing: Identifiable {
    enum Kind {
        case event(CalEvent)
        case task(NexusTask)
        case deadline(NexusTask)
    }
    let id: String
    let kind: Kind
    let title: String
    /// Minutes from midnight on the day it is drawn on (0 for all-day things).
    let start: Int
    let end: Int
    let allDay: Bool
    let color: Color

    var task: NexusTask? {
        switch kind {
        case .task(let t), .deadline(let t): return t
        case .event: return nil
        }
    }

    var timeText: String {
        switch kind {
        case .event(let e): return e.timeText
        case .task: return DayLayout.hhmm(start)
        case .deadline: return "Deadline"
        }
    }
}

/// The Calendar: the device's calendars (Google, the school's Microsoft 365, iCloud, subscribed links, whatever is added in iOS
/// Settings) with the tasks planned at a time and the deadlines. Tap an event for the system's event sheet (edit, delete), a
/// task for its panel; double-tap an empty time for a new event; drag a task block to plan it at another time.
struct CalendarView: View {
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var cal
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("calMode") private var modeRaw = Device.isPhone ? CalMode.day.rawValue : CalMode.week.rawValue
    /// The day the view is on; nil follows today.
    @State private var anchor: String?
    @State private var sheet: EventSheet?
    /// Place tasks: a drawer beside the grid on the iPad, a sheet on the iPhone.
    @State private var placing = false

    private var mode: CalMode {
        guard let m = CalMode(rawValue: modeRaw), CalMode.available.contains(m) else { return .day }
        return m
    }
    private var focus: String { anchor ?? store.today }
    private var compact: Bool { sizeClass == .compact }

    /// The days the view shows.
    private var days: [String] {
        switch mode {
        case .day: return [focus]
        case .three: return (0..<3).map { Days.add(focus, $0) }
        case .week:
            let s = Days.weekStart(focus)
            return (0..<7).map { Days.add(s, $0) }
        case .month: return DayLayout.monthGrid(focus)
        case .list: return (0..<21).map { Days.add(focus, $0) }
        }
    }

    var body: some View {
        let shown = days
        let p = store.planning
        let events = cal.events(from: shown.first ?? focus, through: shown.last ?? focus)
        HStack(spacing: 0) {
            grid(shown, events: events, p: p)
            if placing && !compact {
                Divider()
                // a drawer, not a second navigation stack: its own small header
                VStack(spacing: 0) {
                    HStack {
                        Text("Place tasks").font(.headline)
                        Spacer()
                        Button { withAnimation(.snappy) { placing = false } } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Close Place tasks")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    PlaceTasksList(day: focus)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .frame(width: 320)
                .transition(.move(edge: .trailing))
            }
        }
        .sheet(isPresented: Binding(get: { placing && compact }, set: { if !$0 { placing = false } })) {
            NavigationStack { PlaceTasksList(day: focus, close: { placing = false }) }
                .presentationDetents([.medium, .large])
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .eventSheet($sheet, store: cal)
    }

    @ViewBuilder
    private func grid(_ shown: [String], events: [CalEvent], p: Planning) -> some View {
        VStack(spacing: 0) {
            if !cal.canRead { CalendarAccessCard().padding([.horizontal, .top], 16) }
            switch mode {
            case .day, .three, .week:
                TimeGridView(days: shown, today: store.today,
                             timed: { timed(on: $0, events: events, p: p) },
                             allDay: { allDay(on: $0, events: events, p: p) },
                             tap: { open($0) }, openDay: { openDay($0) },
                             newEvent: { day, minute in sheet = .new(date(day, minute)) },
                             dropTask: { id, day, minute in plan(id, on: day, at: minute, shown: shown) })
            case .month:
                MonthGridView(days: shown, month: DayLayout.monthStart(focus), today: store.today, compact: compact,
                              things: { allDay(on: $0, events: events, p: p) + timed(on: $0, events: events, p: p).sorted { $0.start < $1.start } },
                              openDay: { openDay($0) })
            case .list:
                agenda(shown, events: events, p: p)
            }
        }
        // a swipe on the grid goes earlier or later (not on the drawer, where a task is dragged)
        .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
            let dx = v.translation.width, dy = v.translation.height
            if abs(dx) > 90 && abs(dx) > abs(dy) * 2 { withAnimation(.snappy) { step(dx < 0 ? 1 : -1) } }
        })
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("View", selection: $modeRaw) {
                    ForEach(CalMode.available) { m in Text(m.label).tag(m.rawValue) }
                }
                Toggle("Show tasks and deadlines", isOn: Binding(get: { cal.showTasks }, set: { cal.showTasks = $0 }))
            } label: {
                Label(mode.label, systemImage: "calendar")
                    .labelStyle(.titleAndIcon)
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { withAnimation(.snappy) { placing.toggle() } } label: {
                if compact {
                    Image(systemName: placing ? "tray.full.fill" : "tray.full")
                } else {
                    Label("Place tasks", systemImage: placing ? "tray.full.fill" : "tray.full").labelStyle(.titleAndIcon)
                }
            }
            .accessibilityLabel("Place tasks")
            .disabled(!store.snapshot.isDataFolder)
        }
        if compact {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { withAnimation(.snappy) { step(-1) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Earlier")
                Spacer()
                Button("Today") { withAnimation(.snappy) { anchor = nil } }
                    .disabled(anchor == nil)
                Spacer()
                Button { withAnimation(.snappy) { step(1) } } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Later")
                Spacer()
                Button { sheet = .new(newEventStart()) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New event")
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { withAnimation(.snappy) { step(-1) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Earlier")
                Button("Today") { withAnimation(.snappy) { anchor = nil } }
                    .disabled(anchor == nil)
                Button { withAnimation(.snappy) { step(1) } } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Later")
                Button { sheet = .new(newEventStart()) } label: { Label("New event", systemImage: "plus") }
            }
        }
    }

    private var title: String {
        let shown = days
        switch mode {
        case .day: return (focus == store.today ? "Today · " : "") + Days.label(focus)
        case .three, .week: return "\(Days.label(shown.first ?? focus)) – \(Days.label(shown.last ?? focus))"
        case .month: return (Days.date(focus) ?? Date()).formatted(.dateTime.month(.wide).year())
        case .list: return "From " + Days.label(focus)
        }
    }

    private func step(_ n: Int) {
        let next: String
        switch mode {
        case .day: next = Days.add(focus, n)
        case .three: next = Days.add(focus, 3 * n)
        case .week, .list: next = Days.add(focus, 7 * n)
        case .month: next = DayLayout.addMonths(focus, n)
        }
        anchor = next == store.today ? nil : next
    }

    private func openDay(_ day: String) {
        withAnimation(.snappy) {
            anchor = day == store.today ? nil : day
            modeRaw = CalMode.day.rawValue
        }
    }

    // MARK: what each day shows

    private func timed(on day: String, events: [CalEvent], p: Planning) -> [CalThing] {
        var out: [CalThing] = events.filter { !$0.allDay }.compactMap { e in
            guard let c = DayLayout.clip(start: e.start, end: e.end, day: day) else { return nil }
            return CalThing(id: "e|\(e.id)|\(day)", kind: .event(e), title: e.title, start: c.start, end: max(c.end, c.start + 15),
                            allDay: false, color: e.color)
        }
        if cal.showTasks {
            for t in p.planned(on: day) {
                guard let m = DayLayout.minutes(t.time(on: day)) else { continue }
                let length = Int(((p.estimate(t) ?? 0.5) * 60).rounded())
                out.append(CalThing(id: "t|\(t.id)|\(day)", kind: .task(t), title: t.text, start: m, end: min(24 * 60, m + max(15, length)),
                                    allDay: false, color: store.color(t)))
            }
        }
        return out
    }

    private func allDay(on day: String, events: [CalEvent], p: Planning) -> [CalThing] {
        var out: [CalThing] = events.filter { $0.allDay && $0.days.contains(day) }.map { e in
            CalThing(id: "e|\(e.id)|\(day)", kind: .event(e), title: e.title, start: 0, end: 0, allDay: true, color: e.color)
        }
        if cal.showTasks {
            for t in p.due(on: day) {
                out.append(CalThing(id: "d|\(t.id)|\(day)", kind: .deadline(t), title: (t.key ? "★ " : "") + t.text, start: 0, end: 0,
                                    allDay: true, color: day < store.today ? Theme.late : t.key ? Theme.key : Theme.soon))
            }
        }
        return out
    }

    private func open(_ thing: CalThing) {
        switch thing.kind {
        case .event(let e): sheet = .show(e.event)
        case .task(let t), .deadline(let t): store.open(t)
        }
    }

    private func date(_ day: String, _ minute: Int) -> Date {
        (Days.date(day) ?? Date()).addingTimeInterval(Double(minute * 60))
    }

    /// A new event from the toolbar: the next whole hour today, 9:00 on another day.
    private func newEventStart() -> Date {
        if focus == store.today {
            let now = Date()
            let c = Calendar.current
            let hour = c.date(bySettingHour: c.component(.hour, from: now), minute: 0, second: 0, of: now) ?? now
            return hour.addingTimeInterval(3600)
        }
        return date(focus, 9 * 60)
    }

    /// A task dropped on a time: planned then. It moves from the day it was shown on here, if any (the drag carries only its id).
    private func plan(_ id: String, on day: String, at minute: Int, shown: [String]) -> Bool {
        guard let t = store.task(id), store.canEdit(t) else { return false }
        var plan = t.plan
        if let from = shown.first(where: { d in d != day && plan.contains { $0.day == d } }) {
            plan.removeAll { $0.day == from }
        }
        plan.removeAll { $0.day == day }
        plan.append(PlanEntry(day: day, time: DayLayout.hhmm(minute)))
        plan.sort { $0.day < $1.day }
        withAnimation(.snappy) { store.setPlan(t, plan) }
        return true
    }

    // MARK: the list

    private func agenda(_ shown: [String], events: [CalEvent], p: Planning) -> some View {
        let byDay: [DayThings] = shown.map { d in
            DayThings(day: d, things: allDay(on: d, events: events, p: p) + timed(on: d, events: events, p: p).sorted { $0.start < $1.start })
        }
        let any = byDay.contains { !$0.things.isEmpty }
        return List {
            if !any {
                EmptyNote(title: "Nothing in these three weeks", detail: cal.canRead ? nil : "Allow access to your calendars to see events here.", icon: "calendar")
                    .listRowBackground(Color.clear)
            }
            ForEach(byDay) { entry in
                if !entry.things.isEmpty {
                    Section {
                        ForEach(entry.things) { th in
                            if let t = th.task {
                                HStack(alignment: .top) {
                                    TaskRow(task: t, day: entry.day, compact: true)
                                    if case .deadline = th.kind { Chip(text: "Deadline", icon: "flag", color: th.color) }
                                }
                            } else {
                                Button { open(th) } label: { EventLine(thing: th) }.buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text((entry.day == store.today ? "Today · " : entry.day == Days.add(store.today, 1) ? "Tomorrow · " : "") + Days.label(entry.day))
                            .font(.subheadline.weight(.semibold)).textCase(nil)
                            .foregroundStyle(entry.day == store.today ? Theme.accent : .secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { cal.reloadCalendars() }
    }
}

/// One day of the list and what it shows.
struct DayThings: Identifiable {
    let day: String
    let things: [CalThing]
    var id: String { day }
}

/// An event as a line: its colour, title, time and place. Today, the Planner and the Calendar's list use it.
struct EventLine: View {
    let thing: CalThing
    var small = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(thing.color).frame(width: 4).frame(minHeight: small ? 16 : 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(thing.title).font(small ? .caption : .body).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(thing.timeText)
                    if !small, case .event(let e) = thing.kind, let place = e.location { Text("· " + place).lineLimit(1) }
                }
                .font(small ? .caption2 : .caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension CalThing {
    /// An event as a calendar thing, for the lines on Today and the Planner.
    init(event e: CalEvent, day: String) {
        let c = DayLayout.clip(start: e.start, end: e.end, day: day)
        self.init(id: "e|\(e.id)|\(day)", kind: .event(e), title: e.title, start: c?.start ?? 0, end: c?.end ?? 0, allDay: e.allDay, color: e.color)
    }
}

/// Shown where the calendars would be when Nexus may not read them: why, and the one button that fixes it.
struct CalendarAccessCard: View {
    @Environment(CalendarStore.self) private var cal
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(cal.notAsked ? "Show your calendars here" : "Nexus can't see your calendars").font(.headline)
                Text("Nexus shows the calendars on this \(Device.name). Add your Google and school accounts in the Settings app (Calendar › Accounts) and their events appear here, beside your planned tasks.")
                    .font(.callout).foregroundStyle(.secondary)
                Button(cal.notAsked ? "Allow access" : "Open Settings") {
                    if cal.notAsked {
                        Task { await cal.requestAccess() }
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}
