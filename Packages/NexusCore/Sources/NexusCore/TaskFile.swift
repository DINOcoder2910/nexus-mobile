import Foundation
import Yams

/// Reads a `tasks.yaml` / `inbox.yaml` (and the small `*.yaml` settings files) into plain values. Reading never writes.
public enum TaskFile {
    public struct Parsed {
        /// Every task, depth first, in file order.
        public var tasks: [NexusTask]
        public var top: [String]
    }

    public enum Failure: Error, CustomStringConvertible {
        case yaml(String)
        case shape(String)
        public var description: String {
            switch self {
            case .yaml(let m): return m
            case .shape(let m): return m
            }
        }
    }

    public static func parse(_ text: String, file: String, workstream: String?) throws -> Parsed {
        let node: Node?
        do { node = try Yams.compose(yaml: text) } catch { throw Failure.yaml(yamlMessage(error)) }
        guard let root = node else { return Parsed(tasks: [], top: []) }
        guard let map = root.mapping else { throw Failure.shape("not a task list (expected tasks:)") }
        guard let tasksNode = value(map, "tasks") else { return Parsed(tasks: [], top: []) }
        if tasksNode.scalar != nil && (tasksNode.scalar?.string ?? "").isEmpty { return Parsed(tasks: [], top: []) }
        guard let seq = tasksNode.sequence else { throw Failure.shape("tasks: is not a list") }
        var out: [NexusTask] = []
        var top: [String] = []
        var missing = 0
        func walk(_ seq: Node.Sequence, parent: NexusTask?, depth: Int) -> [String] {
            var ids: [String] = []
            for item in seq {
                guard let m = item.mapping else { continue }
                let rawId = string(value(m, "id"))
                let hasId = !(rawId ?? "").isEmpty
                missing += hasId ? 0 : 1
                let id = hasId ? rawId! : "?\(file)#\(missing)"
                var t = NexusTask(id: id, hasId: hasId, title: string(value(m, "title")) ?? "", file: file, workstream: workstream)
                t.depth = depth
                t.parent = parent?.id
                if let d = value(m, "done") {
                    let s = string(d) ?? ""
                    t.done = !(s.isEmpty || s == "false" || s == "no")
                    t.doneOn = Days.isIso(s) ? s : nil
                }
                if let d = string(value(m, "due")), Days.isIso(String(d.prefix(10))) { t.due = String(d.prefix(10)) }
                t.key = truthy(value(m, "key"))
                t.plan = list(value(m, "plan")).compactMap(PlanEntry.init)
                t.est = string(value(m, "est"))
                if let w = value(m, "waiting") {
                    if let wm = w.mapping { t.waitingOn = string(value(wm, "on")) ?? ""; t.waitingSince = string(value(wm, "since")) }
                    else { t.waitingOn = string(w) ?? "" }
                }
                if let e = value(m, "every") { (t.every, t.everyRaw) = repeatOf(e) }
                t.ownSomeday = truthy(value(m, "someday"))
                t.someday = t.ownSomeday || (parent?.someday ?? false)
                t.tags = list(value(m, "tags"))
                t.note = string(value(m, "note"))
                t.email = string(value(m, "email"))
                t.added = string(value(m, "added"))
                t.order = out.count
                let index = out.count
                out.append(t)
                if let subs = value(m, "subtasks")?.sequence {
                    out[index].children = walk(subs, parent: out[index], depth: depth + 1)
                }
                ids.append(id)
            }
            return ids
        }
        top = walk(seq, parent: nil, depth: 0)
        return Parsed(tasks: out, top: top)
    }

    /// A small settings file (`nexus.yaml`, `group.yaml`, `workstream.yaml`) as key -> node.
    public static func settings(_ text: String) throws -> [String: Node] {
        let node: Node?
        do { node = try Yams.compose(yaml: text) } catch { throw Failure.yaml(yamlMessage(error)) }
        guard let map = node?.mapping else { return [:] }
        var out: [String: Node] = [:]
        for (k, v) in map { if let key = k.scalar?.string { out[key] = v } }
        return out
    }

    // MARK: helpers

    static func value(_ m: Node.Mapping, _ key: String) -> Node? {
        for (k, v) in m where k.scalar?.string == key { return v }
        return nil
    }

    public static func string(_ n: Node?) -> String? {
        guard let s = n?.scalar else { return nil }
        if s.string == "~" || (s.string == "null" && s.style == .plain) { return nil }
        return s.string
    }

    public static func truthy(_ n: Node?) -> Bool {
        guard let s = string(n)?.lowercased() else { return false }
        return ["true", "yes", "on", "y"].contains(s)
    }

    public static func list(_ n: Node?) -> [String] {
        guard let n else { return [] }
        if let seq = n.sequence { return seq.compactMap { string($0) } }
        if let s = string(n), !s.isEmpty {
            return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return []
    }

    static func repeatOf(_ n: Node) -> (Repeat?, String?) {
        if let m = n.mapping {
            let freq = string(value(m, "freq")) ?? ""
            let raw = [freq, list(value(m, "on")).isEmpty ? "" : "on " + list(value(m, "on")).joined(separator: ", "),
                       string(value(m, "until")).map { "until " + $0 } ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            return (Repeat(freq: freq.lowercased(), on: list(value(m, "on")), until: string(value(m, "until"))), raw)
        }
        guard let s = string(n) else { return (nil, nil) }
        // "week on fri until 2026-11-30", "day", "weekdays"
        var freq = s, on: [String] = [], until: String?
        if let r = freq.range(of: " until ") { until = String(freq[r.upperBound...]).trimmingCharacters(in: .whitespaces); freq = String(freq[..<r.lowerBound]) }
        if let r = freq.range(of: " on ") {
            on = freq[r.upperBound...].split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            freq = String(freq[..<r.lowerBound])
        }
        return (Repeat(freq: freq.trimmingCharacters(in: .whitespaces).lowercased(), on: on, until: until), s)
    }

    static func yamlMessage(_ error: Error) -> String {
        let text = "\(error)"
        return text.split(separator: "\n").first.map(String.init) ?? text
    }
}
