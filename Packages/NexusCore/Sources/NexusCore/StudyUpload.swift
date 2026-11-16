import Foundation
import Yams

/// Study › Upload a sheet, the pure half: the laptop's renderer/src/studyupload.js and studyread.js (nexus proposals/study/PDF-READING.md).
/// What Claude is told about the sheets folder, when a PDF's text is too thin (a scan) and which pages OCR reads first, the digest Claude
/// gets, a free keyword hint, the question, Claude's answer read into a proposal, where the confirmed file goes (cut to fit a Windows
/// path, since the laptop opens the same folder), what the app checks itself (the same name, the same text by word shingles), and
/// study/sheets.yaml (what was confirmed about each filed sheet). The reading itself (PDFKit, Vision) is the app's.
public enum StudyUpload {
    public typealias Model = StudySheets.Model

    // MARK: what Claude is told about the folder

    /// Each unit folder with its sheet folders, and the loose files. `focus` (folder paths inside the sheets folder): only those are
    /// listed sheet by sheet; every other folder is its name and how many sheets it holds.
    public static func folderSummary(_ model: Model, root: String, focus: [String]? = nil) -> String {
        let pre = RX.replace("/+$", root, "") + "/"
        let rel = { (p: String) in p.hasPrefix(pre) ? String(p.dropFirst(pre.count)) : p }
        var by: [(String, [String])] = []
        func put(_ g: String, _ line: String?) {
            if let i = by.firstIndex(where: { $0.0 == g }) { if let line { by[i].1.append(line) } } else { by.append((g, line.map { [$0] } ?? [])) }
        }
        for s in model.sheets {
            let g = s.group.map { rel($0.path) } ?? "(top level)"
            put(g, s.dir ? "  - " + StudySheets.base(s.path) + "/" : "  - " + s.files.map(\.name).joined(separator: " | "))
        }
        for g in model.groups where !by.contains(where: { $0.0 == rel(g.path) }) { put(rel(g.path), nil) }
        let show = { (g: String) in focus.map { $0.contains(g) } ?? true }
        let text = StudySheets.stableSorted(by) { StudySheets.localeOrder($0.0, $1.0) < 0 }.map { g, l in
            show(g) ? g + "/\n" + l.joined(separator: "\n") : "\(g)/ (\(l.count) sheet\(l.count == 1 ? "" : "s"), not listed)"
        }.joined(separator: "\n")
        return RX.replace("\n+$", text, "")
    }

    // MARK: where the file goes

    public struct Placement: Equatable, Sendable {
        public var unitFolder: String
        public var existingSheet: String?
        public var title: String
        public var details: String
        public var ms: String
        public var era: String?
        public var fileName: String
        public init(unitFolder: String, existingSheet: String? = nil, title: String, details: String, ms: String, era: String?, fileName: String) {
            self.unitFolder = unitFolder; self.existingSheet = existingSheet; self.title = title; self.details = details; self.ms = ms; self.era = era; self.fileName = fileName
        }
    }

    /// The laptop's data folder path is "C:\Users\…\nexus-data" (about 41 characters): the room a path inside it has under Windows' 260.
    public static let pathRoom = 208

    /// <root>/<unit folder>/<sheet folder>/<file name>, at most `max` characters (nil: no limit). A new sheet folder gives up its details
    /// first and keeps its [era], then the file name its end (never its extension). An existing folder is kept.
    public static func targetPath(root: String, _ p: Placement, max: Int? = nil) -> String {
        let head = [RX.replace("/+$", root, ""), StudySheets.safePath(p.unitFolder)].filter { !$0.isEmpty }.joined(separator: "/")
        let len = StudySheets.u16len
        var sheet = StudySheets.safeName(p.existingSheet.flatMap { $0.isEmpty ? nil : $0 } ?? StudySheets.sheetFolderName(title: p.title, details: p.details, ms: p.ms, era: p.era))
        var file = StudySheets.safeName(p.fileName)
        let room = { (s: String, f: String) -> Int in
            guard let max else { return Int.max }
            return max - (len(head) + 1 + len(s) + 1 + len(f)) - 4 // 4: room for " (2)"
        }
        if room(sheet, file) < 0 && (p.existingSheet ?? "").isEmpty {
            let era = RX.groups(#" \[(?:2025|pre-2025)\]$"#, sheet)?[0] ?? ""
            let bare = StudySheets.u16prefix(sheet, len(sheet) - len(era))
            sheet = fitName(bare, Swift.max(12, len(bare) + room(sheet, file))) + era
        }
        if room(sheet, file) < 0 {
            let ext = RX.groups(#"\.[A-Za-z0-9]{1,5}$"#, file)?[0] ?? ""
            let b = StudySheets.u16prefix(file, len(file) - len(ext))
            file = fitName(b, Swift.max(8, len(b) + room(sheet, file))) + ext
        }
        return head + "/" + sheet + "/" + file
    }

    /// A name cut to n characters at a word, without a dangling " —" or comma.
    static func fitName(_ s: String, _ n: Int) -> String {
        if StudySheets.u16len(s) <= n { return s }
        var c = StudySheets.u16prefix(s, n)
        let sp = (c as NSString).range(of: " ", options: .backwards).location
        if sp != NSNotFound, Double(sp) > Double(n) * 0.6 { c = StudySheets.u16prefix(c, sp) }
        let out = RX.replace(#"[\s,—–-]+$"#, c, "").trimmed
        return out.isEmpty ? StudySheets.u16prefix(s, n) : out
    }

    /// Where a new numbered unit folder goes: beside the numbered ones, else at the top.
    public static func newUnitParent(_ model: Model, root: String) -> String {
        let n = StudySheets.newUnitFolderName(model.groups, label: "x", root: root)
        guard let i = n.range(of: "/", options: .backwards) else { return "" }
        return String(n[...i.lowerBound])
    }

    // MARK: duplicates the app can see for itself

    /// Files of the same name (stem: no markscheme words, no "(1)", no extension), in any sheet.
    public static func sameNameFiles(_ model: Model, _ fileName: String) -> [String] {
        let st = StudySheets.stemOf(fileName)
        if st.isEmpty { return [] }
        return model.sheets.flatMap(\.files).filter { StudySheets.stemOf($0.name) == st }.map(\.path)
    }

    /// Word 5-shingles of a text (lower case, letters and digits only).
    public static func shingles(_ text: String, k: Int = 5) -> Set<String> {
        let w = RX.replace("[^a-z0-9]+", text.lowercased().decomposedStringWithCompatibilityMapping, " ").trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        var out = Set<String>()
        if w.count >= k { for i in 0...(w.count - k) { out.insert(w[i..<(i + k)].joined(separator: " ")) } }
        return out
    }
    /// The share of the smaller text's shingles found in the other (a copy with a page more still matches).
    public static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        let (s, l) = a.count <= b.count ? (a, b) : (b, a)
        return Double(s.filter { l.contains($0) }.count) / Double(s.count)
    }
    /// At least this share of the text in common: "likely the same sheet".
    public static let near = 0.6
    /// Too little text to compare below this.
    public static let minShingles = 25

    /// The files worth comparing text with: the same name, what Claude named, and the unit folder's of the same role; at most `max`.
    public static func compareCandidates(_ model: Model, root: String, proposal: Proposal?, fileName: String, max: Int = 16) -> [String] {
        let pre = RX.replace("/+$", root, "") + "/"
        var out = OrderedSet()
        for p in sameNameFiles(model, fileName) { out.add(p) }
        for d in proposal?.duplicates ?? [] {
            let p = d.path.hasPrefix(pre) ? d.path : pre + d.path
            let bare = RX.replace("/$", p, "")
            for s in model.sheets where s.path == p || s.path == bare || s.files.contains(where: { $0.path == p }) {
                for f in s.files where f.role != "marked" { out.add(f.path) }
            }
        }
        if let pr = proposal, !pr.unitFolder.isEmpty {
            let role = StudySheets.fileRole(fileName)
            for s in model.sheets where s.group.map({ StudySheets.relIn(root, $0.path) }) == pr.unitFolder {
                for f in s.files where f.role == role || f.role == (pr.role.isEmpty ? "paper" : pr.role) { out.add(f.path) }
            }
        }
        return Array(out.items.filter { RX.test(#"(?i)\.(pdf|docx|txt|md)$"#, $0) }.prefix(max))
    }

    // MARK: reading a PDF

    public static let digestMax = 8000
    /// Letters on a page below which it is a scan (a short typed page, a markscheme's last line, is still text).
    public static let pageThin = 25

    static func letters(_ s: String) -> Int { s.unicodeScalars.filter { ($0.value >= 65 && $0.value <= 90) || ($0.value >= 97 && $0.value <= 122) }.count }

    /// A text layer with almost nothing on it: a scan, or a PDF of images.
    public static func isThin(_ pages: [String]) -> Bool {
        let n = pages.count
        if n == 0 { return true }
        let total = pages.reduce(0) { $0 + letters($1) }
        return total < 120 || Double(total) / Double(min(n, 6)) < 60 && pages.prefix(3).allSatisfy { letters($0) < 150 }
    }
    /// The pages (1-based) with almost no text, which OCR reads (a PDF can mix typed pages and scans); at most `max`.
    public static func thinPages(_ pages: [String], max: Int = Int.max) -> [Int] {
        Array(pages.enumerated().filter { letters($0.element) < pageThin }.map { $0.offset + 1 }.prefix(max))
    }
    /// The ones read before Claude is asked: among the first `k` pages and the last, those that need it.
    public static func ocrFirst(_ need: [Int], pages n: Int, k: Int = 3) -> [Int] {
        var want = Set<Int>([n])
        if min(k, n) >= 1 { for i in 1...min(k, n) { want.insert(i) } }
        return need.filter { want.contains($0) }
    }

    /// A line worth keeping from the middle of a paper: a section or paper header, a question's start, marks or time.
    static let key = #"(?i)^\s*(section\s+[a-z0-9]\b|paper\s+[1-3]\b|part\s+[a-z0-9]\b|topic\s+[0-9]|unit\s+[0-9]|mark ?scheme|markscheme|answers?\b|structure\s+[0-9]|reactivity\s+[0-9]|[SR][1-3]\.[0-9])|^\s*(?:q(?:uestion)?\.?\s*)?[0-9]{1,2}\s*[.)]\s|^\s*[0-9]{1,2}\s*\(\s*[a-z]\s*\)|^\s*\(\s*[a-z]\s*\)\s|\[\s*[0-9]+\s*(?:marks?|mk)?\s*\]|\(\s*[0-9]+\s*marks?\s*\)|\b[0-9]+\s*(?:minutes|mins?|marks)\b|\btotal\b.*\bmarks?\b"#
    static func tidy(_ s: String) -> String { RX.replace(#"\n{3,}"#, RX.replace("[ \\t]+", s, " "), "\n\n").trimmed }
    static func cut(_ s: String, _ n: Int) -> String {
        StudySheets.u16len(s) > n ? RX.replace(#"\s+\S*$"#, StudySheets.u16prefix(s, n), "") + " …" : s
    }
    public static func keyLines(_ text: String, max: Int = 40) -> [String] {
        var out: [String] = []
        for l in text.components(separatedBy: "\n") {
            let t = l.trimmed
            if !t.isEmpty && RX.test(key, t) { out.append(cut(t, 110)) }
            if out.count >= max { break }
        }
        return out
    }

    /// The digest Claude gets: pages 1-2 and the last in full, and from every other page its headers, question starts and marks.
    public static func digest(_ pages: [String], cap: Int = digestMax) -> String {
        let n = pages.count
        if n == 0 { return "" }
        let full = { (i: Int, m: Int) in "--- page \(i + 1) ---\n" + cut(tidy(pages[i]), m) }
        let head = [full(0, 2600)] + (n > 1 ? [full(1, 2000)] : [])
        let tail = n > 2 ? [full(n - 1, 1600)] : []
        var mids: [(i: Int, k: [String])] = []
        if n > 3 { for i in 2..<(n - 1) { let k = keyLines(pages[i]); if !k.isEmpty { mids.append((i, k)) } } }
        var room = cap - StudySheets.u16len((head + tail).joined(separator: "\n")) - 40
        let per = mids.isEmpty ? 0 : Swift.max(120, Int((Double(room) / Double(mids.count)).rounded(.down)))
        var mid: [String] = []
        for m in mids {
            if room < 80 { mid.append("--- pages \(m.i + 1)-\(n - 1): not shown (too long) ---"); break }
            var s = "--- page \(m.i + 1) (headers, questions, marks) ---"
            for l in m.k {
                if StudySheets.u16len(s) + StudySheets.u16len(l) + 1 > per { break }
                s += "\n" + l
            }
            mid.append(s)
            room -= StudySheets.u16len(s) + 1
        }
        return StudySheets.u16prefix((head + mid + tail).joined(separator: "\n"), cap)
    }

    /// A free local pointer: the IB codes written in the sheet and the topics its words name, most frequent first.
    public static func keywordCounts(_ pages: [String]) -> [(code: String, n: Int)] {
        var count: [(code: String, n: Int)] = []
        for p in pages {
            var seen = OrderedSet()
            for c in StudySheets.codesIn(p) + StudySheets.codesFromTitle(p) { seen.add(c) }
            for c in seen.items { if let i = count.firstIndex(where: { $0.code == c }) { count[i].n += 1 } else { count.append((c, 1)) } }
        }
        return StudySheets.stableSorted(count) { a, b in a.n != b.n ? a.n > b.n : StudySheets.localeOrder(a.code, b.code) < 0 }
    }
    public static func keywordHint(_ pages: [String]) -> String {
        keywordCounts(pages).prefix(8).map { "\($0.code) ×\($0.n)" }.joined(separator: ", ")
    }

    static func covers(_ g: StudySheets.Group, _ c: String) -> Bool {
        guard let code = g.code else { return false }
        return c == code || c.hasPrefix(code + ".") || code.hasPrefix(c + ".")
    }
    /// The folders Claude sees sheet by sheet: the unit folders of the `n` codes the keyword count scores highest, and Multi-Topic Papers.
    public static func focusFolders(_ model: Model, root: String, pages: [String], n: Int = 3) -> [String] {
        var out: [String] = []
        let coded = model.groups.filter { $0.code != nil }
        for (c, _) in keywordCounts(pages) {
            if let g = StudySheets.stableSorted(coded.filter({ covers($0, c) })) { ($0.code ?? "").count > ($1.code ?? "").count }.first,
               !out.contains(StudySheets.relIn(root, g.path)) { out.append(StudySheets.relIn(root, g.path)) }
            if out.count >= n { break }
        }
        if let multi = model.groups.first(where: { RX.test("(?i)multi", $0.label) }) { out.append(StudySheets.relIn(root, multi.path)) }
        return out
    }

    // MARK: the question

    public static let system = "You file a student's practice sheets into their folder, following its naming convention exactly. You have no tools. Give your answer in the structured form asked for (if you cannot, as one fenced json block with those fields)."

    /// how: text | ocr | images; images: the page numbers whose pictures come with it.
    public static func readPrompt(fileName: String, text: String, hint: String, summary: String, units: String, how: String = "text", pages: Int = 0, images: [Int] = [], note: String = "") -> String {
        let read = how == "ocr" ? "This is (at least partly) a scan: the text of its scanned pages was read by OCR, so expect misread characters."
            : how == "images" ? "This is a scan with little or no readable text." : "The text below is the PDF's own text."
        let pics = images.isEmpty ? "" : " Pictures of page\(images.count > 1 ? "s" : "") \(images.map(String.init).joined(separator: ", ")) come with this message."
        let lines = [
            "(Nexus sheet sort) A student is filing a practice sheet into their sheets folder. Decide what it is, which IB Chemistry units it covers, where it belongs and what to call it, following the folder's own naming convention exactly.",
            "",
            "The convention: unit folders like \"05 Reactivity 1 — Energetics\" (number, IB theme and topic) and a \"Multi-Topic Papers\" folder for sheets that span units in different folders.",
            "Inside, one folder per sheet named \"<Title> — <details> · N copies [2025|pre-2025]\": details are level (HL/SL), kind, marks (\"40 mk\"), minutes (\"60 min\"),",
            "pages (\"26 pp\"), and \"no MS\" when there is no markscheme or \"· MS only\" when it is only a markscheme. [2025] = written for the syllabus first assessed",
            "2025 (codes like S1.2, R2.2; \"Structure\"/\"Reactivity\"); [pre-2025] = the older syllabus (topics numbered 1-11, \"Topic 5\"). The files keep their own names;",
            "a markscheme file ends in \" MS\". If this file is the markscheme (or the paper) of a sheet that is already there, give that existing sheet folder.",
            "List every unit the sheet covers with the section it is in (a paper with Section A on kinetics and Section B on equilibrium gives both).",
            "Say unsure (with the reason) only if the text is too thin or garbled to tell what the sheet is or which units it covers; an era you cannot",
            "tell is not a reason (give era \"unknown\"). Put anything else worth knowing in notes, in one or two short sentences (a question outside the",
            "2025 syllabus, pages missing, a markscheme for only one section), else leave notes empty. Name each section briefly (\"Section A\", \"Paper 1\").",
            units.isEmpty ? "" : "\nThe syllabus units (code: title):\n" + units,
            "",
            "The sheets folder now (the folders most likely for this sheet are listed in full, the others by name only; if you need another folder's sheets to decide, say unsure and name the folder):",
            summary,
            "",
            "The new file's name: \(fileName)",
            "Pages: \(pages > 0 ? String(pages) : "unknown"). \(read)\(pics)",
            note.isEmpty ? "" : "The student knows this sheet and says: \"\"\"\(note)\"\"\"\nTrust that over the file's text and name for what it is, its units, level, marks, time and whether it is the paper or the markscheme. Use the rest only for what they did not say. Do not say unsure about anything they told you.",
            hint.isEmpty ? "" : "A local keyword count (a pointer only, it can be wrong): \(hint)",
            !text.isEmpty ? (!note.isEmpty ? "The start of the file:\n\"\"\"\n\(text)\n\"\"\"" : "The file as a digest (pages 1-2 and the last in full; from every other page its section headers, question starts and marks):\n\"\"\"\n\(text)\n\"\"\"") : "No text could be read from it.",
        ]
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The phone and iPad have no structured output: the schema goes into the question, and the answer comes as one fenced json block.
    public static func answerFormat() -> String {
        "\n\nAnswer with one fenced json block (```json … ```) and nothing else: an object with exactly these fields, as this JSON Schema describes:\n" + schemaJSON
    }

    public static let kinds = ["test", "mcq", "paper 2", "question bank", "worksheet", "worked examples", "mock exam", "data-based", "other"]
    static let kindLabel: [String: String] = ["test": "test", "mcq": "MCQ", "paper 2": "Paper 2 structured", "question bank": "question bank", "worksheet": "worksheet",
                                              "worked examples": "worked set", "mock exam": "mock exam", "data-based": "data-based set", "other": ""]
    /// The laptop's studyread.js SCHEMA, as JSON.
    public static let schemaJSON = #"{"type":"object","additionalProperties":false,"required":["summary","title","units","primaryUnit","kind","level","marks","minutes","pages","hasMarkscheme","role","era","unitFolder","existingSheet","details","fileName","duplicates","notes","unsure","reason"],"properties":{"summary":{"type":"string","description":"one line: what the file is"},"title":{"type":"string","description":"the sheet title in the folder convention, without details"},"units":{"type":"array","description":"every IB unit the sheet covers, by section","items":{"type":"object","additionalProperties":false,"required":["code","section"],"properties":{"code":{"type":"string","description":"e.g. R2.2"},"section":{"type":"string","description":"e.g. Section A, or \"\" for the whole sheet"}}}},"primaryUnit":{"type":"string"},"kind":{"type":"string","enum":["test","mcq","paper 2","question bank","worksheet","worked examples","mock exam","data-based","other"]},"level":{"type":"string","enum":["HL","SL","SL & HL",""]},"marks":{"type":["integer","null"]},"minutes":{"type":["integer","null"]},"pages":{"type":["integer","null"]},"hasMarkscheme":{"type":"boolean","description":"a markscheme is in this file or beside it"},"role":{"type":"string","enum":["paper","markscheme","both"]},"era":{"type":"string","enum":["2025","pre-2025","unknown"]},"unitFolder":{"type":"string","description":"a unit folder path exactly as listed, or a new one beside the numbered ones"},"existingSheet":{"type":["string","null"],"description":"an existing sheet folder in that unit folder this file belongs to, else null"},"details":{"type":"string","description":"e.g. HL test, 40 mk, 60 min"},"fileName":{"type":"string"},"duplicates":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["path","why"],"properties":{"path":{"type":"string"},"why":{"type":"string"}}}},"notes":{"type":"string","description":"one or two short sentences: anything else worth knowing about this sheet (a question out of the 2025 syllabus, pages missing, a markscheme for only one section), else \"\""},"unsure":{"type":"boolean","description":"true only when the text is too thin or garbled to tell what the sheet is or which units it covers (not for an unknown era)"},"reason":{"type":"string","description":"why unsure, else \"\""}}}"#

    // MARK: the answer

    public struct Section: Equatable, Sendable { public var name: String; public var codes: [String] }
    public struct Duplicate: Equatable, Sendable { public var path: String; public var why: String }

    /// What the form shows: Claude's answer read and checked against the folder.
    public struct Proposal: Equatable, Sendable {
        public var summary = ""
        /// paper | ms | marked
        public var role = "paper"
        public var unitFolder = ""
        public var unitIsNew = false
        public var multi = false
        public var existingSheet: String?
        public var title = ""
        public var details = ""
        public var era: String?
        /// with | none | only
        public var ms = "with"
        public var codes: [String] = []
        public var sections: [Section] = []
        public var fileName = ""
        public var duplicates: [Duplicate] = []
        public var kind = "other"
        public var level = ""
        public var marks: Int?
        public var minutes: Int?
        public var pages: Int?
        public var notes = ""
        public var unsure = false
        public var reason = ""
        public init() {}
    }

    static let code = #"^[SR][1-3](\.[0-9]{1,2})?$"#

    /// The folder a set of unit codes belongs in: the one unit folder that covers all of them, else Multi-Topic Papers (found, or new).
    public static func folderFor(_ codes: [String], _ model: Model, root: String) -> (folder: String?, multi: Bool) {
        let groups = model.groups.filter { $0.code != nil }
        var homes = Set<String?>()
        for c in codes { homes.insert(StudySheets.stableSorted(groups.filter { covers($0, c) }) { ($0.code ?? "").count > ($1.code ?? "").count }.first?.path) }
        if !codes.isEmpty, homes.count == 1, let only = homes.first, let path = only { return (StudySheets.relIn(root, path), false) }
        if codes.count <= 1 { return (nil, false) }
        if let multi = model.groups.first(where: { RX.test("(?i)multi", $0.label) }) { return (StudySheets.relIn(root, multi.path), true) }
        return (StudySheets.newUnitFolderName(model.groups, label: "Multi-Topic Papers", root: root), true)
    }

    public enum Answer: Equatable, Sendable {
        case ok(Proposal)
        case failed(String)
    }

    /// Claude's answer (the JSON in its reply) -> the proposal the form shows.
    public static func readAnswer(_ o: JSONValue?, fileName: String, model: Model?, root: String) -> Answer {
        guard let o, case .object = o else { return .failed("Claude's answer was not in the expected form.") }
        func str(_ v: JSONValue?, _ n: Int = 200) -> String {
            guard let v, v != .null else { return "" }
            return StudySheets.u16prefix(YamlJS.string(v).trimmed, n)
        }
        func pick(_ a: String, _ b: String) -> JSONValue? { o[a] ?? o[b] }
        func int(_ v: JSONValue?) -> Int? {
            let x = jsNumber(v)
            return x.isFinite && x > 0 && x < 10000 ? Int(x.rounded(.toNearestOrAwayFromZero)) : nil
        }
        var p = Proposal()
        var units: [(code: String, section: String)] = []
        for u in o["units"]?.array ?? [] {
            if case .string(let s) = u { units.append((s, "")) }
            else { units.append((str(u["code"], 8).uppercased(), str(u["section"], 60))) }
        }
        units = Array(units.filter { RX.test(code, $0.code) }.prefix(16))
        var codes = OrderedSet()
        for u in units { codes.add(u.code) }
        p.codes = codes.items
        for u in units {
            if let i = p.sections.firstIndex(where: { $0.name == u.section }) { if !p.sections[i].codes.contains(u.code) { p.sections[i].codes.append(u.code) } }
            else { p.sections.append(Section(name: u.section, codes: [u.code])) }
        }
        let roleIn = YamlJS.truthy(o["role"]) ? YamlJS.string(o["role"]).lowercased() : ""
        p.role = roleIn == "markscheme" ? "ms" : roleIn == "both" || roleIn == "paper" ? "paper" : StudySheets.fileRole(fileName)
        let k = YamlJS.truthy(o["kind"]) ? YamlJS.string(o["kind"]).lowercased() : ""
        p.kind = kinds.contains(k) ? k : "other"
        let lv = o["level"]?.string ?? ""
        p.level = ["HL", "SL", "SL & HL"].contains(lv) ? lv : ""
        p.marks = int(o["marks"]); p.minutes = int(o["minutes"]); p.pages = int(o["pages"])
        let era = o["era"]?.string
        p.era = era == "2025" || era == "pre-2025" ? era : nil
        let hasMs = o["hasMarkscheme"]?.bool
        p.ms = roleIn == "markscheme" ? "only" : roleIn == "both" || hasMs == true ? "with" : hasMs == false ? "none" : "with"
        // where: Claude's folder when it is one that is there; with units in different folders, Multi-Topic Papers
        let groups = model?.groups.map { StudySheets.relIn(root, $0.path) } ?? []
        let said = StudySheets.safePath(replaceOnce(str(pick("unitFolder", "unit_folder"), 200), root + "/"))
        let saidLast = said.components(separatedBy: "/").last ?? said
        let saidFolder = groups.contains(said) ? said : groups.first { ($0.components(separatedBy: "/").last ?? $0) == saidLast }
        let whereTo: (folder: String?, multi: Bool) = model.map { folderFor(p.codes, $0, root: root) } ?? (folder: nil, multi: false)
        let newFolder = !said.isEmpty && model != nil && !said.contains("/") ? newUnitParent(model!, root: root) + said : said
        p.multi = whereTo.multi
        p.unitFolder = whereTo.multi ? (whereTo.folder ?? "") : saidFolder ?? whereTo.folder ?? (newFolder.isEmpty ? nil : newFolder) ?? groups.first ?? ""
        var existing: String? = str(pick("existingSheet", "existing_sheet"), 200)
        if existing == "" { existing = nil }
        if let e = existing, let m = model,
           !m.sheets.contains(where: { $0.dir && StudySheets.base($0.path) == e && $0.group.map { StudySheets.relIn(root, $0.path) } == p.unitFolder }) { existing = nil }
        p.existingSheet = existing
        var title = StudySheets.safeName(str(o["title"], 120))
        if title.isEmpty { title = StudySheets.safeName(RX.replace(#"\.[^.]+$"#, fileName.isEmpty ? "Sheet" : fileName, "")) }
        if whereTo.multi && StudySheets.codesIn(title).isEmpty { title += " (\(p.codes.joined(separator: ", ")))" }
        p.title = title
        var details = str(o["details"], 120)
        if details.isEmpty {
            details = [p.level, kindLabel[p.kind] ?? "", p.marks.map { "\($0) mk" } ?? "", p.minutes.map { "\($0) min" } ?? "", p.pages.map { "\($0) pp" } ?? ""]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            details = RX.replaceTemplate(#"^(HL|SL|SL & HL), ([A-Za-z0-9_])"#, details, "$1 $2")
        }
        p.details = details
        p.duplicates = Array((o["duplicates"]?.array ?? []).filter { YamlJS.truthy($0["path"]) }.prefix(6)).map {
            Duplicate(path: replaceOnce(YamlJS.string($0["path"]), root + "/"), why: str($0["why"]))
        }
        p.unitIsNew = model != nil && !groups.contains(p.unitFolder)
        p.summary = str(o["summary"], 300)
        var fname = StudySheets.safeName(str(pick("fileName", "file_name"), 150))
        if fname.isEmpty { fname = fileName.isEmpty ? "sheet.pdf" : fileName }
        p.fileName = StudySheets.fileNameFor(fname, role: p.role)
        p.notes = str(o["notes"], 600)
        p.unsure = o["unsure"]?.bool == true
        p.reason = str(o["reason"], 300)
        return .ok(p)
    }

    /// The first occurrence of `what` taken out (JavaScript's string replace).
    static func replaceOnce(_ s: String, _ what: String) -> String {
        guard !what.isEmpty, let r = s.range(of: what) else { return s }
        return s.replacingCharacters(in: r, with: "")
    }

    /// JavaScript's Number(v).
    static func jsNumber(_ v: JSONValue?) -> Double {
        switch v {
        case nil: return .nan
        case .null?: return 0
        case .bool(let b)?: return b ? 1 : 0
        case .number(let n)?: return n
        case .string(let s)?:
            let t = s.trimmed
            if t.isEmpty { return 0 }
            if RX.test("^0[xX][0-9a-fA-F]+$", t) { return Double(Int(t.dropFirst(2), radix: 16) ?? 0) }
            if RX.test(#"^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$"#, t) { return Double(t) ?? .nan }
            if t == "Infinity" || t == "+Infinity" { return .infinity }
            if t == "-Infinity" { return -.infinity }
            return .nan
        case .array(let a)?: return a.isEmpty ? 0 : a.count == 1 ? jsNumber(.string(YamlJS.string(a[0]))) : .nan
        case .object?: return .nan
        }
    }

    /// A reply's fenced or bare JSON object.
    public static func answerFromText(_ text: String) -> JSONValue? {
        let m = RX.groups("```(?:json)?\\s*([\\s\\S]*?)```", text) ?? RX.groups(#"(\{[\s\S]*\})"#, text)
        return try? JSONValue.parse(m.flatMap { $0[1] } ?? text)
    }

    // MARK: pictures of pages

    /// The pictures for one call (each call stands alone): pages 1, 2 and the last always, and `extra` pages Claude has not seen yet.
    /// [] when extra pages are asked for and there are none left.
    public static func picturePages(_ n: Int, sent: [Int] = [], extra: Int = 0) -> [Int] {
        var base: [Int] = []
        for p in [1, 2, n] where p >= 1 && p <= n && !base.contains(p) { base.append(p) }
        let more = n < 1 ? [] : Array((1...n).filter { !base.contains($0) && !sent.contains($0) }.prefix(extra))
        if extra > 0 && more.isEmpty && base.allSatisfy({ sent.contains($0) }) { return [] }
        return (base + more).sorted()
    }
    public static func nextImagePages(_ n: Int, sent: [Int] = [], k: Int = 3) -> [Int] {
        var order: [Int] = []
        for p in [1, 2, n] + (n < 1 ? [] : Array(1...n)) where p >= 1 && p <= n && !order.contains(p) { order.append(p) }
        return Array(order.filter { !sent.contains($0) }.prefix(k))
    }
}

/// study/sheets.yaml: what the user confirmed about a filed sheet (its notes by file, its units), keyed by its path in the sheets folder.
public enum SheetIndex {
    public struct Entry: Equatable, Sendable {
        /// file name -> note ("" for a note of no file in particular).
        public var notes: [(String, String)]
        public var units: [String]
        public var filed: String
        public init(notes: [(String, String)] = [], units: [String] = [], filed: String = "") { self.notes = notes; self.units = units; self.filed = filed }
        public static func == (a: Entry, b: Entry) -> Bool { a.units == b.units && a.filed == b.filed && a.notes.map { $0.0 + "\u{0}" + $0.1 } == b.notes.map { $0.0 + "\u{0}" + $0.1 } }
        func note(_ f: String) -> String? { notes.first { $0.0 == f }?.1 }
    }

    static func notesMap(_ v: JSONValue?) -> [(String, String)] {
        func s(_ x: JSONValue?) -> String { guard let x, x != .null else { return "" }; return StudySheets.u16prefix(YamlJS.string(x).trimmed, 600) }
        if case .object(let o)? = v { return o.map { ($0.0, s($0.1)) }.filter { !$0.1.isEmpty } }
        let t = s(v)
        return t.isEmpty ? [] : [("", t)]
    }

    /// nil when the file is there but does not parse (the caller keeps it aside before writing); [:] for no file.
    public static func parseStrict(_ text: String?) -> [String: Entry]? {
        guard let text, !text.trimmed.isEmpty else { return [:] }
        let o: JSONValue?
        do { o = try YamlJS.parseThrowing(text) } catch { return nil }
        if let o, o != .null {
            guard case .object = o else { return nil }
            if let sh = o["sheets"], sh != .null { guard case .object = sh else { return nil } }
        }
        var out: [String: Entry] = [:]
        for (k, v) in o?["sheets"]?.object ?? [] {
            switch v {
            case .object, .array:
                out[k] = Entry(notes: notesMap(v["notes"]), units: (v["units"]?.array ?? []).map { YamlJS.string($0) }.filter { RX.test(StudyUpload.code, $0) },
                               filed: StudySheets.u16prefix(v["filed"].map { $0 == .null ? "" : YamlJS.string($0) }?.trimmed ?? "", 10))
            default: continue
            }
        }
        return out
    }
    public static func parse(_ text: String?) -> [String: Entry] { parseStrict(text) ?? [:] }

    public static func serialize(_ idx: [String: Entry]) -> String {
        var lines = ["# Written by Nexus (Study › Upload a sheet): what you confirmed about each filed sheet (notes by file), by its path in the sheets folder."]
        var body: [String] = []
        for k in idx.keys.sorted(by: jsLess) {
            let v = idx[k]!
            var e: [String] = []
            let nm = v.notes.filter { !$0.1.isEmpty }
            if !nm.isEmpty { e.append("    notes:"); for (f, t) in nm { e.append("      \(scalar(f)): \(scalar(t))") } }
            if !v.units.isEmpty { e.append("    units:"); for u in v.units { e.append("      - \(scalar(u))") } }
            if !v.filed.isEmpty { e.append("    filed: \(scalar(v.filed))") }
            if !e.isEmpty { body.append("  \(scalar(k)):"); body += e }
        }
        lines.append(body.isEmpty ? "sheets: {}" : "sheets:")
        return (lines + body).joined(separator: "\n") + "\n"
    }

    /// A YAML scalar: plain when that reads back as the same string, else double-quoted.
    static func scalar(_ s: String) -> String {
        let plainOK = !s.isEmpty && !s.contains("\n") && !s.contains(": ") && !s.contains(" #") && !s.hasSuffix(":") && s.trimmed == s
            && !RX.test("^[-?:,\\[\\]{}#&*!|>'\"%@`]", s) && !s.hasPrefix("- ")
            && { if case .string = YamlJS.plain(s) { return true }; return false }()
            && !s.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
        return plainOK ? s : JSONValue.string(s).text
    }

    /// One more file filed into a sheet: its note joins the others under its own name.
    public static func merge(_ prev: Entry?, file: String, notes: String, units: [String], filed: String) -> Entry {
        var nm = prev?.notes.filter { !$0.1.isEmpty } ?? []
        if !notes.isEmpty {
            if let i = nm.firstIndex(where: { $0.0 == file }) { nm[i].1 = notes } else { nm.append((file, notes)) }
        }
        var u = OrderedSet()
        for c in (prev?.units ?? []) + units { u.add(c) }
        return Entry(notes: nm, units: u.items, filed: !filed.isEmpty ? filed : prev?.filed ?? "")
    }

    /// The notes as one text for the sheet's row: "paper.pdf: …" per file when there are two or more.
    public static func notesText(_ notes: [(String, String)]) -> String {
        let e = notes.filter { !$0.1.isEmpty }
        return e.count == 1 ? e[0].1 : e.map { $0.0.isEmpty ? $0.1 : "\($0.0): \($0.1)" }.joined(separator: "\n")
    }
}
