import SwiftUI
import NexusCore

/// Settings › Share into Nexus: how to make the Shortcut that puts Nexus in the Share Sheet (SaveToNexusIntent). Free signing
/// can't carry a share extension, so the Share Sheet reaches Nexus through a Shortcut instead.
struct ShareSettings: View {
    var body: some View {
        Section {
            NavigationLink {
                ShareHowTo()
            } label: {
                Label("Share into Nexus", systemImage: "square.and.arrow.down")
            }
        } footer: {
            Text("Send a PDF, a photo or a link to Nexus from Safari, Photos, Files or Mail.")
        }
    }
}

struct ShareHowTo: View {
    @Environment(\.openURL) private var openURL

    private let steps: [(String, String)] = [
        ("Open Shortcuts and make a new shortcut", "Tap + in the Shortcuts app."),
        ("Add “Save to Nexus”", "Search for Nexus and tap Save to Nexus."),
        ("Show it in the Share Sheet", "Tap the shortcut's ⓘ (Details) and turn on Show in Share Sheet."),
        ("Pass on what was shared", "Tap Items in the Save to Nexus action and pick Shortcut Input."),
        ("Name it Nexus", "Tap the name at the top. It now shows when you tap Share in any app."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.0).font(.body.weight(.medium))
                            Text(s.1).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button {
                    if let u = URL(string: "shortcuts://create-shortcut") { openURL(u) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                }
            } header: {
                Text("Once, to set it up")
            }

            Section("Where things land") {
                Label("A PDF or a photo becomes a board in the notebook \(Shared.defaultNotebook). To use another notebook, type its name in the action's Notebook field.", systemImage: "rectangle.on.rectangle")
                Label("A link or some words become a task in the Inbox, with the link kept as it is.", systemImage: "tray")
                Label("It syncs to your other devices straight away, without opening Nexus.", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.callout)
        }
        .navigationTitle("Share into Nexus")
        .navigationBarTitleDisplayMode(.inline)
    }
}
