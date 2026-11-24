import Foundation
import NexusCore

/// Write on it, from anywhere a PDF shows (a task, Next up, a Study sheet, Files, search): the PDF's board, as the laptop finds
/// and makes it (NexusCore WriteOnIt). A paper of a subject gets its board in the subject's notebook, Papers › its unit; any other
/// PDF keeps the board beside it. A board made before is opened, never a second copy.
extension NexusStore {
    /// What the data folder says about subjects: the top-level notebooks' subjects (notebook.json), the workstreams' folders and
    /// names, and the studies' sheets folders.
    func writeSubjects() -> WriteOnIt.Subjects {
        let key = "\(folder.path)|\(snapshot.loadedAt.timeIntervalSince1970)|\(notebooksVersion)|\(StudyLibrary.shared.studies.map { $0.id + $0.config.sheets }.joined(separator: ","))"
        if SubjectsCache.key == key { return SubjectsCache.value }
        var s = WriteOnIt.Subjects()
        for nb in Notebook.top(folder) {
            let meta = try? JSONValue.parse(String(decoding: (try? Data(contentsOf: folder.appendingPathComponent(nb).appendingPathComponent("notebook.json"))) ?? Data(), as: UTF8.self))
            if let id = meta?["subject"]?.string, !id.isEmpty { s.notebooks[nb] = id }
        }
        for (id, w) in snapshot.workstreams { s.workstreams[id] = (folder: w.folder, name: w.name) }
        for st in StudyLibrary.shared.studies {
            let sheets = st.config.sheets.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            s.sheets[st.id] = sheets.isEmpty ? st.workstream.folder : st.workstream.folder + "/" + sheets
        }
        SubjectsCache.key = key; SubjectsCache.value = s
        return s
    }

    private func isBoard(_ rel: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(rel).path, isDirectory: &dir) && dir.boolValue
    }

    /// The board already made for a PDF, without looking inside other boards (the Papers board or the one beside it): for a
    /// row's "Open its board".
    func madeBoard(pdf: String, _ s: WriteOnIt.Subjects? = nil) -> String? {
        WriteOnIt.existingBoard(pdf, s ?? writeSubjects(), exists: isBoard)
    }

    /// The subject's boards whose printout is this PDF: a quick look for its name in their tiles first, as the laptop's boards_with.
    static func boardsHolding(_ pdf: String, root: URL, _ s: WriteOnIt.Subjects) -> [String] {
        let name = (pdf as NSString).lastPathComponent
        let fm = FileManager.default
        let all = Notebook.list(root).flatMap { nb in nb.allBoards.map(\.board.path) }
        var out: [String] = []
        for b in WriteOnIt.subjectBoards(pdf, s, among: all) {
            let tiles = root.appendingPathComponent(b).appendingPathComponent("tiles")
            guard let files = try? fm.contentsOfDirectory(atPath: tiles.path) else { continue }
            for f in files where f.hasSuffix(".json") {
                guard let text = try? String(contentsOf: tiles.appendingPathComponent(f), encoding: .utf8), text.contains(name),
                      let t = try? BoardFiles.parseTile(text) else { continue }
                if WriteOnIt.holds(b, items: t.items, pdf: pdf) { out.append(b); break }
            }
        }
        return out
    }

    /// Write on it: find the PDF's board (looking through the subject's boards off the main thread), make it the first time, open it.
    func writeOn(pdf path: String) {
        let s = writeSubjects(), root = folder
        if let b = madeBoard(pdf: path, s), WriteOnIt.papersBoard(path, s) == b { openWritten(b); return }
        DispatchQueue.global(qos: .userInitiated).async {
            let holding = WriteOnIt.papersBoard(path, s) == nil ? [] : Self.boardsHolding(path, root: root, s)
            DispatchQueue.main.async { [self] in
                if let b = WriteOnIt.existingBoard(path, s, holding: holding, exists: isBoard) { openWritten(b); return }
                makeBoard(pdf: path, s)
            }
        }
    }

    private func makeBoard(pdf path: String, _ s: WriteOnIt.Subjects) {
        let name = (path as NSString).lastPathComponent
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path) else { problem = "There's no PDF at \(path)"; return }
        let (rel, subject) = WriteOnIt.newBoard(path, s)
        let board = folder.appendingPathComponent(rel, isDirectory: true)
        do {
            // the subject's notebook is filed under it the first time (notebook.json), as the laptop does
            if let id = subject, rel.hasPrefix(BoardFormat.notebooks + "/") {
                let nb = rel.split(separator: "/").prefix(2).joined(separator: "/")
                let meta = folder.appendingPathComponent(nb).appendingPathComponent("notebook.json")
                if !FileManager.default.fileExists(atPath: meta.path) { try FolderAccess.write(meta, WriteOnIt.notebookJSON(subject: id)) }
            }
            try FolderAccess.write(board.appendingPathComponent("board.json"), BoardFormat.boardJSON())
            var c = BoardContent()
            c.items = [WriteOnIt.printout(board: rel, pdf: path)]
            _ = try BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
            boardsChanged(listChanged: true)
        } catch {
            problem = "Couldn't make a board for \(name): \(error.localizedDescription)"
            return
        }
        openWritten(rel)
    }

    private func openWritten(_ rel: String) {
        // from the task panel: the panel goes first, then the board opens
        if openTaskId != nil {
            openTaskId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in openBoard = .init(path: rel, focus: nil) }
        } else {
            openBoard = .init(path: rel, focus: nil)
        }
    }

    /// The markscheme beside a paper (a data-folder path), paired by name as the laptop's sheets.rs.
    func markscheme(of pdf: String) -> String? {
        let dir = (pdf as NSString).deletingLastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent(dir).path) else { return nil }
        return WriteOnIt.markschemePath(for: pdf, names: names)
    }
}

/// The subjects as last read, until the folder, the notebooks or the studies change (a row of a list asks for each sheet).
private enum SubjectsCache {
    static var key = ""
    static var value = WriteOnIt.Subjects()
}
