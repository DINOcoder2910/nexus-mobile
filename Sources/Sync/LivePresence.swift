import Foundation
import NexusCore

/// Where the other devices are working, live (nexus docs/sync.md "Presence"): the laptop typing in a block shows "Typing on the laptop"
/// on it here, and this iPad tells the hub where it types and draws. A long poll of its own beside sync's, started and stopped by
/// SyncService with the same hub; memory only, nothing is written. Boards listen for `LivePresence.changed`.
@MainActor
final class LivePresence {
    static let shared = LivePresence()
    static let changed = Notification.Name("nexus.presence.changed")
    /// Files sync just wrote here (object: [String] of data-folder paths): an open board reads them at once.
    static let pulled = Notification.Name("nexus.sync.pulled")

    private(set) var others: [HubPresence] = []
    private var transport: HTTPSyncTransport?
    private var loop: Task<Void, Never>?
    private var psig = ""
    private var lastKey = ""
    private var lastAt = Date.distantPast
    /// The other device last seen on the hub (for a draft's name: "From Zephyrus Duo 16 08:15").
    private(set) var lastOther: String?

    /// The build of this app (from Info.plist `NexusBuild`, set by the cloud build to the commit), for the hub and Settings.
    static var build: String {
        let b = (Bundle.main.infoDictionary?["NexusBuild"] as? String) ?? ""
        return b.isEmpty || b.hasPrefix("$(") ? "dev" : b
    }

    func start(_ t: HTTPSyncTransport) {
        stop()
        transport = t
        loop = Task { await self.run() }
    }

    func stop() {
        loop?.cancel(); loop = nil
        transport = nil
        psig = ""
        if !others.isEmpty { others = []; NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    /// Where this iPad is working now (board path, block id or nil, "typing" or "drawing"); nil board: nowhere. Sent at most every
    /// 2 seconds while it stays the same, so calling it on every keystroke or stroke is fine.
    func tell(board: String?, block: String? = nil, what: String?) {
        guard let t = transport else { return }
        let key = [board ?? "", block ?? "", what ?? ""].joined(separator: "|")
        if key == lastKey && Date().timeIntervalSince(lastAt) < 2 { return }
        lastKey = key; lastAt = Date()
        Task {
            if let r = try? await t.tellPresence(board: board, block: block, what: board == nil ? nil : what) { self.take(r) }
        }
    }

    /// Who is typing in which block, and who is drawing, on this board.
    func on(board: String) -> (typing: [String: String], drawing: [String]) { LiveBoard.on(others, board: board) }

    private func run() async {
        var fails = 0
        while !Task.isCancelled, let t = transport {
            do {
                let r = try await t.waitPresence(psig: psig, seconds: 25)
                take(r); fails = 0
            } catch is CancellationError {
                return
            } catch {
                // offline, or a hub from before presence: try again later, quietly
                fails += 1
                try? await Task.sleep(for: .seconds(min(60, 5 * fails)))
            }
        }
    }

    private func take(_ r: HubPresenceReply) {
        guard r.psig != psig else { return }
        psig = r.psig
        others = r.presence
        if let d = r.presence.first?.device { lastOther = d }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
