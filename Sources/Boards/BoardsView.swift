import SwiftUI
import UniformTypeIdentifiers

/// The boards from the ink test, kept so nothing you wrote is lost. Notebooks and sections in the laptop's board format replace this next.
struct BoardsView: View {
    @State private var boards: [BoardInfo] = []
    @State private var open: BoardInfo?
    @State private var importing = false
    @State private var problem: String?

    var body: some View {
        List {
            Section {
                Button { newBlank() } label: { Label("New blank board", systemImage: "square.and.pencil") }
                Button { importing = true } label: { Label("New board from a PDF…", systemImage: "doc.richtext") }
            }
            Section {
                if boards.isEmpty { Text("No boards yet").foregroundStyle(.secondary) }
                ForEach(boards) { b in
                    Button { open = b } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.name).font(.headline).foregroundStyle(.primary)
                            Text((b.pdfName ?? "Blank board") + " · " + b.modified.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { rows in
                    rows.forEach { BoardStore.delete(boards[$0].id) }
                    reload()
                }
            } header: { Text("Boards") } footer: {
                Text("These are the ink test's boards. Notebooks and sections, typing mixed with ink and the laptop's board format come next; these boards will move over then.")
            }
        }
        .navigationTitle("Boards")
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
