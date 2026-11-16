import XCTest
@testable import NexusCore

/// The usage files every device sees (nexus docs/data-format.md "Usage"): this device's spending file, the others added up in the
/// laptop's words (renderer/src/usage.js), and the laptop's plan reading as bars.
final class UsageShareTests: XCTestCase {
    func testSpendFileKeepsThreeMonthsAndSkipsSameNumbers() {
        var s = ClaudeSpend()
        for (k, v) in [("2026-08", 1.0), ("2026-09", 2.0), ("2026-10", 3.0), ("2026-11", 0.123456)] { var m = ClaudeSpend.Month(); m.usd = v; m.calls = 2; s.months[k] = m }
        let t = UsageShare.spendText(device: "iPad", spend: s, at: "A")
        let js = try! JSONSerialization.jsonObject(with: Data(t.utf8)) as! [String: Any]
        XCTAssertEqual(js["device"] as? String, "ipad")
        XCTAssertEqual(((js["months"] as? [String: Any]) ?? [:]).keys.sorted(), ["2026-09", "2026-10", "2026-11"])
        XCTAssertEqual(((js["months"] as! [String: Any])["2026-11"] as! [String: Any])["usd"] as? Double, 0.123)
        XCTAssertTrue(UsageShare.sameNumbers(t, UsageShare.spendText(device: "iPad", spend: s, at: "B")))
        s.months["2026-11"]!.calls = 3
        XCTAssertFalse(UsageShare.sameNumbers(t, UsageShare.spendText(device: "iPad", spend: s, at: "B")))
        XCTAssertEqual(UsageShare.fileName(device: "iPhone"), "iphone.json")
    }

    func testOthersAddUpInTheLaptopsWords() {
        // what the laptop's usage-share.js writes (JSON.stringify, one-space indent)
        let laptop = "{\n \"device\": \"laptop\",\n \"months\": {\n  \"2026-11\": {\n   \"usd\": 1.5,\n   \"calls\": 4\n  }\n },\n \"updated\": \"T\"\n}\n"
        let files: [(name: String, text: String)] = [("laptop.json", laptop), ("ipad.json", "{\"device\":\"ipad\",\"months\":{\"2026-11\":{\"usd\":9,\"calls\":1}}}"),
                                                     ("iphone.json", "{\"device\":\"iphone\",\"months\":{\"2026-10\":{\"usd\":1,\"calls\":1}}}"), ("plan.json", "{}"), ("broken.json", "{nope")]
        let o = UsageShare.others(files, month: "2026-11", device: "iPad")
        XCTAssertEqual(o, [UsageShare.Other(device: "laptop", usd: 1.5, calls: 4)])
        var own = ClaudeSpend.Month(); own.usd = 3.5; own.calls = 20
        let bar = UsageShare.apiBar(own: own, credit: 50, others: o, device: "iPad")
        XCTAssertEqual(bar.main, "$5.00 of $50.00 this month (24 replies)")
        XCTAssertEqual(bar.sub, "10% used, $45.00 left")
        XCTAssertEqual(bar.parts, "iPad $3.50 · Laptop $1.50")
        XCTAssertEqual(bar.fraction ?? -1, 0.1, accuracy: 1e-9)
        let none = UsageShare.apiBar(own: ClaudeSpend.Month(), credit: 0, others: [], device: "iPad")
        XCTAssertNil(none.fraction); XCTAssertEqual(none.main, "$0.00 this month"); XCTAssertEqual(none.parts, "")
    }

    func testPlanFileAsBars() {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        let now = f.date(from: "2026-11-13T10:00:00Z")!
        let text = """
        {"at": "2026-11-13T09:58:00.000Z", "subscription": "max", "from": "laptop", "limits": {
          "five_hour": {"utilization": 25, "resets_at": "2026-11-13T12:30:00Z"}, "seven_day": {"utilization": 97.4, "resets_at": null},
          "seven_day_opus": null, "seven_day_sonnet": {"utilization": null}, "model_scoped": [{"display_name": "Fable", "utilization": 18}, {"display_name": "Odd"}],
          "extra_usage": {"is_enabled": true, "monthly_limit": 5000, "used_credits": 1234, "utilization": 24.68, "currency": "USD"}}}
        """
        let p = UsageShare.plan(text, now: now)
        XCTAssertEqual(p?.plan, "Max")
        XCTAssertEqual(p?.rows.map(\.label), ["Current session (5 hours)", "This week, all models", "This week, Fable", "Extra usage this month"])
        XCTAssertEqual(p?.rows.first?.reset, "resets in 2 h 30 min")
        XCTAssertEqual(p?.rows.last?.reset, "$12.34 of $50.00 spent")
        XCTAssertNotNil(p?.at)
        XCTAssertNil(UsageShare.plan("nope"))
        XCTAssertNil(UsageShare.plan("{\"limits\": {}}"))
        XCTAssertEqual(UsageShare.resetText("2026-11-13T10:40:00Z", now: now), "resets in 40 min")
        XCTAssertEqual(UsageShare.resetText("2026-11-13T09:00:00Z", now: now), "resetting now")
    }
}
