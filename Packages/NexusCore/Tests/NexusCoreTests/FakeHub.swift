import Foundation
@testable import NexusCore

/// An in-process hub that follows docs/sync.md: a change log with a sequence number, PUT ok / same / merged / conflict,
/// DELETE ok / kept, the case check. "Merged" is simulated by `mergeHook` (the real hub's line merge lives on the laptop side).
final class FakeHub: SyncTransport, @unchecked Sendable {
    struct Entry {
        var hash: String?
        var size: Int64?
        var deleted: Bool
        var seq: Int
        var device: String
    }

    var folderId = "hub-1"
    var seq = 0
    var files: [String: Data] = [:]
    var log: [String: Entry] = [:]
    var blobs: [String: Data] = [:]
    /// The device name the iPad's requests carry.
    var device = "iPad"
    var stamp = "2026-11-12 0815"
    var offline = false
    /// (base, hub, mine) -> the merged bytes, or nil for a conflict.
    var mergeHook: ((Data, Data, Data) -> Data?)?
    /// Runs after a download reached the client's temp file (to change the local file meanwhile).
    var onDownload: ((String) -> Void)?
    /// Extra change entries (paths a real hub would never send).
    var injected: [HubChange] = []
    var puts: [String] = []
    var deletes: [String] = []
    var downloads: [String] = []

    func resetCounts() {
        puts = []
        deletes = []
        downloads = []
    }

    // MARK: another device's changes

    @discardableResult
    func write(_ path: String, _ text: String, device: String = "Laptop") -> String {
        store(path, Data(text.utf8), device: device)
    }

    func remove(_ path: String, device: String = "Laptop") {
        files[path] = nil
        seq += 1
        log[path] = Entry(hash: nil, size: nil, deleted: true, seq: seq, device: device)
    }

    func text(_ path: String) -> String? { files[path].map { String(decoding: $0, as: UTF8.self) } }

    @discardableResult
    private func store(_ path: String, _ d: Data, device: String) -> String {
        let h = SyncHash.data(d)
        files[path] = d
        blobs[h] = d
        seq += 1
        log[path] = Entry(hash: h, size: Int64(d.count), deleted: false, seq: seq, device: device)
        return h
    }

    private func online() throws {
        if offline { throw SyncError.offline("The fake hub is offline.") }
    }

    // MARK: SyncTransport

    func hello() async throws -> HubHello {
        try online()
        return HubHello(hub: "nexus-hub", protocolVersion: 1, folderId: folderId, seq: seq)
    }

    func changes(since: Int, wait: Int?) async throws -> HubChanges {
        try online()
        let list = log.filter { $0.value.seq > since }
            .sorted { $0.value.seq < $1.value.seq }
            .map { HubChange(path: $0.key, hash: $0.value.hash, size: $0.value.size, deleted: $0.value.deleted, seq: $0.value.seq, device: $0.value.device) }
        return HubChanges(folderId: folderId, seq: seq, changes: list + injected)
    }

    func download(path: String, to destination: URL) async throws -> String? {
        try online()
        guard let d = files[path] else { throw SyncError.notFound }
        downloads.append(path)
        try d.write(to: destination)
        onDownload?(path)
        return SyncHash.data(d)
    }

    func put(path: String, base: String?, body: SyncBody, hash: String) async throws -> PutResult {
        try online()
        let d: Data
        switch body {
        case .data(let x): d = x
        case .file(let u): d = try Data(contentsOf: u)
        }
        guard SyncHash.data(d) == hash else { throw SyncError.badRequest("the body does not match X-Nexus-Hash") }
        guard SyncPaths.isSafe(path), !SyncPaths.isIgnored(path) else { throw SyncError.badRequest("bad path") }
        puts.append(path)
        guard let live = files[path] else {
            if files.keys.contains(where: { $0.lowercased() == path.lowercased() }) { throw SyncError.sameNameDifferentCase }
            let h = store(path, d, device: device)
            return PutResult(result: "ok", hash: h, seq: seq)
        }
        let liveHash = SyncHash.data(live)
        if liveHash == hash { return PutResult(result: "same", hash: hash, seq: log[path]?.seq) }
        if base == liveHash {
            let h = store(path, d, device: device)
            return PutResult(result: "ok", hash: h, seq: seq)
        }
        if let base, let b = blobs[base], let merged = mergeHook?(b, live, d) {
            let h = store(path, merged, device: device)
            return PutResult(result: "merged", hash: h, seq: seq)
        }
        let cp = conflictName(path)
        store(cp, d, device: device)
        return PutResult(result: "conflict", hash: liveHash, seq: seq, conflictPath: cp)
    }

    func delete(path: String, base: String) async throws -> DeleteResult {
        try online()
        deletes.append(path)
        guard let live = files[path] else { return DeleteResult(result: "ok", seq: seq) }
        let liveHash = SyncHash.data(live)
        if liveHash != base { return DeleteResult(result: "kept", hash: liveHash, seq: log[path]?.seq) }
        remove(path, device: device)
        return DeleteResult(result: "ok", seq: seq)
    }

    func conflictName(_ path: String) -> String {
        let slash = path.lastIndex(of: "/")
        let dir = slash.map { String(path[...$0]) } ?? ""
        let name = slash.map { String(path[path.index(after: $0)...]) } ?? path
        let dot = name.lastIndex(of: ".").flatMap { $0 == name.startIndex ? nil : $0 }
        let stem = dot.map { String(name[..<$0]) } ?? name
        let ext = dot.map { String(name[$0...]) } ?? ""
        var n = 1
        while true {
            let candidate = dir + stem + " (conflict \(device) \(stamp)" + (n > 1 ? " \(n)" : "") + ")" + ext
            if files[candidate] == nil { return candidate }
            n += 1
        }
    }
}
