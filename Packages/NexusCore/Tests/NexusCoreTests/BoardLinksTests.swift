import XCTest
@testable import NexusCore

/// Board links must read and write as the laptop's renderer/src/board/links.js does (nexus dev/unit-links.mjs has the same cases).
final class BoardLinksTests: XCTestCase {
    func j(_ s: String) -> JSONValue { try! JSONValue.parse(s) }

    func testEnds() {
        let kinds = [#"{"on":"a"}"#, #"{"on":"a","board":"../B.board"}"#, #"{"board":"../B.board"}"#, #"{"task":"t1"}"#, #"{"note":"n.md"}"#,
                     #"{"deck":"d.yaml","card":"c"}"#, "{}"].map { BoardLinks.kind(j($0))?.rawValue }
        XCTAssertEqual(kinds, ["here", "board", "board", "task", "note", "deck", nil])
        XCTAssertNil(BoardLinks.kind(nil))
        XCTAssertEqual(BoardLinks.norm(j(#"{"on":"x","future":1}"#))?.text, #"{"on":"x","future":1}"#)
        XCTAssertEqual(BoardLinks.norm(j(#"{"on":"p","page":3,"fx":0.123456,"fy":1.4,"fw":-1,"fh":"x"}"#))?.text, #"{"on":"p","page":3,"fx":0.1235,"fy":1,"fw":0}"#)
        XCTAssertEqual(BoardLinks.norm(j(#"{"on":"p","page":0}"#))?.text, #"{"on":"p"}"#)
        XCTAssertEqual(BoardLinks.norm(j(#"{"on":"t","at":{"pre":"x"}}"#))?.text, #"{"on":"t"}"#)
    }

    func testNewLink() {
        let now = ISO8601DateFormatter().date(from: "2026-11-12T10:00:00Z")!
        let lk = BoardLinks.make(id: "k1", a: j(#"{"on":"a"}"#), b: j(#"{"task":"T-1"}"#), color: "#1f9d8b", by: "Duo", now: now, x: 10.126, y: 5)
        XCTAssertEqual(lk?.json.text, #"{"id":"k1","type":"link","x":10.13,"y":5,"a":{"on":"a"},"b":{"task":"T-1"},"color":"#1F9D8B","made":"2026-11-12T10:00:00Z","by":"Duo"}"#)
        XCTAssertNil(BoardLinks.make(id: "k", a: j(#"{"on":"a"}"#), b: j("{}")))
        XCTAssertEqual(BoardLinks.make(id: "k", a: j(#"{"on":"a"}"#), b: j(#"{"on":"b"}"#), color: "red")?.string("color"), BoardLinks.colors[0])
        XCTAssertTrue(BoardLinks.same(j(#"{"on":"a","page":2,"fx":0.1,"fy":0.2}"#), j(#"{"on":"a","page":2,"fx":0.1,"fy":0.2}"#)))
        XCTAssertFalse(BoardLinks.same(j(#"{"on":"a"}"#), j(#"{"on":"a","page":1}"#)))
        XCTAssertFalse(BoardLinks.same(j(#"{"on":"a"}"#), j(#"{"task":"a"}"#)))
        XCTAssertFalse(BoardLinks.same(j(#"{"on":"t","at":{"q":"cell","i":4}}"#), j(#"{"on":"t","at":{"q":"anode","i":10}}"#)))
        XCTAssertFalse(BoardFormat.itemTypes.isDisjoint(with: ["link"]))
        XCTAssertFalse(lk!.isForeign)
        XCTAssertTrue(BoardFormat.unknownFeatures(j(#"{"features":["links"]}"#)).isEmpty)
    }

    func testWhichLinksTouchWhat() {
        let l1 = BoardItem(j(#"{"id":"k1","type":"link","x":0,"y":0,"a":{"on":"a"},"b":{"task":"T-1"}}"#))!
        let l2 = BoardItem(j(#"{"id":"k2","type":"link","x":0,"y":0,"a":{"on":"s1"},"b":{"on":"a"}}"#))!
        let l3 = BoardItem(j(#"{"id":"k3","type":"link","x":0,"y":0,"a":{"on":"z"},"b":{"on":"p","board":"../X.board"}}"#))!
        XCTAssertEqual([BoardLinks.side(l1, on: "a"), BoardLinks.side(l2, on: "a"), BoardLinks.side(l3, on: "p")], ["a", "b", nil])
        XCTAssertEqual(BoardLinks.links([l1, l2, l3], on: ["a"]).map(\.id), ["k1", "k2"])
        XCTAssertEqual(BoardLinks.links([l1, l2, l3], on: ["p"]).map(\.id), [])
    }

    func testPaths() {
        XCTAssertEqual(BoardLinks.board(of: j(#"{"on":"a"}"#), from: "n/C/A.board"), "n/C/A.board")
        XCTAssertEqual(BoardLinks.board(of: j(#"{"on":"a","board":"../B.board"}"#), from: "n/C/A.board"), "n/C/B.board")
        XCTAssertNil(BoardLinks.board(of: j(#"{"task":"t"}"#), from: "n/C/A.board"))
        XCTAssertEqual(BoardLinks.end(for: j(#"{"on":"x","board":"old"}"#), target: "n/C/A.board", from: "n/C/A.board")?.text, #"{"on":"x"}"#)
        XCTAssertEqual(BoardLinks.end(for: j(#"{"on":"x"}"#), target: "n/P/B.board", from: "n/C/A.board")?.text, #"{"on":"x","board":"../../P/B.board"}"#)
        XCTAssertEqual(BoardLinks.end(j(#"{"on":"x"}"#), readOn: "n/C/A.board", shownOn: "n/P/B.board")?.text, #"{"on":"x","board":"../../C/A.board"}"#)
        XCTAssertEqual(BoardLinks.end(j(#"{"on":"y","board":"../../P/B.board"}"#), readOn: "n/C/A.board", shownOn: "n/P/B.board")?.text, #"{"on":"y"}"#)
        XCTAssertEqual(BoardLinks.end(j(#"{"task":"t"}"#), readOn: "a.board", shownOn: "b.board")?.text, #"{"task":"t"}"#)
        XCTAssertNil(BoardLinks.resolve("a.board", "../../x"))
        XCTAssertNil(BoardLinks.resolve("a.board", "C:/x"))
    }

    func testWords() {
        let md = "The anode is where oxidation happens. At the anode, electrons leave."
        let k2 = (md as NSString).range(of: "anode", options: [], range: NSRange(location: 10, length: (md as NSString).length - 10)).location
        let at = BoardLinks.quote(md, from: k2, to: k2 + 5)!
        XCTAssertEqual(at.text, #"{"q":"anode","pre":"ion happens. At the ","post":", electrons leave.","i":\#(k2)}"#)
        XCTAssertEqual(BoardLinks.quote(md, from: 6, to: 6)?["q"]?.string, "anode")
        XCTAssertNil(BoardLinks.quote("a   b", from: 2, to: 3))
        XCTAssertEqual(BoardLinks.find(md, at), NSRange(location: k2, length: 5))
        let md2 = "NEW LINE ADDED ON TOP.\n" + md
        XCTAssertEqual(BoardLinks.find(md2, at), NSRange(location: k2 + 23, length: 5))
        let md3 = md.replacingOccurrences(of: "At the anode", with: "At the positive anode")
        XCTAssertEqual(BoardLinks.find(md3, at)?.location, (md3 as NSString).range(of: "anode", options: .backwards).location)
        XCTAssertNil(BoardLinks.find(md.replacingOccurrences(of: "anode", with: "electrode"), at))
        XCTAssertEqual(BoardLinks.plainWords("**Bold** and [a link](x.md) ==hi=="), "Bold and a link hi")
        // offsets count UTF-16 units, as on the laptop
        let emoji = "🧪 anode"
        XCTAssertEqual(BoardLinks.quote(emoji, from: 3, to: 8)?["i"]?.number, 3)
    }

    func testPdfSpots() {
        let f = BoardLinks.Frame(x: 100, y: 200, w: 800, h: 1000)
        let spot = JSONValue.object(BoardLinks.pdfSpot(f, [500, 700, 300, 600]))
        XCTAssertEqual(spot.text, #"{"fx":0.25,"fy":0.4,"fw":0.25,"fh":0.1}"#)
        XCTAssertEqual(BoardLinks.spotBox(f, spot), [300, 600, 500, 700])
        XCTAssertEqual(JSONValue.object(BoardLinks.pdfSpot(f, [800, 1100, 1000, 1300])).text, #"{"fx":0.875,"fy":0.9,"fw":0.125,"fh":0.1}"#)
        XCTAssertTrue(BoardLinks.isPdfSpot(j(#"{"on":"p","page":1,"fx":0,"fy":0}"#)))
        XCTAssertFalse(BoardLinks.isPdfSpot(j(#"{"on":"p","page":1}"#)))
    }

    func testIndex() throws {
        let lk = BoardLinks.make(id: "k1", a: j(#"{"on":"a"}"#), b: j(#"{"task":"T-1"}"#))!
        let img = BoardItem(id: "img", type: "image", x: 0, y: 0, fields: [("w", .number(10)), ("h", .number(10))])
        let bad = BoardItem(j(#"{"id":"bad","type":"link","x":0,"y":0,"a":{},"b":{"on":"x"}}"#))!
        let tile = BoardFiles.tileJSON(strokes: [], items: [lk, img, bad])
        XCTAssertEqual(BoardLinks.links(inTile: tile).map(\.id), ["k1"])
        XCTAssertEqual(BoardLinks.links(inTile: "{\"items\":[{\"type\":\"image\"}]} not json"), [])
        // a link survives a tile round trip as it was written, one line per link
        let back = try BoardFiles.parseTile(tile).items.first { $0.id == "k1" }
        XCTAssertEqual(back?.cleanJSON.text, lk.cleanJSON.text)
        XCTAssertEqual(tile.split(separator: "\n").filter { $0.contains("\"type\":\"link\"") }.count, 2)

        func L(_ s: String) -> BoardItem { BoardItem(j(s))! }
        let index: [(String, [BoardItem])] = [
            ("n/C/A.board", [L(#"{"id":"k1","type":"link","x":0,"y":0,"a":{"on":"w"},"b":{"on":"p","board":"../../P/B.board","page":2,"fx":0.1,"fy":0.1}}"#),
                             L(#"{"id":"k4","type":"link","x":0,"y":0,"a":{"on":"w"},"b":{"board":"../../P/B.board"}}"#),
                             L(#"{"id":"k6","type":"link","x":0,"y":0,"a":{"on":"a"},"b":{"task":"T-1"}}"#)]),
            ("n/P/B.board", [L(#"{"id":"k5","type":"link","x":0,"y":0,"a":{"on":"q"},"b":{"on":"w","board":"../../C/A.board"}}"#)]),
        ]
        XCTAssertEqual(BoardLinks.incoming(index, to: "n/P/B.board").map { "\($0.from):\($0.link.id):\($0.side)" }, ["n/C/A.board:k1:b", "n/C/A.board:k4:b"])
        XCTAssertEqual(BoardLinks.incoming(index, to: "n/C/A.board").map(\.link.id), ["k5"])
        XCTAssertEqual(BoardLinks.linksTo(index, task: "T-1").map { "\($0.link.id):\($0.side)" }, ["k6:b"])
        XCTAssertEqual([BoardLinks.group(of: j(#"{"on":"a"}"#), from: "n/C/A.board"), BoardLinks.group(of: j(#"{"board":"../B.board"}"#), from: "n/C/A.board"),
                        BoardLinks.group(of: j(#"{"deck":"d","card":"c"}"#), from: "x")], ["here", "board:n/C/B.board", "deck"])
    }

    func testRibbon() {
        let free = BoardLinks.curve((0, 0), (400, 0))
        XCTAssertEqual(free.hits, 0)
        XCTAssertNotEqual(free.c1.1, 0)
        XCTAssertEqual(free.c1.1.sign, free.c2.1.sign)
        let around = BoardLinks.curve((0, 0), (400, 0), obstacles: [[150, 10, 250, 200]])
        XCTAssertEqual(around.hits, 0)
        XCTAssertNotEqual(around.c1.1.sign, free.c1.1.sign)
        XCTAssertLessThanOrEqual(abs(BoardLinks.curve((0, 0), (5000, 0)).c1.1), 160)
        let band = BoardLinks.band((0, 0), (400, 0), free)
        XCTAssertEqual(band.count, 58)
        func width(_ i: Int) -> Double { hypot(band[i].0 - band[57 - i].0, band[i].1 - band[57 - i].1) }
        XCTAssertGreaterThan(width(0), 8)
        XCTAssertLessThan(width(14), 4.5)
        let e = BoardLinks.edgePoint([0, 0, 100, 50], toward: (300, 25))
        XCTAssertEqual([e.0, e.1], [100, 25])
        let c = BoardLinks.clamp((100, 100), (1000, 100), view: [0, 0, 500, 400])
        XCTAssertEqual([c.0, c.1], [482, 100])
        let s = BoardLinks.clamp((100, 100), (200, 150), view: [0, 0, 500, 400])
        XCTAssertEqual([s.0, s.1], [200, 150])
    }

    func testLabels() {
        typealias C = BoardLinks.LabelContext
        XCTAssertEqual(BoardLinks.label(j(#"{"on":"t","at":{"q":"the **anode**"}}"#)), "“the anode”")
        XCTAssertEqual(BoardLinks.label(j(#"{"on":"p","page":12,"fx":0,"fy":0}"#), C(kind: "pdf", pdfName: "Redox")), "Redox p. 12")
        XCTAssertEqual(BoardLinks.label(j(#"{"on":"s","board":"../Cells.board"}"#), C(kind: "stroke")), "Ink · Cells")
        XCTAssertEqual(BoardLinks.label(j(#"{"on":"s","board":"../Cells.board"}"#)), "On Cells")
        XCTAssertEqual(BoardLinks.label(j(#"{"board":"../../Chem/Cells.board"}"#)), "Cells")
        XCTAssertEqual(BoardLinks.label(j(#"{"task":"t"}"#), C(taskTitle: "Revise redox")), "Revise redox")
        XCTAssertEqual(BoardLinks.label(j(#"{"deck":"w/study/decks/ions.yaml","card":"c1"}"#), C(cardFront: "Sulfate")), "Sulfate · ions")
        XCTAssertEqual(BoardLinks.label(j(#"{"note":"notes/Redox summary.md"}"#)), "Redox summary")
    }
}
