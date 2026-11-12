import SwiftUI
import NexusCore

/// Settings › Reminders: the same choices as the laptop's Notifications, for this device's own notices.
struct ReminderSettingsView: View {
    @Environment(ReminderCenter.self) private var reminders
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var r = reminders
        Section {
            Toggle("Reminders", isOn: $r.settings.on)
            if reminders.allowed == .denied && reminders.settings.on {
                Button("Notifications are off for Nexus in iOS Settings. Turn them on") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
                .font(.callout)
            }
            if reminders.settings.on {
                Toggle("Deadlines", isOn: $r.settings.deadlines)
                if reminders.settings.deadlines {
                    DatePicker("Daily notice at", selection: Binding(
                        get: { Self.date(reminders.settings.deadlineAt) },
                        set: { r.settings.deadlineAt = Self.hhmm($0) }), displayedComponents: .hourAndMinute)
                    Stepper(value: $r.settings.keyLead, in: 0...14) {
                        Text(reminders.settings.keyLead >= 2 ? "Key dates ★: \(reminders.settings.keyLead) days ahead too" : "Key dates ★: only the usual notice")
                    }
                }
                Toggle("Planned start times", isOn: $r.settings.plans)
                Toggle("Events without an alert of their own", isOn: $r.settings.events)
                if reminders.settings.plans || reminders.settings.events {
                    Stepper("\(reminders.settings.lead) min before", value: $r.settings.lead, in: 1...120, step: reminders.settings.lead < 10 ? 1 : 5)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("One notice a day for what is due today and tomorrow, and one shortly before a task planned at a time. Done, repeating and Someday tasks are left out. iOS also wakes Nexus now and then to sync, so a change made on the laptop gets here.")
        }
    }

    private static func date(_ hhmm: String) -> Date {
        let m = DayLayout.minutes(hhmm) ?? 8 * 60 + 30
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }

    private static func hhmm(_ d: Date) -> String {
        let c = Calendar.current
        return DayLayout.hhmm(c.component(.hour, from: d) * 60 + c.component(.minute, from: d))
    }
}
