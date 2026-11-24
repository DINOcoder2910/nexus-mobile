import XCTest
@testable import NexusCore

/// The shared cases: folders and files with the answers both apps must give, for the rules the laptop and NexusCore each implement.
/// `Fixtures/shared` is a copy of nexus `dev/shared` (its README says what each rule is; copy it again with
/// `sh tools/shared-cases/copy.sh <nexus checkout>`). The laptop runs the same files in nexus `dev/unit-shared.mjs`, so a rule can't
/// change on one side without failing on the other.
final class SharedCasesTests: XCTestCase {
    var shared: URL!

    override func setUpWithError() throws {
        shared = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("shared")
    }

    func json(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], url.path)
    }
    func dirs(_ url: URL) -> [String] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map(\.lastPathComponent).sorted()
    }
    func days(_ any: Any?) -> [String: [String]] {
        var out: [String: [String]] = [:]
        for (k, v) in any as? [String: Any] ?? [:] { out[k] = v as? [String] ?? [] }
        return out
    }

    /// Every rule folder is one this file runs (a new rule needs a runner here and in the laptop's dev/unit-shared.mjs).
    func testTheRules() {
        XCTAssertEqual(dirs(shared), ["capture", "day-order-file", "fsrs", "order", "recordings", "tutor"])
    }

    /// order/<case>: Today's plan and each day's planned tasks, from the case's data folder, in the one order (DayOrder.swift).
    func testOrder() throws {
        let cases = dirs(shared.appendingPathComponent("order"))
        XCTAssertFalse(cases.isEmpty)
        for name in cases {
            let dir = shared.appendingPathComponent("order").appendingPathComponent(name)
            let c = try json(dir.appendingPathComponent("case.json"))
            let today = try XCTUnwrap(c["today"] as? String)
            let dayStart = c["dayStart"] as? Int ?? 0
            let expect = c["expect"] as? [String: Any] ?? [:]
            let s = DataFolder.load(dir.appendingPathComponent("data"))
            XCTAssertEqual(s.problems.map(\.message), [], "order/\(name): the folder reads cleanly")
            let p = Planning(s, today: today, dayStart: dayStart)
            XCTAssertEqual(p.todayPlan.map(\.id), expect["today"] as? [String] ?? [], "order/\(name): Today")
            for (day, ids) in days(expect["days"]) {
                XCTAssertEqual(p.planned(on: day).map(\.id), ids, "order/\(name): \(day)")
            }
        }
    }

    /// day-order-file/cases.json: reading and writing nexus-day-order.yaml, and a time read for the order.
    func testDayOrderFile() throws {
        let c = try json(shared.appendingPathComponent("day-order-file").appendingPathComponent("cases.json"))
        for x in c["read"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.parse(x["text"] as? String), days(x["expect"]), "read: \(x["about"] ?? "")")
        }
        for x in c["write"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.text(days(x["days"]), today: x["today"] as? String ?? ""), x["expect"] as? String, "write: \(x["about"] ?? "")")
        }
        for x in c["set"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.with(days(x["days"]), day: x["day"] as? String ?? "", keys: x["keys"] as? [String] ?? []), days(x["expect"]), "set: \(x["about"] ?? "")")
        }
        for x in c["time"] as? [[String: Any]] ?? [] {
            XCTAssertEqual(DayOrder.minutes(x["time"] as? String, dayStart: x["dayStart"] as? Int ?? 0), x["expect"] as? Int, "time: \(x["time"] ?? "nil")")
        }
        let back = DayOrder.parse(DayOrder.text(["2026-11-20": ["b", "a"]], today: "2026-11-20"))
        XCTAssertEqual(back, ["2026-11-20": ["b", "a"]], "what is written reads back the same")
    }

    /// recordings/cases.json: the recording format (Recordings.swift), the same answers as the new laptop app's Rust core.
    func testRecordings() throws {
        let c = try JSONValue.parse(String(contentsOf: shared.appendingPathComponent("recordings/cases.json"), encoding: .utf8))
        for x in c["clock"]?.array ?? [] {
            XCTAssertEqual(Recordings.clock(x.array?[0].number ?? -1), x.array?[1].string, "clock")
        }
        for x in c["stamp"]?.array ?? [] {
            let d = try XCTUnwrap(Recordings.date(x["iso"]?.string ?? ""), "iso")
            let zone = try XCTUnwrap(TimeZone(secondsFromGMT: Int(x["offset"]?.number ?? 0) * 60))
            XCTAssertEqual(Recordings.localStamp(d, zone: zone), x["stamp"]?.string)
            XCTAssertEqual(Recordings.localDay(d, zone: zone), x["day"]?.string)
        }
        for x in c["status"]?.array ?? [] {
            var m = Recordings.Meta(id: "x", kind: .meeting, started: Date(), device: "d")
            m.state = x["state"]?.string ?? "done"
            let files = (x["files"]?.array ?? []).compactMap(\.string)
            let got = Recordings.status(m, transcript: files.contains("transcript"), proposal: files.contains("proposal"), filed: files.contains("filed"))
            XCTAssertEqual(got.rawValue, x["expect"]?.string, "status: \(x["about"]?.string ?? "")")
        }
        for x in c["reply"]?.array ?? [] {
            let subjects = Set((x["subjects"]?.array ?? []).compactMap(\.string))
            let got = Recordings.parseReply(x["text"]?.string ?? "", subjects: subjects)?.json ?? .null
            XCTAssertEqual(got.text, (x["expect"] ?? .null).text, "reply: \(x["about"]?.string ?? "")")
        }
        for x in c["summary"]?.array ?? [] {
            let meta = try XCTUnwrap(Recordings.Meta(json: try XCTUnwrap(x["meta"])))
            let p = try XCTUnwrap(Recordings.Proposal(json: try XCTUnwrap(x["proposal"])))
            let zone = try XCTUnwrap(TimeZone(secondsFromGMT: Int(x["offset"]?.number ?? 0) * 60))
            XCTAssertEqual(Recordings.summaryMarkdown(meta: meta, proposal: p, subjectName: x["subjectName"]?.string, zone: zone), x["expect"]?.string,
                           "summary: \(x["about"]?.string ?? "")")
        }
        for x in c["taskNote"]?.array ?? [] {
            let t = try XCTUnwrap(x["task"])
            let task = Recordings.ProposedTask(title: t["title"]?.string ?? "", at: t["at"]?.number, note: t["note"]?.string)
            XCTAssertEqual(Recordings.taskNote(task, title: x["title"]?.string ?? "", path: x["path"]?.string ?? ""), x["expect"]?.string)
        }
        for x in c["teaching"]?.array ?? [] {
            let k = try XCTUnwrap(x["class"])
            let notes = Recordings.ClassNotes(unit: k["unit"]?.string, taught: k["taught"]?.string ?? "", examples: (k["examples"]?.array ?? []).compactMap(\.string),
                                              teaching: k["teaching"]?.string ?? "")
            let moments = (x["moments"]?.array ?? []).map { Recordings.Moment(at: $0["at"]?.number ?? 0, kind: $0["kind"]?.string ?? "", what: $0["what"]?.string ?? "") }
            let got = Recordings.addTeaching(x["existing"]?.string, subjectName: x["subjectName"]?.string ?? "", date: x["date"]?.string ?? "",
                                             title: x["title"]?.string ?? "", path: x["path"]?.string ?? "", notes: notes, moments: moments)
            XCTAssertEqual(got, x["expect"]?.string, "teaching: \(x["about"]?.string ?? "")")
        }
        for x in c["autoPins"]?.array ?? [] {
            let segs = (x["segments"]?.array ?? []).map { Recordings.Segment(start: $0["start"]?.number ?? 0, end: $0["end"]?.number ?? 0, text: $0["text"]?.string ?? "") }
            let have = (x["existing"]?.array ?? []).compactMap(Recordings.Pin.init(json:))
            let got = JSONValue.array(Recordings.autoPins(segs, existing: have).map(\.json))
            XCTAssertEqual(got.text, (x["expect"] ?? .null).text, "autoPins: \(x["about"]?.string ?? "")")
        }
        XCTAssertFalse((c["autoPins"]?.array ?? []).isEmpty, "the autoPins cases are read")
    }

    // MARK: the rules NexusCore's Swift and the shared Rust core both answer (each case through both)

    func cases(_ rule: String) throws -> JSONValue {
        try JSONValue.parse(String(contentsOf: shared.appendingPathComponent(rule).appendingPathComponent("cases.json"), encoding: .utf8))
    }

    /// JSON text with every object's keys sorted, so two answers compare whatever order their keys came in.
    func canon(_ v: JSONValue) -> String {
        switch v {
        case .object(let o): return "{" + o.sorted { $0.0 < $1.0 }.map { JSONValue.string($0.0).text + ":" + canon($0.1) }.joined(separator: ",") + "}"
        case .array(let a): return "[" + a.map { canon($0) }.joined(separator: ",") + "]"
        default: return v.text
        }
    }

    func captureFacts(_ f: CaptureFacts) -> [(String, JSONValue)] {
        var o: [(String, JSONValue)] = []
        if let d = f.due { o.append(("due", .string(d))) }
        if f.key { o.append(("key", .bool(true))) }
        if !f.plan.isEmpty { o.append(("plan", .array(f.plan.map { JSONValue.string($0) }))) }
        if let e = f.est { o.append(("est", .string(e))) }
        if let w = f.waiting { o.append(("waiting", .object([("on", .string(w.on)), ("since", .string(w.since))]))) }
        if let e = f.every {
            var r: [(String, JSONValue)] = [("freq", .string(e.freq))]
            if let on = e.on { r.append(("on", .string(on))) }
            o.append(("every", .object(r)))
        }
        if !f.tags.isEmpty { o.append(("tags", .array(f.tags.map { JSONValue.string($0) }))) }
        return o
    }

    func flagText(_ code: String, _ text: String?) -> JSONValue { .string(code + ((text ?? "").isEmpty ? "" : ":" + (text ?? ""))) }

    /// CaptureParse's answer as the cases write it: {title, ...facts, subs, flags}, or {kind, text}.
    func captureView(_ p: CaptureParsed) -> JSONValue {
        switch p.kind {
        case .empty: return .object([("kind", .string("empty"))])
        case .claude, .palette: return .object([("kind", .string(p.kind.rawValue)), ("text", .string(p.text))])
        case .task:
            var o: [(String, JSONValue)] = [("title", .string(p.title))] + captureFacts(p.facts)
            if !p.subtasks.isEmpty {
                o.append(("subs", .array(p.subtasks.map { s -> JSONValue in
                    let f = captureFacts(s.facts)
                    return f.isEmpty ? .string(s.title) : .array([.string(s.title), .object(f)])
                })))
            }
            if !p.flags.isEmpty { o.append(("flags", .array(p.flags.map { flagText($0.code.rawValue, $0.text) }))) }
            return .object(o)
        }
    }

    /// The core's answer (the laptop's JSON) the same way.
    func captureView(_ p: JSONValue) -> JSONValue {
        guard p["kind"]?.string == "task" else {
            var o: [(String, JSONValue)] = [("kind", p["kind"] ?? .null)]
            if let t = p["text"]?.string, !t.isEmpty { o.append(("text", .string(t))) }
            return .object(o)
        }
        var o: [(String, JSONValue)] = [("title", p["title"] ?? .null)] + (p["facts"]?.object ?? [])
        let subs = p["subtasks"]?.array ?? []
        if !subs.isEmpty {
            o.append(("subs", .array(subs.map { s -> JSONValue in
                let f = s["facts"]?.object ?? []
                return f.isEmpty ? (s["title"] ?? .null) : .array([s["title"] ?? .null, .object(f)])
            })))
        }
        let flags = p["flags"]?.array ?? []
        if !flags.isEmpty { o.append(("flags", .array(flags.map { flagText($0["code"]?.string ?? "", $0["text"]?.string) }))) }
        return .object(o)
    }

    /// capture/cases.json: the capture line, by CaptureParse.swift and by the core (capture.rs).
    func testCapture() throws {
        let c = try cases("capture")
        let today = try XCTUnwrap(c["today"]?.string)
        let all = c["cases"]?.array ?? []
        XCTAssertFalse(all.isEmpty)
        for x in all {
            let text = x["text"]?.string ?? ""
            let day = x["today"]?.string ?? today
            let ws = (x["workstreamTags"]?.array ?? []).compactMap(\.string)
            let want = canon(x["expect"] ?? .null)
            let swift = CaptureParse.parse(text, today: day, plan: x["plan"]?.string, workstreamTag: { ws.contains($0) })
            XCTAssertEqual(canon(captureView(swift)), want, "capture (Swift): \(text)")
            let core = RustCore.capture(text, today: day, plan: x["plan"]?.string, workstreamTags: ws)
            XCTAssertEqual(canon(captureView(core)), want, "capture (core): \(text)")
        }
    }

    /// fsrs/cases.json: a study card after a grade, by StudyFSRS.swift and by the core (study/fsrs.rs), in the cases' time zone.
    func testFSRS() throws {
        let c = try cases("fsrs")
        XCTAssertEqual(c["timeZone"]?.string, "UTC")
        let zone = FSRS.timeZone, hour = Days.dayStartHour, tz = ProcessInfo.processInfo.environment["TZ"]
        FSRS.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        Days.dayStartHour = Int(c["dayStart"]?.number ?? 4)
        setenv("TZ", "UTC", 1) // the core counts days in the process's local time
        defer {
            FSRS.timeZone = zone; Days.dayStartHour = hour
            if let tz { setenv("TZ", tz, 1) } else { unsetenv("TZ") }
        }
        func card(_ v: JSONValue?) -> SRSCard {
            var k = SRSCard()
            k.state = SRSCard.Phase(rawValue: v?["state"]?.string ?? "new") ?? .new
            k.due = Int64(v?["due"]?.number ?? 0); k.s = v?["s"]?.number ?? 0; k.d = v?["d"]?.number ?? 0
            k.reps = Int(v?["reps"]?.number ?? 0); k.lapses = Int(v?["lapses"]?.number ?? 0); k.last = Int64(v?["last"]?.number ?? 0)
            return k
        }
        let all = c["cases"]?.array ?? []
        XCTAssertFalse(all.isEmpty)
        for x in all {
            let about = x["about"]?.string ?? ""
            let grade = Int(x["grade"]?.number ?? 0), now = Int64(x["now"]?.number ?? 0)
            let want = card(x["expect"])
            XCTAssertEqual(FSRS.review(card(x["card"]), grade, now), want, "fsrs (Swift): \(about)")
            let core = RustCore.review(card: x["card"] ?? .null, grade: grade, now: now, dayStart: Days.dayStartHour)
            XCTAssertEqual(card(core), want, "fsrs (core): \(about)")
        }
    }

    /// tutor/cases.json: the reply in pieces (TutorReply.swift's own reader and the core's), a step checked (TutorSteps.swift and the
    /// core), and Check my maths (only the core has it).
    func testTutor() throws {
        let c = try cases("tutor")
        func said(_ ev: [TutorEvent]) -> [String] { ev.compactMap { e -> String? in if case .say(let s, _) = e { return s }; return nil } }
        func order(_ ev: [TutorEvent]) -> [String] { ev.map { e -> String in if case .say = e { return "say" }; return "step" } }
        func steps(_ ev: [TutorEvent]) -> [TutorStep] { ev.compactMap { e -> TutorStep? in if case .step(let s) = e { return s }; return nil } }
        func fields(_ s: TutorStep) -> [String: String] {
            var f = ["type": s.type]
            if let t = s.text { f["text"] = t }
            if let t = s.tex { f["tex"] = t }
            if let t = s.color { f["color"] = t }
            return f
        }
        func want(_ v: JSONValue) -> [String: String] {
            var f: [String: String] = [:]
            for (k, x) in v.object ?? [] where ["type", "text", "tex", "color"].contains(k) { f[k] = x.string }
            return f
        }
        let replies = c["reply"]?.array ?? []
        XCTAssertFalse(replies.isEmpty)
        for x in replies {
            let about = x["about"]?.string ?? ""
            let pieces = (x["pieces"]?.array ?? []).compactMap(\.string)
            let wantSaid = (x["said"]?.array ?? []).compactMap(\.string)
            let wantOrder = (x["order"]?.array ?? []).compactMap(\.string)
            let wantSteps = (x["steps"]?.array ?? []).map(want)
            let wantProblems = (x["problems"]?.array ?? []).map { [$0["problem"]?.string ?? "", $0["text"]?.string ?? ""] }

            let core = TutorReader()
            var ev = pieces.flatMap { core.push($0) }
            ev += core.end()
            XCTAssertEqual(said(ev), wantSaid, "reply (core): \(about): said")
            XCTAssertEqual(order(ev), wantOrder, "reply (core): \(about): order")
            XCTAssertEqual(steps(ev).map(fields), wantSteps, "reply (core): \(about): steps")
            XCTAssertEqual(core.problems.map { [$0.problem, $0.text] }, wantProblems, "reply (core): \(about): problems")

            let swift = SwiftTutorReader()
            var sev = pieces.flatMap { swift.push($0) }
            sev += swift.end()
            XCTAssertEqual(said(sev), wantSaid, "reply (Swift): \(about): said")
            XCTAssertEqual(order(sev), wantOrder, "reply (Swift): \(about): order")
            XCTAssertEqual(steps(sev).map(fields), wantSteps, "reply (Swift): \(about): steps")
            XCTAssertEqual(swift.problems.count, wantProblems.count, "reply (Swift): \(about): problems")
        }
        for x in c["steps"]?.array ?? [] {
            let about = x["about"]?.string ?? ""
            let raw = x["raw"] ?? .null
            let core = RustCore.checkStep(raw)
            let swift = TutorSteps.check(raw)
            if let s = x["step"] {
                XCTAssertEqual(core.step.map { canon($0) }, canon(s), "step (core): \(about)")
                XCTAssertEqual(swift.step.map(fields), want(s), "step (Swift): \(about)")
            } else {
                XCTAssertEqual(core.problem, x["problem"]?.string, "step (core): \(about)")
                XCTAssertNil(swift.step, "step (Swift): \(about) is refused")
            }
        }
        let maths = c["maths"]?.array ?? []
        XCTAssertFalse(maths.isEmpty)
        for x in maths {
            let about = x["about"]?.string ?? ""
            let m = RustCore.checkMaths((x["lines"]?.array ?? []).compactMap(\.string))
            let ok: [JSONValue] = m.lines.map { l in l?.ok.map { JSONValue.bool($0) } ?? .null }
            XCTAssertEqual(JSONValue.array(ok).text, (x["ok"] ?? .null).text, "maths: \(about): ok")
            XCTAssertEqual(m.first.map { Double($0) }, x["first"]?.number, "maths: \(about): first")
            XCTAssertEqual(m.answer, x["answer"]?.string, "maths: \(about): answer")
        }
    }
}
