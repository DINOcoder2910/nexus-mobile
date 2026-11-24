import Foundation

/// Drop (the laptop's docs/sync.md "Drop"): any file put in `Drop/` at the data folder's top reaches every device through the hub,
/// like AirDrop between your own devices. The folder is ordinary synced files; this device keeps its own record of what came from
/// where in `.nexus/drop.json` (never synced: `.nexus/` is ignored), so the Drop screen and the arrival note can say "from Duo".
/// The same shape as the laptop's renderer/src/sync/drop.js and the new app's backend drop.rs.
public enum DropFolder {
    public static let folder = "Drop"
    public static let logPath = ".nexus/drop.json"
    public static let keep = 500

    /// A file inside Drop/ (any depth), as the protocol spells paths.
    public static func isDropPath(_ p: String) -> Bool { p.hasPrefix(folder + "/") && p.count > folder.count + 1 }

    /// Now as the record writes it ("2026-11-22T19:04:02.123Z").
    public static func stamp(_ d: Date = Date()) -> String { isoMs.string(from: d) }

    public static func date(_ s: String) -> Date? { isoMs.date(from: s) ?? isoSec.date(from: s) }

    // made once (the sidebar's count reads the record's times)
    private static let isoMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoSec: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The words of the note for what arrived in one go from other devices, or nil.
    public static func arrivalNotice(_ arrived: [DropItem]) -> (title: String, body: String)? {
        let list = arrived.filter { !$0.here }
        guard !list.isEmpty else { return nil }
        var froms: [String] = []
        for a in list { let f = a.from.isEmpty ? "another device" : a.from; if !froms.contains(f) { froms.append(f) } }
        let from = froms.count == 1 ? froms[0] : froms.dropLast().joined(separator: ", ") + " and " + froms[froms.count - 1]
        let names = list.map { ($0.path as NSString).lastPathComponent }
        if list.count == 1 { return ("From \(from)", "\(names[0]) is in Drop") }
        return ("From \(from)", "\(list.count) files are in Drop: \(names.prefix(3).joined(separator: ", "))\(list.count > 3 ? "…" : "")")
    }
}

/// One line of the record: a file that came from another device, or was sent from here.
public struct DropItem: Codable, Equatable, Sendable {
    public var path: String
    public var hash: String?
    /// The device it came from ("" when the sender didn't say).
    public var from: String
    /// When it came or went (ISO, UTC).
    public var at: String
    /// Sent from this device.
    public var here: Bool

    public init(path: String, hash: String? = nil, from: String, at: String, here: Bool) {
        self.path = path; self.hash = hash; self.from = from; self.at = at; self.here = here
    }

    enum CodingKeys: String, CodingKey { case path, hash, from, at, here }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        hash = try? c.decodeIfPresent(String.self, forKey: .hash)
        from = (try? c.decodeIfPresent(String.self, forKey: .from)) ?? ""
        at = try c.decode(String.self, forKey: .at)
        here = (try? c.decodeIfPresent(Bool.self, forKey: .here)) ?? false
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(path, forKey: .path)
        try c.encode(hash, forKey: .hash)
        try c.encode(from, forKey: .from)
        try c.encode(at, forKey: .at)
        try c.encode(here, forKey: .here)
    }
}

/// This device's record (`.nexus/drop.json`): newest first, one line per path, at most `DropFolder.keep`.
public struct DropLog: Codable, Equatable, Sendable {
    public var version = 1
    public var items: [DropItem] = []

    public init(items: [DropItem] = []) { self.items = items }

    /// The record in a data folder (an unreadable one is empty).
    public static func read(_ folder: URL) -> DropLog {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent(DropFolder.logPath)) else { return DropLog() }
        struct Loose: Decodable { var items: [DropItem]? }
        guard let l = try? JSONDecoder().decode(Loose.self, from: d) else { return DropLog() }
        return DropLog(items: (l.items ?? []).filter { DropFolder.isDropPath($0.path) })
    }

    /// What just came or went, put at the top (in the order given, the last newest).
    public func noting(_ adds: [DropItem]) -> DropLog {
        let fresh = adds.filter { DropFolder.isDropPath($0.path) }
        guard !fresh.isEmpty else { return self }
        let paths = Set(fresh.map(\.path))
        return DropLog(items: Array((fresh.reversed() + items.filter { !paths.contains($0.path) }).prefix(DropFolder.keep)))
    }

    /// Adds to the record on disk (written whole, through a temp file).
    public static func note(_ adds: [DropItem], in folder: URL) throws {
        guard adds.contains(where: { DropFolder.isDropPath($0.path) }) else { return }
        let next = read(folder).noting(adds)
        let url = folder.appendingPathComponent(DropFolder.logPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(next).write(to: url, options: .atomic)
    }

    /// The latest line for a path, or for anything inside it (a folder or a board came as its files).
    public func record(for path: String) -> DropItem? {
        if let i = items.first(where: { $0.path == path }) { return i }
        return items.filter { $0.path.hasPrefix(path + "/") }.max { $0.at < $1.at }
    }
}
