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

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
        clipsToBounds = false
    }

    /// Lay the block out again for its markdown and item; keeps the origin, sets the size.
    func update(md: String, item: BoardItem) {
        let l = TextBlockLayout(TextBlockRender.layout(md, item: item))
        layout = l
        frame = CGRect(origin: frame.origin, size: l.size)
        if let fill = TextLook.look(item).fill {
            layer.backgroundColor = TextBlockRender.color(fill).cgColor
            layer.cornerRadius = 4
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.14
            layer.shadowRadius = 1.5
            layer.shadowOffset = CGSize(width: 0, height: 1)
            layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: l.size), cornerRadius: 4).cgPath
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
        guard let layout, let ctx = UIGraphicsGetCurrentContext() else { return }
        layout.text.draw(in: ctx)
    }

    /// The 0-based markdown line of the task checkbox under `point` (in this view's coordinates), or nil.
    func taskLine(at point: CGPoint) -> Int? {
        layout?.text.taskLine(at: point)
    }
}

/// A block's laid-out words and its size on the board.
final class TextBlockLayout {
    let text: BlockTextLayout
    var size: CGSize { text.size }
    init(_ text: BlockTextLayout) { self.text = text }
}
