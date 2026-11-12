import XCTest
@testable import NexusCore

/// The iPad's Critic and BlockDrafts.merge against what the laptop's own critic.js and drafts.js give (CriticGolden.swift).
final class CriticTests: XCTestCase {
    lazy var golden: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(criticGolden.utf8)) as? [String: Any]) ?? [:]

    func cases(_ k: String) -> [[String: Any]] { golden[k] as? [[String: Any]] ?? [] }

    func testGoldenLoads() {
        XCTAssertGreaterThan(cases("diff").count, 100)
        XCTAssertGreaterThan(cases("edit").count, 300)
    }

    func testParse() {
        var bad = 0
        for c in cases("parse") {
            let md = c["md"] as! String
            let want = (c["marks"] as! [[Any]]).map { "\($0[0])|\($0[1])|\($0[2])|\($0[3])|\($0[4])" }
            let got = Critic.parse(md).map { "\($0.kind.rawValue)|\($0.from)|\($0.to)|\($0.old)|\($0.new)" }
            if got != want { bad += 1; if bad < 4 { XCTFail("parse \(md.debugDescription): \(got) != \(want)") } }
        }
        XCTAssertEqual(bad, 0)
    }

    func testDiff() {
        var bad = 0
        for c in cases("diff") {
            let a = c["a"] as! String, b = c["b"] as! String, d = c["d"] as! String
            let got = Critic.diff(a, b)
            if got != d { bad += 1; if bad < 4 { XCTFail("diff \(a.debugDescription) -> \(b.debugDescription): \(got.debugDescription) != \(d.debugDescription)") } }
            XCTAssertEqual(Critic.text(got, old: true), a)
            XCTAssertEqual(Critic.text(got), b)
        }
        XCTAssertEqual(bad, 0)
    }

    func testTypingInReviewMode() {
        var bad = 0
        for c in cases("edit") {
            let md = c["md"] as! String, from = c["from"] as! Int, to = c["to"] as! Int, ins = c["ins"] as! String, fwd = c["fwd"] as! Bool
            let r = Critic.edit(md, from: from, to: to, insert: ins, forward: fwd)
            if r.md != c["out"] as! String || r.cursor != c["cursor"] as! Int {
                bad += 1
                if bad < 4 { XCTFail("edit \(md.debugDescription) [\(from), \(to)) \(ins.debugDescription) fwd \(fwd): \(r.md.debugDescription) @\(r.cursor) != \((c["out"] as! String).debugDescription) @\(c["cursor"] as! Int)") }
            }
        }
        XCTAssertEqual(bad, 0)
    }

    func testNewOffsets() {
        for c in cases("offsets") { XCTAssertEqual(Critic.newOffsets(c["md"] as! String), c["map"] as! [Int]) }
    }

    func testApplyAndReject() {
        var bad = 0
        for c in cases("resolve") {
            let md = c["md"] as! String, i = c["i"] as! Int, acc = c["acc"] as! Bool
            let got = acc ? Critic.accept(md, i) : Critic.reject(md, i)
            if got != c["out"] as! String { bad += 1; if bad < 4 { XCTFail("resolve \(md.debugDescription) \(i) \(acc): \(got.debugDescription) != \((c["out"] as! String).debugDescription)") } }
        }
        XCTAssertEqual(bad, 0)
    }

    func testBringThemOver() {
        var bad = 0
        for c in cases("merge") {
            let r = BlockDrafts.merge(snap: c["snap"] as! String, old: c["old"] as! String, new: c["new"] as! String)
            if r.text != c["text"] as! String || r.merged != c["merged"] as! Int || r.clashes != c["clashes"] as! Int {
                bad += 1
                if bad < 4 { XCTFail("merge \(c): \(r)") }
            }
        }
        XCTAssertEqual(bad, 0)
    }

    func testReviewUsesTheLaptopsRules() {
        // Enter in Review mode is a suggested line break; markup never spans a line
        let e = Review.type("abc", range: NSRange(location: 3, length: 0), with: "\n")
        XCTAssertEqual(e.text, "abc\n{++++}")
        XCTAssertEqual(e.selection.location, 4)
        XCTAssertEqual(Review.accept("a\n{--b--}\nc", Review.suggestions("a\n{--b--}\nc")[0]).text, "a\nc")
    }
}
