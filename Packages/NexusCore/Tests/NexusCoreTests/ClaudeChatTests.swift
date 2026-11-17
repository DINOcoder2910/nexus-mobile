import XCTest
@testable import NexusCore

/// The Claude conversation on the iPhone and iPad, the pure half: the reply's tags, the data folder as Claude sees it (look-ups, the
/// boundary, proposals and their checks, the diff), Plan with Claude (free time, the prompt, placements accepted at once), the commands,
/// and the day brief in the laptop's words (homebrief.js, claudebrief.js).
final class ClaudeChatTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nexus-chat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try write("nexus.yaml", "nexus: 2\n")
        try write("inbox.yaml", "tasks:\n  - id: inb1\n    title: Call the bank\n")
        try write("classes/group.yaml", "label: Classes\norder: 1\nkind: class\n")
        try write("classes/chem/workstream.yaml", "id: chem\nname: Chemistry\nstatus: active\n")
        try write("classes/chem/tasks.yaml", """
        tasks:
          - id: due1
            title: Lab report — final draft
            due: 2026-11-16
          - id: due2
            title: Essay
            due: 2026-11-16
          - id: pl1
            title: Revise redox
            plan: [2026-11-16 10:00]
            est: 1h30m
          - id: old1
            title: Old worksheet
            due: 2026-10-01
          - id: old2
            title: Recent quiz corrections
            due: 2026-11-14
            est: 45m
          - id: w1
            title: Ms Settle's reply
            waiting: {on: Ms Settle, since: 2026-11-01}
          - id: soon1
            title: Unit test
            due: 2026-11-20

        """)
        try write("classes/chem/notes.md", "# Chemistry\n\nRedox is hard.\n")
        try write("notebooks/Chem/Lesson.board/text/a.md", "redox in a notebook\n")
        try write(".git/config", "redox\n")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func write(_ rel: String, _ text: String) throws {
        let u = dir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: u, atomically: true, encoding: .utf8)
    }

    var planning: Planning { Planning(DataFolder.load(dir), today: "2026-11-16") }

    // MARK: the tags

    func testParsesLookupsAndProposalsInOrder() {
        let reply = """
        I'll look first.
        <read path="classes/chem/tasks.yaml"/>
        <list path="./classes/"/>
        <search>redox</search>
        Then the change:
        <edit path="inbox.yaml">
        <old>
          - id: inb1
            title: Call the bank
        </old>
        <new>
          - id: inb1
            title: Call the bank about the card
        </new>
        </edit>
        <write path="people/kim/2026-11-16 Catch-up.md">
        # Catch-up
        </write>
        Done.
        """
        let p = ClaudeChat.parse(reply)
        XCTAssertEqual(p, [
            .text("I'll look first."),
            .action(.read("classes/chem/tasks.yaml")),
            .action(.list("classes")),
            .action(.search("redox")),
            .text("Then the change:"),
            .action(.edit(path: "inbox.yaml", old: "  - id: inb1\n    title: Call the bank", new: "  - id: inb1\n    title: Call the bank about the card")),
            .action(.write(path: "people/kim/2026-11-16 Catch-up.md", content: "# Catch-up")),
            .text("Done."),
        ])
        XCTAssertTrue(ClaudeChat.Action.read("x").isLookup)
        XCTAssertFalse(ClaudeChat.Action.write(path: "x", content: "").isLookup)
        XCTAssertEqual(ClaudeChat.Action.list("").label, "Looked in the data folder")
    }

    func testAnUnfinishedTagNeverShowsWhileStreaming() {
        XCTAssertEqual(ClaudeChat.words("Let me check <rea"), "Let me check")
        XCTAssertEqual(ClaudeChat.words("Let me check <read path=\"inbox"), "Let me check")
        XCTAssertEqual(ClaudeChat.words("Here: <edit path=\"inbox.yaml\">\n<old>\nx"), "Here:")
        // a "<" that starts no tag is words, as is an unfinished tag once the reply is over
        XCTAssertEqual(ClaudeChat.words("2 < 3 and <b>bold</b>"), "2 < 3 and <b>bold</b>")
        XCTAssertEqual(ClaudeChat.words("Oops <edit path=\"a\">", final: true), "Oops <edit path=\"a\">")
    }

    // MARK: the folder as Claude sees it

    func testLookupsStayInsideTheFolder() {
        let w = ClaudeChat.Workspace(root: dir)
        XCTAssertTrue(w.readText("classes/chem/notes.md").contains("Redox is hard."))
        XCTAssertEqual(w.readText("nope.md"), "There is no file at nope.md.")
        XCTAssertTrue(w.readText("../secret").hasPrefix("Refused"))
        XCTAssertTrue(w.readText(".git/config").hasPrefix("Refused"))
        XCTAssertTrue(w.readText("x/the-thing/a.md").hasPrefix("Refused"))
        XCTAssertTrue(w.readText("classes").contains("That is a folder"))
        XCTAssertEqual(w.listText(""), "classes/\ninbox.yaml\nnexus.yaml\nnotebooks/")
        XCTAssertEqual(w.listText("classes/chem"), "notes.md\ntasks.yaml\nworkstream.yaml")
        // search: YAML and markdown, never the notebooks or .git
        let hits = w.searchText("REDOX")
        XCTAssertTrue(hits.contains("classes/chem/tasks.yaml:9:     title: Revise redox") || hits.contains("classes/chem/tasks.yaml:9: title: Revise redox"), hits)
        XCTAssertTrue(hits.contains("classes/chem/notes.md:3: Redox is hard."), hits)
        XCTAssertFalse(hits.contains("notebooks"))
        XCTAssertFalse(hits.contains(".git"))
        XCTAssertTrue(w.answer(.read("inbox.yaml")).hasPrefix("<result of=\"read inbox.yaml\">\ntasks:"))
    }

    func testAProposalIsCheckedAgainstTheFileAsItIsNow() throws {
        let w = ClaudeChat.Workspace(root: dir)
        let s = DataFolder.load(dir)
        let ok = w.propose(.edit(path: "inbox.yaml", old: "    title: Call the bank", new: "    title: Call the bank about the card"), id: "p1",
                           takenIds: ClaudeChat.idsOutside("inbox.yaml", in: s))
        XCTAssertNil(ok.problem)
        XCTAssertEqual(ok.after, "tasks:\n  - id: inb1\n    title: Call the bank about the card\n")
        XCTAssertEqual(ClaudeChat.diff(ok.before, ok.after), [.same("tasks:"), .same("  - id: inb1"), .removed("    title: Call the bank"), .added("    title: Call the bank about the card"), .same("")])

        // not there, there twice, would not parse, an id another file uses
        XCTAssertNotNil(w.propose(.edit(path: "inbox.yaml", old: "Call the shop", new: "x"), id: "p2").problem)
        try write("twice.md", "a\na\n")
        XCTAssertEqual(w.propose(.edit(path: "twice.md", old: "a", new: "b"), id: "p3").problem,
                       "The text to replace is in the file 2 times; include more of the lines around it so it is there once.")
        XCTAssertTrue(w.propose(.edit(path: "inbox.yaml", old: "    title: Call the bank", new: "    title: [broken"), id: "p4").problem?.contains("YAML") ?? false)
        let dup = w.propose(.edit(path: "inbox.yaml", old: "    title: Call the bank\n", new: "    title: Call the bank\n  - id: due1\n    title: Copy\n"), id: "p5",
                            takenIds: ClaudeChat.idsOutside("inbox.yaml", in: s))
        XCTAssertEqual(dup.problem, "The id due1 is already used by a task in another file.")
        // new files: never over one that exists, never outside the folder
        XCTAssertNil(w.propose(.write(path: "people/kim/2026-11-16 Catch-up.md", content: "# Hi"), id: "p6").problem)
        XCTAssertNotNil(w.propose(.write(path: "inbox.yaml", content: "x"), id: "p7").problem)
        XCTAssertNotNil(w.propose(.write(path: ".nexus/brief.json", content: "{}"), id: "p8").problem)
        XCTAssertNotNil(w.propose(.edit(path: "../x.md", old: "a", new: "b"), id: "p9").problem)
    }

    func testReplaceKeepsTheFilesLineEnds() throws {
        let r = try ClaudeChat.replace("a\nb", with: "a\nc", in: "x\r\na\r\nb\r\n").get()
        XCTAssertEqual(r, "x\r\na\r\nc\r\n")
    }

    // MARK: Plan with Claude

    func testFreeTimeAndThePrompt() {
        let gaps = ClaudeChat.freeGaps(busy: [(9 * 60, 10 * 60), (10 * 60, 11 * 60 + 30), (13 * 60, 13 * 60 + 10)], now: 8 * 60 + 41)
        XCTAssertEqual(gaps.map { [$0.start, $0.end] }, [[8 * 60 + 45, 9 * 60], [11 * 60 + 30, 13 * 60], [13 * 60 + 10, 21 * 60]])
        XCTAssertEqual(ClaudeChat.dayRange(busy: [(7 * 60, 7 * 60 + 30), (21 * 60, 22 * 60 + 10)]).0, 7 * 60)
        XCTAssertEqual(ClaudeChat.dayRange(busy: [(21 * 60, 22 * 60 + 10)]).1, 23 * 60)

        let slipped = ClaudeChat.slippedForPlan(planning)
        XCTAssertEqual(slipped.map(\.id), ["old2", "old1"])
        XCTAssertEqual(slipped.first?.minutes, 45)
        XCTAssertEqual(slipped.last?.minutes, 30)
        let prompt = ClaudeChat.planPrompt(today: "2026-11-16", nowMinute: 9 * 60 + 5, slipped: slipped, gaps: [(start: 9 * 60 + 5, end: 21 * 60)],
                                           files: [(path: "classes/chem/tasks.yaml", text: "tasks: []")])
        XCTAssertTrue(prompt.hasPrefix("Plan my day. Today is 2026-11-16, now 09:05.\n"))
        XCTAssertTrue(prompt.contains("- old2 \"Recent quiz corrections\" in classes/chem/tasks.yaml, about 45m"))
        XCTAssertTrue(prompt.contains("Free today: 09:05-21:00"))
        XCTAssertTrue(prompt.contains("<result of=\"read classes/chem/tasks.yaml\">\ntasks: []\n</result>"))
    }

    func testPlacementsOnTodayAreAcceptedAtOnce() {
        let before = "tasks:\n  - id: a1\n    title: A\n    due: 2026-11-01\n  - id: b1\n    title: B\n"
        let placed = before.replacingOccurrences(of: "    due: 2026-11-01\n", with: "    due: 2026-11-01\n    plan: [2026-11-16 14:00]\n")
        let p = ClaudeChat.placements(path: "classes/chem/tasks.yaml", before: before, after: placed, today: "2026-11-16")
        XCTAssertEqual(p?.auto, true)
        XCTAssertEqual(p?.list.first?.id, "a1")
        XCTAssertEqual(p?.list.first?.time, "14:00")
        // another day, or anything else changed: it waits for Accept
        let tomorrow = before.replacingOccurrences(of: "    due: 2026-11-01\n", with: "    due: 2026-11-01\n    plan: [2026-11-16, 2026-11-17]\n")
        XCTAssertEqual(ClaudeChat.placements(path: "classes/chem/tasks.yaml", before: before, after: tomorrow, today: "2026-11-16")?.auto, false)
        let retitled = placed.replacingOccurrences(of: "title: B", with: "title: Bee")
        let r = ClaudeChat.placements(path: "classes/chem/tasks.yaml", before: before, after: retitled, today: "2026-11-16")
        XCTAssertEqual(r?.planOnly, false)
        XCTAssertEqual(r?.auto, false)
        XCTAssertNil(ClaudeChat.placements(path: "notes.md", before: "a", after: "b", today: "2026-11-16"))
    }

    // MARK: what Claude is told

    func testSystemContextAndCommands() {
        let sys = ClaudeChat.system(rules: nil, device: "iPhone")
        XCTAssertTrue(sys.contains("The user is on their iPhone."))
        XCTAssertTrue(sys.contains("# How this Nexus works")) // the laptop's default rules when the folder has no NEXUS.md
        XCTAssertTrue(ClaudeChat.system(rules: "# Mine", device: "iPad").hasSuffix("# Mine"))

        let ctx = ClaudeChat.context(looking: "Today", today: "2026-11-16", now: "15:40",
                                     workstreams: [.init(id: "chem", name: "Chemistry", folder: "classes/chem", open: 6, parked: false)],
                                     inboxOpen: 1, freeIds: ["abcd"], extra: "The user is on Columbia's page.")
        XCTAssertEqual(ctx, "<context>\nLooking at: Today\nToday is 2026-11-16 (Monday), now 15:40.\nWorkstreams (id: name, folder, open tasks):\n- chem: Chemistry, classes/chem/, 6 open\nInbox: inbox.yaml, 1 open.\nFree ids for new tasks: abcd.\nThe user is on Columbia's page.\n</context>\n\n")
        XCTAssertEqual(ClaudeChat.decisions(accepted: ["inbox.yaml"], rejected: [], failed: []), "<changes>\nAccepted and saved: inbox.yaml.\n</changes>\n\n")

        XCTAssertEqual(ClaudeChat.command(in: "/plan next week")?.name, "/plan")
        XCTAssertEqual(ClaudeChat.command(in: "/plan next week")?.args, "next week")
        XCTAssertNil(ClaudeChat.command(in: "/nope"))
        XCTAssertTrue(ClaudeChat.expand("/plan", today: "2026-11-16")!.contains("about 6 hours of planned work and starting around 04:00"))
        XCTAssertTrue(ClaudeChat.expand("/file-inbox", args: "skip the bank", today: "2026-11-16")!.hasSuffix("The user adds: skip the bank"))
        XCTAssertNil(ClaudeChat.expand("/nope", today: "2026-11-16"))

        let ids = ClaudeChat.freeIds(5, taken: ["abcd"])
        XCTAssertEqual(Set(ids).count, 5)
        XCTAssertFalse(ids.contains("abcd"))
    }

    // MARK: the day brief (homebrief.js, claudebrief.js)

    func testTheBriefInTheLaptopsWords() {
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9))!
        let b = DayBrief.build(planning, now: morning)
        XCTAssertEqual(b.greeting, "Good morning.")
        XCTAssertEqual(b.parts.map(\.id), ["today", "slipped", "waits", "inbox"])
        XCTAssertEqual(b.parts[0].text, "Essay and Lab report are due today, and you have 1 thing planned, about 1h 30m.")
        XCTAssertEqual(b.parts[1].text, "2 older items passed their dates without a plan; most look stale rather than late, and I can re-date or clear them with you.")
        XCTAssertEqual(b.parts[2].text, "Ms Settle's reply has been quiet for 2w.")
        XCTAssertEqual(b.parts[3].text, "The inbox has 1 thing to file.")
        XCTAssertEqual(b.stats.slipped, 2)
        XCTAssertEqual(b.stats.stale, 1)
        XCTAssertEqual(b.stats.oldestWait, 15)

        let facts = DayBrief.facts(planning, brief: b, events: [(title: "Assembly", start: "08:30")])
        XCTAssertEqual(facts, """
        Today: 2026-11-16.
        Calendar today: Assembly at 08:30.
        Due today: Essay; Lab report.
        Planned for today (1, about 1.5 h): Revise redox.
        2 items passed their dates with no plan; 1 of them more than two weeks ago (likely stale). Examples: Old worksheet; Recent quiz corrections.
        Waiting and gone quiet: Ms Settle's reply (15 days).
        Inbox: 1 to file.
        """)
        XCTAssertTrue(DayBrief.prompt(facts).hasSuffix("Facts:\n" + facts))
    }

    func testTheBriefWhenTheDayIsClear() throws {
        try write("classes/chem/tasks.yaml", "tasks:\n  - id: soon1\n    title: Unit test (calculator allowed)\n    due: 2026-11-17\n")
        try write("inbox.yaml", "tasks: []\n")
        let evening = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 19))!
        let b = DayBrief.build(planning, now: evening, name: "Murtaza")
        XCTAssertEqual(b.greeting, "Good evening, Murtaza.")
        XCTAssertEqual(b.text, "Nothing is due or planned for today. Next up: Unit test, due tomorrow.")
        XCTAssertEqual(DayBrief.facts(planning, brief: b), "Today: 2026-11-16.\nNothing is due, planned or slipping.")
    }

    func testCleaningClaudesBriefAndTheDaysCache() {
        XCTAssertEqual(DayBrief.clean("Here's your brief:\n\"**Two** things are due today, and the essay can wait until after school.\""),
                       "Two things are due today, and the essay can wait until after school.")
        XCTAssertNil(DayBrief.clean("Too short."))
        XCTAssertNil(DayBrief.clean(String(repeating: "word ", count: 200)))
        let c = DayBrief.Cache(day: "2026-11-16", text: "x", model: "haiku", generatedAt: 0)
        XCTAssertTrue(c.valid(today: "2026-11-16"))
        XCTAssertFalse(c.valid(today: "2026-11-17"))
        XCTAssertEqual(DayBrief.shortName("A very long title that goes on and on past the forty two characters"), "A very long title that goes on and on…")
        XCTAssertEqual(DayBrief.ageLabel(130), "4mo")
    }
}
