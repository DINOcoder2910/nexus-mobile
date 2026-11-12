import SwiftUI
import NexusCore

/// The Plan / API chip that sits beside every Claude feature on the iPad. A tap flips the one app-wide setting (ClaudeAccount); a flip to
/// API without a key opens a small form for the key right there, so the switch is always where the feature is. The note the flip leaves
/// ("Claude now uses your API key everywhere. $0.21 this month") shows under the chip that was tapped for a few seconds.
struct ClaudeModeChip: View {
    var small = false
    private var account: ClaudeAccount { .shared }
    @State private var mine = false
    @State private var askKey = false

    var body: some View {
        let api = account.mode == .api
        Button {
            mine = true
            if !account.setMode(api ? .plan : .api) { askKey = true }
        } label: {
            Text(account.mode.chip)
                .font((small ? Font.caption2 : Font.caption).weight(.semibold))
                .padding(.horizontal, small ? 7 : 9)
                .frame(height: small ? 20 : 24)
                .foregroundStyle(api ? Theme.claude : Color.secondary)
                .background(Capsule().fill(api ? Theme.claudeTint : Color.clear))
                .overlay(Capsule().strokeBorder(api ? Theme.claude.opacity(0.35) : Color.secondary.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(api ? "Claude uses your API key. Tap to use your plan." : "Claude uses your plan. Tap to use your API key.")
        .help(api ? "Claude uses your API key (\(account.spendText)). Tap to use your plan everywhere." : "Claude uses your plan. Tap to use your API key everywhere.")
        .overlay(alignment: .top) {
            if mine, let note = account.notice, !askKey {
                Text(note)
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .fixedSize()
                    .offset(y: small ? 26 : 30)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.2), value: account.notice)
        .onChange(of: account.notice) { _, now in if now == nil { mine = false } }
        .popover(isPresented: $askKey) {
            ClaudeKeyForm(switchAfter: true) { askKey = false }
                .padding(20)
                .frame(width: 380)
        }
    }
}

/// Paste and save the API key. With `switchAfter`, a saved key also turns API mode on (the chip's "API without a key" path).
struct ClaudeKeyForm: View {
    var switchAfter = false
    var done: () -> Void = {}
    private var account: ClaudeAccount { .shared }
    @State private var key = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add your API key").font(.headline)
            Text("Claude then uses your key everywhere in Nexus on this iPad. It stays in the iPad's Keychain; only its last 4 characters are shown again.")
                .font(.callout).foregroundStyle(.secondary)
            SecureField("sk-ant-…", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if let problem { Text(problem).font(.caption).foregroundStyle(Theme.late) }
            HStack {
                Spacer()
                Button("Cancel", action: done)
                Button("Save", action: save).buttonStyle(.borderedProminent).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        do {
            try account.setKey(key)
            key = ""
            problem = nil
            if switchAfter { account.setMode(.api) }
            done()
        } catch {
            problem = (error as? ClaudeError)?.message ?? error.localizedDescription
        }
    }
}
