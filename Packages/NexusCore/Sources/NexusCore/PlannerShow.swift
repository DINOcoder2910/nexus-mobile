import Foundation

/// The Planner's Show row, as the new laptop app has it (nexus `desktop/src/screens/Planner.tsx` ShowRow): what the days leave out.
/// Planned, Deadlines and Events; then the workstreams with work on the days shown (by id, the Inbox as "inbox"), each a pill that
/// hides it; then the calendars with events on them (the view's part, by name). A hidden one keeps its pill so it can come back, and
/// Show everything clears them all. Each device keeps its own (the laptop keeps it in the app, not in the data folder).
public struct PlannerShow: Equatable {
    public enum Kind: String, CaseIterable { case plan, dl, ev }

    public var kinds: Set<Kind> = []
    public var workstreams: Set<String> = []
    public var calendars: Set<String> = []

    public init(kinds: Set<Kind> = [], workstreams: Set<String> = [], calendars: Set<String> = []) {
        self.kinds = kinds; self.workstreams = workstreams; self.calendars = calendars
    }

    /// The Inbox's key among the workstreams.
    public static let inbox = "inbox"
    public static func key(_ workstream: String?) -> String { workstream ?? inbox }

    public var any: Bool { !kinds.isEmpty || !workstreams.isEmpty || !calendars.isEmpty }
    public func shows(_ k: Kind) -> Bool { !kinds.contains(k) }

    // MARK: kept as one line (the app's own settings)

    /// "k:plan|w:chem|c:School": what is hidden, as the device keeps it.
    public var text: String {
        (kinds.map { "k:" + $0.rawValue }.sorted() + workstreams.map { "w:" + $0 }.sorted() + calendars.map { "c:" + $0 }.sorted())
            .map { $0.replacingOccurrences(of: "|", with: "¦") }.joined(separator: "|")
    }

    public init(text: String) {
        for part in text.split(separator: "|") {
            let s = String(part).replacingOccurrences(of: "¦", with: "|")
            if s.hasPrefix("k:"), let k = Kind(rawValue: String(s.dropFirst(2))) { kinds.insert(k) }
            else if s.hasPrefix("w:") { workstreams.insert(String(s.dropFirst(2))) }
            else if s.hasPrefix("c:") { calendars.insert(String(s.dropFirst(2))) }
        }
    }

    public mutating func flip(_ k: Kind) { if kinds.contains(k) { kinds.remove(k) } else { kinds.insert(k) } }
    public mutating func flip(workstream w: String) { if workstreams.contains(w) { workstreams.remove(w) } else { workstreams.insert(w) } }
    public mutating func flip(calendar c: String) { if calendars.contains(c) { calendars.remove(c) } else { calendars.insert(c) } }

    // MARK: the week as shown

    /// The days without what is hidden: their deadlines and planned cards (the loads stay what is planned), and the lanes.
    public func apply(_ w: WeekPlan.Week) -> WeekPlan.Week {
        guard any else { return w }
        var out = w
        let ok = { (t: NexusTask) in !workstreams.contains(Self.key(t.workstream)) }
        out.days = w.days.map { d in
            var d = d
            d.deadlines = shows(.dl) ? d.deadlines.filter(ok) : []
            d.planned = shows(.plan) ? d.planned.filter(ok) : []
            return d
        }
        out.lanes = shows(.plan) ? w.lanes.filter { !workstreams.contains(Self.key($0.workstream)) } : []
        return out
    }

    /// The workstream pills: those with planned or due work on the days shown, in the lanes' order (the sidebar's), the Inbox last,
    /// then any hidden one that has none now (so it can come back).
    public func pills(_ w: WeekPlan.Week) -> [String] {
        var seen: [String] = []
        func add(_ k: String) { if !seen.contains(k) { seen.append(k) } }
        for l in w.lanes where l.count > 0 { add(Self.key(l.workstream)) }
        for d in w.days { for t in d.deadlines { add(Self.key(t.workstream)) } }
        for k in workstreams.sorted() { add(k) }
        return seen.enumerated().sorted { a, b in
            let ia = a.element == Self.inbox ? 1 : 0, ib = b.element == Self.inbox ? 1 : 0
            return ia != ib ? ia < ib : a.offset < b.offset
        }.map(\.element)
    }
}
