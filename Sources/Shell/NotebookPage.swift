import SwiftUI
import UIKit
import PhotosUI
import VisionKit
import NexusCore

/// A notebook's page: the path at the top, the notebooks inside it, then its boards as cards (the board's picture, thumb.png, its name
/// and when it was last edited). New: Blank board · From a PDF · From a photo · From a scan · New notebook. Press and hold a card for
/// Open · Rename · Move to… · Duplicate · Background · Share as PDF · Delete; drag a card onto a notebook (here or in the sidebar) to
/// move it there.
struct NotebookPage: View {
    let path: String
    let go: (Screen) -> Void
    @Environment(NexusStore.self) private var store
    @State private var actions = NotebookActions()
    @State private var pickingPDF = false
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var sharing: SharedFile?

    var body: some View {
        let _ = store.notebooksVersion
        let tree = Notebook.list(store.folder)
        let nb = Notebook.find(tree, path)
        let rootColor = tree.first { path == $0.path || path.hasPrefix($0.path + "/") }?.color
        Group {
            if let nb {
                ScrollView { content(nb, color: rootColor) }
                    .background(Color(uiColor: .systemGroupedBackground))
            } else {
                ContentUnavailableView("This notebook isn't there any more", systemImage: "book.closed")
            }
        }
        .navigationTitle(nb?.name ?? "Notebook")
        .toolbar { ToolbarItem(placement: .primaryAction) { newMenu.disabled(nb == nil) } }
        .notebookPrompts(actions, store: store)
        .fileImporter(isPresented: $pickingPDF, allowedContentTypes: [.pdf]) { r in
            if case .success(let url) = r { actions.newBoard(fromPDF: url, in: path, store) }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    actions.newBoard(fromPhoto: img, in: path, store)
                }
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            ScannerView { pages in
                scanning = false
                if !pages.isEmpty { actions.newBoard(fromScan: pages, in: path, store) }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $sharing) { f in ShareSheet(url: f.url) }
    }

    private var newMenu: some View {
        Menu {
            Button { actions.ask(.board, in: path) } label: { Label("Blank board", systemImage: "scribble") }
            Button { pickingPDF = true } label: { Label("From a PDF…", systemImage: "doc.richtext") }
            Button { pickingPhoto = true } label: { Label("From a photo…", systemImage: "photo") }
            if VNDocumentCameraViewController.isSupported {
                Button { scanning = true } label: { Label("From a scan…", systemImage: "doc.viewfinder") }
            }
            Divider()
            Button { actions.ask(.notebook, in: path) } label: { Label("New notebook", systemImage: "folder.badge.plus") }
        } label: { Label("New", systemImage: "plus") }
    }

    @ViewBuilder
    private func content(_ nb: Notebook, color: String?) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            crumbs
            if !nb.notebooks.isEmpty {
                Text("Notebooks").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    ForEach(nb.notebooks) { sub in NotebookCard(nb: sub, color: color, actions: actions, open: { go(.notebook(sub.path)) }) }
                }
            }
            Text("Boards").font(.headline)
            if nb.boards.isEmpty {
                Text("No boards here yet. New › Blank board starts one.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 22) {
                    ForEach(nb.boards) { b in BoardCard(b: b, actions: actions, share: { share(b) }) }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Notebooks › School › Chem: each part but the last opens that notebook.
    private var crumbs: some View {
        let parts = path.split(separator: "/").map(String.init)
        return HStack(spacing: 6) {
            ForEach(parts.indices, id: \.self) { i in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                let p = parts[0...i].joined(separator: "/")
                let name = i == 0 ? "Notebooks" : parts[i]
                if i == 0 || i == parts.count - 1 {
                    Text(name).foregroundStyle(i == 0 ? .secondary : .primary)
                } else {
                    Button(name) { go(.notebook(p)) }
                }
            }
        }
        .font(.subheadline)
    }

    private func share(_ b: Notebook.BoardRef) {
        if let url = BoardExport.pdf(root: store.folder, path: b.path) { sharing = SharedFile(url: url) }
        else { actions.problem = "There is nothing on “\(b.name)” to share yet." }
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// A notebook inside the page's notebook.
struct NotebookCard: View {
    let nb: Notebook
    let color: String?
    @Bindable var actions: NotebookActions
    let open: () -> Void
    @Environment(NexusStore.self) private var store

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(color.map { Color(uiColor: InkConvert.color($0)) } ?? Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(nb.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    let n = nb.allBoards.count
                    Text(n == 1 ? "1 board" : "\(n) boards").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu { NotebookMenu(nb: nb, actions: actions) }
        .dropDestination(for: String.self) { paths, _ in actions.move(paths, into: nb.path, store) }
    }
}

/// A board's card: its picture, name and when it was last edited.
struct BoardCard: View {
    let b: Notebook.BoardRef
    @Bindable var actions: NotebookActions
    let share: () -> Void
    @Environment(NexusStore.self) private var store
    @State private var thumb: UIImage?
    @State private var edited: Date?

    var body: some View {
        Button { store.openBoard = .init(path: b.path, focus: nil) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Color.white
                    if let thumb {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Image(systemName: "scribble").font(.largeTitle).foregroundStyle(.quaternary)
                    }
                }
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(uiColor: .separator)))
                Text(b.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(edited.map { "Edited " + $0.formatted(.relative(presentation: .named)) } ?? " ")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(b.path)
        .contextMenu {
            Button { store.openBoard = .init(path: b.path, focus: nil) } label: { Label("Open", systemImage: "arrow.up.right.square") }
            Button { actions.ask(.rename, in: b.path, name: b.name) } label: { Label("Rename…", systemImage: "pencil") }
            Button { actions.moving = b.path } label: { Label("Move to…", systemImage: "folder") }
            Button { actions.duplicate(b, store) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Menu {
                ForEach(Paper.Kind.allCases, id: \.self) { k in
                    Button(k.rawValue.prefix(1).uppercased() + k.rawValue.dropFirst()) { actions.setPaper(b, k, store) }
                }
            } label: { Label("Background", systemImage: "squareshape.split.3x3") }
            Button(action: share) { Label("Share as PDF", systemImage: "square.and.arrow.up") }
            Divider()
            Button(role: .destructive) { actions.removing = b } label: { Label("Delete…", systemImage: "trash") }
        }
        .task(id: "\(b.path)|\(store.openBoard == nil)|\(store.notebooksVersion)") {
            let board = store.folder.appendingPathComponent(b.path, isDirectory: true)
            let (img, when) = await Task.detached(priority: .utility) { () -> (UIImage?, Date?) in
                (UIImage(contentsOfFile: board.appendingPathComponent(BoardThumb.file).path), boardLastEdited(board))
            }.value
            thumb = img
            edited = when
        }
    }
}

/// The newest of board.json, its tiles and its text files.
func boardLastEdited(_ board: URL) -> Date? {
    let fm = FileManager.default
    var urls = [board.appendingPathComponent("board.json")]
    for d in ["tiles", "text"] {
        urls += (try? fm.contentsOfDirectory(at: board.appendingPathComponent(d), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }
    return urls.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
}

/// The share sheet for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// The document camera: scanned pages, or none when cancelled.
struct ScannerView: UIViewControllerRepresentable {
    let done: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done([]) }
    }
}
