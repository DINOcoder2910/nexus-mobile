import Foundation
import NexusCore

/// One request to the hub on the G14 outside sync itself (Google Docs' status, a task's history): the address and token from Settings ›
/// Sync, the device's name, and the hub's error words when it says no.
enum HubAsk {
    struct Failure: Error, LocalizedError {
        /// "nohub" (sync isn't set up), "old" (the hub doesn't know the request: a 404), "auth", "unreachable" or "hub".
        var kind: String
        var words: String
        var errorDescription: String? { words }
    }

    /// The hub's base address and token, when sync is set up.
    static var hub: (url: URL, token: String, device: String)? {
        let d = UserDefaults.standard
        let token = (Keychain.get("hub-token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = HTTPSyncTransport.hubURL(d.string(forKey: "sync.hubAddress") ?? ""), !token.isEmpty else { return nil }
        let name = (d.string(forKey: "sync.deviceName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (url, token, name.isEmpty ? Device.name : name)
    }

    /// `method route?query` with an optional JSON body -> the answer as JSON (an empty object when it has none).
    static func call(_ method: String, _ route: String, query: [(String, String)] = [], body: JSONValue? = nil, timeout: TimeInterval = 20) async throws -> JSONValue {
        guard let h = hub else { throw Failure(kind: "nohub", words: "Set up sync with the hub first (Settings › Sync).") }
        var c = URLComponents(url: h.url, resolvingAgainstBaseURL: false)
        c?.path = route.hasPrefix("/") ? route : "/" + route
        if !query.isEmpty { c?.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        // a + in a path must reach the hub as itself, not as a space
        c?.percentEncodedQuery = c?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = c?.url else { throw Failure(kind: "hub", words: "That isn't a request the hub can take.") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = timeout
        r.setValue("Bearer " + h.token, forHTTPHeaderField: "Authorization")
        r.setValue(h.device, forHTTPHeaderField: "X-Nexus-Device")
        if let body {
            r.httpBody = Data(body.text.utf8)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: r) }
        catch { throw Failure(kind: "unreachable", words: "Could not reach the hub (\(error.localizedDescription)).") }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        let json = (try? JSONValue.parse(text)) ?? .object([])
        if code == 401 { throw Failure(kind: "auth", words: "The hub did not accept this \(Device.name)'s token. Check it in Settings › Sync.") }
        if code == 404, json["error"]?.string == nil || json["error"]?.string == "unknown request" {
            throw Failure(kind: "old", words: "The hub is older than this Nexus and doesn't know this yet. Update the hub on the G14.")
        }
        guard (200..<300).contains(code) else { throw Failure(kind: "hub", words: json["error"]?.string ?? "The hub answered \(code).") }
        return json
    }
}
