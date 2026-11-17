import XCTest
@testable import NexusCore

/// Time tracking's files (nexus docs/data-format.md "Time tracking"), the same cases as the laptop's dev/unit-timelog.mjs: stamps, the
/// file (header, a line per session, append, change, remove, a newer format), running timers, a day split at its start, groups, words.
final class TimeLogTests: XCTestCase {
    let ist = TimeZone(secondsFromGMT: 19800)!

    func testStamps() {
        let d = TimeLog.date("2026-11-16T14:05:12+05:30")!
        XCTAssertEqual(d.timeIntervalSince1970, 1_794_818_112)
        XCTAssertEqual(TimeLog.stamp(d, zone: ist), "2026-11-16T14:05:12+05:30")
        XCTAssertEqual(TimeLog.date("2026-11-16T08:35:12Z"), d)
        XCTAssertNil(TimeLog.date("yesterday"))
        let local = TimeLog.date("2026-11-16 10:00")!
        let c = Days.calendar.dateComponents([.hour, .minute], from: local)
        XCTAssertEqual([c.hour, c.minute], [10, 0])
        XCTAssertEqual(TimeLog.device(ofPath: "time/ipad/2026-11.yaml"), "ipad")
        XCTAssertNil(TimeLog.device(ofPath: "time/ipad/notes.yaml"))
        XCTAssertNil(TimeLog.device(ofPath: "x/time/ipad/2026-11.yaml"))
        let round = TimeLog.date(TimeLog.stamp(local))
        XCTAssertEqual(round, local)
    }

    func testTheFile() throws {
        let e1 = TimeLog.Entry(task: "prab", title: "Physics HW: sheet \"B\"", start: "2026-11-16T14:05:12+05:30", end: "2026-11-16T14:50:03+05:30")
        let e2 = TimeLog.Entry(task: "1234", title: "Read", start: "2026-11-16T15:00:00+05:30")
        var t = TimeLog.append(nil, device: "ipad", e1)
        XCTAssertTrue(t.hasPrefix("# Time tracked on the iPad"))
        XCTAssertEqual(t.components(separatedBy: "\n").first { $0.hasPrefix("  - ") },
                       #"  - {task: "prab", title: "Physics HW: sheet \"B\"", start: "2026-11-16T14:05:12+05:30", end: "2026-11-16T14:50:03+05:30"}"#)
        t = TimeLog.append(t, device: "ipad", e2)
        let f = try TimeLog.parse(t)
        XCTAssertEqual(f.device, "ipad")
        XCTAssertEqual(f.entries.map(\.task), ["prab", "1234"])
        XCTAssertEqual(f.entries.map(\.title), ["Physics HW: sheet \"B\"", "Read"])
        XCTAssertEqual(f.entries.map(\.end), ["2026-11-16T14:50:03+05:30", nil])
        XCTAssertEqual(TimeLog.running(f.entries).map(\.task), ["1234"])
        var stopped = e2; stopped.end = "2026-11-16T15:30:00+05:30"
        let t2 = try XCTUnwrap(TimeLog.replace(t, was: e2, with: stopped))
        let a = t.components(separatedBy: "\n"), b = t2.components(separatedBy: "\n")
        XCTAssertEqual(zip(a, b).filter { $0 != $1 }.count, 1)
        XCTAssertTrue(TimeLog.running(try TimeLog.parse(t2).entries).isEmpty)
        let t3 = try XCTUnwrap(TimeLog.replace(t2, was: e1, with: nil))
        XCTAssertEqual(try TimeLog.parse(t3).entries.map(\.task), ["1234"])
        XCTAssertNil(TimeLog.replace(t3, was: .init(task: "1234", start: "2020-01-01T00:00:00Z"), with: nil))
        // the laptop's file, read here (it is written the same way)
        let laptop = "format: nexus-time/1\ndevice: laptop\nentries: []\n"
        XCTAssertEqual(try TimeLog.parse(TimeLog.append(laptop, device: "laptop", e1)).entries.count, 1)
        XCTAssertThrowsError(try TimeLog.parse("format: nexus-time/2\nentries: []\n"))
        XCTAssertThrowsError(try TimeLog.parse("entries: [\n"))
        XCTAssertEqual(try TimeLog.parse("entries:\n  - {task: \"a\"}\n  - {task: \"b\", start: \"2026-11-16T10:00:00Z\", end: \"2026-11-16T10:30:00Z\"}\n").entries.map(\.task), ["b"])
    }

    func testSameSecondAndHandWritten() throws {
        let same = "2026-11-16T15:00:00+05:30"
        var t = TimeLog.append(nil, device: "ipad", .init(task: "a", start: same, end: "2026-11-16T15:00:30+05:30"))
        t = TimeLog.append(t, device: "ipad", .init(task: "b", start: same))
        t = try XCTUnwrap(TimeLog.replace(t, was: .init(task: "b", start: same), with: .init(task: "b", start: same, end: "2026-11-16T15:10:00+05:30")))
        XCTAssertEqual(try TimeLog.parse(t).entries.map(\.end), ["2026-11-16T15:00:30+05:30", "2026-11-16T15:10:00+05:30"])
        let hand = "entries:\n  - {start: 2026-11-16 10:00, task: ab12}\n"
        XCTAssertEqual(TimeLog.replace(hand, was: .init(task: "ab12", start: "2026-11-16 10:00"), with: .init(task: "ab12", start: "2026-11-16 10:00", end: "2026-11-16 10:30")),
                       "entries:\n  - {task: \"ab12\", start: \"2026-11-16 10:00\", end: \"2026-11-16 10:30\"}\n")
        let ids = try TimeLog.parse("entries:\n  - {task: 1234, start: 2026-11-16 10:00, end: 2026-11-16 10:45}\n").entries
        XCTAssertEqual(ids.map(\.task), ["1234"])
        XCTAssertEqual(ids.first?.seconds(), 45 * 60)
    }

    func testDaysAndSums() {
        func L(_ h: Int, _ m: Int = 0, day: Int = 16) -> String {
            TimeLog.stamp(Days.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m))!)
        }
        let all = [
            TimeLog.Entry(task: "a", start: L(9), end: L(10, 30)),
            TimeLog.Entry(task: "b", start: L(23), end: L(5, 0, day: 17)),
            TimeLog.Entry(task: "a", start: L(14)),
        ]
        let now = Days.calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 14, minute: 20))!
        XCTAssertEqual(all[2].seconds(now: now), 20 * 60)
        let two = Array(all.prefix(2))
        XCTAssertEqual(TimeLog.daySeconds(two, "2026-11-16", startHour: 4), (90 + 300) * 60)
        XCTAssertEqual(TimeLog.daySeconds(two, "2026-11-17", startHour: 4), 60 * 60)
        XCTAssertEqual(TimeLog.daySeconds(two, "2026-11-16", startHour: 0), 150 * 60)
        XCTAssertEqual(TimeLog.sessions(on: "2026-11-17", all, startHour: 4, now: now).map(\.task), ["b"])
        let g = TimeLog.grouped(two, days: ["2026-11-16", "2026-11-17"], startHour: 4) { $0.task }
        XCTAssertEqual(g.map(\.key), ["b", "a"])
        XCTAssertEqual(g.map(\.seconds), [360 * 60, 90 * 60])
    }

    func testWords() {
        XCTAssertEqual([65, 23 * 60 + 10, 3725].map { TimeLog.clock(TimeInterval($0)) }, ["1:05", "23:10", "1:02:05"])
        XCTAssertEqual([0, 30, 45 * 60, 80 * 60, 120 * 60].map { TimeLog.spent(TimeInterval($0)) }, ["", "under a minute", "45m", "1h 20m", "2h"])
        XCTAssertEqual(TimeLog.deviceWords("iphone"), "the iPhone")
        XCTAssertEqual(TimeLog.file(device: "ipad", start: TimeLog.date("2026-11-16 10:00")!), "time/ipad/2026-11.yaml")
    }
}
