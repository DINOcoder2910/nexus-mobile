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

    /// Write on it: the PDF's board beside it (`<name>.board`, its pages down the board as a printout of the PDF where it is,
    /// as the laptop keeps a PDF's writing), made the first time, then opened.
    func writeOn(pdf path: String) {
        let name = (path as NSString).lastPathComponent
        let dir = (path as NSString).deletingLastPathComponent
        let rel = (dir.isEmpty ? "" : dir + "/") + (name as NSString).deletingPathExtension + ".board"
        let board = folder.appendingPathComponent(rel, isDirectory: true)
        if !FileManager.default.fileExists(atPath: board.appendingPathComponent("board.json").path) {
            do {
                try FolderAccess.write(board.appendingPathComponent("board.json"), BoardFormat.boardJSON())
                var c = BoardContent()
                c.items = [BoardItem(id: "pdf1", type: "pdf", x: 60, y: 60, fields: [
                    ("src", .string("../" + name)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in openBoard = .init(path: rel, focus: nil) }
        } else {
            openBoard = .init(path: rel, focus: nil)
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
