import Foundation
import Yams

/// Study › Practice sheets, the laptop's renderer/src/studysheets.js: the pure model over a workstream's sheets folder (study/study.yaml
/// `sheets:`, else the workstream's `files/`). It takes the folder's file paths and gives sheets, filters and the names the upload
/// proposes. Nothing is renamed (nexus docs/data-format.md "Study").
///
/// A sheet is a folder named in the convention "Title — details · N copies [2025]" (details: kind, level, marks, pages, minutes, "no MS",
/// "· MS only"), holding the paper and its markscheme as files; any other file is a loose sheet, paired with its markscheme by name
/// ("Test.pdf" + "Test MS.pdf"). The folder above a sheet is its unit folder ("05 Reactivity 1 — Energetics" → R1). Each sheet gets the
/// syllabus codes it is about: from its unit folder, from codes in its names and from topic words in its title.
public enum StudySheets {
    public static let kinds = ["Test", "MCQ", "Paper 2", "Question bank", "Worksheet", "Worked examples", "Data-based", "Mock exam", "Other"]
    public static let eras: [(id: String, label: String)] = [("2025", "From 2025 syllabus"), ("pre-2025", "Before 2025 syllabus")]
    public static let sorts: [(id: String, label: String)] = [("unit", "Unit folder"), ("title", "Title"), ("marks", "Marks"), ("pages", "Pages")]

    public struct Group: Equatable, Sendable, Hashable {
        /// From the data folder ("classes/chem/files/Sheets/05 Reactivity 1 — Energetics").
        public var path: String
        public var label: String
        public var code: String?
    }

    public struct File: Equatable, Sendable, Identifiable {
        public var path: String
        public var name: String
        /// paper | ms | marked
        public var role: String
        public var id: String { path }
    }

    public struct Facts: Equatable, Sendable {
        public var title = ""
        public var details: [String] = []
        public var era: String?
        public var copies = 1
        /// with | none | only (nil: not said by the name)
        public var ms: String?
        /// The name is in the convention (" — " or an [era]).
        public var meta = false
        public var marks: Int?
        public var pages: Int?
        public var minutes: Int?
        public var questions: Int?
        public var level: String?
        public var kind = "Other"
    }

    public struct Sheet: Equatable, Sendable, Identifiable {
        public var id: String
        /// The sheet folder, or (a loose sheet) its paper.
        public var path: String
        public var dir: Bool
        public var group: Group?
        public var title: String
        public var details: [String]
        public var era: String?
        public var copies: Int
        /// with | none | only
        public var ms: String
        public var meta: Bool
        public var marks: Int?
        public var pages: Int?
        public var minutes: Int?
        public var questions: Int?
        public var level: String?
        public var kind: String
        public var files: [File]
        public var codes: [String] = []
        /// How each code was found: folder | name | title | upload.
        public var codeFrom: [String: String] = [:]
        public var search = ""
        /// What the upload kept about it (study/sheets.yaml), as one text.
        public var notes = ""
    }

    public struct Model: Equatable, Sendable {
        public var sheets: [Sheet] = []
        public var groups: [Group] = []
        public init(sheets: [Sheet] = [], groups: [Group] = []) { self.sheets = sheets; self.groups = groups }
    }

    // MARK: names

    /// Split on commas that are not inside parentheses: "HL test (Hess, spontaneity), no MS" -> ["HL test (Hess, spontaneity)", "no MS"].
    public static func splitTop(_ s: String) -> [String] {
        var out: [String] = [], depth = 0, cur = ""
        for ch in s {
            if ch == "(" { depth += 1 } else if ch == ")" { depth = max(0, depth - 1) }
            if ch == "," && depth == 0 { out.append(cur); cur = "" } else { cur.append(ch) }
        }
        out.append(cur)
        return out.map(\.trimmed).filter { !$0.isEmpty }
    }

    static func num(_ pattern: String, _ s: String) -> Int? {
        guard let g = RX.groups(pattern, s), let d = g[1] else { return nil }
        return Int(d)
    }

    static func levelOf(_ s: String) -> String? {
        let t = " " + RX.replace("[-_]", s, " ") + " "
        let hl = RX.test("(?i)[^A-Za-z]HL[^A-Za-z]", t), sl = RX.test("(?i)[^A-Za-z]SL[^A-Za-z]", t)
        return hl && sl ? "SL & HL" : hl ? "HL" : sl ? "SL" : nil
    }

    public static func kindOf(_ title: String, _ details: String) -> String {
        let d = fold(details), t = fold(title), all = t + " " + d
        if RX.test(#"question bank|\bbank\b"#, d) { return "Question bank" }
        if RX.test("worksheet|practice problems|question set", d) { return "Worksheet" }
        if RX.test("worked", d) { return "Worked examples" }
        if RX.test(#"\bmock\b"#, all) { return "Mock exam" }
        if RX.test("data.based", all) { return "Data-based" }
        let mcq = RX.test(#"\bmcq\b"#, d), str = RX.test("structured|paper 2", d)
        if mcq && !str { return "MCQ" }
        if str && !mcq { return "Paper 2" }
        if RX.test("test|assessment|revision paper|paper|exam|formative|quiz", all) || (mcq && str) || RX.test(#"[0-9]+\s*mk"#, d) { return "Test" }
        return "Other"
    }

    /// A sheet folder's name -> its facts; `meta` is false for a name that is not in the convention (no " — " and no [era]).
    public static func parseSheetName(_ name: String) -> Facts {
        var s = name.trimmed
        var f = Facts()
        var hadEra = false
        if let r = RX.range(#"(?i)\s*\[(2025|pre-2025)\]\s*$"#, s), let g = RX.groups(#"(?i)\s*\[(2025|pre-2025)\]\s*$"#, s) {
            f.era = (g[1] ?? "").lowercased(); hadEra = true
            s = u16prefix(s, r.location).trimmed
        }
        if let r = RX.range(#"(?i)\s*·\s*([0-9]+)\s+copies\b"#, s), let g = RX.groups(#"(?i)\s*·\s*([0-9]+)\s+copies\b"#, s) {
            f.copies = Int(g[1] ?? "") ?? 1
            let ns = s as NSString
            s = (ns.substring(to: r.location) + ns.substring(from: r.location + r.length)).trimmed
        }
        if RX.test(#"(?i)(^|[\s·,])MS only\b"#, s) {
            f.ms = "only"
            s = RX.replaceFirst(#"(?i)\s*·?\s*MS only\b"#, s, "").trimmed
        }
        if RX.test(#"(?i)(^|[\s,])no MS\b"#, s) { f.ms = "none" }
        let dash = s.range(of: " — ")
        f.title = (dash.map { String(s[..<$0.lowerBound]) } ?? s).trimmed
        var rest = dash.map { String(s[$0.upperBound...]).trimmed } ?? ""
        rest = RX.replace(#"\s*·\s*"#, rest, ", ")
        f.details = splitTop(rest).filter { !RX.test(#"(?i)^no MS$"#, $0) }
        f.meta = dash != nil || hadEra
        f.marks = num(#"(?i)([0-9]+)\s*mk\b"#, rest)
        f.pages = num(#"(?i)([0-9]+)\s*pp?\b"#, rest)
        f.minutes = num(#"(?i)([0-9]+)\s*min\b"#, rest)
        f.questions = num(#"([0-9]+)\s*Q\b"#, rest)
        f.level = levelOf(rest) ?? levelOf(f.title)
        f.kind = kindOf(f.title, f.details.joined(separator: ", "))
        return f
    }

    /// A file inside a sheet: the paper, its markscheme, or a student's marked copy.
    public static func fileRole(_ name: String) -> String {
        let n = " " + RX.replace("[._()-]+", stripExt(base(name)), " ") + " "
        if RX.test(#"(?i)\bmarked paper\b"#, n) { return "marked" }
        if RX.test(#"(?i)\b(ms|mark ?schemes?|marking scheme|markin scheme|answers?|solutions?)\b"#, n) { return "ms" }
        return "paper"
    }

    /// The unit folder's name -> { code, label }: "05 Reactivity 1 — Energetics" -> R1, "Reactivity 1 — Energetics".
    public static func unitOfFolder(_ name: String) -> (code: String?, label: String) {
        let label = RX.replace(#"^[0-9]+\s+"#, name, "").trimmed
        guard let m = RX.groups(#"(?i)\b(Structure|Reactivity)\s+([0-9]+)(?:\.([0-9]+))?"#, label), let w = m[1], let n = m[2] else { return (nil, label) }
        return (w.prefix(1).uppercased() + n + (m[3].map { "." + $0 } ?? ""), label)
    }

    /// Syllabus codes written in a name: "S1.1 to S1.5.2, R2.1" -> S1.1 S1.2 S1.3 S1.4 S1.5 R2.1; "S1, R1.1" -> S1 R1.1; "S3.1.9" -> S3.1.
    public static func codesIn(_ s: String) -> [String] {
        var out = OrderedSet()
        for m in RX.all(#"\b([SR])([0-9])\.([0-9]+)(?:\.[0-9]+)*\s*(?:to|-|–)\s*\1\2\.([0-9]+)"#, s) {
            guard let a = Int(m[3] ?? ""), let b = Int(m[4] ?? "") else { continue }
            if b >= a && b - a < 10 { for k in a...b { out.add("\(m[1] ?? "")\(m[2] ?? "").\(k)") } }
        }
        for m in RX.all(#"\b([SR])([1-3])(?:\.([0-9]+))?(?:\.[0-9]+)*(?![A-Za-z0-9_.])"#, s) {
            out.add((m[1] ?? "") + (m[2] ?? "") + (m[3].map { "." + $0 } ?? ""))
        }
        return out.items
    }

    /// Topic words in a title -> codes (IB Chemistry, first assessment 2025). A theme code (S2, R1) stands for every unit in it.
    static let topicWords: [(String, [String])] = [
        ("particulate nature|states of matter|kinetic molecular", ["S1.1"]),
        ("atomic str|atomic structure|nuclear atom|isotope|mass spectr", ["S1.2", "S1.3"]),
        ("electron config|ionization energ|ionisation energ|emission spectr", ["S1.3"]),
        (#"\bmoles?\b|empirical formula|molar mass|avogadro"#, ["S1.4"]),
        (#"gas laws?|ideal gas"#, ["S1.5"]),
        ("ionic", ["S2.1"]),
        ("covalent|lewis|vsepr|hybridi[sz]ation|intermolecular", ["S2.2"]),
        (#"\bbonding\b"#, ["S2"]),
        ("metallic", ["S2.3"]),
        (#"polymer|condensation|alloys?\b|bonding triangle|materials"#, ["S2.4"]),
        ("periodicity|periodic table", ["S3.1"]),
        ("organic|iupac|functional group|naming|isomer", ["S3.2"]),
        ("energetics|enthalpy|calorimetr", ["R1"]),
        (#"\bhess|born.haber|bond enthalp"#, ["R1.2"]),
        (#"combustion|fuels?\b"#, ["R1.3"]),
        ("spontaneity|entropy|gibbs", ["R1.4"]),
        ("stoichiometr|limiting reag|titration|yield", ["R2.1"]),
        (#"kinetics|\brates?\b|activation energy|\bea graphs?\b"#, ["R2.2"]),
        ("equilibri", ["R2.3"]),
        (#"acid.?base|acids? (&|and) bases?|\bph\b|buffer|neutrali[sz]ation"#, ["R3.1"]),
        ("redox|oxidation|electrochem|electrolysis", ["R3.2"]),
        ("radical", ["R3.3"]),
        ("nucleophil|electrophil|substitution|addition reaction", ["R3.4"]),
    ]
    public static func codesFromTitle(_ title: String) -> [String] {
        let t = RX.replace("–|—", fold(title), "-")
        var out = OrderedSet()
        for (re, codes) in topicWords where RX.test(re, t) { for c in codes { out.add(c) } }
        return out.items
    }

    /// "polymers-hl-sl-test-46marks (1).pdf" and its markscheme share a stem: no extension, no "(1)", no markscheme / questions words.
    public static func stemOf(_ name: String) -> String {
        var s = fold(stripExt(base(name)))
        s = RX.replace(#"\([0-9]+\)"#, s, " ")
        s = RX.replace(#"\b(past[- ]test )?questions?\b|\bmarked paper\b|\bmark ?schemes?\b|\bmarking scheme\b|\bmarkin scheme\b|\bms\b|\banswers?\b"#, s, " ")
        s = RX.replace(#"\.pdf\b"#, s, " ")
        return RX.replace(#"[\s_.,-]+"#, s, " ").trimmed
    }
    static func prettyStem(_ name: String) -> String {
        var s = RX.replace(#"\s*\([0-9]+\)\s*$"#, stripExt(base(name)), "")
        s = RX.replace(#"(?i)\s*-\s*(past-test questions|questions)$"#, s, "")
        return s.trimmed
    }

    static func looseFacts(_ name: String) -> Facts {
        let n = stripExt(base(name)), t = RX.replace("[-_]", n, " ")
        var f = Facts()
        f.marks = num(#"(?i)([0-9]+)\s*-?\s*marks?\b"#, t) ?? num(#"(?i)([0-9]+)\s*mk\b"#, t)
        f.minutes = num(#"(?i)([0-9]+)\s*min\b"#, t)
        f.level = levelOf(n)
        f.kind = kindOf(t, t)
        f.era = codesIn(n).isEmpty ? nil : "2025"
        return f
    }

    static func metaName(_ n: String) -> Bool { n.contains(" — ") || RX.test(#"(?i)\[(2025|pre-2025)\]\s*$"#, n) }

    // MARK: the model

    /// files: the sheets folder's file paths (any depth), all inside `root`.
    public static func build(_ files: [String], root: String) -> Model {
        let rootBare = RX.replace("/+$", root, "")
        let pre = root.isEmpty ? "" : rootBare + "/"
        let inRoot = files.filter { pre.isEmpty || $0.hasPrefix(pre) }.filter { !RX.test(#"(^|/)\."#, String($0.dropFirst(pre.count))) }
        var sheets: [Sheet] = []
        var byFolder: [(String, [String])] = [], folderAt: [String: Int] = [:]
        var loose: [(String, [String])] = [], looseAt: [String: Int] = [:]
        var groups: [String: Group] = [:]
        func groupOf(_ dir: String) -> Group? {
            if dir == rootBare { return nil }
            if let g = groups[dir] { return g }
            let u = unitOfFolder(base(dir))
            let g = Group(path: dir, label: u.label, code: u.code)
            groups[dir] = g
            return g
        }
        for p in inRoot {
            // the nearest folder in the convention, up the path (a sheet folder may hold subfolders)
            let rel = String(p.dropFirst(pre.count)).components(separatedBy: "/")
            var sheetDir: String?
            if rel.count >= 2 {
                for i in stride(from: rel.count - 2, through: 0, by: -1) where metaName(rel[i]) {
                    sheetDir = pre + rel[0...i].joined(separator: "/"); break
                }
            }
            if let d = sheetDir {
                if let i = folderAt[d] { byFolder[i].1.append(p) } else { folderAt[d] = byFolder.count; byFolder.append((d, [p])) }
                continue
            }
            let key = dirOf(p) + "\u{0}" + stemOf(p)
            if let i = looseAt[key] { loose[i].1.append(p) } else { looseAt[key] = loose.count; loose.append((key, [p])) }
        }
        for (dir, fs) in byFolder {
            let f = parseSheetName(base(dir))
            let g = groupOf(dirOf(dir))
            let files = fs.sorted(by: jsLess).map { File(path: $0, name: base($0), role: fileRole($0)) }
            let hasMs = files.contains { $0.role == "ms" }
            sheets.append(finish(Sheet(id: dir, path: dir, dir: true, group: g, title: f.title, details: f.details, era: f.era, copies: f.copies,
                                       ms: f.ms ?? (hasMs ? "with" : "none"), meta: f.meta, marks: f.marks, pages: f.pages, minutes: f.minutes,
                                       questions: f.questions, level: f.level, kind: f.kind, files: files)))
        }
        for (_, fs) in loose {
            let files = fs.sorted(by: jsLess).map { File(path: $0, name: base($0), role: fileRole($0)) }
            let paper = files.first { $0.role == "paper" } ?? files[0]
            let g = groupOf(dirOf(paper.path))
            let hasMs = files.contains { $0.role == "ms" }, onlyMs = files.allSatisfy { $0.role == "ms" }
            var facts = looseFacts(paper.name)
            if facts.kind == "Other", let g, RX.test("(?i)test|exam|paper", g.label) { facts.kind = "Test" }
            sheets.append(finish(Sheet(id: paper.path, path: paper.path, dir: false, group: g, title: prettyStem(paper.name), details: [], era: facts.era,
                                       copies: 1, ms: onlyMs ? "only" : hasMs ? "with" : "none", meta: false, marks: facts.marks, pages: nil,
                                       minutes: facts.minutes, questions: nil, level: facts.level, kind: facts.kind, files: files)))
        }
        sheets = stableSorted(sheets) { a, b in
            let c = localeOrder(a.group?.path ?? "", b.group?.path ?? "")
            return c != 0 ? c < 0 : localeOrder(a.title, b.title) < 0
        }
        let gs = stableSorted(groups.values.sorted { jsLess($0.path, $1.path) }) { localeOrder($0.path, $1.path) < 0 }
        return Model(sheets: sheets, groups: gs)
    }

    static func finish(_ s0: Sheet) -> Sheet {
        var s = s0
        var from = OrderedSet(), how: [String: String] = [:]
        func add(_ c: String, _ h: String) { if how[c] == nil { how[c] = h; from.add(c) } }
        if let c = s.group?.code { add(c, "folder") }
        for f in s.files { for c in codesIn(stripExt(f.name)) { add(c, "name") } }
        for c in codesIn(s.title) { add(c, "name") }
        for c in codesFromTitle(([s.title] + s.details).joined(separator: " ")) { add(c, "title") }
        s.codes = from.items.sorted(by: jsLess)
        s.codeFrom = how
        let words = [s.title, s.details.joined(separator: " "), s.group?.label ?? "", s.kind, s.level ?? "", s.codes.joined(separator: " ")] + s.files.map(\.name)
        s.search = RX.replace("[&+]", fold(words.joined(separator: " ")), " ")
        return s
    }

    /// The upload's notes and confirmed units joined to the sheets (study/sheets.yaml, keyed by the sheet's path in the sheets folder).
    public static func withIndex(_ m: Model, root: String, index: [String: SheetIndex.Entry]) -> Model {
        var out = m
        for i in out.sheets.indices {
            guard let info = index[relIn(root, out.sheets[i].path)] else { continue }
            out.sheets[i].notes = SheetIndex.notesText(info.notes)
            for c in info.units where !out.sheets[i].codes.contains(c) { out.sheets[i].codes.append(c); out.sheets[i].codeFrom[c] = "upload" }
            out.sheets[i].codes.sort(by: jsLess)
            if !out.sheets[i].notes.isEmpty { out.sheets[i].search += " " + out.sheets[i].notes.lowercased() }
        }
        return out
    }

    // MARK: units and sheets

    public static func themeOf(_ code: String) -> String { code.components(separatedBy: ".")[0] }
    public static func isTheme(_ code: String) -> Bool { !code.contains(".") }

    /// The sheets about a unit (S1.4), or with a code in a theme (S1); `extra`: sheet paths or titles units.yaml names.
    public static func sheetsFor(unit want: String, in sheets: [Sheet], extra: [String] = []) -> [Sheet] {
        sheets.filter { s in
            (isTheme(want) ? s.codes.contains { themeOf($0) == want } : s.codes.contains(want))
                || extra.contains { x in s.path == x || s.path.hasSuffix("/" + x) || fold(s.title) == fold(x) }
        }
    }

    public struct Filter: Equatable, Sendable, Codable {
        public var q = "", unit = "", kind = "", era = "", ms = "", level = ""
        public init(q: String = "", unit: String = "", kind: String = "", era: String = "", ms: String = "", level: String = "") {
            self.q = q; self.unit = unit; self.kind = kind; self.era = era; self.ms = ms; self.level = level
        }
        public var isEmpty: Bool { q.isEmpty && unit.isEmpty && kind.isEmpty && era.isEmpty && ms.isEmpty && level.isEmpty }
        /// How many filters other than the search are on.
        public var count: Int { [unit, kind, era, ms, level].filter { !$0.isEmpty }.count }
    }

    public static func filter(_ sheets: [Sheet], _ f: Filter) -> [Sheet] {
        let words = RX.replace("[&+]", fold(f.q), " ").components(separatedBy: CharacterSet.whitespacesAndNewlines).filter { !$0.isEmpty }
        return sheets.filter { s in
            if !words.isEmpty && !words.allSatisfy({ s.search.contains($0) }) { return false }
            if !f.unit.isEmpty && sheetsFor(unit: f.unit, in: [s]).isEmpty { return false }
            if !f.kind.isEmpty && s.kind != f.kind { return false }
            if !f.era.isEmpty && (f.era == "unknown" ? s.era != nil : s.era != f.era) { return false }
            if f.ms == "with" && s.ms == "none" { return false }
            if f.ms == "none" && s.ms != "none" { return false }
            if f.ms == "only" && s.ms != "only" { return false }
            if !f.level.isEmpty && !(s.level ?? "").contains(f.level) { return false }
            return true
        }
    }

    public static func sort(_ list: [Sheet], by: String) -> [Sheet] {
        switch by {
        case "title": return stableSorted(list) { localeOrder($0.title, $1.title) < 0 }
        case "marks", "pages":
            let v = { (s: Sheet) -> Int in (by == "marks" ? s.marks : s.pages) ?? -1 }
            return stableSorted(list) { a, b in v(a) != v(b) ? v(a) > v(b) : localeOrder(a.title, b.title) < 0 }
        default: return list
        }
    }

    /// One line of facts for a sheet: "HL · 40 marks · 60 min · 26 pages · 3 copies".
    public static func factsLine(_ s: Sheet) -> String {
        [s.level ?? "", s.marks.map { "\($0) marks" } ?? "", s.questions.map { "\($0) questions" } ?? "", s.minutes.map { "\($0) min" } ?? "",
         s.pages.map { "\($0) \($0 == 1 ? "page" : "pages")" } ?? "", s.copies > 1 ? "\(s.copies) copies" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    public static func msLabel(_ ms: String) -> String { ms == "only" ? "Markscheme only" : ms == "none" ? "No markscheme" : "With markscheme" }

    // MARK: names for the upload (the folder's convention)

    /// Windows-safe: no < > : " / \ | ? * or control characters, no trailing dots or spaces, at most 150 characters.
    public static func safeName(_ s: String) -> String {
        var x = RX.replace("[ \\t]*[<>:\"/\\\\|?*\\u0000-\\u001f]+[ \\t]*", s, " ").trimmed
        x = RX.replace("[. ]+$", x, "")
        return u16prefix(x, 150).trimmed
    }

    /// "Title — details · MS only [2025]".
    public static func sheetFolderName(title: String, details: String, ms: String, copies: Int = 1, era: String?) -> String {
        var d = RX.replaceFirst(#"(?i),?\s*no MS\b"#, details, "")
        d = RX.replaceFirst(#"(?i)\s*·?\s*MS only\b"#, d, "").trimmed
        d = RX.replace(",$", d, "")
        if ms == "none" { d = d.isEmpty ? "no MS" : d + ", no MS" }
        var s = safeName(title) + (d.isEmpty ? "" : " — " + d)
        if ms == "only" { s += " · MS only" }
        if copies > 1 { s += " · \(copies) copies" }
        if era == "2025" || era == "pre-2025" { s += " [\(era!)]" }
        return safeName(s)
    }

    /// A file's name in a sheet folder: its own name, made to say the role the user confirmed (the browser reads the role from the name).
    public static func fileNameFor(_ original: String, role: String) -> String {
        let ext = (RX.groups(#"\.[A-Za-z0-9]{1,5}$"#, original)?[0] ?? "").lowercased()
        var b = safeName(stripExt(base(original)))
        if b.isEmpty { b = "sheet" }
        if role == "ms" && fileRole(b + ext) != "ms" { b += " MS" }
        else if role == "marked" && fileRole(b + ext) != "marked" { b += " marked paper" }
        else if role == "paper" && fileRole(b + ext) != "paper" {
            b = RX.replace(#"(?i)[\s_-]*\b(marked paper|mark ?schemes?|marking scheme|markin scheme|ms|answers?|solutions?)\b"#, b, "")
            b = RX.replace(#"[\s_-]+$"#, b, "").trimmed
            if b.isEmpty { b = "paper" }
        }
        return b + ext
    }

    /// A folder path made of safe names; no empty, "." or ".." parts.
    public static func safePath(_ s: String) -> String {
        RX.split(#"[\\/]+"#, s).map(safeName).filter { !$0.isEmpty && $0 != "." && $0 != ".." }.joined(separator: "/")
    }
    /// A path inside the sheets folder, relative to it.
    public static func relIn(_ root: String, _ p: String) -> String {
        let pre = RX.replace("/+$", root, "") + "/"
        return p.hasPrefix(pre) ? String(p.dropFirst(pre.count)) : p
    }
    /// The next unit folder for a new unit, beside the numbered ones (relative to the root).
    public static func newUnitFolderName(_ groups: [Group], label: String, root: String = "") -> String {
        let numbered = groups.filter { RX.test(#"^[0-9]+\s"#, base($0.path)) }
        let n = numbered.reduce(0) { m, g in max(m, Int(RX.groups(#"^([0-9]+)\s"#, base(g.path))?[1] ?? "") ?? 0) } + 1
        let parent = numbered.isEmpty ? "" : dirOf(relIn(root, numbered[0].path))
        return (parent.isEmpty ? "" : parent + "/") + String(format: "%02d", n) + " " + safeName(label)
    }

    // MARK: helpers

    /// Accents off, lower case (the laptop's fold: NFKD, combining marks removed).
    public static func fold(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.decomposedStringWithCompatibilityMapping.unicodeScalars where !(0x300...0x36F).contains(u.value) { out.append(u) }
        return String(out).lowercased()
    }
    public static func base(_ p: String) -> String { p.components(separatedBy: "/").last ?? p }
    public static func dirOf(_ p: String) -> String {
        guard let i = p.range(of: "/", options: .backwards) else { return "" }
        return String(p[..<i.lowerBound])
    }
    static func stripExt(_ n: String) -> String { RX.replace(#"\.[A-Za-z0-9]{1,5}$"#, n, "") }

    /// The first `n` UTF-16 units of `s` (JavaScript's slice).
    static func u16prefix(_ s: String, _ n: Int) -> String {
        let ns = s as NSString
        return n >= ns.length ? s : ns.substring(to: max(0, n))
    }
    static func u16len(_ s: String) -> Int { (s as NSString).length }

    /// JavaScript's localeCompare (the laptop's sorts by name), as a three-way result.
    public static func localeOrder(_ a: String, _ b: String) -> Int {
        switch a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US")) {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }

    /// A stable sort (JavaScript's Array.prototype.sort is stable; Swift's sort is not promised to be).
    static func stableSorted<T>(_ a: [T], by less: (T, T) -> Bool) -> [T] {
        a.enumerated().sorted { x, y in less(x.element, y.element) || (!less(y.element, x.element) && x.offset < y.offset) }.map(\.element)
    }
}

/// A list of distinct strings in the order they were first added (JavaScript's Set).
struct OrderedSet {
    private(set) var items: [String] = []
    private var seen = Set<String>()
    mutating func add(_ s: String) { if seen.insert(s).inserted { items.append(s) } }
    func has(_ s: String) -> Bool { seen.contains(s) }
    var count: Int { items.count }
}

/// Regular expressions compiled once, with JavaScript's results (groups that took no part are nil).
enum RX {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func re(_ pattern: String) -> NSRegularExpression {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        // the patterns are constants; a bad one is a programming error the tests catch
        let r = try! NSRegularExpression(pattern: pattern, options: [])
        cache[pattern] = r
        return r
    }
    private static func all(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    static func groups(_ pattern: String, _ s: String) -> [String?]? {
        guard let m = re(pattern).firstMatch(in: s, options: [], range: all(s)) else { return nil }
        return pieces(m, s)
    }
    static func range(_ pattern: String, _ s: String) -> NSRange? { re(pattern).firstMatch(in: s, options: [], range: all(s))?.range }
    static func test(_ pattern: String, _ s: String) -> Bool { range(pattern, s) != nil }
    static func all(_ pattern: String, _ s: String) -> [[String?]] { re(pattern).matches(in: s, options: [], range: all(s)).map { pieces($0, s) } }
    static func replace(_ pattern: String, _ s: String, _ with: String) -> String {
        re(pattern).stringByReplacingMatches(in: s, options: [], range: all(s), withTemplate: NSRegularExpression.escapedTemplate(for: with))
    }
    /// A replacement with $1-style groups in it.
    static func replaceTemplate(_ pattern: String, _ s: String, _ template: String) -> String {
        re(pattern).stringByReplacingMatches(in: s, options: [], range: all(s), withTemplate: template)
    }
    /// The first match only (JavaScript's replace without /g).
    static func replaceFirst(_ pattern: String, _ s: String, _ with: String) -> String {
        guard let r = range(pattern, s) else { return s }
        return (s as NSString).replacingCharacters(in: r, with: with)
    }
    static func split(_ pattern: String, _ s: String) -> [String] {
        var out: [String] = [], last = 0
        let ns = s as NSString
        for m in re(pattern).matches(in: s, options: [], range: all(s)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }
    private static func pieces(_ m: NSTextCheckingResult, _ s: String) -> [String?] {
        let ns = s as NSString
        return (0..<m.numberOfRanges).map { i in let r = m.range(at: i); return r.location == NSNotFound ? nil : ns.substring(with: r) }
    }
}
