import AppIntents
import SwiftUI

// How the Nexus Live Activity looks. Built into the extension (the Lock Screen and the Dynamic Island, Widgets/NexusLiveActivity.swift)
// and into the app (Settings › Lock Screen › See how it looks), so both draw the same thing. System type only: the extension
// doesn't carry the app's fonts.

/// The round badge: the subject's colour with a timer (time tracking) or an arrow (up next), red with a microphone or a camera
/// (recording), green with a tick (the day is clear).
struct NexusLiveIcon: View {
    let state: NexusLiveState
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(NexusLive.tint(state, scheme))
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch state.focus {
        case .timer: return "timer"
        case .recording: return state.filming ? "video.fill" : "mic.fill"
        case .next: return "arrow.forward"
        case .clear: return "checkmark"
        }
    }
}

/// The big clock: up from the timer's or the recording's start, down to the next task (drawn by the system every second), "Now"
/// once the next task's time has come.
struct NexusLiveClock: View {
    let state: NexusLiveState

    var body: some View {
        let now = Date()
        Group {
            if state.ahead(now) {
                Text(timerInterval: NexusLive.countdownRange(state.since), countsDown: true)
            } else if state.focus == .next && state.timed {
                Text("Now")
            } else {
                Text(timerInterval: NexusLive.clockRange(state.since), countsDown: false)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

/// One of the activity's buttons: a small capsule (red for Stop, the subject's colour for Start), with or without its word.
struct NexusLiveButton<I: AppIntent>: View {
    let intent: I
    var label: String = ""
    let icon: String
    var spoken: String
    var style: NexusLiveCapsule.Style = .plain

    var body: some View {
        Button(intent: intent) { NexusLiveCapsule(label: label, icon: icon, style: style) }
            .buttonStyle(.plain)
            .accessibilityLabel(spoken)
    }
}

/// A button's look.
struct NexusLiveCapsule: View {
    enum Style { case plain, stop, go(Color) }
    var label: String = ""
    let icon: String
    var style: Style = .plain

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            if !label.isEmpty { Text(label).font(.system(size: 14, weight: .semibold)) }
        }
        .padding(.horizontal, label.isEmpty ? 10 : 12).padding(.vertical, 7)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
    }

    private var fg: Color {
        if case .plain = style { return .primary }
        return .white
    }

    private var bg: Color {
        switch style {
        case .plain: return Color.primary.opacity(0.12)
        case .stop: return .red
        case .go(let c): return c
        }
    }
}

/// The buttons: Done and Stop (a timer); Pin, Snap and Stop (a recording); Done and Start (the next task).
struct NexusLiveButtons: View {
    let state: NexusLiveState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 7) {
            switch state.focus {
            case .timer:
                NexusLiveButton(intent: DoneTaskLiveIntent(task: state.task), icon: "checkmark", spoken: "Tick it off")
                NexusLiveButton(intent: StopTimerLiveIntent(), label: "Stop", icon: "stop.fill", spoken: "Stop the timer", style: .stop)
            case .recording:
                NexusLiveButton(intent: PinMomentLiveIntent(), icon: "pin.fill", spoken: "Pin this moment")
                // Snap opens Nexus on its camera: a link, since a button runs in the background
                Link(destination: NexusLive.snapURL) { NexusLiveCapsule(icon: "camera.fill") }
                    .accessibilityLabel("Snap the board")
                NexusLiveButton(intent: StopRecordingLiveIntent(), label: "Stop", icon: "stop.fill", spoken: "Stop recording", style: .stop)
            case .next:
                if !state.task.isEmpty {
                    NexusLiveButton(intent: DoneTaskLiveIntent(task: state.task), icon: "checkmark", spoken: "Tick it off")
                    NexusLiveButton(intent: StartTaskLiveIntent(task: state.task), label: "Start", icon: "play.fill", spoken: "Start the timer on it",
                                    style: .go(NexusLive.tint(state, scheme)))
                }
            case .clear:
                EmptyView()
            }
        }
    }
}

/// The line under the big row: an icon in its colour, what it is, and its clock (running), its time, or "now" (an event on now).
struct NexusLiveLineRow: View {
    let line: NexusLiveLine
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let now = Date()
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(NexusLive.tint(line, scheme))
                .frame(width: 16)
            Text(line.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 6)
            Group {
                switch line.kind {
                case .timer, .recording:
                    Text(timerInterval: NexusLive.clockRange(line.at), countsDown: false).monospacedDigit().frame(maxWidth: 64, alignment: .trailing)
                case .event, .task:
                    if line.at > now {
                        Text("at ") + Text(line.at, style: .time)
                    } else if let end = line.end {
                        Text("now, until ") + Text(end, style: .time)
                    } else {
                        Text("now")
                    }
                }
            }
            .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            if line.kind == .timer {
                // a timer under a recording: it can stop too
                Button(intent: StopTimerLiveIntent()) {
                    Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 24, height: 20).background(Color.red, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop the timer")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(minHeight: 28)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var symbol: String {
        switch line.kind {
        case .timer: return "timer"
        case .recording: return "mic.fill"
        case .event: return "calendar"
        case .task: return "circle"
        }
    }
}

/// The day: a bar and "3 of 7 done", and the time tracked today (counting while a timer runs).
struct NexusLiveDay: View {
    let state: NexusLiveState
    /// Right-aligned (the Lock Screen card's right side).
    var trailing = false

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            if state.total > 0 {
                HStack(spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.15))
                            Capsule().fill(Color.green).frame(width: max(5, g.size.width * CGFloat(state.done) / CGFloat(max(state.total, 1))))
                        }
                    }
                    .frame(width: 54, height: 5)
                    Text("\(state.done) of \(state.total) done")
                }
            } else {
                Text("Nothing planned")
            }
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 10, weight: .bold))
                if state.counting {
                    Text(timerInterval: NexusLive.clockRange(state.stamp.addingTimeInterval(-state.tracked)), countsDown: false)
                        .monospacedDigit().frame(maxWidth: 58, alignment: .leading)
                } else {
                    Text(NexusLive.spent(state.tracked))
                }
                Text("today")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// The task's estimate as a bar that fills while its timer runs (the system draws it).
struct NexusLiveEstimate: View {
    let state: NexusLiveState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if state.focus == .timer && state.minutes > 0 {
            let end = state.since.addingTimeInterval(Double(state.minutes) * 60)
            ProgressView(timerInterval: min(state.since, Date())...max(end, state.since.addingTimeInterval(60)), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(NexusLive.tint(state, scheme))
            .frame(height: 4)
        }
    }
}

/// The big number: the clock up from the timer's or the recording's start, down to the next task, or a word when nothing counts.
struct NexusLiveBig: View {
    let state: NexusLiveState

    var body: some View {
        Group {
            if state.clocks(Date()) || (state.focus == .next && state.timed) {
                NexusLiveClock(state: state).font(.system(size: 44, weight: .semibold, design: .rounded))
            } else {
                Text(state.focus == .clear ? (state.done > 0 ? "All done" : "Free") : "Up next")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(height: 46, alignment: .leading)
    }
}

/// The Lock Screen (and Notification Centre) card, as tall as iOS lets it be (160 points): the badge, the title and what's under
/// it, and the buttons; the big clock (with the bar toward the estimate) beside the day's ticks and time tracked; then the line of
/// what else runs or comes next.
struct NexusLiveLockView: View {
    let state: NexusLiveState

    var body: some View {
        let line = state.line(at: Date())
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                NexusLiveIcon(state: state, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(state.detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                NexusLiveButtons(state: state)
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    NexusLiveBig(state: state)
                    NexusLiveEstimate(state: state).frame(maxWidth: 180)
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                NexusLiveDay(state: state, trailing: true)
            }
            if let line {
                NexusLiveLineRow(line: line)
            } else {
                Text(state.focus == .clear ? "Nothing else on today" : "Nothing else timed today")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
