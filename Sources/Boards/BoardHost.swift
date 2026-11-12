import SwiftUI
import PencilKit
import NexusCore

/// A data-folder board, full screen, in its own navigation bar (PencilKit lives in UIKit).
struct BoardHost: UIViewControllerRepresentable {
    let target: NexusStore.BoardTarget
    let root: URL
    let store: NexusStore
    let onClose: () -> Void
    let onSaved: (String) -> Void
    /// The board in the side pane (its close button closes the pane).
    var isSide = false
    var onSidebar: (() -> Void)?

    func makeUIViewController(context: Context) -> BoardSplitController {
        let vc = BoardController(root: root, path: target.path, focus: target.focus)
        vc.onClose = onClose
        vc.onSaved = onSaved
        vc.store = store
        vc.isSidePane = isSide
        vc.onSidebar = onSidebar
        vc.focusEnd = target.focusEnd
        // the board in its own navigation, with room for a second pane beside it (Side by side)
        let split = BoardSplitController(board: vc, root: root)
        split.store = store
        split.onSaved = onSaved
        return split
    }

    func updateUIViewController(_ controller: BoardSplitController, context: Context) {}
}

/// The ink test's boards (Documents/Boards) copied once into the data folder as boards in the laptop's format, in the notebook
/// "Ink test", so they sync and open on the laptop. The originals stay where they were.
enum InkBoardMove {
    static let key = "movedInkBoards"
    static let notebook = "Ink test"

    static var moved: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func runIfNeeded(_ store: NexusStore) {
        guard store.snapshot.isDataFolder, store.snapshot.readOnlyReason == nil else { return }
        let todo = BoardStore.list().filter { !moved.contains($0.id) }
        guard !todo.isEmpty else { return }
        do {
            let n = try run(todo, root: store.folder)
            if n > 0 { store.boardsChanged(listChanged: true) }
        } catch {
            store.problem = "Couldn't move the ink test boards into Notebooks: \(error.localizedDescription)"
        }
    }

    static func run(_ boards: [BoardInfo], root: URL) throws -> Int {
        let fm = FileManager.default
        let nbDir = root.appendingPathComponent(BoardFormat.notebooks, isDirectory: true).appendingPathComponent(notebook, isDirectory: true)
        try fm.createDirectory(at: nbDir, withIntermediateDirectories: true)
        var done = moved
        var n = 0
        for b in boards {
            let taken = Set((try? fm.contentsOfDirectory(atPath: nbDir.path)) ?? [])
            let name = BoardFormat.freeName(b.name, taken: taken, suffix: ".board")
            let dir = nbDir.appendingPathComponent(name, isDirectory: true)
            var c = BoardContent()
            c.strokes = InkLedger().strokes(BoardStore.loadDrawing(b.id), offset: .zero, taken: [])
            if let pdf = b.pdfName, let data = try? Data(contentsOf: BoardStore.folder(b.id).appendingPathComponent(pdf)) {
                try FolderAccess.writeData(dir.appendingPathComponent("files").appendingPathComponent(pdf), data)
                let o = BoardStore.origin(b.id) ?? CGPoint(x: 60, y: 60)
                c.items.append(BoardItem(id: "pdf1", type: "pdf", x: Double(o.x), y: Double(o.y), fields: [
                    ("src", .string("files/" + pdf)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
                ]))
            }
            try FolderAccess.write(dir.appendingPathComponent("board.json"), BoardFormat.boardJSON(created: b.modified))
            _ = try BoardFiles.save(c, to: dir, write: { url, text in try FolderAccess.write(url, text) })
            done.insert(b.id)
            UserDefaults.standard.set(Array(done), forKey: key)
            n += 1
        }
        return n
    }
}
