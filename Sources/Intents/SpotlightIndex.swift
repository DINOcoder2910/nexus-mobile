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
        for nb in Notebook.list(store.folder) {
            for (b, place) in nb.allBoards {
                let a = CSSearchableItemAttributeSet(contentType: .content)
                a.title = b.name
                a.contentDescription = "Board in \(place)"
                items.append(CSSearchableItem(uniqueIdentifier: "board:\(b.path)", domainIdentifier: domain, attributeSet: a))
            }
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
