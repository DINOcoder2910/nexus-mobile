import Foundation
import NexusCore

/// The one way Nexus on the iPad asks Claude. `stream` follows the app-wide switch (ClaudeAccount): API mode calls the Messages API with
/// the user's key, streamed; plan mode asks the hub (POST /v1/claude), which hands the request to the Duo's Nexus when it is open and
/// otherwise runs Claude Code on the G14 (the Nexus repo's docs/sync.md "Claude through the hub"). The text arrives through `onText` as
/// it streams (on any thread). Cancelling the caller's Task ends the call and returns what arrived with `stopped` set (its spending is
/// counted); a failure throws a ClaudeError in words.
final class ClaudeClient: @unchecked Sendable {
    static let shared = ClaudeClient()

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 120
        c.timeoutIntervalForResource = 15 * 60
        return URLSession(configuration: c)
    }()

    func stream(_ req: ClaudeRequest, onText: @escaping (String) -> Void) async throws -> ClaudeReply {
        let mode = await MainActor.run { ClaudeAccount.shared.mode }
        return mode == .api ? try await api(req, onText: onText) : try await plan(req, onText: onText)
    }

    // MARK: API mode

    private func api(_ req: ClaudeRequest, onText: @escaping (String) -> Void) async throws -> ClaudeReply {
        guard let key = ClaudeAccount.readKey() else { throw ClaudeError.noKey }
        var r = URLRequest(url: ClaudeWire.apiURL)
        r.httpMethod = "POST"
        r.setValue(key, forHTTPHeaderField: "x-api-key")
        r.setValue(ClaudeWire.apiVersion, forHTTPHeaderField: "anthropic-version")
        r.setValue(ClaudeWire.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = Data(ClaudeWire.apiBody(req).text.utf8)

        let t0 = Date()
        var reply = ClaudeReply(model: ClaudeModels.id(req.model), mode: .api)
        var usage = ClaudeUsage()
        var sawUsage = false
        var failed: String?
        do {
            let (bytes, resp) = try await session.bytes(for: r)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status != 200 {
                let b = try await Self.body(bytes)
                throw ClaudeError(ClaudeWire.friendly(status: status, body: b))
            }
            for try await line in bytes.lines {
                if Task.isCancelled { reply.stopped = true; break }
                guard line.hasPrefix("data:") else { continue }
                switch ClaudeWire.event(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) {
                case .start(let model, let u):
                    if let model { reply.model = model }
                    if let u { usage = u; sawUsage = true }
                case .text(let t):
                    if reply.msToFirstText == nil { reply.msToFirstText = Int(Date().timeIntervalSince(t0) * 1000) }
                    reply.text += t
                    onText(t)
                case .delta(let stop, let u):
                    if let stop { reply.stopReason = stop }
                    if u != nil { usage.merge(u); sawUsage = true }
                case .error(let m): failed = m
                case .stop, .other: break
                }
                if failed != nil { break }
            }
        } catch let e as ClaudeError {
            throw e
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError { reply.stopped = true }
            else { throw ClaudeError(Self.netMessage(error, api: true)) }
        }
        // spending: what the reply used, even when it was stopped part way
        if sawUsage {
            reply.usage = usage
            reply.cost = ClaudePrices.cost(model: reply.model, usage: usage)
            let cost = reply.cost, used = usage
            await MainActor.run { ClaudeAccount.shared.addSpend(cost, usage: used) }
        }
        if let failed, !reply.stopped { throw ClaudeError(failed) }
        if reply.stopped { reply.stopReason = reply.stopReason ?? "stopped" }
        return reply
    }

    // MARK: plan mode (through the hub)

    private func plan(_ req: ClaudeRequest, onText: @escaping (String) -> Void) async throws -> ClaudeReply {
        let d = UserDefaults.standard
        let token = (Keychain.get("hub-token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hub = HTTPSyncTransport.hubURL(d.string(forKey: "sync.hubAddress") ?? ""), !token.isEmpty else { throw ClaudeError.noHub }
        var r = URLRequest(url: hub.appendingPathComponent("v1/claude"))
        r.httpMethod = "POST"
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        r.setValue(d.string(forKey: "sync.deviceName") ?? "iPad", forHTTPHeaderField: "X-Nexus-Device")
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.httpBody = Data(ClaudeWire.relayBody(req).text.utf8)

        let t0 = Date()
        var reply = ClaudeReply(model: ClaudeModels.id(req.model), mode: .plan, sessionId: req.sessionId)
        do {
            let (bytes, resp) = try await session.bytes(for: r)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { throw ClaudeError("The hub can't run Claude yet: update Nexus on the G14 (its hub), or tap the Plan chip to use your API key.") }
            if status == 401 { throw ClaudeError("The hub refused this iPad's token. Check it in Settings › Sync.") }
            if status != 200 {
                let b = try await Self.body(bytes)
                throw ClaudeError((try? JSONValue.parse(b))?["error"]?.string ?? "The hub answered with an error (\(status)).")
            }
            var done = false
            for try await line in bytes.lines {
                if Task.isCancelled { reply.stopped = true; break }
                switch ClaudeWire.relayEvent(line) {
                case .text(let t):
                    if reply.msToFirstText == nil { reply.msToFirstText = Int(Date().timeIntervalSince(t0) * 1000) }
                    reply.text += t
                    onText(t)
                case .done(let model, let sid, let usage, _):
                    if let model { reply.model = model }
                    if let sid { reply.sessionId = sid }
                    reply.usage = usage
                    reply.stopReason = "end_turn"
                    done = true
                case .error(let m): throw ClaudeError(m)
                case .other: break
                }
                if done { break }
            }
            if !done && !reply.stopped { throw ClaudeError("The hub stopped answering part way. Try again.") }
        } catch let e as ClaudeError {
            throw e
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError { reply.stopped = true }
            else { throw ClaudeError(Self.netMessage(error, api: false)) }
        }
        if reply.stopped { reply.stopReason = "stopped" }
        return reply
    }

    // MARK: helpers

    private static func body(_ bytes: URLSession.AsyncBytes) async throws -> String {
        var data = Data()
        for try await b in bytes { data.append(b); if data.count > 65_536 { break } }
        return String(decoding: data, as: UTF8.self)
    }

    private static func netMessage(_ e: Error, api: Bool) -> String {
        let code = (e as? URLError)?.code
        if api { return code == .notConnectedToInternet || code == .networkConnectionLost || code == .timedOut ? "Could not reach the Claude API. Check the iPad's internet connection." : "Could not reach the Claude API (\(e.localizedDescription))." }
        return "Could not reach the hub for your plan. Check Tailscale or the home Wi-Fi, or tap the Plan chip to use your API key."
    }
}
