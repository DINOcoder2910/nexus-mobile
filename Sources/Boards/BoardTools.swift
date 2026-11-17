import UIKit
import PencilKit
import NexusCore

/// The board's tools, in the bar (the redesign's Option B): what the Pencil does, each pen's colour and width, and the board
/// settings that go with them. Kept between boards and launches (UserDefaults), the same on every board.
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
    }

    func colorIndex(_ t: BoardTool) -> Int { min(colors(t).count - 1, max(0, d.integer(forKey: "board.color." + t.rawValue))) }
    func setColorIndex(_ t: BoardTool, _ i: Int) { d.set(i, forKey: "board.color." + t.rawValue) }

    /// The width picked for `t`: its step in widths(t). The six steps are kept under "board.widthStep."; a width kept from before
    /// (three steps, "board.width.") is read into its place among the six. The eraser keeps its three.
    func widthIndex(_ t: BoardTool) -> Int {
        let n = BoardTools.widths(t).count
        if t != .eraser, let v = d.object(forKey: "board.widthStep." + t.rawValue) as? Int { return min(n - 1, max(0, v)) }
        let old = min(2, max(0, d.object(forKey: "board.width." + t.rawValue) as? Int ?? 1))
        return t == .eraser ? old : BoardTools.oldWidthSteps(t)[old]
    }
    func setWidthIndex(_ t: BoardTool, _ i: Int) { d.set(i, forKey: (t == .eraser ? "board.width." : "board.widthStep.") + t.rawValue) }

    func color(_ t: BoardTool) -> String { colors(t)[colorIndex(t)] }
    func width(_ t: BoardTool) -> CGFloat { BoardTools.drawnWidths(t, ink: inkType(t))[widthIndex(t)] }

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
    static func drawnWidths(_ t: BoardTool, ink: PKInkingTool.InkType?) -> [CGFloat] {
        var v = widths(t)
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
        set { d.set(newValue, forKey: "board.eraserPixel") }
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
