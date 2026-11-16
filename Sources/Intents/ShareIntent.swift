import AppIntents
import UniformTypeIdentifiers
import NexusCore

/// Share into Nexus from Safari, Photos, Files or Mail, with no share extension (so nothing extra to sign when sideloading): a
/// Shortcut set to "Show in Share Sheet" runs this action in the app's own process. A PDF or a photo becomes a board in a notebook
/// ("Shared" unless the Shortcut names one), a link or words a task in the Inbox (NexusCore Shared). Settings › Share into Nexus
/// says how to make the Shortcut.
struct SaveToNexusIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Nexus"
    static let description = IntentDescription("Saves what you share: a PDF or a photo becomes a board in a notebook, a link or some words a task in the Inbox.")
    static let openAppWhenRun = false

    /// Any file: what it is, is worked out from its type and bytes (NexusCore Shared.kind). (Listing the content types here
    /// needs iOS 18, above the app's lowest iOS.)
    @Parameter(title: "Items")
    var items: [IntentFile]

    @Parameter(title: "Notebook", description: "Where PDFs and photos go. Leave it empty for “Shared”.")
    var notebook: String?

    static var parameterSummary: some ParameterSummary { Summary("Save \(\.$items) to Nexus") { \.$notebook } }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store
        store.reloadIfChanged()
        let r = ShareSave.save(items.map { ($0.filename, $0.type?.identifier, $0.data) }, notebook: notebook, store: store)
        if r.anything { await AppServices.sync.backgroundCycle(store) }
        return .result(dialog: IntentDialog(stringLiteral: r.summary))
    }
}

/// Words or a link straight from the Share Sheet's text (a Shortcut's input as text, or Siri's "save this to Nexus").
struct SaveTextToNexusIntent: AppIntent {
    static let title: LocalizedStringResource = "Save text to Nexus"
    static let description = IntentDescription("Puts a link or some words in the Nexus Inbox as a task.")
    static let openAppWhenRun = false

    @Parameter(title: "Text or link")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Save \(\.$text) to the Nexus Inbox") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store
        store.reloadIfChanged()
        let r = ShareSave.save([("text.txt", UTType.plainText.identifier, Data(text.utf8))], notebook: nil, store: store)
        if r.anything { await AppServices.sync.backgroundCycle(store) }
        return .result(dialog: IntentDialog(stringLiteral: r.summary))
    }
}

/// Writes shared things into the data folder (the intents above; the app's own drop and paste could use it too).
@MainActor
enum ShareSave {
    struct Result {
        var boards: [String] = []
        var tasks: [String] = []
        var skipped = 0
        var problem: String?
        var notebook = Shared.defaultNotebook

        var anything: Bool { !boards.isEmpty || !tasks.isEmpty }

        var summary: String {
            if let problem, !anything { return problem }
            var parts: [String] = []
            if boards.count == 1 { parts.append("“\(boards[0])” to \(notebook)") }
            if boards.count > 1 { parts.append("\(boards.count) boards to \(notebook)") }
            if tasks.count == 1 { parts.append("“\(tasks[0])” to the Inbox") }
            if tasks.count > 1 { parts.append("\(tasks.count) tasks to the Inbox") }
            var s = parts.isEmpty ? "Nothing Nexus can keep was shared." : "Saved " + parts.joined(separator: " and ") + "."
            if skipped > 0 && !parts.isEmpty { s += " \(skipped) item\(skipped == 1 ? "" : "s") Nexus can't keep left out." }
            return s
        }
    }

    static func save(_ items: [(name: String, type: String?, data: Data)], notebook want: String?, store: NexusStore) -> Result {
        var r = Result()
        guard store.snapshot.isDataFolder, store.snapshot.readOnlyReason == nil else {
            r.problem = store.snapshot.readOnlyReason ?? "Set up the Nexus folder in the app first."
            return r
        }
        r.notebook = Shared.notebook(want)
        let dir = BoardFormat.notebooks + "/" + r.notebook
        let actions = NotebookActions()
        for it in items {
            let kind = Shared.kind(typeId: it.type, name: it.name, data: it.data)
            do {
                switch kind {
                case .pdf:
                    try makeFolder(dir, store)
                    r.boards.append(try pdfBoard(it.data, named: Shared.boardName(fileName: it.name, kind: kind), in: dir, actions, store))
                case .image:
                    guard let img = BoardImage.prepare(data: it.data) else { r.skipped += 1; continue }
                    try makeFolder(dir, store)
                    r.boards.append(try photoBoard(img, named: Shared.boardName(fileName: it.name, kind: kind), in: dir, actions, store))
                case .link, .text:
                    guard let t = Shared.task(kind), let id = store.add(title: t.title, workstream: nil) else { r.skipped += 1; continue }
                    if let note = t.note, let task = store.task(id) { store.setNote(task, note) }
                    r.tasks.append(t.title)
                case .unknown:
                    r.skipped += 1
                }
            } catch {
                r.problem = "Couldn't save “\(it.name)”: \(error.localizedDescription)"
            }
        }
        return r
    }

    private static func makeFolder(_ dir: String, _ store: NexusStore) throws {
        try FileManager.default.createDirectory(at: store.folder.appendingPathComponent(dir, isDirectory: true), withIntermediateDirectories: true)
    }

    /// The PDF beside the board (as on the laptop), its pages down the board. Returns the board's name.
    private static func pdfBoard(_ data: Data, named name: String, in dir: String, _ actions: NotebookActions, _ store: NexusStore) throws -> String {
        let folder = store.folder.appendingPathComponent(dir, isDirectory: true)
        let pdf = BoardFormat.freeName(name, taken: NotebookActions.names(in: folder), suffix: ".pdf")
        try FolderAccess.writeData(folder.appendingPathComponent(pdf), data)
        let it = BoardItem(id: "pdf1", type: "pdf", x: 60, y: 60, fields: [
            ("src", .string("../" + pdf)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
        ])
        let rel = try actions.makeBoard(name, in: dir, store, items: [it])
        return ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The photo in the board's files, at the top left. Returns the board's name.
    private static func photoBoard(_ img: BoardImage.Prepared, named name: String, in dir: String, _ actions: NotebookActions, _ store: NexusStore) throws -> String {
        let file = "files/photo" + img.ext
        let scale = min(1, 1000 / max(1, Double(img.size.width)))
        let it = BoardItem(id: "img1", type: "image", x: 60, y: 60, fields: [
            ("src", .string(file)), ("w", .number((Double(img.size.width) * scale).rounded())), ("h", .number((Double(img.size.height) * scale).rounded())),
        ])
        let rel = try actions.makeBoard(name, in: dir, store)
        let board = store.folder.appendingPathComponent(rel, isDirectory: true)
        try FolderAccess.writeData(board.appendingPathComponent(file), img.data)
        var c = BoardContent()
        c.items = [it]
        _ = try BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
        store.boardsChanged(listChanged: true)
        return ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
