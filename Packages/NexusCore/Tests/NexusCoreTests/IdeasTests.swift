import XCTest
@testable import NexusCore

/// Ideas (nexus docs/data-format.md "Ideas"): the file as the laptop writes it, the To-do list carried over with the laptop's ids, the
/// edits, grouping, the batch prompt and Claude's answer, the quoting the laptop's yaml package uses, and folding a conflict copy.
final class IdeasTests: XCTestCase {
    /// What the laptop's serializeIdeas wrote (renderer/src/ideas.js, the yaml package).
    let laptop = """
    # Ideas: anything you want to do or try. Claude sorts new ones into topics in batches; what you wrote stays in "text".
    # Edit them in Nexus (Customize › Ideas, the iPad's Ideas) or here.
    ideas:
      - id: t0abc123
        text: Make board text better. Typed text on boards is good for now; polish it later.
        title: Make board text better
        note: Typed text on boards is good for now; polish it later.
        topic: Nexus
        kind: nexus
        added: 2026-11-11
        organised: 2026-11-11
        who: claude
        sent: 2026-11-13
      - id: i5k9m2aa
        text: "run a 10k: before summer"
        title: Run a 10k before summer
        topic: Health
        kind: life
        added: 2026-11-13
        from: iPhone
        organised: 2026-11-13
        reply: |-
          Here is a start:
          - Pick a race date

          One question?
        edited: 2026-11-13T17:05:11Z
        mine: kept
      - id: i9x0c3de
        text: build a weather station
        added: 2026-11-13
        from: iPhone

    """

    func testReadsWhatTheLaptopWrites() {
        let p = Ideas.parse(laptop)
        XCTAssertNil(p.error)
        XCTAssertEqual(p.items.map(\.id), ["t0abc123", "i5k9m2aa", "i9x0c3de"])
        XCTAssertEqual(p.items[0].who, "claude")
        XCTAssertEqual(p.items[1].text, "run a 10k: before summer")
        XCTAssertEqual(p.items[1].reply, "Here is a start:\n- Pick a race date\n\nOne question?")
        XCTAssertEqual(p.items[1].extra, [Idea.Extra(key: "mine", yaml: "kept")])
        XCTAssertTrue(p.items[2].isWaiting)
    }

    func testWritesItBackLineForLine() {
        XCTAssertEqual(Ideas.serialize(Ideas.parse(laptop).items), laptop)
    }

    func testQuotingLikeTheLaptop() {
        // the laptop's yaml package (YAML 1.2 core schema), checked against it
        let cases: [(String, String)] = [("plain words", "plain words"), ("42", "\"42\""), ("3.5", "\"3.5\""), ("yes", "yes"), ("true", "\"true\""), ("null", "\"null\""),
            ("~", "\"~\""), ("2026-11-13", "2026-11-13"), ("a: b", "\"a: b\""), ("a #b", "\"a #b\""), ("#x", "\"#x\""), ("- x", "\"- x\""), ("[x", "\"[x\""),
            ("*x", "\"*x\""), ("'x", "\"'x\""), ("\"x", "'\"x'"), (" lead", "\" lead\""), ("trail ", "\"trail \""), ("it's", "it's"), ("say \"hi\"", "say \"hi\""),
            ("colon:end", "colon:end"), ("q?", "q?"), ("? x", "\"? x\""), ("x,y", "x,y"), ("", "\"\""), ("http://x.y", "http://x.y"), ("0x1F", "\"0x1F\""),
            ("1e3", "\"1e3\""), (".5", "\".5\""), ("-", "\"-\""), ("NaN", "NaN"), (".nan", "\".nan\""), ("on", "on"), ("12:30", "12:30"), ("a  b", "a  b"),
            ("x\u{7}", "\"x\\a\""), ("2026-11-13T17:05:11Z", "2026-11-13T17:05:11Z")]
        for (s, want) in cases { XCTAssertEqual(Ideas.scalar(s), want, s) }
    }

    func testToDosCarryOverWithTheLaptopsIds() {
        let p = Ideas.parse(nil, todo: "todos:\n  - title: Fix the planner\n    added: 2026-11-10\n  - title: Old thing\n    done: 2026-11-12\n")
        XCTAssertTrue(p.fromTodo)
        XCTAssertEqual(p.items.map(\.title), ["Fix the planner", "Old thing"])
        XCTAssertEqual(p.items.map(\.organised), ["2026-11-10", "to-do"])
        XCTAssertEqual(p.items[1].done, "2026-11-12")
        XCTAssertEqual(p.items[0].topic, "Nexus")
        XCTAssertEqual(p.items[0].id, Ideas.wordsId("Fix the planner", prefix: "t"))
        let starter = Ideas.parse(nil, todo: nil)
        XCTAssertEqual(starter.items.map(\.text), ["Make board text better. Typed text on boards is good for now; polish it later."])
    }

    func testWordsIdMatchesTheLaptop() {
        // dev/unit-ideas.mjs computes these with the laptop's wordsId
        XCTAssertEqual(Ideas.wordsId("Learn  to juggle"), Ideas.wordsId("learn to JUGGLE"))
        XCTAssertEqual(Ideas.wordsId("a"), "w" + String(UInt32(0xe40c292c), radix: 36).leftPad(7))
        XCTAssertTrue(Ideas.newId(taken: []).hasPrefix("i"))
    }

    func testEdits() {
        var items = Ideas.add([], "  an app that   reminds me\r\n\r\n\r\nto stretch ", today: "2026-11-13", now: "T", from: "iPhone")
        XCTAssertEqual(items[0].text, "an app that reminds me\n\nto stretch")
        XCTAssertEqual(items[0].from, "iPhone")
        XCTAssertEqual(Ideas.add(items, "   ", today: nil, now: nil, from: nil), items)
        let id = items[0].id
        items = Ideas.setWho(items, id, "me", now: "T2"); XCTAssertEqual(items[0].who, "me")
        items = Ideas.setWho(items, id, "me", now: "T3"); XCTAssertNil(items[0].who)
        items = Ideas.markSent(items, id, today: "2026-11-13", reply: " Plan ", now: "T4")
        XCTAssertEqual([items[0].who, items[0].sent, items[0].reply, items[0].edited], ["claude", "2026-11-13", "Plan", "T4"])
        items = Ideas.rename(items, id, " Stretch app ", now: nil); XCTAssertEqual(items[0].title, "Stretch app")
        items = Ideas.tick(items, id, today: "2026-11-14", now: nil); XCTAssertEqual(items[0].done, "2026-11-14")
        XCTAssertEqual(Ideas.remove(items, id), [])
    }

    func testGroups() {
        var a = Idea(id: "p1", text: "p"); a.title = "Week view"; a.topic = "Nexus"; a.organised = "d"; a.who = "me"
        var b = Idea(id: "p2", text: "q"); b.title = "Sidebar"; b.topic = "Nexus"; b.organised = "d"
        var c = Idea(id: "p3", text: "sidebar again"); c.topic = "Nexus"; c.organised = "d"; c.sameAs = "p2"
        var d = Idea(id: "l1", text: "gym"); d.topic = "life"; d.organised = "d"
        let n = Idea(id: "n1", text: "new")
        let g = Ideas.group([n, a, b, c, d])
        XCTAssertEqual(g.waiting.map(\.id), ["n1"])
        XCTAssertEqual(g.topics.map(\.name), ["life", "Nexus"])
        XCTAssertEqual(g.topics[1].rows.map(\.id), ["p2", "p1"])
        XCTAssertEqual(g.topics[1].rows[0].repeats.map(\.id), ["p3"])
        XCTAssertEqual(Ideas.countLine([n, a, b, c, d]), "4 ideas · 1 new")
        let five = (1...5).map { Idea(id: "w\($0)", text: "t") }
        XCTAssertTrue(Ideas.due(five, today: "2026-11-13"))
        XCTAssertFalse(Ideas.due(Array(five.prefix(4)), today: "2026-11-13"))
    }

    func testBatchPromptAndAnswer() {
        var old = Idea(id: "old", text: "week view"); old.title = "Planner week view"; old.topic = "Nexus"; old.organised = "d"
        let items = [old, Idea(id: "n1", text: "um a week view"), Idea(id: "n2", text: "run a 10k")]
        let (batch, prompt) = Ideas.organisePrompt(items)
        XCTAssertEqual(batch, ["n1", "n2"])
        XCTAssertTrue(prompt.hasPrefix("(Nexus ideas sort)\n\nTopics so far, with their ideas (id: title):\n## Nexus\n- old: Planner week view\n\nNew ideas to sort (id: what the user wrote):\n- n1: um a week view\n- n2: run a 10k"))
        let reply = "Here:\n" + Ideas.fence + "json\n{\"ideas\": [{\"id\": \"n1\", \"title\": \"A week view\", \"note\": \"\", \"topic\": \"nexus\", \"kind\": \"nexus\", \"same_as\": \"old\"}, {\"id\": \"n2\", \"title\": \"Run a 10k\", \"note\": \"\", \"topic\": \"Health\", \"kind\": \"LIFE\", \"same_as\": \"n2\"}, {\"id\": \"zz\", \"title\": \"x\", \"note\": \"\", \"topic\": \"x\", \"kind\": \"other\", \"same_as\": \"\"}]}\n" + Ideas.fence
        let sorted = Ideas.readReply(reply)!
        XCTAssertEqual(sorted.count, 3)
        let out = Ideas.applyOrganise(items, sorted, batch: batch, today: "2026-11-13", now: "T")
        XCTAssertEqual(out.sorted, 2)
        XCTAssertEqual(out.topics, ["Health"])
        XCTAssertEqual(out.items[1].topic, "Nexus")
        XCTAssertEqual(out.items[1].sameAs, "old")
        XCTAssertEqual(out.items[1].text, "um a week view")
        XCTAssertEqual(out.items[2].kind, "life")
        XCTAssertNil(out.items[2].sameAs)
        XCTAssertNil(Ideas.readReply("no json here"))
        XCTAssertEqual(Ideas.sortedLine(2, ["Health"]), "Sorted 2 ideas; new topic: Health.")
    }

    func testConflictCopyFold() {
        XCTAssertTrue(Ideas.isConflict("nexus-ideas (conflict iPad 2026-11-13 0815).yaml"))
        XCTAssertFalse(Ideas.isConflict("nexus-ideas.yaml"))
        var a = Idea(id: "a", text: "a"); a.title = "A1"; a.edited = "2026-11-13T10:00:00Z"
        var a2 = a; a2.title = "A2"; a2.edited = "2026-11-13T09:00:00Z"
        var b = Idea(id: "b", text: "b"); b.edited = "2026-11-13T10:00:00Z"
        var b2 = b; b2.who = "me"; b2.edited = "2026-11-13T11:00:00Z"
        let f = Ideas.fold([a, b], [a2, b2, Idea(id: "c", text: "c")])
        XCTAssertTrue(f.changed)
        XCTAssertEqual(f.items.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(f.items[0].title, "A1")
        XCTAssertEqual(f.items[1].who, "me")
        XCTAssertFalse(Ideas.fold([a, b], [a, b]).changed)
    }

    func testWorkPrompt() {
        var x = Idea(id: "x", text: "run a ten k maybe"); x.title = "Run a 10k"; x.note = "Train."; x.topic = "Life"
        XCTAssertEqual(Ideas.workPrompt(x, repeats: [Idea(id: "y", text: "do a 10k race")]),
                       "(Nexus ideas work)\n\nThe idea: Run a 10k\nIts note: Train.\nWhat the user wrote: run a ten k maybe\nAlso written as: do a 10k race\nTopic: Life")
        XCTAssertTrue(Ideas.goesToDoor({ var y = x; y.kind = "nexus"; return y }()))
    }
}

private extension String {
    func leftPad(_ n: Int) -> String { String(repeating: "0", count: max(0, n - count)) + self }
}
