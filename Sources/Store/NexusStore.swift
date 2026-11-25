import SwiftUI
import NexusCore

/// The one place the screens read the data folder from and send edits to. Every edit is a line-level patch of one task file
/// (NexusCore's TaskEditor); after it the folder is read again, so what the screens show is always what the files say.
///
/// Each iPad window has its own store (so a task panel, the add sheet and Undo belong to the window they are in), and one more,
/// `AppServices.store`, serves sync, reminders, Spotlight and Siri. They keep each other current through two notices: `wrote`
/// (this store changed the folder: the others read it again, sync sends it) and `readAgain` (the folder changed underneath).
@Observable
final class NexusStore {
    static let wrote = Notification.Name("NexusStore.wrote")
    static let readAgain = Notification.Name("NexusStore.readAgain")
    static let folderChanged = Notification.Name("NexusStore.folderChanged")

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
    /// Called after the app wrote to the data folder (sync sends it soon after), with the paths written (relative to the folder)
    /// when the writer named them, nil when anything may have changed.
    @ObservationIgnored var onWrite: (([String]?) -> Void)?
    /// Called after every read of the folder (the shared store: reminders and Spotlight follow it).
    @ObservationIgnored var onReload: (() -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
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
        /// A link's end on the board to show first (its box is known once the board is read).
        var focusEnd: JSONValue? = nil
        /// Solve full screen from a question: `focus` across the width, the status bar hidden, Esc back (BoardController.solving).
        var solve = false
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
        TimeTracker.shared.load(url)
        ShortcutCenter.shared.onWrite = { NotificationCenter.default.post(name: NexusStore.wrote, object: nil) }
        loadShortcuts()
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: Self.wrote, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as AnyObject?) !== self else { return }
            if (n.userInfo?["list"] as? Bool) == true { notebooksVersion += 1 }
            reloadIfChanged()
        })
        observers.append(nc.addObserver(forName: Self.readAgain, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as AnyObject?) !== self else { return }
            reloadIfChanged()
        })
        observers.append(nc.addObserver(forName: Self.folderChanged, object: nil, queue: .main) { [weak self] n in
            guard let self, (n.object as AnyObject?) !== self else { return }
            let (url, picked) = FolderAccess.current()
            folder = url; pickedFolder = picked
            reload()
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// This store changed the folder: tell sync (through `onWrite` or the notice) and the other windows. Code that writes to
    /// the folder itself (study grades, boards) calls this after.
    /// `touched`: the files or folders written, relative to the folder, when the writer knows them all (sync then looks at those
    /// only, not at every file in the folder).
    func didWrite(listChanged: Bool = false, touched: [String]? = nil) {
        onWrite?(touched)
        var info: [String: Any] = [:]
        if listChanged { info["list"] = true }
        if let touched { info["touched"] = touched }
        NotificationCenter.default.post(name: Self.wrote, object: self, userInfo: info.isEmpty ? nil : info)
    }

    /// Both devices' shortcuts files, read with the folder (Settings › Shortcuts, the keys the app runs).
    private func loadShortcuts() {
        ShortcutCenter.shared.load(root: folder, canWrite: snapshot.isDataFolder && snapshot.readOnlyReason == nil)
    }

    var planning: Planning { Planning(snapshot, today: today) }
    var editor: TaskEditor { TaskEditor(root: folder, read: FolderAccess.read, write: FolderAccess.write) }
    var folderName: String { pickedFolder ? folder.lastPathComponent : Device.defaultFolder }

    // MARK: reading

    /// Reads the folder again (after an edit, on coming back to the app, or when the files changed underneath).
    func reload() {
        HangWatch.note("store: read the folder again")
        readCount += 1
        today = Days.today()
        snapshot = DataFolder.load(folder)
        fingerprint = DataFolder.fingerprint(folder)
        loadShortcuts()
        TimeTracker.shared.load(folder)
        // the iPhone's Live Activity shows today's tasks too (LiveActivities.swift)
        LiveActivities.refresh()
        onReload?()
    }

    @ObservationIgnored private var readCount = 0
    @ObservationIgnored private var treeCache: (key: String, tree: [Notebook])?

    /// The notebooks under `notebooks/`, read again only after the folder was read again or a notebook or board was made, renamed or
    /// removed. The sidebar and a notebook's page asked for them on every redraw, and with many notebooks (a OneNote import) reading
    /// them is a walk of hundreds of folders on the main thread (the Nov 14 freeze after coming back to the app).
    func notebooks() -> [Notebook] {
        let key = "\(folder.path)|\(notebooksVersion)|\(readCount)"
        if let c = treeCache, c.key == key { return c.tree }
        let tree = Notebook.list(folder)
        treeCache = (key, tree)
        return tree
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
        NotificationCenter.default.post(name: Self.folderChanged, object: self)
    }

    func useDefaultFolder() {
        FolderAccess.useDefault()
        let (url, picked) = FolderAccess.current()
        folder = url; pickedFolder = picked
        reload()
        NotificationCenter.default.post(name: Self.folderChanged, object: self)
    }

    /// A board (or a notebook) was written: let sync send it.
    func boardsChanged(listChanged: Bool = false, touched: [String]? = nil) {
        if listChanged { notebooksVersion += 1 }
        didWrite(listChanged: listChanged, touched: touched)
    }

    func makeSample() {
        do { try SampleFolder.make(at: folder, today: today) } catch { problem = error.localizedDescription }
        reload()
        didWrite()
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
            didWrite()
            toast = Toast(message: c.message, change: c, offerParent: c.offerParent)
        } catch {
            problem = "\(error)"
            reload()
        }
    }

    /// Done or not done.
    func toggleDone(_ t: NexusTask) {
        if t.done { perform { try $0.untick(t, in: $1) } } else {
            TimeTracker.shared.ticked(t, store: self) // a timer on it (or a subtask the tick ticks) stops
            perform { try $0.tick(t, in: $1, today: today) }
        }
    }

    func plan(_ t: NexusTask, on day: String, time: String? = nil) { perform { try $0.plan(t, on: day, time: time, in: $1) } }
    func unplan(_ t: NexusTask, from day: String) { perform { try $0.unplan(t, from: day, in: $1) } }
    func setPlan(_ t: NexusTask, _ plan: [PlanEntry]) { perform { try $0.setPlan(t, plan, in: $1) } }
    /// Moves a planned day (the Planner's drag); `from` nil adds the day.
    func move(_ t: NexusTask, from: String?, to: String) { perform { try $0.move(t, from: from, to: to, in: $1) } }
    /// Gives a task a time on a day (planning it that day), or takes the time off (nil): Today's day card.
    func setTime(_ t: NexusTask, on day: String, _ time: String?) {
        var p = t.plan.filter { $0.day != day }
        p.append(PlanEntry(day: day, time: time))
        perform { try $0.setPlan(t, p, in: $1, message: time.map { "At \(Self.clockText($0)): \(t.text)" } ?? "No time: \(t.text)") }
    }

    /// Plans a task today at a time in one write, taking it off the day it slipped from (`from`; else the latest earlier planned day,
    /// or tomorrow): a drop on Today's hours, and Slipped's "Put them there".
    func planToday(_ t: NexusTask, at time: String, from: String? = nil) {
        let tomorrow = Days.add(today, 1)
        let off = from ?? t.plannedDays.filter { $0 < today }.max() ?? (t.plannedDays.contains(tomorrow) && !t.plannedDays.contains(today) ? tomorrow : nil)
        var p = t.plan.filter { $0.day != today && $0.day != off }
        p.append(PlanEntry(day: today, time: time))
        perform { try $0.setPlan(t, p, in: $1, message: "At \(Self.clockText(time)) today: \(t.text)") }
    }

    /// Your own order of a day's untimed tasks (Today's drag), kept in the synced `nexus-day-order.yaml` as on the laptop.
    func setDayOrder(_ day: String, _ ids: [String]) {
        guard snapshot.readOnlyReason == nil else { problem = snapshot.readOnlyReason; return }
        let url = folder.appendingPathComponent(DayOrder.file)
        let text = DayOrder.text(DayOrder.with(snapshot.dayOrder, day: day, keys: ids), today: today)
        do {
            try FolderAccess.write(url, text)
            reload()
            didWrite(touched: [DayOrder.file])
        } catch {
            problem = "Couldn't save your order: \(error.localizedDescription)"
        }
    }

    /// "16:00" as "4:00", as the new look's lists show a time.
    static func clockText(_ hm: String) -> String {
        guard let m = DayOrder.minutes(hm) else { return hm }
        let h = (m / 60) % 12
        return "\(h == 0 ? 12 : h):" + String(format: "%02d", m % 60)
    }
    func setDue(_ t: NexusTask, _ day: String?) { perform { try $0.setDue(t, day, in: $1) } }
    func setKey(_ t: NexusTask, _ on: Bool) { perform { try $0.setKey(t, on, in: $1) } }
    func setSomeday(_ t: NexusTask, _ on: Bool) { perform { try $0.setSomeday(t, on, in: $1) } }
    func setTitle(_ t: NexusTask, _ title: String) { perform { try $0.setTitle(t, title, in: $1) } }
    func setEstimate(_ t: NexusTask, _ est: String?) { perform { try $0.setEstimate(t, est, in: $1) } }
    func setWaiting(_ t: NexusTask, on who: String?, since: String?) { perform { try $0.setWaiting(t, on: who, since: since, in: $1) } }
    func setRepeat(_ t: NexusTask, _ r: NexusCore.Repeat?) { perform { try $0.setRepeat(t, r, in: $1) } }
    func setTags(_ t: NexusTask, _ tags: [String]) { perform { try $0.setTags(t, tags, in: $1) } }
    func setNote(_ t: NexusTask, _ note: String?) { perform { try $0.setNote(t, note, in: $1) } }
    /// Deletes a task and everything under it (Undo on the bar puts it back): the task panel's Delete.
    func delete(_ t: NexusTask) { perform { try $0.delete(t, in: $1) } }
    /// Moves a task with its subtasks to another subject's list (nil: the Inbox): the task panel's subject menu.
    func moveTask(_ t: NexusTask, to workstream: String?) { perform { try $0.moveTask(t, to: workstream, in: $1) } }
    /// The checklist's moves: under the one above, back out after its parent, up or down among the ones beside it.
    func nest(_ t: NexusTask) { perform { try $0.nest(t, in: $1) } }
    func unnest(_ t: NexusTask) { perform { try $0.unnest(t, in: $1) } }
    func shift(_ t: NexusTask, by step: Int) { perform { try $0.shift(t, by: step, in: $1) } }

    /// Adds a task to a workstream (nil = the Inbox) or under `parent`. Returns its id. `extras` (a typed repeat, waiting on, #tags)
    /// are written straight after, in the same Undo.
    @discardableResult
    func add(title: String, workstream: String?, parent: NexusTask? = nil, due: String? = nil, plan: [PlanEntry] = [], key: Bool = false, est: String? = nil,
             extras: CaptureFacts? = nil) -> String? {
        let file = parent?.file ?? self.workstream(workstream)?.tasksFile ?? "inbox.yaml"
        do {
            var (c, id) = try editor.add(title: title, to: file, parent: parent, due: due, plan: plan, key: key, est: est, in: snapshot, today: today)
            if let x = extras, x.every != nil || x.waiting != nil || !x.tags.isEmpty {
                let s = DataFolder.load(folder)
                if let t = s.tasks[id] {
                    do {
                        if let r = x.every {
                            c.after = try editor.setRepeat(t, NexusCore.Repeat(freq: r.freq, on: r.on.map { [$0] } ?? []), in: s).after
                        }
                        if let w = x.waiting { c.after = try editor.setWaiting(t, on: w.on, since: w.since, in: s).after }
                        if !x.tags.isEmpty { c.after = try editor.setTags(t, x.tags, in: s).after }
                    } catch {
                        problem = "Added, but couldn't write all of it: \(error)"
                    }
                }
            }
            reload()
            didWrite()
            toast = Toast(message: c.message, change: c)
            return id
        } catch {
            problem = "\(error)"
            return nil
        }
    }

    /// Writes a whole text file of the data folder (a workstream's notes.md), with Undo on the bar.
    func writeText(_ rel: String, _ text: String, message: String) {
        guard snapshot.readOnlyReason == nil else { problem = snapshot.readOnlyReason; return }
        let url = folder.appendingPathComponent(rel)
        let before = (try? FolderAccess.read(url)) ?? ""
        guard text != before else { return }
        do {
            try FolderAccess.write(url, text)
            reload()
            didWrite()
            toast = Toast(message: message, change: Change(file: rel, before: before, after: text, message: message))
        } catch {
            problem = "Couldn't save \(rel): \(error.localizedDescription)"
        }
    }

    // MARK: workstream edits (NexusCore WorkstreamEditor: the laptop's New workstream, Rename, Move, Park, Colour, decisions, sessions)

    var workstreamEditor: WorkstreamEditor { WorkstreamEditor(root: folder, read: FolderAccess.read, write: FolderAccess.write) }

    /// One workstream edit: written, the folder read again, sync told, the undo bar shown. Returns false when it couldn't be made.
    @discardableResult
    private func performWs(list: Bool = false, _ make: (WorkstreamEditor, Snapshot) throws -> Change) -> Bool {
        do {
            let c = try make(workstreamEditor, snapshot)
            reload()
            didWrite(listChanged: list)
            toast = Toast(message: c.message, change: c)
            return true
        } catch {
            problem = "\(error)"
            reload()
            return false
        }
    }

    /// A new workstream in a group; returns its id.
    func createWorkstream(in group: String, name: String) -> String? {
        var id: String?
        performWs(list: true) { ed, s in let (c, made) = try ed.create(group: group, name: name, in: s); id = made; return c }
        return id
    }
    func renameWorkstream(_ w: Workstream, to name: String) { performWs { try $0.rename(w, to: name, in: $1) } }
    func moveWorkstream(_ w: Workstream, to group: String) { performWs(list: true) { try $0.move(w, to: group, in: $1) } }
    func parkWorkstream(_ w: Workstream, _ on: Bool) { performWs { try $0.park(w, on, in: $1) } }
    func colorWorkstream(_ w: Workstream, _ color: String?) { performWs { try $0.color(w, color, in: $1) } }
    func addDecision(_ w: Workstream, _ text: String) { performWs { try $0.decision(w, text, date: today, in: $1) } }
    /// A person's new session note (and its task when asked); returns the note's path.
    func newSession(_ w: Workstream, title: String, task: Bool) -> String? {
        var path: String?
        performWs { ed, s in let (c, p) = try ed.session(w, title: title, date: today, task: task, in: s, today: today); path = p; return c }
        return path
    }

    func undo() {
        guard let c = toast?.change else { return }
        do { try editor.undo(c); toast = Toast(message: "Undone") } catch { problem = "\(error)" }
        reload()
        didWrite(listChanged: c.moved != nil || c.created)
    }

    func tickOfferedParent() {
        guard let id = toast?.offerParent, let p = task(id) else { return }
        perform { try $0.tick(p, in: $1, today: today) }
    }
}
