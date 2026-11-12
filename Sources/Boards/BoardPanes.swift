import SwiftUI
import NexusCore

/// The open board in the app's detail column, beside the sidebar (the board's bar shows and hides the sidebar). Side by side lives
/// inside it (SideBySide.swift).
struct BoardPanes: View {
    @Environment(NexusStore.self) private var store
    let main: NexusStore.BoardTarget
    @Binding var columns: NavigationSplitViewVisibility

    var body: some View {
        BoardHost(target: main, root: store.folder, store: store, onClose: { store.openBoard = nil }, onSaved: { path in
            store.boardsChanged()
            HandwritingIndex.shared.refresh(board: path, root: store.folder)
        }, onSidebar: {
            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
        })
        .id(main.id)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}
