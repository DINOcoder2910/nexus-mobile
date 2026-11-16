import XCTest
@testable import NexusCore

/// Talking to the tutor, pausing and talking on keeps what was said before the pause (Nov 16: the recogniser starts its text over
/// after a pause, and the panel showed only the new part).
final class SpeechJoinTests: XCTestCase {
    func feed(_ results: [String], into j: inout SpeechJoin) { for r in results { j.update(r) } }

    func testKeepsWhatWasSaidBeforeAPause() {
        var j = SpeechJoin()
        feed(["What", "What is", "What is a mole"], into: &j)
        XCTAssertEqual(j.text, "What is a mole")
        // the pause: the recogniser's text starts over, with no other sign
        feed(["and", "and how do I", "and how do I use it"], into: &j)
        XCTAssertEqual(j.text, "What is a mole and how do I use it")
        feed(["so", "so is it the same as Avogadro"], into: &j)
        XCTAssertEqual(j.text, "What is a mole and how do I use it so is it the same as Avogadro")
    }

    func testRevisionsReplaceTheStretch() {
        var j = SpeechJoin()
        feed(["I", "Hi there", "Hi there how"], into: &j)
        XCTAssertEqual(j.text, "Hi there how", "a longer result is the same stretch")
        j = SpeechJoin()
        feed(["So what is it", "What is it"], into: &j)
        XCTAssertEqual(j.text, "What is it", "dropping a leading word keeps the stretch")
        j = SpeechJoin()
        feed(["what is a mole", "What is a mole?"], into: &j)
        XCTAssertEqual(j.text, "What is a mole?", "punctuation added is a revision")
        j.update("")
        XCTAssertEqual(j.text, "What is a mole?", "an empty result changes nothing")
    }

    func testTheRecognisersEndOfAStretch() {
        var j = SpeechJoin()
        j.update("What is a mole")
        j.update("What is a mole?", ended: true) // (a result with metadata: the stretch is over)
        j.update("What")                          // same first word: only the end mark tells
        j.update("What about water")
        XCTAssertEqual(j.text, "What is a mole? What about water")
        XCTAssertEqual(j.done, ["What is a mole?"])
        XCTAssertEqual(j.current, "What about water")
    }

    func testTimestamps() {
        var j = SpeechJoin()
        j.update("what is a mole", start: 0.4)
        j.update("what is a mold", start: 0.4)
        XCTAssertEqual(j.text, "what is a mold", "same start: a revision")
        j.update("what about water", start: 5.2)
        XCTAssertEqual(j.text, "what is a mold what about water", "a later start: a new stretch")
        j.update("what about the water", start: 5.2)
        XCTAssertEqual(j.text, "what is a mold what about the water")
        var k = SpeechJoin()
        k.update("what is a mole", start: 0)
        k.update("what is a mole and", start: 0)
        XCTAssertEqual(k.text, "what is a mole and", "a zero timestamp is unknown, not the start")
    }

    func testABigDropIsANewStretch() {
        var j = SpeechJoin()
        j.update("the first law says energy is conserved")
        j.update("the")
        XCTAssertEqual(j.text, "the first law says energy is conserved the", "kept twice rather than lost")
        j.update("the second law")
        XCTAssertEqual(j.text, "the first law says energy is conserved the second law")
    }

    func testCloseForARestart() {
        var j = SpeechJoin()
        j.update("first part")
        j.close() // (the recogniser stopped on its own and listening goes on with a new one)
        j.close()
        j.update("first")
        XCTAssertEqual(j.text, "first part first")
        XCTAssertEqual(SpeechJoin().text, "")
    }
}
