import UIKit
import NexusCore

/// Styles a typed block's raw markdown in place, the laptop's live preview way (NexusCore LiveMarkdown): the text stays the file's
/// markdown character for character, so typing edits the file directly; marks that hide get `hiddenKey` (MDLayoutManager makes them
/// take no room), marks drawn as something else get `glyphKey` (drawn by MDLayoutManager over their clear characters).
/// Used for the block on the board (no selection: every mark hides) and while typing (marks near the selection show, faintly).
/// `scale` multiplies every size, so the editor over a zoomed board draws its words sharp at the board's zoom.
enum BlockStyler {
    static let hiddenKey = NSAttributedString.Key("nexusHidden")
    /// "bullet", "box", "boxdone", "rule".
    static let glyphKey = NSAttributedString.Key("nexusGlyph")
    /// On a quoted line: how deep (Int).
    static let quoteKey = NSAttributedString.Key("nexusQuote")
    /// On fenced code lines.
    static let codeKey = NSAttributedString.Key("nexusCode")
    /// On a task line's checkbox: the 0-based markdown line (Int), to tick it.
    static let taskKey = NSAttributedString.Key("nexusTaskLine")
    /// On every mark that is shown faintly or drawn as a glyph: its colour is the mark's, not the words'.
    static let markKey = NSAttributedString.Key("nexusMark")
    static let faint = BlockLook.muted.withAlphaComponent(0.55)
    /// The line's own text colour (UIColor), for what MDLayoutManager draws on it (a bullet).
    static let textColorKey = NSAttributedString.Key("nexusLineColor")

    struct Result {
        var lines: [MDLine]
        /// The quote bars' step (units at this scale).
        var quoteStep: CGFloat
    }

    @discardableResult
    static func style(_ storage: NSTextStorage, look: BlockLook, scale: CGFloat, selection: NSRange?) -> Result {
        let text = storage.string
        let lines = LiveMarkdown.parse(text)
        let shown = LiveMarkdown.shown(lines, selection: selection)
        let full = NSRange(location: 0, length: storage.length)
        let s = max(0.05, scale)
        let body = look.style(.body)
        let base = body.size * s
        let quoteStep = (look.size * 1.125).rounded() * s
        let listStep = look.size * 1.4 * s

        storage.beginEditing()
        defer { storage.endEditing() }
        if full.length == 0 { return Result(lines: lines, quoteStep: quoteStep) }
        storage.setAttributes([
            .font: look.font(size: base, weight: body.weight),
            .foregroundColor: body.color,
        ], range: full)

        let ns = text as NSString
        var hiddenAt = IndexSet()
        for m in shown {
            switch m.show {
            case .hidden:
                storage.addAttribute(hiddenKey, value: true, range: m.range)
                hiddenAt.insert(integersIn: m.range.location..<(m.range.location + m.range.length))
            case .faint:
                storage.addAttribute(.foregroundColor, value: faint, range: m.range)
                storage.addAttribute(markKey, value: true, range: m.range)
            case .glyph(let g):
                storage.addAttribute(.foregroundColor, value: UIColor.clear, range: m.range)
                storage.addAttribute(markKey, value: true, range: m.range)
                switch g {
                case .bullet: storage.addAttribute(glyphKey, value: "bullet", range: m.range)
                case .checkbox(let done): storage.addAttribute(glyphKey, value: done ? "boxdone" : "box", range: m.range)
                case .rule: storage.addAttribute(glyphKey, value: "rule", range: m.range)
                case .none: break
                }
            }
        }

        for (index, line) in lines.enumerated() {
            // the line with its newline, so the paragraph style covers it
            var lineAll = line.range
            if lineAll.location + lineAll.length < ns.length { lineAll.length += 1 }

            let kind = lineStyle(line)
            var st = look.style(kind)
            if line.quote > 0, kind == .body { st = look.style(.quote) }
            let size = st.size * s
            var font = look.font(size: size, weight: st.weight, mono: st.mono || line.kind == .table || line.kind == .tableRule)
            if line.kind == .fence || line.kind == .mathFence { font = look.font(size: size, weight: .regular, mono: true) }
            if line.range.length > 0 || lineAll.length > 0 {
                storage.addAttribute(.font, value: font, range: lineAll)
                recolor(storage, lineAll, st.color)
            }
            if line.kind == .fence || line.kind == .mathFence || line.kind == .tableRule {
                storage.addAttribute(.foregroundColor, value: faint, range: line.range)
            }
            storage.addAttribute(textColorKey, value: st.color, range: lineAll)
            if line.kind == .code || line.kind == .fence { storage.addAttribute(codeKey, value: true, range: lineAll) }
            if line.kind == .math { storage.addAttribute(.font, value: BlockLook.font(family: "serif", size: size, weight: .regular, italic: true), range: lineAll) }
            if line.quote > 0 { storage.addAttribute(quoteKey, value: line.quote, range: lineAll) }
            if case .task(let done) = line.kind {
                for m in line.marks where m.glyph != .none {
                    storage.addAttribute(taskKey, value: index, range: m.range)
                }
                if done {
                    let words = NSRange(location: line.content, length: max(0, line.range.location + line.range.length - line.content))
                    storage.addAttribute(.foregroundColor, value: BlockLook.doneGrey, range: words)
                    storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: words)
                }
            }
            if line.kind == .table, line.range.length > 0 {
                // the pipes faint
                for k in line.range.location..<(line.range.location + line.range.length) where ns.character(at: k) == 124 {
                    storage.addAttribute(.foregroundColor, value: BlockLook.muted.withAlphaComponent(0.5), range: NSRange(location: k, length: 1))
                }
            }

            // inline spans
            for span in line.spans { applySpan(storage, span, look: look, size: size) }

            // the paragraph: indents (quotes, lists), line height, spacing
            let ps = NSMutableParagraphStyle()
            let q = CGFloat(line.quote) * quoteStep
            var head = q + st.indent * s
            var first = q + st.indent * s
            if line.isList {
                // the list mark sits in a column (level × step), the words start one step further in, wrapped lines too
                let target = CGFloat(line.level) * listStep
                let content = target + listStep
                kernIndent(storage, line: line, hiddenAt: hiddenAt, target: target, content: content, q: q)
                first = q
                head = q + content
            } else if line.continues {
                head = q + CGFloat(line.level + 1) * listStep
                first = head
            }
            ps.firstLineHeadIndent = first
            ps.headIndent = head
            ps.lineBreakMode = .byWordWrapping
            ps.tabStops = []
            ps.defaultTabInterval = size * 2
            let natural = font.lineHeight
            ps.lineSpacing = max(0, size * st.line - natural)
            if index > 0 { ps.paragraphSpacingBefore = st.before * s }
            ps.paragraphSpacing = st.after * s
            storage.addAttribute(.paragraphStyle, value: ps, range: lineAll)
        }
        return Result(lines: lines, quoteStep: quoteStep)
    }

    /// Which style a line is drawn in.
    static func lineStyle(_ line: MDLine) -> BlockStyle {
        switch line.kind {
        case .heading(let n): return BlockStyle.heading(n)
        case .code, .fence: return .code
        default: return .body
        }
    }

    /// Spreads a list line's indent and the space after its mark so the mark sits at `target` and the words start at `content`,
    /// whatever of the mark is showing.
    static func kernIndent(_ storage: NSTextStorage, line: MDLine, hiddenAt: IndexSet, target: CGFloat, content: CGFloat, q: CGFloat) {
        let ns = storage.string as NSString
        // where the line's own text starts after the quote marks
        var start = line.range.location
        while start < line.content, hiddenAt.contains(start) { start += 1 }
        guard let marker = line.marker else { return }
        // the indent: the whitespace before the mark
        let indentRange = NSRange(location: start, length: max(0, marker.location - start))
        if indentRange.length > 0 {
            let w = width(storage, indentRange, hiddenAt: hiddenAt)
            let per = (target - w) / CGFloat(indentRange.length)
            if per > 0 {
                for k in indentRange.location..<(indentRange.location + indentRange.length) where !hiddenAt.contains(k) {
                    storage.addAttribute(.kern, value: per, range: NSRange(location: k, length: 1))
                }
            }
        }
        // the space before the words: the last character before `content`
        let gap = line.content - 1
        guard gap > marker.location, gap < ns.length, ns.character(at: gap) == 32 else { return }
        let before = NSRange(location: marker.location, length: gap - marker.location)
        let used = width(storage, before, hiddenAt: hiddenAt) + width(storage, NSRange(location: gap, length: 1), hiddenAt: hiddenAt)
        let extra = content - target - used
        if extra > 0 { storage.addAttribute(.kern, value: extra, range: NSRange(location: gap, length: 1)) }
    }

    /// How wide some characters are drawn (hidden ones take nothing).
    static func width(_ storage: NSTextStorage, _ range: NSRange, hiddenAt: IndexSet) -> CGFloat {
        guard range.length > 0 else { return 0 }
        var w: CGFloat = 0
        for k in range.location..<(range.location + range.length) where !hiddenAt.contains(k) {
            let piece = storage.attributedSubstring(from: NSRange(location: k, length: 1))
            let plain = NSMutableAttributedString(attributedString: piece)
            plain.removeAttribute(.kern, range: NSRange(location: 0, length: plain.length))
            w += plain.size().width
        }
        return w
    }

    static func applySpan(_ storage: NSTextStorage, _ span: MDSpan, look: BlockLook, size: CGFloat) {
        let r = span.range
        guard r.location + r.length <= storage.length, r.length > 0 else { return }
        switch span.kind {
        case .bold: changeFonts(storage, r) { BlockLook.adding($0, bold: true, italic: false) }
        case .italic: changeFonts(storage, r) { BlockLook.adding($0, bold: false, italic: true) }
        case .strike:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        case .underline:
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        case .code:
            changeFonts(storage, r) { BlockLook.font(family: "mono", size: $0.pointSize * 0.9, weight: .regular, italic: false) }
            storage.addAttribute(.backgroundColor, value: BlockLook.codeBack, range: r)
        case .math:
            changeFonts(storage, r) { BlockLook.font(family: "serif", size: $0.pointSize, weight: .regular, italic: true) }
        case .highlight(let name):
            storage.addAttribute(.backgroundColor, value: BlockLook.highlight(name), range: r)
        case .color(let name):
            if let c = BlockLook.textColor(name) { recolor(storage, r, c) }
        case .link, .wikilink:
            recolor(storage, r, BlockLook.accent)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            storage.addAttribute(.underlineColor, value: BlockLook.accent.withAlphaComponent(0.35), range: r)
        case .nexusTask:
            recolor(storage, r, BlockLook.accent)
            storage.addAttribute(.backgroundColor, value: BlockLook.accent.withAlphaComponent(0.1), range: r)
        case .added:
            recolor(storage, r, BlockLook.added)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        case .deleted:
            recolor(storage, r, BlockLook.deleted)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
        }
    }

    /// Changes every font in a range (keeps hidden and glyph marks as they are: their fonts change too, which is harmless).
    static func changeFonts(_ storage: NSTextStorage, _ r: NSRange, _ change: (UIFont) -> UIFont) {
        storage.enumerateAttribute(.font, in: r, options: []) { value, sub, _ in
            guard let f = value as? UIFont else { return }
            storage.addAttribute(.font, value: change(f), range: sub)
        }
    }

    /// Recolours words but not marks shown faint or drawn as glyphs.
    static func recolor(_ storage: NSTextStorage, _ r: NSRange, _ c: UIColor) {
        storage.enumerateAttribute(markKey, in: r, options: []) { value, sub, _ in
            if value != nil { return }
            storage.addAttribute(.foregroundColor, value: c, range: sub)
        }
    }
}
