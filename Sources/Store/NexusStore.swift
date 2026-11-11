import SwiftUI
import NexusCore

/// The one place the screens read the data folder from and send edits to. Every edit is a line-level patch of one task file
/// (NexusCore's TaskEditor); after it the folder is read again, so what the screens show is always what the files say.
@Observable
final class NexusStore {
    private(set) var snapshot: Snapshot
    private(set) var today: String
    private(set) var folder: URL
    private(set) var pickedFolder: Bool
    private var fingerprint = ""

    /// The last edit, for the undo bar.
    var toast: Toast?
    /// An edit that could not be made, shown as an alert.
    var problem: String?
    /// The task whose panel is open.
    var openTaskId: String?
    /// The capture sheet, with what it starts from.
    var capture: CaptureStart?
    /// Called after the app wrote to the data folder (sync sends it soon after).
    @ObservationIgnored var onWrite: (() -> Void)?
    /// The board open over everything (full screen), and where to look first.
    var openBoard: BoardTarget?
    /// Goes up when a notebook, section or board was made, renamed or removed, so the lists read the folder again.
    var notebooksVersion = 0

    struct BoardTarget: Identifiable {
        let id = UUID()
        /// The board folder, relative to the data folder ("notebooks/Chem/R3/Lesson 1.board").
        var path: String
        /// A place on the board (board units) to show first, e.g. a search hit.
        var focus: CGRect?
    }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var message: String
        var change: Change?
        /// "All subtasks done. Tick “X” too?"
        var offerParent: String?
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    struct CaptureStart: Identifiable {
        let id = UUID()
        var workstream: String?
        var parent: String?
        var plan: String?
    }

    init() {
        let (url, picked) = FolderAccess.current()
        folder = url
        pickedFolder = picked
        today = Days.today()
        snapshot = DataFolder.load(url)
        fingerprint = DataFolder.fingerprint(url)
    }

    var planning: Planning { Planning(snapshot, today: today) }
    var editor: TaskEditor { TaskEditor(root: folder, read: FolderAccess.read, write: FolderAccess.write) }
    var folderName: String { pickedFolder ? folder.lastPathComponent : "On My iPad › Nexus › nexus-data" }

    // MARK: reading

    /// Reads the folder again (after an edit, on coming back to the app, or when the files changed underneath).
    func reload() {
        today = Days.today()
        snapshot = DataFolder.load(folder)
        fingerprint = DataFolder.fingerprint(folder)
    }

    /// Cheap check for another writer; reloads only when something changed. True when the files changed.
    @discardableResult
    func reloadIfChanged() -> Bool {
        let now = DataFolder.fingerprint(folder)
        let changed = now != fingerprint
        if changed || Days.today() != today { reload() }
        return changed
    }

    func useFolder(_ url: URL) {
        do { try FolderAccess.pick(url) } catch { problem = "Couldn't keep access to that folder: \(error.localizedDescription)"; return }
        folder = url; pickedFolder = true
        reload()
    }

    func useDefaultFolder() {
        FolderAccess.useDefault()
        let (url, picked) = FolderAccess.current()
        folder = url; pickedFolder = picked
        reload()
    }

    /// A board (or a notebook) was written: let sync send it.
    func boardsChanged(listChanged: Bool = false) {
        if listChanged { notebooksVersion += 1 }
        onWrite?()
    }

    func makeSample() {
        do { try SampleFolder.make(at: folder, today: today) } catch { problem = error.localizedDescription }
        reload()
        onWrite?()
    }

    // MARK: lookups for the screens

    func task(_ id: String?) -> NexusTask? { id.flatMap { snapshot.tasks[$0] } }
    func workstream(_ id: String?) -> Workstream? { id.flatMap { snapshot.workstreams[$0] } }
    func workstreamName(_ t: NexusTask) -> String { workstream(t.workstream)?.name ?? "Inbox" }
    func color(_ t: NexusTask) -> Color { color(workstream: t.workstream) }
    func color(workstream id: String?) -> Color {
        guard let w = workstream(id) else { return .secondary }
        return Theme.workstream(w.color, key: w.id)
    }
    func canEdit(_ t: NexusTask) -> Bool { t.hasId && snapshot.canEdit(t.file) }
    func open(_ t: NexusTask) { openTaskId = t.id }

    // MARK: edits (each reloads and shows the undo bar)

    private func perform(_ make: (TaskEditor, Snapshot) throws -> Change) {
        do {
            let c = try make(editor, snapshot)
            reload()
            onWrite?()
            toast = Toast(message: c.message, change: c, offerParent: c.offerParent)
        } catch {
            problem = "\(error)"
            reload()
        }
    }

    /// Done or not done.
    func toggleDone(_ t: NexusTask) {
        if t.done { perform { try $0.untick(t, in: $1) } } else { perform { try $0.tick(t, in: $1, today: today) } }
    }

    func plan(_ t: NexusTask, on day: String, time: String? = nil) { perform { try $0.plan(t, on: day, time: time, in: $1) } }
    func unplan(_ t: NexusTask, from day: String) { perform { try $0.unplan(t, from: day, in: $1) } }
    func setPlan(_ t: NexusTask, _ plan: [PlanEntry]) { perform { try $0.setPlan(t, plan, in: $1) } }
    /// Moves a planned day (the Planner's drag); `from` nil adds the day.
    func move(_ t: NexusTask, from: String?, to: String) { perform { try $0.move(t, from: from, to: to, in: $1) } }
    func setDue(_ t: NexusTask, _ day: String?) { perform { try $0.setDue(t, day, in: $1) } }
    func setKey(_ t: NexusTask, _ on: Bool) { perform { try $0.setKey(t, on, in: $1) } }
    func setSomeday(_ t: NexusTask, _ on: Bool) { perform { try $0.setSomeday(t, on, in: $1) } }
    func setTitle(_ t: NexusTask, _ title: String) { perform { try $0.setTitle(t, title, in: $1) } }
    func setEstimate(_ t: NexusTask, _ est: String?) { perform { try $0.setEstimate(t, est, in: $1) } }

    /// Adds a task to a workstream (nil = the Inbox) or under `parent`. Returns its id.
    @discardableResult
    func add(title: String, workstream: String?, parent: NexusTask? = nil, due: String? = nil, plan: [PlanEntry] = [], key: Bool = false, est: String? = nil) -> String? {
        let file = parent?.file ?? self.workstream(workstream)?.tasksFile ?? "inbox.yaml"
        do {
            let (c, id) = try editor.add(title: title, to: file, parent: parent, due: due, plan: plan, key: key, est: est, in: snapshot, today: today)
            reload()
            onWrite?()
            toast = Toast(message: c.message, change: c)
            return id
        } catch {
            problem = "\(error)"
            return nil
        }
    }

    func undo() {
        guard let c = toast?.change else { return }
        do { try editor.undo(c); toast = Toast(message: "Undone") } catch { problem = "\(error)" }
        reload()
        onWrite?()
    }

    func tickOfferedParent() {
        guard let id = toast?.offerParent, let p = task(id) else { return }
        perform { try $0.tick(p, in: $1, today: today) }
    }
}
