import Foundation

/// Study › Memorize: spaced repetition with FSRS (FSRS-5 with its published default weights), a port of the laptop's
/// renderer/src/studyfsrs.js. The same inputs give the same card on every device, so a deck can be reviewed on the laptop, the
/// iPad and the iPhone in turn (StudyTests checks the port against what the laptop's own code gives: StudyGolden.swift).
///
/// Times are milliseconds since 1970 (as the laptop counts them), passed in, never read from the clock here. Days are Nexus days:
/// a day starts at `Days.dayStartHour` (04:00), in `FSRS.timeZone`, so a card due in 3 days is due from the start of that day;
/// learning steps (minutes) stay on the clock.
public enum FSRS {
    public static let w: [Double] = [0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192, 1.01925,
                                     1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621]
    public static let decay = -0.5
    /// 0.9 ** (1 / DECAY) - 1: R = 90% after S days.
    public static let factor = 19.0 / 81.0
    public static let retention = 0.9
    public static let maxDays = 36500
    public static let minute: Int64 = 60_000
    public static let day: Int64 = 86_400_000

    /// The time zone days are counted in (the device's; tests set it).
    public static var timeZone = TimeZone.current

    public struct Grade: Identifiable, Hashable, Sendable {
        public let g: Int
        public let label: String
        public var id: Int { g }
    }
    public static let grades = [Grade(g: 1, label: "Again"), Grade(g: 2, label: "Hard"), Grade(g: 3, label: "Good"), Grade(g: 4, label: "Easy")]

    // MARK: the formulas

    /// Probability of recall after `days` with stability s.
    public static func retrievability(_ days: Double, _ s: Double) -> Double {
        s > 0 ? pow(1 + factor * max(0, days) / s, decay) : 0
    }

    public static func intervalDays(_ s: Double, retention: Double = retention) -> Int {
        let i = (s / factor) * (pow(retention, 1 / decay) - 1)
        return min(maxDays, max(1, Int(jsRound(i))))
    }

    static func initS(_ g: Int) -> Double { max(w[g - 1], 0.1) }
    static func initD(_ g: Int) -> Double { clamp(w[4] - exp(w[5] * Double(g - 1)) + 1, 1, 10) }
    static func nextD(_ d: Double, _ g: Int) -> Double {
        let delta = -w[6] * Double(g - 3)
        let dp = d + delta * ((10 - d) / 9) // linear damping (FSRS-5)
        return clamp(w[7] * initD(4) + (1 - w[7]) * dp, 1, 10) // mean reversion
    }
    static func recallS(_ d: Double, _ s: Double, _ r: Double, _ g: Int) -> Double {
        let hard = g == 2 ? w[15] : 1, easy = g == 4 ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hard * easy)
    }
    static func forgetS(_ d: Double, _ s: Double, _ r: Double) -> Double {
        min(s, w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14]))
    }
    static func shortS(_ s: Double, _ g: Int) -> Double { s * exp(w[17] * (Double(g) - 3 + w[18])) }

    // MARK: days

    static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }

    /// The start of the Nexus day that `ms` falls in.
    public static func dayStartOf(_ ms: Int64) -> Int64 {
        let h = Days.dayStartHour
        let cal = calendar
        let shifted = Date(timeIntervalSince1970: Double(ms - Int64(h) * 3_600_000) / 1000)
        var c = cal.dateComponents([.year, .month, .day], from: shifted)
        c.hour = h; c.minute = 0; c.second = 0
        return msOf(cal.date(from: c) ?? shifted)
    }

    /// The start of the Nexus day `days` after the one `now` falls in.
    public static func dueOnDay(_ now: Int64, _ days: Int) -> Int64 {
        let start = Date(timeIntervalSince1970: Double(dayStartOf(now)) / 1000)
        return msOf(calendar.date(byAdding: .day, value: days, to: start) ?? start)
    }

    public static func daysBetween(_ a: Int64, _ b: Int64) -> Int {
        Int(jsRound(Double(dayStartOf(b) - dayStartOf(a)) / Double(day)))
    }

    // MARK: a review

    /// The card after grade g at time now; the same inputs always give the same card. (The log is the caller's.)
    public static func review(_ card: SRSCard, _ grade: Int, _ now: Int64) -> SRSCard {
        let c = card
        let g = min(4, max(1, grade))
        var out = c
        out.reps = c.reps + 1
        out.last = now
        let days = c.last != 0 ? daysBetween(c.last, now) : 0 // whole days since the last review
        if c.state == .new {
            out.s = initS(g); out.d = initD(g)
            if g == 4 { out.state = .review; out.due = dueOnDay(now, intervalDays(out.s)) }
            else { out.state = .learning; out.due = now + Int64(g == 1 ? 1 : g == 2 ? 5 : 10) * minute }
        } else if c.state == .learning || c.state == .relearning || days < 1 {
            // same-day reviews: short-term stability
            out.s = max(0.1, shortS(c.s != 0 ? c.s : initS(3), g)); out.d = nextD(c.d != 0 ? c.d : initD(3), g)
            if g == 1 {
                out.state = c.state == .review ? .relearning : c.state
                out.due = now + 5 * minute
                if c.state == .review { out.lapses = c.lapses + 1 }
            } else if g == 2 && c.state != .review {
                out.due = now + 10 * minute
            } else {
                out.state = .review; out.due = dueOnDay(now, intervalDays(out.s))
            }
        } else {
            let r = retrievability(Double(days), c.s)
            out.d = nextD(c.d, g)
            if g == 1 { out.s = max(0.1, forgetS(c.d, c.s, r)); out.state = .relearning; out.lapses = c.lapses + 1; out.due = now + 10 * minute }
            else { out.s = recallS(c.d, c.s, r, g); out.state = .review; out.due = dueOnDay(now, intervalDays(out.s)) }
        }
        out.s = r4(out.s); out.d = r4(out.d)
        return out
    }

    public struct Preview: Hashable, Sendable {
        public let grade: Grade
        public let due: Int64
        /// "10 min", "3 days".
        public let inText: String
    }

    /// What each grade would do now.
    public static func preview(_ card: SRSCard, _ now: Int64) -> [Preview] {
        grades.map { x in
            let n = review(card, x.g, now)
            let d = n.state == .review ? daysBetween(now, n.due) : 0
            return Preview(grade: x, due: n.due, inText: d >= 1 ? dayWords(d) : inWords(n.due - now))
        }
    }

    public static func dayWords(_ d: Int) -> String {
        d < 31 ? "\(d) \(d == 1 ? "day" : "days")" : d < 365 ? "\(Int(jsRound(Double(d) / 30.4))) mo" : "\(jsNumber(jsRound(Double(d) / 365 * 10) / 10)) yr"
    }

    /// How long until `due`: minutes and hours today, else whole days.
    public static func untilWords(_ due: Int64, _ now: Int64) -> String {
        let d = daysBetween(now, due)
        return d >= 1 ? dayWords(d) : inWords(due - now)
    }

    public static func inWords(_ ms: Int64) -> String {
        let m = Int(jsRound(Double(ms) / Double(minute)))
        if m < 60 { return "\(max(1, m)) min" }
        let hh = Int(jsRound(Double(m) / 60)); if hh < 24 { return "\(hh) h" }
        let d = Int(jsRound(Double(ms) / Double(day))); if d < 31 { return "\(d) \(d == 1 ? "day" : "days")" }
        let mo = Int(jsRound(Double(d) / 30.4)); if mo < 12 { return "\(mo) mo" }
        return "\(jsNumber(jsRound(Double(d) / 365 * 10) / 10)) yr"
    }

    // MARK: a deck's counts and a session's queue

    public struct Counts: Equatable, Sendable {
        public var due = 0, new = 0, learning = 0, known = 0, total = 0
        public init(due: Int = 0, new: Int = 0, learning: Int = 0, known: Int = 0, total: Int = 0) {
            self.due = due; self.new = new; self.learning = learning; self.known = known; self.total = total
        }
    }

    /// Due now, new (never seen), learning, and known (in review and not due).
    public static func counts(_ cardIds: [String], _ states: [String: SRSCard], _ now: Int64) -> Counts {
        var c = Counts(total: cardIds.count)
        for id in cardIds {
            guard let s = states[id], s.state != .new else { c.new += 1; continue }
            if s.due <= now { c.due += 1 } else if s.state == .review { c.known += 1 } else { c.learning += 1 }
        }
        return c
    }

    /// The session's first queue: the due cards (most overdue first), then up to `newLimit` new cards in deck order.
    public static func sessionQueue(_ cardIds: [String], _ states: [String: SRSCard], _ now: Int64, newLimit: Int = 20, all: Bool = false) -> [String] {
        if all { return cardIds }
        let due = cardIds.enumerated().filter { _, id in states[id].map { $0.state != .new && $0.due <= now } ?? false }
            .sorted { a, b in let x = states[a.element]!.due, y = states[b.element]!.due; return x != y ? x < y : a.offset < b.offset }
            .map(\.element)
        let fresh = cardIds.filter { states[$0] == nil || states[$0]!.state == .new }.prefix(max(0, newLimit))
        return due + fresh
    }

    /// The cards due at or before `until` that are not in the queue and still learning (coming back within the session), soonest first.
    public static func comingBack(_ cardIds: [String], _ states: [String: SRSCard], _ until: Int64, _ queued: [String]) -> [String] {
        let q = Set(queued)
        return cardIds.enumerated().filter { _, id in
            guard !q.contains(id), let s = states[id] else { return false }
            return s.state != .new && s.state != .review && s.due <= until
        }
        .sorted { a, b in let x = states[a.element]!.due, y = states[b.element]!.due; return x != y ? x < y : a.offset < b.offset }
        .map(\.element)
    }

    // MARK: helpers

    static func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, x)) }
    static func r4(_ x: Double) -> Double { jsRound(x * 10000) / 10000 }
    /// JavaScript's Math.round: halves go up.
    static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
    static func msOf(_ d: Date) -> Int64 { Int64((d.timeIntervalSince1970 * 1000).rounded()) }
    /// A number as JavaScript's String(n) writes it ("3", "2.5").
    static func jsNumber(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e15 { return String(Int64(x)) }
        return "\(x)"
    }
}

/// One card's schedule in one direction (a line of study/review.yaml).
public struct SRSCard: Equatable, Sendable {
    public enum Phase: String, Sendable { case new, learning, review, relearning }
    public var state: Phase = .new
    /// Milliseconds; 0 for none.
    public var due: Int64 = 0
    /// Stability (days).
    public var s: Double = 0
    /// Difficulty (1-10).
    public var d: Double = 0
    public var reps = 0
    public var lapses = 0
    public var last: Int64 = 0
    /// The grades, oldest first: (time, grade 1-4, mode: flip, type, mcq).
    public var log: [LogEntry] = []

    public struct LogEntry: Equatable, Sendable {
        public var at: Int64
        public var grade: Int
        public var mode: String
        public init(at: Int64, grade: Int, mode: String) { self.at = at; self.grade = grade; self.mode = mode }
    }

    public init(state: Phase = .new, due: Int64 = 0, s: Double = 0, d: Double = 0, reps: Int = 0, lapses: Int = 0, last: Int64 = 0, log: [LogEntry] = []) {
        self.state = state; self.due = due; self.s = s; self.d = d; self.reps = reps; self.lapses = lapses; self.last = last; self.log = log
    }
}
