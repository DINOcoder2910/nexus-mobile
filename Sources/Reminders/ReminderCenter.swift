import SwiftUI
import UserNotifications
import BackgroundTasks
import NexusCore

/// Reminders on this device: the notices NexusCore's `Reminders` works out (the laptop's rules) are handed to iOS ahead of time,
/// so they come while the app is closed. They are worked out again whenever the folder, the calendars or the settings change,
/// and when iOS wakes the app in the background (a sync cycle first, so a change made on the laptop gets here).
@MainActor
@Observable
final class ReminderCenter {
    static let refreshId = "app.nexus.mobile.refresh"

    var settings: ReminderSettings {
        didSet {
            guard settings != oldValue else { return }
            if let d = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(d, forKey: "reminders") }
            if settings.on && allowed == .notDetermined { requestAccess() }
            reschedule()
        }
    }
    private(set) var allowed: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored weak var store: NexusStore?
    @ObservationIgnored weak var calendar: CalendarStore?
    @ObservationIgnored private var lastKey = ""
    @ObservationIgnored private let delegate = NoticeDelegate()

    init() {
        if let d = UserDefaults.standard.data(forKey: "reminders"), let s = try? JSONDecoder().decode(ReminderSettings.self, from: d) {
            settings = s
        } else {
            settings = ReminderSettings()
        }
        // a tapped notice opens its task in the window in front
        delegate.onTap = { id in WindowRouter.shared.openTask = id }
        UNUserNotificationCenter.current().delegate = delegate
    }

    func attach(_ store: NexusStore, _ calendar: CalendarStore) {
        self.store = store
        self.calendar = calendar
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        allowed = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if allowed == .notDetermined && settings.on && store?.snapshot.isDataFolder == true { requestAccess() }
        reschedule()
    }

    func requestAccess() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            allowed = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            lastKey = ""
            reschedule()
        }
    }

    /// Works the notices out again and gives iOS the new list (only when it changed).
    func reschedule() {
        guard let store else { return }
        let center = UNUserNotificationCenter.current()
        guard settings.on, store.snapshot.isDataFolder, allowed == .authorized || allowed == .provisional || allowed == .ephemeral else {
            if !lastKey.isEmpty || !settings.on { center.removeAllPendingNotificationRequests(); lastKey = "" }
            return
        }
        let now = Date()
        // calendar days and the clock here (the app's day starts at 04:00, but a notice is for a time on the clock)
        let today = Days.iso(now)
        let c = Calendar.current
        let nowMinute = c.component(.hour, from: now) * 60 + c.component(.minute, from: now)
        let list = Reminders.plan(store.snapshot, today: today, nowMinute: nowMinute, events: events(from: today), settings: settings)
        let key = list.map { "\($0.id)|\($0.day)|\($0.minute)|\($0.title)|\($0.body)" }.joined(separator: "\n")
        guard key != lastKey else { return }
        lastKey = key
        center.removeAllPendingNotificationRequests()
        for r in list {
            guard let day = Days.date(r.day) else { continue }
            var when = c.dateComponents([.year, .month, .day], from: day)
            when.hour = r.minute / 60
            when.minute = r.minute % 60
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.threadIdentifier = r.kind.rawValue
            if let first = r.taskIds.first { content.userInfo = ["task": first] }
            let request = UNNotificationRequest(identifier: r.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            center.add(request)
        }
    }

    /// The next week's timed events from the calendars shown in Nexus.
    private func events(from today: String) -> [ReminderEvent] {
        guard settings.events, let calendar else { return [] }
        let c = Calendar.current
        return calendar.events(from: today, through: Days.add(today, 6)).filter { !$0.allDay }.map { e in
            ReminderEvent(id: e.id, title: e.title, day: Days.iso(e.start),
                          minute: c.component(.hour, from: e.start) * 60 + c.component(.minute, from: e.start),
                          hasAlarm: e.event.hasAlarms)
        }
    }

    // MARK: background refresh

    /// Asks iOS to wake the app in a while (it decides when; usually a few times a day for an app that is used).
    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Shows a notice while the app is open too, and hands a tap to the shell.
private final class NoticeDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var onTap: (@MainActor (String) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["task"] as? String else { return }
        await MainActor.run { onTap?(id) }
    }
}
