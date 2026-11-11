import Foundation

/// One write to one task file, with what it said before, so Undo can put it back (only while nobody else changed the file since).
public struct Change {
    public var file: String
    public var before: String
    public var after: String
    /// What happened, for the undo bar ("Done: Physics HW sheet").
    public var message: String
    /// After a tick: the parent whose last open subtask this was, so the screen can offer to tick it too.
    public var offerParent: String?
}

/// The edits the iPad makes, each a line-level patch of one file, checked by parsing the result before it is written.
public struct TaskEditor {
    public enum Failure: Error, CustomStringConvertible {
        case readOnly(String)
        case changedOnDisk
        case wouldBreak(String)
        public var description: String {
            switch self {
            case .readOnly(let why): return why
            case .changedOnDisk: return "The file changed since; nothing was undone"
            case .wouldBreak(let why): return "That edit would break the file (\(why)), so it was not saved"
            }
        }
    }

    public var root: URL
    /// Reads and writes a file of the folder. The app wraps these in file coordination; tests use the plain ones.
    public var read: (URL) throws -> String
    public var write: (URL, String) throws -> Void

    public init(root: URL,
                read: @escaping (URL) throws -> String = { String(decoding: try Data(contentsOf: $0), as: UTF8.self) },
                write: @escaping (URL, String) throws -> Void = { try Data($1.utf8).write(to: $0, options: .atomic) }) {
        self.root = root; self.read = read; self.write = write
    }

    // MARK: the edits

    /// Done, with every open task under it (one date for all). Says when this was the parent's last open subtask.
    public func tick(_ t: NexusTask, in s: Snapshot, today: String) throws -> Change {
        let open = ([t] + s.descendants(of: t)).filter { !$0.done }
        var c = try edit(t, in: s, message: open.count > 1 ? "Ticked “\(t.text)” and \(open.count - 1) open subtask\(open.count == 2 ? "" : "s")" : "Done: \(t.text)") { text in
            try open.reduce(text) { try YamlEdit.setField($0, id: $1.id, key: "done", yaml: today) }
        }
        if let p = t.parent.flatMap({ s.tasks[$0] }), !p.done {
            let ticked = Set(open.map(\.id))
            if s.descendants(of: p).allSatisfy({ $0.done || ticked.contains($0.id) }) { c.offerParent = p.id }
        }
        return c
    }

    /// Not done; a done task above it opens again too (as on the laptop).
    public func untick(_ t: NexusTask, in s: Snapshot) throws -> Change {
        let above = s.ancestors(of: t).filter(\.done)
        return try edit(t, in: s, message: above.isEmpty ? "Not done: \(t.text)" : "Reopened “\(above.last!.text)” too") { text in
            try ([t] + above).reduce(text) { try YamlEdit.setField($0, id: $1.id, key: "done", yaml: nil) }
        }
    }

    public func setPlan(_ t: NexusTask, _ plan: [PlanEntry], in s: Snapshot, message: String? = nil) throws -> Change {
        let sorted = plan.sorted { $0.raw < $1.raw }
        var seen = Set<String>()
        let unique = sorted.filter { seen.insert($0.day).inserted }
        return try field(t, "plan", unique.isEmpty ? nil : YamlEdit.flow(unique.map(\.raw)), in: s,
                         message: message ?? (unique.isEmpty ? "Off the plan: \(t.text)" : "Planned: \(t.text)"))
    }

    /// Plans it for `day` (keeping its other days), with an optional time. A time replaces that day's old one.
    public func plan(_ t: NexusTask, on day: String, time: String? = nil, in s: Snapshot) throws -> Change {
        var p = t.plan.filter { $0.day != day }
        p.append(PlanEntry(day: day, time: time ?? t.time(on: day)))
        return try setPlan(t, p, in: s, message: "Planned for \(Days.label(day)): \(t.text)")
    }

    public func unplan(_ t: NexusTask, from day: String, in s: Snapshot) throws -> Change {
        try setPlan(t, t.plan.filter { $0.day != day }, in: s, message: "Off \(Days.label(day)): \(t.text)")
    }

    /// Moves a task planned for `from` onto `to` (the Planner's drag, "Move to today").
    public func move(_ t: NexusTask, from: String?, to: String, in s: Snapshot) throws -> Change {
        var p = t.plan.filter { $0.day != to && $0.day != from }
        p.append(PlanEntry(day: to, time: from.flatMap { t.time(on: $0) }))
        return try setPlan(t, p, in: s, message: "Moved to \(Days.label(to)): \(t.text)")
    }

    public func setDue(_ t: NexusTask, _ day: String?, in s: Snapshot) throws -> Change {
        try field(t, "due", day, in: s, message: day.map { "Deadline \(Days.label($0)): \(t.text)" } ?? "No deadline: \(t.text)")
    }

    public func setKey(_ t: NexusTask, _ on: Bool, in s: Snapshot) throws -> Change {
        try field(t, "key", on ? "true" : nil, in: s, message: on ? "★ \(t.text)" : "Not key: \(t.text)")
    }

    public func setSomeday(_ t: NexusTask, _ on: Bool, in s: Snapshot) throws -> Change {
        try field(t, "someday", on ? "true" : nil, in: s, message: on ? "Someday: \(t.text)" : "Back from Someday: \(t.text)")
    }

    public func setTitle(_ t: NexusTask, _ title: String, in s: Snapshot) throws -> Change {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw Failure.wouldBreak("a task needs a title") }
        return try field(t, "title", YamlEdit.scalar(clean), in: s, message: "Renamed: \(clean)")
    }

    public func setEstimate(_ t: NexusTask, _ est: String?, in s: Snapshot) throws -> Change {
        let e = est?.trimmingCharacters(in: .whitespaces)
        return try field(t, "est", (e?.isEmpty ?? true) ? nil : YamlEdit.scalar(e!), in: s, message: "Estimate: \(t.text)")
    }

    /// A new task at the end of `file` (or under `parent`). `fields` are written in the laptop's field order after id and title;
    /// `added` is stamped with today, as capture does.
    public func add(title: String, to file: String, parent: NexusTask? = nil, due: String? = nil, plan: [PlanEntry] = [], key: Bool = false,
                    est: String? = nil, in s: Snapshot, today: String) throws -> (Change, String) {
        guard s.canEdit(file) else { throw Failure.readOnly(s.readOnlyReason ?? "\(file) does not parse; fix it on the laptop first") }
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw Failure.wouldBreak("a task needs a title") }
        let url = root.appendingPathComponent(file)
        let before = (try? read(url)) ?? ""
        let id = TaskIds.new(taken: Set(s.tasks.keys).union(YamlEdit.ids(before)))
        var fields: [(String, String)] = []
        if let due { fields.append(("due", due)) }
        if key { fields.append(("key", "true")) }
        if !plan.isEmpty { fields.append(("plan", YamlEdit.flow(plan.map(\.raw)))) }
        if let est, !est.isEmpty { fields.append(("est", YamlEdit.scalar(est))) }
        fields.append(("added", today))
        let after = try YamlEdit.addTask(before, id: id, title: clean, fields: fields, parent: parent?.id)
        try check(after, file: file, workstream: parent?.workstream ?? s.workstreams.values.first { $0.tasksFile == file }?.id,
                  expect: { $0.contains { $0.id == id && $0.title == clean } }, count: countIn(before, file) + 1)
        try write(url, after)
        return (Change(file: file, before: before, after: after, message: "Added: \(clean)"), id)
    }

    /// Puts a file back as it was before `c`, if it still holds what `c` wrote.
    public func undo(_ c: Change) throws {
        let url = root.appendingPathComponent(c.file)
        guard (try? read(url)) == c.after else { throw Failure.changedOnDisk }
        try write(url, c.before)
    }

    // MARK: plumbing

    func field(_ t: NexusTask, _ key: String, _ value: String?, in s: Snapshot, message: String) throws -> Change {
        try edit(t, in: s, message: message) { try YamlEdit.setField($0, id: t.id, key: key, yaml: value) }
    }

    func edit(_ t: NexusTask, in s: Snapshot, message: String, _ change: (String) throws -> String) throws -> Change {
        guard t.hasId else { throw Failure.readOnly("This task has no id yet; open the folder in Nexus on the laptop once and it gets one") }
        guard s.canEdit(t.file) else { throw Failure.readOnly(s.readOnlyReason ?? "\(t.file) does not parse; fix it on the laptop first") }
        let url = root.appendingPathComponent(t.file)
        let before = try read(url)
        let after = try change(before)
        if after == before { return Change(file: t.file, before: before, after: after, message: message) }
        try check(after, file: t.file, workstream: t.workstream, expect: { $0.contains { $0.id == t.id } }, count: countIn(before, t.file))
        try write(url, after)
        return Change(file: t.file, before: before, after: after, message: message)
    }

    func countIn(_ text: String, _ file: String) -> Int {
        (try? TaskFile.parse(text, file: file, workstream: nil).tasks.count) ?? 0
    }

    func check(_ text: String, file: String, workstream: String?, expect: ([NexusTask]) -> Bool, count: Int) throws {
        let parsed: TaskFile.Parsed
        do { parsed = try TaskFile.parse(text, file: file, workstream: workstream) } catch { throw Failure.wouldBreak("\(error)") }
        guard parsed.tasks.count == count else { throw Failure.wouldBreak("\(parsed.tasks.count) tasks instead of \(count)") }
        guard expect(parsed.tasks) else { throw Failure.wouldBreak("the task went missing") }
    }
}
