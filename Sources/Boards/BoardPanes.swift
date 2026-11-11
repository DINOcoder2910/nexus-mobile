import SwiftUI
import PDFKit
import NexusCore

/// What sits beside a board when it is side by side: another board (or the same one again, to see two places at once), or a
/// board's PDF on its own.
enum SidePane: Identifiable {
    case board(NexusStore.BoardTarget)
    case pdf(URL)

    var id: String {
        switch self {
        case .board(let t): return "board:" + t.id.uuidString
        case .pdf(let u): return "pdf:" + u.path
        }
    }
}

/// The open board in the app's detail column, beside the sidebar (the board's bar shows and hides the sidebar), and on its right
/// the side pane when there is one.
struct BoardPanes: View {
    @Environment(NexusStore.self) private var store
    let main: NexusStore.BoardTarget
    @Binding var side: SidePane?
    @Binding var columns: NavigationSplitViewVisibility
    @State private var picking = false

    var body: some View {
        HStack(spacing: 0) {
            host(main, isSide: false).id(main.id).ignoresSafeArea()
            if let side {
                Divider().ignoresSafeArea()
                switch side {
                case .board(let t): host(t, isSide: true).id(t.id).ignoresSafeArea()
                case .pdf(let url): PdfPane(url: url) { withAnimation { self.side = nil } }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $picking) {
            SideBoardPicker(root: store.folder) { path in
                picking = false
                withAnimation { side = .board(.init(path: path, focus: nil)) }
            }
        }
    }

    private func host(_ t: NexusStore.BoardTarget, isSide: Bool) -> some View {
        BoardHost(target: t, root: store.folder, onClose: {
            if isSide { withAnimation { side = nil } } else { store.openBoard = nil }
        }, onSaved: { path in
            store.boardsChanged()
            HandwritingIndex.shared.refresh(board: path, root: store.folder)
        }, isSide: isSide, onSidebar: isSide ? nil : {
            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
        }, onSide: isSide ? nil : { request in
            switch request {
            case .same: withAnimation { side = .board(.init(path: main.path, focus: nil)) }
            case .pick: picking = true
            case .pdf(let url): withAnimation { side = .pdf(url) }
            case .close: withAnimation { side = nil }
            }
        })
    }
}

/// A board's PDF on its own, in its own pane (PDFKit: scroll, zoom, select and find as in any PDF).
struct PdfPane: View {
    let url: URL
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.deletingPathExtension().lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Button("Close", systemImage: "xmark.circle.fill", action: onClose)
                    .labelStyle(.iconOnly).font(.title3).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(.bar)
            Divider()
            PdfKitView(url: url).ignoresSafeArea(edges: .bottom)
        }
    }
}

struct PdfKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {}
}

/// Pick the board to open beside this one.
struct SideBoardPicker: View {
    let root: URL
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Notebook.list(root)) { nb in
                    Section(nb.name) {
                        ForEach(nb.boards) { b in row(b.name, b.path) }
                        ForEach(nb.sections) { s in
                            ForEach(s.boards) { b in row(b.name, b.path, in: s.name) }
                        }
                    }
                }
            }
            .navigationTitle("Open beside")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ name: String, _ path: String, in section: String? = nil) -> some View {
        Button { onPick(path) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(.primary)
                if let section { Text(section).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
