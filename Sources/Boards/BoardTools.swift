import UIKit
import PencilKit

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

    /// The six favourite colours for pens and pencils, and for the highlighter.
    static let penColors = ["#1B1B1B", "#2F6FEB", "#D93025", "#188038", "#E37400", "#8E44AD"]
    static let markerColors = ["#FFE066", "#9BE7A0", "#FFB3C7", "#9FD3FF", "#FFC48C", "#D7B8FF"]
    /// Three widths per tool (board units).
    static func widths(_ t: BoardTool) -> [CGFloat] {
        switch t {
        case .pencil: return [2, 4, 8]
        case .highlighter: return [12, 20, 32]
        case .eraser: return [10, 30, 60]
        default: return [1.5, 3, 6]
        }
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
        let saved = d.stringArray(forKey: key) ?? []
        let base = t == .highlighter ? BoardTools.markerColors : BoardTools.penColors
        return saved.count == base.count ? saved : base
    }

    func setColor(_ t: BoardTool, at i: Int, _ hex: String) {
        var c = colors(t)
        guard c.indices.contains(i) else { return }
        c[i] = hex
        d.set(c, forKey: t == .highlighter ? "board.markerColors" : "board.penColors")
    }

    func colorIndex(_ t: BoardTool) -> Int { min(5, max(0, d.integer(forKey: "board.color." + t.rawValue))) }
    func setColorIndex(_ t: BoardTool, _ i: Int) { d.set(i, forKey: "board.color." + t.rawValue) }

    func widthIndex(_ t: BoardTool) -> Int {
        let v = d.object(forKey: "board.width." + t.rawValue) as? Int ?? 1
        return min(2, max(0, v))
    }
    func setWidthIndex(_ t: BoardTool, _ i: Int) { d.set(i, forKey: "board.width." + t.rawValue) }

    func color(_ t: BoardTool) -> String { colors(t)[colorIndex(t)] }
    func width(_ t: BoardTool) -> CGFloat { BoardTools.widths(t)[widthIndex(t)] }

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
            let type: PKInkingTool.InkType = t == .pencil ? .pencil : t == .highlighter ? .marker : penKind.ink
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
