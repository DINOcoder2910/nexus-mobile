import SwiftUI
import CoreSpotlight
import NexusCore

@main
struct NexusMobileApp: App {
    // shared by every window, also reached by Siri and Shortcuts (AppServices); each window has its own NexusStore (WindowRoot)
    @State private var sync = AppServices.sync
    @State private var calendar = AppServices.calendar
    @State private var reminders = AppServices.reminders
    @State private var router = WindowRouter.shared
    /// The app as a whole (all its windows): sync runs while any window is in front.
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        // one kind of window, opened plain or on a board ("Open in a new window"); on the iPad there can be several
        WindowGroup(for: WindowStart.self) { $start in
            WindowRoot(start: start)
                .environment(sync)
                .environment(calendar)
                .environment(reminders)
                .environment(router)
                .tint(Theme.accent)
        }
        .onChange(of: phase) { _, now in
            if now == .active {
                router.front = windowId
                store.reloadIfChanged()
                answerRouter()
            }
        }
        // a Spotlight result: a task, a workstream or a board
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let hit = SpotlightIndex.target(activity) else { return }
            let value = hit.value
            switch hit.kind {
            case "task": if store.task(value) != nil { store.openTaskId = value }
            case "ws": screen = .workstream(value)
            case "board": store.openBoard = .init(path: value)
            default: break
            }
        }
        .onChange(of: calendar.version) { _, _ in reminders.reschedule() }
        .onChange(of: router.openTask) { _, _ in answerRouter() }
        .onChange(of: router.addSheet) { _, _ in answerRouter() }
        .task {
            AppServices.start()
            if router.front == nil { router.front = windowId }
            if case .board(let path)? = start { store.openBoard = .init(path: path) }
            answerRouter()
            InkBoardMove.runIfNeeded(store)
            // Another writer (sync, the Files app) can change the folder at any time: look every few seconds while open,
            // and tell the other stores (and so sync) what changed.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if phase == .active, store.reloadIfChanged() {
                    NotificationCenter.default.post(name: NexusStore.readAgain, object: store)
                    sync.wake()
                }
            }
        }
    }

    /// A reminder tapped or Siri's add sheet: the window in front answers.
    private func answerRouter() {
        guard router.front == windowId || router.front == nil else { return }
        if let id = router.openTask {
            router.openTask = nil
            if store.task(id) != nil { store.openTaskId = id }
        }
        if router.addSheet {
            router.addSheet = false
            store.capture = .init(workstream: nil, parent: nil, plan: nil)
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
