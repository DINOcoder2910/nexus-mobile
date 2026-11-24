import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The hub's HTTP protocol (docs/sync.md, "The protocol"), behind a small protocol so the tests can use an in-process hub.

/// `GET /v1/hello`.
public struct HubHello: Codable, Equatable, Sendable {
    public var hub: String
    public var protocolVersion: Int
    public var folderId: String
    public var seq: Int
    /// What the hub can do beyond protocol 1 (the Rust hub's `v2`, docs/sync.md "The Rust hub"); nil from the Node hub.
    public var v2: HubV2?

    enum CodingKeys: String, CodingKey {
        case hub, protocolVersion = "protocol", folderId, seq, v2
    }

    public init(hub: String, protocolVersion: Int, folderId: String, seq: Int, v2: HubV2? = nil) {
        self.hub = hub
        self.protocolVersion = protocolVersion
        self.folderId = folderId
        self.seq = seq
        self.v2 = v2
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hub = try c.decode(String.self, forKey: .hub)
        protocolVersion = try c.decode(Int.self, forKey: .protocolVersion)
        folderId = try c.decode(String.self, forKey: .folderId)
        seq = try c.decode(Int.self, forKey: .seq)
        v2 = try? c.decodeIfPresent(HubV2.self, forKey: .v2) // a v2 this app can't read is no v2: protocol 1 still works
    }

    /// The v2 features this hub has (`ops`, `feed`, `ifhash`, `backup`, `activity`).
    public var features: Set<String> { Set(v2?.features ?? []) }
}

/// `hello.v2`: the Rust hub's additions. `features` names them; `hub` says which hub it is.
public struct HubV2: Codable, Equatable, Sendable {
    public struct Impl: Codable, Equatable, Sendable {
        public var impl: String?
        public var version: String?
        public var build: String?

        public init(impl: String?, version: String? = nil, build: String? = nil) {
            self.impl = impl
            self.version = version
            self.build = build
        }
    }

    public var features: [String]
    public var hub: Impl?

    enum CodingKeys: String, CodingKey { case features, hub }

    public init(features: [String], hub: Impl? = nil) {
        self.features = features
        self.hub = hub
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        features = (try? c.decodeIfPresent([String].self, forKey: .features)) ?? []
        hub = try? c.decodeIfPresent(Impl.self, forKey: .hub)
    }
}

/// One line of the change feed (`GET /v2/feed`, NDJSON): the hub writes one whenever files or who is where change, and a ping
/// every 20 s.
public enum HubFeedEvent: Equatable, Sendable {
    /// The first line, then one per change: the hub's folder and its newest seq.
    case changes(folderId: String, seq: Int)
    case presence(HubPresenceReply)
    case ping(seq: Int)

    /// One line of the feed, or nil for a line this app doesn't know.
    public static func parse(_ line: String) -> HubFeedEvent? {
        guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let type = o["type"] as? String else { return nil }
        let seq = (o["seq"] as? NSNumber)?.intValue
        switch type {
        case "hello", "changes":
            guard let f = o["folderId"] as? String, let seq else { return nil }
            return .changes(folderId: f, seq: seq)
        case "presence":
            return (try? JSONDecoder().decode(HubPresenceReply.self, from: d)).map { .presence($0) }
        case "ping":
            return .ping(seq: seq ?? 0)
        default:
            return nil
        }
    }
}

/// One entry of `GET /v1/changes`: the latest state of a path.
public struct HubChange: Codable, Equatable, Sendable {
    public var path: String
    /// nil for a deletion.
    public var hash: String?
    public var size: Int64?
    public var deleted: Bool
    public var seq: Int
    public var device: String?

    enum CodingKeys: String, CodingKey { case path, hash, size, deleted, seq, device }

    public init(path: String, hash: String?, size: Int64? = nil, deleted: Bool = false, seq: Int, device: String? = nil) {
        self.path = path
        self.hash = hash
        self.size = size
        self.deleted = deleted
        self.seq = seq
        self.device = device
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decode(String.self, forKey: .path)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        size = try? c.decodeIfPresent(Int64.self, forKey: .size)
        deleted = (try? c.decodeIfPresent(Bool.self, forKey: .deleted)) ?? false
        seq = try c.decode(Int.self, forKey: .seq)
        device = try? c.decodeIfPresent(String.self, forKey: .device)
    }
}

public struct HubChanges: Codable, Equatable, Sendable {
    public var folderId: String
    public var seq: Int
    public var changes: [HubChange]

    public init(folderId: String, seq: Int, changes: [HubChange]) {
        self.folderId = folderId
        self.seq = seq
        self.changes = changes
    }
}

/// `PUT /v1/file`: `ok`, `same`, `merged` or `conflict`.
public struct PutResult: Codable, Equatable, Sendable {
    public var result: String
    public var hash: String?
    public var seq: Int?
    public var conflictPath: String?

    public init(result: String, hash: String?, seq: Int? = nil, conflictPath: String? = nil) {
        self.result = result
        self.hash = hash
        self.seq = seq
        self.conflictPath = conflictPath
    }
}

/// `DELETE /v1/file`: `ok` or `kept`.
public struct DeleteResult: Codable, Equatable, Sendable {
    public var result: String
    public var hash: String?
    public var seq: Int?

    public init(result: String, hash: String? = nil, seq: Int? = nil) {
        self.result = result
        self.hash = hash
        self.seq = seq
    }
}

/// What a PUT sends: small files from memory, big ones streamed from the file.
public enum SyncBody: Sendable {
    case data(Data)
    case file(URL)
}

public enum SyncError: Error, Equatable, Sendable {
    /// No connection, or it dropped: retried with backoff.
    case offline(String)
    /// A 5xx from the hub: retried with backoff.
    case server(Int)
    case unauthorized
    case notFound
    /// `409 {result: "case"}`: another live file has the same name in other letter case.
    case sameNameDifferentCase
    case badRequest(String)
    case tooLarge
    case notAHub
    case newerHub(Int)
    case badReply
    /// A download did not match its `X-Nexus-Hash`.
    case hashMismatch(String)
    /// Reading or writing the data folder failed.
    case local(String)

    /// Worth trying again soon by itself.
    public var isTransient: Bool {
        switch self {
        case .offline, .server, .hashMismatch: return true
        default: return false
        }
    }

    /// For the status line, in plain words.
    public var plainWords: String {
        switch self {
        case .offline: return "Offline, retrying"
        case .server(let code): return "The hub had a problem (error \(code)), retrying"
        case .unauthorized: return "The hub didn't accept the token. Copy it again from the hub."
        case .notFound: return "The hub didn't have that file."
        case .sameNameDifferentCase: return "The hub has another file with the same name in different capitals. Rename this one."
        case .badRequest(let why): return why.isEmpty ? "The hub refused it." : "The hub refused it: \(why)"
        case .tooLarge: return "Too big for the hub."
        case .notAHub: return "That address answered, but it isn't a Nexus hub. Check the address."
        case .newerHub: return "The hub is newer than this app. Update Nexus on the iPad."
        case .badReply: return "The hub's reply couldn't be read. Is the hub up to date?"
        case .hashMismatch: return "A download arrived damaged, retrying"
        case .local(let why): return why
        }
    }
}

/// The hub, as the sync client sees it.
public protocol SyncTransport: AnyObject, Sendable {
    func hello() async throws -> HubHello
    /// `wait`: hold the request up to that many seconds while nothing is newer (the long poll).
    func changes(since: Int, wait: Int?) async throws -> HubChanges
    /// Streams the hub's live file to `destination`, replacing anything there, and returns its `X-Nexus-Hash`.
    /// Throws `SyncError.notFound` when the hub has no live file there.
    func download(path: String, to destination: URL) async throws -> String?
    /// `base` nil sends `base=none`. `op`: the write's op id (`X-Nexus-Op`, a hub with `ops`): sent again after a lost answer, the hub
    /// gives its first answer instead of merging the same change twice.
    func put(path: String, base: String?, body: SyncBody, hash: String, op: String?) async throws -> PutResult
    func delete(path: String, base: String, op: String?) async throws -> DeleteResult
    /// The change feed (a hub with `feed`): the lines as they come, from `since`; it ends when the hub closes it (every 10 minutes).
    /// Throws `SyncError.notFound` where this transport has no feed.
    func feed(since: Int, psig: String) -> AsyncThrowingStream<HubFeedEvent, Error>
}

public extension SyncTransport {
    func put(path: String, base: String?, body: SyncBody, hash: String) async throws -> PutResult {
        try await put(path: path, base: base, body: body, hash: hash, op: nil)
    }

    func delete(path: String, base: String) async throws -> DeleteResult {
        try await delete(path: path, base: base, op: nil)
    }

    func feed(since: Int, psig: String) -> AsyncThrowingStream<HubFeedEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: SyncError.notFound) }
    }
}

/// The real hub over HTTP (plain HTTP over Tailscale or the home network).
public final class HTTPSyncTransport: SyncTransport {
    public let base: URL
    let token: String
    let device: String
    let session: URLSession
    /// What this app tells the hub on every request (`X-Nexus-App`, docs/sync.md "When one app is behind"):
    /// `app=nexus-mobile; build=<commit>; features=<board features it knows>`.
    let appInfo: String

    public init(base: URL, token: String, device: String, session: URLSession = .shared, appInfo: String = "") {
        self.base = base
        self.token = token
        self.device = device
        self.session = session
        self.appInfo = appInfo
    }

    /// The `X-Nexus-App` value for this app.
    public static func appInfo(build: String) -> String {
        "app=nexus-mobile; build=\(build); features=" + BoardFormat.features.sorted().joined(separator: ",")
    }

    public static let defaultPort = 8743

    /// What the user typed as the hub's address (`100.64.1.2`, `g14:8743`, `http://g14.tailnet.ts.net:8743/`) as a base URL,
    /// or nil if it can't be one. Without a scheme it is `http`; plain `http` without a port uses the hub's default port.
    public static func hubURL(_ text: String) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if !t.contains("://") { t = "http://" + t }
        guard var c = URLComponents(string: t), let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = c.host, !host.isEmpty else { return nil }
        c.scheme = scheme
        if c.port == nil && scheme == "http" { c.port = defaultPort }
        c.path = ""
        c.query = nil
        c.fragment = nil
        c.user = nil
        c.password = nil
        return c.url
    }

    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s }

    func request(_ endpoint: String, _ query: [(String, String)] = [], method: String = "GET", timeout: TimeInterval = 60) throws -> URLRequest {
        guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw SyncError.notAHub }
        c.path = endpoint.hasPrefix("v2/") ? "/" + endpoint : "/v1/" + endpoint
        if !query.isEmpty { c.percentEncodedQuery = query.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&") }
        guard let url = c.url else { throw SyncError.notAHub }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(device, forHTTPHeaderField: "X-Nexus-Device")
        if !appInfo.isEmpty { r.setValue(appInfo, forHTTPHeaderField: "X-Nexus-App") }
        return r
    }

    static func check(_ status: Int, _ body: Data) throws {
        switch status {
        case 200..<300: return
        case 401: throw SyncError.unauthorized
        case 404: throw SyncError.notFound
        case 409: throw SyncError.sameNameDifferentCase
        case 413: throw SyncError.tooLarge
        case 400..<500:
            let why = String(decoding: body.prefix(300), as: UTF8.self)
            throw SyncError.badRequest((try? JSONDecoder().decode([String: String].self, from: body))?["error"] ?? why)
        default: throw SyncError.server(status)
        }
    }

    func send(_ r: URLRequest, body: SyncBody? = nil) async throws -> Data {
        do {
            let result: (Data, URLResponse)
            switch body {
            case nil: result = try await session.data(for: r)
            case .data(let d)?: result = try await session.upload(for: r, from: d)
            case .file(let u)?: result = try await session.upload(for: r, fromFile: u)
            }
            guard let http = result.1 as? HTTPURLResponse else { throw SyncError.badReply }
            try Self.check(http.statusCode, result.0)
            return result.0
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            throw SyncError.offline(e.localizedDescription)
        }
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw SyncError.badReply }
    }

    public func hello() async throws -> HubHello {
        do {
            return try decode(HubHello.self, try await send(try request("hello", timeout: 20)))
        } catch SyncError.notFound {
            throw SyncError.notAHub
        } catch SyncError.badReply {
            throw SyncError.notAHub
        }
    }

    public func changes(since: Int, wait: Int?) async throws -> HubChanges {
        var q = [("since", String(since))]
        if let wait { q.append(("wait", String(wait))) }
        let r = try request("changes", q, timeout: TimeInterval((wait ?? 0) + 30))
        return try decode(HubChanges.self, try await send(r))
    }

    public func download(path: String, to destination: URL) async throws -> String? {
        let r = try request("file", [("path", path)], timeout: 120)
        do {
            let (tmp, resp) = try await session.download(for: r)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let http = resp as? HTTPURLResponse else { throw SyncError.badReply }
            if !(200..<300).contains(http.statusCode) {
                try Self.check(http.statusCode, (try? Data(contentsOf: tmp)) ?? Data())
            }
            try? FileManager.default.removeItem(at: destination)
            do { try FileManager.default.moveItem(at: tmp, to: destination) } catch {
                throw SyncError.local("Couldn't save the download of \(path): \(error.localizedDescription)")
            }
            return http.value(forHTTPHeaderField: "X-Nexus-Hash")
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            throw SyncError.offline(e.localizedDescription)
        }
    }

    public func put(path: String, base: String?, body: SyncBody, hash: String, op: String?) async throws -> PutResult {
        var r = try request("file", [("path", path), ("base", base ?? "none")], method: "PUT", timeout: 120)
        r.setValue(hash, forHTTPHeaderField: "X-Nexus-Hash")
        if let op { r.setValue(op, forHTTPHeaderField: "X-Nexus-Op") }
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return try decode(PutResult.self, try await send(r, body: body))
    }

    // MARK: presence (docs/sync.md "Presence"): where this iPad is working, and where the other devices are

    /// Tells the hub where this iPad is working (nil board: nowhere); the answer is everyone else's.
    public func tellPresence(board: String?, block: String?, what: String?) async throws -> HubPresenceReply {
        var r = try request("presence", method: "POST", timeout: 15)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var o: [(String, JSONValue)] = []
        if let board, let what { o = [("board", .string(board)), ("block", block.map { .string($0) } ?? .null), ("what", .string(what))] }
        return try decode(HubPresenceReply.self, try await send(r, body: .data(Data(JSONValue.object(o).text.utf8))))
    }

    /// Waits (a long poll) until where the other devices are differs from `psig`, or the time is up.
    public func waitPresence(psig: String, seconds: Int) async throws -> HubPresenceReply {
        let r = try request("changes", [("since", "1000000000000"), ("wait", String(seconds)), ("psig", psig)], timeout: TimeInterval(seconds + 30))
        return try decode(HubPresenceReply.self, try await send(r))
    }

    public func delete(path: String, base: String, op: String?) async throws -> DeleteResult {
        var r = try request("file", [("path", path), ("base", base)], method: "DELETE")
        if let op { r.setValue(op, forHTTPHeaderField: "X-Nexus-Op") }
        return try decode(DeleteResult.self, try await send(r))
    }

    // MARK: the change feed (docs/sync.md "The Rust hub")

    public func feed(since: Int, psig: String) -> AsyncThrowingStream<HubFeedEvent, Error> {
        #if canImport(Darwin)
        let request: URLRequest
        do {
            // (the hub pings every 20 s, so a minute's silence is a dead connection)
            request = try self.request("v2/feed", [("since", String(since)), ("psig", psig)], timeout: 60)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        let session = self.session
        return AsyncThrowingStream { out in
            let task = Task {
                do {
                    let (bytes, resp) = try await session.bytes(for: request)
                    guard let http = resp as? HTTPURLResponse else { throw SyncError.badReply }
                    if !(200..<300).contains(http.statusCode) { try Self.check(http.statusCode, Data()) }
                    for try await line in bytes.lines {
                        if let e = HubFeedEvent.parse(line) { out.yield(e) }
                    }
                    out.finish()
                } catch let e as URLError {
                    out.finish(throwing: e.code == .cancelled ? CancellationError() : SyncError.offline(e.localizedDescription))
                } catch {
                    out.finish(throwing: error)
                }
            }
            out.onTermination = { _ in task.cancel() }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: SyncError.notFound) } // (no streamed bytes in Linux Foundation: the long poll)
        #endif
    }
}
