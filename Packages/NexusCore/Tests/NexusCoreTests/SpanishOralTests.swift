import XCTest
@testable import NexusCore

/// Spanish › Oral on the iPhone and iPad (SpanishOral.swift). The golden half checks the files are read as the laptop's own
/// spanishoral.js and spanishoralhear.js read them (SpanishOralGolden.swift, tools/spanish-golden/oral.mjs); the rest is what only the
/// phone does: a recording's oral.yaml waiting for the laptop, a listening test take, the list's titles and marks.
final class SpanishOralTests: XCTestCase {
    lazy var g: [String: Any] = (try? JSONSerialization.jsonObject(with: Data(spanishOralGolden.utf8)) as? [String: Any]) ?? [:]
    private func s(_ a: Any?) -> String { a as? String ?? "" }
    private func d(_ a: Any?) -> Double? { (a as? NSNumber)?.doubleValue }
    private func list(_ a: Any?) -> [Any] { a as? [Any] ?? [] }
    private func obj(_ a: Any?) -> [String: Any] { a as? [String: Any] ?? [:] }

    func testThemesAsTheLaptop() {
        for case let row as [Any] in list(g["toTheme"]) { XCTAssertEqual(SpanishOral.toTheme(s(row[0])), s(row[1]), "toTheme \(row[0])") }
        for case let row as [Any] in list(g["themeName"]) { XCTAssertEqual(SpanishOral.themeName(s(row[0])), s(row[1])) }
        for case let row as [Any] in list(g["labelFor"]) {
            let i = obj(row[0])
            XCTAssertEqual(SpanishOral.labelFor(.init(file: "x", theme: s(i["theme"]), topic: s(i["topic"]), label: s(i["label"]), about: "")), s(row[1]))
        }
        for case let row as [Any] in list(g["oralId"]) { XCTAssertEqual(SpanishOral.oralId(s(row[0])), s(row[1])) }
        for case let row as [Any] in list(g["settings"]) {
            let st = SpanishOral.parseSettings(s(row[0]))
            XCTAssertEqual(st.teacher, s(obj(row[1])["teacher"]), "settings \(row[0])")
            XCTAssertEqual(st.tutor, s(obj(row[1])["tutor"]), "settings \(row[0])")
        }
    }

    func testOralsReadAsTheLaptop() {
        let rows = list(g["orals"])
        XCTAssertEqual(rows.count, 6)
        for (i, item) in rows.enumerated() {
            guard let row = item as? [Any] else { XCTFail("row \(i)"); continue }
            let text = s(row[0])
            let o = SpanishOral.parseOral(text, id: "fallback-\(i)")
            guard let want = row[1] as? [String: Any] else { XCTAssertNil(o, "oral \(i) should not parse"); continue }
            guard let o else { XCTFail("oral \(i) didn't parse"); continue }
            XCTAssertEqual(o.id, s(want["id"]), "id \(i)")
            XCTAssertEqual(o.kind, s(want["kind"]), "kind \(i)")
            XCTAssertEqual(o.by, s(want["by"]), "by \(i)")
            XCTAssertEqual(o.title, s(want["title"]))
            XCTAssertEqual(o.recording, s(want["recording"]))
            XCTAssertEqual(o.started, s(want["started"]))
            XCTAssertEqual(o.image, s(want["image"]))
            XCTAssertEqual(o.theme, s(want["theme"]), "theme \(i)")
            XCTAssertEqual(o.otherTheme, s(want["otherTheme"]))
            XCTAssertEqual(o.notes, s(want["notes"]))
            XCTAssertEqual(o.summary, s(want["summary"]))
            if let wg = want["given"] as? [String: Any] {
                XCTAssertNotNil(o.given, "given \(i)")
                for k in ["A", "B1", "B2", "C"] { XCTAssertEqual(o.given?.crit[k], d(wg[k]), "given \(k) \(i)") }
                XCTAssertEqual(o.given?.total, d(wg["total"]), "given total \(i)")
                XCTAssertEqual(o.given?.max, d(wg["max"]), "given max \(i)")
                XCTAssertEqual(o.given?.comments, s(wg["comments"]))
                XCTAssertEqual(o.given?.points, wg["points"] as? [String])
            } else { XCTAssertNil(o.given, "given \(i)") }
            if let wm = want["marks"] as? [String: Any] {
                for k in ["A", "B1", "B2", "C", "total"] { XCTAssertEqual(o.marks?[k], d(wm[k]), "marks \(k) \(i)") }
            } else { XCTAssertNil(o.marks) }
            let segs = list(want["segments"])
            XCTAssertEqual(o.segments.count, segs.count, "segments \(i)")
            for (a, b) in zip(o.segments, segs) {
                let x = obj(b)
                XCTAssertEqual(a.part, Int(d(x["part"]) ?? 0)); XCTAssertEqual(a.file, s(x["file"])); XCTAssertEqual(a.ms, d(x["ms"]) ?? 0)
                XCTAssertEqual(a.q, s(x["q"])); XCTAssertEqual(a.heard, s(x["heard"])); XCTAssertEqual(a.said, s(x["said"]))
            }
            let turns = list(want["turns"])
            XCTAssertEqual(o.turns.count, turns.count, "turns \(i)")
            for (a, b) in zip(o.turns, turns) {
                let x = obj(b)
                XCTAssertEqual(a.who, s(x["who"])); XCTAssertEqual(a.text, s(x["text"])); XCTAssertEqual(a.start, d(x["start"]) ?? 0)
            }
            XCTAssertEqual(o.listening != nil, want["listening"] as? Bool ?? false, "listening \(i)")
            XCTAssertEqual(SpanishOral.maxOf(o.kind), Int(d(want["max"]) ?? 0))
            XCTAssertEqual(SpanishOral.when(o.started), s(want["when"]))
            let listed = SpanishOral.rows([o], settings: .init(), images: [])[0]
            if let share = d(want["share"]) { XCTAssertEqual(listed.share ?? -1, share, accuracy: 1e-9, "share \(i)") } else { XCTAssertNil(listed.share, "share \(i)") }
        }
    }

    func testListeningTestLinesAsTheLaptop() {
        let want = list(g["listenTest"]).map(obj)
        XCTAssertEqual(SpanishOral.listenTest.map(\.id), want.map { s($0["id"]) })
        XCTAssertEqual(SpanishOral.listenTest.map(\.read), want.map { s($0["read"]) })
        XCTAssertEqual(SpanishOral.listenTest.map(\.how), want.map { s($0["how"]) })
    }

    func testTheListShowsTitlesNewestFirst() {
        var a = SpanishOral.Oral(); a.id = "1"; a.kind = "session"; a.by = "tutor"; a.started = "2026-11-20T18:00"
        var b = SpanishOral.Oral(); b.id = "2"; b.image = "fiesta.jpg"; b.started = "2026-11-21T09:00"; b.marks = ["total": 21]
        var c = SpanishOral.Oral(); c.id = "3"; c.kind = "conversation"; c.started = "2026-11-19T10:00"
        var e = SpanishOral.Oral(); e.id = "4"; e.theme = "planeta"; e.started = "2026-11-18T10:00"
        var st = SpanishOral.Settings(); st.tutor = "Ana"
        let rows = SpanishOral.rows([a, b, c, e], settings: st, images: [.init(file: "fiesta.jpg", theme: "experiencias", topic: "Festivales y celebraciones", label: "", about: "")])
        XCTAssertEqual(rows.map(\.id), ["2", "1", "3", "4"])
        XCTAssertEqual(rows.map(\.title), ["Experiencias: Festivales y celebraciones", "Session with Ana", "Conversation", "Compartir el planeta"])
        XCTAssertEqual(rows[0].total, 21); XCTAssertEqual(rows[0].max, 30)
        XCTAssertNil(rows[1].total)
        XCTAssertEqual(SpanishOral.who("tutor", settings: st), "Ana")
        XCTAssertEqual(SpanishOral.who("practice", settings: st), "Practice")
    }

    func testARecordingAddedOnThePhoneWaitsForTheLaptop() throws {
        var r = SpanishOral.NewRecording()
        r.by = "teacher"; r.kind = "full"; r.title = "  Summative IO "; r.crit = ["A": 9, "B1": 5, "C": 4.5]; r.comments = "Bien hecho."
        let text = SpanishOral.newOral(r, id: "2026-11-23 1830", started: "2026-11-23T18:30", recording: "recording.m4a", device: "iPhone")
        XCTAssertTrue(text.hasPrefix("# An oral recording added on the iPhone"))
        let o = try XCTUnwrap(SpanishOral.parseOral(text))
        XCTAssertEqual(o.id, "2026-11-23 1830"); XCTAssertEqual(o.kind, "full"); XCTAssertEqual(o.by, "teacher"); XCTAssertEqual(o.title, "Summative IO")
        XCTAssertEqual(o.recording, "recording.m4a"); XCTAssertEqual(o.started, "2026-11-23T18:30")
        XCTAssertEqual(o.given?.crit, ["A": 9, "B1": 5, "C": 4.5]); XCTAssertEqual(o.given?.total, 18.5); XCTAssertEqual(o.given?.max, 24)
        XCTAssertEqual(o.given?.comments, "Bien hecho.")
        XCTAssertEqual(o.waiting, "hear"); XCTAssertEqual(o.from, "iPhone")
        // a tutor's session with only a total out of their own maximum, and none at all
        var t = SpanishOral.NewRecording(); t.total = 7; t.max = 10
        let o2 = try XCTUnwrap(SpanishOral.parseOral(SpanishOral.newOral(t, id: "x", started: "2026-11-23T18:31", recording: "recording.m4a", device: "iPad")))
        XCTAssertEqual(o2.by, "tutor"); XCTAssertEqual(o2.kind, "session"); XCTAssertEqual(o2.given?.total, 7); XCTAssertEqual(o2.given?.max, 10)
        XCTAssertEqual(SpanishOral.markOf(o2).total, 7)
        let o3 = try XCTUnwrap(SpanishOral.parseOral(SpanishOral.newOral(SpanishOral.NewRecording(), id: "y", started: "2026-11-23T18:32", recording: "r.m4a", device: "iPad")))
        XCTAssertNil(o3.given)
    }

    func testListeningTakesAndResults() throws {
        let text = SpanishOral.takeYaml(at: "2026-11-23T18:40:00", device: "iPhone", lines: ["t1", "t2", "control"])
        let take = try XCTUnwrap(SpanishOral.parseTake(text, stamp: "2026-11-23 1840"))
        XCTAssertEqual(take.lines, ["t1", "t2", "control"]); XCTAssertEqual(take.device, "iPhone"); XCTAssertEqual(take.heard, "")
        XCTAssertEqual(SpanishOral.parseTake(text + "heard: 2026-11-23 1900.yaml\n", stamp: "s")?.heard, "2026-11-23 1900.yaml")
        // a result as the laptop keeps it (OralAdd.tsx keep)
        let result = "# The listening test (Spanish › Oral)\nat: 2026-11-23T19:00:00\nfrom: iPhone\nresult:\n  grammar:\n    total: 7\n    said: 5\n    meant: 2\n    verdict: partly\n  sounds:\n    total: 8\n    flagged: 6\n    verdict: partly\n  falseFlags:\n    - \"t1: x\"\n  lines: 9\n  advice: The ears hear you well enough to give feedback on your grammar and sounds.\nlines: []\n"
        let r = try XCTUnwrap(SpanishOral.parseTest(result, file: "2026-11-23 1900.yaml"))
        XCTAssertEqual(r.grammarSaid, 5); XCTAssertEqual(r.grammarTotal, 7); XCTAssertEqual(r.soundsFlagged, 6); XCTAssertEqual(r.falseFlags, 1)
        XCTAssertEqual(r.from, "iPhone"); XCTAssertTrue(r.advice.hasPrefix("The ears hear you"))
        XCTAssertNil(SpanishOral.parseTest("at: x\n", file: "f"))
    }

    func testWhatTheEarsHeardAsTheLaptopShowsIt() throws {
        let y = "listening:\n  talk:\n    mine: 0.64\n    me: 185\n  diffs:\n    - part: 2\n      said: fue\n      meant: fui\n      kind: ending\n  sounds:\n    r:\n      - pero\n      - caro\n    h:\n      - hablo\n  soundCounts:\n    r: 3\n    h: 1\n  delivery:\n    - part: 1\n      wpm: 92\n      pauses: 3\n      longPauses: 1\n      english:\n        - okay\n    - part: all\n      wpm: 88\n      pauses: 1\n  ears:\n    said: true\n    sounds: true\n"
        let h = try XCTUnwrap(SpanishOral.heard(try YValue.parse(y)["listening"]))
        XCTAssertEqual(h.talkLine, "You spoke 64% of the time (3 min).")
        XCTAssertEqual(h.diffs, [.init(said: "fue", meant: "fui", kind: "ending", part: "part 2")])
        XCTAssertEqual(h.sounds.map(\.say), ["an English r", "the h sounded (it is silent)"])
        XCTAssertEqual(h.sounds.map(\.count), [3, 1])
        XCTAssertEqual(h.sounds[0].words, ["pero", "caro"])
        XCTAssertEqual(h.delivery, ["Part 1: 92/min, 3 pauses (1 long), English: okay", "Overall: 88/min, 1 pause"])
        XCTAssertTrue(h.saidEar); XCTAssertTrue(h.soundsEar)
        XCTAssertNil(SpanishOral.heard(try YValue.parse("x: 1")))
        XCTAssertEqual(SpanishOral.partLabel(.string("3:10")), "At 3:10")
    }
}
