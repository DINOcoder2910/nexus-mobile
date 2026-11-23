import SwiftUI
import NexusCore

/// A workstream's edits, as the new laptop app has them (nexus `desktop/src/screens/Workstreams.tsx`): New workstream in a group, Rename,
/// Add a decision, a person's New session, Park / Un-park, Colour and Move to group. The menu is a subject page's ⋯ and a hold on the
/// subject in the sidebar (the laptop's right-click); New workstream is also a hold on a group's name. The writes are NexusCore
/// WorkstreamEditor's, each with Undo on the bar.
@Observable
final class WorkstreamActions {
    enum Ask: Identifiable {
        case create(group: String), rename(String), decision(String), session(String)
        var id: String {
            switch self {
            case .create(let g): return "create:" + g
            case .rename(let w): return "rename:" + w
            case .decision(let w): return "decision:" + w
            case .session(let w): return "session:" + w
            }
        }
    }

    var asking: Ask?
    var text = ""
    /// A session note just made, open to write in.
    var note: (path: String, text: String)?
    /// Called with a new workstream's id (the iPad's sidebar opens its page).
    @ObservationIgnored var made: ((String) -> Void)?

    func ask(_ a: Ask, text: String = "") {
        self.text = text
        asking = a
    }

    func title(_ store: NexusStore) -> String {
        switch asking {
        case .create(let g):
            let label = store.snapshot.groups.first(where: { $0.id == g })?.label ?? g
            return "New workstream in \(label)"
        case .rename: return "Rename workstream"
        case .decision: return "Add a decision"
        case .session(let w): return "New session with \(store.workstream(w)?.name ?? "them")"
        case nil: return ""
        }
    }

    func message(_ store: NexusStore) -> String {
        switch asking {
        case .create: return "Its name. A folder of the same name is made in the group, with its workstream.yaml."
        case .rename: return "Links to it in your notes ([[Old name]]) are renamed too. Its folder and id stay as they are."
        case .decision(let w): return "One line: what was decided, and why. It goes under Decisions in \(store.workstream(w)?.name ?? "its") notes, with today's date."
        case .session: return "One dated note per session in their folder, today's date; their page lists them newest first."
        case nil: return ""
        }
    }

    var hint: String {
        switch asking {
        case .create, .rename: return "Name"
        case .decision: return "What was decided, and why"
        case .session: return "Title, for example Essays"
        case nil: return ""
        }
    }

    func finish(_ store: NexusStore, task: Bool = false) {
        guard let a = asking else { return }
        asking = nil
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch a {
        case .create(let g):
            if let id = store.createWorkstream(in: g, name: t) { made?(id) }
        case .rename(let id):
            if let w = store.workstream(id), t != w.name { store.renameWorkstream(w, to: t) }
        case .decision(let id):
            if let w = store.workstream(id) { store.addDecision(w, t) }
        case .session(let id):
            if let w = store.workstream(id), let p = store.newSession(w, title: t, task: task) {
                note = (p, (try? FolderAccess.read(store.folder.appendingPathComponent(p))) ?? "")
            }
        }
    }
}

/// The workstream's menu items (a ⋯ menu or a hold on its row).
struct WorkstreamMenu: View {
    @Environment(NexusStore.self) private var store
    let workstream: Workstream
    let actions: WorkstreamActions

    var body: some View {
        let w = workstream
        let s = store.snapshot
        let locked = s.readOnlyReason != nil
        Group {
            Button { actions.ask(.rename(w.id), text: w.name) } label: { Label("Rename…", systemImage: "pencil") }
            Button { actions.ask(.decision(w.id)) } label: { Label("Add a decision…", systemImage: "flag") }
            if w.kind == "person" {
                Button { actions.ask(.session(w.id)) } label: { Label("New session…", systemImage: "square.and.pencil") }
            }
            Button { store.parkWorkstream(w, !w.parked) } label: {
                Label(w.parked ? "Un-park" : "Park", systemImage: w.parked ? "play.circle" : "pause.circle")
            }
            Menu {
                ForEach(WorkstreamText.colours, id: \.self) { c in
                    Button { store.colorWorkstream(w, c) } label: {
                        Label(c.prefix(1).uppercased() + c.dropFirst(), systemImage: WorkstreamColor.name(w.color) == c ? "checkmark.circle.fill" : "circle.fill")
                    }
                    .tint(Theme.workstream(c, key: c))
                }
            } label: { Label("Colour", systemImage: "paintpalette") }
            let others = s.groups.filter { $0.id != w.group }
            if !others.isEmpty {
                Menu {
                    ForEach(others) { g in
                        Button { store.moveWorkstream(w, to: g.id) } label: { Label(g.label, systemImage: "folder") }
                    }
                } label: { Label("Move to group", systemImage: "folder") }
            }
            Divider()
            let groupName = s.groups.first(where: { $0.id == w.group })?.label ?? w.group
            Button { actions.ask(.create(group: w.group)) } label: {
                Label("New workstream in \(groupName)…", systemImage: "plus")
            }
        }
        .disabled(locked)
    }
}

extension View {
    /// The name and line prompts for the workstream edits, and a new session's note to write in (once on each screen that offers them).
    func workstreamPrompts(_ actions: WorkstreamActions, store: NexusStore) -> some View {
        @Bindable var actions = actions
        let session: Bool = { if case .session(_)? = actions.asking { return true }; return false }()
        return self
            .alert(actions.title(store), isPresented: Binding(get: { actions.asking != nil }, set: { if !$0 { actions.asking = nil } })) {
                TextField(actions.hint, text: $actions.text)
                    .accessibilityIdentifier("ws-prompt-field")
                if session {
                    Button("Create, and a task for it") { actions.finish(store, task: true) }
                }
                Button(actionLabel(actions.asking)) { actions.finish(store) }
                    .accessibilityIdentifier("ws-prompt-ok")
                Button("Cancel", role: .cancel) { actions.asking = nil }
            } message: {
                Text(actions.message(store))
            }
            .sheet(isPresented: Binding(get: { actions.note != nil }, set: { if !$0 { actions.note = nil } })) {
                if let n = actions.note {
                    NotesEditor(title: (n.path as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""), text: n.text) { new in
                        store.writeText(n.path, new, message: "Session note saved")
                    }
                }
            }
    }
}

private func actionLabel(_ a: WorkstreamActions.Ask?) -> String {
    switch a {
    case .create, .session: return "Create"
    case .rename: return "Rename"
    case .decision: return "Add"
    case nil: return "OK"
    }
}

/// A workstream's decisions, newest first (its notes.md's `## Decisions`), with Add a decision.
struct DecisionsCard: View {
    @Environment(NexusStore.self) private var store
    let workstream: Workstream
    let actions: WorkstreamActions
    @State private var decisions: [WorkstreamText.Decision] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Decisions").font(.nx(.title3, .semibold)).foregroundStyle(Kit.ink)
                if !decisions.isEmpty { Text("\(decisions.count)").font(.nx(.subheadline)).foregroundStyle(Kit.faint) }
                Spacer()
                Button { actions.ask(.decision(workstream.id)) } label: { Label("Add a decision", systemImage: "plus") }
                    .font(.nx(.subheadline, .medium)).foregroundStyle(Theme.accent).buttonStyle(.borderless)
                    .disabled(store.snapshot.readOnlyReason != nil)
                    .accessibilityIdentifier("add-decision")
            }
            if decisions.isEmpty {
                Text("No decisions yet. Add one when something is settled, and why.").font(.nx(.callout)).foregroundStyle(Kit.faint)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(decisions.prefix(8).enumerated()), id: \.offset) { _, d in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(d.date.map { wsDayWords($0, today: store.today) } ?? "").font(.nx(.footnote)).foregroundStyle(Kit.faint)
                                .frame(width: 64, alignment: .leading)
                            Text(d.text).font(.nx(.callout)).foregroundStyle(Kit.ink).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("decision")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kit.rests, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ws-decisions")
        .task(id: "\(workstream.id)|\(store.snapshot.loadedAt.timeIntervalSince1970)") {
            let t = (try? FolderAccess.read(store.folder.appendingPathComponent(workstream.folder + "/notes.md"))) ?? ""
            decisions = WorkstreamText.decisions(t)
        }
    }
}

/// A person's sessions (dated notes in their folder), newest first, with New session; tap one to read and write in it.
struct SessionsCard: View {
    @Environment(NexusStore.self) private var store
    let workstream: Workstream
    let actions: WorkstreamActions
    @State private var sessions: [WorkstreamText.Session] = []
    @State private var role: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sessions").font(.nx(.title3, .semibold)).foregroundStyle(Kit.ink)
                if let role { Text(role).font(.nx(.subheadline)).foregroundStyle(Kit.faint).lineLimit(1) }
                Spacer()
                Button { actions.ask(.session(workstream.id)) } label: { Label("New session", systemImage: "plus") }
                    .font(.nx(.subheadline, .medium)).foregroundStyle(Theme.accent).buttonStyle(.borderless)
                    .disabled(store.snapshot.readOnlyReason != nil)
                    .accessibilityIdentifier("new-session")
            }
            if sessions.isEmpty {
                Text("No sessions yet.").font(.nx(.callout)).foregroundStyle(Kit.faint)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sessions, id: \.path) { s in
                        Button {
                            actions.note = (s.path, (try? FolderAccess.read(store.folder.appendingPathComponent(s.path))) ?? "")
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(wsDayWords(s.date, today: store.today)).font(.nx(.footnote)).foregroundStyle(Kit.faint).frame(width: 64, alignment: .leading)
                                Text(s.title).font(.nx(.callout, .medium)).foregroundStyle(Kit.ink)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Kit.faint)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("session")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kit.rests, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ws-sessions")
        .task(id: "\(workstream.folder)|\(store.snapshot.loadedAt.timeIntervalSince1970)") {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: store.folder.appendingPathComponent(workstream.folder).path)) ?? []
            sessions = WorkstreamText.sessions(names, folder: workstream.folder)
            let yaml = (try? FolderAccess.read(store.folder.appendingPathComponent(workstream.folder + "/workstream.yaml"))).flatMap { try? TaskFile.settings($0) }
            let r = yaml.flatMap { TaskFile.string($0["role"]) }, c = yaml.flatMap { TaskFile.string($0["cadence"]) }
            role = r.map { $0 + (c.map { " · " + $0 } ?? "") }
        }
    }
}

/// "Today", "Yesterday", "Mon 3 Nov", "3 Nov 2025": a past day as the laptop's lists say it.
private func wsDayWords(_ day: String, today: String) -> String {
    let n = Days.between(day, today)
    if n == 0 { return "Today" }
    if n == 1 { return "Yesterday" }
    let m = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    let mon = m[max(0, min(11, (Int(day.dropFirst(5).prefix(2)) ?? 1) - 1))]
    let d = Int(day.suffix(2)) ?? 0
    if day.prefix(4) != today.prefix(4) { return "\(d) \(mon) \(day.prefix(4))" }
    return n > 0 && n < 7 ? TodayView.weekday(day, short: true) + " \(d)" : "\(d) \(mon)"
}
