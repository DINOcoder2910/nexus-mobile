import SwiftUI
import NexusCore

/// The task panel's Activity, as the laptop's (desktop/src/screens/TaskPanel.tsx `Activity`): folded until opened, then what happened
/// to the task, newest first, in the laptop's own words (NexusCore TaskActivity). The history comes from the data folder's git backup,
/// which the hub on the G14 keeps (`GET /v2/activity`); without it (no hub, or a hub that doesn't serve history yet) only the file's own
/// facts show: when the task was added and ticked.
struct TaskActivitySection: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask

    @State private var open = false
    @State private var rows: [TaskActivity.Row]?
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Kit.snap) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 12, weight: .semibold))
                    Text("Activity").font(.nx(.headline, .semibold))
                }
                .foregroundStyle(Kit.ink)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("panel-activity-toggle")
            if open {
                if let rows {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(rows.prefix(40).enumerated()), id: \.offset) { _, r in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(r.date.map { TimeWords.dayName($0, today: store.today) } ?? "")
                                    .font(.nx(.footnote)).foregroundStyle(Kit.muted)
                                    .frame(width: 78, alignment: .leading)
                                (Text(r.text) + Text(r.who.map { " · \($0)" } ?? "").italic().foregroundColor(Kit.muted))
                                    .font(.nx(.callout)).foregroundStyle(Kit.ink)
                            }
                        }
                        if rows.isEmpty { Text("Nothing yet.").font(.nx(.footnote)).foregroundStyle(Kit.muted) }
                        if let note { Text(note).font(.nx(.footnote)).foregroundStyle(Kit.faint) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("panel-activity")
                } else {
                    Text("Reading its history…").font(.nx(.footnote)).foregroundStyle(Kit.muted)
                }
            }
        }
        .task(id: open ? key : "") { if open { await load() } }
    }

    /// Read again when the task changes while the panel is open.
    private var key: String { [task.id, task.title, String(task.done), task.due ?? "", task.note ?? "", String(task.plan.count)].joined(separator: "|") }

    private func load() async {
        let path = task.file
        let current = try? String(contentsOf: store.folder.appendingPathComponent(path), encoding: .utf8)
        var names: [String: String] = ["inbox.yaml": "Inbox"]
        for w in store.snapshot.workstreams.values { names[w.tasksFile] = w.name }
        var history: JSONValue?
        do {
            history = TestHooks.extrasTask ? TestHooks.activityAnswer(path: path, current: current)
                : try await HubAsk.call("GET", "/v2/activity", query: [("path", path), ("id", task.id), ("limit", "30")], timeout: 15)
            note = history?["repo"]?.bool == false ? "The data folder isn't backed up with git, so only when it was added and ticked show here." : nil
        } catch let e as HubAsk.Failure {
            note = e.kind == "nohub" ? "Set up sync with the hub (Settings › Sync) to see the rest of its history."
                : e.kind == "old" ? "The hub doesn't keep the history yet, so only when it was added and ticked show here."
                : "Couldn't ask the hub for its history: \(e.words)"
        } catch {
            note = "Couldn't ask the hub for its history."
        }
        let t = task
        let today = store.today
        rows = TaskActivity.shared.rows(id: t.id, path: path, added: t.added, done: t.done, doneOn: t.doneOn, history: history, current: current,
                                        names: names, today: today)
    }
}
