import SwiftUI
import NexusCore

/// One run of Plan with Claude: what it placed on today (accepted at once, as on the laptop, with one Undo for the run), and how it ended.
@MainActor
@Observable
final class PlanRun {
    private(set) var placedTitles: [String] = []
    @ObservationIgnored private(set) var placedIds: [UUID] = []
    private(set) var done = false
    /// Changes in the run that wait for Accept (anything that is not a placement on today).
    private(set) var waiting = 0
    /// Claude's last words ("Everything fitted."), or what went wrong.
    private(set) var summary: String?
    private(set) var failed = false
    private(set) var undone = false

    func placed(_ id: UUID, title: String) { placedIds.append(id); placedTitles.append(title) }

    func finished(_ c: ClaudeConversation) {
        done = true
        waiting = c.pendingCount
        if let last = c.items.last, last.kind == .note { summary = last.text; failed = last.retry }
        else { summary = c.items.last { $0.kind == .claude }?.text }
    }

    func finish(saying s: String) { done = true; summary = s }

    func undo(_ c: ClaudeConversation) {
        for id in placedIds.reversed() { c.undo(id) }
        undone = true
    }
}

/// Plan with Claude (the laptop's on Home and Today, compose-day.js): Claude places what slipped into today's free time. Each placement on
/// today is saved at once (you pressed Plan; Undo puts the whole run back); any other change waits in the conversation for Accept.
@MainActor
@Observable
final class PlanWithClaude {
    static let shared = PlanWithClaude()
    private(set) var run: PlanRun?

    var running: Bool { run.map { !$0.done } ?? false }

    func start(_ store: NexusStore, calendar: CalendarStore) {
        let c = ClaudeChatSession.shared.conversation("main")
        guard !running, !c.busy else { return }
        let r = PlanRun()
        run = r
        let p = store.planning
        let slipped = ClaudeChat.slippedForPlan(p)
        if slipped.isEmpty { r.finish(saying: "Nothing has slipped, so today stays as you planned it."); return }
        let today = store.today
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let nowMin = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        var busy: [(Int, Int)] = []
        if calendar.canRead {
            for e in calendar.events(on: today) where !e.allDay {
                if let m = DayLayout.clip(start: e.start, end: e.end, day: today) { busy.append((m.start, max(m.end, m.start + 15))) }
            }
        }
        for t in p.planned(on: today) {
            if let s = DayLayout.minutes(t.time(on: today)) { busy.append((s, s + Int(((p.estimate(t) ?? 0.5) * 60).rounded()))) }
        }
        let range = ClaudeChat.dayRange(busy: busy)
        let gaps = ClaudeChat.freeGaps(busy: busy, from: range.0, to: range.1, now: nowMin)
        var files: [(path: String, text: String)] = []
        for path in slipped.map(\.path) where !files.contains(where: { $0.path == path }) {
            if let t = try? FolderAccess.read(store.folder.appendingPathComponent(path)) { files.append((path: path, text: t)) }
        }
        c.looking = "Today"
        c.run(shown: "Plan my day", prompt: ClaudeChat.planPrompt(today: today, nowMinute: nowMin, slipped: slipped, gaps: gaps, files: files), plan: r)
    }

    func dismiss() { if !running { run = nil } }
}

/// The Plan with Claude button with its progress and result line, for Today and Home. `prominent`: the screen's main button (Home).
struct PlanWithClaudeButton: View {
    var prominent = false
    /// false: only the progress and result line (Today's header has its own button).
    var buttonShown = true
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var calendar
    private var plan: PlanWithClaude { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if buttonShown { HStack(spacing: 8) {
                Button { plan.start(store, calendar: calendar) } label: {
                    Label(plan.running ? "Planning…" : "Plan with Claude", systemImage: "sparkles")
                        .font(.nx(.callout, .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(prominent ? Theme.accent : Theme.claude)
                .disabled(plan.running || !store.snapshot.isDataFolder || store.snapshot.readOnlyReason != nil)
                .accessibilityIdentifier("plan-with-claude")
                ClaudeModeChip(small: true)
                if plan.running { ProgressView().controlSize(.small) }
            } }
            if let r = plan.run { result(r) }
        }
        .animation(.snappy, value: plan.run?.done)
    }

    @ViewBuilder
    private func result(_ r: PlanRun) -> some View {
        let c = ClaudeChatSession.shared.conversation("main")
        if !r.done {
            Text(c.status ?? "Working on your day").font(.nx(.callout)).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if r.undone {
                    Text("Put back as it was.").font(.nx(.callout)).foregroundStyle(.secondary)
                } else if !r.placedTitles.isEmpty {
                    Text("Placed on today: " + r.placedTitles.joined(separator: ", ") + ".").font(.nx(.callout))
                }
                if let s = r.summary, !r.undone { Text(s).font(.nx(.callout)).foregroundStyle(r.failed ? Theme.late : .secondary).lineLimit(3) }
                HStack(spacing: 14) {
                    if !r.placedTitles.isEmpty && !r.undone { Button("Undo") { r.undo(c) }.accessibilityIdentifier("plan-undo") }
                    if r.waiting > 0 {
                        Button(r.waiting == 1 ? "1 change waits for you" : "\(r.waiting) changes wait for you") { ClaudeChatSession.open(looking: "Today") }
                    } else if !c.isEmpty {
                        Button("Show the conversation") { ClaudeChatSession.open(looking: "Today") }
                    }
                    Button("Done") { plan.dismiss() }.foregroundStyle(.secondary)
                }
                .font(.nx(.callout, .medium))
                .buttonStyle(.borderless)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("plan-result")
        }
    }
}

/// File my Inbox (the laptop's /file-inbox on Home and the Inbox): Claude says where each Inbox item belongs and proposes the moves, which
/// wait for Accept in the conversation.
struct FileInboxButton: View {
    @Environment(NexusStore.self) private var store

    var body: some View {
        Button {
            let c = ClaudeChatSession.shared.conversation("main")
            guard !c.busy, let prompt = ClaudeChat.expand("/file-inbox", today: store.today) else { ClaudeChatSession.open(); return }
            ClaudeChatSession.ask("File my Inbox", prompt: prompt, looking: "Inbox")
        } label: {
            Label("File my Inbox", systemImage: "tray.and.arrow.down")
        }
        .disabled(!store.snapshot.isDataFolder || store.planning.openCount(nil) == 0)
        .accessibilityIdentifier("file-inbox")
    }
}
