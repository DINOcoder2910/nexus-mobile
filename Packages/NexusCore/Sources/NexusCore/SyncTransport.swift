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

    enum CodingKeys: String, CodingKey {
        case hub, protocolVersion = "protocol", folderId, seq
    }

    public init(hub: String, protocolVersion: Int, folderId: String, seq: Int) {
        self.hub = hub
        self.protocolVersion = protocolVersion
        self.folderId = folderId
        self.seq = seq
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
    /// `base` nil sends `base=none`.
    func put(path: String, base: String?, body: SyncBody, hash: String) async throws -> PutResult
    func delete(path: String, base: String) async throws -> DeleteResult
}

/// The real hub over HTTP (plain HTTP over Tailscale or the home network).
public final class HTTPSyncTransport: SyncTransport {
    public let base: URL
    let token: String
    let device: String
    let session: URLSession

    public init(base: URL, token: String, device: String, session: URLSession = .shared) {
        self.base = base
        self.token = token
        self.device = device
        self.session = session
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
        c.path = "/v1/" + endpoint
        if !query.isEmpty { c.percentEncodedQuery = query.map { "\($0.0)=\(Self.encode($0.1))" }.joined(separator: "&") }
        guard let url = c.url else { throw SyncError.notAHub }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue(device, forHTTPHeaderField: "X-Nexus-Device")
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

    public func put(path: String, base: String?, body: SyncBody, hash: String) async throws -> PutResult {
        var r = try request("file", [("path", path), ("base", base ?? "none")], method: "PUT", timeout: 120)
        r.setValue(hash, forHTTPHeaderField: "X-Nexus-Hash")
        r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return try decode(PutResult.self, try await send(r, body: body))
    }

    public func delete(path: String, base: String) async throws -> DeleteResult {
        let r = try request("file", [("path", path), ("base", base)], method: "DELETE")
        return try decode(DeleteResult.self, try await send(r))
    }
}
