import UIKit
import NexusCore

/// A typed block's box on the board (renderer/board.css `.bd-text`): padding 2 by 4 plain, 10 by 14 on a fill (at least 120 wide).
/// A block without its own width wraps at `textWidth` and is otherwise as wide as its words. The words are drawn by BlockStyler and
/// MDLayoutManager, the same way as while typing, so nothing jumps when a block opens.
enum TextBlockRender {
    /// The laptop's wrap width for a block without its own (docs/board-writing.md).
    static let textWidth: CGFloat = 640

    struct Box {
        var padX: CGFloat
        var padY: CGFloat
        var minWidth: CGFloat
        var filled: Bool
    }

    static func box(_ item: BoardItem) -> Box {
        if TextLook.look(item).fill != nil { return Box(padX: 14, padY: 10, minWidth: 120, filled: true) }
        return Box(padX: 4, padY: 2, minWidth: 24, filled: false)
    }

    static func color(_ hex: String) -> UIColor { BlockLook.hex(hex) }

    static func width(_ item: BoardItem) -> CGFloat? {
        guard let w = item.w, w.isFinite, w > 0 else { return nil }
        return CGFloat(w)
    }

    static func layout(_ md: String, item: BoardItem, scale: CGFloat = 1) -> BlockTextLayout {
        let b = box(item)
        return BlockTextLayout(md: md, look: BlockLook(item), width: width(item), scale: scale, padding: CGPoint(x: b.padX, y: b.padY),
                               minWidth: b.minWidth, wrap: textWidth)
    }

    static func size(_ md: String, item: BoardItem) -> CGSize {
        layout(md, item: item).size
    }
}

/// One typed block on the board. The board places it (frame.origin) and handles touches; `taskLine(at:)` says which checkbox a tap
/// is on, so the board can tick it with TextLook.toggleTask.
final class TextBlockView: UIView {
    private(set) var layout: TextBlockLayout?
    /// Words that comments sit on (markdown ranges), underlined softly.
    var marked: [NSRange] = [] { didSet { if marked != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (v: TextBlockView, _: UITraitCollection) in
            v.applyFill()
            v.setNeedsDisplay()
        }
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
        clipsToBounds = false
    }

    /// A folded block (`chip`): its title and one line of facts, drawn instead of the words.
    private(set) var chip: BlockFacts.Chip?

    /// Lay the block out again for its markdown and item; keeps the origin, sets the size.
    func update(md: String, item: BoardItem) {
        let l = TextBlockLayout(TextBlockRender.layout(md, item: item))
        layout = l
        if item.json["chip"]?.bool == true {
            let c = BlockFacts.chip(item, md)
            chip = c
            let title = (c.title as NSString).size(withAttributes: [.font: TextBlockView.chipTitle]).width
            let line = (c.line as NSString).size(withAttributes: [.font: TextBlockView.chipLine]).width
            frame = CGRect(origin: frame.origin, size: CGSize(width: min(360, ceil(max(title, line)) + 52), height: 48))
            fill = BlockLook.hex("#FFFFFF")
        } else {
            chip = nil
            frame = CGRect(origin: frame.origin, size: l.size)
            fill = TextLook.look(item).fill.map(TextBlockRender.color)
        }
        applyFill()
        setNeedsDisplay()
    }

    static let chipTitle = UIFont.systemFont(ofSize: 15, weight: .semibold)
    static let chipLine = UIFont.systemFont(ofSize: 12)

    private func drawChip(_ c: BlockFacts.Chip) {
        let icon: String
        switch c.kind {
        case "checklist": icon = "checklist"
        case "spanish": icon = "globe.europe.africa"
        case "heading": icon = "text.alignleft"
        default: icon = "text.justify.left"
        }
        let ink = BlockLook.ink, muted = BlockLook.muted
        UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))?
            .withTintColor(BlockLook.accent, renderingMode: .alwaysOriginal).draw(in: CGRect(x: 12, y: 15, width: 20, height: 18))
        let width = bounds.width - 52
        func line(_ s: String, _ font: UIFont, _ color: UIColor, y: CGFloat) {
            let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
            (s as NSString).draw(in: CGRect(x: 42, y: y, width: width, height: font.lineHeight + 1), withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
        }
        line(c.title, TextBlockView.chipTitle, ink, y: 6)
        line(c.line, TextBlockView.chipLine, muted, y: 27)
    }

    private var fill: UIColor?

    /// The block's background for the board's light or dark look.
    private func applyFill() {
        guard let l = layout else { return }
        if let fill {
            layer.backgroundColor = fill.resolvedColor(with: traitCollection).cgColor
            layer.cornerRadius = chip == nil ? 4 : 12
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.14
            layer.shadowRadius = 1.5
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: chip == nil ? l.size : frame.size), cornerRadius: chip == nil ? 4 : 12).cgPath
        } else {
            layer.backgroundColor = UIColor.clear.cgColor
            layer.cornerRadius = 0
            layer.shadowOpacity = 0
            layer.shadowPath = nil
        }
        setNeedsDisplay()
    }

    /// Draw sharper when the board is zoomed in (the board may call this with its zoom; 1 is the screen's own scale).
    func setRenderScale(_ zoom: CGFloat) {
        var scale: CGFloat = max(1, min(zoom, 4)) * max(1, traitCollection.displayScale)
        // keep a long block's backing store bounded (about 16 million pixels)
        let area = max(1, bounds.width * bounds.height)
        scale = max(1, min(scale, (16_000_000 / area).squareRoot()))
        if abs(contentScaleFactor - scale) > 0.01 {
            contentScaleFactor = scale
            setNeedsDisplay()
        }
    }

    override func draw(_ rect: CGRect) {
        if let chip { drawChip(chip); return }
        guard let layout, let ctx = UIGraphicsGetCurrentContext() else { return }
        layout.text.drawMarked(marked, in: ctx)
        layout.text.draw(in: ctx)
    }

    /// The 0-based markdown line of the task checkbox under `point` (in this view's coordinates), or nil.
    func taskLine(at point: CGPoint) -> Int? {
        chip == nil ? layout?.text.taskLine(at: point) : nil
    }
}

/// A block's laid-out words and its size on the board.
final class TextBlockLayout {
    let text: BlockTextLayout
    var size: CGSize { text.size }
    init(_ text: BlockTextLayout) { self.text = text }
}
