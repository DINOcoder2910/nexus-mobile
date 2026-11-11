import SwiftUI
import NexusCore

/// The iPad's "Everywhere in Nexus" keys, as invisible buttons with keyboard shortcuts built from the keys in effect, so an edit on
/// Settings › Shortcuts works at once and holding ⌘ lists them in iPadOS's shortcut overlay. They stand aside while a sheet or a board
/// is open (its text fields keep ⌘Z and the rest) and while Settings records a key.
struct AppShortcutKeys: View {
    let enabled: Bool
    /// What may run now (e.g. Undo only when there is something to undo).
    let canRun: (String) -> Bool
    let perform: (String) -> Void

    struct KeyButton: Identifiable {
        let id: String
        let action: String
        let name: String
        let shortcut: KeyboardShortcut
    }

    var body: some View {
        let center = ShortcutCenter.shared
        let list: [KeyButton] = center.ipad.shortcuts.filter { $0.scope == "app" && $0.kind == .key }.flatMap { s in
            s.keys.compactMap { k in KeyMap.swiftUI(k).map { KeyButton(id: s.id + "|" + k, action: s.id, name: s.name, shortcut: $0) } }
        }
        ZStack {
            ForEach(list) { b in
                Button(b.name) { perform(b.action) }
                    .keyboardShortcut(b.shortcut)
                    .disabled(!enabled || center.capturing || !canRun(b.action))
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
