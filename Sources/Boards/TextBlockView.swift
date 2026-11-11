import UIKit
import NexusCore

/// A typed block drawn as the laptop's note reader draws it on a board (renderer/src/app/boarditems.js, renderer/board.css `.bd-text`):
/// the markdown line by line (the laptop's reader keeps every line break), in the block's size and colour, on its fill. Board units:
/// 1 unit is 1 pt at zoom 1.
enum TextBlockRender {
    /// A block without its own width wraps here and is otherwise as wide as its words (the laptop's TEXT_W, max-content).
    static let textWidth: CGFloat = 560
    static let lineHeight: CGFloat = 1.5

    static let ink: UIColor = color("#1B1B1B")
    static let muted: UIColor = color("#6B6B6B")
    static let doneGrey: UIColor = color("#8A8A8A")
    static let accent: UIColor = color("#1F5FD1")
    static let rule: UIColor = UIColor(white: 0, alpha: 0.15)
    static let codeBack: UIColor = UIColor(white: 0, alpha: 0.05)

    /// On a task's checkbox: the 0-based markdown line of the task (an Int).
    static let taskKey = NSAttributedString.Key("nexusTaskLine")
    /// On a quoted line: how deep it is quoted (an Int).
    static let quoteKey = NSAttributedString.Key("nexusQuoteDepth")
    /// On a fenced code line.
    static let codeKey = NSAttributedString.Key("nexusCodeBlock")
    /// On a rule (---).
    static let ruleKey = NSAttributedString.Key("nexusRule")

    /// The block's padding: 2 by 4 plain, 10 by 14 on a fill (which is also at least 120 wide).
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

    static func baseSize(_ item: BoardItem) -> CGFloat {
        CGFloat(TextLook.look(item).size ?? TextLook.defaultSize)
    }

    static func baseColor(_ item: BoardItem) -> UIColor {
        TextLook.look(item).color.map { color($0) } ?? ink
    }

    static func color(_ hex: String) -> UIColor {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return UIColor.black }
        let r = CGFloat((v >> 16) & 0xFF) / 255
        let g = CGFloat((v >> 8) & 0xFF) / 255
        let b = CGFloat(v & 0xFF) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    // MARK: the words

    static func attributed(_ md: String, item: BoardItem) -> NSAttributedString {
        build(md, size: baseSize(item), color: baseColor(item))
    }

    static func size(_ md: String, item: BoardItem) -> CGSize {
        layout(md, item: item).size
    }

    static func layout(_ md: String, item: BoardItem) -> TextBlockLayout {
        TextBlockLayout(text: attributed(md, item: item), item: item, box: box(item), baseSize: baseSize(item))
    }

    // MARK: a small line-based markdown reader

    private enum Kind { case para, heading, list, code, rule }

    private struct Style {
        var size: CGFloat
        var weight: UIFont.Weight = .regular
        var italic: Bool = false
        var mono: Bool = false
        var color: UIColor
        var strike: Bool = false
    }

    private struct Para {
        var text: NSMutableAttributedString
        var kind: Kind
        var fontSize: CGFloat
        var lineHeight: CGFloat
        var depth: Int = 0
        var firstIndent: CGFloat = 0
        var headIndent: CGFloat = 0
        var tab: CGFloat? = nil
        var before: CGFloat = 0
        var after: CGFloat = 0
        var breakAfter: Bool = false
        var group: String { "\(kind)|\(depth)" }
    }

    private static func regex(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p, options: []) }
    private static let fenceRe = regex("^\\s{0,3}(```|~~~)")
    private static let quoteRe = regex("^ {0,3}> ?(.*)$")
    private static let headingRe = regex("^ {0,3}(#{1,6})(?:[ \\t]+(.*?))?(?:[ \\t]+#+)?[ \\t]*$")
    private static let ruleRe = regex("^ {0,3}(?:(?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,})$")
    private static let taskRe = regex("^(\\s*)(?:[-*+]|\\d+[.)])\\s+\\[([ xX])\\]\\s(.*)$")
    private static let bulletRe = regex("^(\\s*)[-*+]\\s+(.*)$")
    private static let numberRe = regex("^(\\s*)(\\d{1,9})[.)]\\s+(.*)$")

    /// The capture groups of a whole-line match ("" for a group that took part in nothing), or nil.
    private static func groups(_ re: NSRegularExpression?, _ s: String) -> [String]? {
        guard let re else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        var out: [String] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            out.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return out
    }

    /// How far a line is indented, in columns (a tab is 4).
    private static func columns(_ s: String) -> Int {
        var n = 0
        for c in s {
            if c == " " { n += 1 } else if c == "\t" { n += 4 } else { break }
        }
        return n
    }

    private static func font(_ st: Style) -> UIFont {
        var f: UIFont = st.mono ? UIFont.monospacedSystemFont(ofSize: st.size, weight: st.weight)
                                : UIFont.systemFont(ofSize: st.size, weight: st.weight)
        if st.italic {
            let traits: UIFontDescriptor.SymbolicTraits = f.fontDescriptor.symbolicTraits.union(.traitItalic)
            if let d = f.fontDescriptor.withSymbolicTraits(traits) { f = UIFont(descriptor: d, size: st.size) }
        }
        return f
    }

    private static func attrs(_ st: Style) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: font(st), .foregroundColor: st.color]
        if st.strike {
            a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            a[.strikethroughColor] = st.color
        }
        return a
    }

    /// One line's inline markdown (bold, italic, code, strikethrough, links), in the given style.
    private static func inline(_ s: String, _ st: Style) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        if s.isEmpty { return out }
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: s, options: opts) else {
            out.append(NSAttributedString(string: s, attributes: attrs(st)))
            return out
        }
        for run in parsed.runs {
            let piece: String = String(parsed[run.range].characters)
            if piece.isEmpty { continue }
            var r: Style = st
            let intent: InlinePresentationIntent = run.inlinePresentationIntent ?? []
            if intent.contains(.stronglyEmphasized) { r.weight = .bold }
            if intent.contains(.emphasized) { r.italic = true }
            if intent.contains(.strikethrough) { r.strike = true }
            if intent.contains(.code) { r.mono = true; r.size = st.size * 0.9 }
            let isLink: Bool = run.link != nil
            if isLink { r.color = accent }
            var a: [NSAttributedString.Key: Any] = attrs(r)
            if intent.contains(.code) { a[.backgroundColor] = codeBack }
            if isLink {
                a[.underlineStyle] = NSUnderlineStyle.single.rawValue
                a[.underlineColor] = accent.withAlphaComponent(0.35)
            }
            out.append(NSAttributedString(string: piece, attributes: a))
        }
        return out
    }

    private static func build(_ md: String, size base: CGFloat, color: UIColor) -> NSAttributedString {
        let plain = Style(size: base, color: color)
        let quoteIndent: CGFloat = (base * 1.125).rounded()
        let listStep: CGFloat = base * 1.4
        let headingScale: [CGFloat] = [1.75, 1.4, 1.15, 1, 0.875, 0.85]
        let headingLine: [CGFloat] = [1.25, 1.3, 1.35, 1.5, 1.5, 1.5]
        let codeSize: CGFloat = base * 0.875

        var paras: [Para] = []
        var inFence = false
        var olNext: [Int: Int] = [:]
        let lines: [String] = md.components(separatedBy: "\n")

        func breakLast() { if !paras.isEmpty { paras[paras.count - 1].breakAfter = true } }

        for (index, raw) in lines.enumerated() {
            let line: String = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            if groups(fenceRe, line) != nil {
                breakLast()
                inFence.toggle()
                olNext.removeAll()
                continue
            }
            if inFence {
                var st = plain
                st.mono = true
                st.size = codeSize
                let t = NSMutableAttributedString(string: line.isEmpty ? "\u{200B}" : line, attributes: attrs(st))
                t.addAttribute(codeKey, value: true, range: NSRange(location: 0, length: t.length))
                paras.append(Para(text: t, kind: .code, fontSize: codeSize, lineHeight: 1.55))
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { breakLast(); continue }

            // quotes first: "> - [ ] b" is a task in a quote
            var rest: String = line
            var depth = 0
            while depth < 8, let g = groups(quoteRe, rest) {
                depth += 1
                rest = g[1]
            }
            var st = plain
            if depth > 0 { st.color = muted }
            let q: CGFloat = CGFloat(depth) * quoteIndent

            if let g = groups(headingRe, rest) {
                let level = min(max(g[1].count, 1), 6)
                var hs = st
                hs.size = base * headingScale[level - 1]
                hs.weight = .semibold
                var p = Para(text: inline(g[2], hs), kind: .heading, fontSize: hs.size, lineHeight: headingLine[level - 1], depth: depth)
                p.firstIndent = q
                p.headIndent = q
                paras.append(p)
                olNext.removeAll()
                continue
            }
            if groups(ruleRe, rest) != nil {
                let t = NSMutableAttributedString(string: "\u{200B}", attributes: attrs(st))
                t.addAttribute(ruleKey, value: true, range: NSRange(location: 0, length: t.length))
                var p = Para(text: t, kind: .rule, fontSize: base, lineHeight: lineHeight, depth: depth)
                p.firstIndent = q
                p.headIndent = q
                paras.append(p)
                olNext.removeAll()
                continue
            }
            if let g = groups(taskRe, rest) {
                let level = min(columns(g[1]) / 2, 8)
                let content: CGFloat = q + listStep * CGFloat(level + 1)
                let done = g[2] != " "
                let t = NSMutableAttributedString()
                var markStyle = st
                markStyle.color = done ? accent : muted
                let mark = NSAttributedString(string: done ? "\u{2611}\u{FE0E}" : "\u{2610}\u{FE0E}", attributes: attrs(markStyle))
                t.append(mark)
                t.addAttribute(taskKey, value: index, range: NSRange(location: 0, length: mark.length))
                t.append(NSAttributedString(string: "\t", attributes: attrs(st)))
                var words = st
                if done { words.color = doneGrey; words.strike = true }
                t.append(inline(g[3], words))
                var p = Para(text: t, kind: .list, fontSize: base, lineHeight: lineHeight, depth: depth)
                p.firstIndent = max(q, content - base * 1.3)
                p.headIndent = content
                p.tab = content
                paras.append(p)
                continue
            }
            if let g = groups(numberRe, rest) {
                let level = min(columns(g[1]) / 2, 8)
                let content: CGFloat = q + listStep * CGFloat(level + 1)
                let n: Int = olNext[level] ?? (Int(g[2]) ?? 1)
                olNext[level] = n + 1
                for k in olNext.keys where k > level { olNext[k] = nil }
                let t = NSMutableAttributedString(string: "\(n).\t", attributes: attrs(st))
                t.append(inline(g[3], st))
                var p = Para(text: t, kind: .list, fontSize: base, lineHeight: lineHeight, depth: depth)
                p.firstIndent = max(q, content - base * 1.4)
                p.headIndent = content
                p.tab = content
                paras.append(p)
                continue
            }
            if let g = groups(bulletRe, rest) {
                let level = min(columns(g[1]) / 2, 8)
                let content: CGFloat = q + listStep * CGFloat(level + 1)
                olNext[level] = nil
                let t = NSMutableAttributedString(string: "\u{2022}\t", attributes: attrs(st))
                t.append(inline(g[2], st))
                var p = Para(text: t, kind: .list, fontSize: base, lineHeight: lineHeight, depth: depth)
                p.firstIndent = max(q, content - base * 0.95)
                p.headIndent = content
                p.tab = content
                paras.append(p)
                continue
            }
            // a plain line: straight after a list item (no blank line) it carries on that item
            let words = rest.trimmingCharacters(in: .whitespaces)
            if let last = paras.last, last.kind == .list, !last.breakAfter, last.depth == depth {
                var p = Para(text: inline(words, st), kind: .list, fontSize: base, lineHeight: lineHeight, depth: depth)
                p.firstIndent = last.headIndent
                p.headIndent = last.headIndent
                paras.append(p)
                continue
            }
            olNext.removeAll()
            var p = Para(text: inline(words, st), kind: .para, fontSize: base, lineHeight: lineHeight, depth: depth)
            p.firstIndent = q
            p.headIndent = q
            paras.append(p)
        }

        // the space between blocks: a paragraph, list or code block ends .4em above the next; a heading has .4em above, .2em below
        func bottom(_ p: Para) -> CGFloat { p.kind == .heading ? 0.2 * p.fontSize : 0.4 * base }
        func top(_ p: Para) -> CGFloat { p.kind == .heading ? 0.4 * p.fontSize : 0 }
        if paras.count > 1 {
            for i in 0..<(paras.count - 1) {
                let a = paras[i], b = paras[i + 1]
                if a.breakAfter || a.group != b.group || a.kind == .heading || b.kind == .heading || a.kind == .rule || b.kind == .rule {
                    paras[i].after = max(bottom(a), top(b))
                }
            }
        }

        let out = NSMutableAttributedString()
        for (i, p) in paras.enumerated() {
            let start = out.length
            let text = p.text
            if text.length == 0 { text.append(NSAttributedString(string: "\u{200B}", attributes: attrs(plain))) }
            out.append(text)
            if i < paras.count - 1 {
                let endAttrs: [NSAttributedString.Key: Any] = text.attributes(at: max(0, text.length - 1), effectiveRange: nil)
                var nl = endAttrs
                nl[taskKey] = nil
                nl[.backgroundColor] = nil
                out.append(NSAttributedString(string: "\n", attributes: nl))
            }
            let range = NSRange(location: start, length: out.length - start)
            let ps = NSMutableParagraphStyle()
            ps.firstLineHeadIndent = p.firstIndent
            ps.headIndent = p.headIndent
            if let tab = p.tab {
                ps.tabStops = [NSTextTab(textAlignment: .left, location: tab, options: [:])]
            } else {
                ps.tabStops = []
            }
            ps.defaultTabInterval = p.kind == .code ? p.fontSize * 2.4 : base * 2
            ps.lineBreakMode = .byWordWrapping
            let natural: CGFloat = (p.kind == .code ? UIFont.monospacedSystemFont(ofSize: p.fontSize, weight: .regular)
                                                    : UIFont.systemFont(ofSize: p.fontSize)).lineHeight
            ps.lineSpacing = max(0, p.fontSize * p.lineHeight - natural)
            ps.paragraphSpacing = p.after
            ps.paragraphSpacingBefore = p.before
            out.addAttribute(.paragraphStyle, value: ps, range: range)
            if p.depth > 0 { out.addAttribute(quoteKey, value: p.depth, range: range) }
        }
        return out
    }
}

/// One block's words laid out (TextKit 1), for its size, its drawing and finding a checkbox under a finger. Sizes are the block's
/// outer box, padding included (the laptop's border-box).
final class TextBlockLayout {
    let text: NSAttributedString
    let storage: NSTextStorage
    let manager: NSLayoutManager
    let container: NSTextContainer
    let box: TextBlockRender.Box
    let baseSize: CGFloat
    let size: CGSize
    var origin: CGPoint { CGPoint(x: box.padX, y: box.padY) }

    init(text: NSAttributedString, item: BoardItem, box: TextBlockRender.Box, baseSize: CGFloat) {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 100_000, height: 10_000_000))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        var outer: CGFloat
        if let w = item.w, w.isFinite, w > 0 {
            outer = CGFloat(w)
        } else {
            manager.ensureLayout(for: container)
            let natural: CGFloat = ceil(manager.usedRect(for: container).width) + 2 * box.padX
            outer = min(natural, TextBlockRender.textWidth)
        }
        outer = max(outer, box.minWidth)
        let inner: CGFloat = max(1, outer - 2 * box.padX)
        container.size = CGSize(width: inner, height: 10_000_000)
        manager.ensureLayout(for: container)
        var height: CGFloat = ceil(manager.usedRect(for: container).height)
        if text.length == 0 { height = ceil(baseSize * TextBlockRender.lineHeight) }

        self.text = text
        self.storage = storage
        self.manager = manager
        self.container = container
        self.box = box
        self.baseSize = baseSize
        self.size = CGSize(width: ceil(outer), height: height + 2 * box.padY)
    }

    private var fullRange: NSRange { NSRange(location: 0, length: storage.length) }

    /// The glyphs' box of a range of characters, in the block's coordinates.
    private func rect(of range: NSRange) -> CGRect {
        let g = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return manager.boundingRect(forGlyphRange: g, in: container).offsetBy(dx: origin.x, dy: origin.y)
    }

    func draw(in ctx: CGContext) {
        guard storage.length > 0 else { return }
        let width: CGFloat = container.size.width

        // code blocks: one soft rounded box behind each run of fenced lines
        storage.enumerateAttribute(TextBlockRender.codeKey, in: fullRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let r = rect(of: range)
            let back = CGRect(x: origin.x - 4, y: r.minY - 3, width: width + 8, height: r.height + 6)
            ctx.setFillColor(TextBlockRender.codeBack.cgColor)
            ctx.addPath(UIBezierPath(roundedRect: back, cornerRadius: 4).cgPath)
            ctx.fillPath()
        }

        let glyphs = manager.glyphRange(for: container)
        manager.drawBackground(forGlyphRange: glyphs, at: origin)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)

        // quotes: a thin bar per level down their left (each level is indented 1.125em, as build() does)
        let step: CGFloat = (baseSize * 1.125).rounded()
        storage.enumerateAttribute(TextBlockRender.quoteKey, in: fullRange, options: []) { value, range, _ in
            guard let depth = value as? Int, depth > 0 else { return }
            let r = rect(of: range)
            ctx.setFillColor(TextBlockRender.rule.cgColor)
            for k in 0..<depth {
                let x: CGFloat = origin.x + CGFloat(k) * step
                ctx.fill(CGRect(x: x, y: r.minY, width: 2, height: r.height))
            }
        }

        // rules: a hairline across the block
        storage.enumerateAttribute(TextBlockRender.ruleKey, in: fullRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let g = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let used = manager.lineFragmentUsedRect(forGlyphAt: g.location, effectiveRange: nil)
            let ps = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            let left: CGFloat = origin.x + (ps?.headIndent ?? 0)
            let y: CGFloat = origin.y + used.minY + (used.height / 2).rounded()
            ctx.setFillColor(TextBlockRender.rule.cgColor)
            ctx.fill(CGRect(x: left, y: y, width: max(0, origin.x + width - left), height: 1))
        }
    }

    /// The markdown line of the task whose checkbox is under `point` (block coordinates), with some room round it for a finger.
    func taskLine(at point: CGPoint) -> Int? {
        var best: Int? = nil
        var bestDistance: CGFloat = .greatestFiniteMagnitude
        storage.enumerateAttribute(TextBlockRender.taskKey, in: fullRange, options: []) { value, range, _ in
            guard let line = value as? Int else { return }
            let g = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var r = manager.boundingRect(forGlyphRange: g, in: container)
            let fragment = manager.lineFragmentUsedRect(forGlyphAt: g.location, effectiveRange: nil)
            r.origin.y = fragment.minY
            r.size.height = fragment.height
            r = r.offsetBy(dx: origin.x, dy: origin.y)
            let slop: CGFloat = max(8, r.height * 0.4)
            let hit = r.insetBy(dx: -slop, dy: -3)
            guard hit.contains(point) else { return }
            let d: CGFloat = abs(point.x - r.midX) + abs(point.y - r.midY)
            if d < bestDistance { bestDistance = d; best = line }
        }
        return best
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
        let l = TextBlockRender.layout(md, item: item)
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
        layout.draw(in: ctx)
    }

    /// The 0-based markdown line of the task checkbox under `point` (in this view's coordinates), or nil.
    func taskLine(at point: CGPoint) -> Int? {
        layout?.taskLine(at: point)
    }
}
