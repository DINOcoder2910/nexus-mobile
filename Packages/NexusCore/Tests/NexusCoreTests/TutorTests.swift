import XCTest
@testable import NexusCore

/// The tutor's core, ported from the laptop's dev/unit-tutor.mjs and dev/unit-tutorturn.mjs with the same cases and the laptop's own
/// answers (golden values printed by the laptop's code), so both apps read and draw a reply the same way.
final class TutorTests: XCTestCase {
    func step(_ json: String) -> TutorStep? { TutorSteps.normalize(try! JSONValue.parse(json)) }
    func problem(_ json: String) -> String? { TutorSteps.check(try! JSONValue.parse(json)).problem }

    // MARK: steps

    func testCleansSteps() {
        let t = step(#"{"type":"text","id":"t1","text":"**OIL RIG**","size":"large","color":"red"}"#)!
        XCTAssertEqual([t.type, t.id, t.color, t.text], ["text", "t1", "#D93025", "**OIL RIG**"])
        XCTAssertEqual(t.size, 22)
        XCTAssertNil(step(#"{"type":"text","text":"a","size":"normal"}"#)!.size, "the normal size is left out")
        XCTAssertEqual(step(#"{"type":"math","tex":"$$E = mc^2$$"}"#)!.tex, "E = mc^2")
        XCTAssertEqual(step(#"{"step":{"type":"math","tex":"x"}}"#)!.tex, "x", "a { step } event is read as its step")
        XCTAssertEqual(step(#"{"type":"Arrow","from":[0,0],"to":[10,0]}"#)!.type, "arrow")
        XCTAssertEqual(problem(#"{"type":"sparkles"}"#), "unknown type \"sparkles\"")
        XCTAssertNil(step(#"{"type":"text","id":"has space","text":"a"}"#))
        XCTAssertNil(step(#"{"type":"text","text":"  "}"#))
        XCTAssertNil(step(#"{"type":"text","text":"a","color":"teal"}"#)!.color)
        XCTAssertEqual(step(##"{"type":"text","text":"a","color":"#00aa00"}"##)!.color, "#00AA00")
        let l = step(#"{"type":"line","from":[0.123,"5"],"to":[1e9,2]}"#)!
        XCTAssertEqual(l.from, .point(0.12, 5))
        XCTAssertEqual(l.to, .point(100000, 2))
        XCTAssertEqual(step(#"{"type":"math","tex":"x","at":[10,20]}"#)!.at, .point(10, 20))
        XCTAssertEqual(step(#"{"type":"math","tex":"x","at":{"right":"eq1","gap":40}}"#)!.at, .beside("right", "eq1", gap: 40))
        XCTAssertNil(step(#"{"type":"math","tex":"x","at":{"near":"eq1"}}"#))
        let a = step(#"{"type":"arrow","from":"eq1","to":{"of":"g1","side":"top","dy":-4},"bend":3,"both":true}"#)!
        XCTAssertEqual(a.from, .id("eq1"))
        XCTAssertEqual(a.to, .of("g1", side: "top", dx: nil, dy: -4))
        XCTAssertEqual(a.bend, 1)
        XCTAssertTrue(a.both)
        XCTAssertNil(step(#"{"type":"arrow","from":[0,0]}"#))
        XCTAssertNil(step(#"{"type":"path","points":[[0,0]]}"#))
        XCTAssertEqual(step(#"{"type":"path","points":[[0,0],[5,5],"x"],"closed":true}"#)!.points, [[0, 0], [5, 5]])
        XCTAssertEqual(step(#"{"type":"circle","target":"eq1"}"#)!.target, .id("eq1"))
        XCTAssertEqual(step(#"{"type":"circle","target":[0,0,10,10]}"#)!.target, .rect(0, 0, 10, 10))
        XCTAssertEqual(step(#"{"type":"circle","target":[3,4]}"#)!.target, .point(3, 4))
        XCTAssertNil(step(#"{"type":"box","target":[0,0,-5,5]}"#))
        let g = step(#"{"type":"graph","fn":"x^2","x":[-2,2],"y":[3,1],"points":[[0,0,"min"],[1]]}"#)!
        XCTAssertEqual(g.fns.map(\.fn), ["x^2"])
        XCTAssertEqual(g.graphPoints, [TutorGraphPoint(x: 0, y: 0, label: "min")])
        XCTAssertEqual(g.xRange, [-2, 2])
        XCTAssertNil(g.yRange, "a range the wrong way round is dropped")
        XCTAssertNil(step(#"{"type":"graph","fns":[]}"#))
        XCTAssertEqual(step(#"{"type":"erase","target":"eq1"}"#)!.target, .id("eq1"))
        XCTAssertNil(step(#"{"type":"erase","target":[0,0]}"#))
        let sc = step(#"{"type":"point","on":"screen","area":"c2"}"#)!
        XCTAssertEqual([sc.on, sc.area], ["screen", "C2"])
        XCTAssertEqual(problem(#"{"type":"point","on":"screen"}"#), "point on the screen needs target [x, y] or [x, y, w, h], or area")
        XCTAssertNil(step(#"{"type":"text","on":"screen","text":"a"}"#))
    }

    func testPromptsCarryEveryType() {
        for t in TutorSteps.stepTypes { XCTAssertTrue(TutorSteps.prompt.contains("\"" + t + "\""), t) }
        XCTAssertFalse(TutorSteps.iPadPrompt.contains("\"on\":\"screen\""), "the iPad has no screen overlay")
        XCTAssertTrue(TutorSteps.iPadPrompt.contains("\"kind\":\"lewis\""), "the iPad draws the laptop's chemistry diagrams too (Sources/Render)")
        let sys = TutorPrompt.iPadSystem(name: "Sam")
        XCTAssertTrue(sys.contains("Sam's study app") && sys.contains("tutor button") && sys.contains("<handwriting>"))
        XCTAssertEqual(TutorPrompt.iPadSystem(name: "Sam"), sys, "the same every turn, so it caches")
        XCTAssertTrue(TutorPrompt.system(name: "Sam").contains(TutorSteps.prompt), "the laptop's prompt carries the steps word for word")
    }

    func testBeats() {
        let ev: [TutorEvent] = [.step(step(#"{"type":"text","text":"a"}"#)!), .say("One.", n: 0), .step(step(#"{"type":"math","tex":"x"}"#)!),
                                .step(step(#"{"type":"line","from":[0,0],"to":[1,1]}"#)!), .say("Two.", n: 1), .say("Three.", n: 2),
                                .step(step(#"{"type":"erase","target":"a"}"#)!)]
        let b = TutorSteps.beats(ev)
        XCTAssertEqual(b.map(\.say), [nil, "One.", "Two.", "Three."])
        XCTAssertEqual(b.map { $0.steps.map(\.type) }, [["text"], ["math", "line"], [], ["erase"]])
    }

    // MARK: geometry

    let boxes: [String: TutorBox] = ["eq1": TutorBox(100, 100, 200, 40), "g1": TutorBox(100, 300, 320, 220)]
    func look(_ id: String) -> TutorBox? { boxes[id] }
    func r(_ p: [Double]) -> [Double] { p.map { TutorSteps.jsRound($0 * 100) / 100 } }

    func testGeometry() {
        let b = TutorBox(0, 0, 100, 50)
        XCTAssertEqual(["topleft", "top", "right", "bottomright", "center"].map { TutorSteps.sidePoint(b, $0) }, [[0, 0], [50, 0], [100, 25], [100, 50], [50, 25]])
        XCTAssertEqual(TutorSteps.resolve(.point(10, 20), look, frame: [1000, 500]), [1010, 520])
        XCTAssertEqual(TutorSteps.resolve(.of("eq1", side: "bottom", dx: nil, dy: 5), look, frame: [1000, 500]), [200, 145])
        XCTAssertNil(TutorSteps.resolve(.id("nope"), look))
        var s = TutorStep(type: "arrow"); s.from = .id("eq1"); s.to = .id("g1")
        let e = TutorSteps.resolveEnds(s, look)!
        XCTAssertEqual([r(e.0), r(e.1)], [[205.38, 146], [236, 294]])
        s.from = .point(200, 600)
        let e2 = TutorSteps.resolveEnds(s, look)!
        XCTAssertEqual([r(e2.0), r(e2.1)], [[200, 600], [223.37, 526]])
        XCTAssertEqual(TutorSteps.resolveTarget(.id("eq1"), look, frame: [5, 5]), TutorBox(100, 100, 200, 40))
        XCTAssertEqual(TutorSteps.resolveTarget(.rect(0, 0, 10, 10), look, frame: [5, 5]), TutorBox(5, 5, 10, 10))
        XCTAssertEqual(TutorSteps.resolveTarget(.point(1, 2), look, frame: [5, 5]), TutorBox(6, 7, 0, 0))
        XCTAssertEqual(TutorSteps.placeBlock(.point(10, 10), size: [50, 20], look, frame: [100, 0]), [110, 10])
        XCTAssertEqual([TutorPlace.beside("below", "eq1", gap: nil), .beside("right", "eq1", gap: 10), .beside("above", "eq1", gap: nil), .beside("left", "eq1", gap: nil)]
            .map { TutorSteps.placeBlock($0, size: [50, 20], look) }, [[100, 164], [310, 110], [100, 56], [26, 110]], "a note beside a line is level with its middle")
        XCTAssertEqual(TutorSteps.placeBlock(nil, size: [50, 20], look, flow: [7, 9]), [7, 9])
        XCTAssertEqual(TutorSteps.placeBlock(.beside("below", "nope", gap: nil), size: [50, 20], look, flow: [7, 9]), [7, 9])
        let t = TutorSteps.estimateSize(step(#"{"type":"text","text":"a short line"}"#)!)
        XCTAssertEqual(t[1], 24)
        XCTAssertTrue(t[0] > 40 && t[0] < 120)
        var long = TutorStep(type: "text"); long.text = String(repeating: "x", count: 300)
        XCTAssertEqual(TutorSteps.estimateSize(long)[0], 560)
        XCTAssertEqual(TutorSteps.estimateSize(step(#"{"type":"graph","fn":"x","w":400}"#)!), [400, 260])
    }

    func testSummary() {
        let raw = [#"{"type":"math","id":"eq1","tex":"Zn \\to Zn^{2+} + 2e^-"}"#, #"{"type":"text","text":"no id, not listed"}"#,
                   #"{"type":"arrow","id":"a1","from":"eq1","to":"g1","label":"loses electrons"}"#, #"{"type":"chem","id":"m1","kind":"lewis","molecule":"H2O"}"#,
                   #"{"type":"circle","id":"c1","on":"screen","target":[1,2,3,4]}"#, #"{"type":"text","id":"gone","text":"later erased"}"#, #"{"type":"erase","target":"gone"}"#]
        let steps = raw.compactMap(step)
        XCTAssertEqual(TutorSteps.summarize(steps, boxes: ["eq1": TutorBox(100.4, 100, 200, 40)]).components(separatedBy: "\n"),
                       ["eq1 math \"Zn \\to Zn^{2+} + 2e^-\" at 100,100,200,40", "a1 arrow \"loses electrons\"", "m1 chem \"lewis H2O\"", "c1 circle (screen)"])
    }

    // MARK: drawing

    func f(_ src: String, _ x: Double) -> Double { try! TutorDraw.compileFn(src)(x) }

    func testFunctions() {
        XCTAssertEqual([f("x^2-3", 2), f("2x", 3), f("-x^2", 3), f("2^-1", 0), f("3(x+1)", 1), f("y = x/2", 4)], [1, 6, -9, 0.5, 6, 2])
        XCTAssertEqual(f("ln x", M_E), 1, accuracy: 1e-12)
        XCTAssertEqual([f("sqrt(x)", 9), f("|x-5|", 2), f("e^x", 0)], [3, 3, 1])
        XCTAssertEqual(f("2pix", 1), 2 * Double.pi, accuracy: 1e-9)
        XCTAssertEqual(f("xsinx", Double.pi / 2), Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual([f("x² − 1", 3), f("2·x", 4)], [8, 8])
        XCTAssertTrue(f("π", 0) > 3.14)
        XCTAssertTrue(f("1/x", 0).isNaN && f("ln x", -1).isNaN)
        for bad in ["eval(1)", "x +", "(x", "alert", ""] { XCTAssertThrowsError(try TutorDraw.compileFn(bad), bad) }
    }

    func testStrokes() {
        var l = TutorDraw.Line(points: [[0, 0], [90, 0]], color: "#D93025", width: 3)
        let st = TutorDraw.inkStroke(l)
        XCTAssertEqual(st.ink, "com.apple.ink.monoline")
        XCTAssertEqual(st.color, "#D93025FF")
        XCTAssertTrue(st.points.allSatisfy { $0.count == 9 && $0[6] == 3 })
        XCTAssertEqual(TutorDraw.strokeTime(st), 90 / TutorDraw.speed, accuracy: 1e-3)
        XCTAssertNil(TutorDraw.strokeUpTo(st, 0))
        XCTAssertEqual(TutorDraw.strokeUpTo(st, 1), st)
        XCTAssertLessThan(TutorDraw.strokeUpTo(st, TutorDraw.strokeTime(st) / 2)!.points.count, st.points.count)
        l.ink = TutorDraw.marker
        XCTAssertTrue(TutorDraw.inkStroke(l, alpha: 0.5).color.hasSuffix("80"))
        XCTAssertEqual(TutorDraw.densify([[0, 0], [10, 0], [10, 10]], step: 100, corners: true).filter { $0 == [10, 0] }.count, 3)
        let ar = TutorDraw.arrowLines([0, 0], [100, 0])
        XCTAssertEqual(ar.count, 2)
        XCTAssertEqual(ar[1][1], [100, 0])
        XCTAssertEqual(TutorDraw.arrowLines([0, 0], [100, 0], both: true).count, 3)
        XCTAssertEqual(TutorDraw.arrowLines([0, 0], [100, 0], head: false).count, 1)
        let bent = TutorDraw.arrowLines([0, 0], [100, 0], bend: 0.5)[0]
        XCTAssertTrue(bent.count > 10 && bent.map { abs($0[1]) }.max()! > 10 && bent.last![0] == 100 && bent[0][0] == 0)
        XCTAssertEqual((TutorDraw.arrowLines([0, 0], [100, 0], bend: -0.5)[0][12][1]).sign == .minus, bent[12][1].sign != .minus)
        XCTAssertEqual(TutorDraw.dashes([[0, 0], [100, 0]]).count, 6)
    }

    /// The laptop's own numbers for the same box and graph (its random wobble included).
    func testMarksAndGraphMatchTheLaptop() {
        let c = TutorDraw.markLines("circle", TutorBox(10, 20, 100, 40))[0]
        XCTAssertEqual(c.count, 73)
        XCTAssertEqual(c[0].map { TutorSteps.jsRound($0 * 1000) / 1000 }, [37.113, 7.255])
        XCTAssertEqual(c[36].map { TutorSteps.jsRound($0 * 1000) / 1000 }, [66.793, 75.325])
        let g = TutorDraw.graphPlan(step(#"{"type":"graph","fns":[{"fn":"x^2-3","label":"y"}],"x":[-4,4],"points":[[0,-3,"min"]]}"#)!, box: TutorBox(0, 0, 320, 220))
        XCTAssertEqual(g.lines.count, 22)
        XCTAssertEqual(g.labels.map(\.text), ["−4", "−3", "−2", "1", "2", "3", "−4", "−2", "2", "4", "6", "8", "10", "12", "0", "y", "min"])
        XCTAssertEqual(g.yRange[0], -4.51, accuracy: 1e-9)
        XCTAssertEqual(g.yRange[1], 13.73, accuracy: 1e-9)
        XCTAssertNil(g.error)
    }

    // MARK: teaching gestures (the laptop's dev/unit-tutor.mjs cases and its own numbers)

    func testInsideTargetsAnglesAndBrief() {
        XCTAssertEqual([#"{"in":"eq1","part":" (x+3) "}"#, #"{"in":"g1","at":[2,"-1"]}"#, #"{"in":"$last"}"#].map { step(#"{"type":"circle","target":"# + $0 + "}")!.target },
                       [.inside(TutorInside(id: "eq1", part: "(x+3)")), .inside(TutorInside(id: "g1", at: [2, -1])), .inside(TutorInside(id: "last"))])
        XCTAssertEqual(step(#"{"type":"box","target":"$last"}"#)!.target, .id("last"), "\"$last\" names the last block")
        XCTAssertEqual(step(#"{"type":"arrow","from":{"in":"g1","at":[0,1]},"to":"eq1"}"#)!.from, .inside(TutorInside(id: "g1", at: [0, 1])))
        XCTAssertEqual([#"{"type":"point","target":"a"}"#, #"{"type":"point","target":"a","brief":false}"#, #"{"type":"circle","target":"a","brief":true}"#,
                        #"{"type":"circle","target":"a"}"#, #"{"type":"math","tex":"x","brief":true}"#].map { step($0)!.brief }, [true, false, true, false, false])
        let ang = step(#"{"type":"angle","at":[10,10],"from":[0,10],"to":"eq1","right":true,"label":"θ"}"#)!
        XCTAssertEqual([ang.vertex, ang.from, ang.to], [.point(10, 10), .point(0, 10), .id("eq1")])
        XCTAssertTrue(ang.right)
        XCTAssertEqual(ang.label, "θ")
        XCTAssertEqual(problem(#"{"type":"angle","from":[0,0],"to":[1,1]}"#), "angle needs at (the corner), from and to (a point along each side)")
        XCTAssertEqual(problem(#"{"type":"circle"}"#), #"circle needs target: an id, [x, y, w, h], [x, y] or {"in": id, "part"|"at": ...}"#)
        XCTAssertEqual(problem(#"{"type":"circle","target":{"in":"bad id"}}"#), #"circle needs target: an id, [x, y, w, h], [x, y] or {"in": id, "part"|"at": ...}"#)
        let a2 = step(#"{"type":"angle","at":"$last","from":{"in":"g1","at":[1,2]},"to":{"of":"a"},"width":3,"brief":true}"#)!
        XCTAssertEqual([a2.vertex, a2.from, a2.to], [.id("last"), .inside(TutorInside(id: "g1", at: [1, 2])), .of("a", side: "center", dx: nil, dy: nil)])
        XCTAssertEqual(a2.width, 3)
        XCTAssertTrue(a2.brief)
        // a closed path: one that ends where it starts drops the repeat and closes, unless it says not
        let shut = step(#"{"type":"path","points":[[0,0],[10,0],[10,10],[0,0]]}"#)!
        XCTAssertEqual(shut.points, [[0, 0], [10, 0], [10, 10]])
        XCTAssertTrue(shut.closed)
        XCTAssertNil(shut.smooth)
        XCTAssertFalse(step(#"{"type":"path","points":[[0,0],[10,0],[10,10],[0,0]],"closed":false}"#)!.closed)
        XCTAssertEqual(step(#"{"type":"path","points":[[0,0],[10,0],[0,0]]}"#)!.points.count, 3, "three points are not a closed shape")
        XCTAssertEqual(step(#"{"type":"path","points":[[0,0],[10,0]],"smooth":true}"#)!.smooth, true)
        // a side of a block as a target
        XCTAssertEqual(step(#"{"type":"point","target":{"of":"eq1","side":"top"}}"#)!.target, .of("eq1", side: "top", dx: nil, dy: nil))
        XCTAssertEqual(TutorSteps.resolveTarget(.of("eq1", side: "top", dx: nil, dy: nil), { _ in TutorBox(0, 0, 100, 40) }), TutorBox(50, 0, 0, 0))
        // resolving inside: the words found (or nothing); a graph point
        let look = TutorLookup(get: { ["eq1": TutorBox(100, 100, 200, 40), "g1": TutorBox(0, 0, 380, 260)][$0] },
                               part: { _, t in t == "x" ? TutorBox(150, 110, 10, 20) : nil }, graphAt: { _, p in [p[0] * 10, p[1] * 10] })
        XCTAssertEqual([TutorInside(id: "eq1", part: "x"), TutorInside(id: "eq1", part: "zz"), TutorInside(id: "g1", at: [2, 3]), TutorInside(id: "nope", part: "x")]
            .map { TutorSteps.resolveTarget(.inside($0), look) }, [TutorBox(150, 110, 10, 20), nil, TutorBox(20, 30, 0, 0), nil], "words not in the block: nothing, not the whole block")
        XCTAssertEqual(TutorSteps.insideBox(TutorInside(id: "eq1", part: "zz"), TutorLookup(get: look.get)), TutorBox(100, 100, 200, 40), "without a part finder: the whole block")
        var ln = TutorStep(type: "line"); ln.from = .inside(TutorInside(id: "eq1", part: "x")); ln.to = .point(155, 300)
        let e = TutorSteps.resolveEnds(ln, look)!
        XCTAssertEqual([r(e.0), r(e.1)], [[155, 133], [155, 300]], "a line from inside a block aims from the words' edge")
        ln.from = .inside(TutorInside(id: "g1", at: [3, 4])); ln.to = .id("eq1")
        let e2 = TutorSteps.resolveEnds(ln, look)!
        XCTAssertEqual([r(e2.0), r(e2.1)], [[30, 40], [144.75, 94]])
    }

    func testPlacement() {
        XCTAssertEqual(TutorSteps.freeSpot([0, 0], size: [100, 40], taken: [TutorBox(0, 20, 200, 30), TutorBox(50, 55, 30, 30), TutorBox(500, 0, 10, 10)]), [0, 95])
        XCTAssertEqual(TutorSteps.freeSpot([300, 0], size: [100, 40], taken: [TutorBox(0, 20, 200, 30)]), [300, 0])
        XCTAssertEqual(TutorSteps.nextFlow([0, 300], at: .point(420, 20), box: TutorBox(420, 20, 200, 40)), [420, 84], "after a block at a point, the next goes under it")
        XCTAssertEqual(TutorSteps.nextFlow([0, 300], at: .beside("right", "a", gap: nil), box: TutorBox(420, 20, 200, 40)), [0, 300])
        XCTAssertEqual(TutorSteps.nextFlow([0, 30], at: .beside("right", "a", gap: nil), box: TutorBox(420, 20, 200, 400)), [0, 444])
        XCTAssertEqual(TutorSteps.nextFlow(nil, at: nil, box: TutorBox(5, 6, 10, 10)), [5, 40])
        XCTAssertEqual(TutorSteps.nextFlow([0, 300], at: .beside("below", "a", gap: nil), box: TutorBox(420, 20, 200, 40)), [420, 84])
        XCTAssertEqual(TutorSteps.placeBlock(.point(0, 900), size: [100, 40], { _ in nil }, flow: [0, 100]), [0, 148], "a block at a point far below the rest comes up near it")
        XCTAssertEqual(TutorSteps.placeBlock(.point(10, 50), size: [100, 40], { _ in nil }, frame: [5, 5], flow: [0, 100]), [15, 55])
        XCTAssertEqual(TutorSteps.placeBlock(.point(0, 900), size: [100, 40], { _ in nil }), [0, 900])
    }

    func testArrowsLabelsAndAngles() {
        XCTAssertEqual(TutorDraw.columnArrow(TutorBox(0, 0, 200, 30), TutorBox(0, 54, 180, 30)), .init(from: [206, 15], to: [188, 69], outX: 236.48))
        XCTAssertNil(TutorDraw.columnArrow(TutorBox(0, 0, 200, 30), TutorBox(0, 154, 180, 30)), "far apart with nothing between: a straight arrow")
        XCTAssertEqual(TutorDraw.columnArrow(TutorBox(0, 0, 200, 30), TutorBox(0, 154, 180, 30), others: [TutorBox(0, 70, 300, 40)]), .init(from: [206, 15], to: [188, 169], outX: 348.48))
        XCTAssertEqual(TutorDraw.columnArrow(TutorBox(0, 200, 200, 30), TutorBox(0, 154, 180, 30)), .init(from: [206, 215], to: [188, 169], outX: 235.52))
        XCTAssertNil(TutorDraw.columnArrow(TutorBox(0, 0, 100, 30), TutorBox(300, 0, 100, 30)), "side by side: not a column")
        XCTAssertEqual(r(TutorDraw.arrowLines([206, 15], [188, 69], outX: 236.48)[0][12]), [226.61, 42])
        XCTAssertTrue(TutorDraw.crossesBox([0, 0], [100, 100], TutorBox(40, 40, 20, 20)))
        XCTAssertFalse(TutorDraw.crossesBox([0, 0], [100, 0], TutorBox(40, 40, 20, 20)))
        XCTAssertEqual(TutorDraw.longEnough([0, 0], [10, 0]), [-46, 0])
        XCTAssertEqual(TutorDraw.longEnough([0, 0], [100, 0]), [0, 0])
        XCTAssertEqual(r(TutorDraw.longEnough([5, 5], [5, 5])), [-28.6, -39.8])
        XCTAssertEqual(TutorDraw.labelAt([[0, 0], [100, 0]], off: 10, side: -1), [50, 10], "labelAt: the other side")
        XCTAssertEqual(TutorDraw.labelAt([[0, 0], [100, 0]], off: 6, size: [40, 20]), [50, -16])
        XCTAssertEqual(TutorDraw.labelAt([[0, 0], [100, 100]], off: 6, size: [40, 20], side: -1).map { TutorSteps.jsRound($0 * 1000) / 1000 }, [30.757, 69.243])
        XCTAssertTrue(TutorDraw.isMathLabel("y = e^x") && TutorDraw.isMathLabel("a_2") && TutorDraw.isMathLabel("\\theta") && !TutorDraw.isMathLabel("y = x + 2"))
        let right = TutorDraw.angleLines([0, 0], [50, 0], [0, -50], right: true)
        XCTAssertEqual(right.lines, [[[16, 0], [16, -16], [0, -16]]], "a right angle is a small square in the corner")
        XCTAssertEqual(right.label[0], 25.851823920180177, accuracy: 1e-9)
        XCTAssertEqual(right.label[1], -25.851823920180177, accuracy: 1e-9)
        let arc = TutorDraw.angleLines([10, 10], [80, 10], [60, -40])
        XCTAssertEqual(arc.lines[0].count, 7)
        XCTAssertEqual(arc.lines[0].last!.map { TutorSteps.jsRound($0 * 1000) / 1000 }, [28.385, -8.385])
        XCTAssertEqual(arc.label.map { TutorSteps.jsRound($0 * 1000) / 1000 }, [46.955, -5.307])
        // a wide line gets an oval just wider than it; a big block a loop close round it
        let wide = TutorDraw.markLines("circle", TutorBox(0, 0, 500, 50))[0]
        XCTAssertEqual(wide.count, 73)
        XCTAssertEqual(wide[0].map { TutorSteps.jsRound($0 * 1000) / 1000 }, [164.337, -14.236])
        XCTAssertEqual(wide[36].map { TutorSteps.jsRound($0 * 1000) / 1000 }, [275.309, 67.132])
        XCTAssertEqual(TutorDraw.markLines("circle", TutorBox(0, 0, 200, 200))[0][0].map { TutorSteps.jsRound($0 * 1000) / 1000 }, [63.963, -10.912])
    }

    func testMathRuns() {
        XCTAssertEqual(["y = e^x and ln x.", "already $x^2$", "snake_case", "H_2O", "2^10 = 1024", "a_{n+1}", "see `x^2` and [a](b_c) then x^-1, (x+1)^2 is k_B."].map(TutorDraw.mathRuns),
                       ["y = $e^x$ and ln x.", "already $x^2$", "snake_case", "$H_2O$", "$2^{10}$ = 1024", "$a_{n+1}$", "see `x^2` and [a](b_c) then $x^{-1}$, $(x+1)^2$ is $k_B$."])
    }

    typealias Lab = (String, Double, Double, String, String)
    func assertLabels(_ got: [TutorDraw.GraphLabel], _ want: [Lab], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.map(\.text), want.map(\.0), file: file, line: line)
        for (g, w) in zip(got, want) {
            XCTAssertEqual(g.x, w.1, accuracy: 0.002, g.text, file: file, line: line)
            XCTAssertEqual(g.y, w.2, accuracy: 0.002, g.text, file: file, line: line)
            XCTAssertEqual([g.anchor, g.color], [w.3, w.4], g.text, file: file, line: line)
        }
    }

    func testGraphLabelsAndGeometryMatchTheLaptop() {
        let grey = "#6B6B6B"
        let trig = TutorDraw.graphPlan(step(#"{"type":"graph","fn":"sin x","x":[-3.5,3.5]}"#)!, box: TutorBox(10, 20, 380, 260))
        XCTAssertEqual(trig.lines.count, 13)
        assertLabels(trig.labels, [("−π", 57.306, 157.4, "center", grey), ("−π/2", 133.153, 157.4, "center", grey), ("π/2", 284.847, 157.4, "center", grey),
                                   ("π", 360.694, 157.4, "center", grey), ("−1", 203, 230.604, "right", grey), ("−0.5", 203, 182.802, "right", grey),
                                   ("0.5", 203, 87.198, "right", grey), ("1", 203, 39.396, "right", grey), ("0", 204, 147, "right", grey)])
        XCTAssertEqual([trig.geom.X0, trig.geom.X1, trig.geom.Y0, trig.geom.Y1], [40, 378, 30, 258])
        XCTAssertEqual(trig.geom.y[1], 1.1924192401898241, accuracy: 1e-12)
        let two = TutorDraw.graphPlan(step(#"{"type":"graph","fns":[{"fn":"x","label":"y = x"},{"fn":"x+2","label":"y = x + 2"}],"x":[-3,3],"points":[[1,3,"P"]],"xLabel":"t / s","yLabel":"y"}"#)!, box: TutorBox(0, 0, 380, 260))
        XCTAssertEqual(two.lines.count, 21)
        XCTAssertEqual(two.lines.last!.color, "#D93025", "a point takes the colour of the curve it is on")
        let ink = "#1B1B1B"
        assertLabels(two.labels, [("−3", 30, 163.427, "center", grey), ("−2", 79.042, 163.427, "center", grey), ("−1", 128.083, 163.427, "center", grey),
                                  ("1", 226.167, 163.427, "center", grey), ("2", 275.208, 163.427, "center", grey), ("−3", 171.125, 219.11, "right", grey),
                                  ("−2", 171.125, 193.082, "right", grey), ("−1", 171.125, 167.055, "right", grey), ("1", 171.125, 115, "right", grey),
                                  ("2", 171.125, 88.973, "right", grey), ("3", 171.125, 62.945, "right", grey), ("4", 171.125, 36.918, "right", grey),
                                  ("5", 171.125, 10.89, "right", grey), ("0", 172.125, 153.027, "right", grey), ("t / s", 338.25, 150.027, "leftmid", ink),
                                  ("y", 185.125, 0, "left", ink), ("y = x", 309.668, 52.5, "right", "#1F5FD1"), ("y = x + 2", 309.668, 0.445, "right", "#D93025"),
                                  ("P", 219.167, 51.745, "right", "#D93025")])
        XCTAssertEqual([two.geom.X0, two.geom.X1, two.geom.Y0, two.geom.Y1], [30, 324.25, 10, 238])
        XCTAssertEqual(two.geom.y[0], -3.38, accuracy: 1e-9)
        XCTAssertEqual(two.geom.y[1], 5.38, accuracy: 1e-9)
        XCTAssertEqual(TutorDraw.graphPoint(two.geom, [1, 3]).map { TutorSteps.jsRound($0 * 1000) / 1000 }, [226.167, 71.945])
        XCTAssertEqual(TutorDraw.graphPoint(two.geom, [two.geom.x[0], two.geom.y[0]]), [two.geom.X0, two.geom.Y1], "a graph's corner is the plot's")
    }

    /// The laptop's third review (nexus a34f457): colours in maths, graphs drawn into, dashed curves, true circles, nested angles, notes
    /// level with their line, a far point no lower than just under the ink.
    func testColoursCurvesAndCirclesMatchTheLaptop() {
        let tex = [#"a + \color{blue}{u} + b"#, #"\color{red} x"#, #"\textcolor{green}{y}"#, #"\color { #a1b2c3 } {z}"#, #"\color{teal}{w}"#, #"\textcolor{blue} q"#]
        let want = [#"a + \textcolor{#1F5FD1}{u} + b"#, #"\color{#D93025} x"#, #"\textcolor{#188038}{y}"#, #"\textcolor{#A1B2C3}{z}"#, #"\textcolor{teal}{w}"#, #"\textcolor{#1F5FD1} q"#]
        XCTAssertEqual(tex.map(TutorSteps.texColors), want)
        XCTAssertEqual(tex.map { TutorSteps.normalize(.object([("type", .string("math")), ("tex", .string("$" + $0 + "$"))]))?.tex }, want)
        XCTAssertEqual(step(#"{"type":"text","text":"see $\\color{red}{x}$ and \\color{red}"}"#)!.text, #"see $\textcolor{#D93025}{x}$ and \color{red}"#, "only maths in a text block")
        XCTAssertEqual(step(#"{"type":"text","text":"a $$\\color{blue}{u}$$ b $\\color{green}{v}$"}"#)!.text, #"a $$\textcolor{#1F5FD1}{u}$$ b $\textcolor{#188038}{v}$"#)
        // a graph drawn into another: no place of its own; a dashed curve
        let gin = step(#"{"type":"graph","in":"g1","fns":[{"fn":"x","dash":true},{"fn":"x+1","dash":"yes"}],"at":[1,2],"w":300,"h":200}"#)!
        XCTAssertEqual(gin.into, "g1")
        XCTAssertNil(gin.at); XCTAssertNil(gin.w); XCTAssertNil(gin.h)
        XCTAssertEqual(gin.fns.map(\.dash), [true, false])
        XCTAssertEqual(step(#"{"type":"graph","in":"$last","fn":"x"}"#)!.into, "last")
        let bad = step(#"{"type":"graph","in":"bad id","fn":"x","at":[1,2]}"#)!
        XCTAssertNil(bad.into); XCTAssertEqual(bad.at, .point(1, 2))
        // a true circle: its centre and radius
        let c = step(#"{"type":"circle","at":[100,50],"r":40}"#)!
        XCTAssertEqual(c.vertex, .point(100, 50)); XCTAssertEqual(c.r, 40)
        XCTAssertNil(c.target)
        let c2 = step(#"{"type":"circle","at":"eq1","r":4000,"label":"O","brief":true}"#)!
        XCTAssertEqual(c2.vertex, .id("eq1")); XCTAssertEqual(c2.r, 2000); XCTAssertTrue(c2.brief)
        let c3 = step(#"{"type":"circle","at":[1,2],"r":5,"target":"eq1"}"#)!
        XCTAssertEqual(c3.target, .id("eq1")); XCTAssertNil(c3.r)
        for raw in [#"{"type":"circle","at":[1,2],"r":0}"#, #"{"type":"circle","r":5}"#] {
            XCTAssertEqual(problem(raw), #"circle needs target: an id, [x, y, w, h], [x, y] or {"in": id, "part"|"at": ...}"#)
        }
        // placing: beside a tall picture, level with its top; a far point no lower than just under the ink
        let boxes = ["eq1": TutorBox(100, 100, 200, 40), "g1": TutorBox(100, 300, 320, 220)]
        XCTAssertEqual(TutorSteps.placeBlock(.beside("right", "g1", gap: nil), size: [50, 10], { boxes[$0] }), [444, 300])
        XCTAssertEqual([(900.0, 400.0), (900, 50), (300, 400)].map { TutorSteps.placeBlock(.point(0, $0.0), size: [100, 40], { _ in nil }, flow: [0, 100], low: $0.1) },
                       [[0, 448], [0, 148], [0, 300]])
        // a second angle at a corner: a wider arc
        let m = TutorDraw.angleLines([10, 10], [80, 10], [60, -40], more: 10)
        XCTAssertEqual(m.lines[0].count, 9)
        XCTAssertEqual(m.lines[0].last!.map { TutorSteps.jsRound($0 * 1000) / 1000 }, [35.456, -15.456])
        XCTAssertEqual(m.label.map { TutorSteps.jsRound($0 * 1000) / 1000 }, [56.194, -9.134])
        let rm = TutorDraw.angleLines([0, 0], [50, 0], [0, -50], right: true, more: 10)
        XCTAssertEqual(rm.lines, [[[26, 0], [26, -26], [0, -26]]])
        XCTAssertEqual(rm.label.map { TutorSteps.jsRound($0 * 1000) / 1000 }, [35.822, -35.822])
        // more curves drawn into a graph: its axes and ranges, no axes or ticks again, colours on from its curves
        let base = TutorDraw.graphPlan(step(#"{"type":"graph","fns":[{"fn":"x^2","label":"y = x²"}],"x":[-3,3],"y":[-2,9]}"#)!, box: TutorBox(0, 0, 380, 260))
        XCTAssertEqual([base.lines.count, base.labels.count], [16, 12])
        XCTAssertEqual(base.geom, TutorDraw.GraphGeom(X0: 30, X1: 368, Y0: 10, Y1: 238, x: [-3, 3], y: [-2, 9], curves: 1))
        let into = TutorDraw.graphPlan(step(#"{"type":"graph","in":"g1","fns":[{"fn":"2x-1","label":"tangent"},{"fn":"-x","dash":true}],"points":[[1,1,"(1, 1)"]]}"#)!,
                                       box: TutorBox(999, 999, 10, 10), into: base.geom)
        XCTAssertEqual(into.lines.count, 23)
        XCTAssertEqual(into.lines.prefix(4).map { "\($0.color) \($0.width) \($0.points.count)" }, ["#D93025 2.5 145", "#188038 2.0 7", "#188038 2.0 8", "#188038 2.0 8"])
        XCTAssertEqual(into.lines.last!.color, "#D93025")
        assertLabels(into.labels, [("tangent", 356.367, 73.055, "right", "#D93025"), ("(1, 1)", 248.333, 155.618, "right", "#D93025")])
        XCTAssertEqual(into.geom, TutorDraw.GraphGeom(X0: 30, X1: 368, Y0: 10, Y1: 238, x: [-3, 3], y: [-2, 9], curves: 3))
        let dash = TutorDraw.graphPlan(step(#"{"type":"graph","fns":[{"fn":"x","dash":true}],"x":[-3,3],"y":[-3,3]}"#)!, box: TutorBox(0, 0, 380, 260))
        let dl = dash.lines.filter(\.curve)
        XCTAssertEqual([dash.lines.count, dl.count], [44, 28])
        XCTAssertEqual(dl[0].points.map { $0.map { TutorSteps.jsRound($0 * 1000) / 1000 } }, [[30, 238], [31.408, 237.05], [32.817, 236.1], [34.225, 235.15], [35.633, 234.2], [37.042, 233.25], [37.461, 232.967]])
        XCTAssertEqual(dl[0].width, 2)
        XCTAssertEqual(dl.last!.points.last!, [368, 10])
    }

    // MARK: reading a reply

    func testSentences() {
        XCTAssertEqual(TutorReader.speakable("**Bold** and `code` cost $5, see [the page](http://x)."), "Bold and code cost 5, see the page.")
        XCTAssertEqual(TutorReader.speakable("- first point"), "first point")
        XCTAssertEqual(TutorReader.sentenceEnd("One. Two"), 4)
        XCTAssertEqual(TutorReader.sentenceEnd("Take e.g. this one. Next"), 19)
        XCTAssertEqual(TutorReader.sentenceEnd("See Fig. 3 here. Next"), 16)
        XCTAssertEqual(TutorReader.sentenceEnd("It is 2.5 moles"), -1)
        XCTAssertEqual(TutorReader.sentenceEnd("No stop here", final: true), 12)
        let s = String(repeating: "word ", count: 30) + ", " + String(repeating: "more ", count: 30)
        let e = TutorReader.sentenceEnd(s)
        XCTAssertTrue(e > 60 && e <= 221, "\(e)")
    }

    static let reply = "First, look here. Mn is reduced, e.g. it gains 5 electrons.\n<step>{\"type\":\"math\",\"id\":\"e1\",\"tex\":\"MnO_4^-\"}</step>\nThat is reduction!<step>{\"type\":\"circle\",\"on\":\"screen\",\"area\":\"c2\",\"label\":\"the ion\"}</step>\n<step>{oops}</step><step>{\"type\":\"nope\"}</step>Done"

    func testReadsAReply() {
        let whole = TutorReader.read(TutorTests.reply)
        XCTAssertEqual(whole.said, ["First, look here.", "Mn is reduced, e.g. it gains 5 electrons.", "That is reduction!", "Done"])
        XCTAssertEqual(whole.steps.map(\.type), ["math", "circle"])
        XCTAssertEqual(whole.steps[1].area, "C2")
        XCTAssertEqual(whole.problems.map(\.problem), ["not JSON", "unknown type \"nope\""])
        let chars = Array(TutorTests.reply)
        for size in [1, 3, 7, 50] {
            let r = TutorReader()
            var ev: [TutorEvent] = []
            var i = 0
            while i < chars.count { ev += r.push(String(chars[i..<min(chars.count, i + size)])); i += size }
            ev += r.end()
            XCTAssertEqual(ev, whole.events, "pieces of \(size)")
        }
        XCTAssertEqual(TutorSteps.beats(whole.events).map { [$0.say ?? "", String($0.steps.count)] },
                       [["First, look here.", "0"], ["Mn is reduced, e.g. it gains 5 electrons.", "1"], ["That is reduction!", "1"], ["Done", "0"]])
    }

    func testEventsComeAsSoonAsTheyCan() {
        var r = TutorReader()
        XCTAssertEqual(r.push("Hello there. Ne"), [.say("Hello there.", n: 0)])
        XCTAssertEqual(r.push("xt\n<step>{\"type\":\"text\",\"te").count, 0)
        var t = TutorStep(type: "text"); t.text = "hi"
        XCTAssertEqual(r.push("xt\":\"hi\"}</step> more"), [.say("Next", n: 1), .step(t)])
        r = TutorReader()
        _ = r.push("The")
        let ev = r.push(" arrow <step>{\"type\":\"text\",\"text\":\"b\"}</step> shows it. ") + r.end()
        XCTAssertEqual(ev.map { e -> String in if case .say(let s, _) = e { return s }; if case .step(let s) = e { return s.type }; return "" }, ["text", "The arrow shows it."])
        r = TutorReader()
        _ = r.push("Cut <step>{\"type\":\"te")
        XCTAssertEqual(r.end(), [.say("Cut", n: 0)])
        XCTAssertEqual(r.problems.map(\.problem), ["cut off"])
    }

    // MARK: sessions

    func testSessionFileIsTheLaptops() {
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let d = utc.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9, minute: 5))!
        XCTAssertEqual(TutorSession.topic("Why is MnO4- reduced here: in the redox titration of iron?"), "Why is MnO4- reduced here in the redox")
        XCTAssertEqual(TutorSession.path(at: d, words: "why is this reduced?", calendar: utc), "notebooks/Tutor/2026-11-11 0905 why is this reduced.board")
        XCTAssertEqual(TutorSession.path(at: d, words: "x", taken: { $0 == "notebooks/Tutor/2026-11-11 0905 x.board" }, calendar: utc), "notebooks/Tutor/2026-11-11 0905 x (2).board")
        XCTAssertEqual(TutorSession.path(at: d, words: "", calendar: utc), "notebooks/Tutor/2026-11-11 0905.board")
        var s = TutorSession(at: d)
        s.add(.init(at: d, you: "why is this reduced?", reply: "Because. <step>{\"type\":\"text\",\"text\":\"x\"}</step>", mode: "plan", model: "sonnet", ms: 812, sessionId: "sess-1"))
        XCTAssertEqual([s.title, s.sessionId], ["why is this reduced", "sess-1"])
        XCTAssertEqual(s.planResume, "sess-1")
        s.add(.init(at: d.addingTimeInterval(1), you: "and iron?", reply: "Iron is oxidised.", mode: "api", model: "claude-sonnet-5-5", cost: 0.0123456789))
        XCTAssertNil(s.planResume, "after an API turn plan mode starts afresh")
        XCTAssertTrue(s.recap().contains("Student: why is this reduced?\nYou: Because"))
        XCTAssertEqual(s.history().map { [$0.role, String($0.text.prefix(8))] }, [["user", "why is t"], ["assistant", "Because."], ["user", "and iron"], ["assistant", "Iron is "]])
        XCTAssertEqual(s.history(max: 1).count, 2)
        // byte for byte what the laptop's session.js serialize writes for the same session
        let laptop = "{\n \"format\": \"nexus-tutor/1\",\n \"created\": \"2026-11-11T09:05:00.000Z\",\n \"title\": \"why is this reduced\",\n \"sessionId\": \"sess-1\",\n \"turns\": [\n  {\n   \"at\": \"2026-11-11T09:05:00.000Z\",\n   \"you\": \"why is this reduced?\",\n   \"reply\": \"Because. <step>{\\\"type\\\":\\\"text\\\",\\\"text\\\":\\\"x\\\"}</step>\",\n   \"mode\": \"plan\",\n   \"model\": \"sonnet\",\n   \"ms\": 812\n  },\n  {\n   \"at\": \"2026-11-11T09:05:01.000Z\",\n   \"you\": \"and iron?\",\n   \"reply\": \"Iron is oxidised.\",\n   \"mode\": \"api\",\n   \"model\": \"claude-sonnet-5-5\",\n   \"cost\": 0.012346\n  }\n ]\n}\n"
        XCTAssertEqual(s.serialized, laptop)
        let back = TutorSession.parse(laptop)
        XCTAssertTrue(back.ok)
        XCTAssertEqual(back.session, s)
        XCTAssertEqual(back.session.steps.map(\.type), ["text"])
        XCTAssertTrue(TutorSession.parse(nil).fresh)
        XCTAssertFalse(TutorSession.parse("{").ok)
        let newer = TutorSession.parse("{\"format\":\"nexus-tutor/2\"}")
        XCTAssertTrue(!newer.ok && newer.newer)
        XCTAssertEqual(JSONValue.object([("a", .array([])), ("b", .object([]))]).indented(), "{\n \"a\": [],\n \"b\": {}\n}")
    }

    func testIPadTurn() {
        let t = TutorPrompt.iPadTurn(words: "is this right?", board: "e1 math \"x\"", view: TutorBox(-600, -40, 1100, 800),
                                     handwriting: [.init(text: "2H2 + O2", box: TutorBox(-500.4, 10, 220, 40))], typed: [.init(text: "Notes", box: TutorBox(-500, -30, 80, 20))])
        XCTAssertTrue(t.contains("from x -600 to 500 and y -40 to 760"), t)
        XCTAssertTrue(t.contains("\"2H2 + O2\" at [-500, 10, 220, 40]"), t)
        XCTAssertTrue(t.contains("<typed>") && t.contains("Already on the board") && t.hasSuffix("They said: is this right?"))
        XCTAssertTrue(TutorPrompt.iPadTurn(words: "").contains("No picture of the board"))
        XCTAssertTrue(TutorPrompt.iPadTurn(words: "", view: TutorBox(0, 0, 10, 10)).contains("said nothing you could hear"))
    }

    func testWhereATurnGoes() {
        let v = TutorBox(0, 0, 1000, 800)
        XCTAssertEqual(TutorPrompt.frame(visible: v, content: []), [40, 40], "an empty view: near its top-left")
        XCTAssertEqual(TutorPrompt.frame(visible: v, content: [TutorBox(50, 100, 300, 200)]), [398, 100], "room on the right: beside it")
        XCTAssertEqual(TutorPrompt.frame(visible: v, content: [TutorBox(50, 100, 800, 200)]), [50, 348], "no room: below it")
        XCTAssertEqual(TutorPrompt.frame(visible: v, content: [TutorBox(5000, 0, 10, 10)]), [40, 40], "what is out of view doesn't count")
    }

    // MARK: recordings

    func testRecording() {
        var r = BoardRecording(id: "r1", started: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(r.file, "files/recording-r1.m4a")
        r.markStroke("s1", at: 1.04)
        r.markStroke("s1", at: 9)
        r.markStroke("s2", at: 5)
        r.markTyped(item: "t1", text: "Oxidation is", at: 10)
        r.markTyped(item: "t1", text: "loss", at: 11.5)
        r.markTyped(item: "t1", text: "reduction is gain", at: 30)
        r.duration = 42.37
        XCTAssertEqual(r.marks.count, 4, "a stroke once; typing close together joins")
        XCTAssertEqual(r.time(ofStroke: "s1"), 1)
        XCTAssertEqual(r.time(ofItem: "t1", word: "Gain,"), 30)
        XCTAssertEqual(r.time(ofItem: "t1", word: "loss"), 10)
        XCTAssertEqual(r.time(ofItem: "t1"), 10)
        XCTAssertNil(r.time(ofStroke: "nope"))
        let md = "Oxidation is loss\nof electrons\n\nreduction is gain"
        XCTAssertEqual(r.time(ofItem: "t1", markdown: md, fraction: 0.05), 10, "a tap at the top: the first words")
        XCTAssertEqual(r.time(ofItem: "t1", markdown: md, fraction: 0.95), 30, "a tap at the bottom: the last")
        XCTAssertEqual(r.strokesNotYet(at: 3), ["s2"])
        XCTAssertEqual(r.itemsNotYet(at: 3), ["t1"])
        XCTAssertEqual(r.itemsNotYet(at: 10), [])
        let back = BoardRecording.parse(r.text)!
        XCTAssertEqual(back.marks, r.marks)
        XCTAssertEqual(back.duration, 42.4)
        XCTAssertTrue(r.text.hasPrefix("{\n \"format\": \"nexus-recording/1\",\n \"id\": \"r1\",\n \"file\": \"files/recording-r1.m4a\""))
        XCTAssertNil(BoardRecording.parse("{\"format\":\"nexus-recording/2\",\"id\":\"x\"}"))
        XCTAssertEqual(BoardRecording.addedText(old: "Oxidation is", new: "Oxidation is loss of"), "loss of")
        XCTAssertEqual(BoardRecording.addedText(old: "Oxidation is loss", new: "Oxidation is losss"), "losss", "a word typed into: the whole word")
        XCTAssertEqual(BoardRecording.addedText(old: "a b c", new: "a c"), "", "a deletion adds nothing")
        XCTAssertEqual(BoardRecording.addedText(old: "", new: "**Bold** start"), "Bold start")
    }

    func testTypingKeyByKey() {
        var r = BoardRecording(id: "r2", started: Date(timeIntervalSince1970: 0))
        var text = "", t = 20.0
        func type(_ s: String, gap: Double = 0.2) { for ch in s { let old = text; text.append(ch); r.typing(item: "b1", old: old, new: text, at: t); t += gap } }
        type("Oxidation is loss")
        XCTAssertEqual(r.marks.count, 1)
        XCTAssertEqual(r.marks[0].text, "Oxidation is loss", "the burst's words, not each key")
        XCTAssertEqual(r.marks[0].at, 20)
        t += 5
        type(" of electrons")
        XCTAssertEqual(r.marks.count, 2, "a pause of 3 s starts a new mark")
        XCTAssertEqual(r.marks[1].text, "of electrons")
        XCTAssertEqual(r.time(ofItem: "b1", word: "electrons"), r.marks[1].at)
        t += 5
        type(String(repeating: "a ", count: 40))
        XCTAssertGreaterThan(r.marks.count, 3, "long typing is split every 10 s")
        let old = text; text.removeLast(4)
        r.typing(item: "b1", old: old, new: text, at: t + 10)
        XCTAssertEqual(r.marks.last?.item, "b1")
        XCTAssertFalse(r.marks.contains { $0.text?.isEmpty ?? false }, "a deletion adds no mark")
    }
}
