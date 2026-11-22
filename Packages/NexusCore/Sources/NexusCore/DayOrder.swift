import Foundation

/// One order for a day's tasks, the same as the laptop's (nexus `renderer/src/dayorder.js`; the shared cases in
/// Tests/NexusCoreTests/Fixtures/shared check both apps give the same answers):
///   1. tasks with a time that day, by time (a time before the day-start hour is that night's, after midnight, so it comes last);
///   2. then your own order for that day: the task ids as you dragged them in Today on the laptop, kept in the data folder's
///      `nexus-day-order.yaml` (one line a day, `2026-11-20: [zo03, zo01]`), so it syncs;
///   3. then by deadline, soonest first, none last;
///   4. then file order: the task file's path, then the task's place in it.
/// Never by name.
public enum DayOrder {
    public static let file = "nexus-day-order.yaml"
    /// A day older than this is dropped when the file is written.
    public static let keepDays = 14
    public static let header = "# Your own order of each day's tasks with no time, as you dragged them in Today: the task ids, one line a day.\n# Nexus writes this file on every device and drops a day older than two weeks.\n"

    /// What the order needs to know of one task on one day.
    public struct Facts {
        public var id: String
        /// The time it is planned at that day ("HH:MM"), or nil.
        public var time: String?
        public var due: String?
        /// The task file, relative to the data folder.
        public var file: String
        /// Its place in that file (any number that grows down the file).
        public var pos: Int
        public init(id: String, time: String?, due: String?, file: String, pos: Int) {
            self.id = id; self.time = time; self.due = due; self.file = file; self.pos = pos
        }
    }

    /// "HH:MM" as minutes from midnight; a time before `dayStart` o'clock is that night's (24 h later). nil when it isn't a time.
    public static func minutes(_ hm: String?, dayStart: Int = 0) -> Int? {
        guard let s = hm?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count >= 1, parts[0].count <= 2, parts[1].count == 2,
              parts[0].allSatisfy({ $0.isASCII && $0.isNumber }), parts[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              let h = Int(parts[0]), let m = Int(parts[1]), h <= 23, m <= 59 else { return nil }
        let v = h * 60 + m
        return v < dayStart * 60 ? v + 24 * 60 : v
    }

    /// Below 0: `a` goes first; above 0: `b` does.
    static func compare(_ a: Facts, _ b: Facts, rank: [String: Int], dayStart: Int) -> Int {
        let ta = minutes(a.time, dayStart: dayStart), tb = minutes(b.time, dayStart: dayStart)
        if ta != nil || tb != nil {
            guard let x = ta else { return 1 }
            guard let y = tb else { return -1 }
            if x != y { return x < y ? -1 : 1 }
        } else {
            let ra = rank[a.id] ?? Int.max, rb = rank[b.id] ?? Int.max
            if ra != rb { return ra < rb ? -1 : 1 }
        }
        let da = a.due.flatMap { Days.isIso($0) ? $0 : nil }, db = b.due.flatMap { Days.isIso($0) ? $0 : nil }
        if da != db {
            guard let x = da else { return 1 }
            guard let y = db else { return -1 }
            return x < y ? -1 : 1
        }
        if a.file != b.file {
            // by code point, as the laptop compares the same strings
            return a.file.unicodeScalars.lexicographicallyPrecedes(b.file.unicodeScalars) ? -1 : 1
        }
        return a.pos == b.pos ? 0 : (a.pos < b.pos ? -1 : 1)
    }

    /// `items` in the one order for a day: `keys` is your order of that day, `facts` what each item is on it.
    public static func sorted<T>(_ items: [T], keys: [String], dayStart: Int, facts: (T) -> Facts) -> [T] {
        var rank: [String: Int] = [:]
        for (i, k) in keys.enumerated() where rank[k] == nil { rank[k] = i }
        let f = items.map(facts)
        let idx = Array(items.indices).sorted { i, j in
            let c = compare(f[i], f[j], rank: rank, dayStart: dayStart)
            return c != 0 ? c < 0 : i < j
        }
        return idx.map { items[$0] }
    }

    // MARK: the file

    static func isId(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { c in
            (c.value >= 48 && c.value <= 57) || (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122) || c == "_" || c == "-"
        }
    }
    static let line = try! NSRegularExpression(pattern: #"^(\d{4}-\d{2}-\d{2})\s*:\s*\[([^\]]*)\]\s*(#.*)?$"#)

    /// Each day's ids. A line that isn't a day and a list of ids is left out, and so is an id that isn't letters, digits, _ or -;
    /// a day listed twice: the last line wins; a day with no ids is not there.
    public static func parse(_ text: String?) -> [String: [String]] {
        var out: [String: [String]] = [:]
        guard let text else { return out }
        for raw in text.components(separatedBy: .newlines) {
            let l = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = l as NSString
            guard let m = line.firstMatch(in: l, range: NSRange(location: 0, length: ns.length)) else { continue }
            let day = ns.substring(with: m.range(at: 1)), list = ns.substring(with: m.range(at: 2))
            var ids: [String] = []
            for x in list.split(separator: ",", omittingEmptySubsequences: false) {
                var id = x.trimmingCharacters(in: .whitespacesAndNewlines)
                if id.count >= 2, let f = id.first, f == "\"" || f == "'", id.last == f { id = String(id.dropFirst().dropLast()) }
                if isId(id) && !ids.contains(id) { ids.append(id) }
            }
            if ids.isEmpty { out.removeValue(forKey: day) } else { out[day] = ids }
        }
        return out
    }

    /// The file's text: the header, then the days in order from `today` - `keepDays` on, each with at least one id.
    public static func text(_ days: [String: [String]], today: String) -> String {
        let from = Days.isIso(today) ? Days.add(today, -keepDays) : ""
        var s = header
        for d in days.keys.sorted() where Days.isIso(d) && d >= from {
            let ids = (days[d] ?? []).filter(isId)
            if ids.isEmpty { continue }
            s += d + ": [" + ids.joined(separator: ", ") + "]\n"
        }
        return s
    }

    /// `days` with `day` set to `keys` (ids only, each once; an empty list removes the day).
    public static func with(_ days: [String: [String]], day: String, keys: [String]) -> [String: [String]] {
        var out = days, ids: [String] = []
        for k in keys where isId(k) && !ids.contains(k) { ids.append(k) }
        if ids.isEmpty { out.removeValue(forKey: day) } else { out[day] = ids }
        return out
    }
}
