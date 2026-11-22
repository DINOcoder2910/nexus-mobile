import ActivityKit
import SwiftUI

// What the app and the Live Activity extension (Widgets/) share: the activity's data, its colours and the links back into the app.
// This file is built into both targets (project.yml), so it uses nothing from the app or NexusCore.

/// One Nexus Live Activity on the iPhone's Lock Screen and in the Dynamic Island: the running timer (time tracking) or the recording
/// (a class, a meeting). The app starts, updates and ends them (LiveActivities.swift); the extension only draws them.
struct NexusActivityAttributes: ActivityAttributes, Hashable {
    enum Kind: String, Codable, Hashable {
        case timer, recording
    }

    /// What changes while it shows.
    struct ContentState: Codable, Hashable {
        /// The task's title, or the recording's kind ("Class").
        var title: String
        /// Under the title: the subject and where the timer started, or the pictures and pins so far.
        var detail: String
        /// The clock counts up from here.
        var since: Date
        /// The subject's colour (light and dark), as hex.
        var light: String
        var dark: String
        /// A recording: the SF Symbol of its kind, and whether it films.
        var icon: String = "timer"
        var filming: Bool = false
    }

    var kind: Kind
    /// Which session: the timer's task and start, or the recording's folder. Another one is a new activity (and one swiped off the
    /// Lock Screen stays off only for its own session).
    var key: String
    /// The timer's task (tapping the activity opens it).
    var task: String = ""
}

enum NexusLive {
    /// The links the Live Activity opens (the app's URL scheme, project.yml): a task's panel, Recordings.
    static func taskURL(_ id: String) -> URL { URL(string: "nexus://task/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id))! }
    static let recordingsURL = URL(string: "nexus://recordings")!
    static let snapURL = URL(string: "nexus://snap")!

    /// "#0F7A49" as a colour.
    static func color(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .green }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// The state's colour for this appearance.
    static func tint(_ s: NexusActivityAttributes.ContentState, _ scheme: ColorScheme) -> Color {
        color(scheme == .dark ? s.dark : s.light)
    }

    /// The clock's range: counting up from `since` (the system draws every second; nothing has to update it).
    static func clockRange(_ since: Date) -> ClosedRange<Date> {
        let start = min(since, Date())
        return start...start.addingTimeInterval(24 * 3600)
    }
}
