import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A file left alone, and why (in plain words for Settings).
public struct SyncProblem: Equatable, Hashable, Sendable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// How this iPad's folder compares with the hub's before the first sync, for the "how to start" question.
public struct FirstSyncSummary: Equatable, Sendable {
    public var hubFiles = 0
    public var localFiles = 0
    public var same = 0
    public var differ = 0
    public var onlyHere = 0
    public var onlyOnHub = 0
    /// The local folder has a nexus.yaml (merging is only offered then).
    public var localIsDataFolder = false

    public init() {}
}

/// What one cycle did.
public struct SyncReport: Equatable, Sendable {
    /// Paths sent to the hub (changed, new or deleted here).
    public var pushed: [String] = []
    /// Paths written or deleted here from the hub.
    public var pulled: [String] = []
    /// Conflict copies in the folder, from the scan.
    public var conflictCopies: [String] = []
    public var problems: [SyncProblem] = []
    /// Files in Drop/ sent from here or come from another device in this cycle (DropLog.swift), already noted in the record.
    public var dropped: [DropItem] = []

    public init() {}
}

public enum SyncOutcome: Equatable, Sendable {
    case synced(SyncReport)
    /// The folder is missing, or has no nexus.yaml: nothing was done (a missing folder must never look like "all deleted").
    case notADataFolder
    /// First sync and the hub has no files: the laptop seeds the hub, not the iPad.
    case hubEmpty
    /// First sync, both sides have files that differ: ask the user (use the hub's copy, or merge).
    case needsFirstSyncChoice(FirstSyncSummary)
    /// More than 25 files and more than a quarter of the folder are gone here: ask before deleting them on the hub.
    case pausedForDeletions([String])
}

public struct SyncProgress: Equatable, Sendable {
    /// Files still to send or fetch in this cycle.
    public var remaining: Int
}

/// The iPad's sync client (docs/sync.md, "A client's cycle"). It never merges: it pushes its own changes first, the hub merges
/// or keeps both, and it takes the result. One cycle at a time; the app's SyncService runs the cycles and the long poll.
public actor SyncClient {
    public let folder: URL
    public let stateURL: URL
    let transport: SyncTransport
    public private(set) var state: SyncState

    /// The mass-deletion guard: more than this many deletions, and more than a quarter of the bases.
    public static let massDeletionCount = 25
    /// Files at most this big are read into memory to send; bigger ones stream from the file.
    static let inMemoryLimit: Int64 = 8 << 20

    private let fm = FileManager.default
    private var allowDeletions = false
    private var pendingDeletions: [String] = []
    /// Files the hub refused (same name in other capitals, unsafe to it, too big), with the hash refused and why: not sent
    /// again until they change.
    private var refused: [String: (hash: String, problem: SyncProblem)] = [:]
    private var dirty = 0
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// This device's name as the hub knows it (the Drop record says who sent what).
    public let device: String

    public init(folder: URL, stateURL: URL, hubUrl: String, transport: SyncTransport, device: String = "iPad") {
        self.folder = folder
        self.stateURL = stateURL
        self.transport = transport
        self.device = device
        let read = SyncState.load(stateURL)
        var s = read ?? SyncState(hubUrl: hubUrl)
        s.hubUrl = hubUrl
        state = s
        savedState = read
    }

    // MARK: one at a time

    private func acquire() async {
        while busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
    }

    private func release() {
        busy = false
        if !waiters.isEmpty { waiters.removeFirst().resume() }
    }

    private func touch() {
        dirty += 1
        if dirty >= 25 { try? saveState() }
    }

    /// The state as last written: a cycle that changed nothing doesn't write it again. With a big data folder (a OneNote import) the
    /// state holds a hash for every file, megabytes of JSON, and it was written at the end of every cycle (each few seconds while you
    /// write on a board).
    private var savedState: SyncState?

    private func saveState() throws {
        dirty = 0
        if let savedState, savedState == state { return }
        try state.save(to: stateURL)
        savedState = state
    }

    // MARK: the cycle

    /// Guard, scan, push, pull. Throws `SyncError` (transient ones are retried by the caller) or `CancellationError`.
    public func cycle(progress: (@Sendable (SyncProgress) -> Void)? = nil) async throws -> SyncOutcome {
        await acquire()
        defer {
            try? saveState()
            release()
        }
        let hello = try await transport.hello()
        guard hello.hub == "nexus-hub" else { throw SyncError.notAHub }
        guard hello.protocolVersion == 1 else { throw SyncError.newerHub(hello.protocolVersion) }
        guard folderExists() else { return .notADataFolder }

        if state.folderId != hello.folderId {
            // First sync, or the hub's folder was made again: the bases mean nothing now.
            state.folderId = nil
            state.bases = [:]
            state.cursor = 0
            state.restoring = nil
            refused = [:]
            pendingDeletions = []
            needFull = true
            let local = scan()
            if local.files.isEmpty && local.unreadable.isEmpty {
                // Nothing here to lose: download everything.
                state.folderId = hello.folderId
                state.restoring = true
            } else {
                let everything = try await transport.changes(since: 0, wait: nil)
                let summary = compare(local, everything)
                if summary.hubFiles == 0 { return .hubEmpty }
                guard summary.differ == 0 && summary.onlyHere == 0 && summary.localIsDataFolder else {
                    return .needsFirstSyncChoice(summary)
                }
                state.folderId = hello.folderId
            }
        }

        var report = SyncReport()
        let local = scan()
        report.problems = local.problems
        report.conflictCopies = local.conflictCopies

        if state.restoring == true || (!hasNexusYaml() && state.bases.isEmpty && local.files.isEmpty) {
            // Pull only, until the hub's copy (with its nexus.yaml) is here.
            state.restoring = true
            try await pull(&report, progress)
            report.dropped = [] // the whole folder coming down, not something sent just now
            if hasNexusYaml() { state.restoring = nil }
            report.conflictCopies = scan().conflictCopies
            return .synced(report)
        }

        guard hasNexusYaml() else { return .notADataFolder }
        if state.bases.isEmpty && hello.seq == 0 { return .hubEmpty }

        // Deleted here: a base whose file is gone (an unreadable file is not gone).
        for p in state.bases.keys where SyncPaths.isIgnored(p) || !SyncPaths.isSafe(p) { state.bases[p] = nil }
        let deleted = state.bases.keys.filter { local.files[$0] == nil && !local.unreadable.contains($0) }.sorted()
        if deleted.count > Self.massDeletionCount && deleted.count * 4 > state.bases.count && !allowDeletions {
            pendingDeletions = deleted
            return .pausedForDeletions(deleted)
        }
        allowDeletions = false
        pendingDeletions = []

        if state.bases.isEmpty && state.cursor == 0 {
            // First sync: files that already match the hub get their base, so only differences are sent.
            for c in try await transport.changes(since: 0, wait: nil).changes where !c.deleted {
                if let h = c.hash, local.files[c.path]?.hash == h { state.bases[c.path] = h }
            }
        }

        try await push(deleted, local, &report, progress)
        try await pull(&report, progress)
        report.conflictCopies = scan().conflictCopies
        noteDrops(report.dropped)
        return .synced(report)
    }

    /// This device's record of what came and went through Drop/ (never synced); a write that fails costs only the "from" words.
    private func noteDrops(_ d: [DropItem]) {
        guard !d.isEmpty else { return }
        try? DropLog.note(d, in: folder)
    }

    /// The long poll: returns when the hub has something newer than the cursor, or after `seconds`.
    public func waitForHub(seconds: Int = 25) async throws -> Bool {
        let page = try await transport.changes(since: state.cursor, wait: seconds)
        return !page.changes.isEmpty || page.folderId != state.folderId
    }

    // MARK: the user's answers

    /// "Merge with this iPad's files": the normal first sync. Files only here are sent; a file that differs is sent with no
    /// base, so the hub keeps its version and saves this iPad's beside it as a conflict copy.
    public func mergeWithHub() async throws {
        await acquire()
        defer { release() }
        let hello = try await transport.hello()
        state.folderId = hello.folderId
        state.bases = [:]
        state.cursor = 0
        state.restoring = nil
        needFull = true
        try saveState()
    }

    /// "Use the hub's copy": moves the folder aside (`nexus-data before sync 2026-11-11 1530`, beside it) if it has anything in
    /// it, then the next cycles download everything. Returns where the old folder went.
    @discardableResult
    public func useHubCopy(now: Date = Date()) async throws -> URL? {
        await acquire()
        defer { release() }
        let hello = try await transport.hello()
        var moved: URL?
        if folderExists(), !((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty {
            moved = try moveAside(now)
        }
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
            throw SyncError.local("Couldn't make the folder again: \(error.localizedDescription)")
        }
        state = SyncState(hubUrl: state.hubUrl)
        state.folderId = hello.folderId
        state.restoring = true
        refused = [:]
        pendingDeletions = []
        allowDeletions = false
        lastScan = nil
        needFull = true
        try saveState()
        return moved
    }

    /// After a pause for deletions: delete them on the hub too, on the next cycle.
    public func allowPendingDeletions() {
        allowDeletions = true
    }

    /// After a pause for deletions: download the missing files again instead. Returns the paths brought back.
    public func bringBackDeleted() async throws -> [String] {
        await acquire()
        defer {
            try? saveState()
            release()
        }
        var back: [String] = []
        for p in pendingDeletions where state.bases[p] != nil {
            try Task.checkCancellation()
            switch try await fetch(p, expecting: nil) {
            case .wrote(let h): state.bases[p] = h; back.append(p)
            case .goneOnHub: state.bases[p] = nil
            case .changedHere: break
            }
            touch()
        }
        pendingDeletions = []
        allowDeletions = false
        return back
    }

    // MARK: push

    private func push(_ deleted: [String], _ local: Scan, _ report: inout SyncReport,
                      _ progress: (@Sendable (SyncProgress) -> Void)?) async throws {
        let changed = local.files.filter { state.bases[$0.key] != $0.value.hash }
            .sorted { ($0.value.mtimeMs, $0.key) < ($1.value.mtimeMs, $1.key) }
        var remaining = deleted.count + changed.count

        for p in deleted {
            try Task.checkCancellation()
            progress?(SyncProgress(remaining: remaining))
            remaining -= 1
            guard let base = state.bases[p] else { continue }
            let r = try await transport.delete(path: p, base: base)
            report.pushed.append(p)
            if r.result == "kept" {
                // An edit on another device wins over this deletion: take the file back.
                switch try await fetch(p, expecting: nil) {
                case .wrote(let h): state.bases[p] = h; report.pulled.append(p)
                case .goneOnHub: state.bases[p] = nil
                case .changedHere: break
                }
            } else {
                state.bases[p] = nil
            }
            touch()
        }

        for (p, file) in changed {
            try Task.checkCancellation()
            progress?(SyncProgress(remaining: remaining))
            remaining -= 1
            if let r = refused[p], r.hash == file.hash {
                report.problems.append(r.problem)
                continue
            }
            let url = folder.appendingPathComponent(p)
            let body: SyncBody
            let sent: String
            if file.size <= Self.inMemoryLimit {
                guard let d = try? Data(contentsOf: url) else { continue }
                body = .data(d)
                sent = SyncHash.data(d)
            } else {
                body = .file(url)
                sent = file.hash
            }
            let r: PutResult
            do {
                r = try await transport.put(path: p, base: state.bases[p], body: body, hash: sent)
            } catch SyncError.sameNameDifferentCase {
                refuse(p, sent, "Another file on the hub has the same name in different capitals, so this one isn't synced. Rename one of them.", &report)
                continue
            } catch SyncError.tooLarge {
                refuse(p, sent, "Too big for the hub, so it isn't synced.", &report)
                continue
            } catch SyncError.badRequest(let why) {
                // A big file that changed while it was being sent fails the hub's hash check: it goes again next time.
                if (try? localHash(p)) != sent { continue }
                refuse(p, sent, "The hub refused it: \(why)", &report)
                continue
            }
            report.pushed.append(p)
            if r.result == "ok" && state.bases[p] == nil && DropFolder.isDropPath(p) {
                report.dropped.append(DropItem(path: p, hash: r.hash ?? sent, from: device, at: DropFolder.stamp(), here: true))
            }
            switch r.result {
            case "ok", "same":
                state.bases[p] = r.hash ?? sent
            case "merged", "conflict":
                // The hub holds the result (merged, or its own version with ours saved as a conflict copy): take it, if the
                // file here is still what was sent. If it changed meanwhile, the old base stays, so the next push merges again.
                switch try await fetch(p, expecting: sent) {
                case .wrote(let h): state.bases[p] = h; report.pulled.append(p)
                case .changedHere, .goneOnHub: break
                }
            default:
                throw SyncError.badReply
            }
            touch()
        }
    }

    private func refuse(_ p: String, _ hash: String, _ message: String, _ report: inout SyncReport) {
        let problem = SyncProblem(path: p, message: message)
        refused[p] = (hash, problem)
        report.problems.append(problem)
    }

    // MARK: pull

    private func pull(_ report: inout SyncReport, _ progress: (@Sendable (SyncProgress) -> Void)?) async throws {
        let page = try await transport.changes(since: state.cursor, wait: nil)
        guard page.folderId == state.folderId else { return } // the hub was reset just now: the next cycle starts again
        var held = false
        var remaining = page.changes.count
        for c in page.changes {
            try Task.checkCancellation()
            remaining -= 1
            let p = c.path
            guard SyncPaths.isSafe(p) else {
                report.problems.append(SyncProblem(path: p, message: "The hub has a file whose name can't be used here, so it was left on the hub."))
                continue
            }
            if SyncPaths.isIgnored(p) { continue }
            let here: String?
            do { here = try localHash(p) } catch {
                report.problems.append(SyncProblem(path: p, message: "Couldn't read it here: \(describe(error))"))
                held = true
                continue
            }
            let base = state.bases[p]
            if c.deleted || c.hash == nil {
                if here == nil {
                    state.bases[p] = nil
                } else if let base, here == base {
                    do {
                        if try removeLocal(p, expecting: base) { state.bases[p] = nil; report.pulled.append(p) }
                    } catch {
                        report.problems.append(SyncProblem(path: p, message: "Couldn't delete it here: \(describe(error))"))
                        held = true
                    }
                }
                // Else it was changed here: the edit is sent next time and wins over the deletion.
            } else if let h = c.hash {
                if here == h {
                    state.bases[p] = h
                } else if here == base {
                    // Unchanged here since the base (or absent with no base): take the hub's.
                    progress?(SyncProgress(remaining: remaining + 1))
                    do {
                        switch try await fetch(p, expecting: here) {
                        case .wrote(let got):
                            state.bases[p] = got; report.pulled.append(p)
                            if DropFolder.isDropPath(p) && (c.device ?? "") != device {
                                report.dropped.append(DropItem(path: p, hash: got, from: c.device ?? "", at: DropFolder.stamp(), here: false))
                            }
                        case .changedHere, .goneOnHub: break
                        }
                    } catch SyncError.local(let why) {
                        report.problems.append(SyncProblem(path: p, message: why))
                        held = true
                    }
                }
                // Else changed here meanwhile: left alone, sent on the next cycle.
            }
            touch()
        }
        // A file that couldn't be written keeps the cursor where it was, so it is tried again.
        if !held { state.cursor = page.seq }
    }

    // MARK: the folder

    struct LocalFile {
        var hash: String
        var size: Int64
        var mtimeMs: Double
    }

    struct Scan {
        var files: [String: LocalFile] = [:]
        var unreadable: Set<String> = []
        var problems: [SyncProblem] = []
        var conflictCopies: [String] = []
    }

    private func folderExists() -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: folder.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func hasNexusYaml() -> Bool { fm.fileExists(atPath: folder.appendingPathComponent("nexus.yaml").path) }

    private static let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]

    // MARK: quick scans

    /// How often a cycle walks the whole folder even when the app named every change. A OneNote import left 16,000 files in the
    /// folder, and every cycle (one each few seconds while you write, one each 25 s idle) walked and looked at all of them, twice.
    public static let fullScanEvery: TimeInterval = 600
    /// The folder as the last scan saw it, kept true by this client's own writes and the paths the app names (`changed`).
    private var lastScan: Scan?
    private var lastFullScan = Date.distantPast
    private var needFull = true
    private var hints: Set<String> = []
    /// Walks of the whole folder so far (tests).
    public private(set) var fullScans = 0
    private var quick = false

    /// From now on the app names what it changes (`changed`, `changedEverywhere`), so a cycle need not walk the whole folder.
    /// Without this every scan walks it all.
    public func useQuickScans() { quick = true }

    /// The app changed these files or folders (relative to the folder) and nothing else: the next cycle looks at them only.
    public func changed(_ paths: [String]) {
        for p in paths {
            let rel = SyncPaths.nfc(p).split(separator: "/").joined(separator: "/")
            if rel.isEmpty { needFull = true } else { hints.insert(rel) }
        }
    }

    /// Something may have changed anywhere in the folder (another app, a write the app didn't name): the next cycle walks it all.
    public func changedEverywhere() { needFull = true }

    /// The folder as it is: a walk of all of it when asked, the first time, or every `fullScanEvery`; otherwise the last scan with
    /// the changed paths looked at again.
    private func scan() -> Scan {
        if !quick || needFull || lastScan == nil || Date().timeIntervalSince(lastFullScan) >= Self.fullScanEvery { return fullScan() }
        return quickScan() ?? fullScan()
    }

    /// Walks the folder (skipping ignored paths and symbolic links), hashing only files whose size or time changed.
    private func fullScan() -> Scan {
        var out = Scan()
        var cache: [String: CachedHash] = [:]
        walk(folder, "", &out, &cache)
        state.hashCache = cache
        out.conflictCopies.sort()
        fullScans += 1
        lastScan = out
        lastFullScan = Date()
        needFull = false
        hints = []
        return out
    }

    /// The last scan, with each hinted path dropped and read again. Nil when a hint can't be trusted (its name differs from the
    /// folder's in capitals): then the whole folder is walked.
    private func quickScan() -> Scan? {
        guard var out = lastScan else { return nil }
        let all = hints.sorted()
        hints = []
        // a hint inside another one is read with it
        var roots: [String] = []
        for h in all where !roots.contains(where: { h == $0 || h.hasPrefix($0 + "/") }) { roots.append(h) }
        var cache = state.hashCache
        for rel in roots {
            let under: (String) -> Bool = { $0 == rel || $0.hasPrefix(rel + "/") }
            for k in out.files.keys where under(k) { out.files[k] = nil }
            for k in cache.keys where under(k) { cache[k] = nil }
            out.unreadable = out.unreadable.filter { !under($0) }
            out.conflictCopies.removeAll(where: under)
            out.problems.removeAll(where: { under($0.path) })
            guard let exact = spelledAsOnDisk(rel) else { return nil }
            guard exact else { continue } // gone
            // a path the full walk never goes into (an ignored or unsafe folder above it) stays out
            let parts = rel.split(separator: "/").map(String.init)
            if parts.dropLast().contains(where: SyncPaths.isIgnoredFolder) { continue }
            if (1..<parts.count).contains(where: { !SyncPaths.isSafe(parts[0..<$0].joined(separator: "/")) }) { continue }
            let url = folder.appendingPathComponent(rel)
            visit(url, rel, &out, &cache)
        }
        state.hashCache = cache
        out.conflictCopies.sort()
        lastScan = out
        return out
    }

    /// True when every part of `rel` is in the folder with exactly that name, false when it isn't there at all, nil when it is
    /// there in other capitals (the iPad's disk doesn't tell them apart; the names sent must be the folder's own).
    private func spelledAsOnDisk(_ rel: String) -> Bool? {
        var dir = folder
        for part in rel.split(separator: "/").map(String.init) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path).map(SyncPaths.nfc) else { return false }
            if !names.contains(part) {
                return names.contains(where: { $0.lowercased() == part.lowercased() }) ? nil : false
            }
            dir = dir.appendingPathComponent(part)
        }
        return true
    }

    private func walk(_ dir: URL, _ prefix: String, _ out: inout Scan, _ cache: inout [String: CachedHash]) {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Self.keys, options: []) else { return }
        for url in items {
            let name = SyncPaths.nfc(url.lastPathComponent)
            visit(url, prefix.isEmpty ? name : prefix + "/" + name, &out, &cache)
        }
    }

    /// One file or folder of a scan.
    private func visit(_ url: URL, _ rel: String, _ out: inout Scan, _ cache: inout [String: CachedHash]) {
        let name = String(rel.split(separator: "/").last ?? "")
        guard let v = try? url.resourceValues(forKeys: Set(Self.keys)), v.isSymbolicLink != true else { return }
        if v.isDirectory == true {
            if SyncPaths.isIgnoredFolder(name) { return }
            guard SyncPaths.isSafe(rel) else {
                out.problems.append(SyncProblem(path: rel, message: "This folder's name can't be used on every device, so it isn't synced. Rename it."))
                return
            }
            walk(url, rel, &out, &cache)
            return
        }
        guard v.isRegularFile == true, !SyncPaths.isIgnored(rel) else { return }
        guard SyncPaths.isSafe(rel) else {
            out.problems.append(SyncProblem(path: rel, message: "This name can't be used on every device, so it isn't synced. Rename it."))
            return
        }
        let size = Int64(v.fileSize ?? 0)
        let mtime = (v.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000
        if let c = state.hashCache[rel], c.size == size, c.mtimeMs == mtime {
            cache[rel] = c
        } else if let h = try? SyncHash.file(url) {
            cache[rel] = CachedHash(size: size, mtimeMs: mtime, hash: h)
        } else {
            out.unreadable.insert(rel)
            return
        }
        out.files[rel] = LocalFile(hash: cache[rel]!.hash, size: size, mtimeMs: mtime)
        if SyncPaths.isConflictCopy(rel) { out.conflictCopies.append(rel) }
    }

    /// The hash of the file at `rel` now (nil when there is none), from the cache when its size and time are unchanged.
    private func localHash(_ rel: String) throws -> String? {
        let url = folder.appendingPathComponent(rel)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { throw SyncError.local("There is a folder here with that name.") }
        let v = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = Int64(v.fileSize ?? 0)
        let mtime = (v.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000
        if let c = state.hashCache[rel], c.size == size, c.mtimeMs == mtime { return c.hash }
        let h = try SyncHash.file(url)
        state.hashCache[rel] = CachedHash(size: size, mtimeMs: mtime, hash: h)
        return h
    }

    private func remember(_ rel: String, _ hash: String) {
        let url = folder.appendingPathComponent(rel)
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        state.hashCache[rel] = CachedHash(size: Int64(v.fileSize ?? 0), mtimeMs: (v.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000, hash: hash)
    }

    enum Fetched {
        case wrote(String)
        /// The file here no longer has the hash expected: left as it is.
        case changedHere
        /// The hub has no live file there any more.
        case goneOnHub
    }

    /// Downloads `rel` to a dot-named temp file beside it, checks it against `X-Nexus-Hash`, and renames it into place only if
    /// the file here still has `expected` (nil: there is still none).
    private func fetch(_ rel: String, expecting expected: String?) async throws -> Fetched {
        let target = folder.appendingPathComponent(rel)
        let dir = target.deletingLastPathComponent()
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            throw SyncError.local("Couldn't make its folder: \(describe(error))")
        }
        let temp = dir.appendingPathComponent(".\(target.lastPathComponent).\(UUID().uuidString.prefix(8)).partial")
        defer { try? fm.removeItem(at: temp) }
        let header: String?
        do {
            header = try await transport.download(path: rel, to: temp)
        } catch SyncError.notFound {
            removeEmptyFolders(above: rel)
            return .goneOnHub
        }
        let got = try SyncHash.file(temp)
        if let header, header.lowercased() != got { throw SyncError.hashMismatch(rel) }
        guard try localHash(rel) == expected else { return .changedHere }
        if rename(temp.path, target.path) != 0 {
            throw SyncError.local("Couldn't write it: \(String(cString: strerror(errno)))")
        }
        remember(rel, got)
        hints.insert(rel) // the next quick scan sees it (else it would look deleted here)
        return .wrote(got)
    }

    /// Deletes `rel` if it still has `expected`, and any folder that leaves empty.
    private func removeLocal(_ rel: String, expecting expected: String) throws -> Bool {
        guard try localHash(rel) == expected else { return false }
        try fm.removeItem(at: folder.appendingPathComponent(rel))
        state.hashCache[rel] = nil
        hints.insert(rel)
        removeEmptyFolders(above: rel)
        return true
    }

    private func removeEmptyFolders(above rel: String) {
        var parts = rel.split(separator: "/").dropLast().map(String.init)
        while !parts.isEmpty {
            let d = folder.appendingPathComponent(parts.joined(separator: "/"))
            guard let items = try? fm.contentsOfDirectory(atPath: d.path), items.isEmpty else { return }
            try? fm.removeItem(at: d)
            parts.removeLast()
        }
    }

    private func moveAside(_ now: Date) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        let parent = folder.deletingLastPathComponent()
        let stem = "\(folder.lastPathComponent) before sync \(f.string(from: now))"
        var dest = parent.appendingPathComponent(stem, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = parent.appendingPathComponent("\(stem) \(n)", isDirectory: true)
            n += 1
        }
        do { try fm.moveItem(at: folder, to: dest) } catch {
            throw SyncError.local("Couldn't move the folder aside: \(describe(error))")
        }
        return dest
    }

    private func compare(_ local: Scan, _ page: HubChanges) -> FirstSyncSummary {
        var hub: [String: String] = [:]
        for c in page.changes where !c.deleted {
            if let h = c.hash, SyncPaths.isSafe(c.path), !SyncPaths.isIgnored(c.path) { hub[c.path] = h }
        }
        var s = FirstSyncSummary()
        s.hubFiles = hub.count
        s.localFiles = local.files.count + local.unreadable.count
        for (p, f) in local.files {
            if let h = hub[p] {
                if h == f.hash { s.same += 1 } else { s.differ += 1 }
            } else {
                s.onlyHere += 1
            }
        }
        s.onlyHere += local.unreadable.count
        s.onlyOnHub = hub.keys.filter { local.files[$0] == nil }.count
        s.localIsDataFolder = local.files["nexus.yaml"] != nil
        return s
    }

    private func describe(_ error: Error) -> String {
        if let e = error as? SyncError { return e.plainWords }
        return error.localizedDescription
    }
}
