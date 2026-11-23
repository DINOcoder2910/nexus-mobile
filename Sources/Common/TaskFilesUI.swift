import SwiftUI
import QuickLook
import NexusCore

extension NexusStore {
    /// The files a task points at (`[[links]]` in its title or note) that are in the folder: beside its list, from the top, or by
    /// name under its list's folder.
    func files(of t: NexusTask) -> [TaskFiles.File] {
        guard !TaskFiles.targets(t).isEmpty else { return [] }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        let dir = (t.file as NSString).deletingLastPathComponent
        return TaskFiles.files(t, exists: { fm.fileExists(atPath: root.appendingPathComponent($0).path) }, find: { name in
            guard let e = fm.enumerator(at: root.appendingPathComponent(dir, isDirectory: true), includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
            var seen = 0
            for case let u as URL in e {
                seen += 1
                if seen > 4000 { return nil }
                guard u.lastPathComponent == name else { continue }
                let full = u.resolvingSymlinksInPath().standardizedFileURL.path
                guard full.hasPrefix(root.path + "/") else { return nil }
                return String(full.dropFirst(root.path.count + 1))
            }
            return nil
        })
    }

    /// The board a PDF is written on, as the laptop finds it (nexus board.rs `board_for`): the paper's board in its subject's
    /// notebook (Papers › its unit folder), then a board there that holds it, then the old board beside it. Nil: none yet.
    func boardFor(pdf path: String) -> String? {
        let fm = FileManager.default
        func exists(_ b: String) -> Bool { fm.fileExists(atPath: folder.appendingPathComponent(b + "/board.json").path) }
        if let p = papersBoard(pdf: path), exists(p.board) { return p.board }
        if let w = subject(of: path) {
            let nbs = BankBoards.subjectNotebooks(root: folder, subject: w.id).filter { $0.subject == w.id }
            if let b = BankBoards.boardsWith(root: folder, pdf: path, notebooks: nbs, folder: w.folder).first { return b }
        }
        let beside = QuestionBank.besideBoard(path)
        return exists(beside) ? beside : nil
    }

    /// The workstream whose folder holds a path (the deepest).
    func subject(of path: String) -> Workstream? {
        snapshot.groups.flatMap { snapshot.workstreams(in: $0) }
            .filter { !$0.folder.isEmpty && (path == $0.folder || path.hasPrefix($0.folder + "/")) }
            .max { $0.folder.count < $1.folder.count }
    }

    /// Where a PDF of a subject gets its board: the subject's notebook › Papers › the unit folder it sits in under the sheets folder.
    func papersBoard(pdf path: String) -> (board: String, subject: Workstream)? {
        guard let w = subject(of: path) else { return nil }
        let cfg = StudyUnits.parseConfig(try? FolderAccess.read(folder.appendingPathComponent(StudyFolder.studyPath(w) + "/study.yaml")))
        let nb = QuestionBank.subjectNotebook(BankBoards.subjectNotebooks(root: folder, subject: w.id), subject: w.id, name: w.name)
        return (QuestionBank.papersBoard(pdf: path, sheetsRoot: w.folder + "/" + cfg.sheets, notebook: nb), w)
    }

    /// Write on it: the PDF's board (`boardFor`), made the first time with the PDF as its printout: in a subject, in the subject's
    /// notebook › Papers (the notebook made and filed under the subject when it has none), else beside the PDF. Then opened.
    func writeOn(pdf path: String, focus: CGRect? = nil) {
        let name = (path as NSString).lastPathComponent
        var rel = boardFor(pdf: path) ?? ""
        if rel.isEmpty {
            let paper = papersBoard(pdf: path)
            rel = paper?.board ?? QuestionBank.besideBoard(path)
            let board = folder.appendingPathComponent(rel, isDirectory: true)
            do {
                if let w = paper?.subject, let nb = rel.hasPrefix("notebooks/") ? rel.split(separator: "/").dropFirst().first.map(String.init) : nil {
                    let meta = folder.appendingPathComponent("notebooks/\(nb)/notebook.json")
                    if !FileManager.default.fileExists(atPath: meta.path) {
                        try FolderAccess.write(meta, JSONValue.object([("format", .string("nexus-notebook/1")), ("subject", .string(w.id))]).text + "\n")
                    }
                }
                try FolderAccess.write(board.appendingPathComponent("board.json"), BoardFormat.boardJSON())
                var c = BoardContent()
                let src = paper == nil ? "../" + name : QuestionBank.relTo(board: rel, path)
                c.items = [BoardItem(id: "pdf1", type: "pdf", x: paper == nil ? 60 : 0, y: paper == nil ? 60 : 0, fields: [
                    ("src", .string(src)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
                ])]
                _ = try BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
                boardsChanged(listChanged: true)
            } catch {
                problem = "Couldn't make a board for \(name): \(error.localizedDescription)"
                return
            }
        }
        // from the task panel: the panel goes first, then the board opens
        if openTaskId != nil {
            openTaskId = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in openBoard = .init(path: rel, focus: focus) }
        } else {
            openBoard = .init(path: rel, focus: focus)
        }
    }
}

/// A task's files as small chips (a PDF opens to write on, anything else in Quick Look), and Write on it for its first PDF.
struct TaskFileChips: View {
    @Environment(NexusStore.self) private var store
    let files: [TaskFiles.File]
    @State private var preview: URL?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(files.prefix(2), id: \.path) { f in
                Button { open(f) } label: {
                    Label(f.name, systemImage: f.kind == "pdf" ? "doc.richtext" : f.kind == "image" ? "photo" : "doc")
                        .font(.nx(.caption)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Kit.page.opacity(0.7), in: Capsule())
                }
                .buttonStyle(.plain).foregroundStyle(Kit.muted)
                .accessibilityIdentifier("task-file")
            }
        }
        .quickLookPreview($preview)
    }

    private func open(_ f: TaskFiles.File) {
        if f.kind == "pdf" { store.writeOn(pdf: f.path) } else { preview = store.folder.appendingPathComponent(f.path) }
    }
}
