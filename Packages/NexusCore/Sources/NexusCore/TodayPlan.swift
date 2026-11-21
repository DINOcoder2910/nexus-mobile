import Foundation

/// Today as the new laptop app has it (nexus `desktop/backend/src/plan.rs today_view`, Nov 20 2026): your list in the one day order,
/// the day's free gaps between events and timed tasks, suggested times for the first untimed tasks, Next up, Key dates, what
/// slipped, and tomorrow's shape. Pure: the screen hands in the events' times and the minute it is now.
public enum TodayPlan {
    /// The hours the day card shows and free time counts in: 8 am to 10 pm.
    public static let dayFrom = 8 * 60
    public static let dayTo = 22 * 60
    /// A timed task with no estimate takes this long on the day.
    public static let defaultBlock = 30

    /// A stretch of the day in minutes from midnight, [start, end).
    public struct Span: Equatable, Hashable {
        public var start: Int
        public var end: Int
        public init(_ start: Int, _ end: Int) { self.start = start; self.end = end }
        public var minutes: Int { end - start }
    }

    /// A suggested time for an untimed task (Plan my day, the dashed blocks on the day card).
    public struct Suggestion: Equatable {
        public var id: String
        public var title: String
        public var span: Span
    }

    /// A task that slipped: its deadline passed (`late`) or it was planned on the last planned day before today and not done.
    public struct Slip: Equatable {
        public var task: NexusTask
        /// The day it was due or planned.
        public var was: String
        public var late: Bool
    }

    public struct KeyDate: Equatable {
        public var task: NexusTask
        /// Days from today to the deadline (negative: late).
        public var days: Int
    }

    public struct Tomorrow: Equatable {
        public var date: String
        public var list: [NexusTask]
        /// Minutes planned (the tasks' own estimates).
        public var planned: Int
        /// Minutes free between 8 am and 10 pm.
        public var free: Int
        /// The longest free stretch.
        public var longest: Span?
    }

    public struct Day: Equatable {
        public var today: String
        public var now: Int
        /// Your list: planned today or due today, open, in the one order.
        public var list: [NexusTask]
        /// Ticked today (planned or due today).
        public var done: [NexusTask]
        /// Minutes the open list's estimates add up to.
        public var estLeft: Int
        /// Minutes free from now to 10 pm.
        public var freeLeft: Int
        /// The day's free gaps from 8 am (the day card's hatched blocks).
        public var gaps: [Span]
        public var suggestions: [Suggestion]
        public var next: NexusTask?
        public var keyDates: [KeyDate]
        public var slipped: [Slip]
        public var tomorrow: Tomorrow

        /// The time a task has today ("HH:MM"), if any.
        public func time(_ t: NexusTask) -> String? { t.time(on: today) }
    }

    /// A task's own estimate in minutes (0 without one).
    public static func minutes(_ t: NexusTask) -> Int { Int(((t.estHours ?? 0) * 60).rounded()) }

    /// "HH:MM" as minutes from midnight.
    public static func clock(_ hm: String?) -> Int? { DayOrder.minutes(hm) }

    /// The free gaps in [from, to) between busy stretches (a gap under 15 minutes doesn't count).
    public static func gaps(_ busy: [Span], from: Int, to: Int) -> [Span] {
        var out: [Span] = []
        var at = from
        for b in busy.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if b.end <= at { continue }
            if b.start >= to { break }
            if b.start > at && b.start - at >= 15 { out.append(Span(at, min(b.start, to))) }
            at = max(at, b.end)
        }
        if to > at && to - at >= 15 { out.append(Span(at, to)) }
        return out
    }

    /// A timed task's stretch on `day`.
    public static func span(_ t: NexusTask, on day: String) -> Span? {
        guard let s = clock(t.time(on: day)) else { return nil }
        let e = minutes(t)
        return Span(s, s + (e > 0 ? e : defaultBlock))
    }

    /// The busy stretches of a day: its timed events and its open timed tasks.
    static func busy(_ rows: [NexusTask], on day: String, events: [Span]) -> [Span] {
        events + rows.filter { !$0.done }.compactMap { span($0, on: day) }
    }

    /// Everything Today shows. `events(day)`: the timed events of a day as spans; `now`: minutes since midnight.
    public static func day(_ p: Planning, now: Int, events: (String) -> [Span]) -> Day {
        let today = p.today
        let list = p.dayPlan(on: today)
        let evs = events(today)
        let busyToday = busy(list, on: today, events: evs)
        let gapsNow = gaps(busyToday, from: max(now, dayFrom), to: dayTo)
        let gapsAll = gaps(busyToday, from: dayFrom, to: dayTo)

        let listIds = Set(list.map(\.id))
        let done = p.s.order.compactMap { p.s.tasks[$0] }
            .filter { $0.done && $0.doneOn.map { $0.hasPrefix(today) } == true && !listIds.contains($0.id) && ($0.plannedDays.contains(today) || $0.due == today) }
            .sorted { ($0.doneOn ?? "") < ($1.doneOn ?? "") }

        // Next up: a timed task going on or next; else the first in your list
        let timedNext = list.compactMap { t -> (Int, NexusTask)? in
            guard let s = span(t, on: today) else { return nil }
            let e = s.start + max(minutes(t), defaultBlock)
            return e > now ? (s.start, t) : nil
        }.min { $0.0 < $1.0 }?.1
        let next = timedNext ?? list.first { $0.time(on: today) == nil }

        // suggestions: the first two untimed tasks with an estimate, in your order, into the free gaps from now (first fit, on the
        // quarter hour)
        var sugg: [Suggestion] = []
        var free = gapsNow.map { Span(($0.start + 14) / 15 * 15, $0.end) }
        for t in list where t.time(on: today) == nil && t.hasId {
            if sugg.count >= 2 { break }
            let need = minutes(t)
            if need == 0 { continue }
            if let i = free.firstIndex(where: { $0.end - $0.start >= need }) {
                sugg.append(Suggestion(id: t.id, title: t.text, span: Span(free[i].start, free[i].start + need)))
                free[i].start = (free[i].start + need + 14) / 15 * 15
            }
        }

        let keys = p.keyDates.map { KeyDate(task: $0, days: Days.between(today, $0.due!)) }

        let tomorrowDay = Days.add(today, 1)
        let tlist = p.dayPlan(on: tomorrowDay)
        let tg = gaps(busy(tlist, on: tomorrowDay, events: events(tomorrowDay)), from: dayFrom, to: dayTo)
        let tomorrow = Tomorrow(date: tomorrowDay, list: tlist, planned: tlist.reduce(0) { $0 + minutes($1) },
                                free: tg.reduce(0) { $0 + $1.minutes }, longest: tg.max { $0.minutes < $1.minutes })

        return Day(today: today, now: now, list: list, done: done, estLeft: list.reduce(0) { $0 + minutes($1) },
                   freeLeft: gapsNow.reduce(0) { $0 + $1.minutes }, gaps: gapsAll, suggestions: sugg, next: next,
                   keyDates: keys, slipped: slipped(p), tomorrow: tomorrow)
    }

    /// What slipped, as the laptop's Today (`todayview.js slippedList`): a deadline passed with no plan from today on, then the tasks
    /// of the last planned day before today that were not done and are not planned again. Repeats and waits are left out. Least
    /// late first.
    public static func slipped(_ p: Planning) -> [Slip] {
        let today = p.today
        let open = p.open.filter { $0.every == nil && $0.everyRaw == nil && $0.waitingOn == nil }
        func ahead(_ t: NexusTask) -> Bool { t.plannedDays.contains { Days.isIso($0) && $0 >= today } }
        var out: [(Int, Slip)] = []
        var seen = Set<String>()
        for t in open where !ahead(t) {
            if let h = t.due, h < today {
                seen.insert(t.id)
                out.append((Days.between(today, h), Slip(task: t, was: h, late: true)))
            }
        }
        let carry = open.filter { !ahead($0) }.flatMap(\.plannedDays).filter { Days.isIso($0) && $0 < today }.max()
        if let cd = carry {
            for t in open where !ahead(t) && !seen.contains(t.id) && t.plannedDays.contains(cd) {
                out.append((Days.between(today, cd), Slip(task: t, was: cd, late: false)))
            }
        }
        // least late first; the same lateness keeps file order
        return out.enumerated().sorted { a, b in a.element.0 != b.element.0 ? a.element.0 > b.element.0 : a.offset < b.offset }
            .map(\.element.1)
    }
}

extension Planning {
    /// A day's list as Today has it: planned that day, and due that day without being planned for it (not a repeat), open, in the
    /// one order.
    public func dayPlan(on day: String) -> [NexusTask] {
        let planned = open.filter { $0.plannedDays.contains(day) }
        let due = open.filter { $0.due == day && !$0.plannedDays.contains(day) && $0.every == nil && $0.everyRaw == nil }
        return DayOrder.sorted(planned + due, keys: s.dayOrder[day] ?? [], dayStart: dayStart) { DayOrder.Facts(id: $0.id, time: $0.time(on: day), due: $0.due, file: $0.file, pos: $0.order) }
    }
}
