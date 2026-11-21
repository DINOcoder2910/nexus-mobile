import Foundation

/// What Today, the Planner and the Tasks lenses show, worked out from a snapshot (the iPad's half of the laptop's `planner.js`).
public struct Planning {
    public let s: Snapshot
    public let today: String

    /// The hour the day starts (a time before it is that night's, so it comes last in a day's order).
    public let dayStart: Int

    public init(_ s: Snapshot, today: String = Days.today(), dayStart: Int = Days.dayStartHour) { self.s = s; self.today = today; self.dayStart = dayStart }

    /// Every task that counts (not done, not Someday, not in a parked workstream), in file order.
    public var open: [NexusTask] { s.order.compactMap { s.tasks[$0] }.filter { !$0.done && s.counts($0) } }

    func sorted(_ ts: [NexusTask]) -> [NexusTask] { ts.sorted { $0.order < $1.order } }

    // MARK: days

    /// What the one order (DayOrder.swift) needs of a task on `day`.
    func facts(_ t: NexusTask, on day: String) -> DayOrder.Facts {
        DayOrder.Facts(id: t.id, time: t.time(on: day), due: t.due, file: t.file, pos: t.order)
    }

    /// Open tasks planned on `day`, in the one order: with a time by time, then your order of that day (`nexus-day-order.yaml`),
    /// then deadline, then file order. Never by name.
    public func planned(on day: String) -> [NexusTask] {
        DayOrder.sorted(open.filter { $0.plannedDays.contains(day) }, keys: s.dayOrder[day] ?? [], dayStart: dayStart) { facts($0, on: day) }
    }

    /// Today's plan, as the laptop's: what is planned for today and what is due today without being planned for it (not a repeat),
    /// in the one order.
    public var todayPlan: [NexusTask] {
        let planned = open.filter { $0.plannedDays.contains(today) }
        let due = open.filter { $0.due == today && !$0.plannedDays.contains(today) && $0.every == nil && $0.everyRaw == nil }
        return DayOrder.sorted(planned + due, keys: s.dayOrder[today] ?? [], dayStart: dayStart) { facts($0, on: today) }
    }

    /// Open tasks whose deadline is `day`.
    public func due(on day: String) -> [NexusTask] { open.filter { $0.due == day } }

    /// Planned for an earlier day, never for today or later, and not done: what slipped.
    public var slipped: [NexusTask] {
        open.filter { t in !t.plan.isEmpty && t.plannedDays.allSatisfy { $0 < today } && t.every == nil }
    }

    /// Deadlines today or already passed that are not on today's plan, latest first.
    public var dueNow: [NexusTask] {
        open.filter { t in t.due.map { $0 <= today } ?? false && !t.plannedDays.contains(today) && t.every == nil }
            .sorted { ($0.due ?? "", $0.file, $0.order) < ($1.due ?? "", $1.file, $1.order) }
    }

    /// Repeating tasks that fall today.
    public var repeatsToday: [NexusTask] {
        open.filter { t in
            guard let r = t.every, !t.plannedDays.contains(today),
                  let n = r.next(today: today, anchor: t.added.map { String($0.prefix(10)) } ?? t.plannedDays.first) else { return false }
            return n.live && n.day == today
        }
    }

    /// Key tasks with a deadline, soonest first (late ones included).
    public var keyDates: [NexusTask] {
        open.filter { $0.key && $0.due != nil }.sorted { ($0.due!, $0.file, $0.order) < ($1.due!, $1.file, $1.order) }
    }

    /// Hours planned on a day (a task's own estimate, else its open subtasks' total).
    public func load(on day: String) -> Double {
        planned(on: day).reduce(0) { $0 + (estimate($1) ?? 0) }
    }

    public func estimate(_ t: NexusTask) -> Double? {
        if let h = t.estHours { return h }
        let kids = s.children(of: t).filter { !$0.done }
        let sum = kids.compactMap { estimate($0) }.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    /// Open tasks not planned for today or later: the Planner's task bank (tasks first, their subtasks after them).
    public var bank: [NexusTask] {
        open.filter { t in !t.plannedDays.contains { $0 >= today } && t.every == nil }
    }

    // MARK: a task's facts

    /// "3/7" of everything under it, or nil without subtasks.
    public func progress(_ t: NexusTask) -> (done: Int, total: Int)? {
        let all = s.descendants(of: t).filter { !$0.someday || t.someday }
        return all.isEmpty ? nil : (all.filter(\.done).count, all.count)
    }

    /// "Physics HW sheet › Q1–5": the titles above a subtask.
    public func crumb(_ t: NexusTask) -> String? {
        let a = s.ancestors(of: t)
        return a.isEmpty ? nil : a.map(\.text).joined(separator: " › ")
    }

    /// The nearest deadline: its own, else the one above it.
    public func deadline(_ t: NexusTask) -> String? {
        t.due ?? s.ancestors(of: t).reversed().compactMap(\.due).first
    }

    // MARK: Tasks lenses

    public enum Lens: String, CaseIterable, Identifiable {
        case all = "All", deadlines = "Deadlines", waiting = "Waiting on", noDate = "No date", slipped = "Slipped", done = "Done", someday = "Someday"
        public var id: String { rawValue }
    }

    public func tasks(_ lens: Lens) -> [NexusTask] {
        switch lens {
        case .all: return open.filter { $0.parent == nil || (s.tasks[$0.parent!]?.done ?? true) }
        case .deadlines: return open.filter { $0.due != nil }.sorted { ($0.key ? 0 : 1, $0.due!, $0.order) < ($1.key ? 0 : 1, $1.due!, $1.order) }
        case .waiting: return open.filter { $0.waitingOn != nil }.sorted { ($0.waitingSince ?? "9", $0.order) < ($1.waitingSince ?? "9", $1.order) }
        case .noDate: return open.filter { $0.due == nil && $0.plan.isEmpty && $0.every == nil && $0.waitingOn == nil && $0.children.isEmpty }
        case .slipped: return slipped
        case .done:
            let from = Days.add(today, -14)
            return s.order.compactMap { s.tasks[$0] }.filter { $0.done && ($0.doneOn.map { $0 >= from } ?? false) }
                .sorted { ($0.doneOn ?? "", -$0.order) > ($1.doneOn ?? "", -$1.order) }
        case .someday: return s.order.compactMap { s.tasks[$0] }.filter { $0.ownSomeday && !$0.done }
        }
    }

    /// Open tasks of a workstream (or the Inbox for nil), top level, in file order.
    public func top(of workstream: String?) -> [NexusTask] {
        let file = workstream.flatMap { s.workstreams[$0]?.tasksFile } ?? "inbox.yaml"
        return (s.top[file] ?? []).compactMap { s.tasks[$0] }
    }

    /// Open tasks in a workstream (not Someday), counting every level.
    public func openCount(_ workstream: String?) -> Int {
        open.filter { $0.workstream == workstream }.count
    }
}
