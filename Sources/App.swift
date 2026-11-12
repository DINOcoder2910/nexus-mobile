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
        .onChange(of: phase) { _, now in appPhase(now) }
        // iOS wakes the app now and then: sync once, read the folder, and give iOS the reminders again
        .backgroundTask(.appRefresh(ReminderCenter.refreshId)) { await refreshInBackground() }
    }

    @MainActor
    private func appPhase(_ now: ScenePhase) {
        switch now {
        case .active:
            AppServices.start()
            AppServices.store.reloadIfChanged()
            calendar.refreshStatus()
            sync.becameActive()
            Task { await reminders.refreshStatus() }
        case .background:
            sync.enteredBackground()
            ReminderCenter.scheduleRefresh()
        default:
            break
        }
    }

    @MainActor
    private func refreshInBackground() async {
        ReminderCenter.scheduleRefresh()
        AppServices.start()
        await sync.backgroundCycle(AppServices.store)
        AppServices.store.reloadIfChanged()
        reminders.reschedule()
    }
}

/// The app's services, made once. The windows get them through the environment; an App Intent (Siri, Shortcuts, the Action
/// button) runs in the same process and reaches them here. `store` is the shared store: sync, reminders and Spotlight follow it,
/// and each window's own store keeps in step with it (NexusStore's notices).
@MainActor
enum AppServices {
    static let store = NexusStore()
    static let sync = SyncService()
    static let calendar = CalendarStore()
    static let reminders = ReminderCenter()
    private static var started = false

    /// Wires them together once (the first window, or a launch straight into the background).
    static func start() {
        guard !started else { return }
        started = true
        sync.attach(store)
        reminders.attach(store, calendar)
        SpotlightIndex.update(store)
        store.onReload = {
            reminders.reschedule()
            SpotlightIndex.update(store)
        }
    }
}

/// What a new window opens on: Today (each its own, so a second ask opens another), or a board (asking again brings that one forward).
enum WindowStart: Hashable, Codable {
    case plain(UUID)
    case board(String)

    /// A plain window asked for again gets a new id, so it is a new window.
    var fresh: WindowStart {
        if case .plain = self { return .plain(UUID()) }
        return self
    }
}

/// "New window" and "Open in a new window", where there can be several windows (the iPad; nothing on the iPhone).
struct NewWindowButton: View {
    var start: WindowStart = .plain(UUID())
    var label = "New window"
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multiple

    var body: some View {
        if multiple {
            Button { openWindow(value: start.fresh) } label: { Label(label, systemImage: "macwindow.badge.plus") }
        }
    }
}

/// Asks from outside a window (a tapped reminder, Siri's "New Nexus task") that one window should answer: the one in front last.
@MainActor
@Observable
final class WindowRouter {
    static let shared = WindowRouter()
    /// The window used last.
    var front: UUID?
    /// A task to open.
    var openTask: String?
    /// The add sheet is asked for.
    var addSheet = false
}

/// One window: its own store (its task panel, add sheet, Undo and open board), on the shared data folder.
struct WindowRoot: View {
    let start: WindowStart?
    @State private var store = NexusStore()

    var body: some View {
        RootView(start: start)
            .environment(store)
    }
}

/// Where the sidebar can take you.
enum Screen: Hashable {
    case today, planner, calendar, tasks, someday, inbox, workstream(String), boards, boardSearch, settings, study
    /// A notebook's page (its path in the data folder, "notebooks/Chem").
    case notebook(String)
}

/// The shell: the sidebar on the left (where you go), the screen on the right, and the task panel, add sheet and undo bar over both.
struct RootView: View {
    var start: WindowStart? = nil
    @Environment(NexusStore.self) private var store
    @Environment(SyncService.self) private var sync
    @Environment(CalendarStore.self) private var calendar
    @Environment(ReminderCenter.self) private var reminders
    @Environment(WindowRouter.self) private var router
    /// This window's phase.
    @Environment(\.scenePhase) private var phase
    @State private var screen: Screen? = .today
    @State private var columns = NavigationSplitViewVisibility.all
    /// On the iPhone the sidebar and the screen are one stack: it opens on the screen (Today), with the sidebar one step back.
    @State private var compactColumn = NavigationSplitViewColumn.detail
    /// This window, for the asks that only one window should answer.
    @State private var windowId = UUID()

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
        // the reminders follow the calendars too (the files: AppServices.start)
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
            // and tell the other stores (and sync) what changed.
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
            case .study: StudyHome()
            }
        }
    }
}
