import ActivityKit
import SwiftUI
import WidgetKit

// The Live Activity extension (project.yml target NexusLiveActivity, bundle app.nexus.mobile.live): it only draws the activities the
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
            NexusLiveLockView(kind: context.attributes.kind, state: context.state)
                .widgetURL(url(context.attributes))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let kind = context.attributes.kind
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        NexusLiveIcon(kind: kind, state: state, size: 30)
                        Text(state.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    NexusLiveClock(state: state)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .frame(maxWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(state.detail).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 6)
                        NexusLiveButtons(kind: kind)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                NexusLiveIcon(kind: kind, state: state, size: 22)
            } compactTrailing: {
                NexusLiveClock(state: state)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: kind == .timer ? 56 : 48)
            } minimal: {
                NexusLiveIcon(kind: kind, state: state, size: 22)
            }
            .widgetURL(url(context.attributes))
            .keylineTint(kind == .recording ? .red : .green)
        }
    }

    private func url(_ a: NexusActivityAttributes) -> URL {
        a.kind == .timer ? NexusLive.taskURL(a.task) : NexusLive.recordingsURL
    }
}
