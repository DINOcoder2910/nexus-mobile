import EventKit
import SwiftUI

/// Settings › Calendars: whether Nexus may read the device's calendars, which ones show, and how to add the Google and school ones.
struct CalendarSettings: View {
    @Environment(CalendarStore.self) private var cal
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if cal.canRead {
                Toggle("Events on Today and the Planner", isOn: Binding(get: { cal.eventsOnPlan }, set: { cal.eventsOnPlan = $0 }))
                Toggle("Tasks and deadlines on the Calendar", isOn: Binding(get: { cal.showTasks }, set: { cal.showTasks = $0 }))
                if cal.calendars.isEmpty {
                    Text("No calendars on this \(Device.name) yet.").foregroundStyle(.secondary)
                }
                ForEach(cal.bySource) { group in
                    DisclosureGroup(group.source) {
                        ForEach(group.calendars, id: \.calendarIdentifier) { c in
                            Toggle(isOn: Binding(get: { cal.isShown(c) }, set: { cal.setShown(c, $0) })) {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(cgColor: c.cgColor)).frame(width: 10, height: 10)
                                    Text(c.title)
                                    if !c.allowsContentModifications { Text("read only").font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }
            } else if cal.notAsked {
                Button("Show my calendars in Nexus") { Task { await cal.requestAccess() } }
            } else {
                Label("Nexus may not read your calendars.", systemImage: "lock").foregroundStyle(.secondary)
                Button("Open Settings to allow it") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Calendars")
        } footer: {
            Text("Nexus shows the calendars this \(Device.name) already has, and edits them with the system's event sheets. To add your Google calendar or the school's Microsoft 365 one, open the Settings app › Calendar › Accounts (on iOS 18 and later: Apps › Calendar › Calendar Accounts) › Add Account. If the school blocks that, publish your calendar in Outlook on the web and add its ICS link there as a Subscribed Calendar (read only). Events stay in the calendars; nothing is written to the data folder.")
        }
    }
}
