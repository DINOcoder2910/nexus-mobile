import XCTest
@testable import NexusCore

/// Editing waiting on, repeats, tags and the note, on the laptop's fixture folder: each edit reads back as written, keeps the
/// rest of the file, and Undo puts the file back byte for byte.
final class TaskFieldsTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        let src = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("data-vault")
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-fields-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: src, to: dir)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func reload() -> Snapshot { DataFolder.load(dir) }

    func testWaitingOnSomeoneAndNotAnyMore() throws {
        let e = TaskEditor(root: dir)
        var s = reload()
        let c = try e.setWaiting(s.tasks["lab4"]!, on: "Mr Kay, the technician", since: "2026-11-12", in: s)
        s = reload()
        XCTAssertEqual(s.tasks["lab4"]?.waitingOn, "Mr Kay, the technician")
        XCTAssertEqual(s.tasks["lab4"]?.waitingSince, "2026-11-12")
        XCTAssertTrue(c.after.contains("waiting: {on: 'Mr Kay, the technician', since: 2026-11-12}"))
        _ = try e.setWaiting(s.tasks["lab7"]!, on: nil, since: nil, in: s)
        s = reload()
        XCTAssertNil(s.tasks["lab7"]?.waitingOn)
        XCTAssertEqual(s.problems, [])
    }

    func testRepeats() throws {
        let e = TaskEditor(root: dir)
        var s = reload()
        _ = try e.setRepeat(s.tasks["lab4"]!, Repeat(freq: "week", on: ["fri"], until: "2026-12-18"), in: s)
        s = reload()
        let r = try XCTUnwrap(s.tasks["lab4"]?.every)
        XCTAssertEqual(r.freq, "week")
        XCTAssertEqual(r.on, ["fri"])
        XCTAssertEqual(r.until, "2026-12-18")
        _ = try e.setRepeat(s.tasks["lab4"]!, Repeat(freq: "week", on: ["mon", "thu"]), in: s)
        s = reload()
        XCTAssertEqual(s.tasks["lab4"]?.every?.on, ["mon", "thu"])
        _ = try e.setRepeat(s.tasks["lab4"]!, nil, in: s)
        s = reload()
        XCTAssertNil(s.tasks["lab4"]?.every)
    }

    func testTagsAreCleanedAndKeptOnce() throws {
        let e = TaskEditor(root: dir)
        var s = reload()
        _ = try e.setTags(s.tasks["lab4"]!, ["#summative", "lab", "Lab", " "], in: s)
        s = reload()
        XCTAssertEqual(s.tasks["lab4"]?.tags, ["summative", "lab"])
        _ = try e.setTags(s.tasks["lab4"]!, [], in: s)
        s = reload()
        XCTAssertEqual(s.tasks["lab4"]?.tags, [])
    }

    func testTheNoteIsABlockAndUndoPutsItBack() throws {
        let e = TaskEditor(root: dir)
        var s = reload()
        let file = s.tasks["lab4"]!.file
        let original = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
        let c = try e.setNote(s.tasks["lab4"]!, "Bring the lab book.\n\n  Page 12: titration", in: s)
        s = reload()
        XCTAssertEqual(s.tasks["lab4"]?.note, "Bring the lab book.\n\n  Page 12: titration\n")
        XCTAssertEqual(s.tasks["lab4"]?.est, "15m")
        XCTAssertEqual(s.problems, [])
        try e.undo(c)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8), original)
    }

    func testANoteOnATaskThatHadNone() throws {
        let e = TaskEditor(root: dir)
        var s = reload()
        _ = try e.setNote(s.tasks["lab7"]!, "First line\n\nThird line", in: s)
        s = reload()
        XCTAssertEqual(s.tasks["lab7"]?.note, "First line\n\nThird line\n")
        XCTAssertEqual(s.tasks["lab7"]?.waitingOn, "Ms Settle")
        _ = try e.setNote(s.tasks["lab7"]!, "", in: s)
        s = reload()
        XCTAssertNil(s.tasks["lab7"]?.note)
    }

    func testBlockScalar() {
        XCTAssertEqual(YamlEdit.blockScalar(key: "note", text: "a\n\nb  \n"), ["note: |", "  a", "", "  b"])
        XCTAssertEqual(YamlEdit.blockScalar(key: "note", text: "  indented"), ["note: |2", "    indented"])
        XCTAssertEqual(YamlEdit.flowScalar("Ms Settle"), "Ms Settle")
        XCTAssertEqual(YamlEdit.flowScalar("a, b"), "'a, b'")
    }
}
