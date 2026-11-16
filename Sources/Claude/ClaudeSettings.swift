import SwiftUI
import NexusCore

/// Settings › Claude on the iPad: the one switch (plan or API key) for every Claude feature, the key, and what the key spent this month.
/// The Plan / API chip beside each feature flips the same setting. The section sits inside SettingsView's Form.
struct ClaudeSettings: View {
    private var account: ClaudeAccount { .shared }
    @State private var addingKey = false
    @State private var wantsAPI = false

    @AppStorage("claude.model") private var chatModel = "sonnet"
    @AppStorage("claude.briefModel") private var briefModel = "haiku"
    @AppStorage("claude.dayHours") private var dayHours = 6.0

    var body: some View {
        Section {
            Picker("Claude uses", selection: Binding(get: { account.mode }, set: { m in if !account.setMode(m) { wantsAPI = true; addingKey = true } })) {
                Text("Your plan").tag(ClaudeMode.plan)
                Text("API key").tag(ClaudeMode.api)
            }
            .pickerStyle(.segmented)

            if account.hasKey {
                LabeledContent("API key", value: "Ends in …\(account.last4)")
                Button("Replace the key…") { addingKey = true }
                Button("Remove the key", role: .destructive) { account.clearKey() }
            } else {
                Button("Add your API key…") { addingKey = true }
            }
            LabeledContent("Spent with the key", value: account.spendText)
            if let note = account.notice { Text(note).font(.callout).foregroundStyle(.secondary) }
        } header: {
            Text("Claude")
        } footer: {
            Text("One switch for every Claude feature on this iPad; the Plan / API chip beside each one flips it too. API uses your key from the Claude Console and answers fastest, anywhere. Your plan runs on your computer through the hub: the Duo when Nexus is open there, otherwise the G14. Spending counts only this iPad's API replies; the laptop has its own switch.")
        }
        Section {
            Picker("Conversation model", selection: $chatModel) {
                Text("Sonnet").tag("sonnet"); Text("Haiku").tag("haiku"); Text("Opus").tag("opus")
            }
            Toggle("Day brief written by Claude", isOn: Binding(get: { DayBriefWriter.shared.on }, set: { DayBriefWriter.shared.on = $0 }))
            if DayBriefWriter.shared.on {
                Picker("Day brief model", selection: $briefModel) {
                    Text("Haiku").tag("haiku"); Text("Sonnet").tag("sonnet")
                }
            }
            Stepper("Plan up to \(dayHours.formatted()) h a day", value: $dayHours, in: 1...14, step: 0.5)
        } header: {
            Text("Claude chat")
        } footer: {
            Text("The conversation (the Claude row, the ✦ button) starts on this model; its header changes it for the next message. Claude reads your data folder and shows each change as a card to accept or reject. The day brief is written once a day from your plans (no files read), with a cheap model; off, the plain summary shows. /plan keeps a day to about this many hours.")
        }
        .sheet(isPresented: $addingKey) {
            ClaudeKeyForm(switchAfter: wantsAPI) { addingKey = false; wantsAPI = false }
                .padding(24)
                .presentationDetents([.height(280)])
        }
    }
}
