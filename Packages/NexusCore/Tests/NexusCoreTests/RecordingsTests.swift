import XCTest
@testable import NexusCore

final class RecordingsTests: XCTestCase {
    let utc = TimeZone(identifier: "UTC")!

    func testFolderNamesAndPictures() {
        let d = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18 11:06 UTC
        XCTAssertEqual(Recordings.folderName(started: d, kind: .meeting, zone: utc), "2026-11-18 1106 Meeting")
        let taken: Set<String> = ["2026-11-18 1106 Class", "2026-11-18 1106 Class 2"]
        XCTAssertEqual(Recordings.folderName(started: d, kind: .lesson, taken: { taken.contains($0) }, zone: utc), "2026-11-18 1106 Class 3")
        XCTAssertEqual(Recordings.pictureFile(at: 75.4, taken: []), "pictures/0075.jpg")
        XCTAssertEqual(Recordings.pictureFile(at: 75.9, taken: ["pictures/0075.jpg"]), "pictures/0075-2.jpg")
        XCTAssertEqual(Recordings.clock(75), "1:15")
        XCTAssertEqual(Recordings.clock(3725), "1:02:05")
        XCTAssertEqual(Recordings.Kind.lesson.rawValue, "class")
    }

    func testMetaRoundTripKeepsUnknownFields() throws {
        var m = Recordings.Meta(id: "abc12345", kind: .lesson, started: Date(timeIntervalSince1970: 0), device: "iPhone")
        m.duration = 61.26
        m.video = Recordings.videoFile
        m.pictures = [.init(file: "pictures/0012.jpg", at: 12.34)]
        let text = m.json.pretty
        XCTAssertTrue(text.contains("\"kind\": \"class\""))
        XCTAssertTrue(text.contains("\"duration\": 61.3"))
        var v = try JSONValue.parse(text)
        v = v.setting("theirs", .string("kept"))
        var back = try XCTUnwrap(Recordings.Meta(json: v))
        XCTAssertEqual(back.kind, .lesson)
        XCTAssertEqual(back.pictures, [.init(file: "pictures/0012.jpg", at: 12.3)])
        back.state = "done"
        XCTAssertEqual(back.json["theirs"]?.string, "kept")
        XCTAssertNil(back.json["problem"])
        XCTAssertNil(Recordings.Meta(json: .object([("format", .string("other"))])))
    }

    func testStatusComesFromTheFiles() {
        var m = Recordings.Meta(id: "a", kind: .meeting, started: Date(), device: "d")
        XCTAssertEqual(Recordings.status(m, transcript: false, proposal: false, filed: false), .recording)
        m.state = "done"
        XCTAssertEqual(Recordings.status(m, transcript: true, proposal: false, filed: false), .preparing)
        XCTAssertEqual(Recordings.status(m, transcript: true, proposal: true, filed: false), .review)
        XCTAssertEqual(Recordings.status(m, transcript: true, proposal: true, filed: true), .filed)
        m.state = "failed"
        XCTAssertEqual(Recordings.status(m, transcript: true, proposal: true, filed: false), .failed)
    }

    func testListReadsNewestFirst() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, t, files) in [("2026-11-20 0900 Meeting", 100.0, ["transcript.json"]), ("2026-11-21 1000 Class", 200.0, ["transcript.json", "proposal.json"])] {
            let f = root.appendingPathComponent("recordings/\(name)")
            try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
            var m = Recordings.Meta(id: name, kind: .meeting, started: Date(timeIntervalSince1970: t), device: "d")
            m.state = "done"
            try m.json.pretty.write(to: f.appendingPathComponent("recording.json"), atomically: true, encoding: .utf8)
            for x in files { try "{}".write(to: f.appendingPathComponent(x), atomically: true, encoding: .utf8) }
        }
        try "x".write(to: root.appendingPathComponent("recordings/.gitignore"), atomically: true, encoding: .utf8)
        let list = Recordings.list(root)
        XCTAssertEqual(list.map(\.path), ["recordings/2026-11-21 1000 Class", "recordings/2026-11-20 0900 Meeting"])
        XCTAssertEqual(list.map(\.status), [.review, .preparing])
    }

    func testTranscriptParagraphsAndText() throws {
        let t = Recordings.Transcript(language: "en-US", engine: "apple", segments: [
            .init(start: 0, end: 2, text: "Right, so today"),
            .init(start: 2.5, end: 4, text: "we do redox."),
            .init(start: 9, end: 11, text: "Any questions?"),
            .init(start: 11.2, end: 12, text: "Yes.", speaker: "S2"),
        ])
        XCTAssertEqual(t.paragraphs().map(\.text), ["Right, so today we do redox.", "Any questions?", "Yes."])
        XCTAssertEqual(t.forClaude, "[0:00] Right, so today we do redox.\n[0:09] Any questions?\n[0:11] S2: Yes.")
        XCTAssertTrue(t.markdown(title: "Redox", names: ["S2": "Ali"]).contains("**0:11** Ali: Yes."))
        XCTAssertEqual(t.words, 9)
        let back = try XCTUnwrap(Recordings.Transcript(json: try JSONValue.parse(t.json.text)))
        XCTAssertEqual(back, t)
    }

    func testParsesClaudesAnswer() throws {
        let reply = """
        Here it is:
        ```json
        {"title": "Meeting with Ms K about the EE", "subject": "chem", "people": ["Ms K"], "speakers": {"S1": "Ms K"},
         "summary": "We went over the **research question**.", "decisions": ["Use iron tablets"],
         "tasks": [{"title": "Email Ms K the draft", "due": "2026-11-27", "at": "12:04"}, {"title": "", "due": "x"},
                   {"title": "Read the method", "due": "Friday", "at": 30}],
         "dates": [{"what": "EE draft due", "date": "2026-12-01", "time": "9:00"}, {"what": "bad", "date": "soon"}],
         "class": null}
        ```
        """
        let p = try XCTUnwrap(Recordings.parseReply(reply, subjects: ["chem", "econ"]))
        XCTAssertEqual(p.title, "Meeting with Ms K about the EE")
        XCTAssertEqual(p.subject, "chem")
        XCTAssertEqual(p.speakers, ["S1": "Ms K"])
        XCTAssertEqual(p.tasks.map(\.title), ["Email Ms K the draft", "Read the method"])
        XCTAssertEqual(p.tasks[0].at, 724)
        XCTAssertEqual(p.tasks[0].due, "2026-11-27")
        XCTAssertNil(p.tasks[1].due)
        XCTAssertEqual(p.dates, [.init(what: "EE draft due", date: "2026-12-01", time: "9:00")])
        XCTAssertNil(p.classNotes)
        // an unknown subject goes to the Inbox; the proposal reads back the same
        let q = try XCTUnwrap(Recordings.parseReply(#"{"title":"T","subject":"physics","summary":"s"}"#, subjects: ["chem"]))
        XCTAssertNil(q.subject)
        let again = try XCTUnwrap(Recordings.Proposal(json: try JSONValue.parse(p.json.text)))
        XCTAssertEqual(again, p)
        XCTAssertNil(Recordings.parseReply("no json here", subjects: nil))
    }

    func testClassNotesSummaryAndTeaching() throws {
        let reply = #"{"title":"Redox: half-equations","subject":"chem","summary":"Half-equations.","tasks":[{"title":"Do Q1-5","at":"40:00"}],"class":{"unit":"R3.2","taught":"1. Oxidation states\n2. Half-equations","examples":["Fe2+ to Fe3+"],"teaching":"Balances O with water first, then H+."}}"#
        var p = try XCTUnwrap(Recordings.parseReply(reply, subjects: nil))
        XCTAssertEqual(p.classNotes?.unit, "R3.2")
        var m = Recordings.Meta(id: "x", kind: .lesson, started: Date(timeIntervalSince1970: 1_795_000_000), device: "d")
        m.duration = 3000
        m.pictures = [.init(file: "pictures/0100.jpg", at: 100)]
        p.tasks.append(.init(title: "Unticked", take: false))
        let md = Recordings.summaryMarkdown(meta: m, proposal: p, subjectName: "Chemistry")
        XCTAssertTrue(md.hasPrefix("# Redox: half-equations\n"))
        XCTAssertTrue(md.contains("- [ ] Do Q1-5 · 40:00"))
        XCTAssertFalse(md.contains("Unticked"))
        XCTAssertTrue(md.contains("## What was taught (R3.2)"))
        XCTAssertTrue(md.contains("- 1:40: ![](pictures/0100.jpg)"))
        let first = Recordings.addTeaching(nil, subjectName: "Chemistry", date: "2026-11-20", title: "Old class", path: "recordings/a", notes: .init(taught: "x", teaching: "Old way."))
        let both = Recordings.addTeaching(first, subjectName: "Chemistry", date: "2026-11-21", title: "Redox", path: "recordings/b", notes: p.classNotes!)
        XCTAssertTrue(both.hasPrefix("# How Chemistry is taught"))
        let newer = try XCTUnwrap(both.range(of: "## 2026-11-21: Redox (R3.2)")), older = try XCTUnwrap(both.range(of: "## 2026-11-20: Old class"))
        XCTAssertLessThan(newer.lowerBound, older.lowerBound)
        XCTAssertTrue(both.contains("[The class](recordings/b/summary.md)"))
        XCTAssertEqual(Recordings.taskNote(p.tasks[0], title: p.title, path: "recordings/b"), "From the recording “Redox: half-equations” at 40:00 (recordings/b).")
    }

    func testPromptAndFiled() throws {
        var m = Recordings.Meta(id: "x", kind: .call, started: Date(timeIntervalSince1970: 1_795_000_000), device: "d")
        m.duration = 65
        let t = Recordings.Transcript(language: "en", engine: "e", segments: [.init(start: 3, end: 4, text: "Hello")])
        let s = Recordings.prompt(meta: m, transcript: t, subjects: [.init(id: "econ", name: "Economics", kind: "class")], event: "Econ IA check-in", today: "2026-11-21")
        XCTAssertTrue(s.contains("a video call"))
        XCTAssertTrue(s.contains("1:05 long"))
        XCTAssertTrue(s.contains("- econ: Economics (class)"))
        XCTAssertTrue(s.contains("The calendar had this at that time: Econ IA check-in."))
        XCTAssertTrue(s.hasSuffix("Transcript:\n[0:03] Hello"))
        let f = Recordings.Filed(accepted: "t", device: "iPhone", subject: "econ", tasks: [(id: "k1", file: "classes/econ/tasks.yaml")], teaching: "classes/econ/teaching.md", teachingBefore: "")
        XCTAssertEqual(Recordings.Filed(json: try JSONValue.parse(f.json.text)), f)
    }
}
