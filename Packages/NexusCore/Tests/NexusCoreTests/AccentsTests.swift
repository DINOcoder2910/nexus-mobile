import XCTest
@testable import NexusCore

final class AccentsTests: XCTestCase {
    func testDeadKeys() {
        XCTAssertEqual(Accents.apply("acute", "e"), "é")
        XCTAssertEqual(Accents.apply("tilde", "N"), "Ñ")
        XCTAssertEqual(Accents.apply("umlaut", "u"), "ü")
        XCTAssertEqual(Accents.apply("acute", "x"), "x")
    }

    func testPracticeTimer() {
        let start = Date(timeIntervalSince1970: 1_793_000_000)
        let it = BoardItem(id: "b", type: "text", x: 0, y: 0).with("practice", Practice.field(minutes: 30, now: start))
        XCTAssertTrue(Practice.isOn(it))
        XCTAssertEqual(Practice.left(it, now: start.addingTimeInterval(60)), 29 * 60)
        XCTAssertEqual(Practice.left(it, now: start.addingTimeInterval(4000)), 0)
        XCTAssertEqual(Practice.clock(125), "2:05")
        XCTAssertNil(Practice.left(BoardItem(id: "c", type: "text", x: 0, y: 0)))
    }
}
