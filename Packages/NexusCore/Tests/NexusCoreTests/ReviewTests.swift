import XCTest
@testable import NexusCore

final class ReviewTests: XCTestCase {
    func r(_ l: Int, _ n: Int = 0) -> NSRange { NSRange(location: l, length: n) }

    func testFindsSuggestions() {
        let s = Review.suggestions("a {++b++} c {--d--} e {~~f~>g~~}")
        XCTAssertEqual(s.map(\.new), ["b", nil, "g"])
        XCTAssertEqual(s.map(\.old), [nil, "d", "f"])
        XCTAssertEqual(Review.all("a {++b++} c {--d--} e {~~f~>g~~}", accept: true), "a b c  e g")
        XCTAssertEqual(Review.all("a {++b++} c {--d--} e {~~f~>g~~}", accept: false), "a  c d e f")
    }

    func testTypingSuggests() {
        // new words
        var e = Review.type("Hello world", range: r(5), with: "!")
        XCTAssertEqual(e.text, "Hello{++!++} world")
        XCTAssertEqual(e.selection, r(9))
        // more typing stays inside the suggestion
        e = Review.type(e.text, range: e.selection, with: "!")
        XCTAssertEqual(e.text, "Hello{++!!++} world")
        // backspacing it all takes the suggestion away
        e = Review.type(e.text, range: r(9, 1), with: "")
        e = Review.type(e.text, range: r(8, 1), with: "")
        XCTAssertEqual(e.text, "Hello world")
    }

    func testDeletingKeepsTheWordsAsASuggestion() {
        var e = Review.type("abc", range: r(2, 1), with: "")
        XCTAssertEqual(e.text, "ab{--c--}")
        XCTAssertEqual(e.selection, r(2))
        e = Review.type(e.text, range: r(1, 1), with: "")
        XCTAssertEqual(e.text, "a{--bc--}")
    }

    func testTypingOverWords() {
        let e = Review.type("the cat", range: r(4, 3), with: "dog")
        XCTAssertEqual(e.text, "the {~~cat~>dog~~}")
        XCTAssertEqual(Review.accept(e.text, Review.suggestions(e.text)[0]).text, "the dog")
        XCTAssertEqual(Review.reject(e.text, Review.suggestions(e.text)[0]).text, "the cat")
    }
}
