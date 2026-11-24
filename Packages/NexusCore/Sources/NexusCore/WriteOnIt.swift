import Foundation

/// Write on it: the board that goes with a PDF, where a new one goes, and the markscheme beside a paper, as the laptop has them
/// (nexus desktop/backend/src/board.rs `board_for` and `writeOnIt`, bank.rs `papers_board`, sheets.rs `markscheme_for`), so both
/// devices find and make the same board. Paths are data-folder paths with "/".
///
/// A paper in a subject's sheets folder gets its board in the subject's notebook, Papers › its unit folder, named after the paper
/// ("notebooks/Chemistry/Papers/05 Reactivity 1/Redox test.board"); the PDF stays where it is. Any other PDF keeps the old board
/// beside it ("a/Paper 1.board"). A board already made is found first: the Papers board, then any board of the subject holding the
/// PDF as a printout, then the one beside it.
public enum WriteOnIt {
    /// What the data folder says about subjects: each top-level notebook's subject (`notebook.json`), the workstreams' folders and
    /// names, and each study's sheets folder.
    public struct Subjects: Sendable {
        /// "notebooks/Chemistry" -> "chem-hl"
        public var notebooks: [String: String]
        /// id -> (folder "classes/chem-hl", name "Chemistry HL")
        public var workstreams: [String: (folder: String, name: String)]
        /// id -> "classes/chem-hl/files"
        public var sheets: [String: String]
        public init(notebooks: [String: String] = [:], workstreams: [String: (folder: String, name: String)] = [:], sheets: [String: String] = [:]) {
            self.notebooks = notebooks; self.workstreams = workstreams; self.sheets = sheets
        }
    }

    /// The old board beside a PDF ("a/Paper 1.pdf" -> "a/Paper 1.board").
    public static func besideBoard(_ pdf: String) -> String {
        let (dir, name) = split(pdf)
        return (dir.isEmpty ? "" : dir + "/") + stem(name) + ".board"
    }

    /// The subject a path belongs to: its notebook's subject, else the workstream whose folder holds it (the deepest).
    public static func subject(of path: String, _ s: Subjects) -> String? {
        if path.hasPrefix("notebooks/") {
            let nb = path.split(separator: "/", omittingEmptySubsequences: false).prefix(2).joined(separator: "/")
            return s.notebooks[nb]
        }
        return s.workstreams.filter { !$0.value.folder.isEmpty && (path == $0.value.folder || path.hasPrefix($0.value.folder + "/")) }
            .max { $0.value.folder.utf8.count < $1.value.folder.utf8.count }?.key
    }

    /// The notebooks filed under a subject, by path.
    public static func notebooks(of id: String, _ s: Subjects) -> [String] {
        s.notebooks.filter { $0.value == id }.map(\.key).sorted(by: before)
    }

    /// Where a paper's board goes when it is first written on, or nil when the PDF belongs to no subject.
    public static func papersBoard(_ pdf: String, _ s: Subjects) -> String? {
        guard let id = subject(of: pdf, s), let ws = s.workstreams[id] else { return nil }
        let nb = notebooks(of: id, s).first ?? "notebooks/" + ws.name
        let (dir, name) = split(pdf)
        // the folders between the sheets folder and the paper: the first is its unit
        var unit = ""
        if let root = s.sheets[id].map(trimSlashes), !root.isEmpty, pdf.hasPrefix(root + "/") {
            let within = String(dir.dropFirst(min(dir.count, root.count + 1)))
            unit = dir == root ? "" : String(within.split(separator: "/", omittingEmptySubsequences: false).first ?? "")
        }
        return unit.isEmpty ? "\(nb)/Papers/\(stem(name)).board" : "\(nb)/Papers/\(unit)/\(stem(name)).board"
    }

    /// Where a new board for this PDF goes, and the subject whose notebook it goes in (its notebook.json may need writing).
    public static func newBoard(_ pdf: String, _ s: Subjects) -> (board: String, subject: String?) {
        if let r = papersBoard(pdf, s) { return (r, subject(of: pdf, s)) }
        return (besideBoard(pdf), nil)
    }

    /// The board already made for this PDF: the Papers board, then the first of `holding` (the subject's boards whose printout is
    /// this PDF, `holds`), then the old one beside it. `exists` says whether a board folder is there.
    public static func existingBoard(_ pdf: String, _ s: Subjects, holding: [String] = [], exists: (String) -> Bool) -> String? {
        if let r = papersBoard(pdf, s), exists(r) { return r }
        if let b = holding.first { return b }
        let beside = besideBoard(pdf)
        return exists(beside) ? beside : nil
    }

    /// The boards worth looking in for a printout of this PDF: those in the subject's notebooks and folder.
    public static func subjectBoards(_ pdf: String, _ s: Subjects, among boards: [String]) -> [String] {
        guard let id = subject(of: pdf, s) else { return [] }
        let nbs = notebooks(of: id, s), folder = s.workstreams[id]?.folder ?? ""
        return boards.filter { b in nbs.contains { b.hasPrefix($0 + "/") } || (!folder.isEmpty && b.hasPrefix(folder + "/")) }
    }

    /// Whether a board's items hold this PDF as a printout (their `src`, relative to the board).
    public static func holds(_ board: String, items: [BoardItem], pdf: String) -> Bool {
        items.contains { $0.type == "pdf" && BoardLinks.resolve(board, $0.json["src"]?.string ?? "") == pdf }
    }

    /// The printout item a new board gets: the PDF at the top left, as the laptop writes it.
    public static func printout(board: String, pdf: String) -> BoardItem {
        BoardItem(id: "pdf1", type: "pdf", x: 0, y: 0, fields: [
            ("src", .string(BoardLinks.rel(from: board, to: pdf))), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
        ])
    }

    /// The notebook.json a subject's new notebook gets.
    public static func notebookJSON(subject id: String) -> String {
        "{\"format\":\"nexus-notebook/1\",\"subject\":\(JSONValue.string(id).text)}\n"
    }

    /// The markscheme that goes with `pdf` among its folder's file names: the same stem with a markscheme's name, or, in a sheet
    /// folder ("Title — details"), the one markscheme when this is the only paper. Nil for a markscheme or a marked copy.
    public static func markscheme(for pdf: String, folderName: String, names: [String]) -> String? {
        let me = split(pdf).name
        guard StudySheets.fileRole(me) == "paper" else { return nil }
        let pdfs = names.filter { $0.lowercased().hasSuffix(".pdf") && $0 != me }
        let st = StudySheets.stemOf(me)
        if !st.isEmpty, let n = pdfs.filter({ StudySheets.fileRole($0) == "ms" && StudySheets.stemOf($0) == st }).sorted(by: before).first { return n }
        if folderName.contains("—") {
            let ms = pdfs.filter { StudySheets.fileRole($0) == "ms" }
            if ms.count == 1 && !pdfs.contains(where: { StudySheets.fileRole($0) == "paper" }) { return ms[0] }
        }
        return nil
    }

    /// The markscheme as a data-folder path, from the names in the paper's folder.
    public static func markschemePath(for pdf: String, names: [String]) -> String? {
        let (dir, _) = split(pdf)
        let folder = dir.split(separator: "/").last.map(String.init) ?? ""
        return markscheme(for: pdf, folderName: folder, names: names).map { dir.isEmpty ? $0 : dir + "/" + $0 }
    }

    // MARK: helpers

    static func split(_ p: String) -> (dir: String, name: String) {
        guard let i = p.lastIndex(of: "/") else { return ("", p) }
        return (String(p[..<i]), String(p[p.index(after: i)...]))
    }
    /// "Paper 1.pdf" -> "Paper 1" (the laptop's: up to the last dot).
    static func stem(_ name: String) -> String {
        guard let i = name.lastIndex(of: ".") else { return name }
        return String(name[..<i])
    }
    static func trimSlashes(_ s: String) -> String {
        var t = Substring(s)
        while t.hasPrefix("/") { t = t.dropFirst() }
        while t.hasSuffix("/") { t = t.dropLast() }
        return String(t)
    }
    /// Rust's string order (bytes), so both devices pick the same one.
    static func before(_ a: String, _ b: String) -> Bool { Array(a.utf8).lexicographicallyPrecedes(Array(b.utf8)) }
}
