import UIKit
import NexusCore

/// How a typed block looks (its item's fields, nexus docs/data-format.md "Typed blocks"): size, colour and background as before,
/// plus the block's font, its styles (Title, Heading 1 to 3, Body, Quote, Code, each changed only where it differs from ours),
/// chemistry and review mode. The words are drawn by BlockStyler, the same on the board and while typing.
struct BlockLook {
    var size: CGFloat
    var color: UIColor
    var fill: UIColor?
    var family: String
    var styles: JSONValue?
    var chem: Bool
    var review: Bool
    var lang: String?

    static let families: [(key: String, label: String)] = [("sans", "Sans"), ("serif", "Serif"), ("mono", "Mono"), ("rounded", "Rounded")]

    init(_ item: BoardItem) {
        let look = TextLook.look(item)
        size = CGFloat(look.size ?? TextLook.defaultSize)
        color = look.color.map { BlockLook.hex($0) } ?? BlockLook.ink
        fill = look.fill.map { BlockLook.hex($0) }
        let f = item.string("font") ?? "sans"
        family = BlockLook.families.contains { $0.key == f } ? f : "sans"
        styles = item.json["styles"]
        chem = item.json["chem"]?.bool ?? true
        review = item.json["review"]?.bool ?? false
        lang = item.string("lang")
    }

    // MARK: colours

    static let ink = hex("#1B1B1B")
    static let muted = hex("#6B6B6B")
    static let doneGrey = hex("#8A8A8A")
    static let accent = hex("#1F5FD1")
    static let rule = UIColor(white: 0, alpha: 0.15)
    static let codeBack = UIColor(white: 0, alpha: 0.05)
    static let added = hex("#188038")
    static let deleted = hex("#D93025")

    /// Highlights by name (`==x==` is yellow; `<mark data-c="…">`).
    static let highlights: [(key: String, label: String, color: UIColor)] = [
        ("yellow", "Yellow", hex("#FFF0A0")), ("green", "Green", hex("#C8F0CF")), ("blue", "Blue", hex("#CFE2FF")),
        ("pink", "Pink", hex("#FFD3E4")), ("orange", "Orange", hex("#FFDDB8")),
    ]

    /// Text colours by name (`<span data-c="…">`), the board's colours.
    static var textColors: [(key: String, label: String, color: UIColor)] {
        TextLook.colors.map { ($0.label.lowercased(), $0.label, hex($0.hex)) }
    }

    static func highlight(_ name: String) -> UIColor {
        highlights.first { $0.key == name }?.color ?? highlights[0].color
    }

    static func textColor(_ name: String) -> UIColor? {
        textColors.first { $0.key == name }?.color
    }

    static func hex(_ hex: String) -> UIColor {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        if s.count == 8 { s = String(s.prefix(6)) }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return UIColor.black }
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    // MARK: styles

    /// One style's look at scale 1: size, weight, colour, line height (a multiple of the size), space before and after, indent.
    struct Style {
        var size: CGFloat
        var weight: UIFont.Weight
        var color: UIColor
        var line: CGFloat
        var before: CGFloat
        var after: CGFloat
        var indent: CGFloat
        var mono: Bool = false
    }

    /// Our default for a style, then the block's own changes on top.
    func style(_ s: BlockStyle) -> Style {
        var st: Style
        switch s {
        case .title: st = Style(size: size * 1.75, weight: .bold, color: color, line: 1.25, before: size * 0.7, after: size * 0.35, indent: 0)
        case .h1: st = Style(size: size * 1.4, weight: .semibold, color: color, line: 1.3, before: size * 0.56, after: size * 0.28, indent: 0)
        case .h2: st = Style(size: size * 1.15, weight: .semibold, color: color, line: 1.35, before: size * 0.46, after: size * 0.23, indent: 0)
        case .h3: st = Style(size: size, weight: .semibold, color: color, line: 1.5, before: size * 0.4, after: size * 0.2, indent: 0)
        case .body: st = Style(size: size, weight: .regular, color: color, line: 1.5, before: 0, after: 0, indent: 0)
        case .quote: st = Style(size: size, weight: .regular, color: BlockLook.muted, line: 1.5, before: 0, after: 0, indent: 0)
        case .code: st = Style(size: size * 0.875, weight: .regular, color: color, line: 1.55, before: 0, after: 0, indent: 0, mono: true)
        }
        guard let own = styles?[s.rawValue] else { return st }
        if let v = own["size"]?.number, v >= 6, v <= 300 { st.size = CGFloat(v) }
        if let v = own["weight"]?.number { st.weight = BlockLook.weight(v) }
        if let v = own["color"]?.string, TextLook.isHex(v) { st.color = BlockLook.hex(v) }
        if let v = own["line"]?.number, v >= 0.8, v <= 4 { st.line = CGFloat(v) }
        if let v = own["before"]?.number, v >= 0, v <= 400 { st.before = CGFloat(v) }
        if let v = own["after"]?.number, v >= 0, v <= 400 { st.after = CGFloat(v) }
        if let v = own["indent"]?.number, v >= 0, v <= 400 { st.indent = CGFloat(v) }
        return st
    }

    static func weight(_ v: Double) -> UIFont.Weight {
        switch v {
        case ..<150: return .ultraLight
        case ..<250: return .thin
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        case ..<750: return .bold
        case ..<850: return .heavy
        default: return .black
        }
    }

    // MARK: fonts

    func font(size: CGFloat, weight: UIFont.Weight, italic: Bool = false, mono: Bool = false) -> UIFont {
        BlockLook.font(family: mono ? "mono" : family, size: size, weight: weight, italic: italic)
    }

    static func font(family: String, size: CGFloat, weight: UIFont.Weight, italic: Bool) -> UIFont {
        var f = UIFont.systemFont(ofSize: max(1, size), weight: weight)
        let design: UIFontDescriptor.SystemDesign
        switch family {
        case "serif": design = .serif
        case "mono": design = .monospaced
        case "rounded": design = .rounded
        default: design = .default
        }
        if design != .default, let d = f.fontDescriptor.withDesign(design) { f = UIFont(descriptor: d, size: max(1, size)) }
        if italic, let d = f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            f = UIFont(descriptor: d, size: max(1, size))
        }
        return f
    }

    /// The same font with bold and/or italic added.
    static func adding(_ f: UIFont, bold: Bool, italic: Bool) -> UIFont {
        var traits = f.fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let d = f.fontDescriptor.withSymbolicTraits(traits) else { return f }
        return UIFont(descriptor: d, size: f.pointSize)
    }
}
