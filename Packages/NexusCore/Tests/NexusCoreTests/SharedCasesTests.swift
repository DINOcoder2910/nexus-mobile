import XCTest
@testable import NexusCore

/// The shared cases: folders and files with the answers both apps must give, for the rules the laptop and NexusCore each implement.
/// `Fixtures/shared` is a copy of nexus `dev/shared` (its README says what each rule is; copy it again with
/// `sh tools/shared-cases/copy.sh <nexus checkout>`). The laptop runs the same files in nexus `dev/unit-shared.mjs`, so a rule can't
/// change on one side without failing on the other.
final class SharedCasesTests: XCTestCase {
    var shared: URL!

    override func setUpWithError() throws {
        shared = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("shared")
    }

    func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], url.path)
    }
    func dirs(_ url: URL) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map(\.lastPathComponent).sorted()
    }
    func days(_ any: Any?) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (k, v) in any as? [String: Any] ?? [:] { out[k] = v as? [String] ?? [] }
        return out
    }

    /// Every rule folder is one this file runs (a new rule needs a runner here and in the laptop's dev/unit-shared.mjs).
    func testTheRules() {
        XCTAssertEqual(dirs(shared), ["day-order-file", "order"])
    }

    /// order/<case>: Today's plan and each day's planned tasks, from the case's data folder, in the one order (DayOrder.swift).
    func testOrder() throws {
        let cases = dirs(shared.appendingPathComponent("order"))
        XCTAssertFalse(cases.isEmpty)
        for name in cases {
            let dir = shared.appendingPathComponent("order").appendingPathComponent(name)
            let c = try json(dir.appendingPathComponent("case.json"))
            let today = try XCTUnwrap(c["today"] as? String)
            let dayStart = c["dayStart"] as? Int ?? 0
            let expect = c["expect"] as? [String: Any] ?? [:]
            let s = DataFolder.load(dir.appendingPathComponent("data"))
            XCTAssertEqual(s.problems.map(\.message), [], "order/\(name): the folder reads cleanly")
            let p = Planning(s, today: today, dayStart: dayStart)
            XCTAssertEqual(p.todayPlan.map(\.id), expect["today"] as? [String] ?? [], "order/\(name): Today")
            for (day, ids) in days(expect["days"]) {
                XCTAssertEqual(p.planned(on: day).map(\.id), ids, "order/\(name): \(day)")
            }
        }
    }

    /// day-order-file/cases.json: reading and writing nexus-day-order.yaml, and a time read for the order.
    func testDayOrderFile() throws {
        let c = try json(shared.appendingPathComponent("day-order-file").appendingPathComponent("cases.json"))
        for x in c["read"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.parse(x["text"] as? String), days(x["expect"]), "read: \(x["about"] ?? "")")
        }
        for x in c["write"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.text(days(x["days"]), today: x["today"] as? String ?? ""), x["expect"] as? String, "write: \(x["about"] ?? "")")
        }
        for x in c["set"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.with(days(x["days"]), day: x["day"] as? String ?? "", keys: x["keys"] as? [String] ?? []), days(x["expect"]), "set: \(x["about"] ?? "")")
        }
        for x in c["time"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.minutes(x["time"] as? String, dayStart: x["dayStart"] as? Int ?? 0), x["expect"] as? Int, "time: \(x["time"] ?? "nil")")
        }
        let back = DayOrder.parse(DayOrder.text(["2026-11-20": ["b", "a"]], today: "2026-11-20"))
        XCTAssertEqual(back, ["2026-11-20": ["b", "a"]], "what is written reads back the same")
    }
}
