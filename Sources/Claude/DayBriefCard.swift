import SwiftUI
import NexusCore

/// Claude's written day brief (the laptop's app/briefai.js): at most one call a day on its own, with the cheap model, from the planner's
/// facts only (no files read); kept on this device for the day, so opening Home again does not ask again; Refresh asks again. Off in
/// Settings › Claude, or when Claude can't be reached: then the plain-logic brief shows, and a failure is not retried until tomorrow.
@MainActor
@Observable
final class DayBriefWriter {
    static let shared = DayBriefWriter()
    private(set) var cache: DayBrief.Cache?
    private(set) var busy = false
    private(set) var error: String?
    @ObservationIgnored private var triedDay = ""

    static let onKey = "claude.brief"
    static let modelKey = "claude.briefModel"
    private static let cacheKey = "claude.briefCache"

    /// Settings › Claude › Day brief written by Claude (on unless turned off).
    var on: Bool = UserDefaults.standard.object(forKey: "claude.brief") as? Bool ?? true {
        didSet { UserDefaults.standard.set(on, forKey: Self.onKey) }
    }
    var model: String { UserDefaults.standard.string(forKey: Self.modelKey) ?? "haiku" }

    init() {
        if !ClaudeDemo.active, let d = UserDefaults.standard.data(forKey: Self.cacheKey) { cache = try? JSONDecoder().decode(DayBrief.Cache.self, from: d) }
    }

    /// Today's written brief, or nil (the plain one shows).
    func text(today: String) -> String? { on ? cache.flatMap { $0.valid(today: today) ? $0.text : nil } : nil }

    /// Once a day on its own: writes today's brief when there is none yet and it was not tried today.
    func ensure(_ store: NexusStore, calendar: CalendarStore) {
        guard on, store.snapshot.isDataFolder, !busy, triedDay != store.today, !(cache?.valid(today: store.today) ?? false) else { return }
        Task { await write(store, calendar: calendar) }
    }

    func write(_ store: NexusStore, calendar: CalendarStore) async {
        guard !busy else { return }
        let day = store.today
        busy = true; error = nil; triedDay = day
        defer { busy = false }
        let p = store.planning
        let base = DayBrief.build(p)
        var events: [(title: String, start: String)] = []
        if calendar.canRead {
            events = calendar.events(on: day).filter { !$0.allDay }.prefix(6).map { (title: $0.title, start: ClaudeConversation.clock($0.start)) }
        }
        let req = ClaudeRequest(model: model, system: DayBrief.system, messages: [.user(DayBrief.prompt(DayBrief.facts(p, brief: base, events: events)))], maxTokens: 400)
        do {
            let r = try await ClaudeConversation.ask(req) { _ in }
            guard let text = DayBrief.clean(r.text) else { error = "Claude's brief was empty or too long, so the plain summary stays."; return }
            let c = DayBrief.Cache(day: day, text: text, model: model, generatedAt: Date().timeIntervalSince1970)
            cache = c
            if !ClaudeDemo.active, let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: Self.cacheKey) }
        } catch {
            self.error = (error as? ClaudeError)?.message ?? error.localizedDescription
        }
    }
}

/// The day brief for the top of Home: the plain-logic brief, or Claude's when it has written today's, with Refresh and the Plan / API
/// chip. `showsGreeting`: the "Good morning." line above it (Home's header may show its own).
struct DayBriefCard: View {
    var showsGreeting = false
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var calendar
    private var writer: DayBriefWriter { .shared }

    var body: some View {
        let base = DayBrief.build(store.planning)
        let written = writer.text(today: store.today)
        VStack(alignment: .leading, spacing: 10) {
            if showsGreeting { Text(base.greeting).font(.title2.weight(.semibold)) }
            Text(written ?? base.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("day-brief")
            HStack(spacing: 10) {
                if written != nil {
                    Label("Written by Claude", systemImage: "sparkles").font(.caption).foregroundStyle(Theme.claude)
                } else if writer.busy {
                    ProgressView().controlSize(.mini)
                    Text("Claude is writing today's brief…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if writer.on {
                    Button {
                        Task { await writer.write(store, calendar: calendar) }
                    } label: {
                        Label(written == nil ? "Write with Claude" : "Refresh", systemImage: "arrow.clockwise").font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .disabled(writer.busy)
                    ClaudeModeChip(small: true)
                }
            }
            if let e = writer.error, written == nil, !writer.busy {
                Text(e).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .task(id: store.today) { writer.ensure(store, calendar: calendar) }
    }
}
