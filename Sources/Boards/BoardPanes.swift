import SwiftUI
import NexusCore

/// The open board in the app's detail column, beside the sidebar (the board's bar shows and hides the sidebar). Side by side lives
/// inside it (SideBySide.swift); this view gives it the app's screens (Today, the Calendar) with the app's environment.
struct BoardPanes: View {
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var calendar
    @Environment(SyncService.self) private var sync
    let main: NexusStore.BoardTarget
    @Binding var columns: NavigationSplitViewVisibility

    var body: some View {
        BoardHost(target: main, root: store.folder, store: store, onClose: { store.openBoard = nil }, onSaved: { path in
            store.boardsChanged()
            HandwritingIndex.shared.refresh(board: path, root: store.folder)
        }, onSidebar: {
            withAnimation { columns = columns == .detailOnly ? .all : .detailOnly }
        }, makeScreen: { screen, close in
            let host = UIHostingController(rootView: SidePaneScreen(screen: screen, close: close)
                .environment(store).environment(calendar).environment(sync).tint(Theme.accent))
            // half the iPad's width: the screens lay out as they do on a narrow screen (the Planner stacks its days, and so on)
            host.traitOverrides.horizontalSizeClass = .compact
            return host
        })
        .id(main.id)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// An app screen in Side by side's second pane, in its own navigation, with a button to close the pane.
struct SidePaneScreen: View {
    let screen: SideScreen
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .today: TodayView()
                case .calendar: CalendarView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close this pane")
                }
            }
        }
    }
}
