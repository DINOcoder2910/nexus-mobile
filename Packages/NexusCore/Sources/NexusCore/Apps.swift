import Foundation

// Applications (the laptop's renderer/src/store/apps.js, ported): the schools (workstreams of kind school, `applications/<school>/workstream.yaml`),
// the deadline runway, the essay board with its "cut to N" ladders, the suggested write order and daily schedule (a SUGGESTION: nothing is
// written until Accept), the applying cap (10), the ED warning, the University of California campuses as one application, and what the
// Applications conversation tells Claude. Pure: the files come in through `AppsFolder`.

public enum Apps {
    public static let maxApplying = 10
    public static let roundKeys = ["ed", "ed2", "ea", "rd"]
    public static let roundNames = ["ed": "ED", "ed2": "ED2", "ea": "EA", "rd": "RD"]
    public static let roundLong = ["ed": "Early Decision", "ed2": "Early Decision II", "ea": "Early Action", "rd": "Regular Decision"]
    public static let binding: Set<String> = ["ed", "ed2"]

    // MARK: application systems (several campuses, one application)

    public struct AppSystem: Equatable {
        public let id, name, short: String
        public let unitids: [Int]
    }
    /// Berkeley, Los Angeles, San Diego, Santa Barbara, Irvine, Davis, Santa Cruz, Riverside, Merced.
    public static let systems = [AppSystem(id: "uc", name: "University of California", short: "UC", unitids: [110635, 110662, 110680, 110705, 110653, 110644, 110714, 110671, 445188])]
    public static func system(ofUnit id: Int?) -> AppSystem? { id.flatMap { u in systems.first { $0.unitids.contains(u) } } }
    public static func system(_ id: String?) -> AppSystem? { id.flatMap { i in systems.first { $0.id == i } } }

    public struct SystemQuestion: Equatable { public let id, short, fam, title: String }
    public struct SystemEssays: Equatable {
        public let name: String
        public let pick, lim: Int
        public let unit: String
        public let list: [SystemQuestion]
    }
    /// The UC Personal Insight Questions: answer 4 of the 8, 350 words each. Only the picked ones are stored, as `essays:` entries with
    /// `sys: uc` in ONE campus's workstream.yaml (`systemLead`), so the board shows each once.
    public static let systemEssays: [String: SystemEssays] = [
        "uc": SystemEssays(name: "Personal Insight Questions", pick: 4, lim: 350, unit: "words", list: [
            SystemQuestion(id: "uc-piq1", short: "Leadership", fam: "comm", title: "Describe an example of your leadership experience in which you have positively influenced others, helped resolve disputes or contributed to group efforts over time."),
            SystemQuestion(id: "uc-piq2", short: "Creativity", fam: "curio", title: "Every person has a creative side, and it can be expressed in many ways: problem solving, original and innovative thinking, and artistically, to name a few. Describe how you express your creative side."),
            SystemQuestion(id: "uc-piq3", short: "Talent or skill", fam: "story", title: "What would you say is your greatest talent or skill? How have you developed and demonstrated that talent over time?"),
            SystemQuestion(id: "uc-piq4", short: "Educational opportunity or barrier", fam: "story", title: "Describe how you have taken advantage of a significant educational opportunity or worked to overcome an educational barrier you have faced."),
            SystemQuestion(id: "uc-piq5", short: "Significant challenge", fam: "story", title: "Describe the most significant challenge you have faced and the steps you have taken to overcome this challenge. How has this challenge affected your academic achievement?"),
            SystemQuestion(id: "uc-piq6", short: "Academic subject", fam: "curio", title: "Think about an academic subject that inspires you. Describe how you have furthered this interest inside and/or outside of the classroom."),
            SystemQuestion(id: "uc-piq7", short: "Community", fam: "comm", title: "What have you done to make your school or your community a better place?"),
            SystemQuestion(id: "uc-piq8", short: "Why you", fam: "bg", title: "Beyond what has already been shared in your application, what do you believe makes you a strong candidate for admissions to the University of California?"),
        ]),
    ]

    /// The campus holding a system's picked essays: the one that holds them, else the first applying campus in the system's order, else the first.
    public static func systemLead(_ schools: [School], _ sysId: String) -> School? {
        let cs = schools.filter { $0.system == sysId && !$0.dropped }
        if cs.isEmpty { return nil }
        if let holder = cs.first(where: { $0.essays.contains { $0.sys == sysId } }) { return holder }
        let order = system(sysId)?.unitids ?? []
        func rank(_ s: School) -> Int { s.unitid.flatMap { order.firstIndex(of: $0) } ?? 99 }
        return cs.sorted { a, b in
            if a.applying != b.applying { return a.applying }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }.first
    }
    /// The ids picked so far, in the list's order.
    public static func systemPicked(_ schools: [School], _ sysId: String) -> [String] {
        guard let lead = systemLead(schools, sysId), let def = systemEssays[sysId] else { return [] }
        let have = Set(lead.essays.filter { $0.sys == sysId }.map(\.id))
        return def.list.filter { have.contains($0.id) }.map(\.id)
    }
    /// The lead's essays with the picks `ids` in place of the old ones (its own prompts kept; a question still picked keeps its link and
    /// family; a new one is added; one no longer picked goes), as the entries to write.
    public static func withSystemPicks(_ essays: [Essay], _ sysId: String, _ ids: [String]) -> [JSONValue] {
        guard let def = systemEssays[sysId] else { return essays.map(\.written) }
        let old = Dictionary(essays.filter { $0.sys == sysId }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let want = Set(ids)
        let picks: [JSONValue] = def.list.filter { want.contains($0.id) }.prefix(def.pick).map { q in
            if let e = old[q.id] { return e.written }
            return .object([("id", .string(q.id)), ("title", .string(q.title)), ("lim", .number(Double(def.lim))), ("fam", .string(q.fam)), ("req", .bool(true)), ("sys", .string(sysId))])
        }
        return essays.filter { $0.sys != sysId }.map(\.written) + picks
    }
    /// The board's essays: a system's essays once (from its lead), the rest as they are.
    public static func dedupeSystemEssays(_ essays: [Essay], _ schools: [School]) -> [Essay] {
        var leads: [String: String] = [:]
        var out: [Essay] = []
        for e in essays {
            guard let sys = e.sys else { out.append(e); continue }
            if leads[sys] == nil { leads[sys] = systemLead(schools, sys)?.id ?? e.school }
            if leads[sys] == e.school { out.append(e) }
        }
        return out
    }
    /// How many applications a list of schools is: a system's campuses count once.
    public static func appCount(_ schools: [School]) -> Int {
        var seen = Set<String>(), n = 0
        for s in schools {
            if let sys = s.system { if seen.contains(sys) { continue }; seen.insert(sys) }
            n += 1
        }
        return n
    }

    // MARK: essay families

    public struct Family: Equatable { public let id, name, tip: String }
    public static let families = [
        Family(id: "story", name: "Your story & adversity", tip: "Write the main statement first; shorter adversity answers are cuts of one scene."),
        Family(id: "bg", name: "Background & lived experience", tip: "The same stories in several lengths. Keep the longest as the master."),
        Family(id: "why", name: "Why us", tip: "Write the longest once, then trim. Swap the specifics, keep the spine."),
        Family(id: "dis", name: "Disagreement & dialogue", tip: "One disagreement story fits every school that asks."),
        Family(id: "curio", name: "Curiosity & research", tip: "Reading list, research mentor, dream class: all pull from the same brag sheet."),
        Family(id: "comm", name: "Community & belonging", tip: "Borrow from the background essay; name real groups."),
        Family(id: "fun", name: "Just for fun", tip: "Short, personality-first. Quick wins."),
        Family(id: "other", name: "Other prompts", tip: "Not grouped yet: pick a family on a card to group it."),
    ]
    public static func family(_ id: String) -> Family { families.first { $0.id == id } ?? families[families.count - 1] }

    /// A best guess from the prompt's words (the user can change it on the card).
    public static func guessFamily(_ text: String) -> String {
        let s = text.lowercased()
        func has(_ re: String) -> Bool { s.range(of: re, options: .regularExpression) != nil }
        if has(#"\bjoy\b|snack|movie|roommate|\bpaint\b|\bfun\b|theme song|three words|thank-you|note to"#) { return "fun" }
        if has(#"disagree|difference of opinion|engaging across|bridge"#) { return "dis" }
        if has(#"assignment"#) { return "curio" }
        if has(#"background|identity|lived|growing up|household|upbringing|life experiences|viewpoints|diversity|dare to grow"#) { return "bg" }
        if has(#"\bwhy\b|draws you|attracts you|what about being a student|plan to pursue|interested in (studying|attending|pursuing)|location|appeal|engaged with|learned about|academic (areas|interests)|goals after graduating|exploration of"#) { return "why" }
        if has(#"adversity|overcome|personal growth"#) || (has(#"\bchallenge\b"#) && !has(#"\bchallenge\b (that )?society"#)) { return "story" }
        if has(#"communit|belong|student group"#) { return "comm" }
        if has(#"intellectual|research|curious|\bclass\b|course|\bread|excited about learning|dream up|interdisciplinary|curriculum|traits in|assignment|first-choice major|academic subject|inspires you"#) { return "curio" }
        return "other"
    }

    // MARK: small helpers

    public static func slugify(_ s: String) -> String {
        let t = s.lowercased().replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return t.isEmpty ? "school" : t
    }
    /// "2026-11-01", "1 Nov 2026" or "1 Nov" (the next such day from `today`) -> ISO, else nil.
    public static func parseDateInput(_ text: String, today: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if Days.isIso(t) { return t }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        let parts = t.replacingOccurrences(of: ".", with: "").split(separator: " ").map(String.init)
        guard parts.count == 2 || parts.count == 3, let d = Int(parts[0]), d >= 1, d <= 31, parts[1].count >= 3,
              let mo = months.firstIndex(of: String(parts[1].prefix(3)).lowercased()) else { return nil }
        func p(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        if parts.count == 3 { guard let y = Int(parts[2]), parts[2].count == 4 else { return nil }; return "\(y)-\(p(mo + 1))-\(p(d))" }
        let y = Int(today.prefix(4)) ?? 2026
        let iso = "\(y)-\(p(mo + 1))-\(p(d))"
        return iso < today ? "\(y + 1)-\(p(mo + 1))-\(p(d))" : iso
    }
    /// "1 Nov".
    public static func short(_ iso: String?) -> String {
        guard let iso, Days.isIso(iso), let m = Int(iso.dropFirst(5).prefix(2)), let d = Int(iso.suffix(2)) else { return "" }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(d) \(months[max(0, min(11, m - 1))])"
    }
    /// Hours as "2h", "1h 30m", "45m".
    public static func dur(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        if m <= 0 { return "0m" }
        if m < 60 { return "\(m)m" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
}

// MARK: - the schools

public struct Round: Equatable {
    public var rate: Double?
    public var dl: String?
    public var label: String?
    /// The date came from an old file's `deadlines:` key.
    public var legacy = false
    /// A rate Claude's research found: its page, year and whether it was worked out.
    public var rateSrc: String?
    public var rateOf = ""
    public var rateHow = ""
    public var rateNote = ""
    /// A rate from the universities database (its published one): the fall of entry and its page.
    public var dbYear: Int?
    public var dbSrc: String?
    public init(rate: Double? = nil, dl: String? = nil, label: String? = nil) { self.rate = rate; self.dl = dl; self.label = label }

    /// Where a round's rate came from, for a note under it.
    public var whence: String {
        guard rate != nil else { return "" }
        if let src = dbSrc { return "published rate\(dbYear.map { ", fall \($0) entry" } ?? "")\(src.isEmpty ? "" : "; " + Apps.bareHost(src))" }
        if let src = rateSrc { return "\(rateOf.isEmpty ? "" : rateOf + ", ")\(rateHow == "derived" ? "worked out from the totals" : "reported")\(rateNote.isEmpty ? "" : ": " + rateNote); from Claude's research, \(Apps.bareHost(src))" }
        return "your value"
    }
}

extension Apps {
    static func bareHost(_ u: String) -> String {
        u.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: .regularExpression)
    }
}

public struct Essay: Identifiable, Equatable {
    public var id: String
    /// The school (or general workstream) it belongs to.
    public var school: String
    public var title: String
    public var q = ""
    public var lim: Int?
    public var unit = "words"
    public var fam = "other"
    public var doc = ""
    public var docTitle = ""
    public var req = false, opt = false, pick = false, picked = false, approx = false
    public var note = ""
    public var sys: String?
    public var idx = 0
    /// A Common App or overview essay (not a school's).
    public var general = false
    public var generalName = ""
    /// The workstream.yaml that holds it.
    public var path = ""

    public init(id: String, school: String, title: String) { self.id = id; self.school = school; self.title = title }

    public static func from(_ v: JSONValue, index i: Int, school: String) -> Essay {
        let o: JSONValue = v.object != nil ? v : .object([("title", .string(v.text1 ?? ""))])
        var e = Essay(id: o["id"]?.text1 ?? "\(school)-\(i + 1)", school: school, title: o["title"]?.text1 ?? "")
        e.q = o["q"]?.text1 ?? ""
        e.lim = o["lim"]?.num.map { Int($0) }
        e.unit = o["unit"]?.text1 == "characters" ? "characters" : "words"
        e.fam = o["fam"]?.text1 ?? Apps.guessFamily(e.title)
        e.doc = o["doc"]?.text1 ?? ""
        e.docTitle = o["docTitle"]?.text1 ?? ""
        e.req = o["req"]?.bool == true; e.opt = o["opt"]?.bool == true; e.pick = o["pick"]?.bool == true
        e.picked = o["picked"]?.bool == true; e.approx = o["approx"]?.bool == true
        e.note = o["note"]?.text1 ?? ""
        e.sys = o["sys"]?.text1
        e.idx = i
        return e
    }

    /// As the file writes it (the laptop's essayWrite: empty values left out).
    public var written: JSONValue {
        var o: [(String, JSONValue)] = [("id", .string(id)), ("title", .string(title))]
        if !q.isEmpty { o.append(("q", .string(q))) }
        if let lim { o.append(("lim", .number(Double(lim)))) }
        if unit == "characters" { o.append(("unit", .string("characters"))) }
        if !fam.isEmpty { o.append(("fam", .string(fam))) }
        if !doc.isEmpty { o.append(("doc", .string(doc))) }
        if !docTitle.isEmpty { o.append(("docTitle", .string(docTitle))) }
        if req { o.append(("req", .bool(true))) }
        if opt { o.append(("opt", .bool(true))) }
        if pick { o.append(("pick", .bool(true))) }
        if picked { o.append(("picked", .bool(true))) }
        if approx { o.append(("approx", .bool(true))) }
        if !note.isEmpty { o.append(("note", .string(note))) }
        if let sys { o.append(("sys", .string(sys))) }
        return .object(o)
    }

    /// "350 words", "150 characters", "~250 words".
    public var limitText: String {
        guard let lim else { return "no limit" }
        return unit == "characters" ? "\(lim) characters" : "\(approx ? "~" : "")\(lim) words"
    }
}

public struct Requirement: Equatable {
    public var t: String
    public var done = false, na = false
    public var note = "", src = ""
    public init(t: String, done: Bool = false, na: Bool = false, note: String = "", src: String = "") { self.t = t; self.done = done; self.na = na; self.note = note; self.src = src }
    public var written: JSONValue {
        var o: [(String, JSONValue)] = [("t", .string(t))]
        if done { o.append(("done", .bool(true))) }
        if na { o.append(("na", .bool(true))) }
        if !note.isEmpty { o.append(("note", .string(note))) }
        if !src.isEmpty { o.append(("src", .string(src))) }
        return .object(o)
    }
}

public struct ResearchPrompt: Equatable {
    public var t: String
    public var lim: Int?
    public var unit: String
    public var why: Bool
}

public struct Research: Equatable {
    public var qs, usn, usne, acc: Double?
    public var rounds: [String: Round] = [:]
    public var notes = ""
    public var prompts: [ResearchPrompt] = []
    /// Source links by what they back ("ED date", "Requirements", a host…), in the file's order.
    public var sources: [(String, String)] = []
    public var loc = ""
    public var reqs: [(t: String, src: String)] = []
    public var checked: String?
    public var checkedLegacy = false

    public static func == (a: Research, b: Research) -> Bool {
        a.qs == b.qs && a.usn == b.usn && a.usne == b.usne && a.acc == b.acc && a.rounds == b.rounds && a.notes == b.notes && a.prompts == b.prompts
            && a.sources.map { $0.0 + "\u{1}" + $0.1 } == b.sources.map { $0.0 + "\u{1}" + $0.1 } && a.loc == b.loc && a.reqs.map { $0.t + "\u{1}" + $0.src } == b.reqs.map { $0.t + "\u{1}" + $0.src }
            && a.checked == b.checked && a.checkedLegacy == b.checkedLegacy
    }
}

public struct School: Identifiable, Equatable {
    public var id: String
    /// Its workstream.yaml and tasks.yaml, relative to the data folder.
    public var path: String
    public var tasksPath: String
    public var folder: String
    public var name: String
    public var short: String
    public var applying = false
    public var dropped = false
    /// The day the application was sent (Mark as applied); the school stays Applying.
    public var applied: String?
    public var round: String?
    /// The school's own soft deadline.
    public var internalDate: String?
    public var unitid: Int?
    public var system: String?
    public var tier: String?
    public var tierLevel: Int?
    public var research = Research()
    /// The whole workstream.yaml and its `research:` as written (for edits that keep what this app doesn't know).
    public var raw: JSONValue = .object([])
    public var rawResearch: JSONValue = .object([])
    public var essays: [Essay] = []
    public var requirements: [Requirement] = []

    public var deadline: String? { round.flatMap { research.rounds[$0]?.dl } }
    public func roundLabel(_ k: String) -> String { research.rounds[k]?.label ?? Apps.roundNames[k] ?? k.uppercased() }
    public var nextDeadline: String? { Apps.roundKeys.compactMap { research.rounds[$0]?.dl }.sorted().first }
    /// "Applying, ED 1 Nov", "Applied 3 Nov", "Considering".
    public var statusText: String {
        if !applying { return "Considering" }
        if let a = applied { return "Applied \(Apps.short(a))" }
        return "Applying" + (round.map { ", " + (Apps.roundNames[$0] ?? $0.uppercased()) } ?? "")
    }

    /// `d`: the workstream.yaml as a JSONValue; `taskCount`: its tasks.yaml's top-level tasks (a school with tasks and no `applying:` is applying).
    public static func from(_ d: JSONValue, workstream w: Workstream, taskCount: Int) -> School {
        let res = d["research"]?.object != nil ? d["research"]! : .object([])
        let name = w.name
        var s = School(id: w.id, path: w.folder + "/workstream.yaml", tasksPath: w.tasksFile, folder: w.folder, name: name,
                       short: d["short"]?.text1 ?? name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression))
        s.applying = d["applying"].map { !$0.isNull ? $0.bool == true : taskCount > 0 } ?? (taskCount > 0)
        s.dropped = d["dropped"]?.bool == true
        s.applied = d["applied"]?.iso
        s.round = d["round"]?.text1?.lowercased()
        s.internalDate = d["internal"]?.iso
        s.unitid = d["unitid"]?.num.map { Int($0) }
        s.system = Apps.system(ofUnit: s.unitid)?.id
        let tier = d["tier"]?.text1?.lowercased()
        if let tier, Unis.tiers.contains(tier) {
            s.tier = tier
            if let lv = d["tier_level"]?.num, lv >= 1, lv <= 5 { s.tierLevel = Int(lv.rounded()) }
        }
        let legacy = d["deadlines"]?.object != nil ? d["deadlines"] : res["deadlines"]?.object != nil ? res["deadlines"] : nil
        var r = Research()
        r.qs = res["qs"]?.num; r.usn = res["usn"]?.num; r.usne = res["usne"]?.num; r.acc = res["acc"]?.num
        r.rounds = normRounds(res["rounds"], legacy: legacy)
        r.notes = res["notes"]?.text1 ?? ""
        r.prompts = (res["prompts"]?.array ?? []).compactMap { p in
            guard let t = p["t"]?.text1, !t.isEmpty else { return nil }
            return ResearchPrompt(t: t, lim: p["lim"]?.num.map { Int($0) }, unit: p["unit"]?.text1 == "characters" ? "characters" : "words", why: p["why"]?.bool == true)
        }
        r.sources = (res["sources"]?.object ?? []).compactMap { k, v in v.text1.map { (k, $0) } }
        r.loc = res["loc"]?.text1 ?? ""
        r.reqs = (res["reqs"]?.array ?? []).compactMap { x -> (t: String, src: String)? in
            if x.object != nil { let t = x["t"]?.text1 ?? ""; return t.isEmpty ? nil : (t, x["src"]?.text1 ?? "") }
            return x.text1.map { ($0, "") }
        }
        let verified = d["verified"] ?? res["verified"]
        let verifiedIso = verified.flatMap { v in v.object != nil ? (v["date"] ?? v["on"])?.iso : v.iso }
        r.checked = res["checked"]?.iso ?? verifiedIso
        r.checkedLegacy = res["checked"]?.iso == nil && verifiedIso != nil
        s.research = r
        s.raw = d
        s.rawResearch = res
        let wsPath = s.path
        s.essays = (d["essays"]?.array ?? []).enumerated().map { (i, v) -> Essay in var e = Essay.from(v, index: i, school: w.id); e.path = wsPath; return e }
        s.requirements = (d["requirements"]?.array ?? []).map { x -> Requirement in
            if x.object != nil { return Requirement(t: x["t"]?.text1 ?? "", done: x["done"]?.bool == true, na: x["na"]?.bool == true, note: x["note"]?.text1 ?? "", src: x["src"]?.text1 ?? "") }
            return Requirement(t: x.text1 ?? "")
        }
        return s
    }

    static func normRounds(_ r: JSONValue?, legacy: JSONValue?) -> [String: Round] {
        var out: [String: Round] = [:]
        for k in Apps.roundKeys {
            let v = r?[k]
            let old: String? = legacy?[k].flatMap { $0.object != nil ? $0["dl"]?.iso : $0.iso }
            if v == nil || v!.isNull || v!.bool == false {
                if let old { var x = Round(dl: old); x.legacy = true; out[k] = x }
                continue
            }
            let o = v!.object != nil ? v! : .object([])
            let dl = o["dl"]?.iso
            var x = Round(rate: o["rate"]?.num, dl: dl ?? old, label: o["label"]?.text1)
            if dl == nil && old != nil { x.legacy = true }
            if x.rate != nil, let src = o["rate_src"]?.text1, !src.isEmpty {
                x.rateSrc = src
                x.rateOf = o["rate_of"]?.text1 ?? ""
                x.rateHow = o["rate_how"]?.text1 == "derived" ? "derived" : "reported"
                x.rateNote = o["rate_note"]?.text1 ?? ""
            }
            out[k] = x
        }
        return out
    }
}

// MARK: - the folder

/// The Applications part of a data folder, read once: the schools (workstreams of kind school), the removed ones, the other workstreams of
/// the group (the overview and the shared Common App), and `tiers.yaml`.
public struct AppsFolder {
    public var schools: [School] = []
    public var dropped: [School] = []
    /// The overview, Common App …: the workstreams in the schools' groups that are not schools, with their workstream.yaml.
    public var general: [(ws: Workstream, details: JSONValue)] = []
    /// The group that holds the schools ("applications").
    public var group = "applications"
    public var tiersText: String?
    /// workstream.yaml files that do not parse (their school is left out).
    public var problems: [String] = []

    public init() {}

    /// `read`: a file of the data folder by its relative path, or nil.
    public init(_ s: Snapshot, read: (String) -> String?) {
        let all = s.groups.flatMap { s.workstreams(in: $0) }
        let schoolWs = all.filter { $0.kind == "school" }
        if let g = schoolWs.first?.group { group = g }
        let groups = Set(schoolWs.map(\.group))
        for w in schoolWs {
            guard let text = read(w.folder + "/workstream.yaml") else { continue }
            guard let d = try? YamlValue.document(text) else { problems.append(w.folder + "/workstream.yaml"); continue }
            let sc = School.from(d, workstream: w, taskCount: (s.top[w.tasksFile] ?? []).count)
            if sc.dropped { dropped.append(sc) } else { schools.append(sc) }
        }
        for w in all where groups.contains(w.group) && w.kind != "school" {
            let d = read(w.folder + "/workstream.yaml").flatMap { try? YamlValue.document($0) } ?? .object([])
            general.append((w, d))
        }
        tiersText = read(group + "/" + Unis.tiersFile)
    }

    public var generalEssays: [Essay] {
        general.flatMap { g in (g.details["essays"]?.array ?? []).enumerated().map { (i, v) -> Essay in
            var e = Essay.from(v, index: i, school: g.ws.id)
            e.general = true; e.generalName = g.ws.name; e.path = g.ws.folder + "/workstream.yaml"
            return e
        } }
    }
    /// The overview's `internal_rule: {for, date}`: the school deadline that goes with a round date.
    public var internalRule: (for: String, date: String)? {
        for g in general { if let r = g.details["internal_rule"], let f = r["for"]?.iso, let d = r["date"]?.iso { return (f, d) } }
        return nil
    }
    public var writingHours: Double? {
        for g in general { if let v = g.details["writing_hours"]?.num, v > 0 { return v } }
        return nil
    }
    /// Where the accepted daily hours go: the group's default workstream, else its first other workstream.
    public func overviewPath(_ s: Snapshot) -> String? {
        let def = s.groups.first { $0.id == group }?.defaultWorkstream
        if let d = def, let w = general.first(where: { $0.ws.id == d || $0.ws.folder.hasSuffix("/" + d) }) { return w.ws.folder + "/workstream.yaml" }
        return general.first.map { $0.ws.folder + "/workstream.yaml" }
    }
}

// MARK: - the cap and the ED warning

public struct CapStatus: Equatable {
    public var n, max: Int
    public var over, atMax: Bool
    public var text: String { "\(n) of \(max) applying" }
}

extension Apps {
    public static func capStatus(_ schools: [School]) -> CapStatus {
        let n = appCount(schools.filter(\.applying))
        return CapStatus(n: n, max: maxApplying, over: n > maxApplying, atMax: n >= maxApplying)
    }
    /// Starting `round` at `schoolId` while another applying school has a binding ED: the warning, else nil.
    public static func edConflict(_ schools: [School], schoolId: String, round: String) -> String? {
        guard round == "ed", let other = schools.first(where: { $0.applying && $0.id != schoolId && $0.round == "ed" }) else { return nil }
        let me = schools.first { $0.id == schoolId }
        return "\(other.short) ED is binding. You can only be bound to one school, so applying ED to \(me?.short ?? "this school") as well would break the ED agreement. Choose RD or EA there, or move \(other.short) first."
    }
}

// MARK: - the work: leaf tasks of the applying schools

public struct WorkItem: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var school: String?
    public var schoolName: String
    /// Its tasks.yaml.
    public var path: String
    public var due: String?
    /// The date is the school's, not the task's own.
    public var inherited: Bool
    public var hours: Double
    public var plan: [String]
    public var overdue: Bool
    public var general: Bool
    // the write order adds these
    public var reuse = 0
    public var why = ""
}

extension Apps {
    /// An open task with no open subtasks. Its date is its own `due`, else its school's internal deadline, else the school's round deadline.
    /// Hours: its estimate, else its parent's estimate shared among the subtasks that have none.
    public static func workItems(_ s: Snapshot, folder f: AppsFolder, today: String) -> [WorkItem] {
        var items: [WorkItem] = []
        let byId = Dictionary(f.schools.filter(\.applying).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let gen = Dictionary(f.general.map { ($0.ws.id, $0.ws) }, uniquingKeysWith: { a, _ in a })
        for g in s.groups {
            for w in s.workstreams(in: g) {
                let school = byId[w.id]
                if school == nil && gen[w.id] == nil { continue }
                for id in s.order {
                    guard let t = s.tasks[id], t.workstream == w.id, t.file == w.tasksFile else { continue }
                    if t.done || t.someday { continue }
                    if s.children(of: t).contains(where: { !$0.done }) { continue }
                    let own = t.due.flatMap { Days.isIso($0) ? $0 : nil }
                    let inh = school.flatMap { $0.internalDate ?? $0.deadline }
                    let due = own ?? inh
                    var hours = t.estHours ?? 0
                    if hours == 0, let p = t.parent.flatMap({ s.tasks[$0] }), let pe = p.estHours {
                        let kids = s.children(of: p).filter { !$0.done && $0.est == nil }
                        let used = s.children(of: p).filter { !$0.done && $0.est != nil }.reduce(0) { $0 + ($1.estHours ?? 0) }
                        hours = max(0, pe - used) / Double(max(1, kids.count))
                        hours = (hours * 4).rounded() / 4
                    }
                    items.append(WorkItem(id: t.id, title: t.title.replacingOccurrences(of: "**", with: ""), school: school?.id,
                                          schoolName: school?.short ?? generalLabel(w), path: w.tasksFile, due: due, inherited: own == nil && due != nil,
                                          hours: hours, plan: t.plan.map { String($0.day.prefix(10)) }, overdue: due.map { $0 < today } ?? false, general: school == nil))
                }
            }
        }
        return items
    }
    static func generalLabel(_ w: Workstream) -> String {
        w.folder.lowercased().contains("common") || w.name.lowercased().contains("common") ? "Common App" : "General"
    }
}

// MARK: - the runway

public struct Gate: Identifiable, Equatable {
    public var date: String?
    public var internalOf: [String] = []
    public var deadlineOf: [String] = []
    public var items: [WorkItem] = []
    /// An internal date only: softer than a real deadline.
    public var soft = false
    public var days = 0
    public var hours = 0.0
    public var rounds: [String] = []
    public var label = ""
    public var binding = false
    public var id: String { date ?? "none" }
}

public struct Runway: Equatable {
    public var gates: [Gate]
    public var undated: Gate?
    public var openHours: Double
}

extension Apps {
    /// A gate per date among the applying schools' internal and round deadlines and their work, plus "no date yet".
    public static func buildRunway(_ items: [WorkItem], schools: [School], today: String) -> Runway {
        let ap = schools.filter(\.applying)
        var map: [String: Gate] = [:]
        func gate(_ d: String, _ f: (inout Gate) -> Void) { var g = map[d] ?? Gate(date: d); f(&g); map[d] = g }
        for s in ap {
            if let i = s.internalDate { gate(i) { $0.internalOf.append(s.id) } }
            if let dl = s.deadline { gate(dl) { $0.deadlineOf.append(s.id) } }
        }
        var none = Gate(date: nil)
        for it in items { if let d = it.due { gate(d) { $0.items.append(it) } } else { none.items.append(it) } }
        let byId = Dictionary(ap.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var gates = map.values.sorted { ($0.date ?? "") < ($1.date ?? "") }
        for i in gates.indices {
            var g = gates[i]
            let dls = g.deadlineOf.compactMap { byId[$0] }
            g.soft = dls.isEmpty && !g.internalOf.isEmpty
            g.days = Days.between(today, g.date ?? today)
            g.hours = g.items.reduce(0) { $0 + $1.hours }
            var seen = Set<String>()
            g.rounds = dls.compactMap { $0.round.flatMap { roundNames[$0] } }.filter { seen.insert($0).inserted }
            g.label = g.soft ? "School deadline" : dls.map { "\($0.short) \(roundNames[$0.round ?? ""] ?? "")" }.joined(separator: ", ")
            g.binding = dls.contains { binding.contains($0.round ?? "") }
            g.items.sort { $0.hours != $1.hours ? $0.hours > $1.hours : $0.title < $1.title }
            gates[i] = g
        }
        return Runway(gates: gates, undated: none.items.isEmpty ? nil : none, openHours: items.reduce(0) { $0 + $1.hours })
    }
}

// MARK: - the essay board

public struct BoardRung: Equatable {
    public var essay: Essay
    /// "cut to 150", "same length" or "".
    public var cut: String
}

public struct BoardRow: Identifiable, Equatable {
    public var fam: Apps.Family
    public var master: Essay
    public var ladder: [BoardRung]
    public var count: Int
    public var schools: [String]
    public var max: Int
    public var id: String { fam.id }
}

extension Apps {
    public static func boardRows(_ schools: [School], _ essays: [Essay]) -> [BoardRow] {
        let byId = Dictionary(schools.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func earliest(_ e: Essay) -> String { byId[e.school].flatMap { $0.internalDate ?? $0.deadline } ?? "9999" }
        var rows: [BoardRow] = []
        let known = Set(families.map(\.id))
        for f in families {
            let ps = essays.filter { (known.contains($0.fam) ? $0.fam : "other") == f.id }
            if ps.isEmpty { continue }
            let w = ps.filter { $0.unit == "words" }.sorted { a, b in
                if (a.lim ?? 0) != (b.lim ?? 0) { return (a.lim ?? 0) > (b.lim ?? 0) }
                if earliest(a) != earliest(b) { return earliest(a) < earliest(b) }
                return a.title < b.title
            }
            let seq = w + ps.filter { $0.unit != "words" }
            let master = seq[0], rest = Array(seq.dropFirst())
            let ladder = rest.enumerated().map { i, e -> BoardRung in
                let prev = i == 0 ? master : rest[i - 1]
                var cut = ""
                if prev.unit == "words", e.unit == "words", let l = e.lim, let pl = prev.lim { cut = l < pl ? "cut to \(l)" : "same length" }
                return BoardRung(essay: e, cut: cut)
            }
            var seen = Set<String>()
            rows.append(BoardRow(fam: f, master: master, ladder: ladder, count: ps.count, schools: ps.map(\.school).filter { seen.insert($0).inserted },
                                 max: Swift.max(1, w.map { $0.lim ?? 0 }.max() ?? 0)))
        }
        return rows
    }
    static func mastersBySchool(_ rows: [BoardRow]) -> [String: Int] {
        var m: [String: Int] = [:]
        for r in rows where !r.ladder.isEmpty { m[r.master.school, default: 0] += r.ladder.count }
        return m
    }
    /// The shortest "why us" limit of a school: its own why essays, else its research's prompts marked why.
    public static func shortestWhy(_ s: School, essays: [Essay]) -> Int? {
        let own = essays.filter { $0.school == s.id && $0.fam == "why" && $0.unit == "words" }.compactMap(\.lim)
        let rs = s.research.prompts.filter(\.why).compactMap(\.lim)
        return (own + rs).min()
    }
}

// MARK: - the suggested write order and schedule

public struct Pace: Equatable {
    public var hoursPerDay: Double
    public var forDate: String
    public var hours: Double
    public var days: Int
}

public struct Schedule: Equatable {
    public var perDay: [String: Double] = [:]
    public var byItem: [String: [String]] = [:]
    public var late: [String] = []
    public var days: [String] { perDay.keys.sorted() }
    public var hours: Double { perDay.values.reduce(0, +) }
}

extension Apps {
    public static func orderItems(_ items: [WorkItem], rows: [BoardRow], today: String) -> [WorkItem] {
        let reuse = mastersBySchool(rows)
        func score(_ i: WorkItem) -> Int { i.school.flatMap { reuse[$0] } ?? 0 }
        return items.filter { $0.hours > 0 || $0.due != nil }.sorted { a, b in
            let da = a.due ?? "9999", db = b.due ?? "9999"
            if da != db { return da < db }
            if score(a) != score(b) { return score(a) > score(b) }
            if a.hours != b.hours { return a.hours > b.hours }
            return a.title < b.title
        }.map { i -> WorkItem in var x = i; x.reuse = score(i); x.why = whyText(i, score(i), today); return x }
    }
    static func whyText(_ i: WorkItem, _ reuse: Int, _ today: String) -> String {
        var bits: [String] = []
        if let d = i.due {
            let n = Days.between(today, d)
            bits.append(n < 0 ? "\(-n) day\(n == -1 ? "" : "s") late" : n == 0 ? "due today" : "due in \(n) day\(n == 1 ? "" : "s")")
        } else { bits.append("no date yet") }
        if reuse > 0 { bits.append("\(i.schoolName) holds the master of \(reuse) other essay\(reuse == 1 ? "" : "s")") }
        if i.inherited { bits.append("date from the school deadline") }
        return bits.joined(separator: "; ")
    }
    /// Hours already planned per day (an accepted plan): the task's estimate shared over its plan days.
    public static func plannedHours(_ items: [WorkItem]) -> [String: Double] {
        var m: [String: Double] = [:]
        for i in items where !i.plan.isEmpty && i.hours > 0 { let per = i.hours / Double(i.plan.count); for d in i.plan { m[d, default: 0] += per } }
        return m
    }
    /// The pace that would finish the work due by the nearest dated gate: open hours / days left, in half hours.
    public static func suggestPace(_ ordered: [WorkItem], today: String) -> Pace? {
        let open = ordered.filter { $0.hours > 0 && $0.plan.isEmpty && $0.due != nil }
        guard let first = open.first?.due else { return nil }
        let hrs = open.filter { ($0.due ?? "") <= first }.reduce(0) { $0 + $1.hours }
        let days = max(1, Days.between(today, first))
        return Pace(hoursPerDay: max(0.5, (hrs / Double(days) * 2).rounded(.up) / 2), forDate: first, hours: hrs, days: days)
    }
    /// The unplanned items spread over the days from today at `hoursPerDay`, in order.
    public static func suggestSchedule(_ ordered: [WorkItem], today: String, hoursPerDay: Double, maxDays: Int = 120) -> Schedule {
        var out = Schedule()
        let already = plannedHours(ordered)
        var day = today
        func room(_ d: String) -> Double { max(0, hoursPerDay - (already[d] ?? 0) - (out.perDay[d] ?? 0)) }
        for it in ordered {
            guard it.hours > 0, it.plan.isEmpty else { continue }
            var left = it.hours, days: [String] = [], guardN = 0
            while left > 1e-9 && guardN < maxDays {
                guardN += 1
                let r = room(day)
                if r <= 1e-9 { day = Days.add(day, 1); continue }
                let put = min(r, left)
                out.perDay[day, default: 0] += put
                left -= put
                if !days.contains(day) { days.append(day) }
                if room(day) <= 1e-9 && left > 1e-9 { day = Days.add(day, 1) }
            }
            out.byItem[it.id] = days
            if let due = it.due, let last = days.last, last > due { out.late.append(it.id) }
        }
        return out
    }
}

// MARK: - a round's rate: the folder's, else the database's

extension Apps {
    /// A round's admit rate, in this order: the folder's (yours, or Claude's research with its page), then the database's published one, else
    /// none. -> the folder's round with `rate` filled in, or nil when there is no round at all.
    public static func roundInfo(_ s: School?, _ u: UniSchool?, _ k: String) -> Round? {
        let r = s?.research.rounds[k]
        if let r, r.rate != nil { return r }
        if let d = u?.rounds[k], let rate = d.rate {
            var x = r ?? Round()
            x.rate = rate; x.dbYear = d.year; x.dbSrc = d.src
            return x
        }
        return r
    }
    public static func roundRate(_ s: School?, _ u: UniSchool?, _ k: String) -> Double? { roundInfo(s, u, k)?.rate }
    public static func bestEarly(_ s: School?, _ u: UniSchool?) -> Double? { ["ed", "ed2", "ea"].compactMap { roundRate(s, u, $0) }.max() }
}

// MARK: - what the Applications conversation tells Claude

extension Apps {
    public static let claudeIntro = "This is the Applications conversation: the user's college applications. Each school is a folder (its path is in the list below) holding workstream.yaml (its details: applying, round, internal, applied, tier, tier_level, research with rounds and reqs, essays, requirements) and notes.md (the user's free notes about it; \"no notes.md yet\" when it does not exist). The summary below is short on purpose: Read a school's files for detail. When the user asks, you may add to a school's notes.md or update its workstream.yaml with Edit or Write (create notes.md with a \"# <school name>\" heading when it is missing). Every change is shown to the user to accept, so keep each one small and keep the YAML keys as they are."
    public static let claudeMax = 14000

    public static func claudeSchoolLine(_ s: School, hasNotes: (School) -> Bool) -> String {
        let rounds = roundKeys.compactMap { k in s.research.rounds[k]?.dl.map { "\(roundNames[k]!) \($0)" } }
        let reqs = s.requirements.filter { !$0.na }
        let done = reqs.filter(\.done).count
        let bits: [String?] = [
            "- \(s.name)", "\(s.folder)/\(hasNotes(s) ? "" : " (no notes.md yet)")",
            s.applying ? "applying\(s.round.map { ", " + (roundNames[$0] ?? $0) } ?? "")\(s.applied.map { ", applied \($0)" } ?? "")" : "considering",
            s.tier.map { "tier: \($0)\(s.tierLevel.map { " \($0)" } ?? "")" },
            rounds.isEmpty ? nil : "deadlines: " + rounds.joined(separator: ", "),
            s.internalDate.map { "school deadline \($0)" },
            reqs.isEmpty ? nil : "requirements \(done)/\(reqs.count) done",
            s.essays.isEmpty ? nil : "\(s.essays.count) essay\(s.essays.count == 1 ? "" : "s")",
        ]
        return bits.compactMap { $0 }.joined(separator: " | ")
    }

    /// The summary of every school on the list (a system's campuses as one application), cut at `max` characters.
    public static func claudeSummary(_ schools: [School], hasNotes: (School) -> Bool = { _ in true }, max: Int = claudeMax) -> String {
        let sorted = schools.sorted { a, b in a.applying == b.applying ? a.name.localizedCompare(b.name) == .orderedAscending : a.applying }
        var out: [String] = [], done = Set<String>()
        for s in sorted {
            guard let sysId = s.system, let sys = system(sysId) else { out.append(claudeSchoolLine(s, hasNotes: hasNotes)); continue }
            if done.contains(sysId) { continue }
            done.insert(sysId)
            let cs = sorted.filter { $0.system == sysId }
            out.append("- \(sys.name): ONE application covering \(cs.count) campus\(cs.count == 1 ? "" : "es") (their status moves together; each campus has its own folder)")
            out += cs.map { "  " + claudeSchoolLine($0, hasNotes: hasNotes) }
        }
        let ap = appCount(schools.filter(\.applying)), co = appCount(schools.filter { !$0.applying })
        var body = "", i = 0
        while i < out.count { if body.count + out[i].count + 1 > max { break }; body += (body.isEmpty ? "" : "\n") + out[i]; i += 1 }
        if i < out.count { body += "\n(list truncated: \(out.count - i) more line\(out.count - i == 1 ? "" : "s"); Read applications/ for the rest)" }
        return "\(claudeIntro)\nApplications (\(ap) applying, \(co) considering):\n\(out.isEmpty ? "(none yet)" : body)"
    }
}
