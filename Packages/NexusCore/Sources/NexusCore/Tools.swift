import Foundation

/// Tools on boards, the same as the laptop's `renderer/src/tools/catalog.js` (nexus docs/data-format.md "Tools on the board").
///
/// A tool is one self-contained .html page that runs offline, with no access to files, and talks to whoever shows it only by
/// postMessage: the host sends `{"nexus":"tool","type":"init","state","theme"}`, the page answers `{"type":"ready"}` once and
/// `{"type":"state","state"}` when what it shows changes. On a board a tool is an item:
///
///     {"id","type":"tool","x","y","w","h","src":"nexus:tool/<name>" | "<an .html file, relative to the board>",
///      "show":"live"|"picture","image":"files/<picture>.png","state":{...}}
///
/// `h` includes the card's 30-unit head. The built-in tools are the laptop's built pages, which it writes into the data folder's
/// `.nexus-tools/` (with `tools.json`) and sync brings here.
public enum ToolCatalog {
    public struct Tool: Equatable {
        public var name: String
        public var title: String
        public var desc: String
        public var w: Double
        public var h: Double
    }

    public static let tools: [Tool] = [
        Tool(name: "molecules", title: "Molecules", desc: "Type or draw a molecule: Lewis structure, shape, charges, oxidation states", w: 760, h: 620),
        Tool(name: "vsepr", title: "VSEPR chart", desc: "Every shape by bonding and lone pairs, with a model to turn", w: 900, h: 640),
        Tool(name: "enthalpies", title: "Enthalpies", desc: "Born–Haber cycles, every enthalpy term, which method to use", w: 820, h: 620),
    ]
    public static let dir = ".nexus-tools"
    public static let indexFile = dir + "/tools.json"
    public static let format = "nexus-tools/1"
    public static let prefix = "nexus:tool/"
    /// A card's saved state, as JSON text (JavaScript string length, as the laptop counts it).
    public static let stateMax = 32 * 1024
    public static let headHeight: Double = 30
    public static let minW: Double = 220, minH: Double = 160
    /// The board feature a tool item needs (BoardFormat.features).
    public static let feature = "tool"

    public static func tool(named n: String) -> Tool? { tools.first { $0.name == n } }
    public static func builtinSrc(_ name: String) -> String { prefix + name }
    public static func builtinFile(_ name: String) -> String { dir + "/" + name + ".html" }

    public enum Src: Equatable {
        case builtin(String)
        /// An .html file, relative to the board.
        case file(String)
    }

    /// A tool item's src read, or nil when it is neither a built-in tool nor a plain relative .html path.
    public static func parseSrc(_ src: String?) -> Src? {
        let s = src ?? ""
        if s.hasPrefix(prefix) {
            let name = String(s.dropFirst(prefix.count))
            return name.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil ? .builtin(name) : nil
        }
        guard s.range(of: #"\.html?$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        if s.hasPrefix("/") || s.contains("\\") || s.range(of: "^[a-zA-Z]+:", options: .regularExpression) != nil { return nil }
        return .file(s)
    }

    /// What a card's head and the panel call a tool.
    public static func title(_ src: String?) -> String {
        switch parseSrc(src) {
        case .builtin(let n): return tool(named: n)?.title ?? n
        case .file(let rel):
            let last = rel.split(separator: "/").last.map(String.init) ?? rel
            return last.replacingOccurrences(of: #"\.html?$"#, with: "", options: [.regularExpression, .caseInsensitive])
        case nil: return "Tool"
        }
    }

    /// The page's file in the data folder, or nil when the src can't be shown (unknown, or a path that leaves the data folder).
    public static func pageURL(_ src: String?, board: URL, root: URL) -> URL? {
        switch parseSrc(src) {
        case .builtin(let n):
            guard tool(named: n) != nil else { return nil }
            return root.appendingPathComponent(builtinFile(n))
        case .file(let rel):
            return BoardFiles.resolve(rel, board: board, root: root)
        case nil: return nil
        }
    }

    /// A state a tool sent: kept only when it is an object whose JSON fits in `stateMax`.
    public static func keepState(_ v: JSONValue?) -> JSONValue? {
        guard let v, case .object = v else { return nil }
        return v.text.utf16.count <= stateMax ? v : nil
    }

    public enum Message: Equatable {
        case ready
        case state(JSONValue)
        case size(Double)
    }

    /// A message from a tool page (the JSON text the iPad's web view passes on), checked as the laptop's `toolMessage`.
    public static func message(_ text: String) -> Message? {
        guard let d = try? JSONValue.parse(text), d["nexus"]?.string == "tool" else { return nil }
        switch d["type"]?.string {
        case "ready": return .ready
        case "state": return keepState(d["state"]).map { .state($0) }
        case "size":
            guard let h = d["h"]?.number, h.isFinite else { return nil }
            return .size(max(80, min(4000, h.rounded())))
        default: return nil
        }
    }

    /// The script that hands a page its init: `state` (or null) and a light or dark theme.
    public static func initScript(state: JSONValue?, dark: Bool) -> String {
        let msg: JSONValue = .object([
            ("nexus", .string("tool")), ("type", .string("init")), ("state", state ?? .null),
            ("theme", .object([("dark", .bool(dark)), ("vars", .object([]))])),
        ])
        // JSON is JavaScript, but U+2028 / U+2029 inside a string end a line in older engines
        let js = msg.text.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "window.postMessage(\(js), '*'); true;"
    }

    /// A new tool item, keys in the laptop's order (boardtools.js addToolItem). `w`, `h` are the tool's own size, without the head.
    public static func item(id: String, src: String, x: Double, y: Double, w: Double? = nil, h: Double? = nil,
                            image: String? = nil, state: JSONValue? = nil) -> BoardItem {
        var tw: Double = 640, th: Double = 480
        if case .builtin(let n) = parseSrc(src), let t = tool(named: n) { tw = t.w; th = t.h }
        var fields: [(String, JSONValue)] = [
            ("w", .number((w ?? tw).rounded())), ("h", .number(((h ?? th) + headHeight).rounded())),
            ("src", .string(src)), ("show", .string(image == nil ? "live" : "picture")),
        ]
        if let image { fields.append(("image", .string(image))) }
        if let s = keepState(state) { fields.append(("state", s)) }
        return BoardItem(id: id, type: "tool", x: x.rounded(), y: y.rounded(), fields: fields)
    }

    /// The built-in tools whose pages the laptop has written (tools.json's list), or nil when tools.json is missing or not this format.
    public static func readIndex(_ text: String?) -> [String]? {
        guard let text, let o = try? JSONValue.parse(text), o["format"]?.string == format else { return nil }
        return (o["tools"]?.array ?? []).compactMap { $0["name"]?.string }
    }

    /// The folders whose .html files are this board's notebook tools (as the laptop's notebookTools): the folder the board is in,
    /// and its parent when that is a notebook under notebooks/. Paths relative to the data folder.
    public static func notebookDirs(boardPath: String) -> [String] {
        let dir = parent(boardPath)
        var out = [dir]
        let up = parent(dir)
        if !up.isEmpty, up.hasPrefix("notebooks/") { out.append(up) }
        return out
    }

    /// `file` (relative to the data folder) as a src relative to the board folder `boardPath`, as the laptop's `relTo`.
    public static func relative(_ file: String, fromBoard boardPath: String) -> String {
        let a = boardPath.split(separator: "/").map(String.init), b = file.split(separator: "/").map(String.init)
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        return (Array(repeating: "..", count: a.count - i) + b[i...]).joined(separator: "/")
    }

    static func parent(_ p: String) -> String {
        guard let i = p.lastIndex(of: "/") else { return "" }
        return String(p[..<i])
    }
}
