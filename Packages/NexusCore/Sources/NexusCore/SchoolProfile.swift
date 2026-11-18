import Foundation

// Applications' "Research with Claude" (the laptop's schoolprofile.js): one Claude call with web search returns JSON (a brief, each round's admit
// rate with its year and page, the city, opportunities, things to do, Greek life, a few more facts and the concerns). A figure is kept only with
// a page address. It is saved in one write with Undo: `research.profile` and, for the rounds, `research.rounds.<k>.rate` with `rate_of`, `rate_src`
// and `rate_how` (a rate typed by hand, one with no `rate_src`, is never replaced).

public struct SchoolProfile: Equatable {
    public struct ProfileRound: Equatable {
        public var offered: Bool
        public var rate: Double?
        public var of = "", how = "", note = "", src = ""
    }
    public struct City: Equatable {
        public var name = "", about = "", metro = "", population = "", weather = "", cost = ""
        public var isEmpty: Bool { [name, about, metro, population, weather, cost].allSatisfy(\.isEmpty) }
    }
    public struct Greek: Equatable {
        public var men, women, all: Double?
        public var of = "", src = ""
    }
    public struct Line: Equatable {
        public var l: String, v: String
        public var src = ""
    }

    public var checked: String?
    public var brief = ""
    public var rounds: [String: ProfileRound] = [:]
    public var city = City()
    public var opportunities: [String] = []
    public var todo: [String] = []
    public var greek: Greek?
    public var extras: [Line] = []
    public var concerns: [Line] = []
    public var v = 1
    public var sources: [String] = []

    public static let version = 2
    static let listMax = 8

    public static let system = "You research US universities on the web for a high-school senior who is applying for engineering. You search, read the pages you find, and answer with one JSON object. You never invent a figure: when no page gives it, it is null. Every figure carries the address of the page it came from. You use the Common Data Set, the school's own class profile and admissions pages, and reliable news reports."

    /// The prompt for one school; `u` its database record (city and state, website), or nil.
    public static func prompt(name: String, u: UniSchool?, today: String) -> String {
        let where_ = u.flatMap { x -> String? in guard let c = x.city, !c.isEmpty else { return nil }; return "\(c), \(x.st ?? "")" } ?? "its city"
        return [
            "Research \(name) (Nexus school research) for a student applying for engineering. Today is \(today).",
            u.flatMap { x -> String? in guard let h = x.host, !h.isEmpty else { return nil }; return "Its website is \(h)." } ?? "",
            "",
            "Find:",
            "1. The admit rate of each application round for first-year applicants, from the most recent cycle with published numbers: Early Decision (ed), Early Decision II (ed2), Early Action, including restrictive or single-choice early action (ea), and Regular Decision (rd). A round's rate is admitted / applied in that round. If a school reports ED I and ED II together, give the combined rate as ed and say so in \"note\". If no page gives the RD rate but one gives the overall and early numbers (the Common Data Set does: C1 and C21/C22), you may work it out as (all admitted - early admitted) / (all applicants - early applicants): set \"how\" to \"derived\" and say what you used in \"note\". Mark rounds the school does not offer with \"offered\": false.",
            "2. \(where_): what it is like to live there, how far the nearest big city is, the weather, the cost of living.",
            "3. Opportunities for an engineering student: internships and co-ops, the industries and employers nearby, research for undergraduates, anything the school is known for.",
            "4. Things to do in the city and around it.",
            "5. Greek life: the percent of undergraduate men in fraternities and women in sororities (Common Data Set F1), or the overall percent.",
            "6. A few more facts worth knowing when choosing (for example: how you enter engineering, a housing guarantee, the first-year program, notable engineering majors, a co-op, campus safety, the size of classes). Short.",
            "7. Issues and possible concerns, honestly, the downsides a student should weigh: for example weed-out courses or a competitive or capped entry into engineering majors, no guaranteed transfer into engineering, a housing shortage, crime near campus, a high cost or thin financial aid, grade deflation or a stressful culture, an isolated location, recent budget cuts, strikes, closures or controversies, a heavy party or Greek scene. Only real ones that pages support, each with a short detail and its page when you have one.",
            "",
            "Answer with only this JSON object (no other text):",
            "```json",
            "{\"brief\": \"4 to 6 sentences: what the school is like for an engineering student, its strengths, its feel\",",
            " \"rounds\": {\"ed\": {\"offered\": true, \"rate\": 21.5, \"of\": \"Class of 2029\", \"how\": \"reported\", \"note\": \"\", \"src\": \"https://...\"}, \"ed2\": {\"offered\": false}, \"ea\": {\"offered\": false}, \"rd\": {\"offered\": true, \"rate\": 5.2, \"of\": \"Class of 2029\", \"how\": \"derived\", \"note\": \"from CDS C1 minus C21\", \"src\": \"https://...\"}},",
            " \"city\": {\"name\": \"Evanston, IL\", \"about\": \"1 or 2 sentences\", \"metro\": \"Chicago, 25 minutes by train\", \"population\": \"75,000\", \"weather\": \"cold, snowy winters; warm summers\", \"cost\": \"high\"},",
            " \"opportunities\": [\"short line\", \"...\"],",
            " \"todo\": [\"short line\", \"...\"],",
            " \"greek\": {\"men\": 30, \"women\": 35, \"all\": null, \"of\": \"2024-25\", \"src\": \"https://...\"},",
            " \"extras\": [{\"label\": \"Entering engineering\", \"value\": \"direct admission to the engineering school\"}],",
            " \"concerns\": [{\"issue\": \"Capped CS major\", \"detail\": \"1 or 2 sentences\", \"src\": \"https://...\"}],",
            " \"sources\": [\"https://...\"]}",
            "```",
            "Rates and percents are numbers (21.5, not \"21.5%\"). Use null for what you cannot find. Keep each list to 3 to 6 short lines.",
        ].joined(separator: "\n")
    }

    // MARK: reading a reply or a saved profile

    static func str(_ v: JSONValue?, _ max: Int = 600) -> String {
        guard let t = v?.text1 else { return "" }
        let s = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return String(s.prefix(max))
    }
    static func isUrl(_ v: JSONValue?) -> Bool {
        guard let s = v?.string?.trimmingCharacters(in: .whitespaces) else { return false }
        return s.range(of: #"^https?://\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func pct(_ v: JSONValue?) -> Double? {
        var n: Double?
        if case .string(let s)? = v { n = Double(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) } else { n = v?.number }
        guard let n, n.isFinite, n >= 0, n <= 100 else { return nil }
        return (n * 10).rounded() / 10
    }
    static func lines(_ v: JSONValue?) -> [String] {
        (v?.array ?? []).map { x -> String in
            if x.object != nil { return str(x["text"] ?? x["t"], 240) }
            return str(x, 240)
        }.filter { !$0.isEmpty }.prefix(listMax).map { $0 }
    }

    /// A reply's JSON or a saved `research.profile` in one shape, or nil when there is nothing in it.
    public init?(_ j: JSONValue?) {
        guard let j, j.object != nil else { return nil }
        for k in Apps.roundKeys {
            guard let r = j["rounds"]?[k], r.object != nil else { continue }
            let src = SchoolProfile.isUrl(r["src"]) ? SchoolProfile.str(r["src"], 400) : ""
            let rate = src.isEmpty ? nil : SchoolProfile.pct(r["rate"])
            let offered: Bool? = r["offered"] == .bool(false) ? false : (r["offered"] == .bool(true) || rate != nil) ? true : nil
            guard let offered else { continue }
            let has = rate != nil
            rounds[k] = ProfileRound(offered: offered, rate: offered ? rate : nil, of: has ? SchoolProfile.str(r["of"], 60) : "",
                                     how: has ? (r["how"]?.string == "derived" ? "derived" : "reported") : "", note: has ? SchoolProfile.str(r["note"], 200) : "", src: has ? src : "")
        }
        let c = j["city"]
        city = City(name: SchoolProfile.str(c?["name"], 80), about: SchoolProfile.str(c?["about"], 400), metro: SchoolProfile.str(c?["metro"], 160),
                    population: SchoolProfile.str(c?["population"], 40), weather: SchoolProfile.str(c?["weather"], 200), cost: SchoolProfile.str(c?["cost"], 80))
        if let g = j["greek"], SchoolProfile.isUrl(g["src"]) {
            let gr = Greek(men: SchoolProfile.pct(g["men"]), women: SchoolProfile.pct(g["women"]), all: SchoolProfile.pct(g["all"]), of: SchoolProfile.str(g["of"], 40), src: SchoolProfile.str(g["src"], 400))
            greek = SchoolProfile.greekOf(gr) != nil ? gr : nil
        }
        extras = (j["extras"]?.array ?? []).compactMap { x -> Line? in
            guard x.object != nil else { return nil }
            let l = SchoolProfile.str(x["l"] ?? x["label"], 60), v = SchoolProfile.str(x["v"] ?? x["value"], 240)
            return l.isEmpty || v.isEmpty ? nil : Line(l: l, v: v)
        }.prefix(SchoolProfile.listMax).map { $0 }
        concerns = (j["concerns"]?.array ?? []).compactMap { x -> Line? in
            if case .string = x { let l = SchoolProfile.str(x, 120); return l.isEmpty ? nil : Line(l: l, v: "") }
            guard x.object != nil else { return nil }
            let l = SchoolProfile.str(x["l"] ?? x["issue"] ?? x["label"], 120)
            guard !l.isEmpty else { return nil }
            return Line(l: l, v: SchoolProfile.str(x["v"] ?? x["detail"] ?? x["value"], 300), src: SchoolProfile.isUrl(x["src"]) ? SchoolProfile.str(x["src"], 400) : "")
        }.prefix(SchoolProfile.listMax).map { $0 }
        var seen = Set<String>()
        sources = (j["sources"]?.array ?? []).filter { SchoolProfile.isUrl($0) }.map { SchoolProfile.str($0, 400) }.filter { seen.insert($0).inserted }.prefix(12).map { $0 }
        checked = j["checked"]?.iso
        brief = SchoolProfile.str(j["brief"], 1500)
        opportunities = SchoolProfile.lines(j["opportunities"])
        todo = SchoolProfile.lines(j["todo"])
        v = Int(j["v"]?.num ?? 1)
        if v == 0 { v = 1 }
        let any = !brief.isEmpty || !rounds.isEmpty || !city.isEmpty || !opportunities.isEmpty || !todo.isEmpty || greek != nil || !extras.isEmpty || !concerns.isEmpty
        if !any { return nil }
    }

    /// The profile in a Claude reply (a fenced or bare JSON object), or nil.
    public static func parse(_ reply: String) -> SchoolProfile? { SchoolProfile(SiteFacts.jsonObject(reply)) }

    // MARK: Greek life

    /// The share in Greek life: the overall percent, else the mean of men's and women's, else whichever is known.
    public static func greekOf(_ g: Greek?) -> Double? {
        guard let g else { return nil }
        if let a = g.all { return a }
        if let m = g.men, let w = g.women { return ((m + w) / 2 * 10).rounded() / 10 }
        return g.men ?? g.women
    }
    /// More Greek life is not good (the user's rule): -3...3 as the other figures' shades.
    public static func greekLevel(_ p: Double?) -> Int {
        guard let p else { return 0 }
        return p <= 5 ? 2 : p < 10 ? 1 : p < 20 ? 0 : p < 27 ? -1 : p < 35 ? -2 : -3
    }

    /// The fall a rate's class entered: "Class of 2029" entered in 2025; "Fall 2025", "2025-26" and "2025" are that fall.
    public static func entryYear(_ of: String?) -> Int? {
        let t = of ?? ""
        if let r = t.range(of: #"(?i)\bclass\s+of\s+20\d\d\b"#, options: .regularExpression), let y = Int(t[r].suffix(4)) { return y - 4 }
        if let r = t.range(of: #"\b20\d\d\b"#, options: .regularExpression) { return Int(t[r]) }
        return nil
    }

    // MARK: saving

    /// As written in `research.profile` (empty values left out, so the file stays short).
    public func written(roundsOverride: [String: ProfileRound]? = nil) -> JSONValue {
        func s(_ k: String, _ v: String) -> (String, JSONValue)? { v.isEmpty ? nil : (k, .string(v)) }
        func n(_ k: String, _ v: Double?) -> (String, JSONValue)? { v.map { (k, .number($0)) } }
        var o: [(String, JSONValue)] = []
        if let checked { o.append(("checked", .string(checked))) }
        if let x = s("brief", brief) { o.append(x) }
        let c: [(String, JSONValue)] = [s("name", city.name), s("about", city.about), s("metro", city.metro), s("population", city.population), s("weather", city.weather), s("cost", city.cost)].compactMap { $0 }
        if !c.isEmpty { o.append(("city", .object(c))) }
        if !opportunities.isEmpty { o.append(("opportunities", .array(opportunities.map { .string($0) }))) }
        if !todo.isEmpty { o.append(("todo", .array(todo.map { .string($0) }))) }
        if let g = greek {
            o.append(("greek", .object([n("men", g.men), n("women", g.women), n("all", g.all), s("of", g.of), s("src", g.src)].compactMap { $0 })))
        }
        if !extras.isEmpty { o.append(("extras", .array(extras.map { .object([("l", .string($0.l)), ("v", .string($0.v))]) }))) }
        if !concerns.isEmpty {
            o.append(("concerns", .array(concerns.map { .object([("l", JSONValue.string($0.l)), s("v", $0.v), s("src", $0.src)].compactMap { $0 }) })))
        }
        o.append(("v", .number(Double(v))))
        if !sources.isEmpty { o.append(("sources", .array(sources.map { .string($0) }))) }
        let rs = roundsOverride ?? rounds
        if !rs.isEmpty {
            o.append(("rounds", .object(Apps.roundKeys.compactMap { k -> (String, JSONValue)? in
                guard let r = rs[k] else { return nil }
                return (k, .object([("offered", JSONValue.bool(r.offered)), n("rate", r.rate), s("of", r.of), s("how", r.how), s("note", r.note), s("src", r.src)].compactMap { $0 }))
            })))
        }
        return .object(o)
    }

    public struct Applied {
        public var research: JSONValue
        public var filled: [String] = [], kept: [String] = [], newer: [String] = []
    }

    /// The research to write: `raw` is the school's `research` as in the file. The profile replaces the old one; a round's rate is set where the
    /// profile has one and the file has none, or one from an earlier research (`rate_src`); a rate typed by hand is kept. An earlier research's rate
    /// for a newer entry year than the new one is kept (and the profile shows it too).
    public func apply(to raw: JSONValue, today: String) -> Applied {
        var research: JSONValue = raw.object != nil ? raw : .object([])
        var out = Applied(research: research)
        var rs = rounds
        var fileRounds: JSONValue = research["rounds"]?.object != nil ? research["rounds"]! : .object([])
        for k in Apps.roundKeys {
            guard let r = rs[k], r.offered, let rate = r.rate else { continue }
            let cur = fileRounds[k]?.object != nil ? fileRounds[k] : nil
            if let cur, let was = cur["rate"]?.num, (cur["rate_src"]?.text1 ?? "").isEmpty {
                if abs(was - rate) > 1e-9 { out.kept.append(k) }
                continue
            }
            if let cur, let wasRate = cur["rate"]?.num {
                if let was = SchoolProfile.entryYear(cur["rate_of"]?.text1), let now = SchoolProfile.entryYear(r.of), was > now {
                    rs[k] = ProfileRound(offered: true, rate: wasRate, of: cur["rate_of"]?.text1 ?? "", how: cur["rate_how"]?.string == "derived" ? "derived" : "reported",
                                         note: cur["rate_note"]?.text1 ?? "", src: cur["rate_src"]?.text1 ?? "")
                    out.newer.append(k)
                    continue
                }
            }
            var next: JSONValue = cur ?? .object([])
            next = next.setting("rate", .number(rate)).setting("rate_of", r.of.isEmpty ? nil : .string(r.of)).setting("rate_how", r.how == "derived" ? .string("derived") : nil)
                .setting("rate_note", r.note.isEmpty ? nil : .string(r.note)).setting("rate_src", r.src.isEmpty ? nil : .string(r.src))
            fileRounds = fileRounds.setting(k, next)
            out.filled.append(k)
        }
        if !out.filled.isEmpty { research = research.setting("rounds", fileRounds) }
        var p = self
        p.checked = today
        p.v = SchoolProfile.version
        research = research.setting("profile", p.written(roundsOverride: rs))
        out.research = research
        return out
    }
}
