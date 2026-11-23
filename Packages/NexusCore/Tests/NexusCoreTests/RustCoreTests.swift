import XCTest
@testable import NexusCore

/// The shared Rust core as NexusCore calls it (RustCore.swift over the UniFFI library built from Packages/NexusCore/Rust). The rules
/// themselves are checked case by case in SharedCasesTests; here, that the library is the one copied and that its answers come
/// across into NexusCore's types.
final class RustCoreTests: XCTestCase {
    func testTheLibraryIsTheCopiedCore() throws {
        XCTAssertTrue(RustCore.version.hasPrefix("nexus-core "), RustCore.version)
        // Packages/NexusCore/Rust/COMMIT (this file is in Packages/NexusCore/Tests/NexusCoreTests): the core says the commit it was built from
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let commit = try String(contentsOf: package.appendingPathComponent("Rust/COMMIT"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(RustCore.version.contains(commit), "\(RustCore.version) vs \(commit)")
    }

    func testTheReaderHandsOverEventsAsTheyCome() {
        let r = TutorReader()
        XCTAssertEqual(r.push("Hello there. Ne"), [.say("Hello there.", n: 0)])
        XCTAssertEqual(r.push("xt\n<step>{\"type\":\"text\",\"te").count, 0)
        var t = TutorStep(type: "text"); t.text = "hi"
        XCTAssertEqual(r.push("xt\":\"hi\"}</step> more"), [.say("Next", n: 1), .step(t)])
        XCTAssertEqual(r.end(), [.say("more", n: 2)])
        XCTAssertEqual(r.sentences, 3)
        XCTAssertTrue(r.problems.isEmpty)
        XCTAssertEqual(TutorReader.spoken("**Good.** Now the `x` term."), "Good. Now the x term.")
    }

    func testCheckMyMaths() {
        let m = RustCore.checkMaths(["2x + 6 = 14", "", "2x = 8", "x = -4"])
        XCTAssertEqual(m.first, 3)
        XCTAssertEqual(m.firstWritten, 3, "the third written line")
        XCTAssertNil(m.lines[1], "a blank line keeps its place")
        XCTAssertEqual(m.lines[2]?.ok, true)
        XCTAssertEqual(m.lines[3]?.ok, false)
        XCTAssertFalse(m.lines[3]?.why.isEmpty ?? true, "the slip says why")
        XCTAssertEqual(m.answer, "x = 4")
        XCTAssertTrue(m.compared)
        let fine = RustCore.checkMaths(["(x+1)^2", "x^2 + 2x + 1"])
        XCTAssertNil(fine.first)
        XCTAssertNil(fine.firstWritten)
        XCTAssertNil(fine.answer)
    }

    func testThePromptIsTheCores() {
        XCTAssertEqual(TutorSteps.prompt, RustCore.stepsPrompt)
        XCTAssertTrue(TutorSteps.prompt.hasPrefix("Drawing steps: each step is one JSON object."))
        XCTAssertFalse(TutorSteps.iPadPrompt.contains("\nOn the screen"))
    }

    func testCaptureAndCards() {
        let p = RustCore.capture("physics hw sheet by friday", today: "2026-10-28")
        XCTAssertEqual(p["title"]?.string, "physics hw sheet")
        XCTAssertEqual(p["facts"]?["due"]?.string, "2026-10-30")
        let c = RustCore.review(card: .object([]), grade: 3, now: 1_000_000, dayStart: 4)
        XCTAssertEqual(c["state"]?.string, "learning")
        XCTAssertEqual(c["due"]?.number, 1_000_000 + 10 * 60_000)
    }
}
