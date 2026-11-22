import SwiftUI
import NexusCore

/// The quick page (the iPhone's Action button, Siri "Open the Nexus quick page"): big buttons for what is wanted in a hurry (record,
/// film, a new task, an idea), then what the day holds: the next event, today's events and tasks, and a few numbers.
struct QuickPage: View {
    var close: () -> Void
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var calendar
    @State private var rec = RecordingService.shared
    @State private var timer = TimeTracker.shared
    @State private var openRecordings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RecordButtons(big: true)
                    HStack(spacing: 10) {
                        big("New task", "plus.circle.fill", id: "quick-task") {
                            close()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.capture = .init(workstream: nil, parent: nil, plan: store.today) }
                        }
                        big("Idea", "lightbulb.fill", id: "quick-idea") {
                            close()
                            WindowRouter.shared.ideas = true
                        }
                        big("Recordings", "waveform", id: "quick-recordings", badge: reviewCount) { openRecordings = true }
                    }
                    stats
                    if store.snapshot.isDataFolder { events; tasks }
                }
                .padding(16)
            }
            .navigationTitle(Days.label(store.today))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: close).accessibilityIdentifier("quick-done") } }
            .navigationDestination(isPresented: $openRecordings) { RecordingsView() }
        }
        .accessibilityIdentifier("quick-page")
    }

    private var reviewCount: Int {
        let _ = rec.version
        return Recordings.list(store.folder).filter { $0.status == .review }.count
    }

    private func big(_ label: String, _ icon: String, id: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title2)
                Text(label).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent, in: Capsule()).offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(id)
    }

    // MARK: the numbers

    private var stats: some View {
        let plan = store.planning
        let today = store.today
        let done = store.snapshot.tasks.values.filter { $0.done && $0.doneOn == today }.count
        let left = plan.todayPlan.count
        let tracked = TimeLog.daySeconds(timer.entries, today)
        let next = plan.open.filter { ($0.due ?? "") >= today }.sorted { ($0.due ?? "", $0.title) < ($1.due ?? "", $1.title) }.first
        let late = plan.open.filter { ($0.due ?? "9999") < today }.count
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            tile("Done today", "\(done) of \(done + left)", icon: "checkmark.circle", id: "quick-stat-done")
            tile("Tracked today", hours(tracked) + (timer.current != nil ? " · running" : ""), icon: "timer", id: "quick-stat-time")
            tile("Next deadline", next.map { "\(Days.label($0.due!)): \($0.title)" } ?? "None", icon: "flag", id: "quick-stat-deadline")
            tile(late > 0 ? "Late" : "Next up", late > 0 ? "\(late) past due" : (plan.todayPlan.first?.title ?? "Nothing planned"),
                 icon: late > 0 ? "exclamationmark.triangle" : "arrow.right.circle", id: "quick-stat-next", warn: late > 0)
        }
    }

    private func hours(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    private func tile(_ label: String, _ value: String, icon: String, id: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon).font(.caption).foregroundStyle(warn ? Theme.late : .secondary)
            Text(value).font(.headline).lineLimit(2).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: the day

    @ViewBuilder
    private var events: some View {
        if calendar.canRead {
            let list = calendar.events(on: store.today)
            VStack(alignment: .leading, spacing: 8) {
                if let n = calendar.next(today: store.today) {
                    let mins = Int(n.start.timeIntervalSinceNow / 60)
                    Text(mins > 0 ? "Next: \(n.title) in \(mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : "\(mins) min")" : "Now: \(n.title)")
                        .font(.title3.weight(.semibold))
                }
                Text("Calendar").font(.headline)
                if list.isEmpty { Text("Nothing on the calendar today.").foregroundStyle(.secondary) }
                ForEach(list) { e in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 4, height: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.title).font(.body.weight(.medium)).lineLimit(1)
                            Text(e.timeText + (e.location.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .opacity(e.end < Date() ? 0.5 : 1)
                }
            }
        }
    }

    private var tasks: some View {
        let list = store.planning.todayPlan
        return VStack(alignment: .leading, spacing: 6) {
            Text("Today's tasks").font(.headline)
            if list.isEmpty { Text("Nothing planned for today.").foregroundStyle(.secondary) }
            ForEach(list.prefix(10)) { t in TaskRow(task: t, day: store.today, compact: true) }
            if list.count > 10 { Text("\(list.count - 10) more on Today").font(.caption).foregroundStyle(.secondary) }
        }
    }
}
