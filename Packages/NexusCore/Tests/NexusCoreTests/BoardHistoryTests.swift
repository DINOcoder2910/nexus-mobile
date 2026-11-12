import XCTest
@testable import NexusCore

/// The version history log must be what the laptop's renderer/src/board/history.js writes and reads (the expected lines below are
/// that file's output for the same edits).
final class BoardHistoryTests: XCTestCase {
    let now = 1_794_391_200_000.0 // 2026-11-11T10:00:00.000Z

    let s1 = BoardStroke(id: "s1", ink: "com.apple.ink.pen", color: "#000000FF",
                         points: [[1, 2, 1, 0, 1.571, 0, 2, 2, 1], [3, 4, 1, 0, 1.571, 0.5, 2, 2, 1]])
    var t1: BoardItem { BoardItem(id: "t1", type: "text", x: 10, y: 20) }

    func testNames() {
        XCTAssertEqual(BoardHistory.deviceSlug("Zephyrus Duo 16"), "zephyrus-duo-16")
        XCTAssertEqual(BoardHistory.deviceSlug("Murtaza’s iPad Pro"), "murtaza-s-ipad-pro")
        XCTAssertEqual(BoardHistory.deviceSlug("Café"), "cafe")
        XCTAssertEqual(BoardHistory.deviceSlug("  "), "device")
        XCTAssertEqual(BoardHistory.logFile(device: "iPad", ms: now), "history/ipad-2026-11.jsonl")
        let info = BoardHistory.logInfo("history/zephyrus-duo-16-2026-10.jsonl.gz")
        XCTAssertEqual(info?.device, "zephyrus-duo-16")
        XCTAssertEqual(info?.month, "2026-10")
        XCTAssertEqual(info?.gz, true)
        XCTAssertNil(BoardHistory.logInfo("history/notes.txt"))
        XCTAssertNil(BoardHistory.logInfo("tiles/0_0.json"))
    }

    func testTimes() {
        XCTAssertEqual(BoardHistory.iso(now), "2026-11-11T10:00:00.000Z")
        XCTAssertEqual(BoardHistory.iso(now + 1234), "2026-11-11T10:00:01.234Z")
        XCTAssertEqual(BoardHistory.time("2026-11-11T10:00:01.234Z"), now + 1234)
        XCTAssertEqual(BoardHistory.time("2026-11-11T10:00:00Z"), now)
        XCTAssertNil(BoardHistory.time("yesterday"))
    }

    func testTextDiff() {
        XCTAssertNil(BoardHistory.textDiff("same", "same"))
        let a = BoardHistory.textDiff("Hello", "Helo")!
        XCTAssertEqual([a.at, a.del], [3, 1]); XCTAssertEqual(a.ins, "")
        let b = BoardHistory.textDiff("", "Hi")!
        XCTAssertEqual([b.at, b.del], [0, 0]); XCTAssertEqual(b.ins, "Hi")
        // an emoji is one change (UTF-16, as the laptop counts)
        let c = BoardHistory.textDiff("a😀b", "a😃b")!
        XCTAssertEqual([c.at, c.del], [1, 2]); XCTAssertEqual(c.ins, "😃")
        XCTAssertEqual(BoardHistory.applyKey("a😀b", at: 1, del: 2, ins: "😃"), "a😃b")
        XCTAssertEqual(BoardHistory.applyKey("Helo", at: 3, del: 0, ins: "l"), "Hello")
        XCTAssertEqual(BoardHistory.applyKey("ab", at: 99, del: 5, ins: "c"), "abc")
    }

    func testRecorderLinesAsTheLaptopWritesThem() {
        let r = HistoryRecorder(now: now)
        r.saved(from: BoardState(), to: BoardState(strokes: [s1], items: [t1], texts: ["t1": "Hi"]), now: now)
        r.typing(id: "t1", prev: "Hi", md: "Hi!", now: now + 1000)
        XCTAssertEqual(r.take(),
            "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"open\"}\n"
            + "{\"t\":\"2026-11-11T09:59:59.500Z\",\"op\":\"stroke\",\"s\":{\"id\":\"s1\",\"ink\":\"com.apple.ink.pen\",\"color\":\"#000000FF\",\"points\":[[1,2,1,0,1.571,0,2,2,1],[3,4,1,0,1.571,0.5,2,2,1]]}}\n"
            + "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"item\",\"it\":{\"id\":\"t1\",\"type\":\"text\",\"x\":10,\"y\":20}}\n"
            + "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"type\",\"id\":\"t1\",\"k\":[[0,0,0,\"Hi\"],[1000,2,0,\"!\"]]}\n")
        XCTAssertFalse(r.pending)
        // the save after the keystroke: nothing new to say about the words
        r.saved(from: BoardState(strokes: [s1], items: [t1], texts: ["t1": "Hi"]), to: BoardState(strokes: [s1], items: [t1], texts: ["t1": "Hi!"]), now: now + 2000)
        XCTAssertEqual(r.take(), "")
        r.saved(from: BoardState(strokes: [s1], items: [t1], texts: ["t1": "Hi!"]), to: BoardState(strokes: [], items: [t1], texts: ["t1": "Hi!"]), now: now + 9000)
        XCTAssertEqual(r.take(), "{\"t\":\"2026-11-11T10:00:09.000Z\",\"op\":\"erase\",\"ids\":[\"s1\"]}\n")
    }

    func testErasingWhatNoLogHas() {
        let r = HistoryRecorder(known: ["t1"], now: now)
        r.saved(from: BoardState(strokes: [s1], items: [t1], texts: [:]), to: BoardState(), now: now)
        let lines = r.take().split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"erase\",\"ids\":[\"s1\",\"t1\"],\"was\":[{\"id\":\"s1\",\"ink\":\"com.apple.ink.pen\",\"color\":\"#000000FF\",\"points\":[[1,2,1,0,1.571,0,2,2,1],[3,4,1,0,1.571,0.5,2,2,1]]}]}")
    }

    func testStrokeTimes() {
        let r = HistoryRecorder(now: now)
        var s2 = s1; s2.id = "s2"
        var s3 = s1; s3.id = "s3"
        // s2 drawn 2 s ago (PencilKit's date); s3 dated before the last save: a stroke moved, written now
        r.saved(from: BoardState(), to: BoardState(strokes: [s2, s3], items: [], texts: [:]), now: now + 5000, born: ["s2": now + 3000, "s3": now - 60000])
        let lines = BoardHistory.parseLog(r.take())
        XCTAssertEqual(lines.map(\.op), ["open", "stroke", "stroke"])
        XCTAssertEqual(lines[1].t, now + 3000)
        XCTAssertEqual(lines[2].t, now + 5000)
    }

    func testDrafts() {
        let r = HistoryRecorder(now: now)
        r.typing(id: "t1", prev: "Old", md: "Old!", now: now, d: "2")
        XCTAssertEqual(r.take(),
            "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"open\"}\n"
            + "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"text\",\"id\":\"t1\",\"d\":\"2\",\"md\":\"Old\"}\n"
            + "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"type\",\"id\":\"t1\",\"d\":\"2\",\"k\":[[0,3,0,\"!\"]]}\n")
    }

    func testParseSkipsWhatItCannotRead() {
        let text = """
        {"t":"2026-11-11T10:00:00.000Z","op":"open"}
        not json
        {"t":"2026-11-11T10:00:01.000Z","op":"fly"}
        {"op":"stroke","s":{"id":"x","points":[[1,2]]}}
        {"t":"2026-11-11T10:00:02.000Z","op":"stroke","s":{"id":"x","points":[]}}
        {"t":"2026-11-11T10:00:03.000Z","op":"item","it":{"id":"i1","type":"shape","x":0,"y":0,"w":10,"h":10,"shape":"rect"}}

        """
        let lines = BoardHistory.parseLog(text, device: "ipad")
        XCTAssertEqual(lines.map(\.op), ["open", "item"])
        XCTAssertEqual(lines[1].device, "ipad")
        XCTAssertEqual(BoardHistory.knownIds(lines), ["i1"])
    }

    /// The laptop and the iPad each wrote a part; the player sees one board.
    func testTimelineAndReplay() {
        let laptop = """
        {"t":"2026-11-11T10:00:00.000Z","op":"open"}
        {"t":"2026-11-11T10:00:01.000Z","op":"item","it":{"id":"t1","type":"text","x":10,"y":20}}
        {"t":"2026-11-11T10:00:01.000Z","op":"type","id":"t1","k":[[0,0,0,"H"],[200,1,0,"i"]]}
        {"t":"2026-11-11T10:05:00.000Z","op":"erase","ids":["s1"]}
        """
        let ipad = """
        {"t":"2026-11-11T10:00:02.000Z","op":"stroke","s":{"id":"s1","ink":"com.apple.ink.pen","color":"#000000FF","points":[[1,2,1,0,1.571,0,2,2,1],[3,4,1,0,1.571,0.5,2,2,1]]}}
        """
        let lines = BoardHistory.parseLog(laptop, device: "zephyrus-duo-16") + BoardHistory.parseLog(ipad, device: "ipad")
        let tl = HistoryTimeline(lines, now: BoardState(strokes: [], items: [t1], texts: ["t1": "Hi"]))
        XCTAssertNil(tl.rough)
        XCTAssertEqual(tl.start, now)
        XCTAssertEqual(tl.end, now + 300_000)
        let R = HistoryReplayer(tl)
        R.seek(now + 1000)
        XCTAssertEqual(R.items.map(\.id), ["t1"])
        XCTAssertEqual(R.texts["t1"], "H")
        R.seek(now + 1200)
        XCTAssertEqual(R.texts["t1"], "Hi")
        R.seek(now + 2250)
        XCTAssertEqual(R.strokes.map(\.id), ["s1"])
        XCTAssertEqual(R.writing.count, 1)
        XCTAssertEqual(R.writing.first?.upTo ?? 0, 0.25, accuracy: 1e-9)
        XCTAssertEqual(HistoryReplayer.partStroke(s1, 0.25).points.count, 1)
        R.seek(now + 3000)
        XCTAssertEqual(R.writing.count, 0)
        R.seek(now + 400_000)
        XCTAssertEqual(R.strokes.count, 0)
        // back again
        R.seek(now + 500)
        XCTAssertEqual(R.items.count, 0)
        XCTAssertEqual(tl.sessions().count, 1)
    }

    func testRoughStartForWhatCameBeforeTheLog() {
        let line = "{\"t\":\"2026-11-11T10:00:00.000Z\",\"op\":\"erase\",\"ids\":[\"old\"],\"was\":[{\"id\":\"old\",\"ink\":\"com.apple.ink.pen\",\"color\":\"#000000FF\",\"points\":[[0,0,1,0,1.571,0,2,2,1]]}]}"
        let pdf = BoardItem(id: "p1", type: "pdf", x: 0, y: 0, fields: [("src", .string("files/a.pdf"))])
        let tl = HistoryTimeline(BoardHistory.parseLog(line), now: BoardState(strokes: [s1], items: [t1, pdf], texts: ["t1": "Hi"]))
        XCTAssertEqual(tl.rough, now)
        // the printout first, then the text, then the ink
        var kinds: [String] = []
        for e in tl.ev {
            switch e.kind {
            case .item(let it): kinds.append("i:" + it.id)
            case .stroke(let s): kinds.append("s:" + s.id)
            case .words(let k, _): kinds.append("w:" + k)
            case .erase: kinds.append("e")
            default: kinds.append("?")
            }
        }
        XCTAssertEqual(kinds, ["i:p1", "i:t1", "w:t1~", "s:old", "s:s1", "e"])
        let R = HistoryReplayer(tl).seek(now - 1)
        XCTAssertEqual(Set(R.strokes.map(\.id)), ["old", "s1"])
        XCTAssertEqual(R.texts["t1"], "Hi")
    }

    func testPlayClockShortensPauses() {
        let text = """
        {"t":"2026-11-11T10:00:00.000Z","op":"open"}
        {"t":"2026-11-11T11:00:00.000Z","op":"open"}
        """
        let tl = HistoryTimeline(BoardHistory.parseLog(text), now: BoardState())
        let c = PlayClock(tl)
        XCTAssertEqual(c.length, 600)
        XCTAssertEqual(c.toReal(600), now + 3_600_000)
        XCTAssertEqual(c.toPlay(now + 3_600_000), 600)
        XCTAssertEqual(PlayClock(tl, skip: false).length, 3_600_000)
        XCTAssertEqual(tl.sessions().count, 2)
    }

    func testCopyOut() {
        var moved = s1; moved.points[0][0] = 50
        let old = BoardState(strokes: [s1, BoardStroke(id: "gone", ink: "com.apple.ink.pen", color: "#000000FF", points: [[0, 0]])],
                             items: [t1], texts: ["t1": "Old words"])
        let cur = BoardState(strokes: [moved], items: [t1], texts: ["t1": "Old words"])
        var n = 0
        let out = BoardHistory.copyOut(old: old, current: cur) { taken in n += 1; var id = "c\(n)"; while taken.contains(id) { n += 1; id = "c\(n)" }; return id }
        XCTAssertEqual(out.strokes.map(\.id), ["c1", "gone"])
        XCTAssertEqual(out.items.count, 0) // unchanged since
    }

    func testThumbFrame() {
        let f = BoardThumb.frame((x0: 100, y0: 100, x1: 300, y1: 200))
        XCTAssertEqual(f.w, 320); XCTAssertEqual(f.h, 240)
        XCTAssertEqual(f.x, 100 - 24 - (320 - 248) / 2)
        XCTAssertEqual(f.y, 76)
        let e = BoardThumb.frame(nil)
        XCTAssertEqual(e.w, 800); XCTAssertEqual(e.h, 600)
    }
}
