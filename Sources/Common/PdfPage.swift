import SwiftUI
import PDFKit
import NexusCore

/// A PDF opened from a Study sheet, Files or search, as the laptop's clean viewer (nexus desktop/src/board/pdfview.tsx PdfPage and
/// files/FileScreen.tsx): the PDF with no ink, Write on it as its main button (Your board once it has one), its markscheme in a
/// second pane, and what it goes with: its subject, its boards, the tasks that point at it and the subject's cards for its units.
struct PdfOpen: Identifiable, Equatable {
    /// A data-folder path ("classes/chem/files/R1/Test.pdf").
    let path: String
    var id: String { path }

    /// A file of the data folder as a path of it, or nil for one outside.
    init?(_ url: URL, root: URL) {
        let r = root.resolvingSymlinksInPath().standardizedFileURL.path, f = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard f.hasPrefix(r + "/") else { return nil }
        path = String(f.dropFirst(r.count + 1))
    }
    init(path: String) { self.path = path }

    static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    /// A file a list opens: a PDF of the data folder on its page, anything else in Quick Look.
    static func route(_ url: URL, root: URL, pdf: Binding<PdfOpen?>, preview: Binding<URL?>) {
        if isPDF(url), let o = PdfOpen(url, root: root) { pdf.wrappedValue = o } else { preview.wrappedValue = url }
    }
}

extension View {
    /// Shows a PDF's page over the screen while `open` holds one.
    func pdfPage(_ open: Binding<PdfOpen?>) -> some View {
        fullScreenCover(item: open) { o in PdfPage(path: o.path) }
    }
}

struct PdfPage: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var size
    let path: String

    @State private var board: String?
    @State private var boards: [String] = []
    @State private var ms: String?
    @State private var showMs = false
    @State private var related = Related()

    struct Related {
        var subject: Workstream?
        var tasks: [NexusTask] = []
        var decks: [(path: String, name: String)] = []
        var studyId = ""
    }

    private var name: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
    private var crumbs: String { path.split(separator: "/").dropLast().suffix(2).joined(separator: " › ") }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasRelated { relatedRow.padding(.horizontal, 16).padding(.vertical, 8) }
                Divider()
                panes
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }.accessibilityIdentifier("pdf-close")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        if !crumbs.isEmpty { Text(crumbs).font(.nx(.caption2)).foregroundStyle(.secondary).lineLimit(1) }
                        Text(name).font(.nx(.headline)).lineLimit(1).accessibilityIdentifier("pdf-name")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if ms != nil {
                        Button { withAnimation(.easeOut(duration: 0.2)) { showMs.toggle() } } label: {
                            Label("Markscheme", systemImage: "rectangle.split.2x1")
                        }
                        .labelStyle(.titleAndIcon)
                        .tint(showMs ? Theme.accent : .primary)
                        .accessibilityIdentifier("pdf-ms")
                        .accessibilityValue(showMs ? "shown" : "hidden")
                    }
                    if let board {
                        Button { open(board: board) } label: { Label("Your board", systemImage: "scribble.variable") }
                            .labelStyle(.titleAndIcon).buttonStyle(.borderedProminent).tint(Theme.accent)
                            .accessibilityIdentifier("pdf-board")
                    } else {
                        Button { writeOnIt() } label: { Label("Write on it", systemImage: "pencil.and.scribble") }
                            .labelStyle(.titleAndIcon).buttonStyle(.borderedProminent).tint(Theme.accent)
                            .disabled(store.snapshot.readOnlyReason != nil)
                            .accessibilityIdentifier("write-on-it")
                    }
                }
            }
        }
        .task(id: path) { load() }
    }

    // MARK: pieces

    @ViewBuilder
    private var panes: some View {
        let paper = PdfKitView(url: store.folder.appendingPathComponent(path)).accessibilityIdentifier("pdf-view")
        if showMs, let ms {
            let other = VStack(spacing: 0) {
                Text("Markscheme · " + ((ms as NSString).lastPathComponent as NSString).deletingPathExtension)
                    .font(.nx(.caption, .medium)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 6)
                PdfKitView(url: store.folder.appendingPathComponent(ms))
            }.accessibilityElement(children: .contain).accessibilityIdentifier("pdf-ms-pane")
            if size == .regular {
                HStack(spacing: 0) { paper; Divider(); other }
            } else {
                VStack(spacing: 0) { paper; Divider(); other }
            }
        } else {
            paper
        }
    }

    private var hasRelated: Bool { related.subject != nil || !boards.isEmpty || !related.tasks.isEmpty || !related.decks.isEmpty }

    private var relatedRow: some View {
        FlowRow(spacing: 6) {
            if let w = related.subject {
                Chip(text: w.name, icon: "circle.fill", color: store.color(workstream: w.id))
                    .accessibilityIdentifier("pdf-subject")
            }
            ForEach(boards, id: \.self) { b in
                Button { open(board: b) } label: {
                    Chip(text: ((b as NSString).lastPathComponent as NSString).deletingPathExtension, icon: "scribble.variable", color: Theme.accent)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Your board " + ((b as NSString).lastPathComponent as NSString).deletingPathExtension)
                .accessibilityIdentifier("pdf-related-board")
            }
            ForEach(related.tasks, id: \.id) { t in
                Button { open(task: t) } label: { Chip(text: t.title, icon: "checkmark.circle", color: store.color(t)) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("pdf-related-task")
            }
            ForEach(related.decks, id: \.path) { d in
                NavigationLink { DeckView(workstreamId: related.studyId, path: d.path) } label: {
                    Chip(text: d.name, icon: "rectangle.on.rectangle.angled", color: .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("pdf-related-cards")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pdf-related")
    }

    // MARK: what it goes with

    private func load() {
        let s = store.writeSubjects()
        board = store.madeBoard(pdf: path, s)
        boards = board.map { [$0] } ?? []
        ms = store.markscheme(of: path)
        var r = Related()
        if let id = WriteOnIt.subject(of: path, s) { r.subject = store.workstream(id) }
        r.tasks = store.snapshot.tasks.values.filter { !$0.done && !TaskFiles.targets($0).isEmpty && store.files(of: $0).contains { $0.path == path } }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        // the subject's cards for the units this sheet is on
        if let id = r.subject?.id, let study = StudyLibrary.shared.study(id),
           let sheet = study.sheets.sheets.first(where: { $0.files.contains { $0.path == path } }) {
            let codes = sheet.codes
            r.studyId = id
            r.decks = study.decks.compactMap { f -> (path: String, name: String)? in
                guard let d = f.deck, !d.unit.isEmpty else { return nil }
                let on = codes.contains { c in c == d.unit || c.hasPrefix(d.unit + ".") || d.unit.hasPrefix(c + ".") }
                return on ? (f.path, d.title.isEmpty ? f.fileId : d.title) : nil
            }
        }
        related = r
        // other boards of the subject holding it as a printout: a look through their tiles, off the main thread
        let root = store.folder, me = path
        DispatchQueue.global(qos: .utility).async {
            let more = NexusStore.boardsHolding(me, root: root, s)
            DispatchQueue.main.async {
                guard me == path else { return }
                for b in more where !boards.contains(b) { boards.append(b) }
                if board == nil { board = boards.first }
            }
        }
    }

    // MARK: going on

    private func writeOnIt() {
        let p = path
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [store] in store.writeOn(pdf: p) }
    }

    private func open(board b: String) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [store] in store.openBoard = .init(path: b, focus: nil) }
    }

    private func open(task t: NexusTask) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [store] in store.open(t) }
    }
}

/// PDFKit's view: the pages down, fitted to the width.
struct PdfKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .secondarySystemBackground
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL?.standardizedFileURL != url.standardizedFileURL { v.document = PDFDocument(url: url) }
    }
}
