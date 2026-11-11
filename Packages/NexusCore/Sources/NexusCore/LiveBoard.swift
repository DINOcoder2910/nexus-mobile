import Foundation

/// The laptop and the iPad on one board at once (nexus docs/sync.md "Live on a board"; the laptop's `renderer/src/board/livetext.js`
/// and `renderer/src/sync/merge.js`). Before the iPad writes a tile or a block's words, it checks whether the laptop (through sync)
/// wrote that file since the iPad read it; if so the two are merged the way the hub merges: tiles by stroke and item id, words by
/// line. Words changed on the same lines on both keep the iPad's, and the laptop's become a draft of the block. Pure but for reading.
public enum LiveBoard {

    // MARK: line merge (the hub's diff3)

    static let cellCap = 4_000_000

    /// base line index -> the matching line index in `side`, or -1; nil when too big to work out.
    static func matchLines(_ base: [String], _ side: [String]) -> [Int]? {
        var m = [Int](repeating: -1, count: base.count)
        var pre = 0
        while pre < base.count && pre < side.count && base[pre] == side[pre] { m[pre] = pre; pre += 1 }
        var suf = 0
        while suf < base.count - pre && suf < side.count - pre && base[base.count - 1 - suf] == side[side.count - 1 - suf] {
            m[base.count - 1 - suf] = side.count - 1 - suf; suf += 1
        }
        let B = Array(base[pre..<(base.count - suf)]), S = Array(side[pre..<(side.count - suf)])
        if B.isEmpty || S.isEmpty { return m }
        if B.count * S.count > cellCap { return nil }
        let w = S.count + 1
        var L = [UInt32](repeating: 0, count: (B.count + 1) * w)
        for i in stride(from: B.count - 1, through: 0, by: -1) {
            for j in stride(from: S.count - 1, through: 0, by: -1) {
                L[i * w + j] = B[i] == S[j] ? L[(i + 1) * w + j + 1] + 1 : max(L[(i + 1) * w + j], L[i * w + j + 1])
            }
        }
        var i = 0, j = 0
        while i < B.count && j < S.count {
            if B[i] == S[j] { m[pre + i] = pre + j; i += 1; j += 1 } else if L[(i + 1) * w + j] >= L[i * w + j + 1] { i += 1 } else { j += 1 }
        }
        return m
    }

    /// Three-way line merge: a change on one side is taken; the same change on both once; two insertions at one place keep both
    /// (the hub's first); anything else overlapping is nil (a clash).
    public static func mergeLines(base: String, hub: String, mine: String) -> String? {
        let o = base.components(separatedBy: "\n"), a = hub.components(separatedBy: "\n"), b = mine.components(separatedBy: "\n")
        guard let ma = matchLines(o, a), let mb = matchLines(o, b) else { return nil }
        var out: [String] = []
        var io = 0, ia = 0, ib = 0
        while true {
            while io < o.count && ma[io] == ia && mb[io] == ib { out.append(o[io]); io += 1; ia += 1; ib += 1 }
            if io >= o.count && ia >= a.count && ib >= b.count { break }
            var j = io
            while j < o.count && !(ma[j] >= 0 && mb[j] >= 0) { j += 1 }
            let ea = j < o.count ? ma[j] : a.count, eb = j < o.count ? mb[j] : b.count
            let oc = Array(o[io..<j]), ac = Array(a[ia..<ea]), bc = Array(b[ib..<eb])
            if ac == oc { out += bc }
            else if bc == oc || ac == bc { out += ac }
            else if oc.isEmpty { out += ac + bc }
            else { return nil }
            io = j; ia = ea; ib = eb
        }
        return out.joined(separator: "\n")
    }

    /// A block's words that moved on disk from `base` to `theirs` while the iPad typed `mine`: the merged words, or nil (a clash).
    public static func mergeBlock(base: String?, mine: String, theirs: String) -> String? {
        let base = base ?? ""
        if theirs == base || theirs == mine { return mine }
        if mine == base { return theirs }
        return mergeLines(base: base, hub: theirs, mine: mine)
    }

    // MARK: tile merge (by id, as the hub)

    static func mergeList<T>(_ base: [T], _ hub: [T], _ mine: [T], key: (T) -> String, js: (T) -> String) -> [T] {
        var B: [String: T] = [:], M: [String: T] = [:], H = Set<String>()
        for x in base { B[key(x)] = x }
        for x in mine { M[key(x)] = x }
        for x in hub { H.insert(key(x)) }
        var out: [T] = []
        for h in hub {
            let k = key(h), bx = B[k], mx = M[k]
            if let bx, mx == nil { if js(h) != js(bx) { out.append(h) }; continue }
            if let bx, let mx, js(mx) != js(bx) { out.append(mx); continue }
            out.append(h)
        }
        for m in mine {
            let k = key(m)
            if H.contains(k) { continue }
            if let bx = B[k], js(m) == js(bx) { continue }
            out.append(m)
        }
        return out
    }

    /// The hub's tile merge: nil when a side doesn't parse.
    public static func mergeTile(base: String, hub: String, mine: String) -> String? {
        if hub == mine || hub == base { return mine }
        if mine == base { return hub }
        guard let b = try? BoardFiles.parseTile(base), let h = try? BoardFiles.parseTile(hub), let m = try? BoardFiles.parseTile(mine) else { return nil }
        let strokes = mergeList(b.strokes, h.strokes, m.strokes, key: { $0.id.isEmpty ? "js:" + $0.json.text : "id:" + $0.id }, js: { $0.json.text })
        let items = mergeList(b.items, h.items, m.items, key: { "id:" + $0.id }, js: { $0.cleanJSON.text })
        return BoardFiles.tileJSON(strokes: strokes, items: items)
    }

    static let emptyTile = BoardFiles.tileJSON(strokes: [], items: [])

    // MARK: conflict copies and drafts

    public struct Conflict: Equatable, Sendable {
        public var id: String
        public var device: String
        public var date: String
        public var time: String
    }

    /// A conflict copy of a block's words as the hub names it: `text/<id> (conflict <device> <YYYY-MM-DD HHmm>[ n]).md`.
    public static func textConflict(_ rel: String) -> Conflict? {
        guard let re = try? NSRegularExpression(pattern: #"^text/([a-z2-9]{5,}) \(conflict (.+) (\d{4}-\d\d-\d\d) (\d\d)(\d\d)(?: \d+)?\)\.md$"#) else { return nil }
        let ns = rel as NSString
        guard let m = re.firstMatch(in: rel, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let g = { (i: Int) in ns.substring(with: m.range(at: i)) }
        return Conflict(id: g(1), device: g(2), date: g(3), time: g(4) + ":" + g(5))
    }

    public static func clashName(_ device: String, _ time: String) -> String { "From \(device.isEmpty ? "the other device" : device)\(time.isEmpty ? "" : " " + time)" }

    static func isoSeconds(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    /// Keep words as another draft of a text item (docs/data-format.md "Drafts"): the item with its drafts list, and the file
    /// (`text/<id>~<draft id>.md`) to write the words to. The current draft stays current; a block without drafts gets "Draft 1".
    public static func clashDraft(_ item: BoardItem, name: String, now: Date = Date()) -> (item: BoardItem, file: String, draft: String) {
        let made = isoSeconds(now)
        var drafts = item.json["drafts"]?.array ?? []
        if drafts.isEmpty {
            drafts = [.object([("id", .string("d1")), ("name", .string("Draft 1")), ("made", .string(made)), ("locked", .bool(false))])]
        }
        let ids = Set(drafts.compactMap { $0["id"]?.string })
        let cur = item.json["draft"]?.string.flatMap { ids.contains($0) ? $0 : nil } ?? drafts[0]["id"]?.string ?? "d1"
        var n = drafts.count + 1
        while ids.contains("d\(n)") { n += 1 }
        let id = "d\(n)"
        drafts.append(.object([("id", .string(id)), ("name", .string(name)), ("made", .string(made)), ("locked", .bool(false))]))
        let out = item.with("drafts", .array(drafts)).with("draft", .string(cur))
        return (out, "text/\(item.id)~\(id).md", id)
    }

    // MARK: before a save

    public struct Reconciled {
        public var content: BoardContent
        /// Tiles the laptop wrote meanwhile, merged in: the canvas must be read again.
        public var mergedTiles: [String] = []
        /// Blocks whose words were merged with the laptop's.
        public var mergedTexts: [String] = []
        /// Blocks where both changed the same lines: the laptop's words kept as this draft name.
        public var drafts: [String] = []
    }

    /// Before `BoardFiles.save`: every tile and block the iPad is about to write that was written by someone else since it was read
    /// (the laptop, through sync) is merged with that write, so nothing of theirs is written over. `read` reads a file in the board
    /// (nil when missing); `write` writes a draft's words. `device` names the laptop for a draft ("From Zephyrus Duo 16 08:15").
    public static func reconcile(_ c: BoardContent, read: (String) -> String?, write: (String, String) throws -> Void,
                                 device: String, now: Date = Date()) rethrows -> Reconciled {
        var r = Reconciled(content: c)
        guard c.readOnly == nil else { return r }
        let ch = BoardFiles.changes(c)
        for (key, mine) in ch.tiles.sorted(by: { $0.key < $1.key }) {
            guard let disk = read(BoardFormat.tileFile(key)) else { continue }
            let base = c.tilesOnDisk[key] ?? emptyTile
            if disk == base || disk == mine { continue }
            guard let merged = mergeTile(base: base, hub: disk, mine: mine), let t = try? BoardFiles.parseTile(merged) else { continue }
            // the merged tile replaces what this tile held
            r.content.strokes.removeAll { $0.tileKey == key }
            r.content.items.removeAll { $0.tileKey == key }
            r.content.strokes += t.strokes
            r.content.items += t.items
            for it in t.items where it.type == "text" && r.content.texts[it.id] == nil {
                let md = read(BoardFormat.textFile(it.id)) ?? ""
                r.content.texts[it.id] = md; r.content.textsOnDisk[it.id] = md
            }
            r.content.tilesOnDisk[key] = disk
            r.mergedTiles.append(key)
        }
        let time: String = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: now) }()
        for (id, mine) in ch.texts.sorted(by: { $0.key < $1.key }) {
            guard let disk = read(BoardFormat.textFile(id)) else { continue }
            let base = c.textsOnDisk[id]
            if disk == (base ?? "") || disk == mine { continue }
            if let merged = mergeBlock(base: base, mine: mine, theirs: disk) {
                r.content.texts[id] = merged
                r.mergedTexts.append(id)
            } else if let k = r.content.items.firstIndex(where: { $0.id == id }) {
                let name = clashName(device, time)
                let d = clashDraft(r.content.items[k], name: name, now: now)
                try write(d.file, disk)
                r.content.items[k] = d.item
                if BoardFormat.features.contains("drafts"), let m = r.content.meta { r.content.meta = BoardFormat.withFeature(m, "drafts") }
                r.drafts.append(name)
            }
            r.content.textsOnDisk[id] = disk
        }
        return r
    }

    // MARK: who is where

    /// Who is typing in which block and drawing on this board (the hub's presence).
    public static func on(_ list: [HubPresence], board: String) -> (typing: [String: String], drawing: [String]) {
        var typing: [String: String] = [:], drawing: [String] = []
        for p in list where p.board == board {
            if p.what == "typing", let b = p.block { typing[b] = p.device }
            else if p.what == "drawing", !drawing.contains(p.device) { drawing.append(p.device) }
        }
        return (typing, drawing)
    }
}

/// One device's place on the hub (nexus docs/sync.md "Presence"): memory only, gone a few seconds after it stops being renewed.
public struct HubPresence: Codable, Equatable, Sendable {
    public var device: String
    public var board: String
    public var block: String?
    public var what: String
    public init(device: String, board: String, block: String?, what: String) { self.device = device; self.board = board; self.block = block; self.what = what }
}

public struct HubPresenceReply: Codable, Equatable, Sendable {
    public var presence: [HubPresence]
    public var psig: String
}
