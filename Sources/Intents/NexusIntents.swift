import AppIntents
import SwiftUI
import NexusCore

/// Adding to Nexus from anywhere: Siri ("Add to Nexus"), the Shortcuts app, the Action button and Spotlight run these in the
/// app's own process (no extension, so nothing extra to sign when sideloading). The line is read as the add sheet reads it.
struct AddToNexusIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Nexus"
    static let description = IntentDescription("Adds a task the way the add box reads it: “physics sheet by fri 45m #physics”.")
    static let openAppWhenRun = false

    @Parameter(title: "Task", requestValueDialog: "What should I add?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to Nexus") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store
        let sync = AppServices.sync
        store.reloadIfChanged()
        let added = QuickAdd.add(text, store: store)
        guard let added else {
            return .result(dialog: IntentDialog(stringLiteral: store.problem ?? "Couldn't add that. Is the Nexus folder set up?"))
        }
        // send it to the hub now: the app may go back to sleep straight after
        await sync.backgroundCycle(store)
        return .result(dialog: IntentDialog(stringLiteral: "Added “\(added.title)” to \(added.place)."))
    }
}

/// Opens the add sheet (for the Action button when typing is easier than speaking).
struct OpenAddSheetIntent: AppIntent {
    static let title: LocalizedStringResource = "New Nexus task"
    static let description = IntentDescription("Opens Nexus on the add sheet.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WindowRouter.shared.addSheet = true
        return .result()
    }
}

struct NexusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToNexusIntent(),
                    phrases: ["Add to \(.applicationName)", "Add a task to \(.applicationName)", "Capture in \(.applicationName)",
                              "New \(.applicationName) task"],
                    shortTitle: "Add to Nexus", systemImageName: "plus.circle")
        AppShortcut(intent: OpenAddSheetIntent(),
                    phrases: ["Open the \(.applicationName) add sheet", "Type a task in \(.applicationName)"],
                    shortTitle: "New task", systemImageName: "square.and.pencil")
    }
}

/// One line added as the add sheet adds it: the laptop's capture reading (dates, times, estimate, ★, #workstream, `; subtasks`),
/// landing where the sheet would put it.
@MainActor
enum QuickAdd {
    static func add(_ line: String, store: NexusStore) -> (title: String, place: String)? {
        guard store.snapshot.isDataFolder, store.snapshot.readOnlyReason == nil else { return nil }
        let p = CaptureParse.parseLine(line, in: store.snapshot, today: store.today, plan: nil, commands: false)
        guard p.kind == .task, p.ok else { return nil }
        let l = CaptureParse.land(p, in: store.snapshot)
        let ws = l.workstream?.id
        guard let id = store.add(title: p.title, workstream: ws, due: p.facts.due, plan: p.facts.planEntries, key: p.facts.key, est: p.facts.est,
                                 extras: p.facts)
        else { return nil }
        for s in p.subtasksToAdd {
            store.add(title: s.title, workstream: ws, parent: store.task(id), due: s.facts.due, plan: s.facts.planEntries,
                      key: s.facts.key, est: s.facts.est, extras: s.facts)
        }
        return (p.title, l.workstream?.name ?? "the Inbox")
    }
}
