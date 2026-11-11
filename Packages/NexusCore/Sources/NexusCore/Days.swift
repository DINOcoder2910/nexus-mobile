import Foundation

/// Days are plain `YYYY-MM-DD` strings, as in the files. The app day starts at 04:00 like the laptop's ("your day lasts until
/// that hour"), so a task ticked at 1 am still lands on the evening's day.
public enum Days {
    public static var dayStartHour = 4

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }()

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func iso(_ date: Date) -> String { formatter().string(from: date) }

    public static func date(_ iso: String) -> Date? {
        guard isIso(iso) else { return nil }
        return formatter().date(from: iso)
    }

    /// Today as the app sees it (before `dayStartHour` it is still yesterday).
    public static func today(now: Date = Date()) -> String {
        iso(now.addingTimeInterval(-Double(dayStartHour) * 3600))
    }

    public static func isIso(_ s: String) -> Bool {
        let b = Array(s.utf8)
        guard b.count == 10, b[4] == 45, b[7] == 45 else { return false }
        for (i, c) in b.enumerated() where i != 4 && i != 7 { if c < 48 || c > 57 { return false } }
        return true
    }

    public static func add(_ iso: String, _ n: Int) -> String {
        guard let d = date(iso), let r = calendar.date(byAdding: .day, value: n, to: d) else { return iso }
        return self.iso(r)
    }

    /// b - a in days.
    public static func between(_ a: String, _ b: String) -> Int {
        guard let x = date(a), let y = date(b) else { return 0 }
        return calendar.dateComponents([.day], from: x, to: y).day ?? 0
    }

    /// 0 = Sunday ... 6 = Saturday, as the laptop's planner counts them.
    public static func weekday(_ iso: String) -> Int {
        guard let d = date(iso) else { return 0 }
        return calendar.component(.weekday, from: d) - 1
    }

    /// The Monday on or before `iso`.
    public static func weekStart(_ iso: String) -> String {
        let w = weekday(iso)
        return add(iso, -((w + 6) % 7))
    }

    static let shortDays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "Wed 12 Nov"
    public static func label(_ iso: String) -> String {
        guard isIso(iso), let m = Int(iso.dropFirst(5).prefix(2)), let d = Int(iso.suffix(2)) else { return iso }
        return "\(shortDays[weekday(iso)]) \(d) \(months[max(0, min(11, m - 1))])"
    }

    /// How a deadline reads next to a task: "Today", "Tomorrow", "Fri", "3 days late", "12 Nov".
    public static func relative(_ iso: String, today: String) -> String {
        guard isIso(iso) else { return iso }
        let n = between(today, iso)
        switch n {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case ..<(-1): return "\(-n) days late"
        case 2...6: return shortDays[weekday(iso)]
        default:
            let m = Int(iso.dropFirst(5).prefix(2)) ?? 1, d = Int(iso.suffix(2)) ?? 1
            return "\(d) \(months[max(0, min(11, m - 1))])"
        }
    }
}

/// An estimate as the files write it ("2h", "45m", "1h30", "0.5h", "90 min") in hours, or nil.
public func hoursOf(_ est: String?) -> Double? {
    guard var s = est?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
    s = s.replacingOccurrences(of: " ", with: "")
    if let n = Double(s) { return n }
    var hours = 0.0, num = "", found = false
    var i = s.startIndex
    while i < s.endIndex {
        let c = s[i]
        if c.isNumber || c == "." { num.append(c); i = s.index(after: i); continue }
        let rest = s[i...]
        let v = Double(num) ?? 0
        if rest.hasPrefix("hours") || rest.hasPrefix("hour") || rest.hasPrefix("hrs") || rest.hasPrefix("hr") || rest.hasPrefix("h") {
            hours += v; found = true
            for p in ["hours", "hour", "hrs", "hr", "h"] where rest.hasPrefix(p) { i = s.index(i, offsetBy: p.count); break }
        } else if rest.hasPrefix("minutes") || rest.hasPrefix("mins") || rest.hasPrefix("min") || rest.hasPrefix("m") {
            hours += v / 60; found = true
            for p in ["minutes", "mins", "min", "m"] where rest.hasPrefix(p) { i = s.index(i, offsetBy: p.count); break }
        } else { return nil }
        num = ""
    }
    if !num.isEmpty, let v = Double(num) { hours += found ? v / 60 : v; found = true } // "1h30"
    return found ? hours : nil
}

/// "1h 30m", "45m", "2h"
public func hoursText(_ h: Double) -> String {
    let mins = Int((h * 60).rounded())
    if mins < 60 { return "\(mins)m" }
    return mins % 60 == 0 ? "\(mins / 60)h" : "\(mins / 60)h \(mins % 60)m"
}
