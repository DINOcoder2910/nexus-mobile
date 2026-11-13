import SwiftUI
import NexusCore

/// Settings › Usage on the iPad: what this iPad spent through the API key this month as a bar against the monthly credit the user types
/// (Anthropic doesn't tell an API key its balance), and the Claude plan's usage, which only Claude Code can read: it runs on the laptop,
/// so here the section says where to see it instead of showing a number it doesn't have (the laptop's Settings › Claude › Usage).
struct ClaudeUsage: View {
    private var account: ClaudeAccount { .shared }
    @AppStorage("apiMonthlyCredit") private var credit: Double = 0

    var body: some View {
        let m = account.spend.month()
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Anthropic API credits").font(.subheadline.weight(.semibold))
                if credit > 0 {
                    ProgressView(value: min(m.usd, credit), total: credit)
                        .tint(m.usd / credit >= 0.9 ? Theme.late : m.usd / credit >= 0.75 ? Theme.soon : Theme.accent)
                        .accessibilityIdentifier("usage.api.bar")
                    Text(String(format: "$%.2f of $%.2f this month", m.usd, credit) + (m.calls > 0 ? " (\(m.calls) \(m.calls == 1 ? "reply" : "replies"))" : ""))
                        .font(.callout).monospacedDigit()
                    Text(String(format: "%d%% used, $%.2f left", Int((m.usd / credit * 100).rounded()), max(0, credit - m.usd))).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(ClaudeSpend.text(m)).font(.callout)
                    Text("Type your monthly API credit below to see how much of it is used.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            LabeledContent("Monthly API credit") {
                TextField("0", value: $credit, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                Text("$ a month").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Claude plan").font(.subheadline.weight(.semibold))
                Text("Not available on the iPad: your plan's usage is read from Claude Code, which runs on the laptop. See it there in Settings › Claude › Usage.")
                    .font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("usage.plan.none")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Usage")
        } footer: {
            Text("API credits count only this iPad's replies through your key, at Anthropic's prices; the laptop counts its own.")
        }
    }
}
