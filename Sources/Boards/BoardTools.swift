import UIKit
import PencilKit
import NexusCore

/// The board's tools, in the bar (the redesign's Option B): what the Pencil does, each pen's colour and width, and the board
/// settings that go with them. Kept between boards and launches (UserDefaults), the same on every board. The pens themselves (each
/// ink's colour and size step, the colour rows, the sizes set on the laptop, the eraser) are shared with the laptop through the data
/// folder's nexus-pens.json (NexusCore Pens): read when a board opens and whenever the file changes, written a moment after a change.
enum BoardTool: String, CaseIterable {
    case hand, pen, pencil, highlighter, eraser, lasso, shapes, text, space

    var title: String {
        switch self {
        case .hand: return "Hand"
        case .pen: return "Pen"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        case .eraser: return "Eraser"
        case .lasso: return "Select"
        case .shapes: return "Shapes"
        case .text: return "Text"
        case .space: return "Insert space"
        }
    }

    var symbol: String {
        switch self {
        case .hand: return "hand.raised"
        case .pen: return "pencil.tip"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .eraser: return "eraser"
        case .lasso: return "lasso"
        case .shapes: return "square.on.circle"
        case .text: return "textformat"
        case .space: return "arrow.up.and.down.text.horizontal"
        }
    }

    /// Tools that put ink down (and so have colours and widths).
    var inks: Bool { self == .pen || self == .pencil || self == .highlighter || self == .shapes }
    /// Tools that let the Pencil draw on the canvas (the rest use it to scroll, type or make space).
    var drawsOnCanvas: Bool { inks || self == .eraser || self == .lasso }
}

final class BoardTools {
    static let shared = BoardTools()
    private let d = UserDefaults.standard

    enum PenKind: String, CaseIterable {
        case pen, monoline, fountain
        var title: String { self == .pen ? "Pen" : self == .monoline ? "Even line" : "Fountain pen" }
        var ink: PKInkingTool.InkType { self == .pen ? .pen : self == .monoline ? .monoline : .fountainPen }
    }

    enum Dark: String, CaseIterable {
        case follow, always, never
        var title: String { self == .follow ? "Follow iPad" : self == .always ? "Always dark" : "Never dark" }
    }

    /// The favourite colours: ten for pens, pencils and shapes, eight for the highlighter (the laptop's board has the same, board.js).
    /// The first six of each were the only ones before Nov 17 2026, so a row someone changed keeps its changes in place.
    static let penColors = ["#1B1B1B", "#2F6FEB", "#D93025", "#188038", "#E37400", "#8E44AD", "#6E6E73", "#0097A7", "#D81B60", "#8D5524"]
    static let markerColors = ["#FFE066", "#9BE7A0", "#FFB3C7", "#9FD3FF", "#FFC48C", "#D7B8FF", "#FF9F8F", "#CFCFCF"]
    /// Six widths per drawing tool (board units), Extra fine to Extra bold; the eraser keeps its three.
    static func widths(_ t: BoardTool) -> [CGFloat] {
        switch t {
        case .pencil: return [2.4, 3, 4, 6, 8, 12] // PencilKit draws a pencil 2.4 to 16 wide; the old Fine (2) drew 2.4
        case .highlighter: return [6, 12, 20, 32, 44, 60]
        case .eraser: return [10, 30, 60]
        default: return [1, 1.5, 3, 4.5, 6, 10]
        }
    }
    static let widthNames = ["Extra fine", "Fine", "Medium", "Thick", "Bold", "Extra bold"]
    /// Where the three widths from before Nov 17 2026 (Fine, Medium, Bold) are now: the same sizes as they drew. (The pencil's old
    /// Fine, 2, drew at PencilKit's least, 2.4, which is its first step now.)
    static func oldWidthSteps(_ t: BoardTool) -> [Int] { t == .pencil ? [0, 2, 4] : [1, 2, 4] }

    /// A saved row of colours brought up to `base`: the saved ones in their places, the new ones after them.
    static func fill(_ saved: [String], _ base: [String]) -> [String] {
        if saved.count == base.count { return saved }
        if saved.isEmpty || saved.count > base.count { return base }
        return Array(saved + base[saved.count...])
    }

    var tool: BoardTool {
        get { BoardTool(rawValue: d.string(forKey: "board.tool") ?? "") ?? .pen }
        set {
            if newValue != tool { d.set(tool.rawValue, forKey: "board.previousTool") }
            d.set(newValue.rawValue, forKey: "board.tool")
        }
    }

    /// The tool before this one (the Pencil's double-tap goes back to it).
    var previousTool: BoardTool { BoardTool(rawValue: d.string(forKey: "board.previousTool") ?? "") ?? .eraser }

    func colors(_ t: BoardTool) -> [String] {
        let key = t == .highlighter ? "board.markerColors" : "board.penColors"
        return BoardTools.fill(d.stringArray(forKey: key) ?? [], t == .highlighter ? BoardTools.markerColors : BoardTools.penColors)
    }

    func setColor(_ t: BoardTool, at i: Int, _ hex: String) {
        var c = colors(t)
        guard c.indices.contains(i) else { return }
        c[i] = hex
        d.set(c, forKey: t == .highlighter ? "board.markerColors" : "board.penColors")
        shareSoon()
    }

    func colorIndex(_ t: BoardTool) -> Int { min(colors(t).count - 1, max(0, d.integer(forKey: "board.color." + t.rawValue))) }
    func setColorIndex(_ t: BoardTool, _ i: Int) { d.set(i, forKey: "board.color." + t.rawValue); shareSoon() }

    /// The width picked for `t`: its step in widths(t). The six steps are kept under "board.widthStep."; a width kept from before
    /// (three steps, "board.width.") is read into its place among the six. The eraser keeps its three.
    func widthIndex(_ t: BoardTool) -> Int {
        let n = BoardTools.widths(t).count
        if t != .eraser, let v = d.object(forKey: "board.widthStep." + t.rawValue) as? Int { return min(n - 1, max(0, v)) }
        let old = min(2, max(0, d.object(forKey: "board.width." + t.rawValue) as? Int ?? 1))
        return t == .eraser ? old : BoardTools.oldWidthSteps(t)[old]
    }
    func setWidthIndex(_ t: BoardTool, _ i: Int) { d.set(i, forKey: (t == .eraser ? "board.width." : "board.widthStep.") + t.rawValue); shareSoon() }

    func color(_ t: BoardTool) -> String { colors(t)[colorIndex(t)] }
    func width(_ t: BoardTool) -> CGFloat { BoardTools.drawnWidths(t, ink: inkType(t), widths: ownWidths(t))[widthIndex(t)] }

    /// The six widths of `t` with the sizes set on the laptop laid over them (shapes draw with the pen's); the built-in ones otherwise.
    func ownWidths(_ t: BoardTool) -> [CGFloat] {
        let base = BoardTools.widths(t)
        guard let k = BoardTools.sharedInk(t == .shapes ? .pen : t), let v = d.array(forKey: "board.inkWidths." + k) as? [Double], v.count == base.count else { return base }
        return v.map { CGFloat($0) }
    }

    /// Whether `t` has sizes of its own (set on the iPad with Save as my default, or on the laptop).
    func hasOwnWidths(_ t: BoardTool) -> Bool { ownWidths(t) != BoardTools.widths(t == .shapes ? .pen : t) }

    /// Save as my default: step `i` of `t`'s row drawn `w` wide (board units) from now on, on this iPad and the laptop (the file
    /// keeps it in the laptop's units, Pens.unscaled). Shapes set the pen's.
    func setOwnWidth(_ t: BoardTool, _ i: Int, _ w: CGFloat) {
        let k = t == .shapes ? BoardTool.pen : t
        guard let ink = BoardTools.sharedInk(k) else { return }
        var row = ownWidths(k)
        guard row.indices.contains(i) else { return }
        row[i] = w
        d.set(row.map { Double($0) }, forKey: "board.inkWidths." + ink)
        shareSoon()
    }

    /// Reset sizes: `t`'s six widths back to the built-in ones, here and on the laptop.
    func resetWidths(_ t: BoardTool) {
        let k = t == .shapes ? BoardTool.pen : t
        guard let ink = BoardTools.sharedInk(k) else { return }
        d.removeObject(forKey: "board.inkWidths." + ink)
        shareSoon()
    }

    /// The tool a stroke of this PencilKit ink was drawn with (the pen for the pen's kinds).
    static func tool(of ink: PKInkingTool.InkType) -> BoardTool {
        switch ink {
        case .marker: return .highlighter
        case .pencil: return .pencil
        default: return .pen
        }
    }

    /// Draw with it: `t` in this colour and step from now on. A colour that isn't in the row takes the picked colour's place
    /// (true when it did, so the board can say so).
    @discardableResult
    func take(_ t: BoardTool, color hex: String, step: Int) -> Bool {
        var replaced = false
        let row = colors(t)
        if let i = row.firstIndex(where: { Pens.color($0) == Pens.color(hex) }) {
            setColorIndex(t, i)
        } else {
            setColor(t, at: colorIndex(t), hex)
            replaced = true
        }
        setWidthIndex(t, min(BoardTools.widths(t).count - 1, max(0, step)))
        tool = t
        return replaced
    }

    /// The PencilKit ink `t` writes with (nil for the eraser and the tools that don't draw).
    func inkType(_ t: BoardTool) -> PKInkingTool.InkType? {
        switch t {
        case .pencil: return .pencil
        case .highlighter: return .marker
        case .pen, .shapes: return penKind.ink
        default: return nil
        }
    }

    /// The widths of `t` as they are drawn: inside the ink's valid range (PencilKit would clamp them), and each step at least a fifth
    /// wider than the one before, so no two steps of the row draw the same. The ranges, from the UI check (iOS 26 simulator): pen
    /// 0.88–25.7, even line (monoline) 0.5–4, fountain pen 1.5–14, pencil 2.4–16, marker 7.5–60; so the even line, the fountain pen and the highlighter move their thinnest steps up.
    static func drawnWidths(_ t: BoardTool, ink: PKInkingTool.InkType?, widths own: [CGFloat]? = nil) -> [CGFloat] {
        var v = own ?? widths(t)
        guard let ink else { return v }
        let r = ink.validWidthRange
        v = v.map { min(max($0, r.lowerBound), r.upperBound) }
        for i in v.indices.dropFirst() where v[i] < v[i - 1] * 1.2 { v[i] = v[i - 1] * 1.2 }
        if let top = v.last, top > r.upperBound {
            v[v.count - 1] = r.upperBound
            for i in stride(from: v.count - 2, through: 0, by: -1) where v[i] > v[i + 1] / 1.2 { v[i] = v[i + 1] / 1.2 }
        }
        return v
    }

    var penKind: PenKind {
        get { PenKind(rawValue: d.string(forKey: "board.penKind") ?? "") ?? .pen }
        set { d.set(newValue.rawValue, forKey: "board.penKind") }
    }

    /// The eraser rubs out part of a stroke (pixel) or whole strokes.
    var eraserPixel: Bool {
        get { d.bool(forKey: "board.eraserPixel") }
        set { d.set(newValue, forKey: "board.eraserPixel"); shareSoon() }
    }

    /// Insert space on a PDF page opens the page up there (true, the default) or moves the whole page down.
    var spaceOpensPage: Bool {
        get { d.object(forKey: "board.spaceOpensPage") as? Bool ?? true }
        set { d.set(newValue, forKey: "board.spaceOpensPage") }
    }

    // Insert space's other options (NexusCore InsertSpace); defaults as approved in the redesign proposal.
    var spaceMoves: InsertSpace.Moves {
        get { InsertSpace.Moves(rawValue: d.string(forKey: "board.spaceMoves") ?? "") ?? .everything }
        set { d.set(newValue.rawValue, forKey: "board.spaceMoves") }
    }
    var spaceDirection: InsertSpace.Direction {
        get { InsertSpace.Direction(rawValue: d.string(forKey: "board.spaceDirection") ?? "") ?? .follow }
        set { d.set(newValue.rawValue, forKey: "board.spaceDirection") }
    }
    var spaceSize: InsertSpace.Size {
        get { InsertSpace.Size(rawValue: d.string(forKey: "board.spaceSize") ?? "") ?? .snap }
        set { d.set(newValue.rawValue, forKey: "board.spaceSize") }
    }
    var spaceClosing: InsertSpace.Closing {
        get { InsertSpace.Closing(rawValue: d.string(forKey: "board.spaceClosing") ?? "") ?? .stopAtContent }
        set { d.set(newValue.rawValue, forKey: "board.spaceClosing") }
    }
    var spaceTap: InsertSpace.Tap {
        get { InsertSpace.Tap(rawValue: d.string(forKey: "board.spaceTap") ?? "") ?? .half }
        set { d.set(newValue.rawValue, forKey: "board.spaceTap") }
    }
    var spaceAfter: InsertSpace.After {
        get { InsertSpace.After(rawValue: d.string(forKey: "board.spaceAfter") ?? "") ?? .pen }
        set { d.set(newValue.rawValue, forKey: "board.spaceAfter") }
    }

    var fingersDraw: Bool {
        get { d.bool(forKey: "board.fingersDraw") }
        set { d.set(newValue, forKey: "board.fingersDraw") }
    }

    /// Dark boards: follow the iPad's setting, or always or never (app-wide).
    var dark: Dark {
        get { Dark(rawValue: d.string(forKey: "board.dark") ?? "") ?? .follow }
        set { d.set(newValue.rawValue, forKey: "board.dark") }
    }

    var hintShown: Bool {
        get { d.bool(forKey: "board.hintShown") }
        set { d.set(newValue, forKey: "board.hintShown") }
    }

    // MARK: shared with the laptop (nexus-pens.json)

    /// The file's name for the ink `t` draws (the highlighter is the laptop's marker); nil for the tools it doesn't share.
    static func sharedInk(_ t: BoardTool) -> String? { t == .pen ? "pen" : t == .pencil ? "pencil" : t == .highlighter ? "marker" : nil }
    static let sharedTools: [BoardTool] = [.pen, .pencil, .highlighter]

    private var folder: URL?
    private var stamp: Date?
    /// The pens as they were when last read from the file or written to it: a save names only what changed since.
    private var base: Pens.Shared?
    private var pending: DispatchWorkItem?
    /// For the UI check (`-NexusTestSharedPens`): the file as last read or written.
    private(set) var lastFileText: String?
    static let testShared = ProcessInfo.processInfo.arguments.contains("-NexusTestSharedPens")

    private var fileURL: URL? { folder?.appendingPathComponent(Pens.file) }
    private static func modified(_ u: URL) -> Date? { (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date }

    /// The pens as the file has them. The sizes are always named, in the laptop's units (Pens.unscaled), so a size set here or
    /// put back with Reset sizes reaches the laptop; only those that changed are saved.
    func shared() -> Pens.Shared {
        var s = Pens.Shared()
        for t in BoardTools.sharedTools {
            if let k = BoardTools.sharedInk(t), let c = Pens.color(color(t)) { s.inks[k] = Pens.Ink(color: c, step: widthIndex(t)) }
            if let k = BoardTools.sharedInk(t),
               let w = Pens.unscaled(ownWidths(t).map { Double($0) }, ink: k, own: BoardTools.widths(t).map { Double($0) }) { s.widths[k] = w }
        }
        let pen = colors(.pen).compactMap(Pens.color), marker = colors(.highlighter).compactMap(Pens.color)
        if pen.count == 10 { s.colors["pen"] = pen }
        if marker.count == 8 { s.colors["marker"] = marker }
        s.eraser = eraserPixel ? "part" : "stroke"
        return s
    }

    /// Reads the data folder's pens file when it changed (or the folder did) and puts it in place; true when the pens changed.
    @discardableResult
    func refresh(_ root: URL?) -> Bool {
        guard let root else { return false }
        if root != folder { saveShared(); folder = root; stamp = nil; base = nil }
        guard let url = fileURL else { return false }
        if base != nil, BoardTools.modified(url) == stamp { return false }
        saveShared() // a change still waiting goes out first, laid over what came in
        let text = try? FolderAccess.read(url)
        stamp = BoardTools.modified(url)
        lastFileText = text
        let before = (shared(), BoardTools.sharedTools.map(ownWidths))
        if let text { take(Pens.read(text)) } else { for k in Pens.inks { d.removeObject(forKey: "board.inkWidths." + k) } } // (only ever from the file)
        base = shared()
        return before.0 != base || before.1 != BoardTools.sharedTools.map(ownWidths)
    }

    /// The file's pens in place: the rows first, so an ink's colour is found in its row; a colour that isn't in it is left as it is.
    private func take(_ s: Pens.Shared) {
        if let r = s.colors["pen"] { d.set(r.map(Pens.short), forKey: "board.penColors") }
        if let r = s.colors["marker"] { d.set(r.map(Pens.short), forKey: "board.markerColors") }
        for t in BoardTools.sharedTools {
            guard let k = BoardTools.sharedInk(t) else { continue }
            if let i = s.inks[k] {
                if let at = colors(t).firstIndex(where: { Pens.color($0) == i.color }) { d.set(at, forKey: "board.color." + t.rawValue) }
                d.set(i.step, forKey: "board.widthStep." + t.rawValue)
            }
            if let w = Pens.scaled(s.widths[k], ink: k, own: BoardTools.widths(t).map { Double($0) }) { d.set(w, forKey: "board.inkWidths." + k) }
            else { d.removeObject(forKey: "board.inkWidths." + k) }
        }
        if let e = s.eraser { d.set(e == "part", forKey: "board.eraserPixel") }
    }

    /// A pen changed in the bar: saved to the file a moment later (a colour being picked changes many times a second).
    private func shareSoon() {
        guard base != nil else { return }
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.saveShared() }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    /// Writes what changed since the file was last read or written, laid over the file as it is now. Its stamp is forgotten, so the
    /// next look takes in what the laptop had changed meanwhile.
    func saveShared() {
        pending?.cancel(); pending = nil
        guard let url = fileURL, let base else { return }
        let now = shared()
        let set = Pens.changes(from: base, to: now)
        guard !set.isEmpty else { return }
        let text = Pens.merge(try? FolderAccess.read(url), set)
        do {
            try FolderAccess.write(url, text)
            self.base = now; stamp = nil; lastFileText = text
        } catch {
            HangWatch.note("pens: couldn't write \(Pens.file): \(error.localizedDescription)")
        }
    }

    /// The PencilKit tool for `t` (nil for tools that don't draw). In a dark board the colour is given as it shows on dark, the way
    /// PencilKit wants it; the ink is still saved in its light colour.
    func pkTool(_ t: BoardTool, dark: Bool) -> PKTool? {
        switch t {
        case .pen, .pencil, .highlighter, .shapes:
            let type: PKInkingTool.InkType = inkType(t) ?? .pen
            // the tool's colour is always the light-board colour: a dark canvas shows it converted (black as white) and the stroke keeps
            // the light colour, so it turns back when the board does. Converting it here as well made ink drawn on a dark board come out
            // dark grey on dark, and stay grey on a light board.
            _ = dark
            return PKInkingTool(type, color: InkConvert.color(color(t)), width: width(t))
        case .eraser:
            return eraserPixel ? PKEraserTool(.bitmap, width: width(.eraser)) : PKEraserTool(.vector)
        case .lasso:
            return PKLassoTool()
        case .hand, .text, .space:
            return nil
        }
    }
}
