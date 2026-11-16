import SwiftUI
import NexusCore

/// Applications on the iPhone and iPad (the laptop's appsdata.js): the model of the folder's schools, built once per read of the folder; the
/// universities database (read once from the app, off the main thread); every write, each with Undo on the bar; and Claude's two jobs, the
/// school research and the site check, which keep running while you move around the app.
@MainActor
@Observable
final class AppsData {
    static let shared = AppsData()

    enum DBState: Equatable { case idle, loading, ready, failed(String) }
    private(set) var dbState: DBState = .idle
    @ObservationIgnored private(set) var db: UniDB?
    /// Bumped when the database arrives (the screens read `db` through it).
    private(set) var dbVersion = 0

    @ObservationIgnored private var key = ""
    @ObservationIgnored private var cached: AppsModel?

    /// Claude researching a school (its id): what it is doing, and the last result or failure, by school.
    private(set) var researching: [String: String] = [:]
    var researchNote: [String: String] = [:]

    /// The Ask Claude button: the Claude chat's own screen opens it with the Applications conversation (wired where the chat lives).
    /// Set by the Claude chat when both are built: opens the "apps" conversation with what the page shows.
    static var askHandler: ((_ looking: String, _ context: String) -> Void)?

    // MARK: the model

    func model(_ store: NexusStore) -> AppsModel {
        let k = "\(store.snapshot.loadedAt.timeIntervalSince1970)|\(store.today)|\(dbVersion)"
        if k == key, let m = cached { return m }
        let root = store.folder
        let m = AppsModel(store.snapshot, read: { DataFolder.text(root, $0) }, today: store.today, db: db)
        key = k; cached = m
        return m
    }

    /// Is there anything of Applications in this folder (a school, or the schools' group)?
    func hasApps(_ store: NexusStore) -> Bool {
        store.snapshot.workstreams.values.contains { $0.kind == "school" }
    }

    func loadDB() {
        guard dbState == .idle else { return }
        dbState = .loading
        Task.detached(priority: .utility) {
            let result: Result<UniDB, Error>
            if let url = Bundle.main.url(forResource: "universities", withExtension: "json") {
                do { result = .success(try UniDB(json: Data(contentsOf: url))) } catch { result = .failure(error) }
            } else {
                result = .failure(AppsEditor.Failure.cannot("The universities database is not in this build."))
            }
            await MainActor.run {
                switch result {
                case .success(let d): self.db = d; self.dbState = .ready
                case .failure(let e): self.dbState = .failed("\(e)")
                }
                self.dbVersion += 1
            }
        }
    }

    // MARK: writes

    func editor(_ store: NexusStore) -> AppsEditor {
        AppsEditor(root: store.folder, readOnly: store.snapshot.readOnlyReason, read: FolderAccess.read, write: FolderAccess.write)
    }

    /// One write with Undo on the bar; a failure shows as the store's alert. Returns whether it was made.
    @discardableResult
    func edit(_ store: NexusStore, _ make: (AppsEditor, AppsModel) throws -> Change) -> Bool {
        do {
            let c = try make(editor(store), model(store))
            store.reload()
            store.didWrite(listChanged: true)
            if c.before != c.after || !c.also.isEmpty { store.toast = .init(message: c.message, change: c) }
            return true
        } catch {
            store.problem = "\(error)"
            store.reload()
            return false
        }
    }

    // MARK: Claude's research of a school

    func research(_ s: School, store: NexusStore) {
        guard researching[s.id] == nil else { return }
        let m = model(store)
        let row = m.rows(db).first { $0.s?.id == s.id }
        let prompt = SchoolProfile.prompt(name: s.name, u: row?.u, today: store.today)
        researching[s.id] = "Searching the web…"
        researchNote[s.id] = nil
        let id = s.id
        Task {
            do {
                let req = ClaudeRequest(model: "sonnet", system: SchoolProfile.system, messages: [.user(prompt)], maxTokens: 16000, web: true)
                let reply = try await ClaudeClient.shared.stream(req) { _ in }
                await MainActor.run { self.researching[id] = "Saving…" }
                guard let p = SchoolProfile.parse(reply.text) else { throw AppsEditor.Failure.cannot("Claude's answer was not in the expected form.") }
                await MainActor.run {
                    store.reload()
                    guard let now = self.model(store).school(id) else { self.finish(id, "\(s.short)'s folder is gone."); return }
                    var out: SchoolProfile.Applied?
                    self.edit(store) { e, _ in let (c, o) = try e.saveProfile(now, p, today: store.today); out = o; return c }
                    var note = "Researched today."
                    if let o = out {
                        if !o.filled.isEmpty { note += " Rates added: \(o.filled.map { Apps.roundNames[$0] ?? $0 }.joined(separator: ", "))." }
                        if !o.kept.isEmpty { note += " Your own \(o.kept.map { Apps.roundNames[$0] ?? $0 }.joined(separator: ", ")) rate kept." }
                    }
                    self.finish(id, note)
                }
            } catch {
                await MainActor.run { self.finish(id, "Claude could not do the research (\(error)).") }
            }
        }
    }

    private func finish(_ id: String, _ note: String) {
        researching[id] = nil
        researchNote[id] = note
    }
}

extension UniDB: @unchecked Sendable {}

/// The school's colour, as the laptop's Applications colour a school (Common App green, the overview slate).
extension NexusStore {
    func schoolColor(_ id: String?) -> Color {
        guard let id else { return .secondary }
        if id == "common-app" { return Theme.workstream("green", key: id) }
        return color(workstream: id)
    }
}
