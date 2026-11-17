import CoreSpotlight
import UniformTypeIdentifiers
import NexusCore

/// Nexus in the system search (swipe down on the Home Screen): open tasks, workstreams and boards. Tapping one opens it in the
/// app (RootView's `onContinueUserActivity`). The index is made again when the folder changes, only when what it holds changed.
@MainActor
enum SpotlightIndex {
    static let domain = "app.nexus.mobile"
    private static var lastKey = ""

    static func update(_ store: NexusStore) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let s = store.snapshot
        guard s.isDataFolder else { clear(); return }
        let today = store.today
        var items: [CSSearchableItem] = []

        for t in Planning(s, today: today).open where t.hasId {
            let a = CSSearchableItemAttributeSet(contentType: .text)
            a.title = t.text
            var parts = [store.workstreamName(t)]
            if let d = t.due { parts.append("due " + Days.relative(d, today: today)) }
            if t.key { parts.append("★ key date") }
            if let w = t.waitingOn { parts.append("waiting on \(w)") }
            a.contentDescription = parts.joined(separator: " · ")
            a.keywords = t.tags + [store.workstreamName(t)]
            items.append(CSSearchableItem(uniqueIdentifier: "task:\(t.id)", domainIdentifier: domain, attributeSet: a))
        }
        for w in s.workstreams.values where !w.finished {
            let a = CSSearchableItemAttributeSet(contentType: .folder)
            a.title = w.name
            a.contentDescription = w.parked ? "Workstream (parked)" : "Workstream"
            a.keywords = w.aliases
            items.append(CSSearchableItem(uniqueIdentifier: "ws:\(w.id)", domainIdentifier: domain, attributeSet: a))
        }
        // the boards: a walk of every notebook folder (over a thousand boards after the OneNote import), away from the main thread
        let root = store.folder
        generation += 1
        pending = items
        let gen = generation
        Task.detached(priority: .utility) {
            let boards = Notebook.list(root).flatMap { nb in nb.allBoards.map { [$0.board.path, $0.board.name, $0.place] } }
            await MainActor.run { finish(boards: boards, generation: gen) }
        }
    }

    /// Bumped by each update, so an older walk that finishes late doesn't index over a newer one.
    private static var generation = 0
    /// The tasks and workstreams of the latest update, waiting for its boards.
    private static var pending: [CSSearchableItem] = []

    private static func finish(boards: [[String]], generation gen: Int) {
        guard gen == generation else { return }
        var items = pending
        pending = []
        for b in boards {
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = b[1]
            a.contentDescription = "Board in \(b[2])"
            items.append(CSSearchableItem(uniqueIdentifier: "board:\(b[0])", domainIdentifier: domain, attributeSet: a))
        }

        let key = items.map { "\($0.uniqueIdentifier)|\($0.attributeSet.title ?? "")|\($0.attributeSet.contentDescription ?? "")" }
            .sorted().joined(separator: "\n")
        guard key != lastKey else { return }
        lastKey = key
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items)
        }
    }

    static func clear() {
        generation += 1
        guard !lastKey.isEmpty else { return }
        lastKey = ""
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain])
    }

    /// What a tapped result is: ("task", id), ("ws", id) or ("board", path).
    static func target(_ activity: NSUserActivity) -> (kind: String, value: String)? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let colon = id.firstIndex(of: ":") else { return nil }
        return (String(id[..<colon]), String(id[id.index(after: colon)...]))
    }
}
