import SwiftUI
import NexusCore

/// Time tracking on the iPad and the iPhone (nexus docs/data-format.md "Time tracking"; the pure half is NexusCore TimeLog): every
/// device's `time/<device>/<month>.yaml`, read with the folder, the one timer that runs, and start / stop / add / change / remove.
/// This device writes `time/ipad/…` or `time/iphone/…`; stopping a timer another device started sets `end` on that device's line
/// (one timer runs at a time across the devices). Shared by every window; each write tells sync through the window's store.
@Observable
final class TimeTracker {
    static let shared = TimeTracker()

    /// Every session in every file.
    private(set) var entries: [TimeLog.Entry] = []
    /// Files that do not parse (or were written by a newer Nexus), said on the Time screen.
    private(set) var problems: [String] = []
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var stamp = ""

    /// This device's name in the files.
    static var device: String { Device.isPhone ? "iphone" : "ipad" }

    // MARK: reading

    /// Reads the time files again when any changed (the store calls this on every read of the folder).
    func load(_ root: URL, force: Bool = false) {
        let fm = FileManager.default
        let base = root.appendingPathComponent(TimeLog.dir, isDirectory: true)
        var files: [(rel: String, url: URL)] = []
        var key = root.path
        for d in ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? d.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            for f in ((try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let rel = "\(TimeLog.dir)/\(d.lastPathComponent)/\(f.lastPathComponent)"
                guard TimeLog.device(ofPath: rel) != nil else { continue }
                let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                key += "|\(rel):\(v?.fileSize ?? 0):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                files.append((rel, f))
            }
        }
        guard force || key != stamp || folder != root else { return }
        folder = root; stamp = key
        var all: [TimeLog.Entry] = [], bad: [String] = []
        for (rel, url) in files {
            guard let text = try? FolderAccess.read(url) else { continue }
            do {
                let f = try TimeLog.parse(text)
                let dev = TimeLog.device(ofPath: rel) ?? ""
                all += f.entries.map { var e = $0; e.path = rel; e.device = dev; return e }
            } catch {
                bad.append("\(rel) \(error)")
            }
        }
        entries = all
        problems = bad
    }

    // MARK: what is there

    var running: [TimeLog.Entry] { TimeLog.running(entries) }
    var current: TimeLog.Entry? { running.first }
    func isRunning(_ id: String) -> Bool { entries.contains { $0.running && $0.task == id } }

    /// The task and every subtask under it.
    static func ids(under id: String, in s: Snapshot) -> Set<String> {
        var out: Set<String> = [id]
        var stack = [id]
        while let x = stack.popLast() {
            for c in s.tasks[x]?.children ?? [] where !out.contains(c) { out.insert(c); stack.append(c) }
        }
        return out
    }

    /// Seconds spent on a task (and its subtasks), a running timer counted to `now`.
    func seconds(_ id: String, in s: Snapshot, subs: Bool = true, now: Date = Date()) -> TimeInterval {
        let ids = subs ? Self.ids(under: id, in: s) : [id]
        return entries.filter { ids.contains($0.task) }.reduce(0) { $0 + $1.seconds(now: now) }
    }

    func sessions(of id: String, in s: Snapshot, subs: Bool = true) -> [TimeLog.Entry] {
        let ids = subs ? Self.ids(under: id, in: s) : [id]
        return entries.filter { ids.contains($0.task) }.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    func title(_ e: TimeLog.Entry, in s: Snapshot) -> String {
        if let t = s.tasks[e.task] { return t.text }
        return e.title.isEmpty ? "A task that is gone" : e.title
    }

    // MARK: writing

    /// One file changed from what is on disk now (nil from `change`: nothing to write). The undo bar gets the change.
    @discardableResult
    private func edit(_ rel: String, store: NexusStore, message: String? = nil, _ change: (String?) -> String?) -> Bool {
        guard store.snapshot.readOnlyReason == nil else { store.problem = store.snapshot.readOnlyReason; return false }
        let url = store.folder.appendingPathComponent(rel)
        let before = try? FolderAccess.read(url)
        guard let after = change(before), after != before else { return false }
        do {
            try FolderAccess.write(url, after)
        } catch {
            store.problem = "Couldn't save \(rel): \(error.localizedDescription)"
            return false
        }
        load(store.folder, force: true)
        store.didWrite(touched: [rel])
        if let message { store.toast = .init(message: message, change: Change(file: rel, before: before ?? "", after: after, message: message)) }
        return true
    }

    private func put(_ e: TimeLog.Entry, _ next: TimeLog.Entry?, store: NexusStore, message: String? = nil) -> Bool {
        edit(e.path, store: store, message: message) { text in
            guard let text else { return nil }
            return TimeLog.replace(text, was: e, with: next.map { TimeLog.Entry(task: e.task, title: e.title, start: $0.start, end: $0.end) })
        }
    }

    private func stopAll(_ list: [TimeLog.Entry], at: Date, store: NexusStore, message: String? = nil) {
        for (i, e) in list.enumerated() {
            var x = e
            x.end = TimeLog.stamp((e.startDate ?? at) > at ? (e.startDate ?? at) : at)
            _ = put(e, x, store: store, message: i == 0 ? message : nil)
        }
    }

    /// A timer on `task`; every timer that runs stops first.
    func start(_ task: NexusTask, store: NexusStore) {
        let now = Date()
        let was = running
        if !was.isEmpty { stopAll(was, at: now, store: store) }
        var at = now
        while entries.contains(where: { $0.task == task.id && $0.start == TimeLog.stamp(at) }) { at = at.addingTimeInterval(1) }
        let e = TimeLog.Entry(task: task.id, title: task.title, start: TimeLog.stamp(at))
        let rel = TimeLog.file(device: Self.device, start: at)
        edit(rel, store: store) { TimeLog.append($0, device: Self.device, e) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Stops every timer that runs (Undo on the bar: it runs on).
    func stop(store: NexusStore) {
        let list = running
        guard let first = list.first else { return }
        let words = TimeLog.spent(first.seconds())
        stopAll(list, at: Date(), store: store, message: "Stopped: \(words.isEmpty ? "under a minute" : words) on \(title(first, in: store.snapshot))")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func toggle(_ task: NexusTask, store: NexusStore) {
        if isRunning(task.id) { stop(store: store) } else { start(task, store: store) }
    }

    /// A task (and the subtasks the tick ticks) was ticked off here: its timer stops.
    func ticked(_ task: NexusTask, store: NexusStore) {
        let ids = Self.ids(under: task.id, in: store.snapshot)
        let hit = running.filter { ids.contains($0.task) }
        guard !hit.isEmpty else { return }
        stopAll(hit, at: Date(), store: store)
    }

    /// Time put in by hand: [from, to) on `task`.
    func add(_ task: NexusTask, from: Date, to: Date, store: NexusStore) {
        guard to > from else { store.problem = "The end has to be after the start."; return }
        let e = TimeLog.Entry(task: task.id, title: task.title, start: TimeLog.stamp(from), end: TimeLog.stamp(to))
        edit(TimeLog.file(device: Self.device, start: from), store: store, message: "Added \(TimeLog.spent(to.timeIntervalSince(from))) to \(task.text)") {
            TimeLog.append($0, device: Self.device, e)
        }
    }

    /// A session's times changed (`to` nil: it keeps running).
    func change(_ e: TimeLog.Entry, from: Date, to: Date?, store: NexusStore) {
        if let to, to <= from { store.problem = "The end has to be after the start."; return }
        let next = TimeLog.Entry(task: e.task, title: e.title, start: TimeLog.stamp(from), end: to.map { TimeLog.stamp($0) })
        _ = put(e, next, store: store, message: "Changed a session of \(title(e, in: store.snapshot))")
    }

    func remove(_ e: TimeLog.Entry, store: NexusStore) {
        let words = TimeLog.spent(e.seconds())
        _ = put(e, nil, store: store, message: "Removed \(words.isEmpty ? "a session" : words) on \(title(e, in: store.snapshot))")
    }
}
