import ActivityKit
import SwiftUI
import NexusCore

/// The iPhone's Live Activities (the extension that draws them: Widgets/NexusLiveActivity.swift): the running timer, and the
/// recording. Whatever runs here is put on the Lock Screen and in the Dynamic Island, and taken off when it stops; `refresh()` is
/// called whenever the time files are read (a timer started on the laptop shows once this phone has synced) and whenever a
/// recording starts, stops or gains a picture or a pin.
///
/// Free signing has no push service, so an activity only starts while Nexus is open on the phone; once it shows, its clock counts by
/// itself and its buttons (LiveActivityIntents.swift) run in this app in the background.
@MainActor
@Observable
final class LiveActivities {
    static let shared = LiveActivities()
    static let settingKey = "liveActivities.on"

    /// What shows now, one line each ("Redox worksheet", "Meeting"), for Settings and the tests.
    private(set) var showing: [String] = []
    /// Why one didn't start (the last time it tried).
    private(set) var problem: String?
    @ObservationIgnored private var queued = false
    /// Swiped off the Lock Screen: not put back while it runs.
    @ObservationIgnored private var dismissed: Set<NexusActivityAttributes> = []

    /// Settings › Live Activities (on unless turned off).
    static var on: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true }
    /// The iPhone has them; the iPad's download carries no extension (build.yml).
    static var supported: Bool { Device.isPhone }
    /// iOS lets Nexus show them (Settings › Nexus › Live Activities).
    static var allowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: keeping them in step

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

    /// Puts on what runs, updates what changed, ends what stopped. One swiped off the Lock Screen stays off until that timer or
    /// recording ends.
    func apply() {
        guard Self.supported else { return }
        let want = Self.on ? wanted() : []
        let all = Activity<NexusActivityAttributes>.activities
        for a in all where a.activityState == .dismissed { dismissed.insert(a.attributes) }
        dismissed = dismissed.filter { d in want.contains { $0.attributes == d } }
        let live = all.filter { $0.activityState == .active || $0.activityState == .stale }
        for a in live where !want.contains(where: { $0.attributes == a.attributes }) {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        var problem: String?
        var shown: [String] = []
        for w in want where !dismissed.contains(w.attributes) {
            if let a = live.first(where: { $0.attributes == w.attributes }) {
                if a.content.state != w.state { Task { await a.update(ActivityContent(state: w.state, staleDate: nil)) } }
                shown.append(w.state.title)
            } else if UIApplication.shared.applicationState == .active {
                // iOS starts one only while the app is in front (no push service under free signing): a timer started elsewhere shows when Nexus is next opened
                do {
                    _ = try Activity.request(attributes: w.attributes, content: ActivityContent(state: w.state, staleDate: nil), pushType: nil)
                    shown.append(w.state.title)
                } catch {
                    problem = Self.allowed ? "The Live Activity couldn't start: \(error.localizedDescription)" : "Live Activities are off for Nexus in the iPhone's Settings › Nexus."
                    HangWatch.note("live activity: \(error)")
                }
            }
        }
        self.problem = problem
        showing = shown
    }

    private struct Want { var attributes: NexusActivityAttributes; var state: NexusLiveState }

    private func wanted() -> [Want] {
        let store = AppServices.store
        var out: [Want] = []
        if let e = TimeTracker.shared.current, let s = Self.timerState(e, store: store) {
            out.append(.init(attributes: .init(kind: .timer, key: e.task + "|" + e.start, task: e.task), state: s))
        }
        if let r = RecordingService.shared.active {
            out.append(.init(attributes: .init(kind: .recording, key: r.path), state: Self.recordingState(r.meta, began: r.began, filming: r.filming, store: store)))
        }
        return out
    }

    // MARK: what each shows

    static func timerState(_ e: TimeLog.Entry, store: NexusStore) -> NexusLiveState? {
        guard let since = e.startDate else { return nil }
        let s = store.snapshot
        let w = s.tasks[e.task].flatMap { store.workstream($0.workstream) }
        var bits: [String] = []
        if let w { bits.append(w.name) }
        if !e.device.isEmpty && e.device != TimeTracker.device { bits.append("started on the \(deviceWord(e.device))") }
        if bits.isEmpty { bits.append("Time tracking") }
        let hex = w.map { Theme.workstreamHex($0.color, key: $0.id) } ?? (light: "#0F7A49", dark: "#4FD28F")
        return .init(title: TimeTracker.shared.title(e, in: s), detail: bits.joined(separator: " · "), since: since, light: hex.light, dark: hex.dark)
    }

    static func recordingState(_ m: Recordings.Meta, began: Date, filming: Bool, store: NexusStore) -> NexusLiveState {
        // the kind as the title ("Class", "Meeting"); the red badge says it records
        let title = m.kind.word
        var bits: [String] = [filming ? "Filming" : "Recording"]
        if let sub = m.subject, let w = store.workstream(sub) { bits.append(w.name) }
        let pics = m.pictures.count, pins = m.pins.count
        if pics > 0 { bits.append(pics == 1 ? "1 picture" : "\(pics) pictures") }
        if pins > 0 { bits.append(pins == 1 ? "1 pin" : "\(pins) pins") }
        if bits.count == 1 { bits.append("since " + began.formatted(date: .omitted, time: .shortened)) }
        return .init(title: title, detail: bits.joined(separator: " · "), since: began, light: "#B3261E", dark: "#FF8A80", icon: m.kind.icon, filming: filming)
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

/// Settings › Live Activities (the iPhone): on or off, what shows now, and how it looks.
struct LiveActivitySettings: View {
    @AppStorage(LiveActivities.settingKey) private var on = true
    @State private var live = LiveActivities.shared

    var body: some View {
        if LiveActivities.supported {
            Section {
                Toggle("Live Activities", isOn: $on)
                    .accessibilityIdentifier("live-toggle")
                    .onChange(of: on) { _, _ in live.apply() }
                if on {
                    LabeledContent("Showing now") {
                        Text(live.showing.isEmpty ? "Nothing" : live.showing.joined(separator: ", "))
                            .accessibilityIdentifier("live-status")
                    }
                    if let p = live.problem { Label(p, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
                    NavigationLink("See how it looks") { LiveActivityPreview() }
                        .accessibilityIdentifier("live-preview")
                }
            } header: { Text("Lock Screen") } footer: {
                Text("The running timer and a recording show on the Lock Screen and in the Dynamic Island, with Stop (and Pin and Snap while recording). One starts while Nexus is open on this iPhone; a timer started on the laptop shows the next time you open Nexus here.")
            }
            .onAppear { live.apply() }
        }
    }
}

/// How the Live Activities look (Settings › Live Activities › See how it looks): the Lock Screen cards and the Dynamic Island,
/// drawn with the extension's own views, on what runs now or on an example.
struct LiveActivityPreview: View {
    @Environment(NexusStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Lock Screen").font(.nx(.subheadline, .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    ForEach(Array(examples.enumerated()), id: \.offset) { _, x in
                        NexusLiveLockView(kind: x.0, state: x.1)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .environment(\.colorScheme, .dark)
                    }
                }
                .padding(8)
                .background(LinearGradient(colors: [Color(red: 0.16, green: 0.22, blue: 0.36), Color(red: 0.38, green: 0.22, blue: 0.42)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                // a picture: its buttons would act on the real timer
                .allowsHitTesting(false)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("live-preview-lock")

                Text("Dynamic Island").font(.nx(.subheadline, .semibold)).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    ForEach(Array(examples.enumerated()), id: \.offset) { _, x in
                        HStack(spacing: 0) {
                            NexusLiveIcon(kind: x.0, state: x.1, size: 22)
                            Spacer(minLength: 70)
                            NexusLiveClock(state: x.1).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 56)
                        }
                        .padding(.horizontal, 10).frame(width: 250, height: 37)
                        .background(Color.black, in: Capsule())
                        .environment(\.colorScheme, .dark)
                    }
                }
                .frame(maxWidth: .infinity)
                Text("Hold the Dynamic Island to open it: the title, the clock and the buttons. Tap a timer to open its task, a recording to open Recordings.")
                    .font(.nx(.footnote)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 20)
        }
        .navigationTitle("Live Activities")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What runs now, or an example of each.
    private var examples: [(NexusActivityAttributes.Kind, NexusLiveState)] {
        let now = Date()
        let timer = TimeTracker.shared.current.flatMap { LiveActivities.timerState($0, store: store) }
            ?? .init(title: "Redox worksheet", detail: "Chemistry HL", since: now.addingTimeInterval(-1520), light: "#0F7A49", dark: "#4FD28F")
        let rec = RecordingService.shared.active.map { LiveActivities.recordingState($0.meta, began: $0.began, filming: $0.filming, store: store) }
            ?? .init(title: "Class", detail: "Recording · Chemistry HL · 2 pictures", since: now.addingTimeInterval(-754), light: "#B3261E", dark: "#FF8A80", icon: "graduationcap")
        return [(.timer, timer), (.recording, rec)]
    }
}
