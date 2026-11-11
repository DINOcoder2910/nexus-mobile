import Foundation

/// Everything the planner screens read from a data folder, built fresh from the files (the files are the truth).
public struct Snapshot {
    public var root: URL
    public var groups: [WorkGroup] = []
    public var workstreams: [String: Workstream] = [:]
    /// Every task by id, at every depth.
    public var tasks: [String: NexusTask] = [:]
    /// Every task id in reading order (groups in order, then the Inbox), depth first.
    public var order: [String] = []
    /// The top-level task ids of each task file.
    public var top: [String: [String]] = [:]
    public var problems: [Problem] = []
    /// Files that did not parse: shown as they last were, never written.
    public var brokenFiles: Set<String> = []
    /// Why nothing may be written to this folder (an old or newer format), or nil.
    public var readOnlyReason: String?
    public var isDataFolder = false
    public var loadedAt = Date()

    public init(root: URL) { self.root = root }

    public func workstream(of t: NexusTask) -> Workstream? { t.workstream.flatMap { workstreams[$0] } }
    public func children(of t: NexusTask) -> [NexusTask] { t.children.compactMap { tasks[$0] } }
    public func ancestors(of t: NexusTask) -> [NexusTask] {
        var out: [NexusTask] = [], p = t.parent
        while let id = p, let a = tasks[id] { out.insert(a, at: 0); p = a.parent }
        return out
    }
    public func descendants(of t: NexusTask) -> [NexusTask] {
        children(of: t).flatMap { [$0] + descendants(of: $0) }
    }
    /// The workstreams of a group, in name order like the sidebar.
    public func workstreams(in g: WorkGroup) -> [Workstream] { g.workstreams.compactMap { workstreams[$0] } }
    public var inboxTop: [NexusTask] { (top["inbox.yaml"] ?? []).compactMap { tasks[$0] } }
    /// A task counts in Today, the Planner and the lenses unless it is Someday or its workstream is parked.
    public func counts(_ t: NexusTask) -> Bool {
        if t.someday { return false }
        if let w = workstream(of: t), w.parked { return false }
        return true
    }
    public func canEdit(_ file: String) -> Bool { readOnlyReason == nil && !brokenFiles.contains(file) }
}

public enum DataFolder {
    static let skip: Set<String> = [".git", ".import", ".nexus", ".obsidian", "node_modules", ".Trash", "files"]

    /// Reads the folder. Missing files are fine; a file that does not parse is listed in `problems` and left out.
    public static func load(_ root: URL) -> Snapshot {
        var s = Snapshot(root: root)
        let fm = FileManager.default
        func read(_ rel: String) -> String? {
            guard let d = try? Data(contentsOf: root.appendingPathComponent(rel)) else { return nil }
            return String(decoding: d, as: UTF8.self)
        }
        guard let nexus = read("nexus.yaml") else { return s }
        s.isDataFolder = true
        if let cfg = try? TaskFile.settings(nexus) {
            let v = TaskFile.string(cfg["nexus"]).flatMap { Int($0) } ?? 0
            if v < 2 { s.readOnlyReason = "This folder is in the old layout; open it in Nexus on the laptop first." }
            else if v > 2 { s.readOnlyReason = "This folder was made by a newer Nexus; update the app to change it." }
        } else {
            s.problems.append(Problem(file: "nexus.yaml", message: "does not parse"))
            s.readOnlyReason = "nexus.yaml does not parse"
        }

        func dirs(_ rel: String) -> [String] {
            let url = rel.isEmpty ? root : root.appendingPathComponent(rel)
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .map(\.lastPathComponent).filter { !skip.contains($0) && !$0.hasPrefix(".") && !$0.hasSuffix(".board") }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }

        var groups: [WorkGroup] = []
        for g in dirs("") {
            let groupYaml = read(g + "/group.yaml").flatMap { try? TaskFile.settings($0) }
            var wsIds: [String] = []
            for w in dirs(g) {
                let folder = g + "/" + w
                guard let text = read(folder + "/workstream.yaml") else { continue }
                guard let cfg = try? TaskFile.settings(text) else {
                    s.problems.append(Problem(file: folder + "/workstream.yaml", message: "does not parse")); continue
                }
                let id = TaskFile.string(cfg["id"]) ?? w
                let ws = Workstream(id: id, name: TaskFile.string(cfg["name"]) ?? w,
                                    kind: TaskFile.string(cfg["kind"]) ?? groupYaml.flatMap { TaskFile.string($0["kind"]) },
                                    color: TaskFile.string(cfg["color"]) ?? groupYaml.flatMap { TaskFile.string($0["color"]) },
                                    status: TaskFile.string(cfg["status"]) ?? "active",
                                    aliases: TaskFile.list(cfg["aliases"]), folder: folder, group: g)
                if s.workstreams[id] != nil { s.problems.append(Problem(file: folder + "/workstream.yaml", message: "id \(id) is used twice")); continue }
                s.workstreams[id] = ws
                wsIds.append(id)
            }
            guard groupYaml != nil || !wsIds.isEmpty else { continue }
            let label = groupYaml.flatMap { TaskFile.string($0["label"]) } ?? g.prefix(1).uppercased() + g.dropFirst()
            wsIds.sort { (s.workstreams[$0]?.name ?? $0).localizedStandardCompare(s.workstreams[$1]?.name ?? $1) == .orderedAscending }
            groups.append(WorkGroup(id: g, label: label, order: groupYaml.flatMap { TaskFile.string($0["order"]) }.flatMap(Double.init) ?? 1000,
                                color: groupYaml.flatMap { TaskFile.string($0["color"]) }, kind: groupYaml.flatMap { TaskFile.string($0["kind"]) },
                                defaultWorkstream: groupYaml.flatMap { TaskFile.string($0["default"]) }, workstreams: wsIds))
        }
        s.groups = groups.sorted { $0.order != $1.order ? $0.order < $1.order : $0.label < $1.label }

        func addFile(_ rel: String, workstream: String?) {
            guard let text = read(rel) else { return }
            do {
                let p = try TaskFile.parse(text, file: rel, workstream: workstream)
                for var t in p.tasks {
                    if s.tasks[t.id] != nil { s.problems.append(Problem(file: rel, message: "id \(t.id) is used twice")); continue }
                    t.order = s.order.count
                    s.tasks[t.id] = t
                    s.order.append(t.id)
                }
                s.top[rel] = p.top
            } catch {
                s.problems.append(Problem(file: rel, message: "\(error)"))
                s.brokenFiles.insert(rel)
            }
        }
        for g in s.groups { for w in s.workstreams(in: g) { addFile(w.tasksFile, workstream: w.id) } }
        addFile("inbox.yaml", workstream: nil)
        s.loadedAt = Date()
        return s
    }

    /// A cheap summary of the files `load` reads (names, sizes, change times), so the app can notice another writer (sync, Files)
    /// and load again only when something changed.
    public static func fingerprint(_ root: URL) -> String {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        var parts: [String] = []
        func stamp(_ url: URL) {
            guard let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true else { return }
            parts.append("\(url.lastPathComponent):\(v.fileSize ?? 0):\(v.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        func list(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        for a in list(root) {
            if a.pathExtension == "yaml" { stamp(a); continue }
            guard !skip.contains(a.lastPathComponent), (try? a.resourceValues(forKeys: keys).isDirectory) == true else { continue }
            parts.append("/" + a.lastPathComponent)
            for b in list(a) {
                if b.lastPathComponent == "group.yaml" { stamp(b); continue }
                guard (try? b.resourceValues(forKeys: keys).isDirectory) == true, !b.lastPathComponent.hasSuffix(".board") else { continue }
                parts.append("//" + b.lastPathComponent)
                for name in ["workstream.yaml", "tasks.yaml"] { stamp(b.appendingPathComponent(name)) }
            }
        }
        return parts.joined(separator: "|")
    }

    /// Reads a text file of the folder (a workstream's notes.md), or nil.
    public static func text(_ root: URL, _ rel: String) -> String? {
        guard let d = try? Data(contentsOf: root.appendingPathComponent(rel)) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    /// The files beside a workstream's tasks (its notes, dated notes, files/), for its page: relative paths, newest first.
    public static func files(_ root: URL, in folder: String) -> [(path: String, modified: Date)] {
        let base = root.appendingPathComponent(folder)
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [(String, Date)] = []
        let basePath = base.resolvingSymlinksInPath().path
        for case let url as URL in e {
            let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard v?.isRegularFile == true else { continue }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(basePath + "/") else { continue }
            let rel = folder + "/" + path.dropFirst(basePath.count + 1)
            if rel.hasSuffix("/tasks.yaml") || rel.hasSuffix("/workstream.yaml") { continue }
            out.append((rel, v?.contentModificationDate ?? .distantPast))
        }
        return out.sorted { $0.1 > $1.1 }
    }
}
