import Foundation

/// One draft of a text block (nexus docs/data-format.md "Drafts").
public struct BlockDraft: Equatable, Sendable {
    public var id: String
    public var name: String
    public var made: String
    public var locked: Bool
    /// The draft this one was made from (its snapshot is `text/<block>~<id>@snap.md`).
    public var from: String?

    public init(id: String, name: String, made: String, locked: Bool = false, from: String? = nil) {
        self.id = id; self.name = name; self.made = made; self.locked = locked; self.from = from
    }

    init?(_ v: JSONValue) {
        guard let id = v["id"]?.string, !id.isEmpty else { return nil }
        self.id = id
        name = v["name"]?.string ?? id
        made = v["made"]?.string ?? ""
        locked = v["locked"]?.bool ?? false
        from = v["from"]?.string
    }

    var json: JSONValue {
        var f: [(String, JSONValue)] = [("id", .string(id)), ("name", .string(name)), ("made", .string(made)), ("locked", .bool(locked))]
        if let from { f.append(("from", .string(from))) }
        return .object(f)
    }
}

/// A text block's drafts (feature `drafts`). `text/<id>.md` always holds the current draft; every other draft is
/// `text/<id>~<draft>.md`, and a draft made from another keeps `text/<id>~<draft>@snap.md`, the other as it was then.
/// In `BoardContent.texts` those files are keyed `<id>~<draft>` and `<id>~<draft>@snap` (the file is `text/<key>.md`).
/// A new draft does not lock the old one; locking is the draft's own Lock button, and it can be unlocked.
public enum BlockDrafts {
    public static func list(_ item: BoardItem) -> [BlockDraft] {
        var seen = Set<String>()
        return (item.json["drafts"]?.array ?? []).compactMap(BlockDraft.init).filter { seen.insert($0.id).inserted }
    }

    /// The current draft's id, or nil for a block without drafts.
    public static func current(_ item: BoardItem) -> String? {
        let all = list(item)
        guard !all.isEmpty else { return nil }
        if let d = item.string("draft"), all.contains(where: { $0.id == d }) { return d }
        return all[0].id
    }

    /// The key of a draft's words in `texts`: the block's id for the current draft (or nil), `<id>~<draft>` for another.
    public static func key(_ item: BoardItem, _ draft: String?) -> String {
        guard let draft, draft != current(item), list(item).contains(where: { $0.id == draft }) else { return item.id }
        return "\(item.id)~\(draft)"
    }

    public static func snapKey(_ id: String, _ draft: String) -> String { "\(id)~\(draft)@snap" }

    /// Every extra file key the block's drafts keep (other drafts' words and the snapshots), for loading and saving.
    public static func fileKeys(_ item: BoardItem) -> [String] {
        let cur = current(item)
        var out: [String] = []
        for d in list(item) {
            if d.id != cur { out.append("\(item.id)~\(d.id)") }
            if d.from != nil { out.append(snapKey(item.id, d.id)) }
        }
        return out
    }

    public static func words(_ c: BoardContent, _ id: String, _ draft: String?) -> String {
        guard let it = c.items.first(where: { $0.id == id }) else { return c.texts[id] ?? "" }
        return c.texts[key(it, draft)] ?? ""
    }

    public static func isLocked(_ item: BoardItem, _ draft: String?) -> Bool {
        guard let d = draft ?? current(item) else { return false }
        return list(item).first { $0.id == d }?.locked ?? false
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    static func write(_ item: BoardItem, _ drafts: [BlockDraft], current: String) -> BoardItem {
        item.with("drafts", .array(drafts.map(\.json))).with("draft", .string(current))
    }

    /// Drafts for a block that has none yet: its words become "Draft 1".
    static func started(_ item: BoardItem, now: Date) -> [BlockDraft] {
        let all = list(item)
        return all.isEmpty ? [BlockDraft(id: "d1", name: "Draft 1", made: iso(now))] : all
    }

    /// A new draft made from `from` (default: the current one), with the same words, and made current. The old one stays as it is
    /// (unlocked unless `lockOld`) and a snapshot of it is kept, so its later edits can be seen and brought over.
    public static func make(_ c: BoardContent, id: String, from: String? = nil, name: String? = nil, lockOld: Bool = false,
                            now: Date = Date()) -> (content: BoardContent, draft: String)? {
        guard let k = c.items.firstIndex(where: { $0.id == id && $0.type == "text" }) else { return nil }
        var out = c
        let item = c.items[k]
        var drafts = started(item, now: now)
        let cur = current(item) ?? drafts[0].id
        let source = from.flatMap { f in drafts.contains { $0.id == f } ? f : nil } ?? cur
        let sourceWords = words(c, id, source)
        let ids = Set(drafts.map(\.id))
        var n = drafts.count + 1
        while ids.contains("d\(n)") { n += 1 }
        let new = "d\(n)"
        let clean = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        drafts.append(BlockDraft(id: new, name: clean.isEmpty ? "Draft \(n)" : clean, made: iso(now), from: source))
        if lockOld, let i = drafts.firstIndex(where: { $0.id == source }) { drafts[i].locked = true }
        // the current draft's words move to their own file; the new one is current
        out.texts["\(id)~\(cur)"] = c.texts[id] ?? ""
        out.texts[id] = sourceWords
        out.texts[snapKey(id, new)] = sourceWords
        out.items[k] = write(item, drafts, current: new)
        return (out, new)
    }

    /// Makes `draft` the current one: the two files swap (text/<id>.md always holds the current draft).
    public static func makeCurrent(_ c: BoardContent, id: String, draft: String) -> BoardContent {
        guard let k = c.items.firstIndex(where: { $0.id == id }), let cur = current(c.items[k]), cur != draft,
              list(c.items[k]).contains(where: { $0.id == draft }) else { return c }
        var out = c
        out.texts["\(id)~\(cur)"] = c.texts[id] ?? ""
        out.texts[id] = c.texts["\(id)~\(draft)"] ?? ""
        out.texts["\(id)~\(draft)"] = nil
        out.items[k] = out.items[k].with("draft", .string(draft))
        return out
    }

    public static func setLocked(_ c: BoardContent, id: String, draft: String?, _ locked: Bool, now: Date = Date()) -> BoardContent {
        guard let k = c.items.firstIndex(where: { $0.id == id }) else { return c }
        var out = c
        var drafts = started(c.items[k], now: now)
        let d = draft ?? current(c.items[k]) ?? drafts[0].id
        guard let i = drafts.firstIndex(where: { $0.id == d }) else { return c }
        drafts[i].locked = locked
        out.items[k] = write(c.items[k], drafts, current: current(c.items[k]) ?? drafts[0].id)
        return out
    }

    public static func rename(_ c: BoardContent, id: String, draft: String, to name: String) -> BoardContent {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let k = c.items.firstIndex(where: { $0.id == id }), let cur = current(c.items[k]) else { return c }
        var drafts = list(c.items[k])
        guard let i = drafts.firstIndex(where: { $0.id == draft }) else { return c }
        drafts[i].name = clean
        var out = c
        out.items[k] = write(c.items[k], drafts, current: cur)
        return out
    }

    /// Removes a draft (never the last one). Removing the current one makes the newest other one current.
    public static func delete(_ c: BoardContent, id: String, draft: String) -> BoardContent {
        guard let k = c.items.firstIndex(where: { $0.id == id }) else { return c }
        let all = list(c.items[k])
        guard all.count > 1, all.contains(where: { $0.id == draft }) else { return c }
        var out = c
        if current(c.items[k]) == draft, let next = all.last(where: { $0.id != draft }) {
            out = makeCurrent(out, id: id, draft: next.id)
        }
        out.texts["\(id)~\(draft)"] = nil
        out.texts[snapKey(id, draft)] = nil
        let rest = all.filter { $0.id != draft }
        out.items[k] = write(out.items[k], rest, current: current(out.items[k]) ?? rest[0].id)
        return out
    }

    // MARK: seeing and bringing over the old draft's later edits

    /// One line of a comparison: kept, only in the second (added) or only in the first (removed).
    public enum LineChange: Equatable, Sendable {
        case same(String)
        case added(String)
        case removed(String)
    }

    /// The lines of `a` and `b` compared (by the longest run of lines they share).
    public static func compare(_ a: String, _ b: String) -> [LineChange] {
        let x = a.components(separatedBy: "\n"), y = b.components(separatedBy: "\n")
        guard let m = LiveBoard.matchLines(x, y) else { return x.map { .removed($0) } + y.map { .added($0) } }
        var out: [LineChange] = []
        var j = 0
        for i in x.indices {
            if m[i] >= 0 {
                while j < m[i] { out.append(.added(y[j])); j += 1 }
                out.append(.same(x[i])); j = m[i] + 1
            } else {
                out.append(.removed(x[i]))
            }
        }
        while j < y.count { out.append(.added(y[j])); j += 1 }
        return out
    }

    /// What changed in the draft `draft` was made from since then (its snapshot against its words now); empty when nothing did,
    /// nil when the draft wasn't made from another or the other is gone.
    public static func changedSince(_ c: BoardContent, id: String, draft: String) -> [LineChange]? {
        guard let it = c.items.first(where: { $0.id == id }), let d = list(it).first(where: { $0.id == draft }),
              let from = d.from, list(it).contains(where: { $0.id == from }) else { return nil }
        let snap = c.texts[snapKey(id, draft)] ?? ""
        let now = words(c, id, from)
        if snap == now { return [] }
        return compare(snap, now).filter { if case .same = $0 { return false } else { return true } }
    }

    /// Bring them over: the old draft's edits since the snapshot are merged into `draft` (three-way, by line), and the snapshot
    /// moves on so the same edits aren't brought twice. Nil when a line was changed in both (nothing changes then).
    public static func bringOver(_ c: BoardContent, id: String, into draft: String) -> BoardContent? {
        guard let it = c.items.first(where: { $0.id == id }), let d = list(it).first(where: { $0.id == draft }),
              let from = d.from else { return nil }
        let snap = c.texts[snapKey(id, draft)] ?? ""
        let theirs = words(c, id, from)
        let mine = words(c, id, draft)
        guard let merged = LiveBoard.mergeLines(base: snap, hub: theirs, mine: mine) else { return nil }
        var out = c
        out.texts[key(it, draft)] = merged
        out.texts[snapKey(id, draft)] = theirs
        return out
    }
}
