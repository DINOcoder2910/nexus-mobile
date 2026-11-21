import SwiftUI
import NexusCore

/// Settings › Usage on the iPad and iPhone (the laptop's Settings › Claude › Usage, nexus docs/data-format.md "Usage"). API credits: what
/// Nexus spent through the API key this month on this device plus the others (their files in the data folder's usage/), as a bar against
/// the monthly credit the user types (Anthropic doesn't tell an API key its balance). The Claude plan: only Claude Code can read it, and
/// it runs on the laptop, which keeps its last reading in usage/plan.json; that is shown here with when it was read, or where to see it.
struct UsageSettings: View {
    @Environment(NexusStore.self) private var store
    private var account: ClaudeAccount { .shared }
    @AppStorage("apiMonthlyCredit") private var credit: Double = 0
    @State private var others: [UsageShare.Other] = []
    @State private var plan: UsageShare.Plan?

    var body: some View {
        let m = account.spend.month()
        let bar = UsageShare.apiBar(own: m, credit: credit, others: others, device: Device.name)
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Anthropic API credits").font(.nx(.subheadline, .semibold))
                if let f = bar.fraction {
                    ProgressView(value: f)
                        .tint(f >= 0.9 ? Theme.late : f >= 0.75 ? Theme.soon : Theme.accent)
                        .accessibilityIdentifier("usage.api.bar")
                }
                Text(bar.main).font(.nx(.callout)).monospacedDigit().accessibilityIdentifier("usage.api.main")
                Text(bar.sub).font(.nx(.caption)).foregroundStyle(.secondary)
                if !bar.parts.isEmpty { Text(bar.parts).font(.nx(.caption)).foregroundStyle(.secondary).accessibilityIdentifier("usage.api.parts") }
            }
            .padding(.vertical, 4)
            LabeledContent("Monthly API credit") {
                TextField("0", value: $credit, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                Text("$ a month").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude plan" + ((plan?.plan.isEmpty ?? true) ? "" : " (\(plan!.plan))")).font(.nx(.subheadline, .semibold))
                if let plan {
                    ForEach(plan.rows) { r in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(r.label).font(.nx(.callout))
                                Spacer()
                                Text("\(Int(r.pct.rounded()))%").font(.nx(.callout)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: r.pct / 100).tint(r.pct >= 90 ? Theme.late : r.pct >= 75 ? Theme.soon : Theme.accent)
                            if !r.reset.isEmpty { Text(r.reset).font(.nx(.caption)).foregroundStyle(.secondary) }
                        }
                    }
                    .accessibilityIdentifier("usage.plan.rows")
                    if let at = plan.at {
                        Text("Read on the laptop " + at.formatted(.relative(presentation: .named)) + ", the same numbers as Claude Code's /usage.")
                            .font(.nx(.caption)).foregroundStyle(.secondary).accessibilityIdentifier("usage.plan.at")
                    }
                } else {
                    Text("Not read yet: your plan's usage comes from Claude Code on the laptop. Nexus there reads it about once an hour, and it shows here after the next sync.")
                        .font(.nx(.callout)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("usage.plan.none")
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Usage")
        } footer: {
            Text("API credits count Nexus's replies through your key on the laptop, iPad and iPhone together, at Anthropic's prices. Other programs using the same key aren't counted.")
        }
        .task { read() }
        .onChange(of: account.spend) { _, _ in read() }
    }

    /// usage/: the other devices' spending and the laptop's plan reading.
    private func read() {
        let dir = store.folder.appendingPathComponent(UsageShare.dir)
        if IdeasModel.testSeed { Self.seed(dir) }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var files: [(name: String, text: String)] = []
        for n in names where n.lowercased().hasSuffix(".json") {
            if let t = try? FolderAccess.read(dir.appendingPathComponent(n)) { files.append((n, t)) }
        }
        others = UsageShare.others(files, month: ClaudeSpend.monthKey(Date()), device: Device.name)
        plan = files.first(where: { $0.name.lowercased() == "plan.json" }).flatMap { UsageShare.plan($0.text) }
    }

    /// The UI check's usage (-NexusTestIdeas): the laptop's spending and its plan reading, as the laptop writes them.
    static func seed(_ dir: URL) {
        let plan = dir.appendingPathComponent("plan.json")
        guard !FileManager.default.fileExists(atPath: plan.path) else { return }
        let iso = { (h: Double) in Ideas.stamp(Date().addingTimeInterval(h * 3600)) }
        let month = ClaudeSpend.monthKey(Date())
        try? FolderAccess.write(dir.appendingPathComponent("laptop.json"), "{\"device\": \"laptop\", \"months\": {\"\(month)\": {\"usd\": 1.25, \"calls\": 9}}}\n")
        try? FolderAccess.write(plan, "{\"at\": \"\(iso(-0.3))\", \"subscription\": \"max\", \"from\": \"laptop\", \"limits\": {\"five_hour\": {\"utilization\": 25, \"resets_at\": \"\(iso(2.5))\"}, \"seven_day\": {\"utilization\": 82, \"resets_at\": \"\(iso(60))\"}, \"model_scoped\": [{\"display_name\": \"Fable\", \"utilization\": 18, \"resets_at\": \"\(iso(60))\"}]}}\n")
    }
}

/// Writes this device's spending into the data folder's usage/<device>.json after a call that cost something, so the laptop and the other
/// device can add it to their bars. Only when the numbers changed (no sync, no backup commit for the time alone).
@MainActor
enum UsageFile {
    static func writeSpend(_ spend: ClaudeSpend) {
        let store = AppServices.store
        guard store.snapshot.isDataFolder, store.snapshot.readOnlyReason == nil else { return }
        let url = store.folder.appendingPathComponent(UsageShare.dir).appendingPathComponent(UsageShare.fileName(device: Device.name))
        let text = UsageShare.spendText(device: Device.name, spend: spend, at: Ideas.stamp())
        if let old = try? FolderAccess.read(url), UsageShare.sameNumbers(old, text) { return }
        do { try FolderAccess.write(url, text); store.didWrite() } catch {}
    }
}
