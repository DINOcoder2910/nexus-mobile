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
            .map { TutorSteps.placeBlock($0, size: [50, 20], look) }, [[100, 164], [310, 100], [100, 56], [26, 100]])
        XCTAssertEqual(TutorSteps.placeBlock(nil, size: [50, 20], look, flow: [7, 9]), [7, 9])
        XCTAssertEqual(TutorSteps.placeBlock(.beside("below", "nope", gap: nil), size: [50, 20], look, flow: [7, 9]), [7, 9])
        let t = TutorSteps.estimateSize(step(#"{"type":"text","text":"a short line"}"#)!)
        XCTAssertEqual(t[1], 24)
        XCTAssertTrue(t[0] > 40 && t[0] < 120)
        var long = TutorStep(type: "text"); long.text = String(repeating: "x", count: 300)
        XCTAssertEqual(TutorSteps.estimateSize(long)[0], 560)
        XCTAssertEqual(TutorSteps.estimateSize(step(#"{"type":"graph","fn":"x","w":400}"#)!), [400, 220])
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
        XCTAssertEqual(g.labels.map(\.text), ["−4", "4", "12", "−4", "y", "min"])
        XCTAssertEqual(g.yRange[0], -4.51, accuracy: 1e-9)
        XCTAssertEqual(g.yRange[1], 13.73, accuracy: 1e-9)
        XCTAssertNil(g.error)
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
}
