import UIKit
import NexusCore

/// Revision tape (feature `tape`; item `{"type": "tape", "x", "y", "w", "h", "color"}`): a strip that covers words and ink to test
/// yourself. Tap it to peek, tap again to cover; peeking is this iPad's own and isn't saved.
final class TapeView: UIView {
    private let stripes = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.cornerRadius = 3
        layer.addSublayer(stripes)
        stripes.fillColor = nil
        stripes.lineWidth = 2
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    static let colors: [(hex: String, label: String)] = [("#F6C945", "Yellow"), ("#7FB8F0", "Blue"), ("#F29BB8", "Pink"), ("#8FD19E", "Green"), ("#B9B9B9", "Grey")]

    func update(_ it: BoardItem, offset: CGPoint, peeking: Bool) {
        let w = max(20, it.w ?? 200), h = max(12, it.h ?? 40)
        frame = CGRect(x: it.x + offset.x, y: it.y + offset.y, width: w, height: h)
        let c = BlockLook.hex(it.string("color") ?? TapeView.colors[0].hex)
        backgroundColor = peeking ? c.withAlphaComponent(0.12) : c
        layer.borderWidth = peeking ? 1.5 : 0
        layer.borderColor = c.cgColor
        // diagonal stripes, as paper tape has
        let path = UIBezierPath()
        var x = -h
        while x < w { path.move(to: CGPoint(x: x, y: h)); path.addLine(to: CGPoint(x: x + h, y: 0)); x += 14 }
        stripes.path = peeking ? nil : path.cgPath
        stripes.strokeColor = UIColor(white: 1, alpha: 0.18).cgColor
        stripes.frame = bounds
        layer.masksToBounds = true
        accessibilityLabel = peeking ? "Revision tape, lifted" : "Revision tape"
    }
}

extension BoardController {
    /// Covers a rect (board units) with tape; one undo step.
    @discardableResult
    func addTape(rect r: CGRect, color: String? = nil) -> String? {
        guard !readOnly, r.width > 4, r.height > 4 else { return nil }
        let id = BoardFormat.newId(taken: allIds)
        let it = BoardItem(id: id, type: "tape", x: Double(r.minX.rounded()), y: Double(r.minY.rounded()), fields: [
            ("w", .number(Double(r.width.rounded()))), ("h", .number(Double(r.height.rounded()))), ("color", .string(color ?? TapeView.colors[0].hex)),
        ])
        changeItems("Revision tape") { $0.items.append(it) }
        addFeature("tape")
        return id
    }

    /// Covers each line of a block's words with its own strip (so you can peek line by line).
    func tapeBlock(_ id: String) {
        guard let block = content.items.first(where: { $0.id == id }) else { return }
        let md = content.texts[shownKey(id)] ?? ""
        let layout = TextBlockRender.layout(md, item: block)
        var rects: [CGRect] = []
        layout.manager.enumerateLineFragments(forGlyphRange: layout.manager.glyphRange(for: layout.container)) { _, used, _, g, _ in
            let chars = layout.manager.characterRange(forGlyphRange: g, actualGlyphRange: nil)
            let line = (md as NSString).substring(with: chars).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, used.width > 2 else { return }
            rects.append(used.offsetBy(dx: block.x + layout.padding.x, dy: block.y + layout.padding.y).insetBy(dx: -3, dy: -1))
        }
        guard !rects.isEmpty else { tell("Nothing to cover yet.", brief: true); return }
        var taken = allIds
        changeItems("Revision tape") { c in
            for r in rects {
                let nid = BoardFormat.newId(taken: taken); taken.insert(nid)
                c.items.append(BoardItem(id: nid, type: "tape", x: Double(r.minX.rounded()), y: Double(r.minY.rounded()), fields: [
                    ("w", .number(Double(r.width.rounded()))), ("h", .number(Double(r.height.rounded()))), ("color", .string(TapeView.colors[0].hex)),
                ]))
            }
        }
        addFeature("tape")
    }

    func togglePeek(_ id: String) {
        if peeking.contains(id) { peeking.remove(id) } else { peeking.insert(id) }
        rebuildItems()
    }

    /// Lift or cover every strip on the board at once.
    func peekAll(_ lift: Bool) {
        let all = content.items.filter { $0.type == "tape" }.map(\.id)
        peeking = lift ? Set(all) : []
        rebuildItems()
    }

    func removeTape(_ id: String) {
        changeItems("Remove tape") { $0.items.removeAll { $0.id == id } }
    }
}
