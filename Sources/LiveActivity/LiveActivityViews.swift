import AppIntents
import SwiftUI

// How a Nexus Live Activity looks. Built into the extension (the Lock Screen and the Dynamic Island, Widgets/NexusLiveActivity.swift)
// and into the app (Settings › Live Activities › See how it looks), so both draw the same thing. System type only: the extension
// doesn't carry the app's fonts.

typealias NexusLiveState = NexusActivityAttributes.ContentState

/// The round badge: the subject's colour with a timer (time tracking), red with a microphone or a camera (recording).
struct NexusLiveIcon: View {
    let kind: NexusActivityAttributes.Kind
    let state: NexusLiveState
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            Circle().fill(kind == .recording ? Color.red : NexusLive.tint(state, scheme))
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch kind {
        case .timer: return "timer"
        case .recording: return state.filming ? "video.fill" : "mic.fill"
        }
    }
}

/// The clock, counting up from the start (drawn by the system every second).
struct NexusLiveClock: View {
    let state: NexusLiveState
    var body: some View {
        Text(timerInterval: NexusLive.clockRange(state.since), countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

/// One of the activity's buttons: a small capsule (red for Stop).
struct NexusLiveButton<I: AppIntent>: View {
    let intent: I
    let label: String
    let icon: String
    var spoken: String
    var stop = false

    var body: some View {
        Button(intent: intent) { NexusLiveCapsule(label: label, icon: icon, stop: stop) }
            .buttonStyle(.plain)
            .accessibilityLabel(spoken)
    }
}

/// A button's look.
struct NexusLiveCapsule: View {
    let label: String
    let icon: String
    var stop = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold))
            Text(label).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(stop ? Color.white : Color.primary)
        .background(stop ? Color.red : Color.primary.opacity(0.12), in: Capsule())
    }
}

/// The buttons: Stop (a timer); Pin, Snap and Stop (a recording).
struct NexusLiveButtons: View {
    let kind: NexusActivityAttributes.Kind

    var body: some View {
        HStack(spacing: 8) {
            switch kind {
            case .timer:
                NexusLiveButton(intent: StopTimerLiveIntent(), label: "Stop", icon: "stop.fill", spoken: "Stop the timer", stop: true)
            case .recording:
                NexusLiveButton(intent: PinMomentLiveIntent(), label: "Pin", icon: "pin.fill", spoken: "Pin this moment")
                // Snap opens Nexus on its camera: a link, since a button runs in the background
                Link(destination: NexusLive.snapURL) { NexusLiveCapsule(label: "Snap", icon: "camera.fill") }
                    .accessibilityLabel("Snap the board")
                NexusLiveButton(intent: StopRecordingLiveIntent(), label: "Stop", icon: "stop.fill", spoken: "Stop recording", stop: true)
            }
        }
    }
}

/// The Lock Screen (and Notification Centre) card: the badge, the title and what's under it, the clock, the buttons.
struct NexusLiveLockView: View {
    let kind: NexusActivityAttributes.Kind
    let state: NexusLiveState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                NexusLiveIcon(kind: kind, state: state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(state.detail).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
                .layoutPriority(1)
                Spacer(minLength: 6)
                NexusLiveClock(state: state)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 104, alignment: .trailing)
            }
            HStack {
                Text("Nexus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                NexusLiveButtons(kind: kind)
            }
        }
        .padding(16)
    }
}
