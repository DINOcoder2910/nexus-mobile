import SwiftUI
import NexusCore

/// The bar that says what just changed, with Undo (and "Tick it" when the last subtask of a task was ticked). It goes after a few seconds.
struct UndoBar: View {
    @Environment(NexusStore.self) private var store

    var body: some View {
        if let toast = store.toast {
            HStack(spacing: 14) {
                Text(toast.offerParent.flatMap { store.task($0) }.map { "All subtasks done. Tick “\($0.text)” too?" } ?? toast.message)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if toast.offerParent != nil {
                    Button("Tick it") { store.tickOfferedParent() }.fontWeight(.semibold)
                }
                if toast.change != nil {
                    Button("Undo") { store.undo() }.fontWeight(.semibold)
                }
                Button { store.toast = nil } label: { Image(systemName: "xmark").imageScale(.small) }
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.bottom, 18)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(toast.offerParent == nil ? 5 : 8))
                if store.toast?.id == toast.id { withAnimation { store.toast = nil } }
            }
        }
    }
}
