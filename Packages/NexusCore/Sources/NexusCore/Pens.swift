import Foundation

/// Your pens, shared with the laptop through the data folder: `nexus-pens.json` at its top (the Nexus repo's docs/data-format.md
/// "Pens", the new laptop app's desktop/backend/src/pens.rs, whose rules these are):
///
/// `{"format": "nexus-pens/1", "pen": {"color": "#RRGGBBAA", "step": 0-5}, "pencil": {..}, "marker": {..},
///   "colors": {"pen": [ten], "marker": [eight]}, "widths": {"pen": [six], "pencil": [six], "marker": [six]}, "eraser": "stroke" | "part"}`
///
/// `step` is the width step (Extra fine to Extra bold, the same six on both apps); `colors` the whole rows as the user has them (pen
/// and pencil share the pen row; the iPad's highlighter is the marker); `widths` each ink's six widths in board units as the user
/// set them on the laptop (0.2 to 120; missing: the built-in ones). Every part is optional, and a part that isn't well formed is
/// read as missing. A save names only what changed and is laid over the file as it is on disk, keeping parts this app doesn't know,
/// so a change the laptop made to something else stays. What stays on each device: the tool in hand, the bar, the shapes' colour.
/// Pure: the app's BoardTools reads and writes the file.
public enum Pens {
    public static let file = "nexus-pens.json"
    public static let format = "nexus-pens/1"
    public static let inks = ["pen", "pencil", "marker"]
    static let rows: [(String, Int)] = [("pen", 10), ("marker", 8)]

    /// The laptop's built-in widths (desktop/src/board/tools.ts WIDTHS). A width the user set there is read as so many times the
    /// laptop's own, and the iPad draws its step that many times its own (PencilKit's inks are not the laptop's: its pencil is wider).
    public static let laptopWidths: [String: [Double]] = ["pen": [1, 1.5, 3, 4.5, 6, 10], "pencil": [0.6, 1, 2, 3, 4, 6], "marker": [6, 12, 20, 30, 44, 60]]

    public struct Ink: Equatable {
        public var color: String
        public var step: Int
        public init(color: String, step: Int) { self.color = color; self.step = step }
    }

    /// The well-formed parts of the file, or the parts of a save.
    public struct Shared: Equatable {
        public var inks: [String: Ink] = [:]
        public var colors: [String: [String]] = [:]
        public var widths: [String: [Double]] = [:]
        public var eraser: String?
        public init() {}
        public var isEmpty: Bool { inks.isEmpty && colors.isEmpty && widths.isEmpty && eraser == nil }
    }

    /// A colour as the file keeps it, `#RRGGBBAA` in capitals (a `#RRGGBB` is opaque); nil when it isn't one.
    public static func color(_ s: String?) -> String? {
        guard let s else { return nil }
        var h = Substring(s.trimmingCharacters(in: .whitespacesAndNewlines))
        while h.hasPrefix("#") { h = h.dropFirst() }
        guard h.count == 6 || h.count == 8, h.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        return "#" + h.uppercased() + (h.count == 6 ? "FF" : "")
    }
    /// A file colour as the iPad's rows keep it: `#RRGGBB` when opaque.
    public static func short(_ c: String) -> String { c.count == 9 && c.hasSuffix("FF") ? String(c.prefix(7)) : c }

    static func ink(_ v: JSONValue?) -> Ink? {
        guard let c = color(v?["color"]?.string), let n = v?["step"]?.number, n.isFinite else { return nil }
        return Ink(color: c, step: Int(min(5, max(0, n.rounded()))))
    }
    static func widths(_ v: [Double]?) -> [Double]? {
        guard let v, v.count == 6, v.allSatisfy({ $0.isFinite && $0 >= 0.2 && $0 <= 120 }) else { return nil }
        return v.map { ($0 * 100).rounded() / 100 }
    }
    static func row(_ v: [String]?, _ n: Int) -> [String]? {
        guard let v, v.count == n else { return nil }
        let c = v.compactMap(color)
        return c.count == n ? c : nil
    }
    static func numbers(_ v: JSONValue?) -> [Double]? {
        guard let a = v?.array else { return nil }
        let n = a.compactMap(\.number)
        return n.count == a.count ? n : nil
    }
    static func strings(_ v: JSONValue?) -> [String]? {
        guard let a = v?.array else { return nil }
        let s = a.compactMap(\.string)
        return s.count == a.count ? s : nil
    }

    /// The file as the iPad reads it: only the well-formed parts (no file, not JSON or another format: nothing).
    public static func read(_ text: String?) -> Shared {
        var out = Shared()
        guard let text, let f = try? JSONValue.parse(text), f["format"]?.string == format else { return out }
        for k in inks { if let i = ink(f[k]) { out.inks[k] = i } }
        for (k, n) in rows { if let r = row(strings(f["colors"]?[k]), n) { out.colors[k] = r } }
        for k in inks { if let w = widths(numbers(f["widths"]?[k])) { out.widths[k] = w } }
        if let e = f["eraser"]?.string, e == "stroke" || e == "part" { out.eraser = e }
        return out
    }

    /// The parts of `b` that differ from `a` (what a save names).
    public static func changes(from a: Shared, to b: Shared) -> Shared {
        var out = Shared()
        for (k, v) in b.inks where a.inks[k] != v { out.inks[k] = v }
        for (k, v) in b.colors where a.colors[k] != v { out.colors[k] = v }
        for (k, v) in b.widths where a.widths[k] != v { out.widths[k] = v }
        if let e = b.eraser, e != a.eraser { out.eraser = e }
        return out
    }

    /// `set` laid over the file on disk (none, not JSON or another format: a new file), as the file's text. A part of `set` that
    /// isn't well formed is left out.
    public static func merge(_ disk: String?, _ set: Shared) -> String {
        var file: [(String, JSONValue)] = []
        if let disk, let d = try? JSONValue.parse(disk), d["format"]?.string == format, let o = d.object { file = o }
        var f = JSONValue.object(file).setting("format", .string(format))
        for k in inks {
            if let i = set.inks[k], let c = color(i.color) {
                f = f.setting(k, .object([("color", .string(c)), ("step", .number(Double(min(5, max(0, i.step)))))]))
            }
        }
        var cols = f["colors"]?.object.map(JSONValue.object) ?? .object([])
        var colsSet = false
        for (k, n) in rows { if let r = row(set.colors[k], n) { cols = cols.setting(k, .array(r.map(JSONValue.string))); colsSet = true } }
        if colsSet { f = f.setting("colors", cols) }
        var ws = f["widths"]?.object.map(JSONValue.object) ?? .object([])
        var wsSet = false
        for k in inks { if let w = widths(set.widths[k]) { ws = ws.setting(k, .array(w.map(JSONValue.number))); wsSet = true } }
        if wsSet { f = f.setting("widths", ws) }
        if let e = set.eraser, e == "stroke" || e == "part" { f = f.setting("eraser", .string(e)) }
        // the format first, then the parts in the laptop's order, then whatever another app keeps
        let order = ["format", "pen", "pencil", "marker", "colors", "widths", "eraser"]
        let o = f.object ?? []
        let sorted = order.compactMap { k in o.first { $0.0 == k } } + o.filter { !order.contains($0.0) }
        return JSONValue.object(sorted).pretty + "\n"
    }

    /// The iPad's six widths for an ink with the laptop's shared ones laid over its own `own` (see laptopWidths); nil when the file
    /// has none for it.
    public static func scaled(_ shared: [Double]?, ink: String, own: [Double]) -> [Double]? {
        guard let s = widths(shared), let base = laptopWidths[ink], own.count == 6 else { return nil }
        return own.indices.map { (own[$0] * s[$0] / base[$0] * 100).rounded() / 100 }
    }
}
