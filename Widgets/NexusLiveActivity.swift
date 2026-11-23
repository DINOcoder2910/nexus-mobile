import ActivityKit
import SwiftUI
import WidgetKit

// The Live Activity extension (project.yml target NexusLiveActivity, bundle app.nexus.mobile.live): it only draws the one activity the
// app starts (Sources/LiveActivity/LiveActivities.swift). Its views and buttons are shared with the app (Sources/LiveActivity/).
// Only the iPhone's download carries it (build.yml): it needs one more App ID under free signing, and the iPad has no use for it.

@main
struct NexusWidgets: WidgetBundle {
    var body: some Widget {
        NexusLiveWidget()
    }
}

struct NexusLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NexusActivityAttributes.self) { context in
            NexusLiveLockView(state: context.state)
                .widgetURL(NexusLive.url(context.state))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            let line = state.line(at: Date())
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NexusLiveIcon(state: state, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                            Text(state.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if state.clocks(Date()) || (state.focus == .next && state.timed) {
                        NexusLiveClock(state: state)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .frame(maxWidth: 96, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        NexusLiveEstimate(state: state)
                        if let line { NexusLiveLineRow(line: line) }
                        HStack {
                            NexusLiveDay(state: state)
                            Spacer(minLength: 6)
                            NexusLiveButtons(state: state)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                NexusLiveIcon(state: state, size: 22)
            } compactTrailing: {
                if state.clocks(Date()) {
                    NexusLiveClock(state: state)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 56)
                } else {
                    // nothing counts: how far the day has got
                    Text(state.total > 0 ? "\(state.done)/\(state.total)" : "")
                        .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
            } minimal: {
                NexusLiveIcon(state: state, size: 22)
            }
            .widgetURL(NexusLive.url(state))
            .keylineTint(state.focus == .recording ? .red : NexusLive.color(state.dark))
        }
    }
}
