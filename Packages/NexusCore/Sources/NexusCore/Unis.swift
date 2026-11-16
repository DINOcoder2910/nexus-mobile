import Foundation

// The universities database for Applications › Research (the laptop's store/unis.js and store/unisquery.js, ported). The dataset is the
// laptop's renderer/data/universities.json, shipped inside the app (reference data, not in the data folder; Nexus never writes it). Here: a
// dataset school as a row (`UniSchool`), the short names, the rankings with their groups (engineering first), linking a school's folder to its
// record (`unitid:`, else its name and aliases), your own values winning over the database's, tiers (and `tiers.yaml` for schools with no
// folder), sorting with empty values last, how good a figure is (its percentile), and the filters and search.

public struct UniRound: Equatable {
    public var rate: Double?
    public var year: Int?
    public var src: String
}

public struct UniSchool: Identifiable, Equatable {
    public var id: Int
    public var name, full, short, folder: String
    public var aliases: [String] = []
    public var city, st, url, admissionsUrl, applyUrl, npcUrl, host: String?
    /// "pub", "pri" or "fp".
    public var ctrl: String?
    public var ug: Int?
    public var size: String?
    public var setting, locale: String?
    public var acc: Double?
    public var sat, act: [Double]?
    public var tin, tout, net, earn: Double?
    public var grad: Double?
    public var offersEng = false
    public var engN: Int?
    /// "large", "medium", "small", "offered" or nil.
    public var eng: String?
    public var engFields: [String] = []
    public var offersCS = false
    public var csN: Int?
    public var ranks: [String: Double] = [:]
    public var rankLabels: [String: String] = [:]
    public var score: Double?
    public var rounds: [String: UniRound] = [:]
    public var lat, lon: Double?
}

public struct RankMeta: Equatable {
    public var k, l, g, long: String
    /// Only the top of the list is published (no rank does not mean unranked).
    public var partial: Bool
    public var entries: Int?
    public var note: String { partial ? entries.map { "top \($0)" } ?? "" : "" }
}

/// The dataset, read once.
public final class UniDB {
    public let list: [UniSchool]
    public let ranks: [RankMeta]
    public let byId: [Int: UniSchool]
    let exact: [String: [Int]]
    let core: [String: [Int]]
    private var dists: [String: [Double]] = [:]
    private let lock = NSLock()

    public init(list: [UniSchool], ranks: [RankMeta]) {
        self.list = list
        self.ranks = ranks
        byId = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var ex: [String: [Int]] = [:], co: [String: [Int]] = [:]
        func push(_ m: inout [String: [Int]], _ k: String, _ id: Int) { if k.isEmpty { return }; if !(m[k] ?? []).contains(id) { m[k, default: []].append(id) } }
        for u in list {
            for n in [u.name, Unis.noCampus(u.name), u.short, u.folder] + u.aliases { push(&ex, Unis.norm(n), u.id) }
            for n in [u.name, u.short, u.folder] { push(&co, Unis.core(n), u.id) }
        }
        exact = ex; core = co
    }

    /// The dataset's JSON (`{meta, sources, schools}`).
    public convenience init(json data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Unis.Failure.notTheDataset }
        let schools = (root["schools"] as? [[String: Any]] ?? []).compactMap(Unis.normalise)
        self.init(list: schools, ranks: Unis.buildRanks(root["sources"] as? [String: Any] ?? [:]))
    }

    public func rank(_ k: String) -> RankMeta? { ranks.first { $0.k == k } }

    /// Every school's figure for `k`, sorted (built once per key).
    public func dist(_ k: String) -> [Double] {
        lock.lock(); defer { lock.unlock() }
        if let d = dists[k] { return d }
        let d = list.compactMap { Unis.statValue($0, k) }.sorted()
        dists[k] = d
        return d
    }
}

/// A row of Research: a dataset school and its folder (either may be missing).
public struct UniRow: Identifiable, Equatable {
    public var key: String
    public var u: UniSchool?
    public var s: School?
    /// A removed folder that Consider puts back.
    public var dropped: School?
    /// The tier of a school with no folder at all (tiers.yaml).
    public var t: LooseTier?
    public var mine: Bool { s != nil }
    public var applying: Bool { s?.applying == true }
    public var name: String { s?.name ?? u?.name ?? "" }
    public var label: String { s?.short ?? u?.short ?? "" }
    public var full: String { u?.full ?? s?.name ?? "" }
    public var id: String { key }
    /// The application system it belongs to (the UC campuses).
    public var system: String? { s?.system ?? Apps.system(ofUnit: u?.id ?? s?.unitid)?.id }
}

public struct LooseTier: Equatable {
    public var tier: String
    public var level: Int?
    public var name: String?
    public init(tier: String, level: Int?, name: String?) { self.tier = tier; self.level = level; self.name = name }
}

public enum Unis {
    public enum Failure: Error { case notTheDataset }

    public static let tiers = ["safety", "target", "reach", "dream"]
    public static let tierNames = ["safety": "Safety", "target": "Target", "reach": "Reach", "dream": "Dream"]
    public static let tierHints = ["safety": "very likely to get in", "target": "a fair chance", "reach": "possible, not likely", "dream": "a long shot you would love"]
    public static let tierEnds = ["safety": ("Low, the surest", "High, near Target"), "target": ("Low, near Safety", "High, near Reach"), "reach": ("Low, near Target", "High, near Dream"), "dream": ("Low, near Reach", "High, the longest shot")]
    public static func tierSortKey(_ tier: String?, _ level: Int?) -> Double? { tier.flatMap { tiers.firstIndex(of: $0) }.map { Double($0 * 10 + (level ?? 3)) } }
    public static func tierText(_ tier: String?, _ level: Int?) -> String {
        guard let t = tier, let n = tierNames[t] else { return "No tier" }
        return n + (level.map { ", \($0) of 5" } ?? "")
    }

    public static let ctrlNames = ["pub": "Public", "pri": "Private", "fp": "For-profit"]
    public static let sizeNames = ["small": "Small", "medium": "Medium", "large": "Large"]
    public static let engNames = ["large": "Large", "medium": "Medium", "small": "Small", "offered": "Offered"]
    public static func sizeOf(_ ug: Int?) -> String? { ug.map { $0 < 5000 ? "small" : $0 <= 15000 ? "medium" : "large" } }
    public static func engSizeOf(_ offers: Bool, _ n: Int?) -> String? {
        guard offers else { return nil }
        guard let n, n > 0 else { return "offered" }
        return n >= 1000 ? "large" : n >= 300 ? "medium" : "small"
    }
    public static let states = ["AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico", "GU": "Guam", "VI": "Virgin Islands"]

    // MARK: short names

    static let shortNames: [Int: String] = [
        166683: "MIT", 110404: "Caltech", 243744: "Stanford", 162928: "Johns Hopkins", 215062: "UPenn", 110662: "UCLA", 110635: "UC Berkeley", 110680: "UC San Diego",
        110644: "UC Davis", 110653: "UC Irvine", 110705: "UC Santa Barbara", 152080: "Notre Dame", 211440: "Carnegie Mellon", 179867: "WashU", 199120: "UNC Chapel Hill",
        123961: "USC", 193900: "NYU", 228778: "UT Austin", 139755: "Georgia Tech", 145637: "UIUC", 240444: "UW–Madison", 204796: "Ohio State", 186380: "Rutgers",
        163286: "Maryland", 201645: "Case Western", 214777: "Penn State", 194824: "RPI", 168421: "WPI", 186867: "Stevens", 441982: "Olin", 152318: "Rose-Hulman",
        110422: "Cal Poly SLO", 236948: "U. of Washington", 134130: "U. of Florida", 234076: "UVA", 170976: "Michigan", 243780: "Purdue", 233921: "Virginia Tech",
        174066: "Minnesota", 228723: "Texas A&M", 190150: "Columbia", 147767: "Northwestern", 198419: "Duke", 190415: "Cornell", 186131: "Princeton", 166027: "Harvard",
        130794: "Yale", 217156: "Brown", 182670: "Dartmouth", 221999: "Vanderbilt", 227757: "Rice", 168148: "Tufts", 115409: "Harvey Mudd", 190372: "Cooper Union",
        164988: "Boston University", 167358: "Northeastern", 126614: "CU Boulder", 104151: "Arizona State", 153603: "Iowa State", 215293: "Pitt", 160755: "Tulane",
        139658: "Emory", 144050: "UChicago", 166629: "UMass Amherst", 126775: "Colorado School of Mines", 212054: "Drexel", 196413: "Syracuse", 217882: "Clemson",
        100858: "Auburn", 221759: "Tennessee", 230764: "Utah", 209542: "Oregon State", 171100: "Michigan State", 151351: "Indiana", 178411: "Missouri S&T",
        133553: "Embry-Riddle", 239318: "MSOE", 195003: "RIT", 195030: "Rochester", 213543: "Lehigh", 211291: "Bucknell", 216597: "Villanova", 122931: "Santa Clara",
        228246: "SMU", 145600: "UIC",
    ]
    static func tidy(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s*--\s*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)-Main Campus$|\s+Main Campus$|\s+Campus$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^The (University )"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: rankings

    public static let rankGroups = [("eng", "Engineering"), ("usnSpec", "US News engineering specialties"), ("subj", "QS and THE by subject"), ("gras", "ShanghaiRanking GRAS (engineering subjects)"), ("gen", "Overall")]
    static let rankL: [(String, String, String)] = [
        ("usnEngDoctorate", "US News Eng", "eng"), ("usnEngNoDoctorate", "US News Eng, no PhD", "eng"), ("qsEngTech", "QS Eng", "eng"), ("theEng", "THE Eng", "eng"),
        ("usnEngAerospace", "US News Aero", "usnSpec"), ("usnEngBioAgricultural", "US News Bio/Ag", "usnSpec"), ("usnEngBiomedical", "US News BME", "usnSpec"), ("usnEngChemical", "US News ChemE", "usnSpec"),
        ("usnEngCivil", "US News Civil", "usnSpec"), ("usnEngComputer", "US News CompE", "usnSpec"), ("usnEngElectrical", "US News EE", "usnSpec"), ("usnEngEnvironmental", "US News Environmental", "usnSpec"),
        ("usnEngIndustrial", "US News Industrial", "usnSpec"), ("usnEngMaterials", "US News Materials", "usnSpec"), ("usnEngMechanical", "US News ME", "usnSpec"), ("usnEngPetroleum", "US News Petroleum", "usnSpec"),
        ("usnEngNoDocAerospace", "US News Aero, no PhD", "usnSpec"), ("usnEngNoDocCivil", "US News Civil, no PhD", "usnSpec"), ("usnEngNoDocComputer", "US News CompE, no PhD", "usnSpec"),
        ("usnEngNoDocElectrical", "US News EE, no PhD", "usnSpec"), ("usnEngNoDocMechanical", "US News ME, no PhD", "usnSpec"),
        ("qsCS", "QS CS", "subj"), ("qsEngMechanical", "QS ME", "subj"), ("qsEngElectrical", "QS EE", "subj"), ("qsEngChemical", "QS ChemE", "subj"), ("qsEngCivil", "QS Civil", "subj"),
        ("qsEngPetroleum", "QS Petroleum", "subj"), ("qsEngMining", "QS Mining", "subj"), ("theCS", "THE CS", "subj"),
        ("qs", "QS World", "gen"), ("usnNational", "US News", "gen"), ("the", "THE World", "gen"), ("forbes", "Forbes", "gen"), ("wsj", "WSJ", "gen"), ("niche", "Niche", "gen"), ("usnRegional", "US News Regional", "gen"),
    ]
    static let grasL = ["Aerospace": "Aero", "AI": "AI", "Automation": "Automation", "Biomedical": "BME", "Biotech": "Biotech", "Chemical": "ChemE", "Civil": "Civil", "CS": "CS", "Electrical": "EE", "Energy": "Energy", "Environmental": "Environmental", "FoodScience": "Food", "Instruments": "Instruments", "MarineOcean": "Marine", "Materials": "Materials", "Mechanical": "ME", "Metallurgical": "Metallurgy", "Mining": "Mining", "Nano": "Nano", "RemoteSensing": "Remote sensing", "Robotics": "Robotics", "Telecom": "Telecom", "Textile": "Textile", "Transportation": "Transport", "WaterResources": "Water"]
    /// "Top N in US News Eng" counts either US News engineering list.
    public static let anyEng = "usnEngAny"

    /// The rankings the dataset carries, in picker order, from its `sources` block.
    public static func buildRanks(_ sources: [String: Any]) -> [RankMeta] {
        var out: [RankMeta] = [], seen = Set<String>()
        func add(_ k: String, _ l: String, _ g: String, _ src: [String: Any]) {
            if seen.contains(k) { return }
            seen.insert(k)
            let ed = src["edition"] as? String ?? ""
            let yr = ed.range(of: #"\b20\d\d\b"#, options: .regularExpression).map { String(ed[$0]) } ?? ""
            let label = (src["label"] as? String ?? l).replacingOccurrences(of: #"(?i)\s*\((world rank|rank within region)[^)]*\)"#, with: "", options: .regularExpression)
            let world = src["world"] as? Bool == true, regional = src["regional"] as? Bool == true
            out.append(RankMeta(k: k, l: l, g: g, long: "\(label)\(yr.isEmpty ? "" : ", " + yr)\(world ? " (world rank)" : "")\(regional ? " (rank within its region)" : "")",
                                partial: src["partial"] as? Bool == true, entries: (src["entries"] as? NSNumber)?.intValue))
        }
        for (k, l, g) in rankL {
            if k == "usnRegional" {
                if var a = sources["usnRegionalUniversities"] as? [String: Any], a["available"] as? Bool != false { a["label"] = "U.S. News Best Regional Universities and Colleges"; add(k, l, g, a) }
                continue
            }
            if let src = sources[k] as? [String: Any], src["available"] as? Bool != false, src["group"] as? String != "classification" { add(k, l, g, src) }
        }
        for k in sources.keys.sorted() {
            guard !seen.contains(k), let src = sources[k] as? [String: Any], src["available"] as? Bool != false, let group = src["group"] as? String,
                  !["classification", "accreditation", "regional"].contains(group), src["entries"] != nil, !(src["entries"] is NSNull) else { continue }
            if k.hasPrefix("gras") { let sub = String(k.dropFirst(4)); add(k, "Shanghai \(grasL[sub] ?? sub)", "gras", src); continue }
            let label = String((src["label"] as? String ?? k).replacingOccurrences(of: #"\s*\(.*$"#, with: "", options: .regularExpression).prefix(28))
            add(k, label, group == "general" ? "gen" : "subj", src)
        }
        let order = ["eng": 0, "usnSpec": 1, "subj": 2, "gras": 3, "gen": 4]
        return out.enumerated().sorted { a, b in
            let x = order[a.element.g] ?? 9, y = order[b.element.g] ?? 9
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: a dataset school

    static func dbl(_ v: Any?) -> Double? { (v as? NSNumber).map(\.doubleValue) }
    static func int(_ v: Any?) -> Int? { (v as? NSNumber).map(\.intValue) }
    static func pct1(_ v: Double?) -> Double? { v.map { ($0 * 1000).rounded() / 10 } }
    static func pct0(_ v: Double?) -> Double? { v.map { ($0 * 100).rounded() } }
    static func hostOf(_ u: String?) -> String? {
        guard let u, let h = URL(string: u)?.host else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    public static func normalise(_ x: [String: Any]) -> UniSchool? {
        guard let id = int(x["id"]), let name = x["name"] as? String else { return nil }
        var ranks: [String: Double] = [:]
        for (k, v) in x["ranks"] as? [String: Any] ?? [:] { if let d = dbl(v) { ranks[k] = d } }
        var labels: [String: String] = [:]
        for (k, v) in x["rankLabels"] as? [String: Any] ?? [:] { if let s = v as? String { labels[k] = s } else if let d = dbl(v) { labels[k] = JSONValue.format(d) } }
        if let r = ranks["usnRegionalUniversities"] ?? ranks["usnRegionalColleges"] {
            ranks["usnRegional"] = r
            if let l = labels["usnRegionalUniversities"] ?? labels["usnRegionalColleges"] { labels["usnRegional"] = l }
        }
        let control = (x["control"] as? String ?? "").lowercased()
        let ctrl: String? = control.contains("for-profit") ? "fp" : control.contains("private") ? "pri" : control.contains("public") ? "pub" : nil
        let short = x["short"] as? String
        let raw = ["id": id, "short": short ?? name] as [String: Any]
        var u = UniSchool(id: id, name: name, full: tidy(name), short: shortName(raw), folder: tidy(short ?? name))
        u.aliases = x["aliases"] as? [String] ?? []
        u.city = x["city"] as? String; u.st = x["state"] as? String
        u.url = x["url"] as? String; u.admissionsUrl = x["admissionsUrl"] as? String; u.applyUrl = x["applyUrl"] as? String; u.npcUrl = x["netPriceCalcUrl"] as? String
        u.host = hostOf(u.admissionsUrl ?? u.url)
        u.ctrl = ctrl
        u.ug = int(x["size"])
        u.size = x["sizeBucket"] as? String ?? sizeOf(u.ug)
        if let st = x["setting"] as? String, let f = st.first { u.setting = f.uppercased() + st.dropFirst() }
        u.locale = x["locale"] as? String
        u.acc = pct1(dbl(x["admitRate"]))
        u.sat = (x["sat"] as? [Any])?.compactMap(dbl); if u.sat?.isEmpty == true { u.sat = nil }
        u.act = (x["act"] as? [Any])?.compactMap(dbl); if u.act?.isEmpty == true { u.act = nil }
        u.tin = dbl(x["tuitionIn"]); u.tout = dbl(x["tuitionOut"]); u.net = dbl(x["netPrice"])
        u.grad = pct0(dbl(x["gradRate"])); u.earn = dbl(x["medianEarnings"])
        u.offersEng = x["engBachelors"] as? Bool == true
        u.engN = u.offersEng ? int(x["engDegrees"]) : nil
        u.eng = engSizeOf(u.offersEng, int(x["engDegrees"]))
        u.engFields = x["engFields"] as? [String] ?? []
        u.offersCS = x["csBachelors"] as? Bool == true
        u.csN = int(x["csDegrees"])
        u.ranks = ranks; u.rankLabels = labels
        u.score = dbl(x["score"])
        for (k, v) in x["rounds"] as? [String: Any] ?? [:] {
            guard let o = v as? [String: Any] else { continue }
            u.rounds[k] = UniRound(rate: dbl(o["rate"]), year: int(o["year"]), src: o["src"] as? String ?? "")
        }
        u.lat = dbl(x["lat"]); u.lon = dbl(x["lon"])
        return u
    }

    static func shortName(_ x: [String: Any]) -> String {
        if let id = x["id"] as? Int, let s = shortNames[id] { return s }
        let s = tidy(x["short"] as? String ?? "")
        if s.hasPrefix("University of California-") { return "UC " + s.dropFirst("University of California-".count) }
        return s
    }

    // MARK: linking a folder to its record

    static func norm(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var t = folded.replacingOccurrences(of: "&", with: " and ").replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("the ") { t = String(t.dropFirst(4)) }
        return t.trimmingCharacters(in: .whitespaces)
    }
    /// "Northwestern University" and "Northwestern" are one name ("University of Washington" and "Washington University" are not).
    static func core(_ s: String) -> String { norm(s).replacingOccurrences(of: #" (university|college)$"#, with: "", options: .regularExpression) }
    /// "University of Michigan-Ann Arbor" -> "University of Michigan" (not "Rose-Hulman Institute").
    static func noCampus(_ s: String) -> String {
        guard let r = s.range(of: #"-[A-Z][^-]*$"#, options: .regularExpression) else { return s }
        let tail = String(s[r])
        if tail.range(of: #"\b(University|Institute)\b"#, options: .regularExpression) != nil { return s }
        return String(s[..<r.lowerBound])
    }
    static let stop: Set<String> = ["university", "college", "institute", "of", "the", "at", "in", "main", "campus", "and", "school"]

    /// One candidate list to one answer: a single school, or the best-scored one when it stands far ahead.
    static func pick(_ c: [UniSchool]) -> UniSchool? {
        if c.isEmpty { return nil }
        if c.count == 1 { return c[0] }
        let s = c.sorted { ($0.score ?? 9) < ($1.score ?? 9) }
        return (s[0].score ?? 9) * 3 < (s[1].score ?? 9) ? s[0] : nil
    }

    public struct Link { public var u: UniSchool?; public var how: String; public var cands: [UniSchool] }

    /// A school's record: by `unitid`, else by its exact name (or short name, or alias), else by its core name; else the names it could be.
    public static func link(_ s: School, _ db: UniDB?) -> Link {
        guard let db else { return Link(u: nil, how: "", cands: []) }
        if let id = s.unitid, let u = db.byId[id] { return Link(u: u, how: "id", cands: []) }
        var names: [String] = []
        for n in [s.name, s.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression), s.short] where !n.isEmpty && !names.contains(n) { names.append(n) }
        var ex: [UniSchool] = []
        for n in names { for id in db.exact[norm(n)] ?? [] { if let u = db.byId[id], !ex.contains(where: { $0.id == id }) { ex.append(u) } } }
        if let e = pick(ex) { return Link(u: e, how: "name", cands: []) }
        var co: [UniSchool] = []
        for n in names { for id in db.core[core(n)] ?? [] { if let u = db.byId[id], !co.contains(where: { $0.id == id }) { co.append(u) } } }
        if let c = pick(co), ex.isEmpty { return Link(u: c, how: "core", cands: []) }
        var cands = ex.isEmpty ? co : ex
        if cands.isEmpty {
            let words = norm(names.count > 1 ? names[1] : names[0]).split(separator: " ").map(String.init).filter { $0.count > 1 && !stop.contains($0) }
            if !words.isEmpty { cands = db.list.filter { u in let h = norm(u.name + " " + u.short); return words.allSatisfy { h.contains($0) } } }
        }
        return Link(u: nil, how: "", cands: Array(cands.sorted { ($0.score ?? 9) < ($1.score ?? 9) }.prefix(6)))
    }

    // MARK: your values win

    /// The dataset fields a school's own `research:` can override: column -> research key.
    public static let own = ["acc": "acc", "qs": "qs", "usnNational": "usn", "usnEngDoctorate": "usne"]
    public static func ownOf(_ row: UniRow, _ k: String) -> (v: Double, src: String?)? {
        guard let f = own[k], let s = row.s else { return nil }
        let v: Double? = f == "acc" ? s.research.acc : f == "qs" ? s.research.qs : f == "usn" ? s.research.usn : s.research.usne
        guard let v else { return nil }
        return (v, s.research.sources.first { $0.0 == f }?.1)
    }
    public static func accOf(_ row: UniRow) -> Double? { ownOf(row, "acc")?.v ?? row.u?.acc }
    public static func rankOf(_ row: UniRow, _ k: String) -> Double? {
        if k == anyEng {
            let a = rankOf(row, "usnEngDoctorate"), b = rankOf(row, "usnEngNoDoctorate")
            if let a, let b { return min(a, b) }
            return a ?? b
        }
        if let o = ownOf(row, k) { return o.v }
        return row.u?.ranks[k]
    }
    /// "#12", a band "801–850".
    public static func rankText(_ row: UniRow, _ k: String) -> String? {
        guard let v = rankOf(row, k) else { return nil }
        if ownOf(row, k) != nil { return "#" + JSONValue.format(v) }
        if let l = row.u?.rankLabels[k], l.range(of: #"^\d+\s*[-–]\s*\d+$"#, options: .regularExpression) != nil {
            return l.replacingOccurrences(of: #"\s*[-–]\s*"#, with: "–", options: .regularExpression)
        }
        return "#" + JSONValue.format(v)
    }
    public static func isTie(_ row: UniRow, _ k: String) -> Bool { ownOf(row, k) == nil && (row.u?.rankLabels[k]?.hasPrefix("=") ?? false) }

    /// A row's tier: its folder's (a removed folder's too), else the folder-less one from tiers.yaml.
    public static func tierOf(_ row: UniRow) -> String? { row.s?.tier ?? row.dropped?.tier ?? row.t?.tier }
    public static func levelOf(_ row: UniRow) -> Int? {
        if let s = row.s ?? row.dropped { return s.tier != nil ? s.tierLevel : nil }
        return row.t?.level
    }
    public static func tierKey(_ row: UniRow) -> Double? { tierSortKey(tierOf(row), levelOf(row)) }

    // MARK: tiers.yaml (the tiers of database schools that have no folder)

    public static let tiersFile = "tiers.yaml"
    static let tiersHead = "# Tiers of schools in the universities database that have no folder here (Applications > Research > All).\n# One line per school, by its database id (UNITID). When a school joins Considering, its tier moves into its own workstream.yaml.\n"

    /// The file's entries by id; nil when it does not parse (it is then never written over).
    public static func parseTiers(_ text: String?) -> [Int: LooseTier]? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let d = try? YamlValue.document(text), let o = d.object else { return nil }
        var map: [Int: LooseTier] = [:]
        for (k, v) in o {
            guard let id = Int(k), id > 0 else { continue }
            let t = (v.object != nil ? v["tier"]?.text1 : v.text1)?.lowercased() ?? ""
            guard tiers.contains(t) else { continue }
            let lv = v["tier_level"]?.num
            map[id] = LooseTier(tier: t, level: lv.flatMap { $0 >= 1 && $0 <= 5 ? Int($0.rounded()) : nil }, name: v["name"]?.text1)
        }
        return map
    }
    public static func tiersText(_ map: [Int: LooseTier]) -> String {
        tiersHead + map.keys.sorted().map { id in
            let e = map[id]!
            return "\(id): {tier: \(e.tier)\(e.level.map { ", tier_level: \($0)" } ?? "")\(e.name.map { ", name: " + JSONValue.string($0).text } ?? "")}\n"
        }.joined()
    }

    // MARK: sorting (empty values always last)

    public enum Key: Comparable {
        case n(Double), s(String)
        public static func < (a: Key, b: Key) -> Bool {
            switch (a, b) {
            case let (.n(x), .n(y)): return x < y
            case let (.s(x), .s(y)): return x.localizedCaseInsensitiveCompare(y) == .orderedAscending
            case (.n, .s): return true
            case (.s, .n): return false
            }
        }
    }
    public static func sortRows(_ rows: [UniRow], dir: Int = 1, key: (UniRow) -> Key?) -> [UniRow] {
        rows.map { ($0, key($0)) }.sorted { a, b in
            switch (a.1, b.1) {
            case (nil, nil): return a.0.label.localizedCaseInsensitiveCompare(b.0.label) == .orderedAscending
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?):
                if x == y { return a.0.label.localizedCaseInsensitiveCompare(b.0.label) == .orderedAscending }
                return dir > 0 ? x < y : y < x
            }
        }.map(\.0)
    }

    // MARK: how good a figure is

    /// 1: higher is better; -1: lower is better (a lower admit rate, cost or rank: selective is good, the user's rule).
    public static let statDir: [String: Int] = ["acc": -1, "sat": 1, "act": 1, "net": -1, "tin": -1, "tout": -1, "grad": 1, "earn": 1]
    public static func statDirection(_ k: String) -> Int { statDir[k] ?? -1 }
    static func mid(_ a: [Double]?) -> Double? { guard let a, let f = a.first else { return nil }; return a.count > 1 ? (f + a[1]) / 2 : f }
    public static func statValue(_ u: UniSchool?, _ k: String) -> Double? {
        guard let u else { return nil }
        switch k {
        case "sat": return mid(u.sat)
        case "act": return mid(u.act)
        case "acc": return u.acc
        case "net": return u.net
        case "tin": return u.tin
        case "tout": return u.tout
        case "grad": return u.grad
        case "earn": return u.earn
        default: return u.ranks[k]
        }
    }

    public struct Standing: Equatable {
        /// 0…1, 1 the best.
        public var g: Double
        /// -3…3, the shade (0 none).
        public var lv: Int
        public var top: Bool
        public var pct: Int
        public var n: Int
        public var text = ""
    }
    static func firstAtLeast(_ a: [Double], _ v: Double) -> Int { var lo = 0, hi = a.count; while lo < hi { let m = (lo + hi) / 2; if a[m] < v { lo = m + 1 } else { hi = m } }; return lo }
    static func firstAbove(_ a: [Double], _ v: Double) -> Int { var lo = 0, hi = a.count; while lo < hi { let m = (lo + hi) / 2; if a[m] <= v { lo = m + 1 } else { hi = m } }; return lo }
    /// Where `v` stands among `dist` (sorted), or nil with fewer than 5 to compare with. `partial`: being on a partial list is never bad.
    public static func standing(_ dist: [Double], _ v: Double?, dir: Int, partial: Bool = false) -> Standing? {
        guard let v, v.isFinite, dist.count >= 5 else { return nil }
        let n = dist.count, lo = firstAtLeast(dist, v), hi = firstAbove(dist, v), eq = hi - lo
        let worse = dir > 0 ? lo : n - hi, better = dir > 0 ? n - hi : lo
        let raw = (Double(worse) + Double(eq) / 2) / Double(n)
        let g = partial ? 0.5 + raw / 2 : raw
        let top = raw >= 0.5
        let pct = max(1, min(100, Int((Double((top ? better : worse) + max(1, eq)) / Double(n) * 100).rounded(.up))))
        return Standing(g: g, lv: shadeLevel(g), top: top, pct: pct, n: n)
    }
    /// Only the ends are shaded: the best fifth green (strongest in the best 5%), the worst fifth red, the middle none.
    public static func shadeLevel(_ g: Double) -> Int { g >= 0.95 ? 3 : g >= 0.88 ? 2 : g >= 0.8 ? 1 : g > 0.2 ? 0 : g > 0.12 ? -1 : g > 0.05 ? -2 : -3 }
    public static func standingText(_ st: Standing, of: String? = nil) -> String {
        "\(st.top ? "Top" : "Bottom") \(st.pct)% of \(of ?? "\(st.n.formatted()) schools")"
    }

    // MARK: filters and search

    public struct Filters: Equatable, Codable {
        public var type: [String] = []
        public var size: [String] = []
        public var states: [String] = []
        public var accMin = "", accMax = ""
        public var tier: [String] = []
        public var eng = false, cs = false
        public var rankTop = ""
        public var rankSrc = Unis.anyEng
        public var offers: [String] = []
        public init() {}
        public var isEmpty: Bool { Unis.activeFilters(self).isEmpty }
    }
    static func numOr(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces)) }
    /// A state typed as "CA", "ca" or "California" -> its code.
    public static func stateCode(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if states[t.uppercased()] != nil { return t.uppercased() }
        return states.first { $0.value.lowercased() == t.lowercased() }?.key
    }
    public static func passes(_ row: UniRow, _ f: Filters) -> Bool {
        let u = row.u
        if !f.type.isEmpty && !(u?.ctrl.map { f.type.contains($0) } ?? false) { return false }
        if !f.size.isEmpty && !(u?.size.map { f.size.contains($0) } ?? false) { return false }
        if !f.states.isEmpty && !(u?.st.map { f.states.contains($0) } ?? false) { return false }
        let lo = numOr(f.accMin), hi = numOr(f.accMax)
        if lo != nil || hi != nil {
            guard let a = accOf(row) else { return false }
            if let lo, a < lo { return false }
            if let hi, a > hi { return false }
        }
        if !f.tier.isEmpty && !f.tier.contains(tierOf(row) ?? "none") { return false }
        if f.eng && u?.offersEng != true { return false }
        if f.cs && u?.offersCS != true { return false }
        if !f.offers.isEmpty { guard let s = row.s, f.offers.allSatisfy({ s.research.rounds[$0] != nil }) else { return false } }
        if let top = numOr(f.rankTop) { guard let r = rankOf(row, f.rankSrc), r <= top else { return false } }
        return true
    }
    /// Every word must appear in the name, a short name, an alias or the city.
    public static func hay(_ row: UniRow) -> String {
        var bits = [row.name, row.label, row.full]
        if let u = row.u { bits += [u.short, u.folder] + u.aliases + [u.city ?? ""] }
        if let s = row.s { bits += [s.short, s.research.loc] }
        return bits.joined(separator: " ").lowercased()
    }
    public static func matches(_ row: UniRow, _ q: String) -> Bool {
        let words = q.lowercased().split(whereSeparator: \.isWhitespace)
        if words.isEmpty { return true }
        let h = hay(row)
        return words.allSatisfy { h.contains($0) }
    }
    /// The active filters as chips, in the panel's order.
    public static func activeFilters(_ f: Filters, rankLabel: (String) -> String = { $0 }) -> [(key: String, label: String)] {
        var out: [(key: String, label: String)] = []
        if !f.type.isEmpty { out.append(("type", f.type.map { ctrlNames[$0] ?? $0 }.joined(separator: ", "))) }
        if !f.size.isEmpty { out.append(("size", "Size: " + f.size.map { sizeNames[$0] ?? $0 }.joined(separator: ", "))) }
        if !f.states.isEmpty { out.append(("states", "State: " + f.states.joined(separator: ", "))) }
        let lo = numOr(f.accMin), hi = numOr(f.accMax)
        if lo != nil || hi != nil {
            let a = lo.map { JSONValue.format($0) }, b = hi.map { JSONValue.format($0) }
            out.append(("acc", a != nil && b != nil ? "Admit \(a!)–\(b!)%" : a != nil ? "Admit \(a!)% or more" : "Admit \(b!)% or less"))
        }
        if !f.tier.isEmpty { out.append(("tier", "Tier: " + f.tier.map { tierNames[$0] ?? "no tier" }.joined(separator: ", "))) }
        if f.eng { out.append(("eng", "Engineering offered")) }
        if f.cs { out.append(("cs", "CS offered")) }
        if !f.offers.isEmpty { out.append(("offers", "Offers " + f.offers.map { Apps.roundNames[$0] ?? $0 }.joined(separator: ", "))) }
        if let top = numOr(f.rankTop) { out.append(("rank", "Ranked within \(JSONValue.format(top)) in \(rankLabel(f.rankSrc))")) }
        return out
    }
    public static func clearFilter(_ f: inout Filters, _ key: String) {
        switch key {
        case "type": f.type = []
        case "size": f.size = []
        case "states": f.states = []
        case "acc": f.accMin = ""; f.accMax = ""
        case "tier": f.tier = []
        case "eng": f.eng = false
        case "cs": f.cs = false
        case "offers": f.offers = []
        case "rank": f.rankTop = ""
        default: break
        }
    }
}
