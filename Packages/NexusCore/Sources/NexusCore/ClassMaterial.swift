import Foundation

/// Class material from Schoology (nexus desktop/backend/src/schoology_hub.rs): the iPad's button asks the hub (POST
/// /v1/schoology/look), the hub asks Nexus on the G14, which reads Schoology, makes the boards and hands them to the hub, so they
/// come here by sync. GET /v1/schoology/status answers what the last look did. This is the words for it and where the button shows.
public enum ClassMaterial {
    /// What the G14 last said, from its status JSON.
    public struct Status: Equatable {
        public var running = false
        public var last: String?
        public var made: [String] = []
        public var failed: [String] = []
        public var error: String?
        public var signedOut = false
        /// The notebook folders it fills ("notebooks/Chemistry HL/Chem HL Notes - G12").
        public var roots: [String] = []
        public init() {}
    }

    public static func status(_ text: String) -> Status? {
        guard let v = try? JSONValue.parse(text), v.object != nil else { return nil }
        var s = Status()
        s.running = v["running"]?.bool ?? false
        s.last = v["last"]?.string
        s.made = (v["made"]?.array ?? []).compactMap(\.string)
        s.failed = (v["failed"]?.array ?? []).compactMap(\.string)
        s.error = v["error"]?.string
        s.signedOut = v["signedOut"]?.bool ?? false
        s.roots = (v["roots"]?.array ?? []).compactMap(\.string)
        return s
    }

    /// The button shows on a notebook the look fills, and on the notebooks that hold one ("Chemistry HL" holds its notes).
    public static func shows(on path: String, roots: [String]) -> Bool {
        roots.contains { path == $0 || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }
    }

    /// "notebooks/Chem/R3.2/R3.2.8.board" -> "R3.2.8"
    public static func boardName(_ path: String) -> String {
        let last = path.split(separator: "/").last.map(String.init) ?? path
        return last.hasSuffix(".board") ? String(last.dropLast(6)) : last
    }

    /// One line for after a look (or while it runs).
    public static func words(_ s: Status) -> String {
        if s.running { return "Getting class material from Schoology…" }
        if s.signedOut { return "Schoology signed you out. Sign in again on the G14: Nexus › Settings › Schoology › Sign in." }
        if let e = s.error, !e.isEmpty { return "Couldn't get class material: \(e)" }
        let names = s.made.map(boardName)
        var line: String
        switch names.count {
        case 0: line = "Nothing new on Schoology."
        case 1: line = "New board: \(names[0])."
        case 2, 3: line = "New boards: \(names.joined(separator: ", "))."
        default: line = "New boards: \(names.prefix(2).joined(separator: ", ")) and \(names.count - 2) more."
        }
        if !s.failed.isEmpty { line += s.failed.count == 1 ? " One file didn't come." : " \(s.failed.count) files didn't come." }
        return line
    }
}
