import UIKit

/// TextKit 1 layout for a typed block styled by BlockStyler: hidden marks become null glyphs (they take no room), and what the
/// marks stand for is drawn behind the words: bullets, checkboxes, rules, quote bars and the box behind fenced code.
/// The same class lays out the block on the board and inside the editor's text view, so the two look alike.
final class MDLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// The quote bars' step at this layout's scale.
    var quoteStep: CGFloat = 18

    override init() {
        super.init()
        delegate = self
        allowsNonContiguousLayout = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    // MARK: hidden marks take no room

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>,
                       font aFont: UIFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard let storage = textStorage, glyphRange.length > 0 else { return 0 }
        var changed = false
        var newProps: [NSLayoutManager.GlyphProperty] = []
        newProps.reserveCapacity(glyphRange.length)
        for i in 0..<glyphRange.length {
            let ci = charIndexes[i]
            var p = props[i]
            if ci < storage.length, storage.attribute(BlockStyler.mathKey, at: ci, effectiveRange: nil) != nil {
                p = .controlCharacter
                changed = true
            } else if ci < storage.length, storage.attribute(BlockStyler.hiddenKey, at: ci, effectiveRange: nil) != nil {
                p = .null
                changed = true
            }
            newProps.append(p)
        }
        guard changed else { return 0 }
        newProps.withUnsafeBufferPointer { buf in
            if let base = buf.baseAddress {
                layoutManager.setGlyphs(glyphs, properties: base, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            }
        }
        return glyphRange.length
    }

    // MARK: maths: one character takes the formula's width, and the picture is drawn there

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if let storage = textStorage, charIndex < storage.length, storage.attribute(BlockStyler.mathKey, at: charIndex, effectiveRange: nil) != nil {
            return .whitespace
        }
        return action
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer,
                       proposedLineFragment proposedRect: CGRect, glyphPosition: CGPoint, characterIndex charIndex: Int) -> CGRect {
        guard let storage = textStorage, charIndex < storage.length,
              let box = storage.attribute(BlockStyler.mathKey, at: charIndex, effectiveRange: nil) as? BlockStyler.MathBox
        else { return CGRect(origin: glyphPosition, size: .zero) }
        return CGRect(x: glyphPosition.x, y: glyphPosition.y, width: box.size.width, height: 0)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(BlockStyler.mathKey, in: chars, options: []) { value, range, _ in
            guard let box = value as? BlockStyler.MathBox, let r = mathRect(box, at: range.location) else { return }
            box.image.draw(in: r.offsetBy(dx: origin.x, dy: origin.y))
        }
    }

    /// Where a formula's picture is drawn (container coordinates).
    private func mathRect(_ box: BlockStyler.MathBox, at charIndex: Int) -> CGRect? {
        guard let storage = textStorage else { return nil }
        let g = glyphIndexForCharacter(at: charIndex)
        guard g < numberOfGlyphs else { return nil }
        let frag = lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let at = location(forGlyphAt: g)
        let font = (storage.attribute(.font, at: charIndex, effectiveRange: nil) as? UIFont) ?? UIFont.systemFont(ofSize: 16)
        let baseline = frag.minY + at.y
        return box.block
            ? CGRect(x: frag.minX + max(0, (frag.width - box.size.width) / 2), y: baseline - box.size.height - font.descender,
                     width: box.size.width, height: box.size.height)
            : CGRect(x: frag.minX + at.x, y: baseline - font.xHeight / 2 - box.size.height / 2,
                     width: box.size.width, height: box.size.height)
    }

    /// The bottom of the lowest formula picture (container coordinates), or 0. A tall formula on the last line reaches below the used
    /// rect (the room under it is line spacing, which the last line doesn't get), so a block measured by the used rect alone cut its
    /// bottom half off.
    func mathBottom() -> CGFloat {
        guard let storage = textStorage, storage.length > 0 else { return 0 }
        var bottom: CGFloat = 0
        storage.enumerateAttribute(BlockStyler.mathKey, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            if let box = value as? BlockStyler.MathBox, let r = mathRect(box, at: range.location) { bottom = max(bottom, r.maxY) }
        }
        return bottom
    }

    // MARK: drawing what marks stand for

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        guard let storage = textStorage, let container = textContainers.first, let ctx = UIGraphicsGetCurrentContext() else {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let width = container.size.width - 2 * container.lineFragmentPadding

        // fenced code: one soft box behind each run of code lines
        storage.enumerateAttribute(BlockStyler.codeKey, in: chars, options: []) { value, range, _ in
            guard value != nil else { return }
            let r = rect(of: range, in: container)
            guard !r.isNull else { return }
            let back = CGRect(x: origin.x + container.lineFragmentPadding - 4, y: origin.y + r.minY - 2, width: width + 8, height: r.height + 4)
            ctx.setFillColor(BlockLook.codeBack.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: back, cornerRadius: 4).cgPath)
            ctx.fillPath()
        }

        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        // quote bars, one per level
        storage.enumerateAttribute(BlockStyler.quoteKey, in: chars, options: []) { value, range, _ in
            guard let depth = value as? Int, depth > 0 else { return }
            let r = rect(of: range, in: container)
            guard !r.isNull else { return }
            ctx.setFillColor(BlockLook.rule.cgColor)
            for k in 0..<depth {
                let x = origin.x + container.lineFragmentPadding + CGFloat(k) * quoteStep
                ctx.fill(CGRect(x: x, y: origin.y + r.minY, width: 2, height: r.height))
            }
        }

        // bullets, checkboxes, rules
        storage.enumerateAttribute(BlockStyler.glyphKey, in: chars, options: []) { value, range, _ in
            guard let kind = value as? String else { return }
            let g = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard g.length > 0 else { return }
            let frag = lineFragmentRect(forGlyphAt: g.location, effectiveRange: nil)
            let used = lineFragmentUsedRect(forGlyphAt: g.location, effectiveRange: nil)
            let box = boundingRect(forGlyphRange: g, in: container)
            let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? UIFont) ?? UIFont.systemFont(ofSize: 16)
            let baseline = frag.minY + location(forGlyphAt: g.location).y
            let color = (storage.attribute(BlockStyler.textColorKey, at: range.location, effectiveRange: nil) as? UIColor) ?? BlockLook.ink
            switch kind {
            case "bullet":
                let d = max(2, font.pointSize * 0.32)
                let cy = origin.y + baseline - font.xHeight / 2
                let cx = origin.x + box.minX + max(d / 2, box.width / 2)
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d))
            case "box", "boxdone":
                let side = font.pointSize * 0.9
                let cy = origin.y + baseline - font.capHeight / 2
                let x = origin.x + box.minX + max(0, (box.width - side) / 2)
                let r = CGRect(x: x, y: cy - side / 2, width: side, height: side)
                let path = UIBezierPath(roundedRect: r, cornerRadius: side * 0.2)
                if kind == "boxdone" {
                    ctx.setFillColor(BlockLook.accent.cgColor)
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
                    let tick = UIBezierPath()
                    tick.move(to: CGPoint(x: r.minX + side * 0.22, y: r.minY + side * 0.52))
                    tick.addLine(to: CGPoint(x: r.minX + side * 0.42, y: r.minY + side * 0.72))
                    tick.addLine(to: CGPoint(x: r.minX + side * 0.78, y: r.minY + side * 0.3))
                    ctx.setStrokeColor(UIColor.white.cgColor)
                    ctx.setLineWidth(max(1, side * 0.12))
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.addPath(tick.cgPath)
                    ctx.strokePath()
                } else {
                    ctx.setStrokeColor(BlockLook.muted.cgColor)
                    ctx.setLineWidth(max(1, side * 0.08))
                    ctx.addPath(UIBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: side * 0.2).cgPath)
                    ctx.strokePath()
                }
            case "rule":
                let y = origin.y + used.minY + (used.height / 2).rounded()
                let left = origin.x + used.minX
                ctx.setFillColor(BlockLook.rule.cgColor)
                ctx.fill(CGRect(x: left, y: y, width: max(0, origin.x + container.lineFragmentPadding + width - left), height: 1))
            default:
                break
            }
        }
    }

    /// The line fragments a run of characters sits in, joined (container coordinates).
    func rect(of range: NSRange, in container: NSTextContainer) -> CGRect {
        let g = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard g.length > 0 else { return .null }
        var out = CGRect.null
        enumerateLineFragments(forGlyphRange: g) { _, used, _, _, _ in out = out.union(used) }
        return out
    }

    /// The task line (0-based) whose checkbox is near a point (container coordinates), with room round it for a finger.
    func taskLine(at point: CGPoint) -> Int? {
        guard let storage = textStorage, let container = textContainers.first else { return nil }
        var best: Int? = nil
        var bestDistance = CGFloat.greatestFiniteMagnitude
        storage.enumerateAttribute(BlockStyler.taskKey, in: NSRange(location: 0, length: storage.length), options: []) { value, range, _ in
            guard let line = value as? Int else { return }
            let g = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard g.length > 0 else { return }
            var r = boundingRect(forGlyphRange: g, in: container)
            let frag = lineFragmentUsedRect(forGlyphAt: g.location, effectiveRange: nil)
            r.origin.y = frag.minY
            r.size.height = frag.height
            let slop = max(8, r.height * 0.4)
            guard r.insetBy(dx: -slop, dy: -3).contains(point) else { return }
            let d = abs(point.x - r.midX) + abs(point.y - r.midY)
            if d < bestDistance { bestDistance = d; best = line }
        }
        return best
    }
}

/// One block's words laid out on their own (not in a text view): for its size on the board and for drawing it.
final class BlockTextLayout {
    let storage: NSTextStorage
    let manager: MDLayoutManager
    let container: NSTextContainer
    let size: CGSize
    let padding: CGPoint

    /// Lays out `md` for the block: `width` is the block's own width (nil: as wide as its words, up to the wrap width), all at `scale`.
    init(md: String, look: BlockLook, width: CGFloat?, scale: CGFloat = 1, padding: CGPoint, minWidth: CGFloat, wrap: CGFloat) {
        let storage = NSTextStorage(string: md)
        let manager = MDLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 100_000, height: 10_000_000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let result = BlockStyler.style(storage, look: look, scale: scale, selection: nil)
        manager.quoteStep = result.quoteStep

        var outer: CGFloat
        if let w = width, w.isFinite, w > 0 {
            outer = w * scale
        } else {
            manager.ensureLayout(for: container)
            let natural = ceil(manager.usedRect(for: container).width) + 2 * padding.x * scale
            outer = min(natural, wrap * scale)
        }
        outer = max(outer, minWidth * scale)
        container.size = CGSize(width: max(1, outer - 2 * padding.x * scale), height: 10_000_000)
        manager.ensureLayout(for: container)
        var height = ceil(max(manager.usedRect(for: container).height, manager.mathBottom()))
        if storage.length == 0 { height = ceil(look.size * 1.5 * scale) }

        self.storage = storage
        self.manager = manager
        self.container = container
        self.padding = CGPoint(x: padding.x * scale, y: padding.y * scale)
        self.size = CGSize(width: ceil(outer), height: height + 2 * padding.y * scale)
    }

    func draw(in ctx: CGContext) {
        let glyphs = manager.glyphRange(for: container)
        guard glyphs.length > 0 else { return }
        manager.drawBackground(forGlyphRange: glyphs, at: padding)
        manager.drawGlyphs(forGlyphRange: glyphs, at: padding)
    }

    /// The task line under a point (block coordinates), or nil.
    func taskLine(at point: CGPoint) -> Int? {
        manager.taskLine(at: CGPoint(x: point.x - padding.x, y: point.y - padding.y))
    }

    /// The box round a run of characters (inside the padding: add `padding` for block coordinates); null when it shows nothing.
    func rect(of range: NSRange) -> CGRect {
        let r = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard r.length > 0 || (range.length == 0 && range.location <= storage.length) else { return .null }
        let g = manager.glyphRange(forCharacterRange: r.length > 0 ? r : NSRange(location: max(0, min(r.location, storage.length - 1)), length: storage.length > 0 ? 1 : 0),
                                   actualCharacterRange: nil)
        guard g.length > 0 else { return .null }
        return manager.boundingRect(forGlyphRange: g, in: container)
    }

    /// The character nearest a point (inside the padding).
    func characterIndex(at p: CGPoint) -> Int {
        guard storage.length > 0 else { return 0 }
        var fraction: CGFloat = 0
        let i = manager.characterIndex(for: p, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        return min(storage.length, i + (fraction > 0.5 ? 1 : 0))
    }

    /// A soft underline under each range (comments' words), drawn behind the words.
    func drawMarked(_ ranges: [NSRange], in ctx: CGContext) {
        guard !ranges.isEmpty else { return }
        ctx.setFillColor(UIColor(red: 1, green: 0.78, blue: 0.2, alpha: 0.28).cgColor)
        for range in ranges {
            let r = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            guard r.length > 0 else { continue }
            let g = manager.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            manager.enumerateEnclosingRects(forGlyphRange: g, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                ctx.fill(rect.offsetBy(dx: self.padding.x, dy: self.padding.y))
            }
        }
    }
}
