import Foundation

// Applications in one place for the screens (the laptop's appsdata.js getApps / researchModel), and its writes (AppsEditor), each one step with
// Undo: a school's details are edited key by key in its workstream.yaml (DetailEdit), a step that writes several files (a new school and its
// tasks.yaml, a system's campuses, Accept on the write order) is one Change with `also`.

public struct AppsModel {
    public var today: String
    public var folder: AppsFolder
    public var schools: [School]
    public var applying: [School] { schools.filter(\.applying) }
    public var considering: [School] { schools.filter { !$0.applying } }
    /// The applying schools' essays (a system's once) and the overview's.
    public var essays: [Essay]
    public var items: [WorkItem]
    public var board: [BoardRow]
    public var ordered: [WorkItem]
    public var runway: Runway
    public var cap: CapStatus
    public var pace: Pace?
    public var planned: [String: Double]

    /// `db` links the folders to their database records (a UC campus without `unitid` is still one of the UC).
    public init(_ s: Snapshot, read: (String) -> String?, today: String, db: UniDB? = nil) {
        self.today = today
        var f = AppsFolder(s, read: read)
        if let db {
            for i in f.schools.indices where f.schools[i].system == nil {
                if let u = Unis.link(f.schools[i], db).u, let sys = Apps.system(ofUnit: u.id) { f.schools[i].system = sys.id }
            }
        }
        folder = f
        schools = f.schools
        let mine = f.schools.filter(\.applying).flatMap { sc in sc.essays.map { e -> Essay in var x = e; x.path = sc.path; return x } }
        essays = Apps.dedupeSystemEssays(mine, f.schools) + f.generalEssays
        items = Apps.workItems(s, folder: f, today: today)
        board = Apps.boardRows(f.schools, essays)
        ordered = Apps.orderItems(items, rows: board, today: today)
        runway = Apps.buildRunway(items, schools: f.schools, today: today)
        cap = Apps.capStatus(f.schools)
        pace = Apps.suggestPace(ordered, today: today)
        planned = Apps.plannedHours(items)
    }

    public func school(_ id: String?) -> School? { id.flatMap { i in schools.first { $0.id == i } ?? folder.dropped.first { $0.id == i } } }
    /// The school whose folder holds `workstream` (a school's page opens from the sidebar by its workstream id).
    public func school(workstream id: String) -> School? { school(id) }
    public func system(of s: School) -> Apps.AppSystem? { Apps.system(s.system) }
    /// The campuses on the list that are one application with `s` (itself alone otherwise).
    public func campuses(of s: School) -> [School] { s.system.map { sys in schools.filter { $0.system == sys } } ?? [s] }

    /// The plan to start applying in `round`: its deadline, the school's own date from the overview's rule, the ED warning and the cap.
    public func startPlan(_ s: School, round: String) -> (dl: String?, internal: String?, conflict: String?, willOver: Bool) {
        let dl = s.research.rounds[round]?.dl
        let rule = folder.internalRule
        return (dl, dl.flatMap { d in rule.flatMap { $0.for == d ? $0.date : nil } }, Apps.edConflict(schools, schoolId: s.id, round: round), cap.n + 1 > Apps.maxApplying)
    }

    /// The suggested schedule of the write order (`hoursPerDay` nil: the saved daily hours, else the pace's).
    public func suggestion(hoursPerDay: Double? = nil) -> (hoursPerDay: Double, schedule: Schedule) {
        let h = hoursPerDay ?? folder.writingHours ?? pace?.hoursPerDay ?? 1
        return (h, Apps.suggestSchedule(ordered, today: today, hoursPerDay: h))
    }

    // MARK: Research: every database school, with its folder when it is on the list, plus the folders the database does not know

    public func rows(_ db: UniDB?) -> [UniRow] {
        var byU: [Int: School] = [:], dropped: [Int: School] = [:]
        var custom: [School] = []
        for s in schools {
            if let u = Unis.link(s, db).u, byU[u.id] == nil { byU[u.id] = s } else { custom.append(s) }
        }
        for s in folder.dropped { if let u = Unis.link(s, db).u, byU[u.id] == nil, dropped[u.id] == nil { dropped[u.id] = s } }
        let loose = Unis.parseTiers(folder.tiersText) ?? [:]
        var out: [UniRow] = (db?.list ?? []).map { u in
            let s = byU[u.id], d = dropped[u.id]
            return UniRow(key: "u\(u.id)", u: u, s: s, dropped: d, t: s == nil && d == nil ? loose[u.id] : nil)
        }
        out += custom.map { UniRow(key: "s:" + $0.id, u: nil, s: $0, dropped: nil, t: nil) }
        return out
    }

    /// What the Applications conversation tells Claude: every school on the list, and the school in front.
    public func claudeContext(current: School?, notesExist: (School) -> Bool) -> String {
        var t = Apps.claudeSummary(schools, hasNotes: notesExist)
        if let c = current { t += "\n\nThe user is on \(c.name)'s page: \(c.path) (notes: \(c.folder)/notes.md)." }
        return t
    }
}

// MARK: - the writes

public struct AppsEditor {
    public var root: URL
    public var read: (URL) throws -> String
    public var write: (URL, String) throws -> Void
    public var readOnly: String?

    public init(root: URL, readOnly: String? = nil,
                read: @escaping (URL) throws -> String = { String(decoding: try Data(contentsOf: $0), as: UTF8.self) },
                write: @escaping (URL, String) throws -> Void = { try Data($1.utf8).write(to: $0, options: .atomic) }) {
        self.root = root; self.readOnly = readOnly; self.read = read; self.write = write
    }

    public enum Failure: Error, CustomStringConvertible {
        case cannot(String)
        public var description: String { if case .cannot(let w) = self { return w }; return "" }
    }

    func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }
    func exists(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url(rel).path) }
    func guardWritable() throws { if let r = readOnly { throw Failure.cannot(r) } }

    /// Several details of one file in one write. Nothing is written when nothing changes (the Change then has before == after).
    public func details(_ path: String, _ values: [(String, JSONValue?)], message: String) throws -> Change {
        try guardWritable()
        let before = try read(url(path))
        let after = try DetailEdit.set(before, values)
        if after != before { try write(url(path), after) }
        return Change(file: path, before: before, after: after, message: message)
    }

    /// The same details on several schools, one write each, one Undo.
    public func detailsMany(_ list: [(path: String, values: [(String, JSONValue?)])], message: String) throws -> Change {
        guard !list.isEmpty else { throw Failure.cannot("Nothing to change.") }
        // check every file first, so a failure writes nothing
        try guardWritable()
        var planned: [(String, String, String)] = []
        for x in list {
            let before = try read(url(x.path))
            planned.append((x.path, before, try DetailEdit.set(before, x.values)))
        }
        for p in planned where p.1 != p.2 { try write(url(p.0), p.2) }
        var c = Change(file: planned[0].0, before: planned[0].1, after: planned[0].2, message: message)
        c.also = planned.dropFirst().map { Change(file: $0.0, before: $0.1, after: $0.2, message: message) }
        return c
    }

    /// A school's `research:`, changed by `edit` (its raw value; empty values dropped so the file stays short).
    public func research(_ s: School, message: String, _ edit: (inout JSONValue) -> Void) throws -> Change {
        var r: JSONValue = s.rawResearch.object != nil ? s.rawResearch : .object([])
        edit(&r)
        return try details(s.path, [("research", AppsEditor.clean(r))], message: message)
    }

    /// Empty values out (null, "", []), and in the rounds too; `rounds` and `profile` keep their own shape.
    public static func clean(_ v: JSONValue) -> JSONValue? {
        guard case .object(let o) = v else { return v }
        var out: [(String, JSONValue)] = []
        for (k, x) in o {
            switch x {
            case .null: continue
            case .string(let s) where s.isEmpty: continue
            case .array(let a) where a.isEmpty: continue
            case .object where k == "rounds":
                let rs = (x.object ?? []).map { ($0.0, $0.1.object != nil ? (clean($0.1) ?? .object([])) : $0.1) }
                out.append((k, .object(rs)))
            default: out.append((k, x))
            }
        }
        return .object(out)
    }

    // MARK: schools

    /// A new school in Considering: `<group>/<slug>/workstream.yaml` and an empty tasks.yaml. A removed one with the same folder comes back.
    /// `start`: start applying right away (in `round`, rd when none).
    public func addSchool(_ name: String, model m: AppsModel, unitid: Int? = nil, short: String? = nil, tier: String? = nil, level: Int? = nil,
                          round: String? = nil, dl: String? = nil, start: Bool = false, snapshot: Snapshot, today: String) throws -> (Change, String) {
        try guardWritable()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw Failure.cannot("Type the school name.") }
        let id = Apps.slugify(name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression))
        guard !id.isEmpty else { throw Failure.cannot("That name has no letters to make a folder from.") }
        let group = m.folder.group
        let rel = "\(group)/\(id)/workstream.yaml", tasks = "\(group)/\(id)/tasks.yaml"
        if let d = m.folder.dropped.first(where: { $0.path == rel }) {
            return (try details(d.path, [("dropped", nil)], message: "\(d.short) put back"), d.id)
        }
        if m.schools.contains(where: { $0.id == id || $0.path == rel }) { throw Failure.cannot("\(name) is already in the list.") }
        if exists(rel) { throw Failure.cannot("That folder already exists.") }
        let loose = Unis.parseTiers(m.folder.tiersText) ?? [:]
        var tier = tier.flatMap { Unis.tiers.contains($0) ? $0 : nil }, level = level
        if tier == nil, let u = unitid, let lt = loose[u] { tier = lt.tier; level = lt.level }
        let rk = round.flatMap { Apps.roundKeys.contains($0) ? $0 : nil }
        var lines = ["id: \(id)", "name: \(DetailEdit.scalar(.string(name)))"]
        if let short, !short.isEmpty, short != name { lines.append("short: \(DetailEdit.scalar(.string(short)))") }
        if let unitid { lines.append("unitid: \(unitid)") }
        if let tier { lines.append("tier: \(tier)"); if let level { lines.append("tier_level: \(level)") } }
        lines += ["status: active", "applying: false"]
        if let rk { lines += ["research:", "  rounds:", "    \(rk): {\(dl.map { "dl: " + $0 } ?? "")}"] } else { lines.append("research: {}") }
        let text = lines.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(at: url(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
        let taskText = exists(tasks) ? (try? read(url(tasks))) : nil
        if taskText == nil { try write(url(tasks), "tasks: []\n") }
        try write(url(rel), text)
        // Undo leaves the folder and marks the school removed, as the laptop does (the files may have synced on already)
        var c = Change(file: rel, before: text.replacingOccurrences(of: "applying: false\n", with: "applying: false\ndropped: true\n"), after: text, message: "\(short ?? name) added")
        // the line in tiers.yaml moves into the folder
        if let u = unitid, loose[u] != nil, var map = Unis.parseTiers(m.folder.tiersText) {
            map[u] = nil
            let tp = "\(group)/\(Unis.tiersFile)"
            let before = (try? read(url(tp))) ?? ""
            let after = Unis.tiersText(map)
            try write(url(tp), after)
            c.also.append(Change(file: tp, before: before, after: after, message: c.message))
        }
        if start {
            let now = DataFolder.load(root)
            let m2 = AppsModel(now, read: { try? self.read(self.url($0)) }, today: today)
            if let s = m2.school(id) {
                let c2 = try startApplying(s, round: rk ?? "rd", model: m2, snapshot: now, today: today)
                c.after = (try? read(url(rel))) ?? c.after
                c.also += c2.also.filter { $0.file != rel }
                // the start's writes to the school's own file are part of `after`; the tasks file was empty before
                if c2.file != rel { c.also.append(c2) }
            }
        }
        return (c, id)
    }

    /// Start applying in `round`: the round, the school's own date, essays from the research prompts, the checklist and a "<short> supplemental
    /// essays" task. A system's other campuses on the list start with it.
    public func startApplying(_ s: School, round: String, model m: AppsModel, snapshot: Snapshot, today: String) throws -> Change {
        try guardWritable()
        let plan = m.startPlan(s, round: round)
        var values: [(String, JSONValue?)] = [("applying", .bool(true)), ("round", .string(round))]
        if let i = plan.internal { values.append(("internal", .string(i))) } else if s.internalDate != nil { values.append(("internal", nil)) }
        if s.essays.isEmpty && !s.research.prompts.isEmpty {
            let base = String(s.id.prefix(4))
            values.append(("essays", .array(s.research.prompts.enumerated().map { i, q in
                AppsEditor.clean(.object([("id", .string("\(base)\(i + 1)")), ("title", .string(q.t)), ("lim", q.lim.map { .number(Double($0)) } ?? .null),
                                          ("unit", q.lim != nil && q.unit == "characters" ? .string("characters") : .null), ("fam", .string(Apps.guessFamily(q.t)))])) ?? .null
            })))
        }
        if s.requirements.isEmpty {
            let found: [JSONValue] = s.research.reqs.isEmpty
                ? ["Counsellor recommendation", "Teacher recommendation", "Test scores sent"].map { .object([("t", .string($0))]) }
                : s.research.reqs.map { r in .object([("t", JSONValue.string(r.t))] + (r.src.isEmpty ? [] : [("src", .string(r.src))])) }
            values.append(("requirements", .array([.object([("t", .string("Common App (shared)"))]), .object([("t", .string("Supplemental essays"))])] + found)))
        }
        let others = m.campuses(of: s).filter { $0.id != s.id && !$0.applying }
        var list: [(path: String, values: [(String, JSONValue?)])] = [(s.path, values)]
        for o in others {
            var v: [(String, JSONValue?)] = [("applying", .bool(true)), ("round", .string(round))]
            if let i = plan.internal { v.append(("internal", .string(i))) }
            list.append((o.path, v))
        }
        let label = others.isEmpty ? "Applying: \(s.short)" : "Applying: \(Apps.system(s.system)?.name ?? s.short)"
        var c = try detailsMany(list, message: label)
        // the task goes to the school's tasks.yaml (made when there is none yet)
        let tp = s.tasksPath.isEmpty ? s.folder + "/tasks.yaml" : s.tasksPath
        var made: Change?
        if !exists(tp) {
            try write(url(tp), "tasks: []\n")
            var mc = Change(file: tp, before: "", after: "tasks: []\n", message: label); mc.created = true
            made = mc
        }
        let now = DataFolder.load(root)
        let te = TaskEditor(root: root, read: read, write: write)
        let (tc, _) = try te.add(title: "\(s.short) supplemental essays", to: tp, due: plan.dl, in: now, today: today)
        if var mc = made { mc.after = tc.after; c.also.append(mc) } else { c.also.append(tc) }
        return c
    }

    /// Considering a database school (or a removed one of yours): its folder, `unitid:` and tier. A UC campus brings every campus of the system,
    /// one Undo for all, and they share the status of the campuses already on the list.
    public func consider(_ row: UniRow, model m: AppsModel, rows: [UniRow], tier: String? = nil, level: Int? = nil, start: Bool = false, round: String? = nil,
                         snapshot: Snapshot, today: String) throws -> (Change, String) {
        if let s = row.s { throw Failure.cannot("\(s.name) is already in the list.") }
        var (c, id0) = try considerOne(row, model: m, tier: tier, level: level, start: start, round: round, snapshot: snapshot, today: today)
        let id = id0
        guard let u = row.u, let sys = Apps.system(ofUnit: u.id) else { return (c, id) }
        for other in rows where other.s == nil && other.u != nil && other.u!.id != u.id && sys.unitids.contains(other.u!.id) {
            let now = DataFolder.load(root)
            let m2 = AppsModel(now, read: { try? self.read(self.url($0)) }, today: today)
            if let r = try? considerOne(other, model: m2, snapshot: now, today: today) { c.also.append(r.0) }
        }
        // the group takes one status: the one picked when it was started, else the campuses already on the list
        let now = DataFolder.load(root)
        let m3 = AppsModel(now, read: { try? self.read(self.url($0)) }, today: today)
        let all = m3.schools.filter { $0.system == sys.id || ($0.unitid.map { sys.unitids.contains($0) } ?? false) }
        let ref = all.first { $0.id == id && $0.applying } ?? m.schools.first { $0.system == sys.id }
        var fix: [(path: String, values: [(String, JSONValue?)])] = []
        for s in all where s.id != ref?.id {
            let want: [(String, JSONValue?)] = ref?.applying == true
                ? [("applying", .bool(true)), ("round", ref?.round.map { .string($0) }), ("internal", ref?.internalDate.map { .string($0) }), ("applied", ref?.applied.map { .string($0) })]
                : [("applying", .bool(false)), ("applied", nil)]
            let differs = want.contains { k, v in
                switch k {
                case "applying": return (v == .bool(true)) != s.applying
                case "round": return v?.string != s.round
                case "internal": return v?.string != s.internalDate
                default: return v?.string != s.applied
                }
            }
            if differs { fix.append((s.path, want)) }
        }
        if !fix.isEmpty, let f = try? detailsMany(fix, message: c.message) { c.also.append(f) }
        c.message = "\(sys.name) added"
        return (c, id)
    }

    func considerOne(_ row: UniRow, model m: AppsModel, tier: String? = nil, level: Int? = nil, start: Bool = false, round: String? = nil,
                     snapshot: Snapshot, today: String) throws -> (Change, String) {
        if let d = row.dropped {
            var v: [(String, JSONValue?)] = [("dropped", nil)]
            if let tier { v += [("tier", .string(tier)), ("tier_level", level.map { .number(Double($0)) })] }
            else if let lt = row.u.flatMap({ (Unis.parseTiers(m.folder.tiersText) ?? [:])[$0.id] }), d.tier == nil {
                v += [("tier", .string(lt.tier)), ("tier_level", lt.level.map { .number(Double($0)) })]
            }
            if let u = row.u, d.unitid == nil { v.append(("unitid", .number(Double(u.id)))) }
            return (try details(d.path, v, message: "\(d.short) put back"), d.id)
        }
        guard let u = row.u else { throw Failure.cannot("That school is not in the database.") }
        return try addSchool(u.folder, model: m, unitid: u.id, short: u.short != u.folder ? u.short : nil, tier: tier, level: level, round: round,
                             dl: nil, start: start, snapshot: snapshot, today: today)
    }

    public func setApplied(_ s: School, _ on: Bool, model m: AppsModel, today: String) throws -> Change {
        let sys = m.system(of: s)
        let list = sys != nil ? m.campuses(of: s).filter { $0.applying || $0.id == s.id } : [s]
        return try detailsMany(list.map { ($0.path, [("applied", on ? .string(today) : nil)]) }, message: "\(sys?.name ?? s.short) \(on ? "applied" : "not applied")")
    }
    public func moveBack(_ s: School, model m: AppsModel) throws -> Change {
        guard let sys = m.system(of: s) else { return try details(s.path, [("applying", .bool(false))], message: "\(s.short) back to Considering") }
        return try detailsMany(m.campuses(of: s).filter(\.applying).map { ($0.path, [("applying", .bool(false))]) }, message: "\(sys.name) back to Considering")
    }
    /// Off the list (the folder is kept, `dropped: true`); a system's campuses go together.
    public func remove(_ s: School, model m: AppsModel) throws -> Change {
        let list = m.campuses(of: s)
        return try detailsMany(list.map { ($0.path, [("dropped", .bool(true))]) }, message: "\(m.system(of: s)?.name ?? s.short) removed")
    }
    public func restore(_ s: School) throws -> Change { try details(s.path, [("dropped", nil)], message: "\(s.short) put back") }
    public func link(_ s: School, to u: UniSchool) throws -> Change { try details(s.path, [("unitid", .number(Double(u.id)))], message: "\(s.short) linked") }
    public func setRound(_ s: School, _ round: String) throws -> Change { try details(s.path, [("round", .string(round))], message: "\(s.short): \(Apps.roundNames[round] ?? round)") }
    public func setInternal(_ s: School, _ day: String?) throws -> Change { try details(s.path, [("internal", day.map { .string($0) })], message: "\(s.short) own date") }

    // MARK: tiers

    /// A school's tier: in its workstream.yaml when it has a folder (a removed one too), else a line of tiers.yaml.
    public func setTier(_ row: UniRow, tier: String?, level: Int?, model m: AppsModel) throws -> Change {
        let t = tier.flatMap { Unis.tiers.contains($0) ? $0 : nil }
        let lv = t == nil ? nil : level
        if let s = row.s ?? row.dropped {
            return try details(s.path, [("tier", t.map { .string($0) }), ("tier_level", lv.map { .number(Double($0)) })], message: t != nil ? "\(s.short) tier" : "\(s.short) tier cleared")
        }
        guard let u = row.u else { throw Failure.cannot("That school is not in the database.") }
        try guardWritable()
        let tp = "\(m.folder.group)/\(Unis.tiersFile)"
        let before = exists(tp) ? try read(url(tp)) : ""
        guard var map = Unis.parseTiers(before) else { throw Failure.cannot("\(tp) does not parse, so it was left as it is. Fix it and try again.") }
        if let t { map[u.id] = LooseTier(tier: t, level: lv, name: u.name) } else { map[u.id] = nil }
        let after = Unis.tiersText(map)
        if after != before {
            try FileManager.default.createDirectory(at: url(tp).deletingLastPathComponent(), withIntermediateDirectories: true)
            try write(url(tp), after)
        }
        var c = Change(file: tp, before: before, after: after, message: t != nil ? "\(row.label) tier" : "\(row.label) tier cleared")
        c.created = before.isEmpty
        return c
    }

    // MARK: essays and the checklist

    static func essayList(_ es: [Essay]) -> JSONValue { .array(es.map(\.written)) }

    public func addEssay(_ s: School, title: String, lim: Int?, unit: String) throws -> Change {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw Failure.cannot("Type the prompt.") }
        let ids = Set(s.essays.map(\.id)), base = String(s.id.prefix(4))
        var n = s.essays.count + 1
        while ids.contains("\(base)\(n)") { n += 1 }
        var e = Essay(id: "\(base)\(n)", school: s.id, title: t)
        e.lim = lim; e.unit = unit == "characters" ? "characters" : "words"; e.fam = Apps.guessFamily(t)
        return try details(s.path, [("essays", AppsEditor.essayList(s.essays + [e]))], message: "\(s.short) prompt added")
    }
    public func removeEssay(_ e: Essay, of s: School) throws -> Change {
        try details(s.path, [("essays", AppsEditor.essayList(s.essays.filter { $0.id != e.id }))], message: "\(s.short) prompt removed")
    }
    /// One essay changed in its school's list (or the overview's, for a general one).
    public func editEssay(_ e: Essay, model m: AppsModel, message: String, _ change: (inout Essay) -> Void) throws -> Change {
        if !e.general, let s = m.school(e.school) {
            var list = s.essays
            guard let i = list.firstIndex(where: { $0.id == e.id }) else { throw Failure.cannot("That essay is gone.") }
            change(&list[i])
            return try details(s.path, [("essays", AppsEditor.essayList(list))], message: message)
        }
        var list = m.folder.generalEssays.filter { $0.path == e.path }
        guard let i = list.firstIndex(where: { $0.id == e.id }) else { throw Failure.cannot("That essay is gone.") }
        change(&list[i])
        return try details(e.path, [("essays", AppsEditor.essayList(list))], message: message)
    }
    /// A system's picked questions (the UC's 4 of 8), on its lead campus.
    public func setSystemPicks(_ sysId: String, _ ids: [String], model m: AppsModel) throws -> Change {
        guard let lead = Apps.systemLead(m.schools, sysId) else { throw Failure.cannot("None of its campuses is on your list.") }
        return try details(lead.path, [("essays", .array(Apps.withSystemPicks(lead.essays, sysId, ids)))], message: "\(Apps.system(sysId)?.short ?? sysId) questions picked")
    }

    public func toggleRequirement(_ s: School, at i: Int, na: Bool = false) throws -> Change {
        var list = s.requirements
        guard list.indices.contains(i) else { throw Failure.cannot("That item is gone.") }
        if na { list[i].na.toggle(); if list[i].na { list[i].done = false } } else { list[i].done.toggle(); if list[i].done { list[i].na = false } }
        return try details(s.path, [("requirements", .array(list.map(\.written)))], message: "\(s.short): \(list[i].t)")
    }
    public func addRequirement(_ s: School, _ text: String) throws -> Change {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw Failure.cannot("Type what to add.") }
        return try details(s.path, [("requirements", .array(s.requirements.map(\.written) + [.object([("t", .string(t))])]))], message: "\(s.short): \(t) added")
    }
    public func removeRequirement(_ s: School, at i: Int) throws -> Change {
        var list = s.requirements
        guard list.indices.contains(i) else { throw Failure.cannot("That item is gone.") }
        let t = list.remove(at: i).t
        return try details(s.path, [("requirements", .array(list.map(\.written)))], message: "\(s.short): \(t) removed")
    }

    // MARK: research

    /// One of the research numbers typed by hand (qs, usn, usne, acc), with the page it came from.
    public func setOwn(_ s: School, field: String, value: Double?, src: String? = nil) throws -> Change {
        try research(s, message: "\(s.short) \(field)") { r in
            r = r.setting(field, value.map { .number($0) })
            if let src {
                var so: JSONValue = r["sources"]?.object != nil ? r["sources"]! : .object([])
                so = so.setting(field, src.isEmpty ? nil : .string(src))
                r = r.setting("sources", (so.object ?? []).isEmpty ? nil : so)
            }
        }
    }
    /// A round's deadline, rate or label typed by hand (a rate typed here has no `rate_src`, so research never replaces it).
    public func setRound(_ s: School, _ k: String, dl: String?? = nil, rate: Double?? = nil, label: String?? = nil) throws -> Change {
        try research(s, message: "\(s.short) \(Apps.roundNames[k] ?? k)") { r in
            var rs: JSONValue = r["rounds"]?.object != nil ? r["rounds"]! : .object([])
            var x: JSONValue = rs[k]?.object != nil ? rs[k]! : .object([])
            if let dl { x = x.setting("dl", dl.map { .string($0) }) }
            if let rate { x = x.setting("rate", rate.map { .number($0) }).setting("rate_src", nil).setting("rate_of", nil).setting("rate_how", nil).setting("rate_note", nil) }
            if let label { x = x.setting("label", label.flatMap { $0.isEmpty ? nil : .string($0) }) }
            rs = rs.setting(k, (x.object ?? []).isEmpty ? nil : x)
            r = r.setting("rounds", (rs.object ?? []).isEmpty ? nil : rs)
        }
    }
    public func setLocation(_ s: School, _ loc: String) throws -> Change {
        try research(s, message: "\(s.short) location") { $0 = $0.setting("loc", loc.isEmpty ? nil : .string(loc)) }
    }
    /// A source link (named by the page's host, numbered when that host is there already).
    public func addSource(_ s: School, url u: String) throws -> Change {
        try research(s, message: "\(s.short) source") { r in
            var so: JSONValue = r["sources"]?.object != nil ? r["sources"]! : .object([])
            let k = URL(string: u)?.host?.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression) ?? "link"
            var key = k, n = 1
            while so[key] != nil { n += 1; key = "\(k) \(n)" }
            so = so.setting(key, .string(u))
            r = r.setting("sources", so)
        }
    }
    public func removeSource(_ s: School, key: String) throws -> Change {
        try research(s, message: "\(s.short) source removed") { r in
            let so = (r["sources"] ?? .object([])).setting(key, nil)
            r = r.setting("sources", (so.object ?? []).isEmpty ? nil : so)
        }
    }

    /// Save selected of the site check: `research` (dates, requirements found, sources, checked) and, for an applying school, the new
    /// requirements on its checklist too.
    public func saveFindings(_ s: School, take: [SiteFacts.Finding], host: String, today: String) throws -> Change {
        let take = take.filter { $0.on && $0.status != "same" && $0.kind != .none }
        guard !take.isEmpty else { throw Failure.cannot("Nothing is selected.") }
        let out = SiteFacts.apply(s.rawResearch, take: take, today: today)
        var values: [(String, JSONValue?)] = [("research", AppsEditor.clean(out.research))]
        if s.applying {
            let have = Set(s.requirements.map { SiteFacts.norm($0.t) })
            let add = out.reqs.filter { !have.contains(SiteFacts.norm($0.t)) }
            if !add.isEmpty {
                values.append(("requirements", .array(s.requirements.map(\.written) + add.map { .object([("t", JSONValue.string($0.t))] + ($0.src.isEmpty ? [] : [("src", .string($0.src))])) })))
            }
        }
        return try details(s.path, values, message: "\(s.short) site check (\(host))")
    }

    /// Claude's research saved: the profile, and the rounds' rates (a rate typed by hand is kept). The file is read again first (the research takes
    /// minutes, so an edit made meanwhile is kept).
    public func saveProfile(_ s: School, _ p: SchoolProfile, today: String) throws -> (Change, SchoolProfile.Applied) {
        let text = try read(url(s.path))
        let raw = (try? YamlValue.document(text))?["research"] ?? .object([])
        let out = p.apply(to: raw, today: today)
        return (try details(s.path, [("research", AppsEditor.clean(out.research))], message: "\(s.short) research"), out)
    }

    // MARK: the write order

    /// Accept: the suggested plan days onto the tasks (one write per tasks file) and the daily hours onto the overview.
    public func acceptSchedule(_ m: AppsModel, schedule: Schedule, hoursPerDay: Double, snapshot s: Snapshot) throws -> Change {
        try guardWritable()
        var byFile: [String: [(String, [String])]] = [:]
        var order: [String] = []
        for it in m.ordered {
            guard let days = schedule.byItem[it.id], !days.isEmpty, let t = s.tasks[it.id] else { continue }
            if byFile[t.file] == nil { order.append(t.file) }
            byFile[t.file, default: []].append((t.id, (t.plan.map(\.raw) + days).sorted()))
        }
        guard !order.isEmpty else { throw Failure.cannot("Nothing to plan.") }
        var changes: [Change] = []
        for f in order {
            let before = try read(url(f))
            var after = before
            for (id, days) in byFile[f]! {
                var seen = Set<String>()
                let unique = days.filter { seen.insert(String($0.prefix(10))).inserted }
                after = try YamlEdit.setField(after, id: id, key: "plan", yaml: YamlEdit.flow(unique))
            }
            let n = (try? TaskFile.parse(before, file: f, workstream: nil).tasks.count) ?? -1
            guard (try? TaskFile.parse(after, file: f, workstream: nil).tasks.count) == n else { throw TaskEditor.Failure.wouldBreak("\(f) would lose tasks") }
            changes.append(Change(file: f, before: before, after: after, message: ""))
        }
        for c in changes { try write(url(c.file), c.after) }
        var c = changes[0]
        c.message = "Planned \(schedule.byItem.count) piece\(schedule.byItem.count == 1 ? "" : "s") of work"
        c.also = Array(changes.dropFirst())
        if let ov = m.folder.overviewPath(s), let h = try? details(ov, [("writing_hours", .number(hoursPerDay))], message: c.message), h.before != h.after { c.also.append(h) }
        return c
    }
}
