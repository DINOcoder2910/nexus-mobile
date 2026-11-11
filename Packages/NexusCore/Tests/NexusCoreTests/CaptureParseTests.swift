import XCTest
@testable import NexusCore

/// The capture line, as the laptop reads it (CaptureParse.swift is a port of its taskparse.js, dates.js, matchCapture and
/// captureland.js). The table is the laptop's dev/unit-taskparse.mjs, with the expected values printed by the laptop's own parser.
/// Today is fixed as there: Wednesday 2026-10-28 (thu 29, fri 30, sat 31, sun 1 Nov, mon 2 Nov).
final class CaptureParseTests: XCTestCase {
    let today = "2026-10-28"

    struct R {
        var text: String
        var want: String
        var today: String?
        var plan: String?
        init(_ text: String, _ want: String, today: String? = nil, plan: String? = nil) {
            self.text = text; self.want = want; self.today = today; self.plan = plan
        }
    }

    /// A parse in one line, the same way the laptop-side generator printed it.
    func desc(_ title: String, _ f: CaptureFacts, _ flags: [CaptureFlag]) -> String {
        var p = [title]
        if let d = f.due { p.append("due " + d) }
        if f.key { p.append("key") }
        if !f.plan.isEmpty { p.append("plan " + f.plan.joined(separator: ",")) }
        if let e = f.est { p.append("est " + e) }
        if let w = f.waiting { p.append("waiting \(w.on) since \(w.since)") }
        if let e = f.every { p.append("every " + e.freq + (e.on.map { " " + $0 } ?? "")) }
        if !f.tags.isEmpty { p.append("tags " + f.tags.joined(separator: ",")) }
        if !flags.isEmpty {
            let fl = flags.map { (x: CaptureFlag) -> String in
                let t = x.text ?? ""
                return x.code.rawValue + (t.isEmpty ? "" : ":" + t)
            }
            p.append("flags " + fl.joined(separator: ","))
        }
        return p.joined(separator: " | ")
    }

    func view(_ p: CaptureParsed) -> String {
        switch p.kind {
        case .empty: return "empty"
        case .claude, .palette: return p.kind.rawValue + ":" + p.text
        case .task: return desc(p.title, p.facts, p.flags) + p.subtasks.map { " ; (" + desc($0.title, $0.facts, $0.flags) + ")" }.joined()
        }
    }

    func P(_ text: String, plan: String? = nil, workstreamTag: ((String) -> Bool)? = nil, ignore: [CaptureIgnore] = []) -> CaptureParsed {
        CaptureParse.parse(text, today: today, plan: plan, workstreamTag: workstreamTag, ignore: ignore)
    }

    func spans(_ text: String, workstreamTag: ((String) -> Bool)? = nil) -> String {
        let chars = Array(text)
        return P(text, workstreamTag: workstreamTag).spans
            .map { "\($0.kind.rawValue) \($0.part) " + String(chars[$0.start..<$0.end]) }
            .joined(separator: ", ")
    }

    // MARK: the laptop's table

    func testTheLaptopTable() {
        let rows: [R] = [
            R("physics hw sheet by friday", "physics hw sheet | due 2026-10-30"),
            R("phys ia draft on thu 4pm 2h!", "phys ia draft | key | plan 2026-10-29 16:00 | est 2h"),
            R("chem lab report by fri; data; graph; conclusion", "chem lab report | due 2026-10-30 ; (data) ; (graph) ; (conclusion)"),
            R("sat practice test on sat", "sat practice test | plan 2026-10-31 | flags ambiguous:sat"),
            R("by fri 5pm submit form", "submit form | due 2026-10-30 | flags time-dropped:5pm"),
            R("\"due friday\" reading", "due friday reading"),
            R("IA draft #summative by fri", "IA draft | due 2026-10-30 | tags summative"),
            R("essay feedback waiting on Mr Daniel", "essay feedback | waiting Mr Daniel since 2026-10-28"),
            R("waiting on Mr Daniel", "waiting on Mr Daniel | waiting Mr Daniel since 2026-10-28"),
            R("physics quiz every mon", "physics quiz | every week mon"),
            R("read ch 4 in 3 days", "read ch 4 | due 2026-10-31"),
            R("econ p1 12 nov", "econ p1 | due 2026-11-12"),
            R("econ p1 12 nov", "econ p1 | due 2027-11-12", today: "2026-12-01"),
            R("mock exam 12 jan", "mock exam | due 2027-01-12"),
            R("reunion 3 oct", "reunion | due 2027-10-03"),
            R("by fri 2h", " | due 2026-10-30 | est 2h | flags no-title"),
            R("/plan my week", "claude:/plan my week"),
            R("> settings", "palette:> settings"),
            R("   ", "empty"),
            R("physics hw sheet by fri; q1-5 by thu on wed 45m; q6-10", "physics hw sheet | due 2026-10-30 ; (q1-5 | due 2026-10-29 | plan 2026-11-04 | est 45m) ; (q6-10)"),
            R("essay;; ; outline 4pm", "essay ; (outline | plan 2026-10-28 16:00)"),
            R("essay; by fri", "essay ; ( | due 2026-10-30 | flags no-title)"),
            R("\"a; b\" notes; c", "a; b notes ; (c)"),
            R("revise; sat paper 2 on sat!", "revise ; (sat paper 2 | key | plan 2026-10-31 | flags ambiguous:sat)"),
            R("read “by fri” notes", "read by fri notes"),
            R("revise tomorrow", "revise | due 2026-10-29"),
            R("portfolio next week", "portfolio | due 2026-11-02"),
            R("tidy notes eow", "tidy notes | due 2026-11-01"),
            R("report in 2 weeks", "report | due 2026-11-11"),
            R("fees by end of month", "fees | due 2026-10-31"),
            R("form before 12 nov", "form | due 2026-11-12"),
            R("lab due tue", "lab | due 2026-11-03"),
            R("slides for mon", "slides | due 2026-11-02"),
            R("flashcards do today", "flashcards | plan 2026-10-28"),
            R("essay due fri 13 nov", "essay | due 2026-11-13"),
            R("finish this fri", "finish | due 2026-10-30"),
            R("visa by 2026-10-01", "visa | due 2026-10-01 | flags past-date:2026-10-01"),
            R("revise on thu on sat", "revise | plan 2026-10-29,2026-10-31"),
            R("essay by fri by mon", "essay by mon | due 2026-10-30"),
            R("call mum 4:30pm", "call mum | plan 2026-10-28 16:30"),
            R("meet at 16:00 on fri", "meet | plan 2026-10-30 16:00"),
            R("gym tomorrow 7 am", "gym | due 2026-10-29 | flags time-dropped:7 am"),
            R("submit by 5pm", "submit | due 2026-10-28 | flags time-dropped:5pm"),
            R("physics ia by fri on thu 4pm", "physics ia | due 2026-10-30 | plan 2026-10-29 16:00"),
            R("revise 4pm", "revise | plan 2026-10-30 16:00", plan: "2026-10-30"),
            R("revise on sat", "revise | plan 2026-10-31", plan: "2026-10-30"),
            R("essay by mon", "essay | due 2026-11-02 | plan 2026-10-28", plan: "2026-10-28"),
            R("read 1h30", "read | est 1h30m"),
            R("read 90 min", "read | est 1h30m"),
            R("read 2 hrs", "read | est 2h"),
            R("read ~1.5h", "read | est 1h30m"),
            R("read for 45 mins", "read | est 45m"),
            R("! essay", "essay | key"),
            R("essay ★ by fri", "essay | due 2026-10-30 | key"),
            R("essay * submit!", "essay submit | key"),
            R("SAT study 1h daily", "SAT study | est 1h | every day"),
            R("gym every fri 4pm", "gym | plan 2026-10-30 16:00 | every week fri"),
            R("wait for it", "wait for it"),
            R("stand-up every weekday", "stand-up | every weekdays"),
            R("review every week", "review | every week"),
            R("reference letter wait for megan by fri", "reference letter | due 2026-10-30 | waiting megan since 2026-10-28"),
            R("waiting on OJSS reply", "reply | waiting OJSS since 2026-10-28"),
            R("#summative #ia-2 essay", "essay | tags summative,ia-2"),
            R("may need to redo", "may need to redo | flags ambiguous:may"),
            R("essay due may 3", "essay | due 2027-05-03"),
            R("study for sat", "study for sat | flags ambiguous:sat"),
            R("mock on sun", "mock | plan 2026-11-01"),
            R("take a week off", "take a week off"),
            R("email tom about it now", "email tom about it now"),
            R("q 10/20 and 3 days", "q 10/20 and 3 days"),
            R("last fri recap", "last fri recap"),
            R("call mum today 4pm", "call mum | due 2026-10-28 | flags time-dropped:4pm"),
            R("read \"next week\" chapter by fri", "read next week chapter | due 2026-10-30"),
            R("Submit form, by fri.", "Submit form | due 2026-10-30"),
        ]
        for r in rows {
            let p = CaptureParse.parse(r.text, today: r.today ?? today, plan: r.plan)
            XCTAssertEqual(view(p), r.want, "parse: \(r.text)")
        }
    }

    func testTheIPadExample() {
        let p = P("physics hw sheet by fri; q1-5 by thu on wed 45m")
        XCTAssertTrue(p.ok)
        XCTAssertEqual(p.title, "physics hw sheet")
        XCTAssertEqual(p.facts.due, "2026-10-30")
        XCTAssertEqual(p.subtasks.count, 1)
        let q = p.subtasks[0]
        XCTAssertEqual(q.title, "q1-5")
        XCTAssertEqual(q.facts.due, "2026-10-29")
        XCTAssertEqual(q.facts.planEntries, [PlanEntry(day: "2026-11-04")])
        XCTAssertEqual(q.facts.est, "45m")
        XCTAssertEqual(hoursOf(q.facts.est), 0.75)
        XCTAssertEqual(P("call mum on thu 4pm").facts.planEntries, [PlanEntry(day: "2026-10-29", time: "16:00")])
        XCTAssertEqual(hoursOf(P("read 1h30").facts.est), 1.5)
    }

    func testOkSubtasksAndCommandsOff() {
        XCTAssertEqual(["essay", "by fri", "\"   \""].map { P($0).ok }, [true, false, false])
        let p = P("physics hw sheet by fri ★; q1-5 45m; by thu; q6-10")
        XCTAssertEqual(p.subtasksToAdd.map(\.title), ["q1-5", "q6-10"])
        XCTAssertTrue(p.facts.key)
        let c = CaptureParse.parse("/plan my week", today: today, commands: false)
        XCTAssertEqual(c.kind, .task)
        XCTAssertEqual(c.title, "/plan my week")
    }

    func testFlags() {
        XCTAssertEqual(P("by fri 5pm form").flags, [CaptureFlag(code: .timeDropped, text: "5pm", time: "17:00")])
        XCTAssertEqual(P("revise; may need sat paper").subtasks[0].flags.map { $0.code.rawValue + ":" + ($0.text ?? "") }, ["ambiguous:may", "ambiguous:sat"])
    }

    func testMatchWordsAndTags() {
        XCTAssertEqual(P("phys hw by fri").matchText, "phys hw")
        let q = P("read \"physics\" notes #summative")
        XCTAssertEqual(q.matchText, "read notes")
        XCTAssertEqual(q.matchTags, ["summative"])
        XCTAssertNil(q.workstreamTag)
        XCTAssertEqual(P("letter waiting on Ms Settle").matchText, "letter Ms Settle")
        let w = P("worksheet #chem #summative", workstreamTag: { $0 == "chem" })
        XCTAssertEqual(w.title, "worksheet")
        XCTAssertEqual(w.facts.tags, ["summative"])
        XCTAssertEqual(w.matchTags, ["chem", "summative"])
        XCTAssertEqual(w.workstreamTag, "chem")
        XCTAssertEqual(w.matchText, "worksheet")
    }

    func testReaders() {
        XCTAssertEqual(["4pm", "4:30pm", "12am", "12pm", "16:00", "13pm", "24:00", "4"].map { CaptureParse.timeOf($0) },
                       ["16:00", "16:30", "00:00", "12:00", "16:00", nil, nil, nil])
        XCTAssertEqual(["1h", "30m", "1h30", "1h30m", "1.5h", "90 min", "2 hrs", "~2h", "0m", "h"].map { CaptureParse.estimateOf($0) },
                       [60, 30, 90, 90, 90, 90, 120, 120, nil, nil])
        XCTAssertEqual([45, 60, 90, 150].map { CaptureParse.estToken($0) }, ["45m", "1h", "1h30m", "2h30m"])
    }

    func testDates() {
        func d(_ s: String, _ t: String) -> String? { CaptureParse.parseNaturalDate(s, today: t) }
        XCTAssertEqual(["2026-10-28", "2026-10-05", "2026-10-11"].map { d("next week", $0) }, ["2026-11-02", "2026-10-12", "2026-10-12"])
        XCTAssertEqual(["2026-10-28", "2026-10-31", "2026-11-01"].map { d("this weekend", $0) }, ["2026-10-31", "2026-10-31", "2026-11-01"])
        XCTAssertEqual(d("tonight", today), today)
        XCTAssertEqual(d("eow", today), "2026-11-01")
        XCTAssertEqual(d("fri", today), "2026-10-30")
        XCTAssertEqual(d("wed", today), "2026-11-04")
        XCTAssertEqual(d("this wed", today), today)
        XCTAssertEqual(d("last wed", today), "2026-10-21")
        XCTAssertEqual(d("in 1 month", "2026-01-31"), "2026-03-03") // rolls over as JavaScript's Date does
        XCTAssertEqual(d("eom", "2028-02-10"), "2028-02-29")
        XCTAssertEqual(d("3 days ago", today), "2026-10-25")
        XCTAssertEqual(d("12th of october 2027", today), "2027-10-12")
        XCTAssertEqual(d("31 feb", today), nil)
        XCTAssertEqual(d("2026-13-01", today), nil)
        XCTAssertEqual(d("10/12/27", today), "2027-10-12")
        XCTAssertEqual(d("eoy", today), "2026-12-31")
    }

    // MARK: spans and taken-back parts

    func testSpans() {
        let rows: [(String, String)] = [
            ("phys ia draft on thu 4pm 2h!", "plan 0 on thu, time 0 4pm, est 0 2h, key 0 !"),
            ("  by fri 5pm submit form", "due 0 by fri, dropped 0 5pm"),
            ("call mum today 4pm", "due 0 today, dropped 0 4pm"),
            ("meet at 16:00 on fri", "time 0 at 16:00, plan 0 on fri"),
            ("essay; q1 by thu; q2 45m", "sub 0 ;, due 1 by thu, sub 0 ;, est 2 45m"),
            ("★fri essay", "key 0 ★, due 0 fri"),
            ("essay * by fri", "key 0 *, due 0 by fri"),
            ("essay feedback waiting on Mr Daniel by fri", "waiting 0 waiting on Mr Daniel, due 0 by fri"),
            ("read for 45 mins", "est 0 for 45 mins"),
            ("essay due fri 13 nov", "due 0 due fri 13 nov"),
            ("read \"next week\" chapter by fri", "due 0 by fri"),
            ("physics hw sheet by fri; q1-5 by thu on wed 45m; q6-10", "due 0 by fri, sub 0 ;, due 1 by thu, plan 1 on wed, est 1 45m, sub 0 ;"),
            ("may need to redo", ""),
        ]
        for (text, want) in rows { XCTAssertEqual(spans(text), want, "spans: \(text)") }
        XCTAssertEqual(P("  by fri 5pm submit form").spans, [CaptureSpan(start: 2, end: 8, kind: .due), CaptureSpan(start: 9, end: 12, kind: .dropped)])
        XCTAssertEqual(spans("x #tag1 #chem", workstreamTag: { $0 == "chem" }), "tag 0 #tag1, ws 0 #chem")
        XCTAssertEqual(P("IA draft #summative by fri").spans.first?.tag, "summative")
    }

    func testIgnore() {
        let a = P("essay by fri", ignore: [CaptureIgnore(start: 6, end: 12, kind: .due)])
        XCTAssertEqual([a.title, a.facts.due ?? "-"], ["essay by fri", "-"])
        XCTAssertEqual(a.spans, [])
        XCTAssertEqual(a.matchText, "essay")
        let b = P("call mom fri!", ignore: [CaptureIgnore(start: 12, end: 13, kind: .key)])
        XCTAssertEqual(b.title, "call mom!")
        XCTAssertEqual(b.facts.due, "2026-10-30")
        XCTAssertFalse(b.facts.key)
        let c = P("essay; outline", ignore: [CaptureIgnore(start: 5, end: 6, kind: .sub)])
        XCTAssertEqual(c.title, "essay; outline")
        XCTAssertEqual(c.subtasks.count, 0)
        let d = P("essay by fri by mon", ignore: [CaptureIgnore(start: 6, end: 12, kind: .due)])
        XCTAssertEqual(d.title, "essay by fri")
        XCTAssertEqual(d.facts.due, "2026-11-02")
    }

    // MARK: where it lands (the laptop's dev/unit-captureland.mjs, on a hand-made folder shaped like its fixture)

    func folder() -> Snapshot {
        func ws(_ id: String, _ name: String, _ group: String, aliases: [String] = [], status: String = "active") -> Workstream {
            Workstream(id: id, name: name, kind: nil, color: nil, status: status, aliases: aliases, folder: group + "/" + id, group: group)
        }
        var s = Snapshot(root: URL(fileURLWithPath: "/tmp"))
        let all = [
            ws("beta", "Beta class", "classes", aliases: ["BETA"]), ws("beta-lab", "Beta lab", "classes"),
            ws("math-ia", "Math IA", "ias-ee", aliases: ["MATHIA", "ia"], status: "parked"),
            ws("alpha", "Alpha project", "projects", aliases: ["ALPHA"]), ws("publications", "Publications", "projects", aliases: ["PUB", "pubs"]),
            ws("northwestern", "Northwestern (McCormick)", "applications"), ws("overview", "Applications overview", "applications", aliases: ["APP"]),
            ws("pat", "Pat Example", "people"), ws("sam-lee", "Sam Lee", "people"),
        ]
        for w in all { s.workstreams[w.id] = w }
        func g(_ id: String, _ label: String, _ order: Double, _ wss: [String], def: String? = nil) -> NexusCore.WorkGroup {
            NexusCore.WorkGroup(id: id, label: label, order: order, color: nil, kind: nil, defaultWorkstream: def, workstreams: wss)
        }
        s.groups = [
            g("classes", "Classes", 1, ["beta", "beta-lab"]), g("ias-ee", "IAs & EE", 2, ["math-ia"]),
            g("projects", "Projects", 3, ["alpha", "publications"]),
            g("applications", "Applications", 4, ["northwestern", "overview"], def: "overview"),
            g("people", "People", 5, ["pat", "sam-lee"]),
        ]
        return s
    }

    func L(_ text: String, context: String? = nil, recent: [String] = []) -> (CaptureParsed, CaptureLanding) {
        let s = folder()
        let p = CaptureParse.parseLine(text, in: s, today: today)
        return (p, CaptureParse.land(p, in: s, context: context, recent: recent))
    }

    func testLandsByWords() {
        let (p, l) = L("beta hw sheet by friday")
        XCTAssertEqual(l.workstream?.id, "beta")
        XCTAssertEqual(l.how, .words)
        XCTAssertTrue(l.guessed)
        XCTAssertEqual(l.file, "classes/beta/tasks.yaml")
        XCTAssertEqual(l.from, "beta")
        XCTAssertEqual(p.title, "beta hw sheet") // the matched word stays in the title
        XCTAssertEqual(p.facts.due, "2026-10-30")
        XCTAssertEqual(L("PUB reviewer reply").1.workstream?.id, "publications")
        XCTAssertEqual(L("phys pubs").1.workstream?.id, "publications")
        XCTAssertEqual(L("northwestern supplement draft").1.workstream?.id, "northwestern")
        XCTAssertEqual(L("north essay").1.workstream?.id, "northwestern") // the start of a word of the name
    }

    func testLongestMatchWins() {
        let l = L("beta lab write-up").1
        XCTAssertEqual(l.workstream?.id, "beta-lab")
        XCTAssertEqual(l.from, "beta lab")
        let m = CaptureParse.matchCapture("beta lab write-up", in: folder())
        XCTAssertEqual(m.matches.map(\.workstream.id), ["beta-lab", "beta"])
        XCTAssertEqual(m.alternatives.map(\.id), ["beta"])
    }

    func testTagWins() {
        let (p, l) = L("beta reading #alpha #summative")
        XCTAssertEqual(l.workstream?.id, "alpha")
        XCTAssertEqual(l.how, .tag)
        XCTAssertFalse(l.guessed)
        XCTAssertEqual(l.from, "")
        XCTAssertEqual(p.facts.tags, ["summative"])
        XCTAssertEqual(p.title, "beta reading")
        XCTAssertEqual(p.spans.map(\.kind), [.ws, .tag])
        XCTAssertNil(CaptureParse.tagWorkstream("summative", in: folder()))
        XCTAssertEqual(L("essay #summative").0.facts.tags, ["summative"])
        XCTAssertEqual(CaptureParse.tagWorkstream("beta-lab", in: folder())?.id, "beta-lab")
    }

    func testGroupDefaultContextAndInbox() {
        XCTAssertEqual(L("applications transcript request").1.workstream?.id, "overview") // the group's label -> its default
        let inbox = L("buy milk").1
        XCTAssertNil(inbox.workstream)
        XCTAssertEqual(inbox.how, .inbox)
        XCTAssertEqual(inbox.file, "inbox.yaml")
        XCTAssertEqual(inbox.label, "Inbox")
        XCTAssertNil(L("call the dentist").1.workstream) // everyday words never match
        let page = L("read chapter 3", context: "pat").1
        XCTAssertEqual(page.workstream?.id, "pat")
        XCTAssertEqual(page.how, .context)
        XCTAssertEqual(L("alpha follow-up", context: "pat").1.workstream?.id, "alpha")
        XCTAssertEqual(L("ia draft").1.workstream?.id, "math-ia") // an alias matches a parked workstream too
    }

    func testAlternatives() {
        let ids = { (l: CaptureLanding) in l.alternatives.map { $0?.id ?? "inbox" } }
        XCTAssertEqual(ids(L("beta quiz", recent: ["alpha", "beta", "pat", "columbia"]).1), ["beta", "beta-lab", "alpha", "pat", "inbox"])
        XCTAssertEqual(ids(L("buy milk", recent: ["alpha"]).1), ["inbox", "alpha"])
    }

    func testAtMarks() {
        let (p, _) = L("Email the form back @fri")
        XCTAssertEqual(p.title, "Email the form back")
        XCTAssertEqual(p.facts.due, "2026-10-30")
        let text = "essay @fri"
        let chars = Array(text)
        XCTAssertEqual(L(text).0.spans.map { "\($0.kind.rawValue) " + String(chars[$0.start..<$0.end]) }, ["due @fri"])
        let line = "@fri essay @mon! x; @tue y 4pm"
        let lc = Array(line)
        XCTAssertEqual(L(line).0.spans.map { "\($0.kind.rawValue) \($0.part) " + String(lc[$0.start..<$0.end]) },
                       ["due 0 @fri", "key 0 !", "sub 0 ;", "due 1 @tue", "dropped 1 4pm"])
        XCTAssertEqual(L("mail bob@x.com").0.title, "mail bob@x.com")
        XCTAssertEqual(L("mail bob@x.com").0.spans, [])
        let back = CaptureParse.parseLine("essay @fri", in: folder(), today: today, ignore: [CaptureIgnore(start: 6, end: 10, kind: .due)])
        XCTAssertEqual(back.title, "essay @fri")
        XCTAssertNil(back.facts.due)
    }

    func testChips() {
        let (p, l) = L("beta hw sheet by fri on mon 30m! every week waiting on sam #x; a; b")
        XCTAssertEqual(CaptureParse.chips(p, landing: l, today: today).map { "\($0.kind.rawValue):\($0.text)" }, [
            "ws:Beta class", "due:due Fri 30 Oct · in 2 days", "plan:on Mon 2 Nov", "est:30m", "key:★ key date", "every:weekly",
            "waiting:waiting on sam", "tag:#x", "subs:2 subtasks",
        ])
        XCTAssertEqual(CaptureParse.chips(p, landing: l, today: today).first?.tail, " from “beta”")
        XCTAssertEqual(["beta a today", "beta a tomorrow", "beta a by fri", "beta a by 9 nov"].map { t -> String in
            let (pp, ll) = L(t)
            return CaptureParse.chips(pp, landing: ll, today: today).first(where: { $0.kind == .due })?.text ?? ""
        }, ["due today", "due tomorrow", "due Fri 30 Oct · in 2 days", "due Mon 9 Nov · in 12 days"])
        let (q, m) = L("call the dentist; ring")
        XCTAssertEqual(CaptureParse.chips(q, landing: m, today: today).map { "\($0.kind.rawValue):\($0.text)" }, ["ws:Inbox", "subs:1 subtask"])
        let (r, n) = L("beta report by fri 5pm")
        XCTAssertEqual(CaptureParse.chips(r, landing: n, today: today).filter { $0.kind == .dropped }.map(\.text), ["5pm"])
        let (c, k) = L("hw sheet", context: "beta")
        XCTAssertEqual(CaptureParse.chips(c, landing: k, today: today).first?.tail, " this page")
    }
}
