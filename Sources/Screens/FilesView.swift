import SwiftUI
import QuickLook
import UniformTypeIdentifiers
import NexusCore

/// Files: the data folder as it is on disk, the laptop's Files mode for the iPhone and the iPad. Folders open in place; a board opens
/// as a board; a PDF on its page (PdfPage: Write on it, its markscheme, its boards and tasks); anything else (picture, Word, Excel, PowerPoint, text, YAML, markdown, audio, video) opens in the system's viewer.
/// Hold a file for Share, Rename and Delete; + makes a folder or brings files in from the Files app. The files Nexus itself is built
/// on (nexus.yaml, a workstream's tasks.yaml…) and boards can be opened and shared here but not renamed or deleted: their own
/// screens do that, so links and the laptop stay right. The iPad shows a size and date column; the iPhone keeps rows to one line.
struct FilesView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The folder shown, relative to the data folder ("" is the data folder itself).
    var path = ""
    var go: (Screen) -> Void = { _ in }

    @State private var entries: [FileEntry] = []
    @State private var preview: URL?
    @State private var pdf: PdfOpen?
    @State private var renaming: FileEntry?
    @State private var newName = ""
    @State private var deleting: FileEntry?
    @State private var makingFolder = false
    @State private var importing = false
    @State private var showHidden = false

    private var folder: URL { path.isEmpty ? store.folder : store.folder.appendingPathComponent(path, isDirectory: true) }
    private var title: String { path.isEmpty ? "Files" : (path as NSString).lastPathComponent }
    private var wide: Bool { sizeClass == .regular }

    var body: some View {
        List {
            if entries.isEmpty {
                Text("This folder is empty.").foregroundStyle(.secondary)
            }
            ForEach(entries) { e in
                Group {
                    // a folder pushes onto this stack (the iPad's detail column too), the rest opens in place
                    if e.isFolder && !e.isBoard {
                        NavigationLink { FilesView(path: e.rel, go: go) } label: { row(e) }
                    } else {
                        Button { open(e) } label: { row(e) }.buttonStyle(.plain)
                    }
                }
                    .contextMenu { menu(e) }
                    .swipeActions(edge: .trailing) {
                        if e.canChange { Button(role: .destructive) { deleting = e } label: { Label("Delete", systemImage: "trash") } }
                    }
                    .accessibilityIdentifier("file-\(e.name)")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(path.isEmpty ? .automatic : .inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newName = ""; makingFolder = true } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    Button { importing = true } label: { Label("Bring in from Files…", systemImage: "square.and.arrow.down") }
                    Divider()
                    Toggle(isOn: $showHidden) { Label("Show hidden files", systemImage: "eye") }
                } label: { Label("Add", systemImage: "plus") }
                .disabled(store.snapshot.readOnlyReason != nil)
            }
        }
        .task(id: "\(path)|\(store.snapshot.loadedAt)|\(store.notebooksVersion)|\(showHidden)") { reload() }
        .refreshable { reload() }
        .quickLookPreview($preview)
        .pdfPage($pdf)
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let e = renaming { rename(e, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New folder", isPresented: $makingFolder) {
            TextField("Name", text: $newName)
            Button("Make") { makeFolder(newName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleting.map { "Delete “\($0.name)”?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let e = deleting { delete(e) } }
        } message: {
            Text("It goes to the bin in this \(Device.name)'s Nexus folder (.trash), and away from your other devices when they sync.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { bringIn(urls) }
        }
    }

    // MARK: a row

    private func row(_ e: FileEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: e.symbol)
                .font(.nx(.title3))
                .foregroundStyle(e.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.display).lineLimit(1).truncationMode(.middle)
                if !wide, let sub = e.subtitle { Text(sub).font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if wide {
                Text(e.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "")
                    .font(.nx(.callout)).foregroundStyle(.secondary).monospacedDigit().frame(width: 80, alignment: .trailing)
                Text(e.modified.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "")
                    .font(.nx(.callout)).foregroundStyle(.secondary).frame(width: 170, alignment: .trailing)
            }
            if !e.canChange { Image(systemName: "lock").font(.nx(.caption2)).foregroundStyle(.tertiary) }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func menu(_ e: FileEntry) -> some View {
        if !e.isFolder || e.isBoard { Button { open(e) } label: { Label("Open", systemImage: "arrow.up.forward.square") } }
        if !e.isFolder && PdfOpen.isPDF(e.url) {
            Button { store.writeOn(pdf: e.rel) } label: { Label("Write on it", systemImage: "pencil.and.scribble") }
                .disabled(store.snapshot.readOnlyReason != nil)
        }
        if !e.isFolder { ShareLink(item: e.url) { Label("Share…", systemImage: "square.and.arrow.up") } }
        if e.canChange {
            Button { newName = e.name; renaming = e } label: { Label("Rename…", systemImage: "pencil") }
            Button(role: .destructive) { deleting = e } label: { Label("Delete…", systemImage: "trash") }
        }
    }

    // MARK: doing things

    private func reload() { entries = FileEntry.list(folder, rel: path, showHidden: showHidden) }

    private func open(_ e: FileEntry) {
        if e.isBoard { store.openBoard = .init(path: e.rel, focus: nil); return }
        if e.isFolder { return } // its row is a link
        // a PDF opens on its page (Write on it, its markscheme, what it goes with), anything else in Quick Look
        if PdfOpen.isPDF(e.url) { pdf = PdfOpen(path: e.rel); return }
        preview = e.url
    }

    private func rename(_ e: FileEntry, to want: String) {
        let name = want.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != e.name else { return }
        let rel = path.isEmpty ? name : path + "/" + name
        guard !name.contains("/"), SyncPaths.isSafe(rel), !SyncPaths.isIgnored(rel) else {
            store.problem = "“\(name)” can't be a file name on every device (no / \\ : * ? \" < > |, nor a dot or space at the end)."
            return
        }
        let to = folder.appendingPathComponent(name)
        // a name that differs only in capitals is a move on Windows too: go through a free name
        if FileManager.default.fileExists(atPath: to.path), name.lowercased() != e.name.lowercased() {
            store.problem = "There is already a “\(name)” here."
            return
        }
        do {
            if name.lowercased() == e.name.lowercased() {
                let step = folder.appendingPathComponent(".renaming-" + UUID().uuidString)
                try FileManager.default.moveItem(at: e.url, to: step)
                try FileManager.default.moveItem(at: step, to: to)
            } else {
                try FileManager.default.moveItem(at: e.url, to: to)
            }
            store.didWrite(listChanged: true, touched: [e.rel, rel])
            store.toast = .init(message: "Renamed to “\(name)”")
            reload()
        } catch { store.problem = "Couldn't rename it: \(error.localizedDescription)" }
    }

    private func delete(_ e: FileEntry) {
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "")
        let bin = store.folder.appendingPathComponent(".trash/\(stamp)", isDirectory: true).appendingPathComponent(e.rel)
        do {
            try FileManager.default.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: e.url, to: bin)
            store.didWrite(listChanged: true, touched: [e.rel])
            store.toast = .init(message: "Moved “\(e.name)” to the bin")
            reload()
        } catch { store.problem = "Couldn't delete it: \(error.localizedDescription)" }
    }

    private func makeFolder(_ want: String) {
        let name = want.trimmingCharacters(in: .whitespaces)
        let rel = path.isEmpty ? name : path + "/" + name
        guard !name.isEmpty, !name.contains("/"), SyncPaths.isSafe(rel), !SyncPaths.isIgnored(rel) else {
            store.problem = "“\(name)” can't be a folder name on every device."
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: false)
            store.didWrite(listChanged: true, touched: [rel])
            reload()
        } catch { store.problem = "Couldn't make the folder: \(error.localizedDescription)" }
    }

    /// Copies files picked in the Files app into this folder (a free name when one is taken).
    private func bringIn(_ urls: [URL]) {
        var touched: [String] = []
        let taken = Set(entries.map { $0.name.lowercased() })
        var used = taken
        for u in urls {
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let ext = u.pathExtension
            let stem = u.deletingPathExtension().lastPathComponent
            var name = u.lastPathComponent
            var n = 2
            while used.contains(name.lowercased()) { name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"; n += 1 }
            used.insert(name.lowercased())
            do {
                try FileManager.default.copyItem(at: u, to: folder.appendingPathComponent(name))
                touched.append(path.isEmpty ? name : path + "/" + name)
            } catch { store.problem = "Couldn't bring in “\(u.lastPathComponent)”: \(error.localizedDescription)" }
        }
        guard !touched.isEmpty else { return }
        store.didWrite(listChanged: true, touched: touched)
        store.toast = .init(message: touched.count == 1 ? "Brought in “\((touched[0] as NSString).lastPathComponent)”" : "Brought in \(touched.count) files")
        reload()
    }
}

/// One file or folder in Files.
struct FileEntry: Identifiable, Equatable {
    let url: URL
    /// Its path in the data folder ("notebooks/Chem/R3.board").
    let rel: String
    let name: String
    let isFolder: Bool
    let size: Int64?
    let modified: Date?
    /// Items inside a folder (nil for a file).
    let count: Int?

    var id: String { rel }
    var isBoard: Bool { isFolder && name.lowercased().hasSuffix(".board") }
    var ext: String { (name as NSString).pathExtension.lowercased() }
    var display: String { isBoard ? String(name.dropLast(6)) : name }

    /// The files Nexus is built on, and boards: opened and shared here, renamed and deleted from their own screens.
    var canChange: Bool {
        if isBoard { return false }
        let n = name.lowercased()
        if ["nexus.yaml", "inbox.yaml", "tasks.yaml", "workstream.yaml", "group.yaml", "notebooks", "review.yaml"].contains(n) { return false }
        // the data folder's own top-level folders: workstream groups and the notebooks
        if isFolder && !rel.contains("/") { return false }
        return true
    }

    var subtitle: String? {
        if isBoard { return "Board" }
        if isFolder { return count.map { $0 == 1 ? "1 item" : "\($0) items" } }
        let s = size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let d = modified.map { $0.formatted(date: .abbreviated, time: .omitted) }
        return [s, d].compactMap { $0 }.joined(separator: " · ")
    }

    var symbol: String {
        if isBoard { return "scribble.variable" }
        if isFolder { return "folder.fill" }
        switch ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp": return "photo"
        case "md", "markdown", "txt": return "doc.plaintext"
        case "yaml", "yml", "json", "jsonl", "csv", "ini", "log": return "curlybraces"
        case "doc", "docx", "pages", "rtf", "odt": return "doc.text"
        case "xls", "xlsx", "numbers", "ods": return "tablecells"
        case "ppt", "pptx", "key", "odp": return "rectangle.on.rectangle"
        case "mp3", "m4a", "wav", "aac", "caf": return "waveform"
        case "mp4", "mov", "m4v": return "film"
        case "zip", "onepkg", "one": return "archivebox"
        default: return "doc"
        }
    }

    var tint: Color {
        if isBoard { return Theme.accent }
        if isFolder { return .accentColor.opacity(0.85) }
        switch ext {
        case "pdf": return .red
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp": return .purple
        case "doc", "docx", "pages": return .blue
        case "xls", "xlsx", "numbers", "csv": return .green
        case "ppt", "pptx", "key": return .orange
        case "yaml", "yml", "json", "jsonl": return .teal
        default: return .secondary
        }
    }

    /// A folder's entries: folders (boards among them) first, then files, by name as Finder sorts; hidden and ignored names left
    /// out unless asked for.
    static func list(_ dir: URL, rel: String, showHidden: Bool) -> [FileEntry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: []) else { return [] }
        var out: [FileEntry] = []
        for u in urls {
            let name = u.lastPathComponent
            let r = rel.isEmpty ? name : rel + "/" + name
            if !showHidden && (name.hasPrefix(".") || SyncPaths.isIgnored(r)) { continue }
            let v = try? u.resourceValues(forKeys: Set(keys))
            let folder = v?.isDirectory ?? false
            let n = folder && !name.lowercased().hasSuffix(".board")
                ? (try? fm.contentsOfDirectory(atPath: u.path).filter { !$0.hasPrefix(".") }.count) : nil
            out.append(FileEntry(url: u, rel: r, name: name, isFolder: folder, size: folder ? nil : v?.fileSize.map(Int64.init),
                                 modified: v?.contentModificationDate, count: n))
        }
        return out.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
