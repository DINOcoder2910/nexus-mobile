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

    init() {
        // the kit's type (Gabarito and Onest), before the first window draws
        KitFonts.register()
        WebRender.warmUp()
        // Applications' Ask Claude opens the Claude chat on its own conversation, with what the page shows
        AppsData.askHandler = { looking, ctx in ClaudeChatSession.open(conversation: "apps", looking: looking, context: { ctx }) }
    }

    var body: some Scene {
        // one kind of window, opened plain or on a board ("Open in a new window"); on the iPad there can be several
        WindowGroup(for: WindowStart.self) { $start in
            WindowRoot(start: start)
                .environment(sync)
                .environment(calendar)
                .environment(reminders)
                .environment(router)
                .tint(Theme.accent)
                // text that names no style of its own is the kit's body type
                .font(.nx(.body))
        }
        .onChange(of: phase) { _, now in appPhase(now) }
        // iOS wakes the app now and then: sync once, read the folder, and give iOS the reminders again
        .backgroundTask(.appRefresh(ReminderCenter.refreshId)) { await refreshInBackground() }
    }

    @MainActor
    private func appPhase(_ now: ScenePhase) {
        HangWatch.note("app phase: \(now)")
        switch now {
        case .active:
            AppServices.start()
            AppServices.store.reloadIfChanged()
            // a timer started on another device, or while Nexus was closed, goes on the Lock Screen now (iOS starts one only in front)
            LiveActivities.refresh()
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
        HangWatch.shared.start(folder: store.folder)
        // the UI check's own freeze, to see that the watcher records one (UITests/PdfPickerTests)
        if ProcessInfo.processInfo.arguments.contains("-NexusTestStall") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                HangWatch.note("test: stalling the main thread for 7 s")
                Thread.sleep(forTimeInterval: 7)
            }
        }
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

/// "Open in a new window" on a board's menu, where there can be several windows (the iPad; nothing on the iPhone).
/// There is no plain "New window" button: it was too easy to press by accident (Nov 12). A new window comes from the system:
/// hold the app's icon › New Window, or Show All Windows › +.
struct NewWindowButton: View {
    var start: WindowStart
    var label = "Open in a new window"
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
    /// Ideas is asked for (the "Add an idea" shortcut that opens the app), with the cursor in its add box.
    var ideas = false
    var focusIdeas = false
    /// The quick page is asked for (the Action button's "Open the Nexus quick page").
    var quick = false
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
    case today, planner, calendar, tasks, someday, inbox, workstream(String), boards, boardSearch, settings, study, ideas, time
    /// Home (the laptop's first screen) and How Nexus works.
    case home, guide
    /// Files: a folder of the data folder ("" is the folder itself).
    case files(String)
    /// The Claude conversation as its own screen (the iPad also has it as a column beside any screen).
    case claude
    /// A notebook's page (its path in the data folder, "notebooks/Chem").
    case notebook(String)
    /// Applications (the tracker and Research), and a school's page by its workstream id.
    case applications, school(String)
    /// Recordings: meetings, classes and filmed classes, transcribed here and prepared by Claude for review.
    case recordings
    /// Drop: files sent between your devices through the hub (Drop/ at the data folder's top).
    case drop
    /// A subject's page (a workstream in the new look: its next tasks, notebooks, study and files), and its Study page.
    case subject(String), studyPage(String)
    /// A Spanish subject's Oral practice page (Today's From Study oral card).
    case oralPage(String)
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
    /// The iPhone's tab bar: the tab, and each tab's stack.
    @State private var tab: PhoneTab = .today
    @State private var todayPath: [Screen] = []
    @State private var calendarPath: [Screen] = []
    @State private var inboxPath: [Screen] = []
    @State private var subjectsPath: [Screen] = []
    @State private var morePath: [Screen] = []
    @State private var quickOpen = false

    var body: some View {
        @Bindable var store = store
        shell
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
        .onChange(of: screen) { _, now in
            guard let now else { return }
            if !Device.isPhone && ClaudeChatSession.shared.presented == "main" { ClaudeChatSession.shared.conversation("main").looking = lookingName(now) }
            store.openBoard = nil
            // the iPhone has no selection: the screen goes to its tab, and the ask is cleared so the same one works again
            if Device.isPhone { showOnPhone(now); screen = nil }
        }
        .alert("Couldn't do that", isPresented: Binding(get: { store.problem != nil }, set: { if !$0 { store.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(store.problem ?? "") }
        .onChange(of: phase) { _, now in
            HangWatch.note("window phase: \(now)")
            if now == .active {
                router.front = windowId
                store.reloadIfChanged()
                answerRouter()
            }
        }
        // the Live Activity's links (nexus://task/<id>, nexus://recordings, nexus://snap; NexusLive)
        .onOpenURL { url in
            guard url.scheme == "nexus" else { return }
            switch url.host {
            case "task":
                let id = url.pathComponents.dropFirst().joined(separator: "/")
                if store.task(id) != nil { store.openTaskId = id }
            case "recordings": screen = .recordings
            case "today": screen = .today
            // Snap on a recording's Live Activity: the camera (filming: this moment marked for a picture from the film)
            case "snap": RecordingService.shared.snap()
            default: break
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
        .onChange(of: router.ideas) { _, _ in answerRouter() }
        .onChange(of: router.quick) { _, _ in answerRouter() }
        // the quick page (the Action button), over everything; recording shows its bar on every screen
        .fullScreenCover(isPresented: $quickOpen) { QuickPage(close: { quickOpen = false }).environment(store).recordingCovers(pill: false) }
        .recordingCovers(pill: !Device.isPhone && screen != .recordings)
        // the UI check's Spanish demo, with the folder (here, not in the sidebar: the iPhone shows its sidebar only under More)
        .task(id: store.snapshot.loadedAt) { SpanishDemo.prepare(store) }
        .task {
            AppServices.start()
            if router.front == nil { router.front = windowId }
            if case .board(let path)? = start { store.openBoard = .init(path: path) }
            answerRouter()
            InkBoardMove.runIfNeeded(store)
            TestHooks.run(store)
            RecordingDemo.atStart(store)
            RecordingService.shared.resume()
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

    /// The iPad: the sidebar and the screen. The iPhone: a tab bar (Today, Calendar, Inbox, Notebooks, More).
    @ViewBuilder
    private var shell: some View {
        if Device.isPhone { phoneTabs } else { split }
    }

    private var split: some View {
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
                        .toolbar {
                            // the laptop's pinned Claude column (Ctrl+Shift+J): the conversation beside the screen
                            if screen != .claude && store.snapshot.isDataFolder {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {
                                        if claude.presented == nil { ClaudeChatSession.open(looking: lookingName(screen ?? .today)) } else { claude.presented = nil }
                                    } label: {
                                        Label("Claude", systemImage: claude.presented == nil ? "sparkles" : "sparkles.rectangle.stack.fill")
                                    }
                                    .accessibilityIdentifier("claude-column")
                                }
                            }
                        }
                }
                .id(screen)
                .inspector(isPresented: Binding(get: { claude.presented != nil && screen != .claude }, set: { if !$0 { claude.presented = nil } })) {
                    // its own header row in view (an inspector's toolbar items would join the screen's toolbar, even while it is closed)
                    Group {
                        if let key = claude.presented {
                            ClaudeChatView(conversation: key, onClose: { claude.presented = nil }, inColumn: true)
                        }
                    }
                    .inspectorColumnWidth(min: 320, ideal: 400, max: 520)
                }
            }
        }
        .overlay(alignment: .bottom) { UndoBar().animation(.snappy, value: store.toast) }
    }

    private var claude: ClaudeChatSession { .shared }

    /// What Claude is told the user is looking at, for a screen.
    private func lookingName(_ s: Screen) -> String {
        switch s {
        case .today: return "Today"
        case .planner: return "the Planner (this week)"
        case .calendar: return "the Calendar"
        case .tasks: return "Tasks"
        case .someday: return "Someday"
        case .inbox: return "the Inbox (inbox.yaml)"
        case .workstream(let id): return store.workstream(id).map { "\($0.name) (\($0.folder))" } ?? id
        case .boards, .boardSearch: return "Notebooks"
        case .notebook(let path): return "the notebook \(path)"
        case .settings: return "Settings"
        case .study: return "Study"
        case .ideas: return "Ideas"
        case .time: return "Time (tracked time)"
        case .claude: return "Claude"
        case .applications: return "Applications"
        case .school(let id): return store.workstream(id).map { "\($0.name)'s page in Applications (\($0.folder))" } ?? id
        case .home: return "Home"
        case .guide: return "How Nexus works"
        case .files(let path): return path.isEmpty ? "Files (the data folder)" : "Files: \(path)"
        case .recordings: return "Recordings (recordings/)"
        case .drop: return "Drop (files sent between your devices, Drop/)"
        case .subject(let id): return store.workstream(id).map { "\($0.name)'s page (\($0.folder))" } ?? id
        case .studyPage(let id): return store.workstream(id).map { "\($0.name)'s Study (\($0.folder)/study)" } ?? id
        case .oralPage(let id): return store.workstream(id).map { "\($0.name)'s Oral practice (\($0.folder)/study/spanish/oral)" } ?? id
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
        if router.ideas {
            router.ideas = false
            router.focusIdeas = true
            quickOpen = false
            screen = .ideas
        }
        if router.quick {
            router.quick = false
            quickOpen = true
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
            else if case .school(let w) = screen { store.capture = .init(workstream: w, parent: nil, plan: nil) }
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
        screenView(screen ?? .today, go: { screen = $0 })
    }

    /// One screen. `go` is where a link inside it goes (the split view's selection, or a push on the iPhone's tab).
    @ViewBuilder
    private func screenView(_ s: Screen, go: @escaping (Screen) -> Void) -> some View {
        if !store.snapshot.isDataFolder, s != .boards, s != .settings, s != .calendar, s != .guide {
            FolderSetupView()
        } else {
            switch s {
            case .today: TodayView(go: go)
            case .home: HomeView(go: go)
            case .files(let path): FilesView(path: path, go: go)
            case .guide: GuideView()
            case .planner: PlannerView()
            case .calendar: CalendarView()
            case .tasks: TasksView(lens: .all)
            case .someday: TasksView(lens: .someday)
            case .inbox: WorkstreamView(workstreamId: nil)
            case .workstream(let id): WorkstreamView(workstreamId: id)
            case .boards: BoardsView()
            case .boardSearch: BoardSearchView()
            case .notebook(let path): NotebookPage(path: path, go: go)
            case .settings: SettingsView()
            case .study: StudyHome()
            case .applications: ApplicationsView(go: go)
            case .school(let id): SchoolPage(id: id, go: go)
            case .ideas: IdeasView()
            case .time: TimeView()
            case .claude: ClaudeChatView()
            case .recordings: RecordingsView()
            case .drop: DropView()
            case .subject(let id): SubjectPage(workstreamId: id, go: go)
            case .studyPage(let id): StudyPage(workstreamId: id)
            case .oralPage(let id): OralPage(workstreamId: id)
            }
        }
    }

    // MARK: the iPhone: a tab bar

    enum PhoneTab: Hashable { case today, calendar, inbox, subjects, more }

    private var phoneTabs: some View {
        TabView(selection: $tab) {
            phoneStack(.today, $todayPath) { screenView(.today, go: { todayPath.append($0) }) }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(PhoneTab.today)
            phoneStack(.calendar, $calendarPath) { screenView(.calendar, go: { calendarPath.append($0) }) }
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(PhoneTab.calendar)
            phoneStack(.inbox, $inboxPath) { screenView(.inbox, go: { inboxPath.append($0) }) }
                .tabItem { Label("Inbox", systemImage: "tray") }
                .badge(store.snapshot.isDataFolder ? store.planning.openCount(nil) : 0)
                .tag(PhoneTab.inbox)
            // the new look's Subjects tab: each subject opens its page; every notebook below them
            phoneStack(.subjects, $subjectsPath) {
                Sidebar(selection: .constant(nil), pushes: true, subjectsTab: true, title: "Subjects")
            }
            .tabItem { Label("Subjects", systemImage: "books.vertical") }
            .tag(PhoneTab.subjects)
            // More is every screen, the ones in the tab bar too (the sidebar as a list)
            phoneStack(.more, $morePath) {
                Sidebar(selection: .constant(nil), pushes: true, title: "More")
            }
            .tabItem { Label("More", systemImage: "ellipsis.circle") }
            .tag(PhoneTab.more)
        }
        // Claude opened from a screen (Today's menu, a task, Plan with Claude's result): a sheet over the tabs
        .sheet(isPresented: Binding(get: { ClaudeChatSession.shared.presented != nil }, set: { if !$0 { ClaudeChatSession.shared.presented = nil } })) {
            NavigationStack {
                ClaudeChatView(conversation: ClaudeChatSession.shared.presented ?? "main", onClose: { ClaudeChatSession.shared.presented = nil })
            }
            .environment(store)
        }
        // a board takes the whole phone; its sidebar button (and Close) go back to the tabs
        .fullScreenCover(item: Binding(get: { store.openBoard }, set: { store.openBoard = $0 })) { target in
            BoardPanes(main: target, columns: Binding(get: { .detailOnly }, set: { if $0 != .detailOnly { store.openBoard = nil } }))
        }
    }

    /// A tab's stack: its screens push onto it, with the undo bar and the floating + over it (above the tab bar).
    private func phoneStack<Root: View>(_ which: PhoneTab, _ path: Binding<[Screen]>, @ViewBuilder _ root: () -> Root) -> some View {
        let content = root()
        return NavigationStack(path: path) {
            content.navigationDestination(for: Screen.self) { s in
                screenView(s, go: { path.wrappedValue.append($0) })
            }
        }
        .overlay(alignment: .bottomTrailing) {
            // the Calendar has its own + (a new event) in its bottom bar; Claude has its box and send button there
            if which != .calendar && path.wrappedValue.last != .claude && store.snapshot.isDataFolder && store.snapshot.readOnlyReason == nil {
                Button { addFrom(which, path.wrappedValue.last) } label: {
                    Image(systemName: "plus")
                        .font(.nx(.title2, .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Theme.accent, in: Circle())
                        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                }
                .accessibilityLabel("Add a task")
                .padding(.trailing, 18)
                .padding(.bottom, store.toast == nil ? 18 : 84)
                .animation(.snappy, value: store.toast == nil)
            }
        }
        // a recording (not on Recordings, which has its own Stop) and the running timer, over every tab (Snap, Stop; the timer's task opens on a tap)
        .overlay(alignment: .bottomLeading) {
            let recording = RecordingService.shared.active.map { !$0.filming } == true && path.wrappedValue.last != .recordings
            let timing = store.snapshot.isDataFolder && TimeTracker.shared.current != nil
            if (recording || timing) && path.wrappedValue.last != .claude {
                VStack(alignment: .leading, spacing: 8) {
                    if recording { RecordingPill() }
                    if timing { RunningTimerPill().transition(.move(edge: .bottom).combined(with: .opacity)) }
                }
                .padding(.leading, 16)
                .padding(.trailing, 92)
                .padding(.bottom, (store.toast == nil ? 22 : 88) + (which == .calendar ? 56 : 0))
                .animation(.snappy, value: store.toast == nil)
                .animation(.snappy, value: recording)
            }
        }
        .overlay(alignment: .bottom) { UndoBar().animation(.snappy, value: store.toast) }
    }

    /// The floating +: into the workstream on screen, planned today on Today, else the Inbox.
    private func addFrom(_ which: PhoneTab, _ top: Screen?) {
        if case .workstream(let w)? = top { store.capture = .init(workstream: w, parent: nil, plan: nil); return }
        if case .school(let w)? = top { store.capture = .init(workstream: w, parent: nil, plan: nil); return }
        store.capture = .init(workstream: nil, parent: nil, plan: which == .today && top == nil ? store.today : nil)
    }

    /// A screen asked for from elsewhere (a Spotlight result, a key): the tab that has it, or pushed on More.
    private func showOnPhone(_ s: Screen) {
        switch s {
        case .today: tab = .today; todayPath = []
        case .calendar: tab = .calendar; calendarPath = []
        case .inbox: tab = .inbox; inboxPath = []
        case .notebook, .boardSearch, .boards, .subject: tab = .subjects; subjectsPath = [s]
        default: tab = .more; morePath = [s]
        }
    }
}
