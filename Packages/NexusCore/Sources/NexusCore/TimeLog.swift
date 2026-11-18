import Foundation
import Yams

/// Time tracking's files, as the laptop's `renderer/src/timelog.js` reads and writes them (nexus docs/data-format.md "Time tracking"):
/// each device keeps `time/<device>/<YYYY-MM>.yaml` (the month a session started in), one line per session, a line with no `end` a timer
/// that is running. One timer runs at a time across the devices (starting one stops every other, in whichever file it is). A session
/// is known by its task and its start together. Pure: the app's TimeTracker does the reading, writing and the screens.
///
///     # Time tracked on the iPad (Nexus writes this file). One line per session; a line with no end is a timer that is running.
///     format: nexus-time/1
///     device: ipad
///     entries:
///       - {task: "prab", title: "Physics HW sheet", start: "2026-11-16T14:05:12+05:30", end: "2026-11-16T14:50:03+05:30"}
public enum TimeLog {
    public static let format = "nexus-time/1"
    public static let dir = "time"

    /// One session of one file.
    public struct Entry: Hashable, Identifiable {
        public var task: String
        public var title: String
        public var start: String
        public var end: String?
        /// The file it is in (relative to the data folder) and that file's device; set by the reader.
        public var path = ""
        public var device = ""
        public var id: String { "\(path)|\(task)|\(start)" }
        public var running: Bool { end == nil }
        public init(task: String, title: String = "", start: String, end: String? = nil, path: String = "", device: String = "") {
            self.task = task; self.title = title; self.start = start; self.end = end; self.path = path; self.device = device
        }
        public var startDate: Date? { TimeLog.date(start) }
        public var endDate: Date? { end.flatMap { TimeLog.date($0) } }
        /// Seconds it lasted (a running one: until `now`), never below 0.
        public func seconds(now: Date = Date()) -> TimeInterval {
            guard let a = startDate else { return 0 }
            let b = end == nil ? now : (endDate ?? a)
            return max(0, b.timeIntervalSince(a))
        }
    }

    public struct File {
        public var device: String?
        public var entries: [Entry]
    }

    public enum Failure: Error, CustomStringConvertible {
        case yaml(String), newer(String), shape(String)
        public var description: String {
            switch self {
            case .yaml(let m): return "does not parse (\(m))"
            case .newer(let f): return "was written by a newer Nexus (\(f))"
            case .shape(let m): return m
            }
        }
    }

    public static func deviceWords(_ d: String) -> String {
        switch d { case "laptop": return "the laptop"; case "ipad": return "the iPad"; case "iphone": return "the iPhone"; default: return d.isEmpty ? "another device" : d }
    }
    public static func deviceName(_ d: String) -> String {
        switch d { case "laptop": return "Laptop"; case "ipad": return "iPad"; case "iphone": return "iPhone"; default: return d }
    }

    // MARK: stamps

    /// "2026-11-16T14:05:12+05:30": local time with its offset, to the second.
    public static func stamp(_ d: Date, zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssxxx"
        return f.string(from: Date(timeIntervalSince1970: floor(d.timeIntervalSince1970)))
    }

    /// A stamp -> a date: with an offset or Z, or local time without one ("2026-11-16 10:00" from a hand-written line).
    public static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let re = try! NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})?$"#)
        guard let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        func g(_ i: Int) -> String? { let r = m.range(at: i); return r.location == NSNotFound ? nil : String(t[Range(r, in: t)!]) }
        var c = DateComponents()
        c.year = Int(g(1)!); c.month = Int(g(2)!); c.day = Int(g(3)!); c.hour = Int(g(4)!); c.minute = Int(g(5)!); c.second = Int(g(6) ?? "0")
        var cal = Calendar(identifier: .gregorian)
        if let z = g(7) {
            if z == "Z" { cal.timeZone = TimeZone(secondsFromGMT: 0)! } else {
                let zz = z.replacingOccurrences(of: ":", with: "")
                let sign = zz.hasPrefix("-") ? -1 : 1
                let hh = Int(zz.dropFirst().prefix(2)) ?? 0, mm = Int(zz.dropFirst(3).prefix(2)) ?? 0
                cal.timeZone = TimeZone(secondsFromGMT: sign * (hh * 3600 + mm * 60))!
            }
        } else { cal.timeZone = .current }
        return cal.date(from: c)
    }

    /// The month file a session that started at `d` goes in.
    public static func file(device: String, start d: Date) -> String {
        let c = Days.calendar.dateComponents([.year, .month], from: d)
        return "\(dir)/\(device)/\(String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)).yaml"
    }

    /// A path in the data folder -> its device when it is a time file.
    public static func device(ofPath p: String) -> String? {
        let parts = p.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "time", !parts[1].isEmpty else { return nil }
        let name = parts[2]
        let re = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}\.yaml$"#)
        guard re.firstMatch(in: String(name), range: NSRange(name.startIndex..., in: name)) != nil else { return nil }
        return String(parts[1])
    }

    // MARK: the file

    public static func header(_ device: String) -> String {
        "# Time tracked on \(deviceWords(device)) (Nexus writes this file). One line per session; a line with no end is a timer that is running.\n" +
        "format: \(format)\ndevice: \(device)\nentries:\n"
    }

    /// A JSON string (a YAML double-quoted string).
    static func q(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
        let arr = String(decoding: data, as: UTF8.self)
        return String(arr.dropFirst().dropLast())
    }

    /// One session as its line.
    public static func line(_ e: Entry) -> String {
        var parts = ["task: \(q(e.task))"]
        if !e.title.isEmpty { parts.append("title: \(q(e.title))") }
        parts.append("start: \(q(e.start))")
        if let end = e.end { parts.append("end: \(q(end))") }
        return "  - {\(parts.joined(separator: ", "))}"
    }

    public static func parse(_ text: String) throws -> File {
        let node: Node?
        do { node = try Yams.compose(yaml: text) } catch { throw Failure.yaml(TaskFile.yamlMessage(error)) }
        guard let node else { return File(device: nil, entries: []) }
        guard let map = node.mapping else { throw Failure.shape("is not a time file") }
        if let fmt = TaskFile.string(TaskFile.value(map, "format")), fmt != format, fmt.hasPrefix("nexus-time/"),
           (Int(fmt.dropFirst("nexus-time/".count)) ?? 0) > 1 {
            throw Failure.newer(fmt)
        }
        var out: [Entry] = []
        for item in TaskFile.value(map, "entries")?.sequence.map({ Array($0) }) ?? [] {
            guard let m = item.mapping, let task = TaskFile.string(TaskFile.value(m, "task")), let start = TaskFile.string(TaskFile.value(m, "start")),
                  date(start) != nil else { continue }
            let end = TaskFile.string(TaskFile.value(m, "end")).flatMap { $0.isEmpty ? nil : $0 }
            if let end, date(end) == nil { continue }
            out.append(Entry(task: task, title: TaskFile.string(TaskFile.value(m, "title")) ?? "", start: start, end: end))
        }
        return File(device: TaskFile.string(TaskFile.value(map, "device")), entries: out)
    }

    /// A session added at the end (a file that is not there yet starts with the header).
    public static func append(_ text: String?, device: String, _ e: Entry) -> String {
        var t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? header(device) : text!
        if t.range(of: #"(^|\n)entries:"#, options: .regularExpression) == nil { t = trimEnd(t) + "\nentries:\n" }
        if let r = t.range(of: #"entries:\s*\[\s*\]\s*$"#, options: .regularExpression) { t.replaceSubrange(r, with: "entries:\n") }
        return trimEnd(t) + "\n" + line(e) + "\n"
    }

    private static func trimEnd(_ s: String) -> String {
        var s = s
        while s.hasSuffix("\n") { s.removeLast() }
        return s
    }

    /// The line (0-based) of the session {task, start}; each `- {…}` line is read on its own, so a hand-written one is found too.
    static func lineIndex(_ lines: [String], task: String, start: String) -> Int? {
        let fast = "start: \(q(start))", fastTask = "task: \(q(task))"
        let want = date(start)
        for (i, l) in lines.enumerated() {
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("-") else { continue }
            let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("{"), rest.hasSuffix("}") else { continue }
            if l.contains(fast) && l.contains(fastTask) { return i }
            guard let n = try? Yams.compose(yaml: rest), let m = n.mapping else { continue }
            if TaskFile.string(TaskFile.value(m, "task")) == task, let s = TaskFile.string(TaskFile.value(m, "start")), let d = date(s), d == want { return i }
        }
        return nil
    }

    /// The session `was` changed to `e` (nil: removed) -> the new text, or nil when its line is not there.
    public static func replace(_ text: String, was: Entry, with e: Entry?) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard let i = lineIndex(lines, task: was.task, start: was.start) else { return nil }
        if let e { lines[i] = line(e) } else { lines.remove(at: i) }
        return lines.joined(separator: "\n")
    }

    // MARK: sums

    /// The timers that run, the newest first.
    public static func running(_ all: [Entry]) -> [Entry] {
        all.filter(\.running).sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// The app's day `iso` (from the day-start hour to the next one), local time.
    public static func dayRange(_ iso: String, startHour: Int = Days.dayStartHour) -> (Date, Date)? {
        guard let d = Days.date(iso), let a = Days.calendar.date(byAdding: .hour, value: startHour, to: d),
              let b = Days.calendar.date(byAdding: .day, value: 1, to: a) else { return nil }
        return (a, b)
    }

    /// The part of a session inside [from, to) in seconds.
    public static func overlap(_ e: Entry, _ from: Date, _ to: Date, now: Date = Date()) -> TimeInterval {
        guard let a = e.startDate else { return 0 }
        let b = e.end == nil ? now : (e.endDate ?? a)
        return max(0, min(b, to).timeIntervalSince(max(a, from)))
    }

    /// Seconds spent on the app's day `iso` (a session over the day's start counts on both days by its part on each).
    public static func daySeconds(_ all: [Entry], _ iso: String, startHour: Int = Days.dayStartHour, now: Date = Date(), filter: ((Entry) -> Bool)? = nil) -> TimeInterval {
        guard let (a, b) = dayRange(iso, startHour: startHour) else { return 0 }
        return all.reduce(0) { $0 + ((filter?($1) ?? true) ? overlap($1, a, b, now: now) : 0) }
    }

    /// The sessions that touch the app's day `iso`, oldest first.
    public static func sessions(on iso: String, _ all: [Entry], startHour: Int = Days.dayStartHour, now: Date = Date()) -> [Entry] {
        guard let (a, b) = dayRange(iso, startHour: startHour) else { return [] }
        return all.filter { e in
            guard let s = e.startDate else { return false }
            let end = e.end == nil ? now : (e.endDate ?? s)
            return end > a && s < b
        }.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Seconds over `days` grouped by `key` (a workstream, a task), the biggest first.
    public static func grouped(_ all: [Entry], days: [String], startHour: Int = Days.dayStartHour, now: Date = Date(), key: (Entry) -> String) -> [(key: String, seconds: TimeInterval)] {
        var m: [String: TimeInterval] = [:]
        for d in days {
            guard let (a, b) = dayRange(d, startHour: startHour) else { continue }
            for e in all { let t = overlap(e, a, b, now: now); if t > 0 { m[key(e), default: 0] += t } }
        }
        return m.map { (key: $0.key, seconds: $0.value) }.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.key < $1.key }
    }

    // MARK: words

    /// A running timer's clock: "4:05", "23:10", "1:05:12".
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds)), h = s / 3600, m = (s % 3600) / 60, x = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
    }

    /// Time spent in words: "1h 20m", "45m", "under a minute" ("" for nothing).
    public static func spent(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "" }
        let mins = Int(seconds / 60)
        if mins == 0 { return "under a minute" }
        let h = mins / 60, m = mins % 60
        return h > 0 && m > 0 ? "\(h)h \(m)m" : h > 0 ? "\(h)h" : "\(m)m"
    }

    /// "14:05" for a stamp, local time.
    public static func hm(_ stamp: String) -> String {
        guard let d = date(stamp) else { return "" }
        let c = Days.calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
