import XCTest
@testable import NexusCore

/// A task's Activity (TaskActivity.swift, the laptop's activity.js in JavaScriptCore): the hub's history in the laptop's words.
final class TaskActivityTests: XCTestCase {
    let v1 = "tasks:\n  - id: t1\n    title: Redox worksheet\n    added: 2026-11-20\n"
    let v2 = "tasks:\n  - id: t1\n    title: Redox worksheet Q1-5\n    added: 2026-11-20\n    due: 2026-11-25\n"

    func testTheHubsHistoryInTheLaptopsWords() throws {
        #if canImport(JavaScriptCore)
        let h = try JSONValue.parse("""
        {"repo":true,"versions":[{"hash":"b","at":"2026-11-21T10:00:00+05:30","author":"Claude","path":"chem/tasks.yaml","text":\(JSONValue.string(v2).text)},
        {"hash":"a","at":"2026-11-20T10:00:00+05:30","author":"Murtaza","path":"chem/tasks.yaml","text":\(JSONValue.string(v1).text)}],"trail":[]}
        """)
        let rows = TaskActivity.shared.rows(id: "t1", path: "chem/tasks.yaml", added: "2026-11-20", done: false, doneOn: nil, history: h,
                                            current: v2, names: ["chem/tasks.yaml": "Chemistry"], today: "2026-11-23")
        XCTAssertEqual(rows.map(\.text), ["Renamed from “Redox worksheet”", "Deadline set to Wed 25 Nov", "Added"], TaskActivity.shared.lastError ?? "")
        XCTAssertEqual(rows.first?.who, "Claude")
        XCTAssertEqual(rows.last?.date, "2026-11-20")
        #endif
    }

    func testWithoutHistoryTheFilesFactsShow() {
        let rows = TaskActivity.shared.rows(id: "t1", path: "chem/tasks.yaml", added: "2026-11-20", done: true, doneOn: "2026-11-22", history: nil,
                                            current: nil, names: [:], today: "2026-11-23")
        XCTAssertEqual(rows.map(\.text), ["Ticked off", "Added"])
        XCTAssertEqual(rows.map(\.date), ["2026-11-22", "2026-11-20"])
    }
}
