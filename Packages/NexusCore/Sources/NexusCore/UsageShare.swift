import Foundation

/// The usage numbers every device can see (nexus docs/data-format.md "Usage"; the laptop's usage-share.js and renderer/src/usage.js).
/// Each device writes only its own `usage/<device>.json` (what Nexus spent through the API key on it, the last 3 months), so the files
/// never clash, and the laptop writes `usage/plan.json`: the plan's usage as Claude Code last reported it (only Claude Code, on the laptop,
/// can read it). Pure: the files' text, adding the devices up, and the plan's bars in the laptop's words.
public enum UsageShare {
    public static let dir = "usage"
    public static let keepMonths = 3

    public static func fileName(device: String) -> String { device.lowercased() + ".json" }

    struct SpendFile: Codable {
        struct Month: Codable, Equatable { var usd: Double; var calls: Int }
        var device: String
        var months: [String: Month]
        var updated: String?
    }

    /// This device's spending file: the last 3 months, money to a tenth of a cent.
    public static func spendText(device: String, spend: ClaudeSpend, at: String) -> String {
        var months: [String: SpendFile.Month] = [:]
        for k in spend.months.keys.sorted().suffix(keepMonths) {
            let m = spend.months[k] ?? ClaudeSpend.Month()
            months[k] = SpendFile.Month(usd: (m.usd * 1000).rounded() / 1000, calls: m.calls)
        }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = (try? e.encode(SpendFile(device: device.lowercased(), months: months, updated: at))) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }
    /// The same numbers (only the time differs): no write, so no sync and no backup commit for nothing.
    public static func sameNumbers(_ a: String, _ b: String) -> Bool {
        let d = JSONDecoder()
        guard let x = try? d.decode(SpendFile.self, from: Data(a.utf8)), let y = try? d.decode(SpendFile.self, from: Data(b.utf8)) else { return false }
        return x.months == y.months
    }

    public struct Other: Equatable, Sendable {
        public let device: String, usd: Double, calls: Int
        public init(device: String, usd: Double, calls: Int) { self.device = device; self.usd = usd; self.calls = calls }
    }
    /// The other devices' spending this month: `files` are usage/'s (name, text); this device's own file and plan.json are left out, and
    /// devices with nothing that month too. Biggest first.
    public static func others(_ files: [(name: String, text: String)], month: String, device: String) -> [Other] {
        var out: [Other] = []
        for f in files {
            guard f.name.lowercased().hasSuffix(".json") else { continue }
            let stem = String(f.name.dropLast(5)).lowercased()
            if stem == "plan" || stem == device.lowercased() { continue }
            guard let js = try? JSONDecoder().decode(SpendFile.self, from: Data(f.text.utf8)), let m = js.months[month] else { continue }
            if m.usd <= 0 && m.calls == 0 { continue }
            out.append(Other(device: js.device, usd: m.usd, calls: m.calls))
        }
        return out.sorted { $0.usd > $1.usd }
    }

    public static let labels = ["laptop": "Laptop", "ipad": "iPad", "iphone": "iPhone"]
    public static func label(_ device: String) -> String { labels[device.lowercased()] ?? device }
    static func money(_ v: Double) -> String { v > 0 && v < 0.1 ? String(format: "$%.3f", v) : String(format: "$%.2f", v) }

    /// The API bar (the laptop's usage.js apiBar): this device's month plus the others, against the monthly credit (0: no bar).
    public struct ApiBar: Equatable, Sendable {
        public let fraction: Double?, main: String, sub: String, parts: String
    }
    public static func apiBar(own: ClaudeSpend.Month, credit: Double, others: [Other], device: String) -> ApiBar {
        let usd = own.usd + others.reduce(0) { $0 + $1.usd }
        let calls = own.calls + others.reduce(0) { $0 + $1.calls }
        let replies = calls > 0 ? " (\(calls) \(calls == 1 ? "reply" : "replies"))" : ""
        let parts = others.isEmpty ? "" : ([(device, own.usd)] + others.map { ($0.device, $0.usd) }).map { label($0.0) + " " + money($0.1) }.joined(separator: " · ")
        guard credit > 0 else {
            return ApiBar(fraction: nil, main: (calls > 0 ? money(usd) : "$0.00") + " this month" + replies, sub: "Type your monthly API credit below to see how much of it is used.", parts: parts)
        }
        let pct = usd / credit * 100
        return ApiBar(fraction: min(1, max(0, usd / credit)), main: money(usd) + " of " + money(credit) + " this month" + replies,
                      sub: "\(Int(pct.rounded()))% used, " + money(max(0, credit - usd)) + " left", parts: parts)
    }

    // MARK: the plan (usage/plan.json)

    public struct PlanRow: Equatable, Sendable, Identifiable {
        public let id: String, label: String, pct: Double, reset: String
    }
    public struct Plan: Equatable, Sendable {
        public let plan: String, rows: [PlanRow], at: Date?
    }
    static let windows: [(String, String)] = [("five_hour", "Current session (5 hours)"), ("seven_day", "This week, all models"), ("seven_day_opus", "This week, Opus"), ("seven_day_sonnet", "This week, Sonnet")]
    static let planNames = ["max": "Max", "pro": "Pro", "team": "Team", "enterprise": "Enterprise"]

    static func date(_ s: Any?) -> Date? {
        guard let s = s as? String else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
    static func number(_ v: Any?) -> Double? { (v as? NSNumber).map { $0.doubleValue } }

    /// When a window resets, in words: "resets in 40 min", "resets in 2 h 30 min", else "resets Sat 21:30".
    public static func resetText(_ iso: String?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let t = date(iso) else { return "" }
        let ms = t.timeIntervalSince(now) * 1000
        if ms <= 0 { return "resetting now" }
        let min = Int((ms / 60000).rounded())
        if min < 60 { return "resets in \(min) min" }
        if min < 24 * 60 { let h = min / 60, m = min % 60; return "resets in \(h) h" + (m > 0 ? " \(m) min" : "") }
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: t)
        let day = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][((c.weekday ?? 1) - 1) % 7]
        return "resets \(day) " + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// usage/plan.json -> the plan's bars, or nil when there is none (or it has no rows).
    public static func plan(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Plan? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], let L = obj["limits"] as? [String: Any] else { return nil }
        var rows: [PlanRow] = []
        let clamp = { (p: Double) in min(100, max(0, p)) }
        for (id, label) in windows {
            guard let w = L[id] as? [String: Any], let u = number(w["utilization"]) else { continue }
            rows.append(PlanRow(id: id, label: label, pct: clamp(u), reset: resetText(w["resets_at"] as? String, now: now, calendar: calendar)))
        }
        for m in (L["model_scoped"] as? [[String: Any]]) ?? [] {
            guard let name = m["display_name"] as? String, let u = number(m["utilization"]) else { continue }
            let label = "This week, " + name
            if rows.contains(where: { $0.label == label }) { continue }
            rows.append(PlanRow(id: "model:" + name, label: label, pct: clamp(u), reset: resetText(m["resets_at"] as? String, now: now, calendar: calendar)))
        }
        if let x = L["extra_usage"] as? [String: Any], (x["is_enabled"] as? Bool) == true {
            let cur = ((x["currency"] as? String) ?? "USD").uppercased()
            let amt = { (v: Double) in (cur == "USD" ? "$" : cur + " ") + String(format: "%.2f", v / 100) }
            let used = number(x["used_credits"]), limit = number(x["monthly_limit"])
            let pct = number(x["utilization"]) ?? ((limit ?? 0) > 0 && used != nil ? used! / limit! * 100 : nil)
            if let pct {
                rows.append(PlanRow(id: "extra", label: "Extra usage this month", pct: clamp(pct), reset: used.map { amt($0) + (limit.map { " of " + amt($0) } ?? "") + " spent" } ?? ""))
            }
        }
        guard !rows.isEmpty else { return nil }
        let sub = (obj["subscription"] as? String) ?? ""
        return Plan(plan: planNames[sub.lowercased()] ?? sub, rows: rows, at: date(obj["at"]))
    }
}
