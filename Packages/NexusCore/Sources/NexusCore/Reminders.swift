import Foundation

// The notices the iPhone and iPad schedule ahead, so iOS shows them while the app is closed. The same calm rules as the laptop's
// Windows notices (renderer/src/notifyrules.js): one digest a day for what is due today and tomorrow (not before 08:30), an
// earlier heads-up for key dates (★) a few days off in that digest, and a notice shortly before a task planned at a time.
// Done, repeating, Someday and parked tasks are never mentioned. Calendar events get a notice only when they have no alarm of
// their own (the Calendar app already tells about those).

public struct ReminderSettings: Equatable, Codable {
    public var on = true
    public var deadlines = true
    /// "HH:mm": the daily digest's time.
    public var deadlineAt = "08:30"
    /// Days before a key date for the first heads-up; 0 or 1 turns it off.
    public var keyLead = 3
    public var plans = true
    /// Minutes before a planned time or an event.
    public var lead = 10
    public var events = true
    public init() {}
}

/// A calendar event the app read, for its notice.
public struct ReminderEvent: Equatable {
    public var id: String
    public var title: String
    public var day: String
    public var minute: Int
    public var hasAlarm: Bool
    public init(id: String, title: String, day: String, minute: Int, hasAlarm: Bool) {
        self.id = id; self.title = title; self.day = day; self.minute = minute; self.hasAlarm = hasAlarm
    }
}

public struct Reminder: Equatable {
    public enum Kind: String { case deadline, plan, event }
    /// Stable for the same notice, so scheduling again replaces it instead of adding one.
    public var id: String
    public var kind: Kind
    public var day: String
    /// Minutes since the day began.
    public var minute: Int
    public var title: String
    public var body: String
    /// The tasks it is about (tapping it opens the first).
    public var taskIds: [String]
}

public enum Reminders {
    /// iOS keeps at most 64 pending notices per app; leave room.
    public static let most = 60

    /// Everything to schedule from now (`today` at `nowMinute`) for `days` days, soonest first.
    public static func plan(_ s: Snapshot, today: String, nowMinute: Int, days: Int = 7, events: [ReminderEvent] = [],
                            settings: ReminderSettings) -> [Reminder] {
        guard settings.on, Days.isIso(today) else { return [] }
        let tasks = Planning(s, today: today).open.filter { $0.every == nil && $0.everyRaw == nil && $0.hasId }
        let lastDay = Days.add(today, days - 1)
        var out: [Reminder] = []
        let isFuture = { (day: String, minute: Int) in day > today || (day == today && minute > nowMinute) }

        if settings.deadlines, let at = DayLayout.minutes(settings.deadlineAt) {
            for i in 0..<days {
                let d = Days.add(today, i)
                guard isFuture(d, at) else { continue }
                if let r = digest(tasks, day: d, at: at, keyLead: settings.keyLead) { out.append(r) }
            }
        }

        if settings.plans {
            var starts: [String: [(NexusTask, String)]] = [:]
            for t in tasks {
                for e in t.plan where e.day >= today && e.day <= lastDay {
                    guard let time = e.time, let m = DayLayout.minutes(time) else { continue }
                    starts["\(e.day) \(DayLayout.hhmm(m))", default: []].append((t, time))
                }
            }
            for (key, group) in starts {
                let day = String(key.prefix(10)), m = DayLayout.minutes(String(key.suffix(5))) ?? 0
                let fire = m - settings.lead
                guard fire >= 0, isFuture(day, fire) else { continue }
                let sorted = group.sorted { $0.0.order < $1.0.order }
                let one = sorted.count == 1
                out.append(Reminder(id: "pl:\(key)", kind: .plan, day: day, minute: fire,
                                    title: one ? short(sorted[0].0.text) : "\(sorted.count) things start at \(DayLayout.hhmm(m))",
                                    body: one ? "Starts at \(DayLayout.hhmm(m)) (in \(settings.lead) min)"
                                              : Self.list(sorted.map { Self.short($0.0.text, 50) }),
                                    taskIds: sorted.map(\.0.id)))
            }
        }

        if settings.events {
            for e in events where !e.hasAlarm && e.day >= today && e.day <= lastDay {
                let fire = e.minute - settings.lead
                guard fire >= 0, isFuture(e.day, fire) else { continue }
                out.append(Reminder(id: "ev:\(e.id):\(e.day)", kind: .event, day: e.day, minute: fire, title: short(e.title),
                                    body: "Starts at \(DayLayout.hhmm(e.minute)) (in \(settings.lead) min)", taskIds: []))
            }
        }

        out.sort { ($0.day, $0.minute, $0.id) < ($1.day, $1.minute, $1.id) }
        return Array(out.prefix(most))
    }

    /// One day's deadline notice: due that day, due the next, and key dates a few days off.
    static func digest(_ tasks: [NexusTask], day: String, at: Int, keyLead: Int) -> Reminder? {
        let tomorrow = Days.add(day, 1)
        var today: [NexusTask] = [], next: [NexusTask] = [], early: [(NexusTask, Int)] = []
        for t in tasks {
            guard let due = t.due, Days.isIso(due) else { continue }
            if due == day { today.append(t) }
            else if due == tomorrow { next.append(t) }
            else if t.key && keyLead >= 2 {
                let n = Days.between(day, due)
                if n >= 2 && n <= keyLead { early.append((t, n)) }
            }
        }
        early.sort { $0.1 < $1.1 }
        let all = today + next + early.map(\.0)
        guard let first = all.first else { return nil }
        let star = { (t: NexusTask) in t.key ? "★ " : "" }
        let body: String
        let title: String
        if all.count == 1 {
            title = short(first.text)
            body = early.first.map { "★ Key date, due in \($0.1) days" } ?? "\(star(first))Due \(today.isEmpty ? "tomorrow" : "today")"
        } else {
            let counts = [today.isEmpty ? "" : "\(today.count) today", next.isEmpty ? "" : "\(next.count) tomorrow",
                          early.isEmpty ? "" : "\(early.count) key \(early.count == 1 ? "date" : "dates") ahead"].filter { !$0.isEmpty }
            title = "\(all.count) deadlines: " + counts.joined(separator: ", ")
            body = [today.isEmpty ? "" : "Today: " + list(today.map { star($0) + short($0.text, 60) }),
                    next.isEmpty ? "" : "Tomorrow: " + list(next.map { star($0) + short($0.text, 60) }),
                    early.isEmpty ? "" : "Key dates: " + list(early.map { "\(short($0.0.text, 50)) in \($0.1) days" })]
                .filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return Reminder(id: "dl:\(day)", kind: .deadline, day: day, minute: at, title: title, body: body, taskIds: all.map(\.id))
    }

    static func short(_ s: String, _ n: Int = 70) -> String {
        let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard t.count > n else { return t }
        var cut = String(t.prefix(n - 1))
        if let sp = cut.lastIndex(of: " ") { cut = String(cut[..<sp]) }
        return cut + "…"
    }

    static func list(_ titles: [String], max: Int = 4) -> String {
        titles.prefix(max).joined(separator: ", ") + (titles.count > max ? " and \(titles.count - max) more" : "")
    }
}
