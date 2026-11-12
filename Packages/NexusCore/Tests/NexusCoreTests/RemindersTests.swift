import XCTest
@testable import NexusCore

/// The notices scheduled ahead: the laptop's calm rules (one deadline digest a day, key dates early, a notice before a planned time).
final class RemindersTests: XCTestCase {
    var dir: URL!
    let today = "2030-01-07"

    override func setUpWithError() throws {
        let src = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("data-vault")
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-remind-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: src, to: dir)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    @discardableResult
    private func add(_ title: String, due: String? = nil, plan: [PlanEntry] = [], key: Bool = false) throws -> String {
        let s = DataFolder.load(dir)
        return try TaskEditor(root: dir).add(title: title, to: "inbox.yaml", due: due, plan: plan, key: key, in: s, today: today).1
    }

    func testOneDigestADayWithTodayTomorrowAndKeyDates() throws {
        try add("Physics lab report", due: today)
        try add("Spanish oral", due: Days.add(today, 1), key: true)
        try add("EE draft", due: Days.add(today, 3), key: true)
        let r = Reminders.plan(DataFolder.load(dir), today: today, nowMinute: 7 * 60, settings: ReminderSettings())
        let first = try XCTUnwrap(r.first)
        XCTAssertEqual(first.id, "dl:\(today)")
        XCTAssertEqual(first.minute, 8 * 60 + 30)
        XCTAssertEqual(first.title, "3 deadlines: 1 today, 1 tomorrow, 1 key date ahead")
        XCTAssertEqual(first.body, "Today: Physics lab report\nTomorrow: ★ Spanish oral\nKey dates: EE draft in 3 days")
        XCTAssertEqual(r.filter { $0.kind == .deadline }.map(\.day), [today, Days.add(today, 1), Days.add(today, 2), Days.add(today, 3)])
    }

    func testTodaysDigestIsLeftOutOnceItsTimeHasPassed() throws {
        try add("Physics lab report", due: today)
        let r = Reminders.plan(DataFolder.load(dir), today: today, nowMinute: 9 * 60, settings: ReminderSettings())
        XCTAssertTrue(r.isEmpty)
    }

    func testPlannedTimesAreGroupedAndComeBeforeTheStart() throws {
        try add("Read chapter 4", plan: [PlanEntry(day: today, time: "14:00")])
        try add("Past papers", plan: [PlanEntry(day: today, time: "14:00")])
        try add("Gym", plan: [PlanEntry(day: Days.add(today, 1), time: "07:00")])
        try add("No time", plan: [PlanEntry(day: today)])
        let r = Reminders.plan(DataFolder.load(dir), today: today, nowMinute: 10 * 60, settings: ReminderSettings())
        XCTAssertEqual(r.map(\.id), ["pl:\(today) 14:00", "pl:\(Days.add(today, 1)) 07:00"])
        XCTAssertEqual(r[0].minute, 13 * 60 + 50)
        XCTAssertEqual(r[0].title, "2 things start at 14:00")
        XCTAssertEqual(r[0].taskIds.count, 2)
        XCTAssertEqual(r[1].title, "Gym")
        XCTAssertEqual(r[1].body, "Starts at 07:00 (in 10 min)")
    }

    func testDoneTasksEventsWithAlarmsAndSwitchedOffKindsAreLeftOut() throws {
        let id = try add("Hand in form", due: Days.add(today, 1))
        var s = DataFolder.load(dir)
        _ = try TaskEditor(root: dir).tick(try XCTUnwrap(s.tasks[id]), in: s, today: today)
        s = DataFolder.load(dir)
        let events = [ReminderEvent(id: "a", title: "Chem class", day: today, minute: 11 * 60, hasAlarm: false),
                      ReminderEvent(id: "b", title: "Dentist", day: today, minute: 15 * 60, hasAlarm: true)]
        var settings = ReminderSettings()
        let r = Reminders.plan(s, today: today, nowMinute: 8 * 60, events: events, settings: settings)
        XCTAssertEqual(r.map(\.id), ["ev:a:\(today)"])
        settings.events = false
        XCTAssertTrue(Reminders.plan(s, today: today, nowMinute: 8 * 60, events: events, settings: settings).isEmpty)
        settings.on = false
        XCTAssertTrue(Reminders.plan(s, today: today, nowMinute: 8 * 60, events: events, settings: settings).isEmpty)
    }

    func testShortTitles() {
        XCTAssertEqual(Reminders.short("a  b\nc"), "a b c")
        XCTAssertEqual(Reminders.short("one two three four", 12), "one two…")
        XCTAssertEqual(Reminders.list(["a", "b", "c", "d", "e", "f"]), "a, b, c, d and 2 more")
    }
}
