import Foundation
import CryptoKit

/// A file's size and modified time when it was last hashed, and the hash: a file whose size and time are unchanged is not read
/// again. Stored as `[size, mtimeMs, hash]`, the shape docs/sync.md gives.
public struct CachedHash: Codable, Equatable, Sendable {
    public var size: Int64
    public var mtimeMs: Double
    public var hash: String

    public init(size: Int64, mtimeMs: Double, hash: String) {
        self.size = size
        self.mtimeMs = mtimeMs
        self.hash = hash
    }

    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        size = try c.decode(Int64.self)
        mtimeMs = try c.decode(Double.self)
        hash = try c.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(size)
        try c.encode(mtimeMs)
        try c.encode(hash)
    }
}

/// What a device remembers about one data folder, kept outside the folder (on the iPad in Application Support), so a copied
/// folder never inherits another folder's bases.
public struct SyncState: Codable, Equatable, Sendable {
    public var hubUrl: String
    /// The hub folder these bases belong to; a different one on the hub means start again (first sync).
    public var folderId: String?
    /// The last change sequence number seen.
    public var cursor: Int
    /// Per path, the hash this device last agreed with the hub.
    public var bases: [String: String]
    public var hashCache: [String: CachedHash]
    /// The first download into an empty folder (or after "Use the hub's copy") has not finished: pull only, push nothing.
    public var restoring: Bool?

    public init(hubUrl: String = "") {
        self.hubUrl = hubUrl
        folderId = nil
        cursor = 0
        bases = [:]
        hashCache = [:]
        restoring = nil
    }

    /// The saved state, or nil when there is none (or it can't be read: then sync starts as a first sync, which loses nothing).
    public static func load(_ url: URL) -> SyncState? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SyncState.self, from: d)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }

    /// The state file's name for a data folder, from a key naming the folder (its path).
    public static func fileName(forKey key: String) -> String {
        String(SyncHash.data(Data(key.utf8)).prefix(24)) + ".json"
    }
}

/// SHA-256 as lowercase hex, the hub's file hash.
public enum SyncHash {
    public static func data(_ d: Data) -> String { hex(SHA256.hash(data: d)) }

    /// Hashes a file a megabyte at a time, so a 50 MB PDF is never read into memory whole.
    public static func file(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var sha = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty {
            sha.update(data: chunk)
        }
        return hex(sha.finalize())
    }

    static let digits = Array("0123456789abcdef".utf8)

    static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        var out: [UInt8] = []
        out.reserveCapacity(64)
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
