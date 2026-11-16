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

/// An idea into Ideas without opening the app (Siri: "Add an idea to Nexus", the Action button): dictate it, it is saved as written
/// and sent to the hub; Claude sorts it with the next batch (on the laptop, a few minutes later).
struct AddIdeaIntent: AppIntent {
    static let title: LocalizedStringResource = "Add an idea to Nexus"
    static let description = IntentDescription("Saves an idea in Nexus's Ideas, as you said it. Claude sorts it into a topic later.")
    static let openAppWhenRun = false

    @Parameter(title: "Idea", requestValueDialog: "What's the idea?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to Nexus's Ideas") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppServices.start()
        let store = AppServices.store
        store.reloadIfChanged()
        guard IdeasFile.add(text, store: store) else {
            return .result(dialog: IntentDialog(stringLiteral: store.problem ?? "Couldn't save that idea. Is the Nexus folder set up?"))
        }
        await AppServices.sync.backgroundCycle(store)
        return .result(dialog: IntentDialog(stringLiteral: "Saved in Ideas. Claude sorts it in a few minutes."))
    }
}

/// Opens Ideas with the keyboard up (for the Action button when typing or the keyboard's dictation suits better).
struct OpenIdeasIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Nexus Ideas"
    static let description = IntentDescription("Opens Nexus on Ideas, ready to type or dictate an idea.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WindowRouter.shared.ideas = true
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
        AppShortcut(intent: AddIdeaIntent(),
                    phrases: ["Add an idea to \(.applicationName)", "New idea in \(.applicationName)", "Save an idea in \(.applicationName)"],
                    shortTitle: "Add an idea", systemImageName: "lightbulb")
        AppShortcut(intent: OpenIdeasIntent(),
                    phrases: ["Open \(.applicationName) ideas", "Type an idea in \(.applicationName)"],
                    shortTitle: "Ideas", systemImageName: "lightbulb.max")
    }
}

/// One idea added to nexus-ideas.yaml from outside the Ideas screen (the shortcut): read, add as written, write whole (Ideas.swift).
@MainActor
enum IdeasFile {
    static func add(_ text: String, store: NexusStore) -> Bool {
        guard store.snapshot.isDataFolder, store.snapshot.readOnlyReason == nil else { return false }
        let file = store.folder.appendingPathComponent(Ideas.file)
        let parsed: Ideas.Parsed
        if let cur = try? FolderAccess.read(file) { parsed = Ideas.parse(cur) }
        else { parsed = Ideas.parse(nil, todo: try? FolderAccess.read(store.folder.appendingPathComponent(Ideas.todoFile))) }
        if let e = parsed.error { store.problem = Ideas.file + " " + e + ", so the idea wasn't saved."; return false }
        let next = Ideas.add(parsed.items, text, today: Days.today(), now: Ideas.stamp(), from: Device.name)
        guard next != parsed.items else { return false }
        do { try FolderAccess.write(file, Ideas.serialize(next)); store.didWrite(); return true } catch { store.problem = "Couldn't save \(Ideas.file): \(error.localizedDescription)"; return false }
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
