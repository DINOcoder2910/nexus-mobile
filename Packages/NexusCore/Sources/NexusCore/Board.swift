import Foundation

/// A board's files, the same as the laptop's `renderer/src/board/format.js` (nexus docs/data-format.md "Boards"):
///
///     Cells.board/
///       board.json            {"format": "nexus-board/1", "created": "...", "tile": 1024}
///       tiles/<tx>_<ty>.json  what is in one 1024-unit square: strokes (PencilKit's points) and items, one per line
///       text/<id>.md          a typed block's markdown
///       files/                images put on the board
///
/// Units are iPad points, y down, any sign. Saving rewrites only the tiles whose text changed.
public enum BoardFormat {
    public static let format = "nexus-board/1"
    public static let tileFormat = "nexus-board-tile/1"
    public static let tile: Double = 1024
    public static let pdfWidth: Double = 820
    public static let pdfGap: Double = 24
    public static let pointFields = ["x", "y", "force", "azimuth", "altitude", "t", "w", "h", "opacity"]
    /// The item types this app draws and edits; any other type (made by a newer Nexus) is kept as it is and shown as a placeholder.
    public static let itemTypes: Set<String> = ["text", "image", "pdf", "shape", "link"]
    /// The board redesign's features this app understands (nexus docs/data-format.md "Features"): a board.json naming one not here
    /// opens read-only. Add a name in the same change that makes the app read and write that feature.
    public static let features: Set<String> = [BoardLinks.feature]
    /// A placeholder's size when a foreign item has none.
    public static let foreignSize = (w: 200.0, h: 80.0)

    /// board.json with `name` added to its features (the first time this app writes that feature); the same when it is there already.
    public static func withFeature(_ meta: JSONValue, _ name: String) -> JSONValue {
        var f = meta["features"]?.array ?? []
        if f.contains(where: { $0.string == name }) { return meta }
        f.append(.string(name))
        return meta.setting("features", .array(f))
    }

    /// board.json's text as the laptop writes it (`JSON.stringify(meta, null, 2)` and a newline).
    public static func metaText(_ meta: JSONValue) -> String { meta.pretty + "\n" }

    /// The features a board.json names that this app doesn't know, in the order named.
    public static func unknownFeatures(_ meta: JSONValue?, known: Set<String> = features) -> [String] {
        var out: [String] = []
        for f in meta?["features"]?.array?.compactMap(\.string) ?? [] where !known.contains(f) && !out.contains(f) { out.append(f) }
        return out
    }
    public static let shapes: Set<String> = ["rect", "ellipse", "line", "arrow"]
    public static let notebooks = "notebooks"
    /// A typed block wraps at this width until it is given its own (the laptop's TEXT_W).
    public static let textWidth: Double = 560
    public static let defaultTextSize: Double = 16

    public static func tileKey(_ x: Double, _ y: Double, size: Double = tile) -> String {
        "\(Int(floor(x / size)))_\(Int(floor(y / size)))"
    }
    public static func tileFile(_ key: String) -> String { "tiles/\(key).json" }
    public static func keyOfFile(_ name: String) -> String? {
        guard name.hasSuffix(".json") else { return nil }
        let k = String(name.dropLast(5))
        let parts = k.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil else { return nil }
        return k
    }
    public static func textFile(_ id: String) -> String { "text/\(id).md" }

    static let idChars = Array("abcdefghijkmnopqrstuvwxyz23456789")
    /// A new id for a stroke or item: 5 or more of a-z2-9, not in `taken`.
    public static func newId(taken: Set<String>) -> String {
        var n = 5
        while true {
            for _ in 0..<20 {
                let s = String((0..<n).map { _ in idChars.randomElement()! })
                if !taken.contains(s) { return s }
            }
            n += 1
        }
    }

    /// A folder or board name that isn't taken (compared without case), cleaned of characters Windows can't hold.
    public static func freeName(_ want: String, taken: Set<String>, suffix: String = "") -> String {
        let low = Set(taken.map { $0.lowercased() })
        var clean = want.replacingOccurrences(of: #"[\\/:*?"<>|]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        while clean.hasSuffix(".") || clean.hasSuffix(" ") { clean.removeLast() }
        if clean.isEmpty { clean = "Untitled" }
        if !low.contains((clean + suffix).lowercased()) { return clean + suffix }
        var i = 2
        while low.contains("\(clean) \(i)\(suffix)".lowercased()) { i += 1 }
        return "\(clean) \(i)\(suffix)"
    }

    /// "2026-11-11T09:30Z", as the laptop writes `created`.
    public static func boardJSON(created: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return "{\n  \"format\": \"\(format)\",\n  \"created\": \"\(f.string(from: created))Z\",\n  \"tile\": 1024\n}\n"
    }
}

/// One stroke as the files keep it: PencilKit's ink id, `#RRGGBBAA`, and its control points (`pointFields` order).
public struct BoardStroke: Equatable {
    public var id: String
    public var ink: String
    public var color: String
    public var points: [[Double]]
    /// Parts kept of a partly erased stroke (parametric), or nil.
    public var ranges: [[Double]]?
    /// The stroke as it was read (unknown keys kept); nil for a new one.
    public var raw: JSONValue?

    public init(id: String, ink: String, color: String, points: [[Double]], ranges: [[Double]]? = nil) {
        self.id = id; self.ink = ink; self.color = color; self.points = points; self.ranges = ranges
    }

    public var tileKey: String { points.first.map { BoardFormat.tileKey($0[0], $0[1]) } ?? "0_0" }

    /// The JSON written for it: the stroke as it was read when nothing changed, else its fields in the laptop's order.
    public var json: JSONValue {
        if let raw, BoardStroke(raw, fields: nil)?.sameContent(self) == true { return raw }
        var o: [(String, JSONValue)] = [("id", .string(id)), ("ink", .string(ink)), ("color", .string(color)),
                                        ("points", .array(points.map { .array($0.map { .number($0) }) }))]
        if let ranges { o.append(("ranges", .array(ranges.map { .array($0.map { .number($0) }) }))) }
        if case .object(let extra)? = raw {
            for (k, v) in extra where !["id", "ink", "color", "points", "ranges"].contains(k) { o.append((k, v)) }
        }
        return .object(o)
    }

    func sameContent(_ o: BoardStroke) -> Bool { id == o.id && ink == o.ink && color == o.color && points == o.points && ranges == o.ranges }

    /// Reads a stroke; `fields` is the tile's pointFields (a tile written with another order is remapped).
    public init?(_ v: JSONValue, fields: [String]?) {
        guard let pts = v["points"]?.array else { return nil }
        var points: [[Double]] = []
        let order = fields ?? BoardFormat.pointFields
        let same = order == BoardFormat.pointFields
        let dflt: [String: Double] = ["force": 1, "azimuth": 0, "altitude": Double.pi / 2, "t": 0, "w": 2, "h": 2, "opacity": 1]
        for p in pts {
            guard let a = p.array?.map({ $0.number }), a.count >= 2, let x = a[0], let y = a[1], x.isFinite, y.isFinite else { continue }
            if same {
                points.append(a.map { $0 ?? 0 })
            } else {
                points.append(BoardFormat.pointFields.map { f in
                    if let i = order.firstIndex(of: f), i < a.count, let n = a[i] { return n }
                    return dflt[f] ?? 0
                })
            }
        }
        guard !points.isEmpty else { return nil }
        id = v["id"]?.string ?? ""
        ink = v["ink"]?.string ?? "com.apple.ink.pen"
        let c = v["color"]?.string ?? ""
        color = c.range(of: #"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$"#, options: .regularExpression) != nil ? c : "#000000FF"
        self.points = points
        ranges = v["ranges"]?.array?.compactMap { $0.array?.compactMap(\.number) }
        raw = v
    }
}

/// An item on a board: typed text, an image, a PDF printout, a shape. Kept as its JSON object so fields the iPad doesn't know survive.
public struct BoardItem: Equatable, Identifiable {
    public var json: JSONValue

    public init?(_ v: JSONValue) {
        guard let id = v["id"]?.string, !id.isEmpty, let t = v["type"]?.string, !t.isEmpty,
              let x = v["x"]?.number, let y = v["y"]?.number, x.isFinite, y.isFinite else { return nil }
        json = v
        if t == "shape", !BoardFormat.shapes.contains(v["shape"]?.string ?? "") { json = json.setting("shape", .string("rect")) }
    }

    public init(id: String, type: String, x: Double, y: Double, fields: [(String, JSONValue)] = []) {
        json = .object([("id", .string(id)), ("type", .string(type)), ("x", .number(x)), ("y", .number(y))] + fields)
    }

    public var id: String { json["id"]?.string ?? "" }
    public var type: String { json["type"]?.string ?? "" }
    public var x: Double { json["x"]?.number ?? 0 }
    public var y: Double { json["y"]?.number ?? 0 }
    public var w: Double? { json["w"]?.number }
    public var h: Double? { json["h"]?.number }
    public var src: String? { json["src"]?.string }
    public var shape: String? { json["shape"]?.string }
    public var tileKey: String { BoardFormat.tileKey(x, y) }
    /// Made by a newer Nexus: a type this app doesn't draw. Kept and written back unchanged.
    public var isForeign: Bool { !BoardFormat.itemTypes.contains(type) }
    public func number(_ k: String) -> Double? { json[k]?.number }
    public func string(_ k: String) -> String? { json[k]?.string }

    public func with(_ key: String, _ value: JSONValue?) -> BoardItem {
        var c = self; c.json = json.setting(key, value); return c
    }

    /// As the laptop writes an item: numbers to 2 decimals, fields starting with `_` left out.
    public var cleanJSON: JSONValue {
        guard case .object(let o) = json else { return json }
        return .object(o.filter { !$0.0.hasPrefix("_") }.map { k, v in
            if case .number(let n) = v { return (k, .number((n * 100).rounded() / 100)) }
            return (k, v)
        })
    }
}

/// A whole board read from its folder.
public struct BoardContent {
    public var strokes: [BoardStroke] = []
    public var items: [BoardItem] = []
    /// A typed block's markdown by item id.
    public var texts: [String: String] = [:]
    /// What each tile file held when read (or last written), to write only what changed.
    public var tilesOnDisk: [String: String] = [:]
    public var textsOnDisk: [String: String] = [:]
    /// board.json as read (unknown keys kept), and what it was on disk: save writes it when the two differ (paper, features, ...).
    /// Change it with `BoardFormat.withFeature` or `setting`; nil for an ink test board until its first save.
    public var meta: JSONValue?
    public var metaOnDisk: JSONValue?
    /// A newer format: shown, never written.
    public var readOnly: String?
    public var created: String?

    public init() {}
}

public enum BoardFiles {
    public enum Failure: Error, CustomStringConvertible {
        case notABoard(String)
        public var description: String { if case .notABoard(let m) = self { return m }; return "" }
    }

    /// A tile's text, exactly as the laptop's `tileJson`: strokes in drawing order, items by id, one per line.
    public static func tileJSON(strokes: [BoardStroke], items: [BoardItem]) -> String {
        let s = strokes.map { $0.json.text }
        let its = items.sorted { $0.id < $1.id }.map { $0.cleanJSON.text }
        let fields = JSONValue.array(BoardFormat.pointFields.map { .string($0) }).text
        return "{\"format\":\"\(BoardFormat.tileFormat)\",\"pointFields\":\(fields),\n\"strokes\":["
            + (s.isEmpty ? "" : "\n" + s.joined(separator: ",\n") + "\n") + "],\n\"items\":["
            + (its.isEmpty ? "" : "\n" + its.joined(separator: ",\n") + "\n") + "]}\n"
    }

    public static func parseTile(_ text: String) throws -> (strokes: [BoardStroke], items: [BoardItem]) {
        let v = try JSONValue.parse(text)
        let fields = v["pointFields"]?.array?.compactMap(\.string)
        let strokes = (v["strokes"]?.array ?? []).compactMap { BoardStroke($0, fields: fields) }
        let items = (v["items"]?.array ?? []).compactMap { BoardItem($0) }
        return (strokes, items)
    }

    /// Reads a `<name>.board` folder. A tile that doesn't parse is skipped (and never written over: it stays in `tilesOnDisk` as is).
    public static func load(_ board: URL) throws -> BoardContent {
        var c = BoardContent()
        let fm = FileManager.default
        guard let metaData = try? Data(contentsOf: board.appendingPathComponent("board.json")) else {
            throw Failure.notABoard("\(board.lastPathComponent) has no board.json")
        }
        let meta = try? JSONValue.parse(String(decoding: metaData, as: UTF8.self))
        let fmt = meta?["format"]?.string ?? ""
        c.created = meta?["created"]?.string
        if fmt == BoardFormat.format { c.meta = meta; c.metaOnDisk = meta }
        if fmt != BoardFormat.format {
            if fmt.hasPrefix("nexus-board/") { c.readOnly = "This board was made by a newer Nexus (\(fmt))." }
            else if fmt == "nexus-board-test/1" { return legacy(board, meta: meta) }
            else { throw Failure.notABoard("board.json is not a Nexus board") }
        }
        let unknown = BoardFormat.unknownFeatures(meta)
        if c.readOnly == nil, !unknown.isEmpty {
            c.readOnly = "This board uses \(unknown.joined(separator: ", ")) from a newer Nexus. Update the iPad app to edit it."
        }
        let tiles = board.appendingPathComponent("tiles")
        let names = ((try? fm.contentsOfDirectory(atPath: tiles.path)) ?? []).sorted()
        var seen = Set<String>()
        for name in names {
            guard let key = BoardFormat.keyOfFile(name),
                  let d = try? Data(contentsOf: tiles.appendingPathComponent(name)) else { continue }
            let text = String(decoding: d, as: UTF8.self)
            c.tilesOnDisk[key] = text
            guard let t = try? parseTile(text) else { continue }
            for s in t.strokes where s.id.isEmpty || !seen.contains(s.id) { seen.insert(s.id); c.strokes.append(s) }
            for it in t.items where !seen.contains(it.id) { seen.insert(it.id); c.items.append(it) }
        }
        for it in c.items where it.type == "text" {
            if let d = try? Data(contentsOf: board.appendingPathComponent(BoardFormat.textFile(it.id))) {
                let md = String(decoding: d, as: UTF8.self)
                c.texts[it.id] = md
                c.textsOnDisk[it.id] = md
            } else { c.texts[it.id] = "" }
        }
        // strokes with no id (an old export) get one, so they can be written
        var taken = seen
        for i in c.strokes.indices where c.strokes[i].id.isEmpty {
            let id = BoardFormat.newId(taken: taken); taken.insert(id); c.strokes[i].id = id
        }
        return c
    }

    /// An ink test board (board.json `nexus-board-test/1` + strokes.json + its PDF): read as it is; the first save writes the new format.
    static func legacy(_ board: URL, meta: JSONValue?) -> BoardContent {
        var c = BoardContent()
        if let d = try? Data(contentsOf: board.appendingPathComponent("strokes.json")), let v = try? JSONValue.parse(String(decoding: d, as: UTF8.self)) {
            let fields = v["pointFields"]?.array?.compactMap(\.string)
            // ids as the laptop gives them (`i<index>`), so both read an ink test board the same way
            for (i, s) in (v["strokes"]?.array ?? []).enumerated() {
                guard var st = BoardStroke(s, fields: fields) else { continue }
                st.raw = nil
                if st.id.isEmpty { st.id = "i\(i)" }
                c.strokes.append(st)
            }
        }
        if let pdf = meta?["pdf"]?.string, !pdf.isEmpty {
            c.items.append(BoardItem(id: "pdf1", type: "pdf", x: meta?["originX"]?.number ?? 60, y: meta?["originY"]?.number ?? 60,
                                     fields: [("src", .string(pdf)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap))]))
        }
        return c
    }

    /// The files to write for the board as it is now: every tile whose text differs from what is on disk (a tile left empty is
    /// written empty, as the laptop does), changed text blocks, and the text files of removed blocks to delete.
    public static func changes(_ c: BoardContent) -> (tiles: [String: String], texts: [String: String], removedTexts: [String]) {
        var byKey: [String: (s: [BoardStroke], i: [BoardItem])] = [:]
        for s in c.strokes { byKey[s.tileKey, default: ([], [])].s.append(s) }
        for it in c.items { byKey[it.tileKey, default: ([], [])].i.append(it) }
        var tiles: [String: String] = [:]
        for key in Set(byKey.keys).union(c.tilesOnDisk.keys) {
            let t = byKey[key] ?? ([], [])
            let text = tileJSON(strokes: t.s, items: t.i)
            if c.tilesOnDisk[key] != text {
                // a tile on disk that doesn't parse is never written over unless something now lives in it
                if let old = c.tilesOnDisk[key], (try? parseTile(old)) == nil, t.s.isEmpty, t.i.isEmpty { continue }
                tiles[key] = text
            }
        }
        var texts: [String: String] = [:]
        let textIds = Set(c.items.filter { $0.type == "text" }.map(\.id))
        for id in textIds { let md = c.texts[id] ?? ""; if c.textsOnDisk[id] != md { texts[id] = md } }
        let removed = c.textsOnDisk.keys.filter { !textIds.contains($0) }
        return (tiles, texts, removed.sorted())
    }

    /// Writes what changed; returns the content with its on-disk record brought up to date. `write` does an atomic write of one file.
    public static func save(_ c: BoardContent, to board: URL, write: (URL, String) throws -> Void,
                            remove: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) throws -> BoardContent {
        guard c.readOnly == nil else { return c }
        var out = c
        let fm = FileManager.default
        let metaURL = board.appendingPathComponent("board.json")
        if let d = try? Data(contentsOf: metaURL), (try? JSONValue.parse(String(decoding: d, as: UTF8.self)))?["format"]?.string != BoardFormat.format {
            let text = BoardFormat.boardJSON() // an ink test board becomes a real one on its first save
            try write(metaURL, text)
            out.meta = try? JSONValue.parse(text)
            out.metaOnDisk = out.meta
        } else if !fm.fileExists(atPath: metaURL.path) {
            try write(metaURL, c.meta.map(BoardFormat.metaText) ?? BoardFormat.boardJSON())
            out.metaOnDisk = c.meta
        } else if let m = c.meta, m != c.metaOnDisk {
            try write(metaURL, BoardFormat.metaText(m))
            out.metaOnDisk = m
        }
        let ch = changes(c)
        for (key, text) in ch.tiles {
            try write(board.appendingPathComponent(BoardFormat.tileFile(key)), text)
            out.tilesOnDisk[key] = text
        }
        for (id, md) in ch.texts {
            try write(board.appendingPathComponent(BoardFormat.textFile(id)), md)
            out.textsOnDisk[id] = md
        }
        for id in ch.removedTexts {
            try? remove(board.appendingPathComponent(BoardFormat.textFile(id)))
            out.textsOnDisk[id] = nil
        }
        return out
    }

    /// A PDF printout's page frames on the board: each `w` wide, `gap` apart, from the page sizes (rotation applied).
    /// Each page's frame on the board, from its top to its bottom (a page opened in two spans the room between its parts).
    public static func pdfFrames(_ item: BoardItem, sizes: [(w: Double, h: Double)]) -> [(x: Double, y: Double, w: Double, h: Double)] {
        var out = sizes.map { _ in (x: item.x, y: Double.nan, w: 0.0, h: 0.0) }
        for s in pdfSegments(item, sizes: sizes) {
            let f = out[s.page]
            if f.y.isNaN { out[s.page] = (s.x, s.y, s.w, s.h) } else { out[s.page].h = s.y + s.h - f.y }
        }
        return out
    }

    /// One drawn piece of a page: the whole page, or one part of a page opened in two (`top`, `bottom`: fractions of its height).
    public struct PdfSegment: Equatable {
        public var page: Int // from 0
        public var x, y, w, h: Double
        public var top, bottom: Double
    }

    /// Room in a printout (the pdf item's `space`, nexus docs/data-format.md "Space in a PDF"), cleaned: pages from 1, `at` 0...1,
    /// `gap` > 0, sorted by page then at.
    public static func pdfSpace(_ item: BoardItem) -> [(page: Int, at: Double, gap: Double)] {
        (item.json["space"]?.array ?? []).compactMap { v -> (page: Int, at: Double, gap: Double)? in
            guard let p = v["page"]?.number, p >= 1, let g = v["gap"]?.number, g > 0 else { return nil }
            return (Int(p), min(1, max(0, v["at"]?.number ?? 1)), g)
        }.sorted { ($0.page, $0.at) < ($1.page, $1.at) }
    }

    /// The pages laid down the board from the item's x, y, each `w` wide and `gap` apart, with the room in `space`: `at` 0 opens room
    /// above the page, 1 after it, and in between opens the page in two there (the lower part moves down by `gap`).
    public static func pdfSegments(_ item: BoardItem, sizes: [(w: Double, h: Double)]) -> [PdfSegment] {
        let w = item.w ?? BoardFormat.pdfWidth, gap = item.number("gap") ?? BoardFormat.pdfGap
        let space = pdfSpace(item)
        var y = item.y
        var out: [PdfSegment] = []
        for (i, s) in sizes.enumerated() {
            let h = w * (s.h / max(1, s.w))
            var top = 0.0
            for sp in space where sp.page == i + 1 {
                if sp.at <= 0 { y += sp.gap; continue }
                if sp.at >= 1 { continue }
                guard sp.at > top else { y += sp.gap; continue }
                out.append(PdfSegment(page: i, x: item.x, y: y, w: w, h: h * (sp.at - top), top: top, bottom: sp.at))
                y += h * (sp.at - top) + sp.gap
                top = sp.at
            }
            out.append(PdfSegment(page: i, x: item.x, y: y, w: w, h: h * (1 - top), top: top, bottom: 1))
            y += h * (1 - top) + gap
            for sp in space where sp.page == i + 1 && sp.at >= 1 { y += sp.gap }
        }
        return out
    }

    /// A path relative to the board ("files/a.png", "../Book.pdf") as a URL, or nil when it leaves `root` (the data folder).
    public static func resolve(_ rel: String, board: URL, root: URL) -> URL? {
        guard !rel.isEmpty, !rel.hasPrefix("/"), !rel.contains("\\"), rel.range(of: #"^[a-zA-Z]+:"#, options: .regularExpression) == nil else { return nil }
        var parts = board.standardizedFileURL.pathComponents
        for s in rel.split(separator: "/") {
            if s == "." { continue }
            if s == ".." { if parts.count > 1 { parts.removeLast() } else { return nil } } else { parts.append(String(s)) }
        }
        let path = NSString.path(withComponents: parts)
        let rootPath = root.standardizedFileURL.path
        guard path == rootPath || path.hasPrefix(rootPath + "/") else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// The notebooks: `notebooks/<notebook>/<section>/<board>.board`, a board may also sit straight in a notebook.
public struct Notebook: Identifiable, Hashable {
    public struct Section: Identifiable, Hashable {
        public var name: String
        public var path: String
        public var boards: [BoardRef]
        public var id: String { path }
    }
    public struct BoardRef: Identifiable, Hashable {
        public var name: String
        public var path: String
        public var id: String { path }
    }
    public var name: String
    public var path: String
    public var boards: [BoardRef]
    public var sections: [Section]
    public var id: String { path }

    /// Reads `notebooks/` of a data folder.
    public static func list(_ root: URL) -> [Notebook] {
        let fm = FileManager.default
        func dirs(_ rel: String) -> [String] {
            let url = root.appendingPathComponent(rel)
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map(\.lastPathComponent)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        }
        func boards(_ rel: String) -> [BoardRef] {
            dirs(rel).filter { $0.lowercased().hasSuffix(".board") }.map { BoardRef(name: String($0.dropLast(6)), path: rel + "/" + $0) }
        }
        let base = BoardFormat.notebooks
        return dirs(base).filter { !$0.lowercased().hasSuffix(".board") }.map { nb in
            let p = base + "/" + nb
            return Notebook(name: nb, path: p, boards: boards(p),
                            sections: dirs(p).filter { !$0.lowercased().hasSuffix(".board") }.map { s in
                                Section(name: s, path: p + "/" + s, boards: boards(p + "/" + s))
                            })
        }
    }
}
