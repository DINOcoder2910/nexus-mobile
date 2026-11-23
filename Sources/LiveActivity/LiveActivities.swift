import ActivityKit
import SwiftUI
import NexusCore

/// The iPhone's Live Activity (the extension that draws it: Widgets/NexusLiveActivity.swift): one card for the day (Nov 23 2026,
/// Murtaza: one big one with more on it, not one per thing). Its big row is the recording, else the running timer, else the task up
/// next, else "All done"; under it the other thing that runs or what comes next (a class from the calendar, a timed task); at its
/// foot today's ticks and the time tracked today. `refresh()` is called whenever the folder or the time files are read (a timer
/// started on the laptop shows once this phone has synced), when a recording starts, stops or gains a picture or a pin, and when
/// Nexus comes to the front.
///
/// Free signing has no push service, so the card only starts while Nexus is open on the phone; once it shows, its clocks count by
/// themselves, its buttons (LiveActivityIntents.swift) run in this app in the background and update it, and it is drawn again at
/// the next event's or task's time (its stale date) so the line under the big row moves on.
@MainActor
@Observable
final class LiveActivities {
    static let shared = LiveActivities()
    static let settingKey = "liveActivities.on"
    static let daySettingKey = "liveActivities.day"

    /// What shows now ("Timer: Redox worksheet", "Recording: Meeting", "Next up: …", "Day: All done for today"), for Settings and
    /// the tests.
    private(set) var showing: [String] = []
    /// Why it didn't start (the last time it tried).
    private(set) var problem: String?
    /// What happened to it lately (started, ended and why, what iOS said), newest last: shown under Settings' Lock Screen while
    /// the UI check runs, so a test that finds it gone can say why.
    private(set) var log: [String] = []
    @ObservationIgnored private var queued = false
    /// Swiped off the Lock Screen while showing this (`signature`): not put back until something else is on.
    @ObservationIgnored private var dismissed: String?

    /// Settings › Lock Screen › Live Activity (on unless turned off).
    static var on: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }
    /// Settings › Lock Screen › Show my day: the card stays while nothing runs (the next task, the day's ticks).
    static var day: Bool { UserDefaults.standard.object(forKey: daySettingKey) as? Bool ?? true }
    /// The iPhone has it; the iPad's download carries no extension (build.yml).
    static var supported: Bool { Device.isPhone }
    /// iOS lets Nexus show it (Settings › Nexus › Live Activities).
    static var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: keeping it in step

    /// Looks again soon (several changes in a row are one look). Callable from anywhere.
    nonisolated static func refresh() {
        Task { @MainActor in shared.queue() }
    }

    private func queue() {
        guard !queued else { return }
        queued = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.queued = false
            self.apply()
        }
    }

    /// What it is about, for "swiped off": a new timer, recording or next task is something else.
    private static func signature(_ s: NexusLiveState) -> String {
        let timed = s.focus == .timer || s.focus == .recording || (s.focus == .next && s.timed)
        return "\(s.focus.rawValue)|\(s.task)|\(timed ? "\(s.since.timeIntervalSince1970)" : "")"
    }

    /// Puts it on, updates it, or ends it.
    func apply() {
        guard Self.supported else { return }
        let all = Activity<NexusActivityAttributes>.activities
        for a in all where a.activityState == .dismissed { dismissed = Self.signature(a.content.state) }
        let live = all.filter { $0.activityState == .active || $0.activityState == .stale }
        guard Self.on, let found = Self.state() else {
            for a in live {
                note("end \(a.content.state.title): \(Self.on ? "nothing to show" : "turned off")")
                Task { await a.end(nil, dismissalPolicy: .immediate) }
            }
            showing = []
            problem = nil
            return
        }
        let (want, stale) = found
        let sig = Self.signature(want)
        if dismissed != nil && dismissed != sig { dismissed = nil }
        let content = ActivityContent(state: want, staleDate: stale)
        var problem: String?
        var shows = false
        if let a = live.first {
            for extra in live.dropFirst() { Task { await extra.end(nil, dismissalPolicy: .immediate) } }
            if a.content.state != want || a.content.staleDate != stale { Task { await a.update(content) } }
            shows = true
        } else if dismissed == nil && UIApplication.shared.applicationState == .active {
            // iOS starts one only while the app is in front (no push service under free signing): a timer started elsewhere shows
            // when Nexus is next opened
            do {
                let a = try Activity.request(attributes: NexusActivityAttributes(), content: content, pushType: nil)
                shows = true
                note("start \(want.title)")
                Task { [weak self] in
                    for await s in a.activityStateUpdates { self?.note("\(s)") }
                }
            } catch {
                note("couldn't start \(want.title): \(error.localizedDescription)")
                problem = Self.allowed ? "The Live Activity couldn't start: \(error.localizedDescription)" : "Live Activities are off for Nexus in the iPhone's Settings › Nexus."
                HangWatch.note("live activity: \(error)")
            }
        }
        self.problem = problem
        showing = shows ? Self.words(want) : []
    }

    private static func words(_ s: NexusLiveState) -> [String] {
        let head: String
        switch s.focus {
        case .timer: head = "Timer: "
        case .recording: head = "Recording: "
        case .next: head = "Next up: "
        case .clear: head = "Day: "
        }
        var out = [head + s.title]
        for l in s.lines where l.kind == .timer || l.kind == .recording { out.append((l.kind == .timer ? "Timer: " : "Recording: ") + l.title) }
        return out
    }

    private func note(_ s: String) {
        log.append(Date().formatted(date: .omitted, time: .standard) + " " + s)
        if log.count > 12 { log.removeFirst(log.count - 12) }
        HangWatch.note("live activity: " + s)
    }

    // MARK: what it shows

    /// The card now, and when it should be drawn again (the next event's or task's time); nil: nothing to show.
    static func state(now: Date = Date()) -> (NexusLiveState, Date?)? {
        let store = AppServices.store
        let cal = AppServices.calendar
        let tracker = TimeTracker.shared
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let mins = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let v = TodayPlan.day(store.planning, now: mins, events: { d in TodayEvents.spans(cal, d).map { TodayPlan.Span($0.start, $0.end) } })
        let timer = tracker.current
        let rec = RecordingService.shared.active
        guard timer != nil || rec != nil || day else { return nil }

        var s: NexusLiveState
        var lines: [NexusLiveLine] = []
        if let r = rec {
            s = recordingState(r.meta, began: r.began, filming: r.filming, store: store)
            if let e = timer, let t = timerState(e, store: store) {
                lines.append(.init(kind: .timer, title: t.title, at: t.since, light: t.light, dark: t.dark))
            }
        } else if let e = timer, let t = timerState(e, store: store) {
            s = t
        } else if let n = v.next {
            let hex = hex(of: n, store: store)
            let m = TodayPlan.minutes(n)
            // its time today, unless that is long gone (after midnight the app's day is still yesterday, whose 4 pm has passed)
            let at = TodayPlan.clock(v.time(n)).flatMap { t in Days.date(v.today).map { $0.addingTimeInterval(Double(t) * 60) } }
                .flatMap { $0 > now.addingTimeInterval(-Double(max(m, 30)) * 60) ? $0 : nil }
            var bits = [store.workstreamName(n)]
            if m > 0 { bits.append(NexusLive.spent(Double(m) * 60)) }
            if let at { bits.insert("Up next at " + at.formatted(date: .omitted, time: .shortened), at: 0) } else { bits.insert("Up next", at: 0) }
            s = .init(focus: .next, title: n.text, detail: bits.joined(separator: " · "), since: at ?? Days.date(v.today) ?? now, timed: at != nil, light: hex.light, dark: hex.dark,
                      task: n.id, minutes: m)
        } else {
            let done = v.done.count
            s = .init(focus: .clear, title: done > 0 ? "Today's list is done" : "Nothing planned today",
                      detail: done > 0 ? (done == 1 ? "1 task ticked off" : "\(done) tasks ticked off") : "Add a task in Nexus",
                      since: Days.date(v.today) ?? now, light: "#0F7A49", dark: "#4FD28F")
        }

        // what comes next: the calendar's timed events that haven't ended, and today's timed tasks still to start
        var next: [NexusLiveLine] = []
        if cal.eventsOnPlan && cal.canRead {
            var seen = Set<String>()
            for e in cal.events(on: v.today) where !e.allDay && e.end > now && seen.insert("\(e.title)|\(e.start)").inserted {
                let h = hex(e.color)
                next.append(.init(kind: .event, title: e.title, at: e.start, end: e.end, light: h, dark: h))
            }
        }
        for t in v.list where t.id != s.task {
            guard let m = TodayPlan.clock(v.time(t)), let d0 = Days.date(v.today) else { continue }
            let at = d0.addingTimeInterval(Double(m) * 60)
            guard at > now else { continue }
            let h = hex(of: t, store: store)
            next.append(.init(kind: .task, title: t.text, at: at, light: h.light, dark: h.dark))
        }
        next.sort { $0.at < $1.at }
        lines += next.prefix(3 - lines.count)
        s.lines = lines

        s.done = v.done.count
        s.total = v.done.count + v.list.count
        s.tracked = TimeLog.daySeconds(tracker.entries, store.today, now: now)
        s.counting = timer != nil
        // the tracked time counts on from `stamp` only while a timer runs (else a new stamp would update the card for nothing)
        s.stamp = timer != nil ? now : Days.date(v.today) ?? now

        // drawn again when the line under the big row should move on, or the next task's time comes
        var times = next.map { $0.kind == .event && $0.at <= now ? ($0.end ?? $0.at) : $0.at }
        if s.focus == .next && s.timed && s.since > now { times.append(s.since) }
        return (s, times.filter { $0 > now }.min())
    }

    static func timerState(_ e: TimeLog.Entry, store: NexusStore) -> NexusLiveState? {
        guard let since = e.startDate else { return nil }
        let s = store.snapshot
        let t = s.tasks[e.task]
        let w = t.flatMap { store.workstream($0.workstream) }
        var bits: [String] = []
        if let w { bits.append(w.name) }
        let m = t.map { TodayPlan.minutes($0) } ?? 0
        if m > 0 { bits.append("of " + NexusLive.spent(Double(m) * 60)) }
        if !e.device.isEmpty && e.device != TimeTracker.device { bits.append("started on the \(deviceWord(e.device))") }
        if bits.isEmpty { bits.append("Time tracking") }
        let hex = w.map { Theme.workstreamHex($0.color, key: $0.id) } ?? (light: "#0F7A49", dark: "#4FD28F")
        return .init(focus: .timer, title: TimeTracker.shared.title(e, in: s), detail: bits.joined(separator: " · "), since: since,
                     light: hex.light, dark: hex.dark, task: e.task, minutes: m)
    }

    static func recordingState(_ m: Recordings.Meta, began: Date, filming: Bool, store: NexusStore) -> NexusLiveState {
        // the kind as the title ("Class", "Meeting"); the red badge says it records
        var bits: [String] = [filming ? "Filming" : "Recording"]
        if let sub = m.subject, let w = store.workstream(sub) { bits.append(w.name) }
        let pics = m.pictures.count, pins = m.pins.count
        if pics > 0 { bits.append(pics == 1 ? "1 picture" : "\(pics) pictures") }
        if pins > 0 { bits.append(pins == 1 ? "1 pin" : "\(pins) pins") }
        if bits.count == 1 { bits.append("since " + began.formatted(date: .omitted, time: .shortened)) }
        return .init(focus: .recording, title: m.kind.word, detail: bits.joined(separator: " · "), since: began, light: "#B3261E", dark: "#FF8A80", filming: filming)
    }

    private static func hex(of t: NexusTask, store: NexusStore) -> (light: String, dark: String) {
        store.workstream(t.workstream).map { Theme.workstreamHex($0.color, key: $0.id) } ?? (light: "#556B82", dark: "#A2BAD4")
    }

    /// A calendar's colour as hex.
    private static func hex(_ c: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#556B82" }
        let v = { (x: CGFloat) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v(r), v(g), v(b))
    }

    static func deviceWord(_ d: String) -> String {
        switch d {
        case "laptop": return "laptop"
        case "ipad": return "iPad"
        case "iphone": return "iPhone"
        default: return d
        }
    }

    // MARK: the buttons (LiveActivityIntents.swift: iOS runs them here, often with Nexus in the background)

    static func stopTimer() async {
        AppServices.start()
        let store = AppServices.store
        store.reloadIfChanged()
        TimeTracker.shared.stop(store: store)
        shared.apply()
        // send it to the hub now: the app may go back to sleep straight after
        await AppServices.sync.backgroundCycle(store)
    }

    /// Start on the next task: a time now (to the five minutes) when it has none or a later one, and the timer on it.
    static func startTask(_ id: String) async {
        AppServices.start()
        let store = AppServices.store
        store.reloadIfChanged()
        guard let t = store.task(id), store.canEdit(t) else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let at = TodayPlan.clock(t.time(on: store.today))
        if at == nil || at! > now { store.setTime(t, on: store.today, TimeWords.hm(now / 5 * 5)) }
        if let t = store.task(id) { TimeTracker.shared.start(t, store: store) }
        shared.apply()
        await AppServices.sync.backgroundCycle(store)
    }

    /// The tick: the task is done, and its timer stops.
    static func tickTask(_ id: String) async {
        AppServices.start()
        let store = AppServices.store
        store.reloadIfChanged()
        guard let t = store.task(id), !t.done, store.canEdit(t) else { return }
        store.toggleDone(t)
        shared.apply()
        await AppServices.sync.backgroundCycle(store)
    }

    static func stopRecording() async {
        AppServices.start()
        // the sound is saved before this returns; turning it into words carries on while iOS lets it (and on the next open if not)
        await RecordingService.shared.stop(waitForWords: false)
        shared.apply()
    }

    static func pinMoment() async {
        RecordingService.shared.pin("important")
    }

}

/// Settings › Lock Screen (the iPhone): the Live Activity on or off, whether it stays while nothing runs, what shows now, and how it
/// looks.
struct LiveActivitySettings: View {
    @AppStorage(LiveActivities.settingKey) private var on = true
    @AppStorage(LiveActivities.daySettingKey) private var day = true
    @State private var live = LiveActivities.shared

    var body: some View {
        if LiveActivities.supported {
            Section {
                Toggle("Live Activity", isOn: $on)
                    .accessibilityIdentifier("live-toggle")
                    .onChange(of: on) { _, _ in live.apply() }
                if on {
                    Toggle("Show my day when nothing runs", isOn: $day)
                        .accessibilityIdentifier("live-day")
                        .onChange(of: day) { _, _ in live.apply() }
                    LabeledContent("Showing now") {
                        Text(live.showing.isEmpty ? "Nothing" : live.showing.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("live-status")
                    }
                    if let p = live.problem { Label(p, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                    NavigationLink("See how it looks") { LiveActivityPreview() }
                        .accessibilityIdentifier("live-preview")
                    if ProcessInfo.processInfo.arguments.contains("-NexusTestTime") {
                        Text(live.log.isEmpty ? "no log" : live.log.joined(separator: " | "))
                            .font(.nx(.caption2)).foregroundStyle(.secondary)
                            .accessibilityIdentifier("live-log")
                    }
                }
            } header: { Text("Lock Screen") } footer: {
                Text("One Nexus card on the Lock Screen and in the Dynamic Island: a recording or the running timer (with Stop and the tick), else the task up next (with Start), what comes after it, and today's ticks and time tracked. It starts while Nexus is open on this iPhone; a timer started on the laptop shows the next time you open Nexus here.")
            }
            .onAppear { live.apply() }
        }
    }
}

/// How the Live Activity looks (Settings › Lock Screen › See how it looks): the Lock Screen card and the Dynamic Island, drawn with
/// the extension's own views, on what shows now and on an example of each kind.
struct LiveActivityPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, x in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(x.0).font(.nx(.subheadline, .semibold)).foregroundStyle(.secondary)
                        NexusLiveLockView(state: x.1)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(8)
                            .background(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.36), Color(red: 0.38, green: 0.22, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                            .environment(\.colorScheme, .dark)
                        island(x.1)
                    }
                }
                Text("Hold the Dynamic Island to open it: the card's rows and buttons. Tap the card to open its task, Recordings or Today.")
                    .font(.nx(.footnote)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.top, 20)
            // clear of the tab bar and the timer's pill
            .padding(.bottom, 140)
            // a picture: its buttons would act on the real timer
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("live-preview-lock")
        }
        .navigationTitle("Live Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The Dynamic Island, closed.
    private func island(_ s: NexusLiveState) -> some View {
        HStack(spacing: 0) {
            NexusLiveIcon(state: s, size: 22)
            Spacer(minLength: 70)
            Group {
                if s.clocks(Date()) { NexusLiveClock(state: s) } else { Text(s.total > 0 ? "\(s.done)/\(s.total)" : "").monospacedDigit() }
            }
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 56)
        }
        .padding(.horizontal, 10).frame(width: 250, height: 37)
        .background(Color.black, in: Capsule())
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity)
    }

    /// What shows now, then an example of each other kind.
    private var examples: [(String, NexusLiveState)] {
        let now = Date()
        let green = (light: "#0F7A49", dark: "#4FD28F"), blue = (light: "#1D5FB8", dark: "#7FB2FF"), amber = (light: "#9A5B00", dark: "#F2B45A")
        let cls = NexusLiveLine(kind: .event, title: "Chemistry HL", at: now.addingTimeInterval(1500), end: now.addingTimeInterval(5100), light: blue.light, dark: blue.dark)
        var timer = NexusLiveState(focus: .timer, title: "Redox worksheet", detail: "Chemistry HL · of 1h", since: now.addingTimeInterval(-1520),
                                   light: green.light, dark: green.dark, task: "x", minutes: 60, lines: [cls], done: 3, total: 7,
                                   tracked: 8100, counting: true, stamp: now)
        var rec = NexusLiveState(focus: .recording, title: "Class", detail: "Recording · Chemistry HL · 2 pictures", since: now.addingTimeInterval(-754),
                                 light: "#B3261E", dark: "#FF8A80",
                                 lines: [.init(kind: .timer, title: "Redox worksheet", at: now.addingTimeInterval(-1520), light: green.light, dark: green.dark)],
                                 done: 3, total: 7, tracked: 8100, counting: true, stamp: now)
        let next = NexusLiveState(focus: .next, title: "TOK essay draft", detail: "Up next at " + now.addingTimeInterval(900).formatted(date: .omitted, time: .shortened) + " · TOK · 1h",
                                  since: now.addingTimeInterval(900), light: amber.light, dark: amber.dark, task: "x", minutes: 60, lines: [cls],
                                  done: 3, total: 7, tracked: 8100, stamp: now)
        timer.lines = [cls]
        rec.lines = rec.lines + [cls]
        var out: [(String, NexusLiveState)] = []
        if LiveActivities.on, let found = LiveActivities.state(now: now) { out.append(("Now", found.0)) }
        let others: [(String, NexusLiveState)] = [("While a timer runs", timer), ("While recording", rec), ("When nothing runs", next)]
        let shown = out.first?.1.focus
        out += others.filter { $0.1.focus != shown }
        return out
    }
}
