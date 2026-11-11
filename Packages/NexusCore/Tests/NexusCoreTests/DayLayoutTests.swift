import XCTest
@testable import NexusCore

/// The calendar's time grid: overlapping things side by side, events cut at midnight, times as the task files write them.
final class DayLayoutTests: XCTestCase {
    typealias S = DayLayout.Span

    private func at(_ day: String, _ h: Int, _ m: Int = 0) -> Date {
        Days.date(day)!.addingTimeInterval(Double(h * 3600 + m * 60))
    }

    func testSeparateSpansTakeTheWholeWidth() {
        let p = DayLayout.place([S(id: "a", start: 540, end: 600), S(id: "b", start: 600, end: 660)])
        XCTAssertEqual(p.map(\.columns), [1, 1])
        XCTAssertEqual(p.map(\.column), [0, 0])
    }

    func testOverlappingSpansGoSideBySide() {
        let p = DayLayout.place([S(id: "b", start: 570, end: 630), S(id: "a", start: 540, end: 600)])
        XCTAssertEqual(p.map(\.id), ["a", "b"])
        XCTAssertEqual(p.map(\.column), [0, 1])
        XCTAssertEqual(p.map(\.columns), [2, 2])
    }

    func testAChainSharesOneWidthAndReusesAFreeColumn() {
        // a overlaps b, b overlaps c, a ends before c starts: c goes back into a's column
        let p = DayLayout.place([S(id: "a", start: 540, end: 600), S(id: "b", start: 570, end: 690), S(id: "c", start: 630, end: 700)])
        XCTAssertEqual(p.first { $0.id == "c" }?.column, 0)
        XCTAssertEqual(Set(p.map(\.columns)), [2])
    }

    func testLongerFirstAtTheSameStart() {
        let p = DayLayout.place([S(id: "short", start: 540, end: 570), S(id: "long", start: 540, end: 660)])
        XCTAssertEqual(p.first?.id, "long")
        XCTAssertEqual(p.first?.column, 0)
    }

    func testAShortSpanCountsAsTwentyMinutes() {
        let p = DayLayout.place([S(id: "a", start: 540, end: 545), S(id: "b", start: 550, end: 600)])
        XCTAssertEqual(p.map(\.columns), [2, 2])
    }

    func testAnEventPastMidnightShowsOnBothDays() {
        let s = at("2026-11-12", 23), e = at("2026-11-13", 1)
        XCTAssertEqual(DayLayout.clip(start: s, end: e, day: "2026-11-12").map { [$0.start, $0.end] }, [1380, 1440])
        XCTAssertEqual(DayLayout.clip(start: s, end: e, day: "2026-11-13").map { [$0.start, $0.end] }, [0, 60])
        XCTAssertNil(DayLayout.clip(start: s, end: e, day: "2026-11-14"))
        XCTAssertEqual(DayLayout.days(start: s, end: e), ["2026-11-12", "2026-11-13"])
    }

    func testAnEndAtMidnightStaysOnItsDay() {
        let s = at("2026-11-12", 22), e = at("2026-11-13", 0)
        XCTAssertNil(DayLayout.clip(start: s, end: e, day: "2026-11-13"))
        XCTAssertEqual(DayLayout.days(start: s, end: e), ["2026-11-12"])
        // an all-day event the way calendars store it: midnight to midnight
        XCTAssertEqual(DayLayout.days(start: at("2026-11-12", 0), end: at("2026-11-14", 0)), ["2026-11-12", "2026-11-13"])
    }

    func testAZeroLengthEventIsKept() {
        let s = at("2026-11-12", 9)
        XCTAssertEqual(DayLayout.clip(start: s, end: s, day: "2026-11-12").map { [$0.start, $0.end] }, [540, 540])
    }

    func testTimes() {
        XCTAssertEqual(DayLayout.minutes("09:30"), 570)
        XCTAssertEqual(DayLayout.minutes("9:05"), 545)
        XCTAssertNil(DayLayout.minutes("25:00"))
        XCTAssertNil(DayLayout.minutes("soon"))
        XCTAssertEqual(DayLayout.hhmm(570), "09:30")
        XCTAssertEqual(DayLayout.hhmm(5), "00:05")
    }

    func testMonths() {
        XCTAssertEqual(DayLayout.monthStart("2026-11-12"), "2026-11-01")
        XCTAssertEqual(DayLayout.addMonths("2026-11-12", 1), "2026-12-01")
        XCTAssertEqual(DayLayout.addMonths("2026-01-31", -1), "2025-12-01")
        let g = DayLayout.monthGrid("2026-11-12")
        XCTAssertEqual(g.count, 42)
        XCTAssertEqual(g.first, "2026-10-26") // the Monday before Sunday 1 November 2026
        XCTAssertTrue(g.contains("2026-11-30"))
    }
}
