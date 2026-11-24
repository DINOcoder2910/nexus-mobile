import Foundation

/// The sync chip at the foot of the sidebar (the iPad) and atop More (the iPhone): where this device stands with the hub in a few
/// words, as on the laptop (the Nexus repo's renderer/src/hubstate.js `syncChipOf`, docs/sync.md "The sync chip"): in sync, syncing,
/// offline with what waits here, conflicts, or held.
public struct SyncChip: Equatable, Sendable {
    public enum Tone: String, Sendable { case hidden, ok, busy, warn, bad }

    /// Where sync is, in the chip's terms.
    public enum State: Equatable, Sendable {
        case off
        case notSetUp
        case connecting
        case inSync
        case syncing(Int)
        case offline
        case problem(String)
        /// Many deletions here, held until the user says.
        case deletionsHeld(Int)
        /// Not syncing until the user does something (the first sync's choice, no nexus.yaml, an empty hub).
        case waiting(String)
    }

    public var tone: Tone
    public var text: String
    /// The longer sentence (the accessibility hint).
    public var detail: String

    public init(tone: Tone, text: String, detail: String) {
        self.tone = tone
        self.text = text
        self.detail = detail
    }

    /// `waiting`: the changes here the hub hasn't got (counted while offline); `conflicts`: conflict copies in the folder.
    public static func of(_ state: State, waiting: Int = 0, conflicts: Int = 0, lastSynced: Date? = nil, now: Date = Date()) -> SyncChip {
        func files(_ n: Int) -> String { n == 1 ? "1 file" : "\(n) files" }
        switch state {
        case .off, .notSetUp:
            return SyncChip(tone: .hidden, text: "", detail: "")
        case .offline:
            return SyncChip(tone: .warn, text: waiting > 0 ? "Offline · \(waiting) waiting" : "Offline",
                            detail: "The hub cannot be reached. " + (waiting > 0 ? "\(files(waiting)) changed here go up when it is back." : "Changes made here go up when it is back."))
        case .problem(let why):
            return SyncChip(tone: .bad, text: "Sync problem", detail: why.isEmpty ? "Something went wrong." : why)
        case .waiting(let why):
            return SyncChip(tone: .warn, text: "Not syncing", detail: why)
        case .deletionsHeld(let n):
            return SyncChip(tone: .warn, text: "Deletions held",
                            detail: "\(n > 0 ? String(n) : "Many") files were deleted here at once, so they were not sent. Everything else still syncs.")
        case .connecting, .inSync, .syncing:
            break
        }
        if conflicts > 0 {
            return SyncChip(tone: .warn, text: conflicts == 1 ? "1 conflict" : "\(conflicts) conflicts",
                            detail: "A file was changed in two places at once and could not be merged, so both versions were kept: the other one is beside it, named “(conflict …)”.")
        }
        switch state {
        case .syncing(let n):
            return SyncChip(tone: .busy, text: n > 0 ? "Syncing \(n)" : "Syncing…", detail: n > 0 ? "Sending \(files(n)) to the hub." : "Talking to the hub.")
        case .connecting:
            return SyncChip(tone: .busy, text: "Syncing…", detail: "Talking to the hub.")
        default:
            return SyncChip(tone: .ok, text: "In sync",
                            detail: lastSynced.map { "Up to date with the hub; last synced \(ago($0, now))." } ?? "Up to date with the hub.")
        }
    }

    /// "just now", "5 min ago", "3 h ago", "2 days ago" (hubstate.js `ago`).
    public static func ago(_ t: Date, _ now: Date) -> String {
        let s = max(0, now.timeIntervalSince(t).rounded())
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int((s / 60).rounded())) min ago" }
        if s < 86400 { return "\(Int((s / 3600).rounded())) h ago" }
        return "\(Int((s / 86400).rounded())) days ago"
    }
}
