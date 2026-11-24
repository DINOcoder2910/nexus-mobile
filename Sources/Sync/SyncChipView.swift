import SwiftUI
import NexusCore

/// The sync chip (the Nexus repo's docs/sync.md "The sync chip"): where this device stands with the hub in a few words (In sync,
/// Syncing 3, Offline · 2 waiting, 2 conflicts, Sync problem), as on the laptop's sidebar. Hidden while sync is off or not set up.
/// Tapping it opens Settings, where Sync says more.
struct SyncChipView: View {
    @Environment(SyncService.self) private var sync
    /// What a tap does (the iPad: show Settings); nil: a link to Settings on the navigation stack it is in (the iPhone's More).
    var open: (() -> Void)?

    var body: some View {
        let c = sync.chip
        if c.tone != .hidden {
            Group {
                if let open {
                    Button(action: open) { pill(c) }.buttonStyle(.plain)
                } else {
                    NavigationLink(value: Screen.settings) { pill(c) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(c.text)
            .accessibilityHint(c.detail)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("sync-chip")
        }
    }

    private func pill(_ c: SyncChip) -> some View {
        HStack(spacing: 6) {
            Image(systemName: Self.icon(c))
                .font(.system(size: 11, weight: .semibold))
                .symbolEffect(.pulse, isActive: c.tone == .busy)
            Text(c.text).font(.nx(.caption, .medium)).lineLimit(1)
        }
        .foregroundStyle(Self.color(c.tone))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Self.color(c.tone).opacity(0.12), in: Capsule())
        .contentShape(Capsule())
    }

    static func icon(_ c: SyncChip) -> String {
        if c.text.hasPrefix("Offline") { return "wifi.slash" }
        switch c.tone {
        case .ok: return "checkmark.circle"
        case .busy: return "arrow.triangle.2.circlepath"
        case .warn: return "exclamationmark.circle"
        case .bad: return "xmark.octagon"
        case .hidden: return "circle"
        }
    }

    static func color(_ t: SyncChip.Tone) -> Color {
        switch t {
        case .ok: return Theme.planned
        case .busy: return Theme.claude
        case .warn: return Theme.soon
        case .bad: return Theme.late
        case .hidden: return .secondary
        }
    }
}
