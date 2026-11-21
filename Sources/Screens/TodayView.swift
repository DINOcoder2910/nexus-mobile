import SwiftUI
import NexusCore

/// Today, as the new laptop app has it (switch-over step 4, Nov 20 2026; nexus `desktop/src/screens/Today.tsx`): Key dates and From
/// Study at the top, Next up, your list beside the day's hours, then Slipped and a look at tomorrow. The list is in the one day order
/// (NexusCore DayOrder, synced in `nexus-day-order.yaml`): drag a row onto another to put it there, onto the day to give it a time,
/// and a timed block back onto the list to take the time off. The sums are NexusCore TodayPlan's, the same as the laptop's.
/// Wide (the iPad) the parts sit side by side; narrow (the iPhone, the iPad in a third) they stack.
struct TodayView: View {
    var go: (Screen) -> Void = { _ in }
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var cal
    @State private var eventSheet: EventSheet?
    @State private var adding = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            GeometryReader { geo in
                let wide = geo.size.width > 820
                let v = day(at: tl.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        header(v, wide: wide)
                        top(v, wide: wide)
                        if let n = v.next { NextUpCard(task: n, v: v) }
                        middle(v, wide: wide)
                        bottom(v, wide: wide)
                        problems
                    }
                    .padding(.horizontal, wide ? 32 : 16)
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                    .frame(maxWidth: 1240)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { store.reload() }
            }
        }
        .background(Kit.page)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .eventSheet($eventSheet, store: cal)
        .task { StudyLibrary.shared.refreshIfChanged(store) }
        .toolbar {
            if Device.isPhone && store.snapshot.isDataFolder {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { PlanWithClaude.shared.start(store, calendar: cal) } label: { Label("Plan with Claude", systemImage: "sparkles") }
                            .disabled(PlanWithClaude.shared.running)
                        Button { ClaudeChatSession.open(looking: "Today") } label: { Label("Ask Claude about today", systemImage: "bubble.left.and.text.bubble.right") }
                    } label: {
                        Label("Claude", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("today-claude")
                }
            }
        }
    }

    /// The day's sums at `date`: the device's calendars give the events (when Today shows them).
    private func day(at date: Date) -> TodayPlan.Day {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let spans = { (d: String) in TodayEvents.spans(cal, d).map { TodayPlan.Span($0.start, $0.end) } }
        return TodayPlan.day(store.planning, now: now, events: spans)
    }

    // MARK: the header

    @ViewBuilder
    private func header(_ v: TodayPlan.Day, wide: Bool) -> some View {
        let timedEvents = TodayEvents.spans(cal, v.today).count
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.weekday(v.today).uppercased())
                .font(.nx(.caption, .semibold)).tracking(0.6).foregroundStyle(Kit.muted)
            HStack(alignment: .firstTextBaseline) {
                Text(Self.dayMonth(v.today)).font(.nx(size: wide ? 40 : 32, .bold, display: true)).foregroundStyle(Kit.ink)
                Spacer()
                if !Device.isPhone && store.snapshot.isDataFolder {
                    HStack(spacing: 8) {
                        Button { PlanWithClaude.shared.start(store, calendar: cal) } label: {
                            Label(PlanWithClaude.shared.running ? "Planning…" : "Plan my day", systemImage: "sparkles")
                        }
                        .buttonStyle(.kitClaude)
                        .disabled(PlanWithClaude.shared.running || store.snapshot.readOnlyReason != nil)
                        .accessibilityIdentifier("plan-with-claude")
                        Button { store.capture = .init(workstream: nil, parent: nil, plan: store.today) } label: { Label("Add", systemImage: "plus") }
                            .buttonStyle(.kitPrimary)
                            .accessibilityIdentifier("today-add")
                    }
                }
            }
            summary(v, events: timedEvents)
                .font(.nx(.body)).foregroundStyle(Kit.ink)
                .accessibilityIdentifier("today-sum")
            if PlanWithClaude.shared.run != nil { PlanWithClaudeButton(buttonShown: false).padding(.top, 6) }
        }
    }

    private func summary(_ v: TodayPlan.Day, events: Int) -> Text {
        let left = v.list.count
        let first = left > 0 ? Text("\(left) to do").bold() + Text(v.estLeft > 0 ? ", about \(TimeWords.about(v.estLeft)). " : ". ")
                             : Text("Nothing left for today. ").bold()
        // time tracked today on every device (TimeTracker), once there is a minute of it
        let tracked = TimeLog.daySeconds(TimeTracker.shared.entries, store.today)
        return first + Text(v.freeLeft > 0 ? "You have about \(TimeWords.about(v.freeLeft)) free\(events > 0 ? " between classes" : "")."
                                           : "No free time left today.")
            + Text(tracked >= 60 ? " \(TimeLog.spent(tracked)) tracked." : "").foregroundColor(Kit.muted)
    }

    // MARK: Key dates and From Study

    @ViewBuilder
    private func top(_ v: TodayPlan.Day, wide: Bool) -> some View {
        let keys = VStack(alignment: .leading, spacing: 10) {
            SectionHead(title: "Key dates", note: "starred, soonest first")
            if v.keyDates.isEmpty {
                QuietCard(text: "No starred deadlines. Star a task with a deadline to count down to it here.")
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(v.keyDates.prefix(2), id: \.task.id) { k in KeyDateCard(k: k) }
                }
            }
        }
        let items = studyItems()
        let study = VStack(alignment: .leading, spacing: 10) {
            SectionHead(title: "From Study")
            if items.isEmpty {
                QuietCard(text: "Nothing due from your decks today.")
            } else {
                ForEach(items.prefix(2)) { s in StudyDueCard(item: s) { go(.studyPage(s.workstream.id)) } }
            }
        }
        if wide {
            HStack(alignment: .top, spacing: 24) {
                keys.frame(maxWidth: .infinity, alignment: .leading)
                study.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            keys
            study
        }
    }

    /// Cards due in each subject's decks (study/review.yaml), as the laptop's From Study.
    private func studyItems() -> [StudyDue] {
        let lib = StudyLibrary.shared
        let now = StudyLibrary.now
        return lib.studies.compactMap { s in
            guard !s.workstream.parked else { return nil }
            var n = 0, decks: [String] = []
            for f in s.decks {
                let d = lib.counts(s, f, now: now)?.due ?? 0
                if d > 0 { n += d; decks.append(f.deck?.title ?? f.fileId) }
            }
            return n > 0 ? StudyDue(workstream: s.workstream, count: n, decks: decks) : nil
        } + oralItems()
    }

    /// Spanish oral practice in each subject that has it (study/spanish/oral), with the days since the last oral (orals/ files are
    /// named from their day), as the laptop's From Study.
    private func oralItems() -> [StudyDue] {
        let fm = FileManager.default
        return store.snapshot.workstreams.values.sorted { $0.name < $1.name }.compactMap { w in
            guard !w.parked else { return nil }
            let oral = store.folder.appendingPathComponent(w.folder).appendingPathComponent("study/spanish/oral", isDirectory: true)
            var dir: ObjCBool = false
            guard fm.fileExists(atPath: oral.path, isDirectory: &dir), dir.boolValue else { return nil }
            let names = (try? fm.contentsOfDirectory(atPath: oral.appendingPathComponent("orals").path)) ?? []
            let last = names.filter { $0.count >= 10 && Days.isIso(String($0.prefix(10))) }.map { String($0.prefix(10)) }.max()
            return StudyDue(workstream: w, count: 0, decks: [], oral: true, lastDays: last.map { max(0, Days.between($0, store.today)) })
        }
    }

    // MARK: your list and the day

    @ViewBuilder
    private func middle(_ v: TodayPlan.Day, wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 24) {
                list(v).frame(maxWidth: .infinity, alignment: .leading)
                DayCard(v: v, eventSheet: $eventSheet).frame(width: 380)
            }
        } else {
            list(v)
            DayCard(v: v, eventSheet: $eventSheet)
        }
    }

    private func list(_ v: TodayPlan.Day) -> some View {
        let sugg = Dictionary(v.suggestions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let repeats = store.planning.repeatsToday
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Today's list").font(.nx(size: 22, .bold, display: true)).foregroundStyle(Kit.ink)
                Text("\(v.list.count) left · your order").font(.nx(.subheadline)).foregroundStyle(Kit.muted)
                Spacer(minLength: 0)
                if !Device.isPhone { Text("drag onto the day to give a time").font(.nx(.footnote)).foregroundStyle(Kit.faint).lineLimit(1) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            ForEach(v.list) { t in
                Rectangle().fill(Kit.line).frame(height: 1)
                TodayRow(task: t, v: v, suggestion: sugg[t.id])
                    .dropDestination(for: String.self) { ids, _ in drop(ids, before: t, v) }
            }
            Rectangle().fill(Kit.line).frame(height: 1)
            addRow(v)
            if !repeats.isEmpty {
                Text("Repeats today").font(.nx(.caption, .semibold)).foregroundStyle(Kit.muted).padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
                ForEach(repeats) { t in
                    Rectangle().fill(Kit.line).frame(height: 1)
                    TodayRow(task: t, v: v, suggestion: nil, repeating: true)
                }
            }
            ForEach(v.done) { t in
                Rectangle().fill(Kit.line).frame(height: 1)
                TodayRow(task: t, v: v, suggestion: nil)
            }
            Rectangle().fill(Kit.line).frame(height: 1)
            if v.list.isEmpty && v.done.isEmpty {
                Text("Nothing planned for today. Plan something from the Planner, or add a task.")
                    .font(.nx(.callout)).foregroundStyle(Kit.muted).padding(.horizontal, 44).padding(.vertical, 16)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-list")
    }

    private func addRow(_ v: TodayPlan.Day) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus").foregroundStyle(Kit.muted).frame(width: 22)
            TextField("Add a task", text: $adding)
                .font(.nx(.body))
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit(add)
                .accessibilityIdentifier("today-add-task")
            if !adding.isEmpty { Text("Return to add").font(.nx(.footnote)).foregroundStyle(Kit.faint) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        // a task dropped here goes to the end of your list
        .dropDestination(for: String.self) { ids, _ in drop(ids, before: nil, v) }
    }

    private func add() {
        let t = adding.trimmingCharacters(in: .whitespaces)
        adding = ""
        guard !t.isEmpty else { return }
        store.add(title: t, workstream: nil, plan: [PlanEntry(day: store.today)])
    }

    /// A task dropped on the list: before `target` (nil: the end) in your order. A timed one loses its time; one from another day
    /// (Slipped, Tomorrow) is planned today.
    private func drop(_ ids: [String], before target: NexusTask?, _ v: TodayPlan.Day) -> Bool {
        guard let id = ids.first, let t = store.task(id), store.canEdit(t), id != target?.id else { return false }
        let today = v.today
        if !t.plannedDays.contains(today) {
            let from = t.plannedDays.filter { $0 < today }.max() ?? (t.plannedDays.contains(Days.add(today, 1)) ? Days.add(today, 1) : nil)
            store.move(t, from: from, to: today)
        } else if t.time(on: today) != nil {
            store.setTime(t, on: today, nil)
        }
        var keys = v.list.filter { v.time($0) == nil && $0.id != id }.map(\.id)
        let at = target.flatMap { tg in keys.firstIndex(of: tg.id) } ?? keys.count
        keys.insert(id, at: at)
        withAnimation(Kit.spring) { store.setDayOrder(today, keys) }
        return true
    }

    // MARK: Slipped and tomorrow

    @ViewBuilder
    private func bottom(_ v: TodayPlan.Day, wide: Bool) -> some View {
        if wide {
            HStack(alignment: .top, spacing: 24) {
                SlippedCard(v: v).frame(maxWidth: .infinity, alignment: .leading)
                TomorrowCard(v: v).frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            SlippedCard(v: v)
            TomorrowCard(v: v)
        }
    }

    @ViewBuilder
    private var problems: some View {
        if store.snapshot.problems.count > 0 {
            Card(title: "Things to check", count: store.snapshot.problems.count, icon: "exclamationmark.triangle") {
                ForEach(store.snapshot.problems) { pr in
                    Text("\(pr.file): \(pr.message)").font(.nx(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: words

    static func weekday(_ iso: String, short: Bool = false) -> String {
        guard let d = Days.date(iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = short ? "EEE" : "EEEE"
        return f.string(from: d)
    }

    static func dayMonth(_ iso: String) -> String {
        guard let d = Days.date(iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "d MMMM"
        return f.string(from: d)
    }
}

/// The device's calendar events Today and its day card draw (when Today shows events and Nexus may read the calendars).
enum TodayEvents {
    static func spans(_ cal: CalendarStore, _ day: String) -> [(start: Int, end: Int, event: CalEvent)] {
        guard cal.eventsOnPlan && cal.canRead else { return [] }
        return cal.events(on: day).filter { !$0.allDay }.compactMap { e in
            DayLayout.clip(start: e.start, end: e.end, day: day).map { ($0.start, max($0.end, $0.start + 15), e) }
        }
    }

    static func allDay(_ cal: CalendarStore, _ day: String) -> [CalEvent] {
        guard cal.eventsOnPlan && cal.canRead else { return [] }
        return cal.events(on: day).filter(\.allDay)
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
                Text(title).font(.nx(.headline))
                if let count, count > 0 { Text("\(count)").font(.nx(.subheadline)).foregroundStyle(.secondary) }
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
