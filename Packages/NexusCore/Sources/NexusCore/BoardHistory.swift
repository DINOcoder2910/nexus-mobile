import Foundation

/// A board's version history, as the laptop's `renderer/src/board/history.js` (nexus docs/data-format.md "The board redesign's
/// additions", Version history). Each device appends what it did to `history/<device>-<yyyy-mm>.jsonl` in the board (one JSON per
/// line, its own file, so the hub never merges them); the History view reads every device's files, sorts them into one timeline and
/// replays it.
///   HistoryRecorder   this iPad's saves as log lines: strokes added or replaced, things erased, items added or changed, typing
///   parseLog          a log file's lines -> lines with their time (bad and unknown lines are skipped)
///   HistoryTimeline   every device's lines in time order, with a rough start for what was on the board before the log began
///   HistoryReplayer   the board at any moment (strokes, items, words, strokes being written at that moment)
///   PlayClock         real time <-> play time with long pauses shortened; sessions() the stretches of work, for the scrubber
///   copyOut           what part of an old board brings back into the current one
public enum BoardHistory {
    public static let dir = "history"

    // MARK: names

    /// "Zephyrus Duo 16" -> "zephyrus-duo-16"; "" -> "device".
    public static func deviceSlug(_ name: String) -> String {
        var out = ""
        var dash = false
        for u in name.lowercased().decomposedStringWithCompatibilityMapping.unicodeScalars {
            if (0x300...0x36F).contains(u.value) { continue }
            if (97...122).contains(u.value) || (48...57).contains(u.value) {
                if dash && !out.isEmpty { out += "-" }
                dash = false
                out.unicodeScalars.append(u)
            } else {
                dash = true
            }
        }
        return out.isEmpty ? "device" : out
    }

    /// "2026-11" (UTC) for a time in ms.
    public static func month(_ ms: Double) -> String { String(iso(ms).prefix(7)) }

    /// "history/ipad-2026-11.jsonl".
    public static func logFile(device: String, ms: Double) -> String { dir + "/" + deviceSlug(device) + "-" + month(ms) + ".jsonl" }

    /// "history/ipad-2026-11.jsonl" -> ("ipad", "2026-11", gz false); nil for anything else.
    public static func logInfo(_ rel: String) -> (device: String, month: String, gz: Bool)? {
        guard let m = rel.range(of: #"^history/[a-z0-9-]+-[0-9]{4}-[0-9]{2}\.jsonl(\.gz)?$"#, options: .regularExpression), m.lowerBound == rel.startIndex else { return nil }
        var name = String(rel.dropFirst(dir.count + 1))
        let gz = name.hasSuffix(".gz")
        if gz { name = String(name.dropLast(3)) }
        name = String(name.dropLast(6)) // ".jsonl"
        let mon = String(name.suffix(7))
        return (String(name.dropLast(8)), mon, gz)
    }

    public static func isLogFile(_ rel: String) -> Bool { logInfo(rel) != nil }

    // MARK: times (ISO with ms, UTC, as JavaScript's toISOString)

    private static let isoMs: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private static let isoSec: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// (whole seconds through the formatter and the ms by hand: a fraction through a Double can come out a millisecond short)
    public static func iso(_ ms: Double) -> String {
        let whole = Int64(ms.rounded())
        let sec = whole >= 0 ? whole / 1000 : (whole - 999) / 1000
        let part = Int(whole - sec * 1000)
        let base = isoSec.string(from: Date(timeIntervalSince1970: Double(sec)))
        return String(base.dropLast()) + "." + String(format: "%03d", part) + "Z"
    }
    public static func time(_ s: String) -> Double? {
        guard let d = isoMs.date(from: s) ?? isoPlain.date(from: s) else { return nil }
        return (d.timeIntervalSince1970 * 1000).rounded()
    }
    public static func now() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    // MARK: strokes and words

    /// How long a stroke took to write, in ms (its last point's `t`; 0 for a stroke written without times).
    public static func strokeMs(_ s: BoardStroke) -> Double {
        guard let p = s.points.last, p.count > 5, p[5].isFinite else { return 0 }
        return max(0, min(60000, (p[5] * 1000).rounded()))
    }

    /// One change of a block's markdown as (at, del, ins) in UTF-16 units, as the laptop counts: what changed between the common start
    /// and the common end. Never splits a surrogate pair. nil when nothing changed.
    public static func textDiff(_ a: String, _ b: String) -> (at: Int, del: Int, ins: String)? {
        if a == b { return nil }
        let x = Array(a.utf16), y = Array(b.utf16)
        let n = min(x.count, y.count)
        var i = 0
        while i < n && x[i] == y[i] { i += 1 }
        var j = 0
        while j < n - i && x[x.count - 1 - j] == y[y.count - 1 - j] { j += 1 }
        if i > 0 && UTF16.isLeadSurrogate(x[i - 1]) { i -= 1 }
        if j > 0 && UTF16.isTrailSurrogate(x[x.count - j]) { j -= 1 }
        let ins = String(decoding: y[i..<(y.count - j)], as: UTF16.self)
        return (i, x.count - i - j, ins)
    }

    /// The markdown with one keystroke applied (offsets in UTF-16 units, clamped).
    public static func applyKey(_ md: String, at: Int, del: Int, ins: String) -> String {
        let u = Array(md.utf16)
        let a = max(0, min(u.count, at))
        let e = min(u.count, a + max(0, del))
        return String(decoding: Array(u[..<a]) + Array(ins.utf16) + Array(u[e...]), as: UTF16.self)
    }

    /// A draft field as a key part (a string, or a number as JavaScript prints it).
    static func draftKey(_ v: JSONValue?) -> String {
        switch v {
        case .string(let s)?: return s
        case .number(let n)?: return JSONValue.format(n)
        default: return ""
        }
    }

    // MARK: reading a log

    /// One line of a log file, read.
    public struct Line {
        public var t: Double
        public var op: String
        public var v: JSONValue
        public var device: String?
    }

    public static let ops: Set<String> = ["stroke", "erase", "item", "type", "text", "open"]

    /// A log file's lines (lines that do not parse, have no time or an op this app does not know are skipped).
    public static func parseLog(_ text: String, device: String? = nil) -> [Line] {
        var out: [Line] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty, let v = try? JSONValue.parse(line), v.object != nil,
                  let op = v["op"]?.string, ops.contains(op), let ts = v["t"]?.string, let t = time(ts) else { continue }
            switch op {
            case "stroke": guard let s = v["s"], s["id"]?.string != nil, let p = s["points"]?.array, !p.isEmpty else { continue }
            case "item": guard v["it"]?["id"]?.string != nil else { continue }
            case "erase": guard v["ids"]?.array != nil else { continue }
            case "type": guard v["id"]?.string != nil, v["k"]?.array != nil else { continue }
            case "text": guard v["id"]?.string != nil else { continue }
            default: break
            }
            out.append(Line(t: t, op: op, v: v, device: device))
        }
        return out
    }

    /// Every id the lines added (a stroke or an item): what a recorder starts with as `known`.
    public static func knownIds(_ lines: [Line]) -> Set<String> {
        var s = Set<String>()
        for l in lines {
            if l.op == "stroke", let id = l.v["s"]?["id"]?.string { s.insert(id) }
            else if l.op == "item", let id = l.v["it"]?["id"]?.string { s.insert(id) }
        }
        return s
    }

    /// Every device's log files of a board, read (a `.jsonl.gz` month is skipped here: the iPad has no gunzip without a library).
    public static func readLogs(board: URL, read: (URL) throws -> String = { String(decoding: try Data(contentsOf: $0), as: UTF8.self) }) -> [Line] {
        let dirURL = board.appendingPathComponent(dir, isDirectory: true)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dirURL.path)) ?? []).sorted()
        var out: [Line] = []
        for n in names {
            guard let info = logInfo(dir + "/" + n), !info.gz, let text = try? read(dirURL.appendingPathComponent(n)) else { continue }
            out += parseLog(text, device: info.device)
        }
        return out
    }

    // MARK: Copy out

    /// What of the old board (the part picked) comes into the current one: the things not there now as they were (their own ids), the
    /// things there now but changed since as copies with new ids; things unchanged are left. Texts are by the item ids returned.
    public static func copyOut(old: BoardState, current cur: BoardState, newId: (Set<String>) -> String) -> BoardState {
        let cs = Dictionary(cur.strokes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ci = Dictionary(cur.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var taken = Set(cs.keys).union(ci.keys)
        var out = BoardState()
        for s in old.strokes {
            if let c = cs[s.id] {
                if c.sameContent(s) { continue }
                var copy = s; copy.id = newId(taken); taken.insert(copy.id); out.strokes.append(copy)
            } else { taken.insert(s.id); out.strokes.append(s) }
        }
        for it in old.items {
            let md = old.texts[it.id]
            if let c = ci[it.id] {
                if c.cleanJSON == it.cleanJSON && cur.texts[it.id] == md { continue }
                let id = newId(taken); taken.insert(id)
                out.items.append(it.with("id", .string(id)))
                if let md { out.texts[id] = md }
            } else {
                taken.insert(it.id); out.items.append(it)
                if let md { out.texts[it.id] = md }
            }
        }
        return out
    }
}

/// A board's strokes (drawing order), items and typed words: what a save diff, the replayer and Copy out work on.
public struct BoardState {
    public var strokes: [BoardStroke] = []
    public var items: [BoardItem] = []
    public var texts: [String: String] = [:]
    public init() {}
    public init(strokes: [BoardStroke], items: [BoardItem], texts: [String: String]) { self.strokes = strokes; self.items = items; self.texts = texts }
    public init(_ c: BoardContent) { strokes = c.strokes; items = c.items; texts = c.texts }
    public var isEmpty: Bool { strokes.isEmpty && items.isEmpty }
}

// MARK: - the recorder

/// This iPad's edits, as lines to append. The iPad saves a board as a whole (BoardFiles.save), so the recorder works from the board as
/// it was at the last save and as it is now. `known` holds the ids already in a log (any device's): erasing something that is not
/// gets its whole self in the erase line (`was`), so the player can show it before it went.
public final class HistoryRecorder {
    public var known: Set<String>
    public var burstGap: Double = 4000
    private var out: [String] = []
    private var md: [String: String] = [:]
    private var burst: Burst?
    private var opened = false
    /// When this recorder last logged a save (or opened): a new stroke drawn before it was moved, not written now.
    private var since: Double

    struct Burst { var id: String; var d: String?; var t0: Double; var last: Double; var k: [JSONValue] }

    public init(known: Set<String> = [], now: Double = BoardHistory.now()) { self.known = known; since = now }

    private func push(_ fields: [(String, JSONValue)]) { end(); out.append(JSONValue.object(fields).text) }
    private static func withD(_ o: [(String, JSONValue)], _ d: String?) -> [(String, JSONValue)] {
        guard let d, !d.isEmpty else { return o }
        var r = Array(o.prefix(3)); r.append(("d", .string(d))); r += o.dropFirst(3); return r
    }

    /// A session starts (written once, before the first line of this board's opening).
    public func open(now: Double = BoardHistory.now()) {
        guard !opened else { return }
        opened = true
        push([("t", .string(BoardHistory.iso(now))), ("op", .string("open"))])
    }

    /// The board was saved: what changed between `old` (the last save) and `new`. `born` gives a new stroke's start (PencilKit's
    /// creation date, ms) when known; a stroke dated before the last save is a moved one and is dated now.
    public func saved(from old: BoardState, to new: BoardState, now: Double = BoardHistory.now(), born: [String: Double] = [:]) {
        let oldS = Dictionary(old.strokes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newS = Dictionary(new.strokes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldI = Dictionary(old.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newI = Set(new.items.map(\.id))
        let erasedS = old.strokes.filter { newS[$0.id] == nil }
        let erasedI = old.items.filter { !newI.contains($0.id) }
        if !erasedS.isEmpty || !erasedI.isEmpty || new.strokes.contains(where: { oldS[$0.id]?.sameContent($0) != true }) || new.items.contains(where: { oldI[$0.id] != $0 }) || new.texts != old.texts {
            open(now: now)
        }
        if !erasedS.isEmpty || !erasedI.isEmpty {
            var line: [(String, JSONValue)] = [("t", .string(BoardHistory.iso(now))), ("op", .string("erase")),
                                               ("ids", .array((erasedS.map(\.id) + erasedI.map(\.id)).map { .string($0) }))]
            let was = erasedS.filter { !known.contains($0.id) }.map(\.json) + erasedI.filter { !known.contains($0.id) }.map(\.cleanJSON)
            if !was.isEmpty { line.append(("was", .array(was))) }
            push(line)
        }
        for s in new.strokes {
            var t = now
            if let o = oldS[s.id] {
                if o.sameContent(s) { continue }
            } else if !known.contains(s.id) {
                if let b = born[s.id], b >= since - 1000, b <= now { t = b } else if born[s.id] == nil { t = now - BoardHistory.strokeMs(s) }
            }
            push([("t", .string(BoardHistory.iso(t))), ("op", .string("stroke")), ("s", s.json)])
            known.insert(s.id)
        }
        for it in new.items {
            let o = oldI[it.id]
            if o == nil || o!.cleanJSON != it.cleanJSON {
                push([("t", .string(BoardHistory.iso(now))), ("op", .string("item")), ("it", it.cleanJSON)])
                known.insert(it.id)
            }
            if it.type == "text" {
                let cur = new.texts[it.id] ?? ""
                let prev = o == nil ? nil : (old.texts[it.id] ?? "")
                if o == nil || prev != cur { typing(id: it.id, prev: prev, md: cur, now: now, d: BoardHistory.draftKey(it.json["draft"])) }
            }
        }
        since = now
    }

    /// The words of a block as they are now, changed by someone else (another device): the next change here is measured from them.
    public func seen(id: String, md text: String, d: String? = nil) {
        let key = id + "~" + (d ?? "")
        if md[key] != nil { md[key] = text }
    }

    /// A block's words changed from `prev` to `md` (each keystroke, or a whole change at once). What this recorder last logged for the
    /// block wins over `prev`.
    public func typing(id: String, prev: String?, md text: String, now: Double = BoardHistory.now(), d: String? = nil) {
        let dd: String? = (d?.isEmpty ?? true) ? nil : d
        let key = id + "~" + (dd ?? "")
        open(now: now)
        var had: String
        if let h = md[key] { had = h } else {
            had = prev ?? ""
            if !had.isEmpty { push(Self.withD([("t", .string(BoardHistory.iso(now))), ("op", .string("text")), ("id", .string(id)), ("md", .string(had))], dd)) }
            md[key] = had
        }
        guard let k = BoardHistory.textDiff(had, text) else { return }
        md[key] = text
        if k.ins.utf16.count > 400 || k.del > 400 {
            push(Self.withD([("t", .string(BoardHistory.iso(now))), ("op", .string("text")), ("id", .string(id)), ("md", .string(text))], dd))
            return
        }
        let q: [JSONValue] = [.number(0), .number(Double(k.at)), .number(Double(k.del)), .string(k.ins)]
        if var b = burst, b.id == id, b.d == dd, now - b.last < burstGap, now >= b.t0 {
            var qq = q; qq[0] = .number(now - b.t0)
            b.k.append(.array(qq)); b.last = now; burst = b
            return
        }
        end()
        burst = Burst(id: id, d: dd, t0: now, last: now, k: [.array(q)])
    }

    public func end() {
        guard let b = burst else { return }
        burst = nil
        out.append(JSONValue.object(Self.withD([("t", .string(BoardHistory.iso(b.t0))), ("op", .string("type")), ("id", .string(b.id)), ("k", .array(b.k))], b.d)).text)
    }

    /// The lines written since the last take, as text to append ("" when none). A burst of typing still going on is closed.
    public func take() -> String {
        end()
        let lines = out.joined(separator: "\n")
        out = []
        return lines.isEmpty ? "" : lines + "\n"
    }

    public var pending: Bool { !out.isEmpty || burst != nil }
}

// MARK: - the timeline

public struct HistoryEvent {
    public enum Kind {
        case stroke(BoardStroke)
        case erase([String])
        case item(BoardItem)
        /// A block's whole words (key "id~draft").
        case words(String, String)
        case key(String, Int, Int, String)
        case open
    }
    public var t: Double
    public var kind: Kind
    /// How long a stroke takes to write (ms); 0 for anything else, and for a stroke replaced (the same id again).
    public var dur: Double = 0
}

/// Every device's events in time order, typing taken apart into keystrokes. What was on the board before any log began (the board as it
/// is now, plus what erase lines say was there) is put first, one thing after another in drawing order: a rough history.
public struct HistoryTimeline {
    public var ev: [HistoryEvent]
    public var start: Double
    public var end: Double
    /// Where the logged part starts, when a rough start was put before it.
    public var rough: Double?

    public init(_ lines: [Line], now: BoardState, at nowMs: Double = BoardHistory.now(), roughGap: Double = 250) {
        let evs = lines.enumerated().sorted { $0.element.t != $1.element.t ? $0.element.t < $1.element.t : $0.offset < $1.offset }.map(\.element)
        let added = BoardHistory.knownIds(evs)
        var typed = Set<String>()
        for e in evs where e.op == "type" || e.op == "text" { if let id = e.v["id"]?.string { typed.insert(id) } }
        var out: [HistoryEvent] = []
        var preS: [BoardStroke] = [], preI: [BoardItem] = [], seen = Set<String>()
        for e in evs where e.op == "erase" {
            for x in e.v["was"]?.array ?? [] {
                guard let id = x["id"]?.string, !added.contains(id), !seen.contains(id) else { continue }
                if x["points"]?.array != nil { if let s = BoardStroke(x, fields: nil) { seen.insert(id); preS.append(s) } }
                else if let it = BoardItem(x) { seen.insert(id); preI.append(it) }
            }
        }
        for s in now.strokes where !added.contains(s.id) && !seen.contains(s.id) { seen.insert(s.id); preS.append(s) }
        for it in now.items where !added.contains(it.id) && !seen.contains(it.id) { seen.insert(it.id); preI.append(it) }
        var rough: Double?
        if !preS.isEmpty || !preI.isEmpty {
            let total = Double(preI.count) * roughGap + preS.reduce(0) { $0 + BoardHistory.strokeMs($1) + roughGap }
            let first = evs.first?.t ?? nowMs
            var c = first - total - 1000
            rough = first
            // printouts and pictures first (what the ink was written on), then shapes, then text, then the ink in drawing order
            func rank(_ it: BoardItem) -> Int { it.type == "pdf" ? 0 : it.type == "image" ? 1 : it.type == "text" ? 3 : 2 }
            for it in preI.enumerated().sorted(by: { rank($0.element) != rank($1.element) ? rank($0.element) < rank($1.element) : $0.offset < $1.offset }).map(\.element) {
                out.append(HistoryEvent(t: c, kind: .item(it)))
                if it.type == "text", !typed.contains(it.id), let md = now.texts[it.id] { out.append(HistoryEvent(t: c, kind: .words(it.id + "~", md))) }
                c += roughGap
            }
            for s in preS { out.append(HistoryEvent(t: c, kind: .stroke(s), dur: BoardHistory.strokeMs(s))); c += BoardHistory.strokeMs(s) + roughGap }
        }
        var strokeSeen = Set(preS.map(\.id))
        for e in evs {
            switch e.op {
            case "stroke":
                guard let v = e.v["s"], let s = BoardStroke(v, fields: nil) else { continue }
                let fresh = !strokeSeen.contains(s.id)
                strokeSeen.insert(s.id)
                out.append(HistoryEvent(t: e.t, kind: .stroke(s), dur: fresh ? BoardHistory.strokeMs(s) : 0))
            case "erase":
                out.append(HistoryEvent(t: e.t, kind: .erase((e.v["ids"]?.array ?? []).compactMap(\.string))))
            case "item":
                if let v = e.v["it"], let it = BoardItem(v) { out.append(HistoryEvent(t: e.t, kind: .item(it))) }
            case "text":
                let key = (e.v["id"]?.string ?? "") + "~" + BoardHistory.draftKey(e.v["d"])
                out.append(HistoryEvent(t: e.t, kind: .words(key, e.v["md"]?.string ?? "")))
            case "type":
                let key = (e.v["id"]?.string ?? "") + "~" + BoardHistory.draftKey(e.v["d"])
                for q in e.v["k"]?.array ?? [] {
                    guard let a = q.array else { continue }
                    func num(_ i: Int) -> Double { i < a.count ? (a[i].number ?? 0) : 0 }
                    out.append(HistoryEvent(t: e.t + num(0), kind: .key(key, Int(num(1)), Int(num(2)), a.count > 3 ? (a[3].string ?? "") : "")))
                }
            case "open":
                out.append(HistoryEvent(t: e.t, kind: .open))
            default: break
            }
        }
        // keystrokes of a burst can run past the next line's time: keep the whole timeline in order (stable)
        let sorted = out.enumerated().sorted { $0.element.t != $1.element.t ? $0.element.t < $1.element.t : $0.offset < $1.offset }.map(\.element)
        let first = sorted.first?.t ?? 0
        ev = sorted
        start = first
        end = sorted.reduce(first) { Swift.max($0, $1.t + $1.dur) }
        self.rough = rough
    }

    public typealias Line = BoardHistory.Line

    /// Stretches of work (a gap of more than `gap` ms starts another), for the scrubber's marks.
    public func sessions(gap: Double = 30 * 60000) -> [(start: Double, end: Double)] {
        var out: [(start: Double, end: Double)] = []
        for e in ev {
            let end = e.t + e.dur
            var isOpen = false
            if case .open = e.kind { isOpen = true }
            if let last = out.last, !(e.t - last.end > gap || (isOpen && e.t - last.end > 60000)) {
                out[out.count - 1].end = max(last.end, end)
            } else {
                out.append((e.t, end))
            }
        }
        return out
    }
}

// MARK: - the replayer

/// The board at a moment of a timeline. Going forward applies events; going back starts again from the nearest checkpoint.
public final class HistoryReplayer {
    struct State {
        var order: [String] = []
        var strokes: [String: (s: BoardStroke, ev: Int)] = [:]
        var itemOrder: [String] = []
        var items: [String: BoardItem] = [:]
        var md: [String: String] = [:]
    }
    public let tl: HistoryTimeline
    private var st = State()
    private var n = 0
    private var t: Double = 0
    private var checks: [(n: Int, st: State)] = [(0, State())]
    private static let every = 400

    public init(_ tl: HistoryTimeline) { self.tl = tl }

    /// How many events happen at or before t.
    public func count(at t: Double) -> Int {
        var lo = 0, hi = tl.ev.count
        while lo < hi { let m = (lo + hi) / 2; if tl.ev[m].t <= t { lo = m + 1 } else { hi = m } }
        return lo
    }

    private func apply(_ i: Int) {
        let e = tl.ev[i]
        switch e.kind {
        case .stroke(let s):
            if st.strokes[s.id] == nil { st.order.append(s.id) }
            st.strokes[s.id] = (s, i)
        case .erase(let ids):
            let gone = Set(ids)
            if ids.contains(where: { st.strokes[$0] != nil }) { st.order.removeAll { gone.contains($0) } }
            if ids.contains(where: { st.items[$0] != nil }) { st.itemOrder.removeAll { gone.contains($0) } }
            for id in ids { st.strokes[id] = nil; st.items[id] = nil }
        case .item(let it):
            if st.items[it.id] == nil { st.itemOrder.append(it.id) }
            st.items[it.id] = it
        case .words(let key, let md):
            st.md[key] = md
        case .key(let key, let at, let del, let ins):
            st.md[key] = BoardHistory.applyKey(st.md[key] ?? first(key), at: at, del: del, ins: ins)
        case .open:
            break
        }
    }

    /// Lines without a draft belong to a block's first draft.
    private func first(_ key: String) -> String {
        guard let i = key.lastIndex(of: "~") else { return "" }
        let id = String(key[..<i]), d = String(key[key.index(after: i)...])
        guard !d.isEmpty, let it = st.items[id], let ds = it.json["drafts"]?.array, let f = ds.first,
              BoardHistory.draftKey(f["id"]) == d else { return "" }
        return st.md[id + "~"] ?? ""
    }

    @discardableResult
    public func seek(_ t: Double) -> HistoryReplayer {
        let want = count(at: t)
        if want < n {
            var c = checks[0]
            for k in checks where k.n <= want && k.n > c.n { c = k }
            st = c.st; n = c.n
        }
        while n < want {
            apply(n); n += 1
            if n % Self.every == 0, !checks.contains(where: { $0.n == n }) { checks.append((n, st)) }
        }
        self.t = t
        return self
    }

    /// The strokes as of now, in drawing order.
    public var strokes: [BoardStroke] { st.order.compactMap { st.strokes[$0]?.s } }

    /// The strokes still being written at this moment, with how far (seconds into the stroke).
    public var writing: [(s: BoardStroke, upTo: Double)] {
        var out: [(s: BoardStroke, upTo: Double)] = []
        var i = n - 1
        while i >= 0 {
            let e = tl.ev[i]
            if t - e.t > 60000 { break }
            if case .stroke(let s) = e.kind, e.dur > 0, t < e.t + e.dur, st.strokes[s.id]?.ev == i { out.append((s, (t - e.t) / 1000)) }
            i -= 1
        }
        return out
    }

    /// The items as of now, and each text block's words (its current draft's).
    public var items: [BoardItem] { st.itemOrder.compactMap { st.items[$0] } }
    public var texts: [String: String] {
        var out: [String: String] = [:]
        for it in st.items.values where it.type == "text" {
            let d = BoardHistory.draftKey(it.json["draft"])
            var md = st.md[it.id + "~" + d]
            if md == nil, !d.isEmpty { let f = first(it.id + "~" + d); if !f.isEmpty { md = f } }
            out[it.id] = md ?? st.md[it.id + "~"] ?? ""
        }
        return out
    }

    /// The board at this moment.
    public var state: BoardState { BoardState(strokes: strokes, items: items, texts: texts) }

    /// A stroke as far as it was written `sec` seconds in (at least its first point; kept parts are not shown while it is written).
    public static func partStroke(_ s: BoardStroke, _ sec: Double) -> BoardStroke {
        let pts = s.points.filter { !($0.count > 5 && $0[5] > sec) }
        var out = BoardStroke(id: s.id, ink: s.ink, color: s.color, points: pts.isEmpty ? Array(s.points.prefix(1)) : pts)
        out.raw = nil
        return out
    }
}

// MARK: - the clock

/// Real time <-> play time. With `skip`, a pause longer than `max` between one thing ending and the next beginning plays as `gap`.
public struct PlayClock {
    public private(set) var points: [(real: Double, play: Double)]

    public init(_ tl: HistoryTimeline, skip: Bool = true, max maxPause: Double = 3000, gap: Double = 600) {
        var pts: [(real: Double, play: Double)] = [(tl.start, 0)]
        if skip {
            var busy = tl.start
            for e in tl.ev {
                if e.t - busy > maxPause {
                    let last = pts[pts.count - 1]
                    let pa = last.play + (busy - last.real)
                    pts.append((busy, pa)); pts.append((e.t, pa + gap))
                }
                busy = Swift.max(busy, e.t + e.dur)
            }
        }
        let last = pts[pts.count - 1]
        pts.append((Swift.max(tl.end, last.real), last.play + Swift.max(0, tl.end - last.real)))
        points = pts
    }

    public var length: Double { points[points.count - 1].play }

    public func toPlay(_ t: Double) -> Double { lerp(t, playToReal: false) }
    public func toReal(_ p: Double) -> Double { lerp(p, playToReal: true) }

    private func lerp(_ v: Double, playToReal: Bool) -> Double {
        func a(_ p: (real: Double, play: Double)) -> Double { playToReal ? p.play : p.real }
        func b(_ p: (real: Double, play: Double)) -> Double { playToReal ? p.real : p.play }
        for i in 1..<points.count {
            let A = points[i - 1], B = points[i]
            if v <= a(B) || i == points.count - 1 {
                let span = a(B) - a(A)
                return span > 0 ? b(A) + (b(B) - b(A)) * Swift.max(0, Swift.min(1, (v - a(A)) / span)) : b(B)
            }
        }
        return b(points[0])
    }
}

// MARK: - the board's picture

/// thumb.png in the board: about 480 px wide, rewritten on save at most once a minute; the iPad's notebook page shows it on the card.
public enum BoardThumb {
    public static let file = "thumb.png"
    public static let width: Double = 480, height: Double = 360
    public static let every: Double = 60

    /// The part of the board the picture shows (as the laptop's format.js thumbFrame): `box` everything on the board (nil when empty);
    /// at most `span` units wide, 4:3, from the top left of the content.
    public static func frame(_ box: (x0: Double, y0: Double, x1: Double, y1: Double)?, span: Double = 1600) -> (x: Double, y: Double, w: Double, h: Double) {
        guard let box else { return (0, 0, span / 2, span / 2 * height / width) }
        let pad = 24.0, cw = box.x1 - box.x0 + 2 * pad, ch = box.y1 - box.y0 + 2 * pad
        let w = min(span, max(cw, ch * width / height, 320))
        let h = w * height / width
        let x = cw < w ? box.x0 - pad - (w - cw) / 2 : box.x0 - pad
        return (x, box.y0 - pad, w, h)
    }
}
