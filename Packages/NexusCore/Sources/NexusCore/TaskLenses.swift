import Foundation

/// The Tasks screen's lenses as the new laptop app works them out (nexus `desktop/backend/src/tasks.rs` `tasks_view`), so both apps'
/// Tasks agree: All, No date and Someday list top-level tasks (their subtasks show under them), the others every matching task.
public enum TaskLenses {
    /// Days the Done lens looks back.
    public static let doneDays = 14

    public static func rows(_ p: Planning, _ lens: Planning.Lens) -> [NexusTask] {
        let s = p.s, today = p.today
        let every = s.order.compactMap { s.tasks[$0] }
        func parkedWs(_ t: NexusTask) -> Bool { s.workstream(of: t).map { $0.status != "active" } ?? false }
        func open(_ t: NexusTask) -> Bool { !t.done && !parkedWs(t) && !t.someday }
        func top(_ t: NexusTask) -> Bool { t.parent == nil }
        func hard(_ t: NexusTask) -> String? { t.due.flatMap { Days.isIso($0) ? $0 : nil } }
        func future(_ t: NexusTask) -> Bool { t.plannedDays.contains { Days.isIso($0) && $0 >= today } }
        func title(_ a: NexusTask, _ b: NexusTask) -> Bool { a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending }
        func sameTitle(_ a: NexusTask, _ b: NexusTask) -> Bool { a.title.localizedCaseInsensitiveCompare(b.title) == .orderedSame }

        let rows = every.filter { t in
            switch lens {
            case .all: return open(t) && top(t)
            case .deadlines: return open(t) && hard(t) != nil
            case .waiting: return open(t) && t.waitingOn != nil
            case .noDate: return open(t) && top(t) && hard(t) == nil && t.waitingOn == nil && t.every == nil && t.everyRaw == nil
            case .slipped: return open(t) && t.every == nil && t.everyRaw == nil && t.waitingOn == nil && (hard(t).map { $0 < today } ?? false) && !future(t)
            case .done:
                guard t.done, !parkedWs(t), !t.someday, let d = t.doneOn.map({ String($0.prefix(10)) }), Days.isIso(d) else { return false }
                let n = Days.between(d, today)
                return n >= 0 && n < doneDays
            case .someday: return !t.done && t.someday && (t.ownSomeday || top(t))
            }
        }
        // a stable sort: the comparison, then file order
        let indexed = rows.enumerated().map { ($0.offset, $0.element) }
        func less(_ a: NexusTask, _ b: NexusTask) -> Bool? {
            switch lens {
            case .all:
                switch (hard(a), hard(b)) {
                case let (x?, y?) where x != y: return x < y
                case (.some, nil): return true
                case (nil, .some): return false
                default: return sameTitle(a, b) ? nil : title(a, b)
                }
            case .deadlines:
                if a.key != b.key { return a.key }
                if hard(a) != hard(b) { return (hard(a) ?? "") < (hard(b) ?? "") }
                return sameTitle(a, b) ? nil : title(a, b)
            case .waiting:
                if (a.waitingSince ?? "") != (b.waitingSince ?? "") { return (a.waitingSince ?? "") < (b.waitingSince ?? "") }
                return sameTitle(a, b) ? nil : title(a, b)
            case .slipped:
                if hard(a) != hard(b) { return (hard(a) ?? "") > (hard(b) ?? "") }
                return sameTitle(a, b) ? nil : title(a, b)
            case .done:
                if a.doneOn != b.doneOn { return (a.doneOn ?? "") > (b.doneOn ?? "") }
                return sameTitle(a, b) ? nil : title(a, b)
            case .someday:
                let wa = s.workstreams[a.workstream ?? ""]?.name ?? "~", wb = s.workstreams[b.workstream ?? ""]?.name ?? "~"
                if wa != wb { return wa.localizedCaseInsensitiveCompare(wb) == .orderedAscending }
                return nil
            case .noDate:
                return nil
            }
        }
        return indexed.sorted { x, y in less(x.1, y.1) ?? (x.0 < y.0) }.map(\.1)
    }

    /// How many each lens holds (Someday counts only what was itself sent there).
    public static func count(_ p: Planning, _ lens: Planning.Lens) -> Int {
        let r = rows(p, lens)
        return lens == .someday ? r.filter(\.ownSomeday).count : r.count
    }

    /// Days past its deadline (nil when not late).
    public static func late(_ t: NexusTask, today: String) -> Int? {
        guard let d = t.due, Days.isIso(d), d < today else { return nil }
        return Days.between(d, today)
    }
}
