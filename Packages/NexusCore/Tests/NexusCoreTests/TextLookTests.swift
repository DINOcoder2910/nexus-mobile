import XCTest
@testable import NexusCore

/// A typed block's look and its checkboxes, ported from the laptop's dev/unit-board.mjs ("a typed block's look and its checkboxes").
final class TextLookTests: XCTestCase {
    func item(_ fields: [(String, JSONValue)] = []) -> BoardItem {
        BoardItem(id: "a", type: "text", x: 0, y: 0, fields: fields)
    }

    func testConstants() {
        XCTAssertEqual(TextLook.sizes.map { $0.px }, [13, 16, 22, 32])
        XCTAssertEqual(TextLook.sizes.map { $0.label }, ["Small", "Normal", "Large", "Huge"])
        XCTAssertEqual(TextLook.colors.first?.hex, "#1B1B1B")
        XCTAssertEqual(TextLook.colors.count, 7)
        XCTAssertEqual(TextLook.fills.first?.hex, "")
        XCTAssertEqual(TextLook.fills.first?.label, "None")
        XCTAssertEqual(TextLook.fills.count, 6)
        XCTAssertEqual(TextLook.defaultSize, 16)
    }

    func testAPlainBlockHasNoLookOfItsOwn() {
        let l = TextLook.look(item())
        XCTAssertNil(l.size)
        XCTAssertNil(l.color)
        XCTAssertNil(l.fill)
    }

    func testALookIsReadAndChecked() {
        let l = TextLook.look(item([("size", .number(22)), ("color", .string("#1F5FD1")), ("fill", .string("yellow"))]))
        XCTAssertEqual(l.size, 22)
        XCTAssertEqual(l.color, "#1F5FD1")
        XCTAssertNil(l.fill)
        XCTAssertEqual(TextLook.look(item([("size", .string("22"))])).size, 22)
        XCTAssertEqual(TextLook.look(item([("fill", .string("#fff4b8"))])).fill, "#fff4b8")
    }

    func testASillySizeIsIgnored() {
        XCTAssertNil(TextLook.look(item([("size", .number(4000))])).size)
        XCTAssertNil(TextLook.look(item([("size", .string("big"))])).size)
        XCTAssertNil(TextLook.look(item([("size", .number(4))])).size)
    }

    func testALookIsSetInUpperCase() {
        XCTAssertEqual(TextLook.with(item(), "color", "#1f5fd1"), item([("color", .string("#1F5FD1"))]))
        XCTAssertEqual(TextLook.with(item(), "size", "22"), item([("size", .number(22))]))
    }

    func testTheDefaultSizeOrNoneTakesItOff() {
        XCTAssertEqual(TextLook.with(item([("size", .number(22))]), "size", "16"), item())
        XCTAssertEqual(TextLook.with(item([("fill", .string("#FFF4B8"))]), "fill", nil), item())
        XCTAssertEqual(TextLook.with(item([("fill", .string("#FFF4B8"))]), "fill", ""), item())
        XCTAssertEqual(TextLook.with(item(), "fill", nil), item())
    }

    func testAClickTicksATask() {
        XCTAssertEqual(TextLook.toggleTask("# Do\n- [ ] one\n- [x] two", line: 1), "# Do\n- [x] one\n- [x] two")
    }

    func testAndUnticksOne() {
        XCTAssertEqual(TextLook.toggleTask("- [X] two", line: 0), "- [ ] two")
        XCTAssertEqual(TextLook.toggleTask("a\n- [x] two\nb", line: 1), "a\n- [ ] two\nb")
    }

    func testANumberedQuotedOrIndentedTaskToo() {
        XCTAssertEqual(TextLook.toggleTask("1. [ ] a", line: 0), "1. [x] a")
        XCTAssertEqual(TextLook.toggleTask("> - [ ] b", line: 0), "> - [x] b")
        XCTAssertEqual(TextLook.toggleTask("  * [ ] c", line: 0), "  * [x] c")
    }

    func testALineThatIsNotATaskIsLeft() {
        XCTAssertNil(TextLook.toggleTask("- plain", line: 0))
        XCTAssertNil(TextLook.toggleTask("one", line: 5))
        XCTAssertNil(TextLook.toggleTask("- [ ] one", line: -1))
        XCTAssertNil(TextLook.toggleTask("- [ ]", line: 0))
    }
}
