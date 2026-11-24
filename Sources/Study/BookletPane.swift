import SwiftUI
import PDFKit
import NexusCore

/// The subjects' data booklets (maths: the formula booklet) beside a question, as the laptop's Data booklet (D): the question's
/// subject's first, any other subject's one tap away, each opening at the page you were last on. On the iPad it is the pane beside
/// the question (in place of the markscheme), on the iPhone a sheet; on the board (solving a question, or any paper's board) the bar's
/// Data booklet button puts it in the second pane (BoardController+Booklet.swift). The pick (NexusCore Booklets) is the laptop's.
@MainActor enum BookletShelf {
    private static var cache: (key: String, at: Date, list: [Booklets.Booklet])?

    /// every subject's booklet, the subject `first`'s first (read again after 20 s, or when the folder's tasks were read again)
    static func list(_ store: NexusStore, first: String?) -> [Booklets.Booklet] {
        let key = "\(store.folder.path)|\(store.snapshot.loadedAt.timeIntervalSince1970)"
        let all: [Booklets.Booklet]
        if let c = cache, c.key == key, Date().timeIntervalSince(c.at) < 20 { all = c.list } else {
            all = Booklets.find(root: store.folder, workstreams: Array(store.snapshot.workstreams.values), first: nil)
            cache = (key, Date(), all)
        }
        guard let first, let i = all.firstIndex(where: { $0.id == first }) else { return all }
        var out = all
        out.insert(out.remove(at: i), at: 0)
        return out
    }

    /// the booklet last picked for a subject's questions, else the subject's own (else the first there is)
    static func picked(_ list: [Booklets.Booklet], for subject: String?) -> Booklets.Booklet? {
        let want = subject.flatMap { UserDefaults.standard.string(forKey: "nexus.booklet.pick." + $0) }
        return list.first { $0.id == want } ?? list.first
    }

    static func pick(_ b: Booklets.Booklet, for subject: String?) {
        guard let subject else { return }
        UserDefaults.standard.set(b.id, forKey: "nexus.booklet.pick." + subject)
    }

    /// the page a booklet was left at
    nonisolated static func page(_ path: String) -> Int { UserDefaults.standard.integer(forKey: "nexus.booklet.page." + path) }
    nonisolated static func keep(_ path: String, page: Int) { UserDefaults.standard.set(page, forKey: "nexus.booklet.page." + path) }
}

/// The booklet pane: which subject's (a switch when there are several) and the PDF.
struct BookletPane: View {
    @Environment(NexusStore.self) private var store
    let subject: String
    let close: () -> Void
    @State private var list: [Booklets.Booklet] = []
    @State private var shown: Booklets.Booklet?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "book.pages").foregroundStyle(.secondary)
                if list.count > 1 {
                    Picker("Whose booklet", selection: Binding(get: { shown?.id ?? "" }, set: { id in
                        if let b = list.first(where: { $0.id == id }) { shown = b; BookletShelf.pick(b, for: subject) }
                    })) {
                        ForEach(list) { b in Text(b.name).tag(b.id) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("bq-booklet-subjects")
                } else {
                    Text(shown.map { "\($0.name) \($0.title.lowercased())" } ?? "Data booklet").font(.nx(.callout, .semibold))
                }
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close the booklet")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            if let b = shown {
                BookletPdfView(url: store.folder.appendingPathComponent(b.path), path: b.path)
                    .id(b.path)
            } else {
                EmptyNote(title: "No data booklet yet", detail: "Put the PDF in a subject's files with “data booklet” (maths: “formula booklet”) in its name, and it shows here.", icon: "book.pages")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bq-booklet-pane")
        .task(id: subject) {
            list = BookletShelf.list(store, first: subject)
            shown = BookletShelf.picked(list, for: subject)
        }
    }
}

/// A booklet's PDF, opened at the page it was left at (kept as you scroll).
struct BookletPdfView: UIViewRepresentable {
    let url: URL
    let path: String

    final class Coordinator: NSObject {
        let path: String
        init(path: String) { self.path = path }
        @objc func changed(_ n: Notification) {
            guard let v = n.object as? PDFView, let p = v.currentPage, let i = v.document?.index(for: p) else { return }
            BookletShelf.keep(path, page: i)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(path: path) }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .secondarySystemBackground
        v.document = PDFDocument(url: url)
        let at = BookletShelf.page(path)
        if at > 0, let p = v.document?.page(at: at) { DispatchQueue.main.async { v.go(to: p) } }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.changed(_:)), name: .PDFViewPageChanged, object: v)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}

    static func dismantleUIView(_ v: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator, name: .PDFViewPageChanged, object: v)
    }
}
