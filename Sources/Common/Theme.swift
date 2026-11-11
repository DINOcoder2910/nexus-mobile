import SwiftUI
import NexusCore

/// Nexus's look on the iPad: the laptop's workstream colours and accent (themes.js), light and dark.
enum Theme {
    /// The laptop's default accent, green.
    static let accent = dynamic(light: "#0F7A49", dark: "#4FD28F")
    static let late = dynamic(light: "#B3261E", dark: "#FF8A80")
    static let soon = dynamic(light: "#9A5600", dark: "#E8A95C")
    static let planned = dynamic(light: "#007F43", dark: "#73CE95")
    static let key = dynamic(light: "#B07A00", dark: "#F5C451")

    /// A workstream's colour; one without a colour gets a stable one from its id, as the laptop's Applications do.
    static func workstream(_ stored: String?, key: String) -> Color {
        let name = WorkstreamColor.name(stored) ?? {
            var x: UInt32 = 7
            for c in key.unicodeScalars { x = x &* 31 &+ c.value }
            return WorkstreamColor.names[Int(x % UInt32(WorkstreamColor.names.count))]
        }()
        let pair = WorkstreamColor.hex[name] ?? ("#556B82", "#A2BAD4")
        return dynamic(light: pair.light, dark: pair.dark)
    }

    static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? uiColor(dark) : uiColor(light) })
    }

    static func uiColor(_ hex: String) -> UIColor {
        let c = WorkstreamColor.rgb(hex) ?? [128, 128, 128]
        return UIColor(red: c[0] / 255, green: c[1] / 255, blue: c[2] / 255, alpha: 1)
    }
}

/// A small rounded fact next to a task: a deadline, a time, an estimate.
struct Chip: View {
    var text: String
    var icon: String?
    var color: Color = .secondary
    var strong = false

    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(strong ? .semibold : .regular))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .lineLimit(1)
    }
}

/// The section header style every screen uses.
struct SectionTitle: View {
    var title: String
    var count: Int?
    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let count { Text("\(count)").foregroundStyle(.secondary) }
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
    }
}

/// A calm empty state.
struct EmptyNote: View {
    var title: String
    var detail: String?
    var icon = "checkmark.circle"
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
            if let detail { Text(detail).font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
