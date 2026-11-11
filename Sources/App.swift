import SwiftUI
import NexusCore

@main
struct NexusMobileApp: App {
    @State private var store = NexusStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.accent)
        }
    }
}

/// Where the sidebar can take you.
enum Screen: Hashable {
    case today, planner, tasks, someday, inbox, workstream(String), boards, settings
}

/// The shell: the sidebar on the left (where you go), the screen on the right, and the task panel, add sheet and undo bar over both.
struct RootView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var screen: Screen? = .today
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(selection: $screen)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            NavigationStack {
                detail
            }
            .id(screen)
        }
        .overlay(alignment: .bottom) { UndoBar().animation(.snappy, value: store.toast) }
        .sheet(isPresented: Binding(get: { store.openTaskId != nil }, set: { if !$0 { store.openTaskId = nil } })) {
            if let id = store.openTaskId { TaskDetailView(taskId: id).id(id) }
        }
        .sheet(item: $store.capture) { start in CaptureSheet(start: start) }
        .alert("Couldn't do that", isPresented: Binding(get: { store.problem != nil }, set: { if !$0 { store.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.problem ?? "") }
        .onChange(of: phase) { _, now in if now == .active { store.reloadIfChanged() } }
        .task {
            // Another writer (sync, the Files app) can change the folder at any time: look every few seconds while open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if phase == .active { store.reloadIfChanged() }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !store.snapshot.isDataFolder, screen != .boards, screen != .settings {
            FolderSetupView()
        } else {
            switch screen ?? .today {
            case .today: TodayView()
            case .planner: PlannerView()
            case .tasks: TasksView(lens: .all)
            case .someday: TasksView(lens: .someday)
            case .inbox: WorkstreamView(workstreamId: nil)
            case .workstream(let id): WorkstreamView(workstreamId: id)
            case .boards: BoardsView()
            case .settings: SettingsView()
            }
        }
    }
}
