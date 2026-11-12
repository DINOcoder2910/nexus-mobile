import SwiftUI
import NexusCore

@main
struct NexusMobileApp: App {
    @State private var store = NexusStore()
    @State private var sync = SyncService()
    @State private var calendar = CalendarStore()

    init() { WebRender.warmUp() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(sync)
                .environment(calendar)
                .tint(Theme.accent)
        }
    }
}

/// Where the sidebar can take you.
enum Screen: Hashable {
    case today, planner, calendar, tasks, someday, inbox, workstream(String), boards, boardSearch, settings
    /// A notebook's page (its path in the data folder, "notebooks/Chem").
    case notebook(String)
}

/// The shell: the sidebar on the left (where you go), the screen on the right, and the task panel, add sheet and undo bar over both.
struct RootView: View {
    @Environment(NexusStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(CalendarStore.self) private var calendar
    @Environment(\.scenePhase) private var phase
    @State private var screen: Screen? = .today
    @State private var columns = NavigationSplitViewVisibility.all
    /// On the iPhone the sidebar and the screen are one stack: it opens on the screen (Today), with the sidebar one step back.
    @State private var compactColumn = NavigationSplitViewColumn.detail

    var body: some View {
        @Bindable var store = store
        NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
            Sidebar(selection: $screen)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            // an open board takes the detail column, beside the sidebar (its bar shows and hides the sidebar)
            if let target = store.openBoard {
                BoardPanes(main: target, columns: $columns).id(target.id)
            } else {
                NavigationStack {
                    detail
                }
                .id(screen)
            }
        }
        .overlay(alignment: .bottom) { UndoBar().animation(.snappy, value: store.toast) }
        .background {
            AppShortcutKeys(enabled: store.openTaskId == nil && store.capture == nil && store.openBoard == nil,
                            canRun: canRunShortcut, perform: runShortcut)
        }
        .sheet(isPresented: Binding(get: { store.openTaskId != nil }, set: { if !$0 { store.openTaskId = nil } })) {
            if let id = store.openTaskId { TaskDetailView(taskId: id).id(id) }
        }
        .sheet(item: $store.capture) { start in CaptureSheet(start: start) }
        .onChange(of: store.openBoard?.id) { _, now in
            withAnimation { columns = now == nil ? .all : .detailOnly }
        }
        .onChange(of: screen) { _, _ in store.openBoard = nil }
        .alert("Couldn't do that", isPresented: Binding(get: { store.problem != nil }, set: { if !$0 { store.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.problem ?? "") }
        .onChange(of: phase) { _, now in
            switch now {
            case .active:
                store.reloadIfChanged()
                calendar.refreshStatus()
                sync.becameActive()
            case .background:
                sync.enteredBackground()
            default:
                break
            }
        }
        .onChange(of: store.folder) { _, _ in sync.restart() }
        .task {
            sync.attach(store)
            InkBoardMove.runIfNeeded(store)
            // Another writer (sync, the Files app) can change the folder at any time: look every few seconds while open,
            // and let sync send what changed.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if phase == .active, store.reloadIfChanged() { sync.wake() }
            }
        }
    }

    // MARK: the iPad's app-wide keys (Settings › Shortcuts)

    private func canRunShortcut(_ id: String) -> Bool {
        switch id {
        case "app.undo": return store.toast?.change != nil
        case "app.newTask", "app.search", "app.newNotebook": return store.snapshot.isDataFolder
        default: return true
        }
    }

    private func runShortcut(_ id: String) {
        func go(_ s: Screen) { screen = s }
        switch id {
        case "app.today": go(.today)
        case "app.planner": go(.planner)
        case "app.tasks": go(.tasks)
        case "app.notebooks": go(.boardSearch); columns = .all
        case "app.inbox": go(.inbox)
        case "app.someday": go(.someday)
        case "app.settings": go(.settings)
        case "app.sidebar": columns = columns == .detailOnly ? .all : .detailOnly
        case "app.newTask":
            if case .workstream(let w) = screen { store.capture = .init(workstream: w, parent: nil, plan: nil) }
            else { store.capture = .init(workstream: nil, parent: nil, plan: screen == .today ? store.today : nil) }
        case "app.search":
            ShortcutCenter.shared.searchPending = true
            go(.tasks)
        case "app.newNotebook":
            columns = .all
            ShortcutCenter.shared.notebookRequest += 1
        case "app.undo": store.undo()
        default: break
        }
    }

    @ViewBuilder
    private var detail: some View {
        if !store.snapshot.isDataFolder, screen != .boards, screen != .settings, screen != .calendar {
            FolderSetupView()
        } else {
            switch screen ?? .today {
            case .today: TodayView()
            case .planner: PlannerView()
            case .calendar: CalendarView()
            case .tasks: TasksView(lens: .all)
            case .someday: TasksView(lens: .someday)
            case .inbox: WorkstreamView(workstreamId: nil)
            case .workstream(let id): WorkstreamView(workstreamId: id)
            case .boards: BoardsView()
            case .boardSearch: BoardSearchView()
            case .notebook(let path): NotebookPage(path: path, go: { screen = $0 })
            case .settings: SettingsView()
            }
        }
    }
}
