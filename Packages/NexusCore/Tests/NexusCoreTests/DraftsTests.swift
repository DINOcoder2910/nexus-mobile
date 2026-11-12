import XCTest
@testable import NexusCore

final class DraftsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_793_000_000)

    func board(_ words: String = "one\ntwo\nthree") -> BoardContent {
        var c = BoardContent()
        c.items = [BoardItem(id: "b1", type: "text", x: 0, y: 0)]
        c.texts["b1"] = words
        c.textsOnDisk["b1"] = words
        return c
    }

    func testNewDraftKeepsTheOldOneUnlockedWithASnapshot() throws {
        let made = try XCTUnwrap(BlockDrafts.make(board(), id: "b1", now: now))
        let c = made.content
        let it = c.items[0]
        XCTAssertEqual(made.draft, "d2")
        XCTAssertEqual(BlockDrafts.list(it).map(\.id), ["d1", "d2"])
        XCTAssertEqual(BlockDrafts.list(it).map(\.name), ["Draft 1", "Draft 2"])
        XCTAssertEqual(BlockDrafts.current(it), "d2")
        XCTAssertFalse(BlockDrafts.isLocked(it, "d1"))
        XCTAssertEqual(BlockDrafts.list(it)[1].from, "d1")
        // text/b1.md holds the current draft; the old one has its own file; the snapshot keeps it as it was
        XCTAssertEqual(c.texts["b1"], "one\ntwo\nthree")
        XCTAssertEqual(c.texts["b1~d1"], "one\ntwo\nthree")
        XCTAssertEqual(c.texts["b1~d2@snap"], "one\ntwo\nthree")
        XCTAssertEqual(Set(BlockDrafts.fileKeys(it)), ["b1~d1", "b1~d2@snap"])
        XCTAssertEqual(BlockDrafts.key(it, "d1"), "b1~d1")
        XCTAssertEqual(BlockDrafts.key(it, "d2"), "b1")
        XCTAssertEqual(BlockDrafts.key(it, nil), "b1")
    }

    func testLockOnNewDraftAndUnlock() throws {
        let c = try XCTUnwrap(BlockDrafts.make(board(), id: "b1", name: "Corrected", lockOld: true, now: now)).content
        XCTAssertTrue(BlockDrafts.isLocked(c.items[0], "d1"))
        XCTAssertFalse(BlockDrafts.isLocked(c.items[0], nil))
        XCTAssertEqual(BlockDrafts.list(c.items[0])[1].name, "Corrected")
        let open = BlockDrafts.setLocked(c, id: "b1", draft: "d1", false)
        XCTAssertFalse(BlockDrafts.isLocked(open.items[0], "d1"))
    }

    func testMakeCurrentSwapsTheFiles() throws {
        var c = try XCTUnwrap(BlockDrafts.make(board(), id: "b1", now: now)).content
        c.texts["b1"] = "one\nTWO\nthree"
        c = BlockDrafts.makeCurrent(c, id: "b1", draft: "d1")
        XCTAssertEqual(BlockDrafts.current(c.items[0]), "d1")
        XCTAssertEqual(c.texts["b1"], "one\ntwo\nthree")
        XCTAssertEqual(c.texts["b1~d2"], "one\nTWO\nthree")
        XCTAssertNil(c.texts["b1~d1"])
        XCTAssertEqual(BlockDrafts.words(c, "b1", "d2"), "one\nTWO\nthree")
    }

    func testOldDraftEditsAreSeenAndBroughtOver() throws {
        var c = try XCTUnwrap(BlockDrafts.make(board(), id: "b1", now: now)).content
        XCTAssertEqual(BlockDrafts.changedSince(c, id: "b1", draft: "d2"), [])
        // the new draft changes its last line; a mistake is fixed in the old one's first line
        c.texts["b1"] = "one\ntwo\nTHREE"
        c.texts["b1~d1"] = "One\ntwo\nthree"
        XCTAssertEqual(BlockDrafts.changedSince(c, id: "b1", draft: "d2"), [.removed("one"), .added("One")])
        let r = try XCTUnwrap(BlockDrafts.bringOver(c, id: "b1", into: "d2"))
        XCTAssertEqual(r.content.texts["b1"], "One\ntwo\nTHREE")
        XCTAssertEqual(r.merged, 1)
        XCTAssertEqual(BlockDrafts.changedSince(r.content, id: "b1", draft: "d2"), [])
        // both changed the same line: this draft's line stays, the old draft's version is a suggestion on it (as the laptop does)
        c.texts["b1"] = "One!\ntwo\nTHREE"
        let clash = try XCTUnwrap(BlockDrafts.bringOver(c, id: "b1", into: "d2"))
        XCTAssertEqual(clash.content.texts["b1"], "One{--!--}\ntwo\nTHREE")
        XCTAssertEqual(clash.clashes, 1)
    }

    func testDeleteAndRename() throws {
        var c = try XCTUnwrap(BlockDrafts.make(board(), id: "b1", now: now)).content
        c = BlockDrafts.rename(c, id: "b1", draft: "d1", to: "  First ")
        XCTAssertEqual(BlockDrafts.list(c.items[0])[0].name, "First")
        c.texts["b1"] = "new words"
        c = BlockDrafts.delete(c, id: "b1", draft: "d2")
        XCTAssertEqual(BlockDrafts.list(c.items[0]).map(\.id), ["d1"])
        XCTAssertEqual(BlockDrafts.current(c.items[0]), "d1")
        XCTAssertEqual(c.texts["b1"], "one\ntwo\nthree")
        XCTAssertNil(c.texts["b1~d2"])
        XCTAssertNil(c.texts["b1~d2@snap"])
        // the last draft stays
        XCTAssertEqual(BlockDrafts.delete(c, id: "b1", draft: "d1").items, c.items)
    }

    func testSavingKeepsDraftFilesAndRemovesStaleOnes() throws {
        var c = try XCTUnwrap(BlockDrafts.make(board(), id: "b1", now: now)).content
        var ch = BoardFiles.changes(c)
        XCTAssertEqual(Set(ch.texts.keys), ["b1~d1", "b1~d2@snap"])
        XCTAssertEqual(ch.removedTexts, [])
        for (k, v) in ch.texts { c.textsOnDisk[k] = v }
        // making d1 current: its own file goes, d2 gets one
        c = BlockDrafts.makeCurrent(c, id: "b1", draft: "d1")
        ch = BoardFiles.changes(c)
        XCTAssertEqual(Set(ch.texts.keys), ["b1~d2"])
        XCTAssertEqual(ch.removedTexts, ["b1~d1"])
    }

    func testCompare() {
        XCTAssertEqual(BlockDrafts.compare("a\nb\nc", "a\nx\nc"), [.same("a"), .removed("b"), .added("x"), .same("c")])
        XCTAssertEqual(BlockDrafts.compare("a", "a\nb"), [.same("a"), .added("b")])
    }
}
