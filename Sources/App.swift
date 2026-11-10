import SwiftUI
import UniformTypeIdentifiers

@main
struct NexusMobileApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

/// The test's home: make a blank board or a board from a PDF, reopen saved boards.
struct HomeView: View {
    @State private var boards: [BoardInfo] = []
    @State private var open: BoardInfo?
    @State private var importing = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { newBlank() } label: { Label("New blank board", systemImage: "square.and.pencil") }
                    Button { importing = true } label: { Label("New board from a PDF…", systemImage: "doc.richtext") }
                }
                Section("Boards") {
                    if boards.isEmpty { Text("No boards yet").foregroundStyle(.secondary) }
                    ForEach(boards) { b in
                        Button { open = b } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name).font(.headline)
                                Text(b.pdfName ?? "Blank board").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { rows in
                        rows.forEach { BoardStore.delete(boards[$0].id) }
                        reload()
                    }
                }
                Section("What to try") {
                    Text("Write fast and slow on a blank board, zoom in and out, and see if the ink keeps up like OneNote or Apple Notes.")
                    Text("Make a board from your longest PDF (a 300-page textbook is ideal). Scroll top to bottom quickly, use Contents to jump to chapters, and write on and beside the pages.")
                    Text("Close and reopen a board: your writing should still be there. Boards are saved in Files › On My iPad › Nexus.")
                    Text("The pen button switches between Pencil only (fingers scroll) and fingers draw too.")
                }
                .font(.callout)
            }
            .navigationTitle("Nexus ink test")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    do {
                        let b = try BoardStore.create(name: url.deletingPathExtension().lastPathComponent, pdf: url)
                        reload()
                        open = b
                    } catch { problem = error.localizedDescription }
                case .failure(let error): problem = error.localizedDescription
                }
            }
            .fullScreenCover(item: $open, onDismiss: reload) { b in
                BoardScreen(board: b) { open = nil }.ignoresSafeArea()
            }
            .alert("Something went wrong", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(problem ?? "") }
            .onAppear(perform: reload)
        }
    }

    private func reload() { boards = BoardStore.list() }

    private func newBlank() {
        let f = DateFormatter()
        f.dateFormat = "d MMM, HH:mm"
        do {
            let b = try BoardStore.create(name: "Board " + f.string(from: Date()), pdf: nil)
            reload()
            open = b
        } catch { problem = error.localizedDescription }
    }
}

/// Hosts the UIKit board (PencilKit lives in UIKit) inside its own navigation bar.
struct BoardScreen: UIViewControllerRepresentable {
    let board: BoardInfo
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = BoardViewController(board: board)
        vc.onClose = onClose
        return UINavigationController(rootViewController: vc)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
