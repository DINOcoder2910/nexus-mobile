import SwiftUI
import NexusCore

/// Search boards: finds a word in what was handwritten or typed on any board in Notebooks, and opens the board there. PDFs whose
/// names hold the words come first, each opening on its page (Write on it, its markscheme, what it goes with).
struct BoardSearchView: View {
    @Environment(NexusStore.self) private var store
    @State private var query = ""
    @State private var pdfNames: [String] = []
    @State private var pdf: PdfOpen?

    private var index: HandwritingIndex { HandwritingIndex.shared }

    var body: some View {
        let hits: [HandwritingIndex.Hit] = index.search(query)
        let groups: [BoardHits] = BoardSearchView.grouped(hits)
        let words: [String] = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        List {
            Section {
                status
            }
            let pdfs = BoardSearchView.pdfHits(pdfNames, words: words)
            if !pdfs.isEmpty {
                Section {
                    ForEach(pdfs, id: \.self) { p in
                        Button { pdf = PdfOpen(path: p) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.richtext").foregroundStyle(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(((p as NSString).lastPathComponent as NSString).deletingPathExtension).foregroundStyle(.primary).lineLimit(1)
                                    Text((p as NSString).deletingLastPathComponent).font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .contextMenu {
                            Button { store.writeOn(pdf: p) } label: { Label("Write on it", systemImage: "pencil.and.scribble") }
                        }
                        .accessibilityIdentifier("search-pdf")
                    }
                } header: {
                    Text("PDFs").font(.nx(.headline)).foregroundStyle(.primary).textCase(nil)
                }
            }
            if !groups.isEmpty {
                ForEach(groups) { g in
                    Section {
                        ForEach(g.hits) { hit in
                            Button { store.openBoard = .init(path: hit.boardPath, focus: hit.box) } label: {
                                row(hit, words: words)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.name).font(.nx(.headline)).foregroundStyle(.primary).textCase(nil)
                            if !g.place.isEmpty { Text(g.place).font(.nx(.caption)).foregroundStyle(.secondary).textCase(nil) }
                        }
                    }
                }
            }
        }
        .overlay { emptyState(found: !hits.isEmpty || !BoardSearchView.pdfHits(pdfNames, words: words).isEmpty) }
        .pdfPage($pdf)
        .task(id: "\(store.folder.path)|\(store.notebooksVersion)") {
            let root = store.folder
            pdfNames = await Task.detached(priority: .utility) { BoardSearchView.pdfFiles(root) }.value
        }
        .searchable(text: $query, prompt: "Words on your boards, or a PDF's name")
        .autocorrectionDisabled()
        .navigationTitle("Search boards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { index.reread(root: store.folder) } label: { Label("Re-read", systemImage: "arrow.clockwise") }
                    .disabled(index.isIndexing)
            }
        }
        .onAppear { index.refresh(root: store.folder) }
        .onChange(of: store.notebooksVersion) { _, _ in index.refresh(root: store.folder) }
        .onChange(of: store.folder) { _, _ in index.refresh(root: store.folder) }
    }

    // MARK: pieces

    @ViewBuilder
    private var status: some View {
        if index.isIndexing {
            HStack(spacing: 10) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(progressLine)
                    if let name = index.current { Text(name).font(.nx(.caption)).foregroundStyle(.secondary) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(doneLine)
                    .foregroundStyle(.secondary)
                if let problem = index.problem {
                    Text(problem).font(.nx(.caption)).foregroundStyle(.orange)
                }
            }
        }
    }

    private var progressLine: String {
        let total = index.total
        guard total > 0 else { return "Reading handwriting…" }
        let at = min(index.done + 1, total)
        return "Reading handwriting… \(at) of \(total) " + (total == 1 ? "board" : "boards")
    }

    private var doneLine: String {
        let n = index.boards.count
        return n == 1 ? "1 board read" : "\(n) boards read"
    }

    private func row(_ hit: HandwritingIndex.Hit, words: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: hit.typed ? "textformat" : "scribble")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            BoardSearchView.highlighted(hit.text, words: words)
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer(minLength: 8)
            Text(hit.typed ? "typed" : "handwriting")
                .font(.nx(.caption2))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func emptyState(found: Bool) -> some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        if index.boards.isEmpty && !index.isIndexing && !found {
            ContentUnavailableView("No boards yet", systemImage: "scribble.variable",
                                   description: Text("Boards you make in Notebooks show up here, handwriting and typed text both."))
        } else if q.isEmpty {
            ContentUnavailableView("Search your boards", systemImage: "text.magnifyingglass",
                                   description: Text("Type a word to find it on any board, written by hand or typed."))
        } else if !found {
            if index.isIndexing {
                ContentUnavailableView("Nothing yet", systemImage: "hourglass",
                                       description: Text("Still reading handwriting. “\(q)” may turn up once every board is read."))
            } else {
                ContentUnavailableView("Nothing found", systemImage: "magnifyingglass",
                                       description: Text("No board has “\(q)” on it. Handwriting that is hard to read may be missed."))
            }
        }
    }

    // MARK: helpers

    /// The PDFs whose name (or folder) holds every word, best first: the name before the folder, shorter first; at most 12.
    static func pdfHits(_ all: [String], words: [String]) -> [String] {
        let ws = words.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }.filter { !$0.isEmpty }
        guard !ws.isEmpty else { return [] }
        func fold(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let hits = all.filter { p in let f = fold(p); return ws.allSatisfy { f.contains($0) } }
        let named = { (p: String) in let n = fold((p as NSString).lastPathComponent); return ws.allSatisfy { n.contains($0) } }
        return Array(hits.sorted { a, b in
            let na = named(a), nb = named(b)
            if na != nb { return na }
            return a.count != b.count ? a.count < b.count : a < b
        }.prefix(12))
    }

    /// Every PDF in the data folder (not inside boards, the bin or hidden folders), as data-folder paths.
    nonisolated static func pdfFiles(_ root: URL) -> [String] {
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [String] = [], seen = 0
        for case let u as URL in e {
            seen += 1
            if seen > 60_000 { break }
            if u.pathExtension.lowercased() == "board" { e.skipDescendants(); continue }
            guard u.pathExtension.lowercased() == "pdf" else { continue }
            let full = u.resolvingSymlinksInPath().standardizedFileURL.path
            if full.hasPrefix(base.path + "/") { out.append(String(full.dropFirst(base.path.count + 1))) }
        }
        return out
    }

    struct BoardHits: Identifiable {
        var path: String
        var name: String
        var place: String
        var hits: [HandwritingIndex.Hit]
        var id: String { path }
    }

    /// Hits by board, boards in the order of their best hit, each board's hits as found (best first).
    static func grouped(_ hits: [HandwritingIndex.Hit]) -> [BoardHits] {
        var out: [BoardHits] = []
        var at: [String: Int] = [:]
        for h in hits {
            if let i = at[h.boardPath] {
                out[i].hits.append(h)
            } else {
                at[h.boardPath] = out.count
                out.append(BoardHits(path: h.boardPath, name: h.boardName, place: h.place, hits: [h]))
            }
        }
        return out
    }

    /// The line with each query word in bold and the accent colour (no case, no accents).
    static func highlighted(_ text: String, words: [String]) -> Text {
        var marks: [Range<String.Index>] = []
        for w in words where !w.isEmpty {
            var from = text.startIndex
            while from < text.endIndex,
                  let r = text.range(of: w, options: [.caseInsensitive, .diacriticInsensitive], range: from..<text.endIndex) {
                marks.append(r)
                from = r.upperBound > r.lowerBound ? r.upperBound : text.index(after: r.lowerBound)
            }
        }
        guard !marks.isEmpty else { return Text(text) }
        marks.sort { $0.lowerBound < $1.lowerBound }
        // overlapping marks joined
        var merged: [Range<String.Index>] = []
        for r in marks {
            if let last = merged.last, r.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, r.upperBound)
            } else {
                merged.append(r)
            }
        }
        var result = Text("")
        var pos = text.startIndex
        for r in merged {
            if pos < r.lowerBound { result = result + Text(String(text[pos..<r.lowerBound])) }
            result = result + Text(String(text[r])).bold().foregroundColor(Theme.accent)
            pos = r.upperBound
        }
        if pos < text.endIndex { result = result + Text(String(text[pos..<text.endIndex])) }
        return result
    }
}
