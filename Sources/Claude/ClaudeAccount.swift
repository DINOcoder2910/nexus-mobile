import Foundation
import Observation
import NexusCore

/// Plan or API on the iPad: one app-wide switch (Settings › Claude, and the Plan / API chip beside every Claude feature), the API key and
/// what this iPad spent with it this month. The mode lives in UserDefaults ("claudeMode"; API by default on the iPad, the approved board
/// proposal: fastest, works anywhere), the key in the Keychain (only its last 4 characters are ever shown again), the spending in
/// Application Support (claude-api-spend.json), never in the data folder. The laptop has its own switch (docs/areas.md "Plan or API").
@MainActor
@Observable
final class ClaudeAccount {
    static let shared = ClaudeAccount()

    private enum Keys {
        static let mode = "claudeMode"
        static let key = "anthropic-api-key"
    }

    private(set) var mode: ClaudeMode
    private(set) var hasKey = false
    private(set) var last4 = ""
    private(set) var spend = ClaudeSpend()
    /// A note shown under the chip that was tapped (or in Settings › Claude), cleared after a few seconds.
    private(set) var notice: String?

    private init() {
        mode = ClaudeMode(rawValue: UserDefaults.standard.string(forKey: Keys.mode) ?? "") ?? .api
        refreshKey()
        spend = Self.loadSpend()
    }

    // MARK: the switch

    /// Flip (or set) the mode for all of Nexus on this iPad. API without a key returns false: the caller asks for the key (ClaudeKeyForm).
    @discardableResult
    func setMode(_ m: ClaudeMode) -> Bool {
        if m == .api && !hasKey { return false }
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: Keys.mode)
        say(m == .api ? "Claude now uses your API key everywhere. \(ClaudeSpend.text(spend.month()))." : "Claude now uses your Claude plan everywhere.")
        return true
    }
    func flip() { setMode(mode == .api ? .plan : .api) }

    // MARK: the key

    /// The key, for ClaudeClient only.
    nonisolated static func readKey() -> String? {
        let k = Keychain.get(Keys.key, service: Keychain.claude)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty ?? true) ? nil : k
    }

    /// Saves a key after checking its shape (it starts with sk-ant-).
    func setKey(_ raw: String) throws {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard k.range(of: #"^sk-ant-[A-Za-z0-9_-]{20,}$"#, options: .regularExpression) != nil else {
            throw ClaudeError("That does not look like an Anthropic API key (it starts with sk-ant-).")
        }
        guard Keychain.set(k, for: Keys.key, service: Keychain.claude) else { throw ClaudeError("The iPad's Keychain did not keep the key. Try again.") }
        refreshKey()
    }

    /// Removes the key; on API that switches back to the plan.
    func clearKey() {
        Keychain.set("", for: Keys.key, service: Keychain.claude)
        refreshKey()
        if mode == .api { mode = .plan; UserDefaults.standard.set(ClaudeMode.plan.rawValue, forKey: Keys.mode); say("API key removed. Claude uses your plan again.") }
    }

    private func refreshKey() {
        let k = Self.readKey()
        hasKey = k != nil
        last4 = k.map { String($0.suffix(4)) } ?? ""
    }

    // MARK: spending

    func addSpend(_ usd: Double, usage: ClaudeUsage?) {
        spend.add(usd: usd, usage: usage)
        Self.saveSpend(spend)
    }
    var spendText: String { ClaudeSpend.text(spend.month()) }

    private static var spendURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("claude-api-spend.json")
    }
    private static func loadSpend() -> ClaudeSpend {
        guard let d = try? Data(contentsOf: spendURL), let s = try? JSONDecoder().decode(ClaudeSpend.self, from: d) else { return ClaudeSpend() }
        return s
    }
    private static func saveSpend(_ s: ClaudeSpend) {
        do {
            try FileManager.default.createDirectory(at: spendURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(s).write(to: spendURL, options: .atomic)
        } catch {}
    }

    // MARK: notes

    private var noticeTask: Task<Void, Never>?
    private func say(_ s: String) {
        notice = s
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}
