import XCTest
@testable import NexusCore

final class MarksTests: XCTestCase {
    func testCommentFollowsItsWords() {
        let words = "The cat sat on the mat."
        let at = Anchor.make(words, from: 4, to: 7)
        let m = BoardMarks.make(id: "m1", kind: "bubble", on: "b1", at: at, x: 10, y: 20, text: "Which cat?", by: "iPad")
        XCTAssertEqual(BoardMarks.anchor(m)?.q, "cat")
        XCTAssertEqual(BoardMarks.marks(on: "b1", [m]).map(\.id), ["m1"])
        let edited = "Yesterday the cat sat on the mat."
        let next = BoardMarks.refreshed([m], block: "b1", words: edited)[0]
        XCTAssertEqual(BoardMarks.anchor(next)?.i, 14)
        XCTAssertEqual(Anchor.find(edited, BoardMarks.anchor(next)!)?.from, 14)
        // the words gone: the mark stays as it was (a ghost)
        XCTAssertEqual(BoardMarks.refreshed([next], block: "b1", words: "Nothing here")[0], next)
    }

    func testRepliesAndHandwriting() {
        let s = BoardStroke(id: "s1", ink: "com.apple.ink.pen", color: "#000000FF", points: [[110, 220, 1, 0, 1.571, 0, 2, 2, 1]])
        var m = BoardMarks.make(id: "m1", kind: "bubble", on: nil, at: nil, x: 100, y: 200, strokes: [s], by: "iPad")
        XCTAssertEqual(BoardMarks.strokes(m, absolute: false)[0].points[0][0], 10)
        XCTAssertEqual(BoardMarks.strokes(m)[0].points[0][1], 220)
        m = BoardMarks.reply(m, text: "Done", by: "laptop")
        XCTAssertEqual(BoardMarks.replies(m).map(\.text), ["Done"])
    }

    func testAttachedInkFollowsTheWords() {
        var c = BoardContent()
        c.items = [BoardItem(id: "b1", type: "text", x: 0, y: 0)]
        c.strokes = [BoardStroke(id: "s1", ink: "com.apple.ink.pen", color: "#000000FF", points: [[50, 60, 1, 0, 1.571, 0, 2, 2, 1]]),
                     BoardStroke(id: "s2", ink: "com.apple.ink.pen", color: "#000000FF", points: [[500, 600, 1, 0, 1.571, 0, 2, 2, 1]])]
        c = BoardMarks.attach(c, strokes: ["s1"], mark: "m1", on: "b1", words: "hello world", from: 6, to: 11, x: 40, y: 50, by: "iPad")
        XCTAssertEqual(BoardMarks.strokeMark(c.strokes[0]), "m1")
        XCTAssertNil(BoardMarks.strokeMark(c.strokes[1]))
        XCTAssertTrue(c.strokes[0].json.text.contains("\"mark\":\"m1\""))
        c = BoardMarks.follow(c, mark: "m1", to: (x: 40, y: 80))
        XCTAssertEqual(c.strokes[0].points[0][1], 90)
        XCTAssertEqual(c.strokes[1].points[0][1], 600)
        XCTAssertEqual(c.items.last?.y, 80)
        XCTAssertTrue(c.strokes[0].json.text.contains("\"mark\":\"m1\""))
        c = BoardMarks.detach(c, mark: "m1")
        XCTAssertNil(BoardMarks.strokeMark(c.strokes[0]))
        XCTAssertFalse(c.items.contains { $0.id == "m1" })
    }
}
