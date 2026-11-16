import Foundation

/// The day brief, the laptop's in Swift: `buildBrief` is homebrief.js (the plain-logic brief, no AI, no cost) and `facts` / `prompt` /
/// `clean` / `Cache` are claudebrief.js (Claude's written brief: at most one call a day on its own, the cheap model, facts only, no files
/// read). The app side (calling Claude, keeping the day's brief, Refresh) is Sources/Claude/DayBriefCard.swift. Same wording as the laptop.
public enum DayBrief {
    /// A passed date this many days back looks stale rather than late.
    public static let staleAfter = 14
    /// A wait older than this has "gone quiet" (the laptop's Settings › waits default).
    public static let quietAfter = 7
    /// Deadlines this many days ahead count as "soon".
    public static let soonDays = 7

    public struct Part: Equatable, Sendable {
        public var id: String
        public var text: String
    }

    public struct Stats: Equatable, Sendable {
        public var slipped = 0, stale = 0, waits = 0, quiet = 0, inbox = 0, dueToday = 0, planned = 0, open = 0, apps = 0
        public var plannedHours = 0.0
        public var oldestWait: Int?
        public var nextApp: (name: String, out: Int)? { nextAppName.map { ($0, nextAppOut) } }
        var nextAppName: String?
        var nextAppOut = 0
        public static func == (a: Stats, b: Stats) -> Bool {
            a.slipped == b.slipped && a.stale == b.stale && a.waits == b.waits && a.quiet == b.quiet && a.inbox == b.inbox && a.dueToday == b.dueToday
                && a.planned == b.planned && a.open == b.open && a.plannedHours == b.plannedHours && a.nextAppName == b.nextAppName && a.nextAppOut == b.nextAppOut
        }
    }

    public struct Brief: Equatable, Sendable {
        /// "logic" or "claude".
        public var source: String
        /// "Good morning." or "Good morning, Murtaza."
        public var greeting: String
        public var text: String
        public var parts: [Part]
        public var stats: Stats
    }

    /// A wait: the task and how many days since it started (nil without a `since`).
    public struct Wait: Equatable {
        public var task: NexusTask
        public var age: Int?
    }

    // MARK: words

    /// "3d", "5w", "4mo".
    public static func ageLabel(_ d: Int) -> String { d < 14 ? "\(d)d" : d < 120 ? "\(d / 7)w" : "\(d / 30)mo" }

    /// A short name for a task: the part before " — " or " (", cut at 42 characters.
    public static func shortName(_ title: String) -> String {
        var s = title.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let cut = s.components(separatedBy: " — ").first!.components(separatedBy: " – ").first!.components(separatedBy: " (").first!.trimmingCharacters(in: .whitespaces)
        if !cut.isEmpty { s = cut }
        if s.count > 42 {
            var t = String(s.prefix(41))
            if let r = t.range(of: #"\s+\S*$"#, options: .regularExpression) { t.removeSubrange(r) }
            s = t + "…"
        }
        return s
    }

    public static func greeting(hour: Int) -> String {
        hour < 5 ? "Still up" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }

    static func cap(_ s: String) -> String { s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst() }
    static func listOf(_ names: [String]) -> String {
        names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }
    static func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? one : many }

    // MARK: the model's facts (the laptop's planner model fields the brief reads)

    /// Open tasks with a deadline (not repeating), with how many days out it is (0 today, negative late), soonest first.
    public static func dated(_ p: Planning) -> [(task: NexusTask, out: Int)] {
        p.open.filter { $0.due != nil && Days.isIso($0.due!) && $0.every == nil && $0.everyRaw == nil }
            .map { (task: $0, out: Days.between(p.today, $0.due!)) }
            .sorted { $0.out != $1.out ? $0.out < $1.out : $0.task.text < $1.task.text }
    }

    /// Passed their deadline, with no plan today or later, and not waiting: "slipped" in the brief.
    public static func slipped(_ p: Planning) -> [(task: NexusTask, out: Int)] {
        dated(p).filter { $0.out < 0 && !$0.task.plannedDays.contains { $0 >= p.today } && $0.task.waitingOn == nil }
    }

    /// Waits, the longest first (a wait without a `since` last).
    public static func waits(_ p: Planning) -> [Wait] {
        p.open.filter { $0.waitingOn != nil }
            .map { t in Wait(task: t, age: t.waitingSince.flatMap { Days.isIso(String($0.prefix(10))) ? Days.between(String($0.prefix(10)), p.today) : nil }) }
            .sorted { ($0.age ?? -1) > ($1.age ?? -1) }
    }

    /// Applications: tasks of a school or of the applications group, or tagged APP.
    public static func apps(_ p: Planning) -> [NexusTask] {
        p.open.filter { t in
            if t.tags.contains(where: { $0.uppercased() == "APP" }) { return true }
            guard let w = t.workstream.flatMap({ p.s.workstreams[$0] }) else { return false }
            return w.kind == "school" || w.group == "applications"
        }
    }

    // MARK: the plain-logic brief (homebrief.js buildBrief)

    public static func build(_ p: Planning, now: Date = Date(), calendar: Calendar = .current, name: String = "", quietAfter: Int = quietAfter) -> Brief {
        var parts: [Part] = []
        let all = dated(p)
        let dueToday = all.filter { $0.out == 0 }.map { $0.task }
        let planned = p.planned(on: p.today)
        let hrs = planned.reduce(0.0) { $0 + ($1.estHours ?? 0) }
        let plannedBit = planned.isEmpty ? "" : "\(planned.count) \(plural(planned.count, "thing", "things")) planned\(hrs > 0 ? ", about " + hoursText(hrs) : "")"

        // 1. today
        var first: String
        if !dueToday.isEmpty {
            let names = dueToday.prefix(2).map { shortName($0.title) }
            let more = dueToday.count - names.count
            first = "\(cap(listOf(more > 0 ? names + ["\(more) more"] : Array(names)))) \(dueToday.count == 1 ? "is" : "are") due today"
            first += plannedBit.isEmpty ? "." : ", and you have \(plannedBit)."
        } else if !planned.isEmpty {
            first = "Nothing falls due today; you have \(plannedBit)."
        } else {
            first = "Nothing is due or planned for today."
        }
        parts.append(Part(id: "today", text: first))

        // 2. what passed its date without a plan
        let slip = slipped(p)
        let stale = slip.filter { $0.out < -staleAfter }.count
        if !slip.isEmpty {
            let n = slip.count
            let tail = stale * 2 >= n ? "most look stale rather than late, and I can re-date or clear them with you" : "I can re-date them with you"
            let one = (stale > 0 ? "it looks stale rather than late" : "it may just be late") + ", and I can re-date or clear it with you"
            parts.append(Part(id: "slipped", text: "\(n) older \(plural(n, "item", "items")) passed \(plural(n, "its date", "their dates")) without a plan; \(n == 1 ? one : tail)."))
        }

        // 3. waits gone quiet
        let ws = waits(p)
        let quiet = ws.filter { ($0.age ?? -1) >= quietAfter }
        if !quiet.isEmpty {
            let top = Array(quiet.prefix(2))
            let rest = quiet.count - top.count
            var s = top.count == 1
                ? "\(cap(shortName(top[0].task.title))) has been quiet for \(ageLabel(top[0].age!))"
                : "\(cap(shortName(top[0].task.title))) has been quiet for \(ageLabel(top[0].age!)) and \(shortName(top[1].task.title)) for \(ageLabel(top[1].age!))"
            if rest > 0 { s += ", with \(rest) more waiting" }
            parts.append(Part(id: "waits", text: s + "."))
        }

        // 4. next up, when today is clear
        let soon = all.filter { $0.out > 0 && $0.out <= soonDays }
        if dueToday.isEmpty, let n = soon.first {
            parts.append(Part(id: "next", text: "Next up: \(shortName(n.task.title)), \(n.out == 1 ? "due tomorrow" : "due in \(n.out) days")."))
        }

        // 5. the inbox
        let inbox = p.openCount(nil)
        if inbox > 0 { parts.append(Part(id: "inbox", text: "The inbox has \(inbox) \(plural(inbox, "thing", "things")) to file.")) }

        let appList = apps(p)
        let nextApp = all.filter { $0.out >= 0 && appList.contains($0.task) }.first
        var st = Stats()
        st.slipped = slip.count; st.stale = stale; st.waits = ws.count; st.quiet = quiet.count; st.oldestWait = ws.first?.age
        st.inbox = inbox; st.dueToday = dueToday.count; st.planned = planned.count; st.plannedHours = hrs; st.open = p.open.count
        st.apps = appList.count
        if let a = nextApp { st.nextAppName = shortName(a.task.title); st.nextAppOut = a.out }
        let hour = calendar.component(.hour, from: now)
        return Brief(source: "logic", greeting: greeting(hour: hour) + (name.isEmpty ? "" : ", " + name) + ".",
                     text: parts.map(\.text).joined(separator: " "), parts: parts, stats: st)
    }

    // MARK: Claude's written brief (claudebrief.js)

    public static let system = "You write the short day brief in Nexus, the user's personal workspace. Plain text only, calm and specific, using only the facts you are given."

    public static let example = "\"The Columbia info session starts at 09:00, so the Econ IA draft slides to after school. 6 older items passed their dates without a plan; most look stale rather than late, and I can re-date or clear them with you. The Oxford Journal has been quiet for 8d and the polymer paper for 9w.\""

    /// The facts Claude writes from: today's events (title and start "09:00"), what is due and planned, what slipped, waits gone quiet,
    /// the next application date, the inbox.
    public static func facts(_ p: Planning, brief base: Brief, events: [(title: String, start: String)] = [], quietAfter: Int = quietAfter) -> String {
        let st = base.stats
        var lines: [String] = ["Today: \(p.today)."]
        if !events.isEmpty {
            lines.append("Calendar today: " + events.prefix(6).map { $0.title + ($0.start.isEmpty ? "" : " at " + $0.start) }.joined(separator: "; ") + ".")
        }
        let all = dated(p)
        let due = all.filter { $0.out == 0 }.map { $0.task }
        if !due.isEmpty { lines.append("Due today: " + due.prefix(6).map { shortName($0.title) }.joined(separator: "; ") + (due.count > 6 ? " (+\(due.count - 6) more)" : "") + ".") }
        let planned = p.planned(on: p.today)
        if !planned.isEmpty {
            lines.append("Planned for today (\(planned.count)\(st.plannedHours > 0 ? ", about " + String(format: "%.1f", st.plannedHours) + " h" : "")): " + planned.prefix(6).map { shortName($0.title) }.joined(separator: "; ") + ".")
        }
        if st.slipped > 0 {
            lines.append("\(st.slipped) items passed their dates with no plan; \(st.stale) of them more than two weeks ago (likely stale). Examples: " + slipped(p).prefix(3).map { shortName($0.task.title) }.joined(separator: "; ") + ".")
        }
        let quiet = waits(p).filter { ($0.age ?? -1) >= quietAfter }
        if !quiet.isEmpty { lines.append("Waiting and gone quiet: " + quiet.prefix(4).map { "\(shortName($0.task.title)) (\($0.age!) days)" }.joined(separator: "; ") + ".") }
        if let a = st.nextApp { lines.append("Next application date: \(a.name), \(a.out == 0 ? "today" : "in \(a.out) days").") }
        if st.inbox > 0 { lines.append("Inbox: \(st.inbox) to file.") }
        if lines.count == 1 { lines.append("Nothing is due, planned or slipping.") }
        return lines.joined(separator: "\n")
    }

    public static func prompt(_ facts: String) -> String {
        "Write the day brief for the top of the user's Home screen from these facts. Two to four sentences, calm and specific, in the first person (\"I can re-date them with you\"). "
            + "Say what matters today, what quietly slipped, and what has gone quiet. Use only the facts given; invent nothing. Plain text: no markdown, no list, no greeting, no sign-off.\n\n"
            + "Example of the tone and shape:\n\(example)\n\nFacts:\n\(facts)"
    }

    /// Strips quotes, markdown and any lead-in; nil when nothing usable (shorter than 20 or longer than 900 characters).
    public static func clean(_ text: String) -> String? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: #"^```[a-z]*\n?|```$"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: #"(?i)^(here'?s|here is)[^\n:]*:\s*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^["“]+|["”]+$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.replacingOccurrences(of: #"\s*\n+\s*"#, with: " ", options: .regularExpression)
        return t.count >= 20 && t.count <= 900 ? t : nil
    }

    /// The day's written brief, kept on the device (never in the data folder): valid for the day it was written.
    public struct Cache: Codable, Equatable, Sendable {
        public var day: String
        public var text: String
        public var model: String
        public var generatedAt: Double
        public init(day: String, text: String, model: String, generatedAt: Double) {
            self.day = day; self.text = text; self.model = model; self.generatedAt = generatedAt
        }
        public func valid(today: String) -> Bool { !text.isEmpty && day == today }
    }
}
