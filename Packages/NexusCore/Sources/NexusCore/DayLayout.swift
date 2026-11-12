import Foundation

/// The calendar's time grid, the pure part: where a timed thing falls on a day, and how things that overlap share the width
/// (side by side, as the laptop's Calendar draws them). Minutes count from midnight; a day on the grid runs midnight to midnight.
public enum DayLayout {
    /// Something with a start and an end on one day, in minutes from midnight.
    public struct Span: Equatable {
        public var id: String
        public var start: Int
        public var end: Int
        public init(id: String, start: Int, end: Int) { self.id = id; self.start = start; self.end = end }
    }

    /// A span with its place: column `column` of `columns` side by side.
    public struct Placed: Equatable, Identifiable {
        public var id: String
        public var start: Int
        public var end: Int
        public var column: Int
        public var columns: Int
        public init(id: String, start: Int, end: Int, column: Int, columns: Int) {
            self.id = id; self.start = start; self.end = end; self.column = column; self.columns = columns
        }
    }

    /// Side-by-side columns for overlapping spans. A cluster of spans that overlap (directly or through each other) shares one
    /// width; each span takes the first column that is free at its start. Short spans count as `minLength` long, so a 5-minute
    /// event doesn't hide under the next one. Earlier first, longer first at the same start.
    public static func place(_ spans: [Span], minLength: Int = 20) -> [Placed] {
        let sorted = spans.sorted { a, b in
            a.start != b.start ? a.start < b.start : (a.end - a.start) != (b.end - b.start) ? (a.end - a.start) > (b.end - b.start) : a.id < b.id
        }
        var out: [Placed] = []
        var cluster: [Int] = []          // indexes into out
        var columnEnds: [Int] = []       // where each column of the cluster is free again
        var clusterEnd = Int.min

        func close() {
            for i in cluster { out[i].columns = columnEnds.count }
            cluster = []; columnEnds = []
        }

        for s in sorted {
            let end = max(s.end, s.start + minLength)
            if s.start >= clusterEnd { close(); clusterEnd = Int.min }
            let col = columnEnds.firstIndex { $0 <= s.start } ?? columnEnds.count
            if col == columnEnds.count { columnEnds.append(end) } else { columnEnds[col] = end }
            out.append(Placed(id: s.id, start: s.start, end: s.end, column: col, columns: 1))
            cluster.append(out.count - 1)
            clusterEnd = max(clusterEnd, end)
        }
        close()
        return out
    }

    /// The part of [start, end) that falls on `day` (`YYYY-MM-DD`, midnight to midnight), in minutes; nil when none does.
    /// An event past midnight is cut at the day's edges, so it shows on both days.
    public static func clip(start: Date, end: Date, day: String) -> (start: Int, end: Int)? {
        guard let d0 = Days.date(day), let d1 = Days.calendar.date(byAdding: .day, value: 1, to: d0) else { return nil }
        if end <= start {
            guard start >= d0, start < d1 else { return nil }
            let m = Int((start.timeIntervalSince(d0) / 60).rounded(.down))
            return (m, m)
        }
        let s = max(start, d0), e = min(end, d1)
        guard s < e else { return nil }
        let a = Int((s.timeIntervalSince(d0) / 60).rounded(.down))
        let b = Int((e.timeIntervalSince(d0) / 60).rounded(.up))
        return (a, min(b, 24 * 60))
    }

    /// The days (`YYYY-MM-DD`) an all-day or timed span touches; an end exactly at midnight doesn't touch the next day.
    public static func days(start: Date, end: Date) -> [String] {
        let first = Days.iso(start)
        let last = Days.iso(end > start ? end.addingTimeInterval(-1) : start)
        var out = [first]
        var d = first
        while d < last && out.count < 400 { d = Days.add(d, 1); out.append(d) }
        return out
    }

    /// "09:30" -> 570; nil when it isn't a time.
    public static func minutes(_ hhmm: String?) -> Int? {
        guard let s = hhmm else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// 570 -> "09:30", as the task files write times.
    public static func hhmm(_ minutes: Int) -> String {
        let m = max(0, min(23 * 60 + 59, minutes))
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// The first day of the month `iso` is in.
    public static func monthStart(_ iso: String) -> String {
        guard Days.isIso(iso) else { return iso }
        return String(iso.prefix(8)) + "01"
    }

    /// The first day of the month `n` months after the one `iso` is in.
    public static func addMonths(_ iso: String, _ n: Int) -> String {
        guard let d = Days.date(monthStart(iso)), let r = Days.calendar.date(byAdding: .month, value: n, to: d) else { return iso }
        return Days.iso(r)
    }

    /// The month grid: six weeks from the Monday on or before the 1st.
    public static func monthGrid(_ iso: String) -> [String] {
        let first = Days.weekStart(monthStart(iso))
        return (0..<42).map { Days.add(first, $0) }
    }
}
