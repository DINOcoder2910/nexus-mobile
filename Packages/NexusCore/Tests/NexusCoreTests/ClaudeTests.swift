import XCTest
@testable import NexusCore

/// Claude on the iPad, the pure half: models, prices and this month's spending (the laptop's numbers and wording), the Messages API body
/// and its streamed events, and the plan relay's lines.
final class ClaudeTests: XCTestCase {
    func testModelNames() {
        XCTAssertEqual(ClaudeModels.id("sonnet"), "claude-sonnet-5-5")
        XCTAssertEqual(ClaudeModels.id("Haiku"), "claude-haiku-5-5")
        XCTAssertEqual(ClaudeModels.id("opus"), "claude-opus-5-5")
        XCTAssertEqual(ClaudeModels.id("claude-opus-4-8"), "claude-opus-4-8")
        XCTAssertEqual(ClaudeModels.id(nil, default: "haiku"), "claude-haiku-5-5")
        XCTAssertEqual(ClaudeMode.api.chip, "API")
        XCTAssertEqual(ClaudeMode.plan.chip, "Plan")
    }

    func testPricesMatchTheLaptop() {
        let u = ClaudeUsage(inputTokens: 1_000_000, outputTokens: 100_000, cacheCreationInputTokens: 0, cacheReadInputTokens: 1_000_000)
        XCTAssertEqual(ClaudePrices.cost(model: "claude-sonnet-5-5", usage: u), 2 + 1 + 0.1, accuracy: 1e-9)
        XCTAssertEqual(ClaudePrices.cost(model: "claude-haiku-5-5", usage: ClaudeUsage(inputTokens: 1_000_000)), 0.1, accuracy: 1e-9)
        // an unknown model is counted at Opus prices; a dated id falls back to its family
        XCTAssertEqual(ClaudePrices.cost(model: "claude-new-thing", usage: ClaudeUsage(outputTokens: 1_000_000)), 20, accuracy: 1e-9)
        XCTAssertEqual(ClaudePrices.cost(model: "claude-sonnet-5-5-20261101", usage: ClaudeUsage(outputTokens: 1_000_000)), 10, accuracy: 1e-9)
        XCTAssertEqual(ClaudePrices.cost(model: "claude-sonnet-5-5", usage: nil), 0)
    }

    func testSpendingByMonth() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let nov = cal.date(from: DateComponents(year: 2026, month: 11, day: 30, hour: 23))!
        let dec = cal.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 1))!
        var s = ClaudeSpend()
        XCTAssertEqual(ClaudeSpend.text(s.month(nov, calendar: cal)), "Nothing spent this month")
        s.add(usd: 0.0123, usage: ClaudeUsage(inputTokens: 10, outputTokens: 5, cacheReadInputTokens: 100), at: nov, calendar: cal)
        XCTAssertEqual(ClaudeSpend.text(s.month(nov, calendar: cal)), "$0.012 this month (1 reply)")
        XCTAssertEqual(s.month(nov, calendar: cal).input, 110)
        s.add(usd: 0.2, usage: nil, at: nov, calendar: cal)
        XCTAssertEqual(ClaudeSpend.text(s.month(nov, calendar: cal)), "$0.21 this month (2 replies)")
        s.add(usd: 0.01, usage: nil, at: dec, calendar: cal)
        XCTAssertEqual(s.month(dec, calendar: cal).calls, 1)
        XCTAssertEqual(s.months.keys.sorted(), ["2026-11", "2026-12"])
        // kept as JSON in Application Support
        let back = try! JSONDecoder().decode(ClaudeSpend.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testApiBody() throws {
        let r = ClaudeRequest(model: "sonnet", system: "You are a patient tutor.", messages: [
            .user("first"), .assistant("ok"),
            ClaudeMessage(role: "user", content: [.image(mediaType: "image/jpeg", base64: "AAAA"), .text("and this?")]),
        ], maxTokens: 900, effort: "low")
        let b = ClaudeWire.apiBody(r)
        XCTAssertEqual(b["model"]?.string, "claude-sonnet-5-5")
        XCTAssertEqual(b["max_tokens"]?.number, 900)
        XCTAssertEqual(b["stream"]?.bool, true)
        XCTAssertEqual(b["system"]?.array?.first?["cache_control"]?["type"]?.string, "ephemeral")
        XCTAssertEqual(b["output_config"]?["effort"]?.string, "low")
        XCTAssertEqual(b["fallbacks"]?.string, "default")
        let msgs = b["messages"]?.array ?? []
        XCTAssertEqual(msgs.map { $0["role"]?.string ?? "" }, ["user", "assistant", "user"])
        let last = msgs[2]["content"]?.array ?? []
        XCTAssertEqual(last[0]["source"]?["media_type"]?.string, "image/jpeg")
        XCTAssertEqual(last[1]["text"]?.string, "and this?")
        // no cache mark, no effort: neither is sent
        let b2 = ClaudeWire.apiBody(ClaudeRequest(model: "claude-haiku-5-5", system: "s", messages: [.user("x")], cacheSystem: false))
        XCTAssertNil(b2["system"]?.array?.first?["cache_control"])
        XCTAssertNil(b2["output_config"])
        // what is sent parses back
        XCTAssertEqual(try JSONValue.parse(b.text), b)
    }

    func testStreamedEvents() {
        XCTAssertEqual(ClaudeWire.event(#"{"type":"message_start","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":12,"cache_read_input_tokens":800,"output_tokens":1}}}"#),
                       .start(model: "claude-sonnet-5-5", usage: ClaudeUsage(inputTokens: 12, outputTokens: 1, cacheReadInputTokens: 800)))
        XCTAssertEqual(ClaudeWire.event(#"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hola"}}"#), .text("Hola"))
        XCTAssertEqual(ClaudeWire.event(#"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#), .other)
        guard case .delta(let stop, let usage) = ClaudeWire.event(#"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":42}}"#) else { return XCTFail() }
        XCTAssertEqual(stop, "end_turn")
        var u = ClaudeUsage(inputTokens: 12, outputTokens: 1); u.merge(usage)
        XCTAssertEqual(u, ClaudeUsage(inputTokens: 12, outputTokens: 42))
        XCTAssertEqual(ClaudeWire.event(#"{"type":"message_stop"}"#), .stop)
        XCTAssertEqual(ClaudeWire.event(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#), .error("Overloaded"))
        XCTAssertEqual(ClaudeWire.event("not json"), .other)
    }

    func testFriendlyErrors() {
        XCTAssertTrue(ClaudeWire.friendly(status: 401, body: "").contains("refused"))
        XCTAssertTrue(ClaudeWire.friendly(status: 400, body: #"{"error":{"message":"Your credit balance is too low"}}"#).contains("run out"))
        XCTAssertEqual(ClaudeWire.friendly(status: 400, body: #"{"error":{"message":"max_tokens: too big"}}"#), "max_tokens: too big")
        XCTAssertTrue(ClaudeWire.friendly(status: 529, body: "").contains("busy"))
    }

    func testRelay() throws {
        let b = ClaudeWire.relayBody(ClaudeRequest(model: "opus", system: "sys", messages: [.user("hi")], maxTokens: 100, effort: "low", sessionId: "s-1"))
        XCTAssertEqual(b["model"]?.string, "claude-opus-5-5")
        XCTAssertEqual(b["sessionId"]?.string, "s-1")
        XCTAssertEqual(b["maxTokens"]?.number, 100)
        XCTAssertEqual(ClaudeWire.relayEvent(#"{"type":"text","text":"Ho"}"#), .text("Ho"))
        XCTAssertEqual(ClaudeWire.relayEvent(#"{"type":"done","model":"claude-opus-5-5","sessionId":"s-2","by":"Zephyrus Duo 16","usage":{"input_tokens":3,"output_tokens":4}}"#),
                       .done(model: "claude-opus-5-5", sessionId: "s-2", usage: ClaudeUsage(inputTokens: 3, outputTokens: 4), by: "Zephyrus Duo 16"))
        XCTAssertEqual(ClaudeWire.relayEvent(#"{"type":"error","message":"Claude Code is not signed in"}"#), .error("Claude Code is not signed in"))
        XCTAssertEqual(ClaudeMessage(role: "user", content: [.image(mediaType: "image/png", base64: "x"), .text("a"), .text("b")]).text, "a\nb")
    }
}
