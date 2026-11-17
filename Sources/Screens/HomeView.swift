import SwiftUI
import NexusCore

/// Home, the laptop's first screen (its `home.js`): the day's greeting and one sentence of where it stands, the day brief, the key
/// dates, the Inbox while it has something in it (tick, add, open it), and "Where things stand" (slipped, waiting on, workstreams).
/// The iPad lays it out as the laptop does: the brief across, then the Inbox beside the figures. The iPhone puts the figures first as
/// one row of three numbers to glance at, then the key dates and the Inbox under them.
struct HomeView: View {
    @Environment(NexusStore.self) private var store
    var go: (Screen) -> Void = { _ in }
    @State private var adding = ""
    @State private var showAll = false
    @FocusState private var addFocused: Bool

    var body: some View {
        let p = store.planning
        GeometryReader { geo in
            let wide = geo.size.width > 760
            ScrollView {
                VStack(alignment: .leading, spacing: wide ? 22 : 16) {
                    header(p, wide: wide)
                    // the day brief (Claude's, or the plain one) and Plan with Claude, as at the top of the laptop's Home
                    DayBriefCard()
                    PlanWithClaudeButton(prominent: true)
                    if wide {
                        if !p.keyDates.isEmpty { keyStrip(p) }
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 18) {
                                if inbox(p).isEmpty { quietInbox } else { inboxCard(p) }
                            }
                            .frame(maxWidth: .infinity)
                            standCard(p).frame(width: min(380, geo.size.width * 0.38))
                        }
                    } else {
                        figureRow(p)
                        if !p.keyDates.isEmpty { keyStrip(p) }
                        if !inbox(p).isEmpty { inboxCard(p) }
                    }
                }
                .padding(wide ? 28 : 16)
                .padding(.bottom, 90) // clear of the iPhone's floating +
                .frame(maxWidth: 1100)
                .frame(maxWidth: .infinity)
            }
            .refreshable { store.reload() }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: the greeting

    private func header(_ p: Planning, wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.kicker(store.today)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(Self.greeting(Date())).font(wide ? .system(size: 40, weight: .bold) : .largeTitle.weight(.bold))
            Text(Self.hero(p)).font(wide ? .title3 : .body).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    static func kicker(_ iso: String) -> String {
        guard let d = Days.date(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: d)
    }

    /// The laptop's `greetingFor`.
    static func greeting(_ now: Date) -> String {
        let h = Calendar.current.component(.hour, from: now)
        return (h < 5 ? "Still up" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening") + "."
    }

    /// The laptop's hero sentence: "4 things planned today, about 5h 30m. 1 due today. 2 key dates ahead, the next in 3 days."
    static func hero(_ p: Planning) -> String {
        var s = ""
        let planned = p.planned(on: p.today).count
        let hours = p.load(on: p.today)
        let due = p.due(on: p.today).count
        if planned > 0 {
            s = "\(planned) \(planned == 1 ? "thing" : "things") planned today"
            if hours > 0 { s += ", about " + Self.hours(hours) }
            s += "."
        }
        if due > 0 { s += (s.isEmpty ? "" : " ") + "\(due) due today." }
        if s.isEmpty { s = p.slipped.isEmpty ? "Nothing planned today. A quiet day." : "Nothing planned today." }
        let keys = p.keyDates.filter { ($0.due ?? "") >= p.today }
        if let next = keys.first?.due {
            let n = Days.between(p.today, next)
            s += " \(keys.count) key \(keys.count == 1 ? "date" : "dates") ahead, the next \(n == 0 ? "today" : n == 1 ? "tomorrow" : "in \(n) days")."
        }
        return s
    }

    static func hours(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    // MARK: where things stand

    private struct Figure: Identifiable {
        let id: String
        let n: Int
        let label: String
        let sub: String
        let to: Screen
    }

    private func figures(_ p: Planning) -> [Figure] {
        let slipped = p.slipped
        let stale = slipped.filter { t in (t.plannedDays.max().map { Days.between($0, p.today) } ?? 0) > 14 }.count
        let waits = p.tasks(.waiting)
        let quiet = waits.filter { t in t.waitingSince.map { Days.between(String($0.prefix(10)), p.today) >= 7 } ?? false }.count
        let oldest = waits.compactMap { $0.waitingSince.map { Days.between(String($0.prefix(10)), p.today) } }.max()
        let streams = p.s.workstreams.values.filter { !$0.finished && !$0.parked }.count
        let open = p.open.count
        return [
            Figure(id: "slipped", n: slipped.count, label: "slipped",
                   sub: slipped.isEmpty ? "nothing passed its date unplanned" : "passed their date with no plan" + (stale > 0 ? ", \(stale) look stale" : ""),
                   to: .today),
            Figure(id: "waiting", n: waits.count, label: "waiting on",
                   sub: waits.isEmpty ? "nothing outstanding" : "oldest \(Self.age(oldest ?? 0))" + (quiet > 0 ? ", \(quiet) gone quiet" : ""),
                   to: .tasks),
            Figure(id: "projects", n: streams, label: "workstreams", sub: "\(open) open \(open == 1 ? "task" : "tasks")", to: .tasks),
        ]
    }

    /// The laptop's `ageLabel`: 5d, 3w, 2mo.
    static func age(_ d: Int) -> String { d < 14 ? "\(d)d" : d < 120 ? "\(d / 7)w" : "\(d / 30)mo" }

    /// The iPad's figure column, as the laptop's.
    private func standCard(_ p: Planning) -> some View {
        Card(title: "Where things stand", icon: "chart.bar") {
            ForEach(figures(p)) { f in
                Button { go(f.to) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(f.n)").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(f.n > 0 && f.id == "slipped" ? Theme.late : .primary)
                            .frame(minWidth: 44, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.label).font(.body.weight(.medium))
                            Text(f.sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-fig-\(f.id)")
            }
        }
    }

    /// The iPhone's: three numbers in a row, each a button to the place that owns it.
    private func figureRow(_ p: Planning) -> some View {
        HStack(spacing: 10) {
            ForEach(figures(p)) { f in
                Button { go(f.to) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(f.n)").font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(f.n > 0 && f.id == "slipped" ? Theme.late : .primary)
                        Text(f.label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home-fig-\(f.id)")
            }
        }
    }

    // MARK: key dates

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
                        .frame(width: 180, alignment: .leading)
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: the Inbox

    private func inbox(_ p: Planning) -> [NexusTask] { p.top(of: nil).filter { !$0.done && !$0.someday } }

    private func inboxCard(_ p: Planning) -> some View {
        let rows = inbox(p)
        let shown = showAll ? rows : Array(rows.prefix(7))
        return Card(title: "Inbox", count: rows.count, icon: "tray") {
            ForEach(shown) { t in
                VStack(spacing: 0) {
                    TaskRow(task: t, showWorkstream: false)
                    Divider().padding(.leading, 32)
                }
            }
            if rows.count > 7 {
                Button(showAll ? "Show fewer" : "Show \(rows.count - shown.count) more") { withAnimation(.snappy) { showAll.toggle() } }
                    .font(.callout)
            }
            addField
            HStack {
                Button("Open Inbox") { go(.inbox) }.font(.callout.weight(.medium))
                Spacer()
                FileInboxButton().font(.callout.weight(.medium)).buttonStyle(.borderless)
            }
            .padding(.top, 4)
        }
    }

    /// The Inbox empty on the iPad: one quiet line where the card would be (the laptop hides it; a wide screen keeps its shape).
    private var quietInbox: some View {
        Card(title: "Inbox", icon: "tray") {
            Text("Nothing to file.").font(.callout).foregroundStyle(.secondary)
            addField
        }
    }

    /// "Add a task": read as the add sheet reads it (a #workstream sends it there), landed straight away.
    private var addField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").foregroundStyle(Theme.accent).frame(width: 22)
            TextField("Add a task", text: $adding)
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit(add)
                .accessibilityIdentifier("home-add")
        }
        .padding(.vertical, 8)
        .disabled(store.snapshot.readOnlyReason != nil)
    }

    private func add() {
        let line = adding.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        // the add's own toast says where it went, with Undo
        if QuickAdd.add(line, store: store) != nil {
            adding = ""
            addFocused = true // ready for the next one
        }
    }
}
