import SwiftUI
import PDFKit
import NexusCore

/// The question bank of each subject with a study folder, as the laptop's new app has it (nexus `desktop/backend/src/bank.rs`): the
/// papers (the sheets' PDFs, and the boards with questions marked on them) and their questions as the laptop sorted them, from
/// `study/questions.yaml`, with the marks, pins and bookmarks of `study/question-marks.yaml`. Sorting stays on the laptop (the
/// decision model runs there or on the G14); everything else is here: marks, Working on, Keep my place, a fix to a sort, Mark as
/// question on a board, and how much is written on each question, read from the papers' boards (never stored).
@Observable
final class BankLibrary {
    static let shared = BankLibrary()

    /// A paper as the bank lists it.
    struct Paper: Identifiable, Equatable {
        var path: String
        var title: String
        var unit: String?
        var markscheme: String?
        var isClass: Bool
        var facts: JSONValue
        var sorted: Bool
        var questions: Int
        var done: Int
        var written = 0
        var boards: [String] = []
        var pinned: Bool
        var bookmark: String?
        var lastWritten: String?
        var id: String { path }
        var isPdf: Bool { path.lowercased().hasSuffix(".pdf") }
        static func == (a: Paper, b: Paper) -> Bool {
            a.path == b.path && a.title == b.title && a.sorted == b.sorted && a.questions == b.questions && a.done == b.done && a.written == b.written
                && a.boards == b.boards && a.pinned == b.pinned && a.bookmark == b.bookmark && a.lastWritten == b.lastWritten && a.facts == b.facts
        }
    }

    /// Where a question is on a board, and how much is written there.
    struct Place: Equatable {
        var board: String
        var rects: [[Double]]
        var strokes: Int
        var last: Double
    }

    struct Bank {
        var id: String
        var folder: String
        var questions = QuestionBank.Questions()
        var marks = QuestionBank.Marks()
        /// The files don't read as Nexus writes them: shown as far as they read, never written over here.
        var questionsBroken = false
        var marksBroken = false
        var papers: [Paper] = []
        /// Each question's place on its board, by "<paper>#<q>" (filled in the background).
        var places: [String: Place] = [:]
        var units: [(code: String, title: String)] = []
    }

    private(set) var banks: [String: Bank] = [:]
    /// A save that could not be made, for the screen to show.
    var problem: String?
    /// The question a board was opened from (Write on it): Study goes back to it when the board closes.
    var returnTo: (workstream: String, target: BankTarget)?
    @ObservationIgnored private var stamps: [String: String] = [:]
    @ObservationIgnored private var inkRun: [String: Int] = [:]

    func bank(_ id: String) -> Bank? { banks[id] }

    // MARK: reading

    /// Reads a subject's bank again when its files or sheets changed, then how much is written, in the background.
    func refresh(_ s: StudyLibrary.Study, root: URL, force: Bool = false) {
        let folder = s.workstream.folder
        let qURL = root.appendingPathComponent(String(folder) + "/" + QuestionBank.questionsFile)
        let mURL = root.appendingPathComponent(String(folder) + "/" + QuestionBank.marksFile)
        let stamp = [Self.stamp(qURL), Self.stamp(mURL), String(s.sheets.sheets.count), s.sheets.sheets.map(\.id).joined(separator: "|")].joined(separator: "#")
        if !force, stamps[s.id] == stamp, banks[s.id] != nil { return }
        stamps[s.id] = stamp
        var b = banks[s.id] ?? Bank(id: s.id, folder: String(folder))
        b.folder = String(folder)
        let qText = FileManager.default.fileExists(atPath: qURL.path) ? try? FolderAccess.read(qURL) : nil
        let mText = FileManager.default.fileExists(atPath: mURL.path) ? try? FolderAccess.read(mURL) : nil
        if let q = QuestionBank.Questions.parse(qText) { b.questions = q; b.questionsBroken = false } else { b.questionsBroken = true }
        if let m = QuestionBank.Marks.parse(mText) { b.marks = m; b.marksBroken = false } else { b.marksBroken = true }
        b.units = (s.units ?? []).map { ($0.code, $0.title) }
        b.papers = Self.papers(s, b)
        banks[s.id] = b
        countInk(s.id, root: root)
    }

    private static func stamp(_ u: URL) -> String {
        let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return "\(v?.fileSize ?? -1):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    /// The subject's papers: each paper PDF of the sheets folder, then each board with questions marked on it.
    private static func papers(_ s: StudyLibrary.Study, _ b: Bank) -> [Paper] {
        var out: [Paper] = []
        let old = Dictionary(b.papers.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        func make(_ path: String, title: String, unit: String?, ms: String?) -> Paper {
            let p = b.questions[path]
            let qs = p?.questions.keys ?? []
            let done = qs.filter { b.marks.mark(path, $0) == "done" }.count
            var r = Paper(path: path, title: title, unit: unit, markscheme: ms, isClass: p?.isClass ?? false, facts: p?.facts.value ?? .object([]),
                          sorted: !qs.isEmpty, questions: qs.count, done: done, pinned: b.marks.pinned(path), bookmark: b.marks.bookmark(path))
            if let o = old[path] { r.written = o.written; r.boards = o.boards; r.lastWritten = o.lastWritten }
            return r
        }
        for sh in s.sheets.sheets {
            for f in sh.files where f.role == "paper" && f.path.lowercased().hasSuffix(".pdf") {
                out.append(make(f.path, title: sh.title, unit: sh.group?.label, ms: sh.files.first { $0.role == "ms" }?.path))
            }
        }
        for p in b.questions.papers where !out.contains(where: { $0.path == p.path }) {
            out.append(make(p.path, title: QuestionBank.boardName(p.path), unit: nil, ms: nil))
        }
        return out
    }

    /// Every question of the bank, in the paper's order, with its mark and how much is written.
    func rows(_ id: String, _ f: QuestionBank.Filter, recent: Bool = false) -> [QuestionBank.Row] {
        guard let b = banks[id] else { return [] }
        var out: [QuestionBank.Row] = []
        for p in b.papers where f.paper.isEmpty || f.paper == p.path {
            guard let sp = b.questions[p.path] else { continue }
            for q in sp.questions.keys {
                guard let v = sp.merged(q) else { continue }
                let place = b.places[p.path + "#" + q]
                let r = QuestionBank.Row(
                    paper: p.path, q: q, title: p.title, isClass: p.isClass, facts: sp.facts.value, sort: v,
                    mark: b.marks.mark(p.path, q), markedAt: b.marks.markedAt(p.path, q),
                    written: QuestionBank.writtenWord(place?.strokes ?? 0, marks: v["marks"]?.number.map { Int($0) }),
                    strokes: place?.strokes ?? 0, lastWritten: place.flatMap { Self.day($0.last) }, board: place?.board,
                    pinned: p.pinned, bookmark: p.bookmark == q)
                if QuestionBank.keep(r, f) { out.append(r) }
            }
        }
        return QuestionBank.ordered(out, recent: recent)
    }

    static func day(_ seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date(timeIntervalSince1970: seconds))
    }

    // MARK: how much is written (the boards)

    /// Reads each paper's boards and the ink in each question's place, off the main thread.
    private func countInk(_ id: String, root: URL) {
        guard let b = banks[id] else { return }
        let run = (inkRun[id] ?? 0) + 1
        inkRun[id] = run
        let papers = b.papers.filter(\.sorted), questions = b.questions
        let subject = id, folder = b.folder
        Task.detached(priority: .utility) {
            let notebooks = BankBoards.subjectNotebooks(root: root, subject: subject)
            var places: [String: Place] = [:]
            var boardsOf: [String: [String]] = [:]
            for p in papers {
                guard let sp = questions[p.path] else { continue }
                let boards = p.isPdf ? BankBoards.boardsWith(root: root, pdf: p.path, notebooks: notebooks, folder: folder) : [p.path]
                boardsOf[p.path] = boards
                for (q, place) in BankBoards.places(root: root, paper: p.path, sp: sp, boards: boards) { places[p.path + "#" + q] = place }
            }
            await MainActor.run {
                guard self.inkRun[id] == run, var b = self.banks[id] else { return }
                b.places = places
                for i in b.papers.indices {
                    let path = b.papers[i].path
                    guard let sp = b.questions[path] else { continue }
                    b.papers[i].boards = boardsOf[path] ?? b.papers[i].boards
                    let mine = sp.questions.keys.compactMap { places[path + "#" + $0] }
                    b.papers[i].written = mine.filter { $0.strokes > 0 }.count
                    b.papers[i].lastWritten = Self.day(mine.map(\.last).max() ?? 0)
                }
                self.banks[id] = b
            }
        }
    }

    // MARK: writing

    func canWrite(_ store: NexusStore) -> Bool { store.snapshot.isDataFolder && store.snapshot.readOnlyReason == nil }

    /// Reads the marks file from disk, changes it and writes it (so a change from the laptop meanwhile is kept).
    private func changeMarks(_ store: NexusStore, _ id: String, _ f: (inout QuestionBank.Marks) -> Void) {
        guard canWrite(store), let b = banks[id] else { return }
        let url = store.folder.appendingPathComponent(b.folder + "/" + QuestionBank.marksFile)
        let text = FileManager.default.fileExists(atPath: url.path) ? try? FolderAccess.read(url) : nil
        guard var m = QuestionBank.Marks.parse(text) else {
            problem = "study/question-marks.yaml isn't in the form Nexus writes, so it isn't changed here. Fix it on the laptop."
            return
        }
        f(&m)
        do {
            try FolderAccess.write(url, m.text)
            banks[id]?.marks = m
            if let nb = banks[id] { banks[id]?.papers = Self.repaper(nb) }
            stamps[id] = nil
            store.didWrite(touched: [b.folder + "/" + QuestionBank.marksFile])
        } catch {
            problem = "Couldn't save your mark: \(error.localizedDescription)"
        }
    }

    /// The same, for questions.yaml. Returns false when it couldn't be written.
    @discardableResult
    private func changeQuestions(_ store: NexusStore, _ id: String, _ f: (inout QuestionBank.Questions) throws -> Void) -> Bool {
        guard canWrite(store), let b = banks[id] else { return false }
        let url = store.folder.appendingPathComponent(b.folder + "/" + QuestionBank.questionsFile)
        let text = FileManager.default.fileExists(atPath: url.path) ? try? FolderAccess.read(url) : nil
        guard var q = QuestionBank.Questions.parse(text) else {
            problem = "study/questions.yaml isn't in the form Nexus writes, so it isn't changed here. Fix it on the laptop."
            return false
        }
        do {
            try f(&q)
            try FolderAccess.write(url, q.text)
            banks[id]?.questions = q
            if let nb = banks[id] { banks[id]?.papers = Self.repaper(nb) }
            stamps[id] = nil
            store.didWrite(touched: [b.folder + "/" + QuestionBank.questionsFile])
            return true
        } catch {
            problem = "Couldn't save the question bank: \(error)"
            return false
        }
    }

    /// The papers' counts again after a change (titles and places kept).
    private static func repaper(_ b: Bank) -> [Paper] {
        var out = b.papers
        for i in out.indices {
            let path = out[i].path
            let qs = b.questions[path]?.questions.keys ?? []
            out[i].sorted = !qs.isEmpty
            out[i].questions = qs.count
            out[i].done = qs.filter { b.marks.mark(path, $0) == "done" }.count
            out[i].pinned = b.marks.pinned(path)
            out[i].bookmark = b.marks.bookmark(path)
            out[i].facts = b.questions[path]?.facts.value ?? out[i].facts
            out[i].isClass = b.questions[path]?.isClass ?? out[i].isClass
        }
        for p in b.questions.papers where !out.contains(where: { $0.path == p.path }) {
            out.append(Paper(path: p.path, title: QuestionBank.boardName(p.path), unit: nil, markscheme: nil, isClass: p.isClass, facts: p.facts.value,
                             sorted: !p.questions.isEmpty, questions: p.questions.items.count, done: 0, pinned: b.marks.pinned(p.path), bookmark: b.marks.bookmark(p.path)))
        }
        return out
    }

    /// Done, Hard or Review later (the same one again takes it back).
    func mark(_ store: NexusStore, _ id: String, paper: String, q: String, _ mark: String) {
        let now = banks[id]?.marks.mark(paper, q)
        changeMarks(store, id) { $0.setMark(paper, q, now == mark ? nil : mark, today: Days.today()) }
    }

    func pin(_ store: NexusStore, _ id: String, paper: String, on: Bool) {
        changeMarks(store, id) { $0.setPin(paper, on, today: Days.today()) }
    }

    func bookmark(_ store: NexusStore, _ id: String, paper: String, q: String?) {
        changeMarks(store, id) { $0.setBookmark(paper, q) }
    }

    /// A hand change to a question's unit or type (kept under `mine`; nil takes it back).
    func fix(_ store: NexusStore, _ id: String, paper: String, q: String, _ set: [(String, JSONValue?)]) {
        changeQuestions(store, id) { qs in
            guard var p = qs[paper] else { return }
            try QuestionBank.fix(&p, q, set)
            qs[paper] = p
        }
    }

    /// Mark as question (from a board): the box becomes the board's next question. Returns its key, or nil when it couldn't be saved.
    func addMarked(_ store: NexusStore, _ id: String, board: String, rect: [Double], words: String) -> String? {
        let source = (try? FolderAccess.read(store.folder.appendingPathComponent(board + "/board.json"))).flatMap { try? JSONValue.parse($0) }?["source"]
        var key: String?
        let ok = changeQuestions(store, id) { qs in
            key = QuestionBank.addMarked(&qs, board: board, rect: rect.map { ($0 * 10).rounded() / 10 }, label: nil, words: words, source: source, today: Days.today())
        }
        return ok ? key : nil
    }
}

/// The boards side of the bank: which boards hold a paper, where its questions are on them, and the ink there. Runs off the main
/// thread (PDFKit for the page sizes, the tiles read from disk).
enum BankBoards {
    /// The top-level notebooks filed under a subject by their notebook.json (`"subject": "<id>"`), as the laptop files them.
    static func subjectNotebooks(root: URL, subject: String) -> [(path: String, subject: String?)] {
        let dir = root.appendingPathComponent("notebooks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().compactMap { n -> (path: String, subject: String?)? in
            var isDir: ObjCBool = false
            guard !n.hasPrefix("."), FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let meta = (try? String(contentsOf: dir.appendingPathComponent(n + "/notebook.json"), encoding: .utf8)).flatMap { try? JSONValue.parse($0) }
            return ("notebooks/" + n, meta?["subject"]?.string)
        }
    }

    /// The boards that hold a PDF as a printout: its Papers board, the old board beside it, and the boards under the subject's
    /// notebooks' Papers folders (the laptop also looks through every board of the subject's notebooks; here that would read
    /// thousands of tiles, so a paper put on some other board isn't counted on the iPad).
    static func boardsWith(root: URL, pdf: String, notebooks: [(path: String, subject: String?)], folder: String) -> [String] {
        let name = (pdf as NSString).lastPathComponent
        var candidates: [String] = []
        for nb in notebooks where nb.subject != nil {
            candidates += boards(under: root, nb.path + "/Papers")
        }
        candidates.append(QuestionBank.besideBoard(pdf))
        var out: [String] = []
        for b in candidates where !out.contains(b) {
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(b + "/board.json").path) else { continue }
            let tiles = root.appendingPathComponent(b + "/tiles")
            let files = (try? FileManager.default.contentsOfDirectory(atPath: tiles.path)) ?? []
            let has = files.contains { f in f.hasSuffix(".json") && ((try? String(contentsOf: tiles.appendingPathComponent(f), encoding: .utf8))?.contains(name) ?? false) }
            guard has else { continue }
            if pdfItems(root: root, board: b).contains(where: { QuestionBank.resolveIn(board: b, $0.string("src") ?? "") == pdf }) { out.append(b) }
        }
        return out
    }

    /// Every board folder under a folder (any depth, not inside a board).
    static func boards(under root: URL, _ rel: String) -> [String] {
        var out: [String] = []
        func walk(_ r: String, _ depth: Int) {
            guard depth < 6, let names = try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(r).path) else { return }
            for n in names.sorted() where !n.hasPrefix(".") {
                let p = r + "/" + n
                if n.hasSuffix(".board") { out.append(p); continue }
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: root.appendingPathComponent(p).path, isDirectory: &isDir), isDir.boolValue { walk(p, depth + 1) }
            }
        }
        walk(rel, 0)
        return out
    }

    /// A board's tiles: their strokes, items and when each was saved.
    static func tiles(root: URL, board: String) -> [(strokes: [BoardStroke], items: [BoardItem], when: Double)] {
        let dir = root.appendingPathComponent(board + "/tiles")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".json") }.compactMap { f in
            let u = dir.appendingPathComponent(f)
            guard let t = try? String(contentsOf: u, encoding: .utf8), let parsed = try? BoardFiles.parseTile(t) else { return nil }
            let when = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate?.timeIntervalSince1970 ?? 0
            return (parsed.strokes, parsed.items, when)
        }
    }

    static func pdfItems(root: URL, board: String) -> [BoardItem] {
        tiles(root: root, board: board).flatMap { $0.items.filter { $0.type == "pdf" } }
    }

    /// Each page's size (points, rotation applied), as the board lays a printout's pages out.
    static func pageSizes(_ url: URL) -> [(w: Double, h: Double)] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map { i in
            // as PdfPrintout.displaySize: the media box, turned when the page is
            guard let page = doc.page(at: i) else { return (612, 792) }
            let box = page.bounds(for: .mediaBox)
            return page.rotation % 180 == 0 ? (Double(box.width), Double(box.height)) : (Double(box.height), Double(box.width))
        }
    }

    /// The ink on a board, for counting.
    static func ink(_ tiles: [(strokes: [BoardStroke], items: [BoardItem], when: Double)]) -> QuestionBank.Ink {
        var ink = QuestionBank.Ink()
        for t in tiles {
            for s in t.strokes { if let b = QuestionBank.box(s) { ink.strokes.append((b, t.when)) } }
            for it in t.items where it.type == "text" {
                ink.texts.append([it.x, it.y, it.x + (it.w ?? 400), it.y + (it.number("h") ?? 60)])
            }
        }
        return ink
    }

    /// Each question's place on the first board that holds the paper with ink there, else the first board.
    static func places(root: URL, paper: String, sp: QuestionBank.Paper, boards: [String]) -> [String: BankLibrary.Place] {
        var out: [String: BankLibrary.Place] = [:]
        if !paper.lowercased().hasSuffix(".pdf") {
            let ink = ink(tiles(root: root, board: paper))
            for q in sp.questions.keys {
                guard let v = sp.questions[q], let r = QuestionBank.rect(v) else { continue }
                let got = QuestionBank.inkIn(ink, [r])
                out[q] = .init(board: paper, rects: [r], strokes: got.strokes, last: got.last)
            }
            return out
        }
        let sizes = pageSizes(root.appendingPathComponent(paper))
        guard !sizes.isEmpty else { return out }
        for b in boards {
            let t = tiles(root: root, board: b)
            let segs = t.flatMap { $0.items }.filter { $0.type == "pdf" && QuestionBank.resolveIn(board: b, $0.string("src") ?? "") == paper }
                .flatMap { BoardFiles.pdfSegments($0, sizes: sizes) }
            guard !segs.isEmpty else { continue }
            let ink = ink(t)
            for q in sp.questions.keys {
                guard let v = sp.questions[q], let rects = QuestionBank.place(v, segs: segs), !rects.isEmpty else { continue }
                let got = QuestionBank.inkIn(ink, rects)
                if let old = out[q], !(old.strokes == 0 && got.strokes > 0) { continue }
                out[q] = .init(board: b, rects: rects, strokes: got.strokes, last: got.last)
            }
        }
        return out
    }
}

/// A PDF's words for the bank: its lines (PDFKit's, as the laptop reads PDFium's), the questions found in them, and where a question's
/// answer is in its markscheme.
enum BankPdf {
    static func lines(_ url: URL) -> [[QuestionFinder.Line]] {
        guard let doc = PDFDocument(url: url) else { return [] }
        return (0..<doc.pageCount).map { i in
            guard let page = doc.page(at: i) else { return [] }
            let box = page.bounds(for: .mediaBox)
            guard box.width > 0, box.height > 0, let sel = page.selection(for: box) else { return [] }
            let lines = sel.selectionsByLine().compactMap { l -> QuestionFinder.Line? in
                let t = (l.string ?? "").trimmingCharacters(in: .newlines)
                guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                let b = l.bounds(for: page)
                return QuestionFinder.Line(x: Double((b.minX - box.minX) / box.width), y: Double((box.maxY - b.maxY) / box.height), text: t)
            }
            // top to bottom (PDFKit keeps the content's order, which a two-part line can break)
            return lines.enumerated().sorted { a, b in abs(a.element.y - b.element.y) > 0.004 ? a.element.y < b.element.y : a.offset < b.offset }.map(\.element)
        }
    }

    /// Where question `q`'s answer is: a page and how far down it, in the markscheme at the end of the paper or in its own PDF.
    struct Spot: Equatable { var path: String; var q: String?; var page: Int; var y: Double }

    static func markschemeSpot(root: URL, paper: String, q: String, markscheme: String?) -> Spot? {
        let pages = lines(root.appendingPathComponent(paper))
        let (qs, inside) = QuestionFinder.split(pages)
        let me = qs.first { $0.key == q }
        if let inside {
            guard let me, let m = QuestionFinder.matching(me, in: inside) else { return inside.first.map { Spot(path: paper, q: nil, page: $0.from.page, y: 0) } }
            return Spot(path: paper, q: m.key, page: m.from.page, y: m.from.y)
        }
        guard let ms = markscheme else { return nil }
        let spots = QuestionFinder.runs(lines(root.appendingPathComponent(ms))).flatMap { $0 }
        guard let me, let m = QuestionFinder.matching(me, in: spots) else { return Spot(path: ms, q: nil, page: 0, y: 0) }
        return Spot(path: ms, q: m.key, page: m.from.page, y: m.from.y)
    }

    /// The words under a box on a board, read off the printouts it is over (Mark as question).
    static func words(root: URL, board: String, items: [BoardItem], rect: CGRect) -> String {
        var out = ""
        for it in items where it.type == "pdf" {
            guard let src = QuestionBank.resolveIn(board: board, it.string("src") ?? "") else { continue }
            let url = root.appendingPathComponent(src)
            let sizes = BankBoards.pageSizes(url)
            guard !sizes.isEmpty else { continue }
            var pages: [[QuestionFinder.Line]]?
            for g in BoardFiles.pdfSegments(it, sizes: sizes) {
                let lo = max(Double(rect.minY), g.y), hi = min(Double(rect.maxY), g.y + g.h)
                if hi <= lo || Double(rect.maxX) < g.x || Double(rect.minX) > g.x + g.w { continue }
                if pages == nil { pages = lines(url) }
                let f = { (y: Double) in g.top + (y - g.y) / max(g.h, 1e-9) * (g.bottom - g.top) }
                out += QuestionFinder.regionText(pages ?? [], from: .init(page: g.page, y: f(lo)), to: .init(page: g.page, y: f(hi))) + "\n"
            }
        }
        return out
    }
}
