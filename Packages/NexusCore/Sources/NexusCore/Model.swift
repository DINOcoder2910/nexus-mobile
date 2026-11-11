import Foundation

/// One planned day, with an optional start time ("2026-10-29 14:00").
public struct PlanEntry: Hashable, Codable {
    public var day: String
    public var time: String?
    public init(day: String, time: String? = nil) { self.day = day; self.time = time }

    public init?(_ raw: String) {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first, Days.isIso(String(first)) else { return nil }
        day = String(first)
        time = parts.count > 1 ? String(parts[1]) : nil
    }

    public var raw: String { time.map { "\(day) \($0)" } ?? day }
}

/// `every`: day, weekdays, or week (on some days), with an optional `until`.
public struct Repeat: Hashable {
    public var freq: String
    public var on: [String]
    public var until: String?

    /// The weekdays it falls on (0 = Sunday), nil for every day; `nil` result when the shape is unknown.
    public func days(anchor: String?) -> [Int]?? {
        switch freq.lowercased() {
        case "day": return .some(nil)
        case "weekdays": return .some([1, 2, 3, 4, 5])
        case "week":
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            var out: [Int] = []
            for w in on.map({ $0.lowercased() }) where !w.isEmpty {
                guard w.count >= 3, let i = names.firstIndex(where: { $0.hasPrefix(w) }) else { return nil }
                out.append(i)
            }
            if out.isEmpty, let a = anchor, Days.isIso(a) { out = [Days.weekday(a)] }
            return .some(out.isEmpty ? nil : out)
        default: return nil
        }
    }

    /// The next day from `today` it falls on, or nil when the shape is unknown. `live` is false once that is after `until`.
    public func next(today: String, anchor: String?) -> (day: String, live: Bool)? {
        guard let ds = days(anchor: anchor) else { return nil }
        if let u = until, !Days.isIso(u) { return nil }
        for i in 0..<7 {
            let d = Days.add(today, i)
            if ds == nil || ds!.contains(Days.weekday(d)) {
                return (d, until.map { Days.between(d, $0) >= 0 } ?? true)
            }
        }
        return nil
    }

    public var text: String {
        var s = freq == "weekdays" ? "Weekdays" : freq == "day" ? "Daily" : "Weekly"
        if !on.isEmpty { s += " on " + on.joined(separator: ", ") }
        if let u = until { s += " until \(u)" }
        return s
    }
}

/// A task at any depth. Its workstream is the file it is in.
public struct NexusTask: Identifiable, Hashable {
    /// The task's id from the file. A task without one gets "?<file>#<n>" here and can't be edited until the laptop gives it one.
    public var id: String
    public var hasId: Bool
    public var title: String
    public var done: Bool = false
    public var doneOn: String?
    public var due: String?
    public var key = false
    public var plan: [PlanEntry] = []
    public var est: String?
    public var waitingOn: String?
    public var waitingSince: String?
    public var every: Repeat?
    public var everyRaw: String?
    /// Its own flag or a parked parent's.
    public var someday = false
    public var ownSomeday = false
    public var tags: [String] = []
    public var note: String?
    public var email: String?
    public var added: String?
    public var children: [String] = []
    public var parent: String?
    public var depth = 0
    /// The task file, relative to the data folder ("classes/physics-hl/tasks.yaml", "inbox.yaml").
    public var file: String
    /// nil for the Inbox.
    public var workstream: String?
    /// Place in the folder's reading order, to keep file order wherever the screens list tasks.
    public var order = 0

    public init(id: String, hasId: Bool = true, title: String, file: String, workstream: String?) {
        self.id = id; self.hasId = hasId; self.title = title; self.file = file; self.workstream = workstream
    }

    public var estHours: Double? { hoursOf(est) }
    public var plannedDays: [String] { plan.map(\.day) }
    public func time(on day: String) -> String? { plan.first { $0.day == day }?.time }
    /// Title with `[[links]]` shown as their text.
    public var text: String {
        var s = title
        while let r = s.range(of: #"\[\[([^\]|]+)\|([^\]]+)\]\]"#, options: .regularExpression) {
            let inner = s[r].dropFirst(2).dropLast(2); s.replaceSubrange(r, with: inner.split(separator: "|").last.map(String.init) ?? "")
        }
        while let r = s.range(of: #"\[\[([^\]]+)\]\]"#, options: .regularExpression) {
            s.replaceSubrange(r, with: String(s[r].dropFirst(2).dropLast(2)))
        }
        return s
    }
}

public struct Workstream: Identifiable, Hashable {
    public var id: String
    public var name: String
    public var kind: String?
    public var color: String?
    public var status: String
    public var aliases: [String]
    /// "classes/physics-hl"
    public var folder: String
    public var group: String
    public var tasksFile: String { folder + "/tasks.yaml" }
    public var parked: Bool { status == "parked" }
    public var finished: Bool { status == "done" }
}

public struct Group: Identifiable, Hashable {
    /// The folder name.
    public var id: String
    public var label: String
    public var order: Double
    public var color: String?
    public var kind: String?
    public var defaultWorkstream: String?
    public var workstreams: [String]
}

public struct Problem: Hashable, Identifiable {
    public var file: String
    public var message: String
    public var id: String { file + ":" + message }
}

/// The workstream colours of the laptop's themes.js (light and dark), with the old names mapped as it maps them.
public enum WorkstreamColor {
    public static let names = ["blue", "amber", "green", "rose", "violet", "olive", "teal", "coral", "pink", "slate"]
    public static let hex: [String: (light: String, dark: String)] = [
        "blue": ("#2769B7", "#82BAFF"), "amber": ("#9A5600", "#E8A95C"), "green": ("#007F43", "#73CE95"),
        "rose": ("#A14174", "#F197C2"), "violet": ("#6A57B3", "#B6AAFF"), "olive": ("#6F6E00", "#BCBE5E"),
        "teal": ("#007F88", "#3ACED6"), "coral": ("#AA442B", "#FA9B82"), "pink": ("#94468F", "#E39BDC"), "slate": ("#556B82", "#A2BAD4"),
    ]
    static let old = ["red": "rose", "orange": "coral", "yellow": "amber", "purple": "violet", "indigo": "violet", "gray": "slate", "grey": "slate"]

    /// A stored colour to one of the names (a hex goes to the nearest), nil for none.
    public static func name(_ v: String?) -> String? {
        guard let s = v?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if hex[s] != nil { return s }
        if let o = old[s] { return o }
        guard let rgb = rgb(s) else { return nil }
        var best = "slate", bestD = Double.infinity
        for (n, pair) in hex {
            guard let c = Self.rgb(pair.light) else { continue }
            let d = zip(rgb, c).map { ($0 - $1) * ($0 - $1) }.reduce(0, +)
            if d < bestD { bestD = d; best = n }
        }
        return best
    }

    public static func rgb(_ h: String) -> [Double]? {
        var s = h.hasPrefix("#") ? String(h.dropFirst()) : h
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return [Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255)]
    }
}
