import ActivityKit
import SwiftUI

// What the app and the Live Activity extension (Widgets/) share: the activity's data, its colours and the links back into the app.
// This file is built into both targets (project.yml), so it uses nothing from the app or NexusCore.

/// The one Nexus Live Activity on the iPhone's Lock Screen and in the Dynamic Island (Nov 23 2026, Murtaza: one big card, not one
/// per thing): its big row is what matters now (the recording, else the running timer, else the task up next, else the day is
/// clear), a line under it shows the other thing that runs or what comes next (a class, a timed task), and its foot the day: how
/// many of today's tasks are done and the time tracked today. The app starts and updates it (LiveActivities.swift); the extension
/// only draws it.
struct NexusActivityAttributes: ActivityAttributes, Hashable {
    /// What the big row is about.
    enum Focus: String, Codable, Hashable {
        case timer, recording, next, clear
    }

    /// A line under the big row: the other thing that runs (a timer under a recording), or what comes next.
    struct Line: Codable, Hashable {
        enum Kind: String, Codable, Hashable { case timer, recording, event, task }
        var kind: Kind
        var title: String
        /// When it starts (an event, a timed task) or started (a timer, a recording).
        var at: Date
        /// An event's end.
        var end: Date?
        var light: String
        var dark: String
    }

    /// What changes while it shows.
    struct ContentState: Codable, Hashable {
        var focus: Focus
        /// The task's title, the recording's kind ("Class"), or "All done for today".
        var title: String
        /// Under the title: the subject and where the timer started, the pictures and pins so far, or when the next task is.
        var detail: String
        /// The timer's or the recording's start (the clock counts up from it), or when the next task starts (it counts down to it).
        var since: Date
        /// The next task has a time today (else there's no countdown).
        var timed: Bool = true
        /// The subject's colour (light and dark), as hex.
        var light: String
        var dark: String
        /// A recording: whether it films.
        var filming: Bool = false
        /// The timer's or the next task's id (its buttons and the link to it).
        var task: String = ""
        /// The task's estimate in minutes: the timer's bar fills toward it (0: no bar).
        var minutes: Int = 0
        /// The lines under the big row, the running one first, then what comes next by time (at most three; the card shows the
        /// first that hasn't passed).
        var lines: [Line] = []
        /// Today's tasks: ticked, and all of them.
        var done: Int = 0
        var total: Int = 0
        /// Seconds tracked today up to `stamp`; `counting`: a timer runs, so it goes on counting from there.
        var tracked: Double = 0
        var counting: Bool = false
        var stamp: Date = Date()
    }

    /// One activity at a time: the same one is updated from the Lock Screen's buttons too (iOS lets only an app in front start one).
    var key: String = "nexus"
}

typealias NexusLiveState = NexusActivityAttributes.ContentState
typealias NexusLiveLine = NexusActivityAttributes.Line

extension NexusActivityAttributes.ContentState {
    /// The line the card shows at `now`: the running one, else the first event that hasn't ended or timed task that hasn't started.
    func line(at now: Date) -> NexusLiveLine? {
        lines.first { l in
            switch l.kind {
            case .timer, .recording: return true
            case .event: return (l.end ?? l.at) > now
            case .task: return l.at > now
            }
        }
    }

    /// The next task's countdown is still to come.
    func ahead(_ now: Date) -> Bool { focus == .next && timed && since > now }

    /// The clock counts (up for a timer or a recording, down to the next task).
    func clocks(_ now: Date) -> Bool { focus == .timer || focus == .recording || ahead(now) }
}

enum NexusLive {
    /// The links the Live Activity opens (the app's URL scheme, project.yml): a task's panel, Recordings, Today.
    static func taskURL(_ id: String) -> URL { URL(string: "nexus://task/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id))! }
    static let recordingsURL = URL(string: "nexus://recordings")!
    static let snapURL = URL(string: "nexus://snap")!
    static let todayURL = URL(string: "nexus://today")!

    static func url(_ s: NexusLiveState) -> URL {
        switch s.focus {
        case .recording: return recordingsURL
        case .timer, .next: return s.task.isEmpty ? todayURL : taskURL(s.task)
        case .clear: return todayURL
        }
    }

    /// "#0F7A49" as a colour.
    static func color(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return .green }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// The state's colour for this appearance.
    static func tint(_ s: NexusLiveState, _ scheme: ColorScheme) -> Color {
        s.focus == .recording ? .red : color(scheme == .dark ? s.dark : s.light)
    }

    static func tint(_ l: NexusLiveLine, _ scheme: ColorScheme) -> Color {
        l.kind == .recording ? .red : color(scheme == .dark ? l.dark : l.light)
    }

    /// Counting up from `since` (the system draws every second; nothing has to update it).
    static func clockRange(_ since: Date) -> ClosedRange<Date> {
        let start = min(since, Date())
        return start...start.addingTimeInterval(24 * 3600)
    }

    /// Counting down to `at`.
    static func countdownRange(_ at: Date) -> ClosedRange<Date> {
        let now = Date()
        return now...max(at, now)
    }

    /// "2h 15m", "40m", "0m".
    static func spent(_ seconds: Double) -> String {
        let m = Int(seconds / 60)
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m)m"
    }
}

/// The Home Screen widgets (Widgets/NexusHomeWidget.swift, Nov 23 2026): they live in the Live Activity's extension, so they need no
/// App ID or sideload slot of their own. Free signing gives the app and the extension no shared folder, so the app puts the day's card
/// (the same state the Live Activity shows) into the data folder's `widgets/<device>.json`, sync carries it to the hub, and the widget
/// reads it from the hub with a widget key (the hub's address and token) pasted once into Edit Widget.
enum NexusWidgetShare {
    static let dir = "widgets"
    /// The data folder's file for a device ("widgets/iphone.json").
    static func path(device: String) -> String { dir + "/" + device.lowercased() + ".json" }

    /// What the file and the key say, in JSON with ISO dates.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// The file: `{"format": "nexus-widget/1", "device", "updated", "state"}`.
    struct File: Codable {
        var format = "nexus-widget/1"
        var device: String
        var updated: Date
        var state: NexusLiveState
    }

    /// The widget key: the hub's address, its token and which device's card to show, as one line to paste.
    struct Key: Codable, Equatable {
        var hub: String
        var token: String
        var device: String

        static let prefix = "nexus-widget:"

        var text: String {
            let data = (try? NexusWidgetShare.encoder.encode(self)) ?? Data()
            return Key.prefix + data.base64EncodedString()
        }

        /// What was pasted: the key's line (spaces and line breaks the paste added are dropped); nil if it isn't one.
        init?(_ text: String) {
            var t = text.components(separatedBy: .whitespacesAndNewlines).joined()
            guard t.hasPrefix(Key.prefix) else { return nil }
            t.removeFirst(Key.prefix.count)
            guard let data = Data(base64Encoded: t), let k = try? NexusWidgetShare.decoder.decode(Key.self, from: data),
                  !k.hub.isEmpty, !k.token.isEmpty else { return nil }
            self = k
        }

        init(hub: String, token: String, device: String) { self.hub = hub; self.token = token; self.device = device }
    }
}
