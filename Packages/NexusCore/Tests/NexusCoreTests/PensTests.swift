import XCTest
@testable import NexusCore

/// The pens shared with the laptop (Pens.swift; the new laptop app's desktop/backend/src/pens.rs, whose tests these follow).
final class PensTests: XCTestCase {
    func ink(_ c: String, _ s: Int) -> Pens.Ink { Pens.Ink(color: c, step: s) }

    func testASaveLaysOnlyWhatChangedOverTheFile() {
        var set = Pens.Shared(); set.inks["pen"] = ink("#2f6feb", 3)
        let first = Pens.merge(nil, set)
        XCTAssertEqual(first, "{\n  \"format\": \"nexus-pens/1\",\n  \"pen\": {\n    \"color\": \"#2F6FEBFF\",\n    \"step\": 3\n  }\n}\n")
        // the laptop keeps a part the iPad doesn't know and changed the eraser; the iPad then changes the highlighter
        let laptop = "{\n  \"format\": \"nexus-pens/1\",\n  \"pen\": {\n    \"color\": \"#2F6FEBFF\",\n    \"step\": 3\n  },\n  \"eraser\": \"part\",\n  \"ring\": {\n    \"tools\": [\"pen\"]\n  }\n}\n"
        var m = Pens.Shared(); m.inks["marker"] = ink("#9BE7A0", 4)
        let both = Pens.merge(laptop, m)
        let r = Pens.read(both)
        XCTAssertEqual(r.inks["pen"], ink("#2F6FEBFF", 3))
        XCTAssertEqual(r.inks["marker"], ink("#9BE7A0FF", 4))
        XCTAssertEqual(r.eraser, "part")
        XCTAssertTrue(both.contains("\"ring\": {"), both)
        // in the laptop's order: format, the inks, …, eraser, then the rest
        let keys = ["\"format\"", "\"pen\"", "\"marker\"", "\"eraser\"", "\"ring\""].map { both.range(of: $0)!.lowerBound }
        XCTAssertEqual(keys, keys.sorted())

        // one row of colours changes, the other stays
        var rows = Pens.Shared()
        rows.colors["pen"] = (0..<10).map { "#00000\($0)" }
        rows.colors["marker"] = (0..<8).map { "#FFFF0\($0)FF" }
        let c = Pens.merge(both, rows)
        var one = Pens.Shared(); one.colors["pen"] = Array(repeating: "#111111", count: 10)
        let c2 = Pens.read(Pens.merge(c, one))
        XCTAssertEqual(c2.colors["marker"]?[7], "#FFFF07FF")
        XCTAssertEqual(c2.colors["pen"]?[0], "#111111FF")
        XCTAssertEqual(c2.inks["marker"]?.step, 4)
    }

    func testTheLaptopsWidthsAreReadAndScaledToTheIPadsInks() {
        // as the laptop's serde_json writes them (3.0, not 3)
        let text = "{\n  \"format\": \"nexus-pens/1\",\n  \"widths\": {\n    \"pen\": [\n      1.0,\n      1.5,\n      2.25,\n      4.5,\n      6.0,\n      10.0\n    ],\n    \"pencil\": [0.6, 1.0, 2.0, 3.0, 4.0, 12.0],\n    \"marker\": [1, 2, 3]\n  }\n}\n"
        let r = Pens.read(text)
        XCTAssertEqual(r.widths["pen"], [1, 1.5, 2.25, 4.5, 6, 10])
        XCTAssertNil(r.widths["marker"], "a row of three isn't one")
        XCTAssertEqual(Pens.scaled(r.widths["pen"], ink: "pen", own: [1, 1.5, 3, 4.5, 6, 10]), [1, 1.5, 2.25, 4.5, 6, 10])
        // the laptop's pencil is thinner than PencilKit's: its Extra bold made twice as wide is the iPad's made twice as wide
        XCTAssertEqual(Pens.scaled(r.widths["pencil"], ink: "pencil", own: [2.4, 3, 4, 6, 8, 12]), [2.4, 3, 4, 6, 8, 24])
        XCTAssertNil(Pens.scaled(nil, ink: "pen", own: [1, 1.5, 3, 4.5, 6, 10]))
        // the iPad never writes widths it doesn't have, and keeps the laptop's when it saves something else
        var e = Pens.Shared(); e.eraser = "stroke"
        XCTAssertEqual(Pens.read(Pens.merge(text, e)).widths["pen"]?[2], 2.25)
        var w = Pens.Shared(); w.widths["pen"] = [0, 1, 2, 3, 4, 5]
        XCTAssertNil(Pens.read(Pens.merge(nil, w)).widths["pen"], "0 is under the least width")
    }

    func testWhatIsNotWellFormedIsLeftOut() {
        let odd = "{\"format\":\"nexus-pens/1\",\"pen\":{\"color\":\"#00000000zz\",\"step\":1},\"marker\":{\"color\":\"#FFE066FF\",\"step\":2},\"pencil\":{\"color\":\"#000000\",\"step\":9},\"eraser\":\"all\",\"colors\":{\"pen\":[\"#000000\"]}}"
        let r = Pens.read(odd)
        XCTAssertNil(r.inks["pen"])
        XCTAssertEqual(r.inks["marker"], ink("#FFE066FF", 2))
        XCTAssertEqual(r.inks["pencil"]?.step, 5)
        XCTAssertNil(r.eraser)
        XCTAssertTrue(r.colors.isEmpty)
        XCTAssertEqual(Pens.read("{\"format\":\"nexus-pens/9\",\"pen\":{\"color\":\"#000000FF\",\"step\":1}}"), Pens.Shared())
        XCTAssertEqual(Pens.read("not json"), Pens.Shared())
        XCTAssertEqual(Pens.read(nil), Pens.Shared())
        // a file that isn't one is replaced by a new one
        var s = Pens.Shared(); s.eraser = "part"
        XCTAssertEqual(Pens.merge("{\"format\":\"other\",\"x\":1}", s), "{\n  \"format\": \"nexus-pens/1\",\n  \"eraser\": \"part\"\n}\n")
        XCTAssertEqual(Pens.short("#1B1B1BFF"), "#1B1B1B")
        XCTAssertEqual(Pens.short("#1B1B1B80"), "#1B1B1B80")
        XCTAssertEqual(Pens.color(" ##1b1b1b "), "#1B1B1BFF")
    }

    func testChangesNameOnlyWhatDiffers() {
        var a = Pens.Shared(); a.inks["pen"] = ink("#000000FF", 2); a.eraser = "stroke"; a.colors["pen"] = Array(repeating: "#000000FF", count: 10)
        var b = a; b.inks["pen"]?.step = 3
        let c = Pens.changes(from: a, to: b)
        XCTAssertEqual(c.inks, ["pen": ink("#000000FF", 3)])
        XCTAssertNil(c.eraser)
        XCTAssertTrue(c.colors.isEmpty)
        XCTAssertTrue(Pens.changes(from: a, to: a).isEmpty)
    }
}
