import SwiftUI
import NexusCore

/// The Planner, as the new laptop app has it (nexus `desktop/src/screens/Planner.tsx`): 2 days, 3 days, a Week or a Month (five weeks),
/// rolling from today; ‹ › step a whole view (the Month a week). The days show their load against their free time, the Events and
/// Deadlines rows and a lane per subject; the Month is a grid of days with their cards. The Show row hides planned work, deadlines,
/// events, a subject or a calendar (each device keeps its own, as the laptop does). The task bank is full width below, shown or hidden
/// with its button. Drag a card to another day, a bank card onto a day to plan it, a card back to the bank to take its day off. The
/// sums are NexusCore WeekPlan's and the Show row NexusCore PlannerShow, the same as the laptop's. Narrow (the iPhone) the days stack,
/// and the Month is a small grid: tap a day for its cards under it.
struct PlannerView: View {
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var cal
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var eventSheet: EventSheet?
    @AppStorage("plannerBankOpen") private var bankOpen = true
    @AppStorage("plannerBankFilter") private var filter = Filter.all.rawValue
    @AppStorage("plannerBankGroup") private var group = BankGroup.soonest.rawValue
    /// How many days: 2, 3, 7 or 35 (the Month).
    @AppStorage("plannerSpan") private var span = 7
    /// What the Show row hides (PlannerShow.text).
    @AppStorage("plannerShow") private var showText = ""
    /// The first day shown; nil starts at today.
    @State private var start: String?
    @State private var find = ""
    /// The day a drag is over ("bank" for the bank).
    @State private var hot: String?
    /// The Month on the iPhone: the day whose cards show under the grid.
    @State private var picked: String?

    enum Filter: String, CaseIterable { case all = "All", soon = "Due soon", key = "Key dates", slipped = "Slipped", noDate = "No date" }
    enum BankGroup: String, CaseIterable { case soonest = "Soonest", workstream = "Workstream", deadline = "Deadline" }
    static let spans: [(Int, String)] = [(2, "2 days"), (3, "3 days"), (7, "Week"), (35, "Month")]

    private var stacked: Bool { sizeClass == .compact }
    private var days: Int { Self.spans.contains { $0.0 == span } ? span : 7 }
    private var show: PlannerShow { PlannerShow(text: showText) }

    var body: some View {
        let first = start ?? store.today
        let evs = events(first, Days.add(first, days - 1))
        let w = week(evs)
        let shown = show.apply(w)
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(shown)
                    showRow(w, evs)
                    if days == 35 {
                        month(shown, evs, width: geo.size.width - (stacked ? 32 : 48))
                    } else if stacked {
                        stackedDays(shown, evs)
                    } else {
                        grid(shown, evs, width: geo.size.width - 48)
                    }
                    if bankOpen { bank(w) }
                }
                .padding(.horizontal, stacked ? 16 : 24)
                .padding(.top, 8).padding(.bottom, 80)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("planner")
            }
            .refreshable { store.reload() }
        }
        .background(Kit.page)
        .navigationTitle("Planner")
        .navigationBarTitleDisplayMode(.inline)
        .eventSheet($eventSheet, store: cal)
    }

    /// The calendar's events on the days shown, by day (one read for the whole span), without the hidden calendars' when `shown`.
    private func events(_ first: String, _ last: String) -> [String: [CalEvent]] {
        guard cal.eventsOnPlan && cal.canRead else { return [:] }
        var out: [String: [CalEvent]] = [:]
        for e in cal.events(from: first, through: last) { for d in e.days where d >= first && d <= last { out[d, default: []].append(e) } }
        return out
    }

    private func week(_ evs: [String: [CalEvent]]) -> WeekPlan.Week {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let spans = { (d: String) -> [TodayPlan.Span] in
            var seen = Set<String>()
            return (evs[d] ?? []).filter { !$0.allDay }.compactMap { e in
                DayLayout.clip(start: e.start, end: e.end, day: d).map { TodayPlan.Span($0.start, max($0.end, $0.start + 15)) }
            }
            .filter { seen.insert("\($0)").inserted }
        }
        return WeekPlan.week(store.planning, start: start ?? store.today, now: now, days: days, events: spans)
    }

    /// A day's events as the Show row leaves them.
    private func shownEvents(_ evs: [String: [CalEvent]], _ day: String) -> [CalEvent] {
        let s = show
        guard s.shows(.ev) else { return [] }
        return (evs[day] ?? []).filter { !s.calendars.contains($0.calendarName) }
    }

    // MARK: the header

    private func header(_ w: WeekPlan.Week) -> some View {
        let first = w.days.first?.date ?? w.today, last = w.days.last?.date ?? w.today
        let over = w.overDays
        let spanWord = days == 7 ? "this week" : days == 35 ? "in these five weeks" : "in these \(days) days"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text(Self.range(first, last)).font(.nx(size: stacked ? 26 : 30, .bold, display: true)).foregroundStyle(Kit.ink).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("week-range")
                HStack(spacing: 2) {
                    Button { withAnimation(Kit.spring) { step(-1) } } label: { Image(systemName: "chevron.left").frame(width: 30, height: 30) }
                        .accessibilityLabel("Earlier")
                        .accessibilityIdentifier("week-prev")
                    Button("Today") { withAnimation(Kit.spring) { start = nil } }
                        .font(.nx(.subheadline, .medium)).lineLimit(1).fixedSize().padding(.horizontal, 6)
                        .accessibilityIdentifier("week-today")
                    Button { withAnimation(Kit.spring) { step(1) } } label: { Image(systemName: "chevron.right").frame(width: 30, height: 30) }
                        .accessibilityLabel("Later")
                        .accessibilityIdentifier("week-next")
                }
                .buttonStyle(.plain).foregroundStyle(Kit.muted)
                Spacer(minLength: 8)
                if !stacked { spanSwitch }
                Button { withAnimation(Kit.spring) { bankOpen.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "tray")
                        // the iPhone keeps it to the tray and the count, so the header stays on one line
                        if !stacked { Text("Task bank") }
                        Text("\(w.bank.count)").foregroundStyle(Kit.muted)
                    }
                    .lineLimit(1).fixedSize()
                }
                .buttonStyle(KitButtonStyle(kind: bankOpen ? .tone : .plain, small: true))
                .accessibilityLabel("Task bank")
                .accessibilityIdentifier("bank-toggle")
            }
            if stacked { spanSwitch.padding(.vertical, 4) }
            (Text("\(TimeWords.about(w.load)) planned \(spanWord). ")
                + (over.isEmpty ? Text("Every day fits its free time.")
                   : Text(Self.join(over.map { TodayView.weekday($0.date) }) + (over.count == 1 ? " is" : " are") + " over the free time.")
                        .foregroundColor(Theme.soon).fontWeight(.medium)))
                .font(.nx(.callout)).foregroundStyle(Kit.muted)
                .accessibilityIdentifier("week-sum")
        }
    }

    /// 2 days, 3 days, Week, Month.
    private var spanSwitch: some View {
        KitSwitch(items: Self.spans, selection: Binding(get: { days }, set: { n in span = n; picked = nil }))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan-span")
    }

    /// ‹ › move a whole view; the Month a week.
    private func step(_ dir: Int) {
        let next = Days.add(start ?? store.today, dir * (days == 35 ? 7 : days))
        start = next == store.today ? nil : next
        picked = nil
    }

    static func range(_ a: String, _ b: String) -> String {
        let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        func mon(_ s: String) -> String { m[max(0, min(11, (Int(s.dropFirst(5).prefix(2)) ?? 1) - 1))] }
        func day(_ s: String) -> Int { Int(s.suffix(2)) ?? 0 }
        return mon(a) == mon(b) ? "\(day(a))–\(day(b)) \(mon(b))" : "\(day(a)) \(mon(a)) – \(day(b)) \(mon(b))"
    }

    static func month(_ s: String) -> String {
        ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][max(0, min(11, (Int(s.dropFirst(5).prefix(2)) ?? 1) - 1))]
    }

    static func join(_ words: [String]) -> String {
        words.count <= 1 ? words.joined() : words.dropLast().joined(separator: ", ") + " and " + words.last!
    }

    // MARK: the Show row

    /// Show: Planned, Deadlines, Events; the subjects with work on these days; the calendars with events on them (when more than
    /// one); Show everything while something is hidden. Tap a pill to hide it, again to bring it back.
    private func showRow(_ w: WeekPlan.Week, _ evs: [String: [CalEvent]]) -> some View {
        let s = show
        let wss = s.pills(w)
        var cals: [(String, Color?)] = []
        for d in w.days { for e in evs[d.date] ?? [] where !cals.contains(where: { $0.0 == e.calendarName }) { cals.append((e.calendarName, e.color)) } }
        for c in s.calendars.sorted() where !cals.contains(where: { $0.0 == c }) { cals.append((c, nil)) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Show").font(.nx(size: 12.5, .semibold)).foregroundStyle(Kit.faint).padding(.trailing, 2)
                pill("Planned", on: s.shows(.plan), id: "show-plan") { update { $0.flip(.plan) } }
                pill("Deadlines", on: s.shows(.dl), id: "show-dl") { update { $0.flip(.dl) } }
                pill("Events", on: s.shows(.ev), id: "show-ev") { update { $0.flip(.ev) } }
                if !wss.isEmpty && (s.shows(.plan) || s.shows(.dl)) {
                    gap
                    ForEach(wss, id: \.self) { k in
                        let id = k == PlannerShow.inbox ? nil : k
                        pill(store.workstream(id)?.name ?? (k == PlannerShow.inbox ? "Inbox" : k), on: !s.workstreams.contains(k), id: "show-ws-\(k)",
                             dot: k == PlannerShow.inbox ? Kit.faint : store.color(workstream: id)) { update { $0.flip(workstream: k) } }
                    }
                }
                if cals.count > 1 && s.shows(.ev) {
                    gap
                    ForEach(cals.indices, id: \.self) { i in
                        let name = cals[i].0
                        pill(name.isEmpty ? "Calendar" : name, on: !s.calendars.contains(name), id: "show-cal-\(name)", dot: cals[i].1 ?? Kit.faint) {
                            update { $0.flip(calendar: name) }
                        }
                    }
                }
                if s.any {
                    Button("Show everything") { withAnimation(Kit.snap) { showText = "" } }
                        .font(.nx(size: 12.5, .medium)).foregroundStyle(Theme.accent).buttonStyle(.plain).padding(.leading, 6)
                        .accessibilityIdentifier("show-all")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-show")
    }

    private var gap: some View { Rectangle().fill(Kit.ink.opacity(0.08)).frame(width: 1, height: 18).padding(.horizontal, 4) }

    private func update(_ f: (inout PlannerShow) -> Void) {
        var s = show
        f(&s)
        withAnimation(Kit.snap) { showText = s.text }
    }

    /// One pill: a tick (or the subject's dot) and its name, filled while shown, struck out and faint while hidden.
    private func pill(_ title: String, on: Bool, id: String, dot: Color? = nil, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7).opacity(on ? 1 : 0.4) }
                else { Image(systemName: on ? "checkmark" : "circle.dashed").font(.system(size: 9, weight: .bold)) }
                Text(title).strikethrough(!on, color: Kit.faint).lineLimit(1)
            }
            .font(.nx(size: 12.5, on ? .medium : .regular))
            .foregroundStyle(on ? Kit.ink : Kit.faint)
            .padding(.horizontal, 10).frame(height: 28)
            .background(on ? Kit.rests : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Kit.ink.opacity(on ? 0 : 0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "shown" : "hidden")
        .accessibilityIdentifier(id)
    }

    // MARK: the days side by side (2 days, 3 days, Week)

    private func grid(_ w: WeekPlan.Week, _ evs: [String: [CalEvent]], width: CGFloat) -> some View {
        let n = CGFloat(max(1, w.days.count))
        let inner = width - 16
        let col = max(124, inner / n)
        let s = show
        let content = VStack(alignment: .leading, spacing: 0) {
            row(w, col) { d in DayHead(day: d, today: w.today) }
            if s.shows(.ev) {
                laneLabel("Events", icon: "calendar")
                row(w, col) { d in eventsCell(shownEvents(evs, d.date), d.date) }
            }
            if s.shows(.dl) {
                laneLabel("Deadlines", icon: "tag", count: w.days.reduce(0) { $0 + $1.deadlines.count })
                row(w, col) { d in VStack(alignment: .leading, spacing: 4) { ForEach(d.deadlines) { t in DeadlineChip(task: t) } } }
            }
            ForEach(Array(w.lanes.enumerated()), id: \.offset) { _, l in
                laneHead(l)
                row(w, col, drop: true) { d in
                    let i = w.days.firstIndex { $0.date == d.date } ?? 0
                    VStack(spacing: 6) { ForEach(l.days[i]) { t in PlanCard(task: t, day: d.date, today: w.today) } }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lane")
            }
            laneLabel(s.shows(.plan) ? "Drop a task on any day to plan it" : "Planned work is hidden (Show) · drop a task on a day to plan it", quiet: true)
            row(w, col, drop: true) { _ in Color.clear.frame(height: 34) }
        }
        .padding(8)
        .frame(width: col * n + 16, alignment: .leading)
        .kitSurface(Kit.rests, radius: 18)
        return Group {
            if col * n > inner + 1 {
                ScrollView(.horizontal, showsIndicators: true) { content }.scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            } else {
                content
            }
        }
    }

    /// One row of the days: a cell per day, today's on the accent wash; `drop`: a task dropped on a cell is planned that day.
    private func row<C: View>(_ w: WeekPlan.Week, _ col: CGFloat, drop: Bool = false, @ViewBuilder _ cell: @escaping (WeekPlan.Day) -> C) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(w.days, id: \.date) { d in
                cell(d)
                    .padding(.horizontal, 5).padding(.vertical, 4)
                    .frame(width: col, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(hot == d.date && drop ? Theme.accent.opacity(0.12) : d.date == w.today ? Kit.accentWash.opacity(0.7) : Color.clear)
                    .overlay(alignment: .leading) { if d.date != w.days.first?.date { Rectangle().fill(Kit.ink.opacity(0.05)).frame(width: 1) } }
                    .modifier(DayDrop(enabled: drop, day: d.date, hot: $hot) { ids in self.drop(ids, on: d.date, w) })
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func laneLabel(_ title: String, icon: String? = nil, count: Int? = nil, quiet: Bool = false) -> some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11)) }
            Text(title).fontWeight(quiet ? .regular : .semibold)
            if let count { Text("\(count)").foregroundStyle(Kit.faint) }
        }
        .font(.nx(size: 12.5)).foregroundStyle(quiet ? Kit.faint : Kit.muted)
        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func laneHead(_ l: WeekPlan.Lane) -> some View {
        let color = store.color(workstream: l.workstream)
        let name = store.workstream(l.workstream)?.name ?? "Inbox"
        return HStack(spacing: 7) {
            SubjectDot(color: color)
            Text(name).font(.nx(size: 12.5, .semibold)).foregroundStyle(Kit.ink)
            Text("\(l.count)" + (l.minutes > 0 ? " · " + TimeWords.dur(l.minutes) : "")).font(.nx(size: 12.5)).foregroundStyle(Kit.faint)
        }
        .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(color.opacity(0.55)).frame(height: 1.5) }
        .padding(.top, 6)
    }

    private func eventsCell(_ evs: [CalEvent], _ day: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if evs.isEmpty { Text("–").font(.nx(size: 12)).foregroundStyle(Kit.selected) }
            ForEach(evs.prefix(4)) { e in
                Button { eventSheet = .show(e.event) } label: {
                    (Text(e.allDay ? "all day " : Self.eventClock(e, day)) + Text(e.title).foregroundColor(Kit.ink).fontWeight(.medium))
                        .font(.nx(size: 11.5)).foregroundStyle(Kit.muted).lineLimit(1)
                        .padding(.leading, 7).padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) { Rectangle().fill(Kit.selected).frame(width: 2) }
                }
                .buttonStyle(.plain)
            }
            if evs.count > 4 { Text("+\(evs.count - 4) more").font(.nx(size: 11.5)).foregroundStyle(Kit.faint).padding(.leading, 7) }
        }
    }

    /// "9 ", "10:30 ": an event's start as the week says it.
    static func eventClock(_ e: CalEvent, _ day: String) -> String {
        guard let m = DayLayout.clip(start: e.start, end: e.end, day: day)?.start else { return "" }
        return TimeWords.clock(m).replacingOccurrences(of: ":00", with: "") + " "
    }

    // MARK: the days stacked (the iPhone)

    private func stackedDays(_ w: WeekPlan.Week, _ evs: [String: [CalEvent]]) -> some View {
        VStack(spacing: 10) {
            ForEach(w.days, id: \.date) { d in stackedDay(d, w, evs) }
        }
    }

    private func stackedDay(_ d: WeekPlan.Day, _ w: WeekPlan.Week, _ evs: [String: [CalEvent]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DayHead(day: d, today: w.today)
            let es = shownEvents(evs, d.date)
            if !es.isEmpty { eventsCell(es, d.date) }
            ForEach(d.deadlines) { t in DeadlineChip(task: t) }
            ForEach(d.planned) { t in PlanCard(task: t, day: d.date, today: w.today) }
            if d.planned.isEmpty && !d.past {
                Text(show.shows(.plan) ? "Nothing planned" : "Planned work is hidden").font(.nx(.caption)).foregroundStyle(Kit.faint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hot == d.date ? Theme.accent.opacity(0.12) : d.date == w.today ? Kit.accentWash.opacity(0.7) : Kit.rests,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .modifier(DayDrop(enabled: true, day: d.date, hot: $hot) { ids in self.drop(ids, on: d.date, w) })
    }

    // MARK: the Month

    /// Five weeks of days from the first shown, seven across, each with its load bar, its deadlines and its planned cards (every
    /// subject together), up to four and "+n more"; drop a card on a day to plan it there. On the iPhone a day shows its number, its
    /// load bar and a dot per card; tap it for its cards under the grid.
    private func month(_ w: WeekPlan.Week, _ evs: [String: [CalEvent]], width: CGFloat) -> some View {
        let spacing: CGFloat = stacked ? 3 : 6
        let col = max(30, (width - 6 * spacing) / 7)
        let rows = stride(from: 0, to: w.days.count, by: 7).map { Array(w.days[$0..<min($0 + 7, w.days.count)]) }
        let sel = picked.flatMap { p in w.days.first { $0.date == p } }
        return VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    ForEach(w.days.prefix(7), id: \.date) { d in
                        Text(TodayView.weekday(d.date, short: true)).font(.nx(size: 12, .semibold)).foregroundStyle(Kit.faint)
                            .frame(width: col)
                    }
                }
                ForEach(rows.indices, id: \.self) { r in
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(rows[r], id: \.date) { d in
                            monthDay(d, w, evs, col: col, first: d.date == w.days.first?.date)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("month")
            if stacked, let sel { stackedDay(sel, w, evs).accessibilityIdentifier("month-picked") }
        }
    }

    private func monthDay(_ d: WeekPlan.Day, _ w: WeekPlan.Week, _ evs: [String: [CalEvent]], col: CGFloat, first: Bool) -> some View {
        let isToday = d.date == w.today
        let n = Int(d.date.suffix(2)) ?? 0
        let label = n == 1 || first ? "\(n) \(Self.month(d.date))" : "\(n)"
        let pct = d.free > 0 ? min(1, Double(d.load) / Double(d.free)) : d.load > 0 ? 1 : 0
        let cards = d.planned
        let nEv = shownEvents(evs, d.date).count
        let selected = picked == d.date
        return VStack(alignment: .leading, spacing: stacked ? 3 : 4) {
            HStack(spacing: 4) {
                Text(stacked && n != 1 && !first ? "\(n)" : label)
                    .font(.nx(size: stacked ? 13 : 13.5, isToday ? .bold : .semibold))
                    .foregroundStyle(isToday ? Theme.accent : d.past ? Kit.faint : Kit.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if !stacked && d.load > 0 { Text(TimeWords.dur(d.load)).font(.nx(size: 11)).foregroundStyle(d.over ? Theme.soon : Kit.faint) }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Kit.selected)
                    Capsule().fill(d.over ? Theme.soon : Theme.accent).frame(width: g.size.width * pct)
                }
            }
            .frame(height: stacked ? 3 : 4)
            if stacked {
                // a dot per deadline (★ in the key colour) and per card, in its subject's colour
                let dots = d.deadlines.map { $0.key ? Theme.key : Kit.muted } + cards.map { store.color($0) }
                HStack(spacing: 2) {
                    ForEach(Array(dots.prefix(5).enumerated()), id: \.offset) { _, c in Circle().fill(c).frame(width: 5, height: 5) }
                    if dots.count > 5 { Text("+").font(.nx(size: 9, .bold)).foregroundStyle(Kit.faint) }
                }
                .frame(height: 6)
                if nEv > 0 { Image(systemName: "calendar").font(.system(size: 8)).foregroundStyle(Kit.faint) }
            } else {
                ForEach(d.deadlines) { t in DeadlineChip(task: t) }
                ForEach(cards.prefix(4)) { t in PlanCard(task: t, day: d.date, today: w.today, small: true) }
                if cards.count > 4 { Text("+\(cards.count - 4) more").font(.nx(size: 11)).foregroundStyle(Kit.faint) }
                if nEv > 0 {
                    Label("\(nEv)", systemImage: "calendar").font(.nx(size: 11)).foregroundStyle(Kit.faint).labelStyle(.titleAndIcon)
                }
            }
        }
        .padding(stacked ? 5 : 7)
        .frame(width: col, alignment: .topLeading)
        .frame(minHeight: stacked ? 58 : 118, alignment: .topLeading)
        .background(hot == d.date ? Theme.accent.opacity(0.14) : selected ? Theme.accent.opacity(0.10) : isToday ? Kit.accentWash.opacity(0.8) : Kit.rests,
                    in: RoundedRectangle(cornerRadius: stacked ? 9 : 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: stacked ? 9 : 12, style: .continuous).strokeBorder(selected ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5))
        .opacity(d.past ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if stacked { withAnimation(Kit.snap) { picked = picked == d.date ? nil : d.date } } }
        .modifier(DayDrop(enabled: true, day: d.date, hot: $hot) { ids in self.drop(ids, on: d.date, w) })
        .accessibilityElement(children: stacked ? .combine : .contain)
        .accessibilityLabel("\(label), \(cards.count) planned")
        .accessibilityAddTraits(stacked ? .isButton : [])
        .accessibilityIdentifier("month-day")
    }

    // MARK: dropping

    /// A task dropped on a day: moved from the day of this week it was on (else the day it slipped from), or planned that day.
    private func drop(_ ids: [String], on day: String, _ w: WeekPlan.Week) -> Bool {
        hot = nil
        var done = false
        for id in ids {
            guard let t = store.task(id), store.canEdit(t) else { continue }
            let from = w.days.map(\.date).first { $0 != day && t.plannedDays.contains($0) }
                ?? (t.plannedDays.allSatisfy { $0 < store.today } ? t.plannedDays.max() : nil)
            if from == nil && t.plannedDays.contains(day) { continue }
            withAnimation(Kit.spring) { store.move(t, from: from, to: day) }
            done = true
        }
        return done
    }

    // MARK: the task bank

    private func bank(_ w: WeekPlan.Week) -> some View {
        let f = Filter(rawValue: filter) ?? .all
        let g = BankGroup(rawValue: group) ?? .soonest
        let q = find.trimmingCharacters(in: .whitespaces).lowercased()
        let match = { (t: NexusTask, f: Filter) -> Bool in
            switch f {
            case .all: return true
            case .soon: return t.due.map { Days.between(w.today, $0) <= 3 } ?? false
            case .key: return t.key
            case .slipped: return w.slipped.contains(t.id)
            case .noDate: return t.due == nil
            }
        }
        let rows = w.bank.filter { t in
            (q.isEmpty || (t.text + " " + store.workstreamName(t)).lowercased().contains(q)) && match(t, f)
        }
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) { bankTitle(w); filters(w, f, match); Spacer(minLength: 8); tools(g) }
                VStack(alignment: .leading, spacing: 10) { bankTitle(w); ScrollView(.horizontal, showsIndicators: false) { filters(w, f, match) }; tools(g) }
            }
            ForEach(groups(rows, g, w.today), id: \.label) { grp in
                VStack(alignment: .leading, spacing: 8) {
                    if !grp.label.isEmpty {
                        HStack(spacing: 6) {
                            if let ws = grp.workstream { SubjectDot(color: store.color(workstream: ws)) }
                            Text(grp.label).font(.nx(size: 12.5, .semibold)).foregroundStyle(Kit.ink)
                            Text("\(grp.tasks.count)").font(.nx(size: 12.5)).foregroundStyle(Kit.faint)
                        }
                        .padding(.top, 4)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: stacked ? 260 : 220), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                        ForEach(grp.tasks) { t in BankCard(task: t, today: w.today, slipped: w.slipped.contains(t.id)) }
                    }
                }
            }
            if rows.isEmpty {
                Text(w.bank.isEmpty ? "Everything open is planned." : "Nothing matches.").font(.nx(.callout)).foregroundStyle(Kit.faint).padding(.vertical, 6)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hot == "bank" ? Theme.accent.opacity(0.10) : Kit.rests, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bank")
        // a planned card dropped on the bank loses the day of this week it was on
        .dropDestination(for: String.self) { ids, _ in
            hot = nil
            var done = false
            for id in ids {
                guard let t = store.task(id), store.canEdit(t), let day = w.days.map(\.date).first(where: { t.plannedDays.contains($0) }) else { continue }
                withAnimation(Kit.spring) { store.unplan(t, from: day) }
                done = true
            }
            return done
        } isTargeted: { on in if on { hot = "bank" } else if hot == "bank" { hot = nil } }
    }

    private func bankTitle(_ w: WeekPlan.Week) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Task bank").font(.nx(size: 17, .semibold, display: true)).foregroundStyle(Kit.ink)
            Text("\(w.bank.count) not planned · drag onto a day").font(.nx(.footnote)).foregroundStyle(Kit.faint).lineLimit(1)
        }
        .fixedSize()
    }

    private func filters(_ w: WeekPlan.Week, _ on: Filter, _ match: @escaping (NexusTask, Filter) -> Bool) -> some View {
        HStack(spacing: 14) {
            ForEach(Filter.allCases, id: \.self) { f in
                let n = w.bank.filter { match($0, f) }.count
                Button { withAnimation(Kit.snap) { filter = f.rawValue } } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue).foregroundStyle(f == on ? Kit.ink : Kit.muted)
                        Text("\(n)").foregroundStyle(Kit.faint)
                    }
                    .font(.nx(.subheadline, f == on ? .medium : .regular))
                    .padding(.vertical, 4)
                    .overlay(alignment: .bottom) { if f == on { Rectangle().fill(Theme.accent).frame(height: 2).offset(y: 3) } }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bank-filter-\(f.rawValue)")
            }
        }
        .fixedSize()
    }

    private func tools(_ g: BankGroup) -> some View {
        HStack(spacing: 10) {
            Picker("Group", selection: $group) {
                ForEach(BankGroup.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .frame(width: 270)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Kit.faint)
                TextField("Find", text: $find).font(.nx(.subheadline)).accessibilityIdentifier("bank-find")
            }
            .padding(.horizontal, 10).frame(width: stacked ? nil : 170, height: 32)
            .background(Kit.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private struct BankSection: Identifiable { var label: String; var workstream: String?; var tasks: [NexusTask]; var id: String { label } }

    private func groups(_ rows: [NexusTask], _ g: BankGroup, _ today: String) -> [BankSection] {
        let soonest = rows.enumerated().sorted { a, b in
            let da = a.element.due ?? "9999", db = b.element.due ?? "9999"
            return da != db ? da < db : a.offset < b.offset
        }.map(\.element)
        switch g {
        case .soonest:
            return [BankSection(label: "", tasks: soonest)]
        case .workstream:
            var out: [BankSection] = [], at: [String: Int] = [:]
            for t in rows {
                let k = store.workstreamName(t)
                if let i = at[k] { out[i].tasks.append(t) } else { at[k] = out.count; out.append(BankSection(label: k, workstream: t.workstream, tasks: [t])) }
            }
            return out
        case .deadline:
            var out: [BankSection] = [], at: [String: Int] = [:]
            for t in soonest {
                let k = t.due.map { d in Days.between(today, d) < 0 ? "Late" : Days.between(today, d) <= 7 ? "This week" : "Later" } ?? "No deadline"
                if let i = at[k] { out[i].tasks.append(t) } else { at[k] = out.count; out.append(BankSection(label: k, tasks: [t])) }
            }
            return out
        }
    }
}

/// A drop target for a day of the week, lit while a card is over it.
private struct DayDrop: ViewModifier {
    var enabled: Bool
    var day: String
    @Binding var hot: String?
    var drop: ([String]) -> Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: String.self) { ids, _ in drop(ids) } isTargeted: { on in
                if on { hot = day } else if hot == day { hot = nil }
            }
        } else {
            content
        }
    }
}

/// A day's head: "Fri · today", the date, "6h 15m  of 5h 45m free" and a bar that fills with the load (amber when over).
private struct DayHead: View {
    let day: WeekPlan.Day
    let today: String

    var body: some View {
        let isToday = day.date == today
        let pct = day.free > 0 ? min(1, Double(day.load) / Double(day.free)) : day.load > 0 ? 1 : 0
        VStack(alignment: .leading, spacing: 2) {
            Text(TodayView.weekday(day.date, short: true) + (isToday ? " · today" : ""))
                .font(.nx(size: 12, isToday ? .semibold : .regular)).foregroundStyle(isToday ? Theme.accent : Kit.muted)
            Text(String(Int(day.date.suffix(2)) ?? 0)).font(.nx(size: 20, .bold, display: true)).foregroundStyle(isToday ? Theme.accent : Kit.ink)
            HStack(spacing: 4) {
                Text(TimeWords.dur(day.load).isEmpty ? "0h" : TimeWords.dur(day.load))
                Spacer(minLength: 2)
                Text("of \(TimeWords.about(day.free)) free").lineLimit(1)
            }
            .font(.nx(size: 11)).foregroundStyle(day.over ? Theme.soon : Kit.faint)
            .fontWeight(day.over ? .medium : .regular)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Kit.selected)
                    Capsule().fill(day.over ? Theme.soon : Theme.accent).frame(width: g.size.width * pct)
                }
            }
            .frame(height: 5).padding(.top, 3)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("day-head")
    }
}

/// A deadline on its day: ★ ones in the key colour.
private struct DeadlineChip: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask

    var body: some View {
        Button { store.open(task) } label: {
            Text((task.key ? "★ " : "") + task.text)
                .font(.nx(size: 12)).foregroundStyle(task.key ? Theme.key : Kit.ink).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(task.key ? Theme.key.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Deadline: \(task.text)")
    }
}

/// The meta line of a planner card: its time, estimate and deadline (late in red, near in amber).
private func planMeta(_ t: NexusTask, day: String?, today: String) -> Text {
    var parts: [Text] = []
    if let day, let m = TodayPlan.clock(t.time(on: day)) { parts.append(Text(TimeWords.clock(m))) }
    let est = TodayPlan.minutes(t)
    if est > 0 { parts.append(Text(TimeWords.dur(est))) }
    if let d = t.due {
        let w = TimeWords.due(d, today: today)
        let n = Days.between(today, d)
        parts.append(Text(w.text).foregroundColor(w.late ? Theme.late : n <= 1 ? Theme.soon : Kit.faint))
    }
    return parts.enumerated().reduce(Text("")) { acc, p in p.offset == 0 ? p.element : acc + Text("  ") + p.element }
}

/// A task on a day of the week: tick, title, then its time, estimate and deadline, on its subject's edge. Drag it to another day or
/// back to the bank.
private struct PlanCard: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let day: String
    let today: String
    /// The Month's card: the tick and the title on one line, no meta line.
    var small = false

    var body: some View {
        let color = store.color(task)
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: small ? 5 : 7) {
                TickRing(task: task).scaleEffect(small ? 0.62 : 0.78).frame(width: small ? 14 : 18, height: small ? 14 : 18)
                Text((task.key ? "★ " : "") + task.text).font(.nx(size: small ? 11.5 : 13, .medium)).foregroundStyle(Kit.ink)
                    .lineLimit(small ? 1 : 3).multilineTextAlignment(.leading)
            }
            if !small {
                planMeta(task, day: day, today: today).font(.nx(size: 11)).foregroundStyle(Kit.faint).lineLimit(2)
                    .padding(.leading, 25)
            }
        }
        .padding(.leading, small ? 6 : 9).padding(.trailing, small ? 4 : 6).padding(.vertical, small ? 4 : 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kit.page)
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { store.open(task) }
        .contextMenu { TaskMenu(task: task, day: day) }
        .draggable(task.id) { dragPreview(task, color) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-card")
    }
}

/// A task in the bank: tick, title, its subject, estimate, deadline and "slipped".
private struct BankCard: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let today: String
    let slipped: Bool

    var body: some View {
        let color = store.color(task)
        HStack(alignment: .top, spacing: 9) {
            TickRing(task: task).scaleEffect(0.82).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text((task.key ? "★ " : "") + task.text).font(.nx(size: 14, .medium)).foregroundStyle(Kit.ink).lineLimit(2)
                (Text("● ").foregroundColor(color).font(.system(size: 7)) + Text(store.workstreamName(task) + "  ")
                    + planMeta(task, day: nil, today: today)
                    + (slipped ? Text("  slipped").foregroundColor(Theme.late) : Text("")))
                    .font(.nx(size: 12)).foregroundStyle(Kit.faint).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .background(Kit.page, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { store.open(task) }
        .contextMenu { TaskMenu(task: task, day: nil) }
        .draggable(task.id) { dragPreview(task, color) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bank-card")
    }
}

private func dragPreview(_ t: NexusTask, _ color: Color) -> some View {
    HStack(spacing: 7) { SubjectDot(color: color); Text(t.text).font(.nx(.subheadline, .medium)) }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Kit.page, in: RoundedRectangle(cornerRadius: 10))
}
