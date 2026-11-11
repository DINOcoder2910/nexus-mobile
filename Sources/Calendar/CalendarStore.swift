import EventKit
import SwiftUI
import NexusCore

/// One event as the screens draw it. The EKEvent itself is kept so tapping it opens the system's event sheet.
struct CalEvent: Identifiable {
    let id: String
    let event: EKEvent
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
    let calendarName: String
    let location: String?

    /// "09:00 – 10:30", or "All day".
    var timeText: String {
        if allDay { return "All day" }
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// The days it touches (`YYYY-MM-DD`).
    var days: [String] { DayLayout.days(start: start, end: end) }
}

/// The phone's and the iPad's own calendars, through EventKit: whatever accounts are added in iOS Settings (Google, the school's
/// Microsoft 365 / Exchange, iCloud, subscribed ICS links) show here, and can be edited with the system's sheets. Nothing of it
/// is written to the data folder, as on the laptop (its calendar sync keeps events in its own profile, never in the files).
@Observable
final class CalendarStore {
    @ObservationIgnored let ek = EKEventStore()
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var calendars: [EKCalendar] = []
    /// Goes up when the calendar database changed (another app, an account syncing), so the screens read again.
    private(set) var version = 0

    /// Calendars switched off (their identifiers), remembered on this device.
    var hidden: Set<String> {
        didSet { UserDefaults.standard.set(Array(hidden).sorted(), forKey: "calHidden"); bump() }
    }
    /// Whether the Calendar screen draws timed planned tasks and deadlines too.
    var showTasks: Bool {
        didSet { UserDefaults.standard.set(showTasks, forKey: "calShowTasks") }
    }
    /// Whether Today and the Planner show events.
    var eventsOnPlan: Bool {
        didSet { UserDefaults.standard.set(eventsOnPlan, forKey: "calEventsOnPlan") }
    }

    @ObservationIgnored private var cache: [String: [CalEvent]] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        let d = UserDefaults.standard
        hidden = Set(d.stringArray(forKey: "calHidden") ?? [])
        showTasks = d.object(forKey: "calShowTasks") as? Bool ?? true
        eventsOnPlan = d.object(forKey: "calEventsOnPlan") as? Bool ?? true
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ek, queue: .main) { [weak self] _ in
            self?.reloadCalendars()
        }
        reloadCalendars()
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    var canRead: Bool { status == .fullAccess }
    /// Not asked yet: the screens offer a button rather than asking by themselves.
    var notAsked: Bool { status == .notDetermined }

    /// Asks for access to the calendars (the system's prompt, once).
    func requestAccess() async {
        _ = try? await ek.requestFullAccessToEvents()
        await MainActor.run {
            status = EKEventStore.authorizationStatus(for: .event)
            ek.reset()
            reloadCalendars()
        }
    }

    /// Coming back to the app: access may have changed in Settings.
    func refreshStatus() {
        let now = EKEventStore.authorizationStatus(for: .event)
        if now != status { status = now; reloadCalendars() }
    }

    func reloadCalendars() {
        guard canRead else { calendars = []; bump(); return }
        let all: [EKCalendar] = ek.calendars(for: .event)
        calendars = all.sorted { a, b in
            let sa: String = a.source?.title ?? "", sb: String = b.source?.title ?? ""
            return sa != sb ? sa < sb : a.title < b.title
        }
        bump()
    }

    private func bump() { cache = [:]; version += 1 }

    func isShown(_ c: EKCalendar) -> Bool { !hidden.contains(c.calendarIdentifier) }

    func setShown(_ c: EKCalendar, _ on: Bool) {
        if on { hidden.remove(c.calendarIdentifier) } else { hidden.insert(c.calendarIdentifier) }
    }

    /// The calendars by account ("Google", "Exchange", "iCloud", "Subscribed Calendars").
    var bySource: [CalSource] {
        var out: [CalSource] = []
        for c in calendars {
            let s: String = c.source.title
            if let i = out.firstIndex(where: { $0.source == s }) { out[i].calendars.append(c) } else { out.append(CalSource(source: s, calendars: [c])) }
        }
        return out
    }

    struct CalSource: Identifiable {
        let source: String
        var calendars: [EKCalendar]
        var id: String { source }
    }

    /// The events on the shown calendars from `first` through `last` (days, `YYYY-MM-DD`), all-day first, then by start.
    func events(from first: String, through last: String) -> [CalEvent] {
        _ = version // the screens that ask are redrawn when the calendars change
        guard canRead else { return [] }
        let key = "\(first)|\(last)"
        if let hit = cache[key] { return hit }
        let shown = calendars.filter(isShown)
        guard !shown.isEmpty, let s = Days.date(first), let lastDay = Days.date(Days.add(last, 1)) else { cache[key] = []; return [] }
        let predicate = ek.predicateForEvents(withStart: s, end: lastDay, calendars: shown)
        let found: [EKEvent] = ek.events(matching: predicate)
        var list: [CalEvent] = []
        for e in found { list.append(Self.make(e, fallback: s)) }
        list.sort(by: Self.before)
        if cache.count > 40 { cache = [:] }
        cache[key] = list
        return list
    }

    private static func make(_ e: EKEvent, fallback: Date) -> CalEvent {
        let start: Date = e.startDate ?? fallback
        let end: Date = e.endDate ?? start
        let ident: String = e.eventIdentifier ?? e.calendarItemIdentifier
        let raw: String = e.title ?? ""
        let title: String = raw.isEmpty ? "(No title)" : raw
        let calendar: EKCalendar? = e.calendar
        let color: Color = calendar.map { Color(cgColor: $0.cgColor) } ?? .secondary
        let place: String? = (e.location?.isEmpty ?? true) ? nil : e.location
        return CalEvent(id: ident + "|" + String(start.timeIntervalSince1970), event: e, title: title, start: start, end: end,
                        allDay: e.isAllDay, color: color, calendarName: calendar?.title ?? "", location: place)
    }

    /// All-day first, then by start, then by title.
    private static func before(_ a: CalEvent, _ b: CalEvent) -> Bool {
        if a.allDay != b.allDay { return a.allDay }
        if a.start != b.start { return a.start < b.start }
        return a.title < b.title
    }

    /// The events touching one day.
    func events(on day: String) -> [CalEvent] {
        events(from: day, through: day).filter { $0.days.contains(day) }
    }

    /// The next timed event today that hasn't ended, for Today's header.
    func next(today: String, now: Date = Date()) -> CalEvent? {
        events(on: today).first { !$0.allDay && $0.end > now }
    }
}
