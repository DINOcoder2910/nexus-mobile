import Foundation

// Claude on the iPad, the pure half (the app's Sources/Claude/ does the networking, the Keychain and the chip).
// One app-wide switch picks how Claude is reached, as on the laptop (Settings › Claude › Plan or API, and a Plan / API chip beside
// every Claude feature): `api` calls the Messages API straight from the iPad with the user's own key (the iPad's default: fastest, works
// anywhere); `plan` asks the user's Claude Code on a computer through the hub relay (the Duo when its Nexus is open, else the G14).
// Here: the request and reply types every feature uses, the model names, the prices and this month's spending (the same table and wording
// as the laptop's claude-api.js), the Messages API's request body and its streamed events, and the relay's lines.

public enum ClaudeMode: String, Codable, CaseIterable, Sendable {
    case plan, api
    /// What the chip says.
    public var chip: String { self == .api ? "API" : "Plan" }
    /// What a sentence says ("Claude uses your API key").
    public var name: String { self == .api ? "your API key" : "your Claude plan" }
}

/// One piece of a message: text, or a picture (a JPEG or PNG, base64).
public enum ClaudeBlock: Equatable, Sendable {
    case text(String)
    case image(mediaType: String, base64: String)
}

public struct ClaudeMessage: Equatable, Sendable {
    public var role: String // "user" | "assistant"
    public var content: [ClaudeBlock]
    public init(role: String, content: [ClaudeBlock]) { self.role = role; self.content = content }
    public static func user(_ text: String) -> ClaudeMessage { ClaudeMessage(role: "user", content: [.text(text)]) }
    public static func assistant(_ text: String) -> ClaudeMessage { ClaudeMessage(role: "assistant", content: [.text(text)]) }
    /// The message's text blocks joined (what plan mode sends when it resumes a session).
    public var text: String {
        content.compactMap { if case .text(let t) = $0 { return t }; return nil }.joined(separator: "\n")
    }
}

public struct ClaudeRequest: Sendable {
    /// A full id ("claude-sonnet-5-5") or a short name (sonnet, haiku, opus).
    public var model: String
    public var system: String
    public var messages: [ClaudeMessage]
    public var maxTokens: Int
    /// low | medium | high | xhigh | max, or nil for the model's default.
    public var effort: String?
    /// Mark the system prompt for the prompt cache (it is the same every turn).
    public var cacheSystem: Bool
    /// Plan mode: the relay's session to resume (it then sends only the last user message). API mode ignores it.
    public var sessionId: String?
    public init(model: String, system: String, messages: [ClaudeMessage], maxTokens: Int = 2048, effort: String? = nil, cacheSystem: Bool = true, sessionId: String? = nil) {
        self.model = model; self.system = system; self.messages = messages; self.maxTokens = maxTokens
        self.effort = effort; self.cacheSystem = cacheSystem; self.sessionId = sessionId
    }
}

public struct ClaudeUsage: Equatable, Codable, Sendable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheCreationInputTokens = 0
    public var cacheReadInputTokens = 0
    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheCreationInputTokens: Int = 0, cacheReadInputTokens: Int = 0) {
        self.inputTokens = inputTokens; self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens; self.cacheReadInputTokens = cacheReadInputTokens
    }
    /// From the API's `usage` object (snake_case); fields it leaves out keep their value (a message_delta carries only output_tokens).
    public mutating func merge(_ v: JSONValue?) {
        guard let v else { return }
        if let n = v["input_tokens"]?.number { inputTokens = Int(n) }
        if let n = v["output_tokens"]?.number { outputTokens = Int(n) }
        if let n = v["cache_creation_input_tokens"]?.number { cacheCreationInputTokens = Int(n) }
        if let n = v["cache_read_input_tokens"]?.number { cacheReadInputTokens = Int(n) }
    }
    public static func from(_ v: JSONValue?) -> ClaudeUsage? { guard v?.object != nil else { return nil }; var u = ClaudeUsage(); u.merge(v); return u }
    /// Every input token, cached or not.
    public var allInput: Int { inputTokens + cacheCreationInputTokens + cacheReadInputTokens }
}

public struct ClaudeReply: Sendable {
    public var text: String
    public var usage: ClaudeUsage?
    /// Dollars this reply cost through the API key (0 in plan mode: the plan costs nothing extra).
    public var cost: Double
    public var model: String
    public var mode: ClaudeMode
    /// Milliseconds until the first text arrived (nil when none did).
    public var msToFirstText: Int?
    public var stopReason: String?
    /// The caller's Task was cancelled part way: `text` is what arrived, and its spending is counted.
    public var stopped: Bool
    /// Plan mode: the relay's session, to resume next turn.
    public var sessionId: String?
    public init(text: String = "", usage: ClaudeUsage? = nil, cost: Double = 0, model: String = "", mode: ClaudeMode = .api, msToFirstText: Int? = nil, stopReason: String? = nil, stopped: Bool = false, sessionId: String? = nil) {
        self.text = text; self.usage = usage; self.cost = cost; self.model = model; self.mode = mode
        self.msToFirstText = msToFirstText; self.stopReason = stopReason; self.stopped = stopped; self.sessionId = sessionId
    }
}

/// A failed call, said in words the user can act on.
public struct ClaudeError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }

    public static let noKey = ClaudeError("Claude is set to use your API key, but there is no key yet. Add one in Settings › Claude, or tap the API chip to switch back to your plan.")
    public static let noHub = ClaudeError("Claude is set to use your plan, which runs on your computer through the hub. Set up Sync in Settings first, or tap the Plan chip to use your API key.")
}

// MARK: models and prices

public enum ClaudeModels {
    /// The short names the app uses -> the current ids (never Fable), as the laptop's claude-service.js MODEL_ALIASES.
    public static let aliases = ["sonnet": "claude-sonnet-5-5", "haiku": "claude-haiku-5-5", "opus": "claude-opus-5-5"]
    public static func id(_ m: String?, default def: String = "sonnet") -> String {
        let s = (m ?? "").trimmingCharacters(in: .whitespaces)
        if let a = aliases[s.lowercased()] { return a }
        return s.isEmpty ? aliases[def]! : s
    }
}

public enum ClaudePrices {
    /// $ per million tokens (Anthropic's first-party prices, 2026-11), the laptop's table. cw: writing the prompt cache, cr: reading it.
    public struct Price: Sendable { public let input, output, cacheWrite, cacheRead: Double }
    public static let table: [String: Price] = [
        "claude-opus-5-5": Price(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.2),
        "claude-sonnet-5-5": Price(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.1),
        "claude-sonnet-5": Price(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.2),
        "claude-haiku-5-5": Price(input: 0.1, output: 0.5, cacheWrite: 0.125, cacheRead: 0.01),
        "claude-opus-4-8": Price(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5),
    ]
    /// An unknown model is counted at Opus prices: never under.
    public static func price(_ model: String) -> Price {
        if let p = table[model] { return p }
        let bare = model.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        return table[bare] ?? table["claude-opus-5-5"]!
    }
    public static func cost(model: String, usage: ClaudeUsage?) -> Double {
        guard let u = usage else { return 0 }
        let p = price(model)
        return (Double(u.inputTokens) * p.input + Double(u.outputTokens) * p.output + Double(u.cacheCreationInputTokens) * p.cacheWrite + Double(u.cacheReadInputTokens) * p.cacheRead) / 1_000_000
    }
}

/// What Nexus on this iPad spent through the API key, by local month (kept in Application Support, never in the data folder).
public struct ClaudeSpend: Codable, Equatable, Sendable {
    public struct Month: Codable, Equatable, Sendable {
        public var usd = 0.0, calls = 0, input = 0, output = 0
        public init() {}
    }
    public var v = 1
    public var months: [String: Month] = [:]
    public init() {}

    public static func monthKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
    public mutating func add(usd: Double, usage: ClaudeUsage?, at date: Date = Date(), calendar: Calendar = .current) {
        let k = Self.monthKey(date, calendar: calendar)
        var m = months[k] ?? Month()
        m.usd = ((m.usd + max(0, usd)) * 1e6).rounded() / 1e6
        m.calls += 1
        m.input += usage?.allInput ?? 0
        m.output += usage?.outputTokens ?? 0
        months[k] = m
    }
    public func month(_ date: Date = Date(), calendar: Calendar = .current) -> Month { months[Self.monthKey(date, calendar: calendar)] ?? Month() }
    /// The laptop's wording (tutor/session.js spendText): "$0.012 this month (3 replies)" or "Nothing spent this month".
    public static func text(_ m: Month) -> String {
        guard m.calls > 0 else { return "Nothing spent this month" }
        let usd = String(format: m.usd < 0.1 ? "%.3f" : "%.2f", m.usd)
        return "$\(usd) this month (\(m.calls) \(m.calls == 1 ? "reply" : "replies"))"
    }
}

// MARK: the wire

public enum ClaudeWire {
    public static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2023-06-01"
    /// A declined reply is re-run on a fallback model inside the same call (the laptop sends the same).
    public static let fallbackBeta = "server-side-fallback-2026-07-01"

    static func blockJSON(_ b: ClaudeBlock) -> JSONValue {
        switch b {
        case .text(let t): return .object([("type", .string("text")), ("text", .string(t))])
        case .image(let mt, let data):
            return .object([("type", .string("image")), ("source", .object([("type", .string("base64")), ("media_type", .string(mt)), ("data", .string(data))]))])
        }
    }
    static func messagesJSON(_ ms: [ClaudeMessage]) -> JSONValue {
        .array(ms.map { .object([("role", .string($0.role)), ("content", .array($0.content.map(blockJSON)))]) })
    }

    /// The Messages API body: streamed, the system prompt cached, effort in output_config, fallbacks on.
    public static func apiBody(_ r: ClaudeRequest) -> JSONValue {
        var sys: [(String, JSONValue)] = [("type", .string("text")), ("text", .string(r.system))]
        if r.cacheSystem { sys.append(("cache_control", .object([("type", .string("ephemeral"))]))) }
        var o: [(String, JSONValue)] = [
            ("model", .string(ClaudeModels.id(r.model))),
            ("max_tokens", .number(Double(r.maxTokens))),
            ("stream", .bool(true)),
        ]
        if !r.system.isEmpty { o.append(("system", .array([.object(sys)]))) }
        o.append(("messages", messagesJSON(r.messages)))
        if let e = r.effort, !e.isEmpty { o.append(("output_config", .object([("effort", .string(e))]))) }
        o.append(("fallbacks", .string("default")))
        return .object(o)
    }

    /// One server-sent event's `data:` payload, read.
    public enum Event: Equatable {
        case start(model: String?, usage: ClaudeUsage?)
        case text(String)
        case delta(stopReason: String?, usage: JSONValue?)
        case stop
        case error(String)
        case other
    }
    public static func event(_ data: String) -> Event {
        guard let v = try? JSONValue.parse(data) else { return .other }
        switch v["type"]?.string {
        case "message_start": return .start(model: v["message"]?["model"]?.string, usage: ClaudeUsage.from(v["message"]?["usage"]))
        case "content_block_delta":
            if v["delta"]?["type"]?.string == "text_delta", let t = v["delta"]?["text"]?.string { return .text(t) }
            return .other
        case "message_delta": return .delta(stopReason: v["delta"]?["stop_reason"]?.string, usage: v["usage"])
        case "message_stop": return .stop
        case "error": return .error(v["error"]?["message"]?.string ?? "Claude reported an error.")
        default: return .other
        }
    }

    /// An HTTP failure in words (the laptop's claude-api.js friendly()).
    public static func friendly(status: Int, body: String) -> String {
        let m = body.lowercased()
        if status == 401 || m.contains("invalid x-api-key") || m.contains("authentication") { return "Your API key was refused. Check it in Settings › Claude, or tap the API chip to switch back to your plan." }
        if status == 402 || m.contains("credit balance") || m.contains("billing") { return "Your API credits have run out. Tap the API chip to switch back to your plan." }
        if status == 429 { return "Too many requests right now. Try again in a moment." }
        if status == 529 || m.contains("overloaded") { return "Claude is busy right now. Try again in a moment." }
        if let v = try? JSONValue.parse(body), let msg = v["error"]?["message"]?.string { return String(msg.prefix(300)) }
        return "Claude answered with an error (\(status))."
    }

    // ---- the plan relay (the hub's POST /v1/claude, Nexus repo docs/sync.md "Claude through the hub"): the same request as JSON in,
    // one JSON object per line out: {"type":"text","text":…} as it streams, then {"type":"done",…} or {"type":"error","message":…}.

    public static func relayBody(_ r: ClaudeRequest) -> JSONValue {
        var o: [(String, JSONValue)] = [
            ("model", .string(ClaudeModels.id(r.model))),
            ("system", .string(r.system)),
            ("messages", messagesJSON(r.messages)),
            ("maxTokens", .number(Double(r.maxTokens))),
        ]
        if let e = r.effort { o.append(("effort", .string(e))) }
        if let s = r.sessionId { o.append(("sessionId", .string(s))) }
        return .object(o)
    }
    public enum RelayEvent: Equatable {
        case text(String)
        case done(model: String?, sessionId: String?, usage: ClaudeUsage?, by: String?)
        case error(String)
        case other
    }
    public static func relayEvent(_ line: String) -> RelayEvent {
        guard let v = try? JSONValue.parse(line) else { return .other }
        switch v["type"]?.string {
        case "text": return .text(v["text"]?.string ?? "")
        case "done": return .done(model: v["model"]?.string, sessionId: v["sessionId"]?.string, usage: ClaudeUsage.from(v["usage"]), by: v["by"]?.string)
        case "error": return .error(v["message"]?.string ?? "Claude reported an error.")
        default: return .other
        }
    }
}
