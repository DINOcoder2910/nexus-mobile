import XCTest
@testable import NexusCore

/// Today as the new laptop app works it out (TodayPlan.swift): the same folder and answers as nexus
/// `desktop/backend/src/plan.rs`'s `today_has_every_part`, so both apps' Today agree.
final class TodayPlanTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-today-\(UUID().uuidString)")
        func write(_ rel: String, _ text: String) throws {
            let u = dir.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("nexus.yaml", "nexus: 2\n")
        try write("classes/group.yaml", "label: Classes\norder: 1\nkind: class\n")
        try write("classes/chem/workstream.yaml", "id: chem\nname: Chemistry HL\ncolor: green\n")
        try write("classes/chem/tasks.yaml", """
        tasks:
          - {id: a1, title: Redox set, plan: ['2026-11-20 10:30'], est: 1h30m}
          - {id: a2, title: Lab write-up, plan: ['2026-11-20'], est: 1h}
          - {id: a3, title: Read ahead, plan: ['2026-11-20'], est: 30m}
          - {id: a4, title: Due today, due: 2026-11-20}
          - {id: a5, title: Was yesterday, plan: ['2026-11-19'], est: 20m}
          - {id: a6, title: Late one, due: 2026-11-18}
          - {id: a7, title: Test, due: 2026-11-26, key: true}
          - {id: a8, title: Tomorrow's, plan: ['2026-11-21 19:30'], est: 45m}
          - {id: a9, title: Ticked today, plan: ['2026-11-20'], done: 2026-11-20}

        """)
        try write("inbox.yaml", "tasks: []\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Chemistry 9 to 10 every weekday, as the laptop's test's events.yaml.
    func events(_ day: String) -> [TodayPlan.Span] { Days.weekday(day) >= 1 && Days.weekday(day) <= 5 ? [.init(9 * 60, 10 * 60)] : [] }

    func day() -> TodayPlan.Day {
        TodayPlan.day(Planning(DataFolder.load(dir), today: "2026-11-20"), now: 10 * 60, events: events)
    }

    func testTodayHasEveryPart() {
        let v = day()
        // a timed one first, then a deadline before none, then file order
        XCTAssertEqual(v.list.map(\.title), ["Redox set", "Due today", "Lab write-up", "Read ahead"])
        XCTAssertEqual(v.next?.title, "Redox set")
        XCTAssertEqual(v.keyDates.first?.task.title, "Test")
        XCTAssertEqual(v.keyDates.first?.days, 6)
        XCTAssertEqual(v.slipped.map(\.task.title), ["Was yesterday", "Late one"])
        XCTAssertEqual(v.slipped.map(\.late), [false, true])
        XCTAssertEqual(v.slipped.first?.was, "2026-11-19")
        // suggestions: the first untimed tasks with an estimate, into the free gaps after now (Redox runs 10:30 to 12:00)
        XCTAssertEqual(v.suggestions.map(\.title), ["Lab write-up", "Read ahead"])
        XCTAssertEqual(v.suggestions.first?.span, .init(12 * 60, 13 * 60))
        XCTAssertEqual(v.suggestions.last?.span, .init(10 * 60, 10 * 60 + 30)) // first fit: the half hour before Redox
        XCTAssertEqual(v.tomorrow.list.map(\.title), ["Tomorrow's"])
        XCTAssertEqual(v.tomorrow.planned, 45)
        XCTAssertEqual(v.done.map(\.title), ["Ticked today"])
        XCTAssertEqual(v.estLeft, 90 + 60 + 30)
        // free from 10: 10:00-10:30 and 12:00-22:00
        XCTAssertEqual(v.freeLeft, 30 + 600)
        // the whole day's gaps from 8: 8-9, 10-10:30, 12-22
        XCTAssertEqual(v.gaps, [.init(480, 540), .init(600, 630), .init(720, 1320)])
    }

    func testFreeGaps() {
        let busy: [TodayPlan.Span] = [.init(9 * 60, 10 * 60), .init(9 * 60 + 30, 11 * 60), .init(13 * 60, 13 * 60 + 10)]
        XCTAssertEqual(TodayPlan.gaps(busy, from: 8 * 60, to: 14 * 60), [.init(480, 540), .init(660, 780), .init(790, 840)])
        // under 15 minutes is no gap
        XCTAssertEqual(TodayPlan.gaps([.init(490, 900)], from: 480, to: 910), [])
    }

    func testNextUpIsTheFirstInYourListWhenNothingIsTimed() {
        let v = TodayPlan.day(Planning(DataFolder.load(dir), today: "2026-11-20"), now: 13 * 60, events: events)
        // Redox (10:30 to 12:00) is over by 1 pm
        XCTAssertEqual(v.next?.title, "Due today")
    }

    func testEstimates() {
        var t = NexusTask(id: "x", title: "x", file: "inbox.yaml", workstream: nil)
        t.est = "1h 30m"; XCTAssertEqual(TodayPlan.minutes(t), 90)
        t.est = "45m"; XCTAssertEqual(TodayPlan.minutes(t), 45)
        t.est = "1.5h"; XCTAssertEqual(TodayPlan.minutes(t), 90)
        t.est = nil; XCTAssertEqual(TodayPlan.minutes(t), 0)
    }

    /// The Planner's week from today, as the laptop's `week_view`: planned days, loads against free time, deadlines, lanes, the bank.
    func testWeek() {
        let p = Planning(DataFolder.load(dir), today: "2026-11-20")
        let w = WeekPlan.week(p, start: "2026-11-20", now: 10 * 60, events: events)
        XCTAssertEqual(w.days.map(\.date).first, "2026-11-20")
        XCTAssertEqual(w.days.last?.date, "2026-11-26")
        XCTAssertEqual(w.days[0].planned.map(\.title), ["Redox set", "Lab write-up", "Read ahead"])
        XCTAssertEqual(w.days[0].load, 180)
        XCTAssertEqual(w.days[0].free, 30 + 600)
        // Saturday: no class, Tomorrow's from 19:30 to 20:15
        XCTAssertEqual(w.days[1].load, 45)
        XCTAssertEqual(w.days[1].free, (1170 - 480) + (1320 - 1215))
        XCTAssertEqual(w.days[0].deadlines.map(\.title), ["Due today"])
        XCTAssertEqual(w.days[6].deadlines.map(\.title), ["Test"])
        XCTAssertEqual(w.lanes.count, 1)
        XCTAssertEqual(w.lanes.first?.workstream, "chem")
        XCTAssertEqual(w.lanes.first?.count, 4)
        XCTAssertEqual(w.bank.map(\.title), ["Due today", "Was yesterday", "Late one", "Test"])
        XCTAssertEqual(w.slipped, Set(["a5", "a6"]))
        XCTAssertEqual(w.load, 225)
        XCTAssertTrue(w.overDays.isEmpty)
        // a week that starts before today: the past days hold no plan
        let back = WeekPlan.week(p, start: "2026-11-18", now: 10 * 60, events: events)
        XCTAssertTrue(back.days[1].past)
        XCTAssertTrue(back.days[1].planned.isEmpty)
    }

}
