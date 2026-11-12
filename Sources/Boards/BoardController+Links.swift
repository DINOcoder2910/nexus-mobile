import UIKit
import SwiftUI
import PDFKit
import NexusCore

/// What the board's links are doing now (BoardController.links).
struct LinkState {
    /// Link mode: a finger tap picks an end (the first, then the other); a finger drag on a PDF page picks a passage.
    var mode = false
    /// The first end picked, waiting for the other.
    var pending: JSONValue?
    /// Every link shown, not only those of the picked thing.
    var showAll = UserDefaults.standard.bool(forKey: "board.links.showAll")
    /// A thing whose links show because its badge was tapped.
    var pinned: String?
    var color = UserDefaults.standard.string(forKey: "board.links.color") ?? BoardLinks.colors[0]
    /// A passage being chosen on a PDF page (board units).
    var band: Band?
    /// A passage chosen: pull it out as an excerpt, or link it.
    var passage: Passage?
    /// Links shown for a moment after they were made or found.
    var flash: [String: Date] = [:]
    /// Tasks read from the folder when the board has no store (a board opened on its own).
    var tasks: [String: NexusTask]?
    /// Study cards' fronts read for labels ("" when not found), by "deck#card".
    var cards: [String: String] = [:]

    struct Band { var start: CGPoint; var now: CGPoint; var pdf: String; var page: Int }
    struct Passage { var pdf: String; var page: Int; var box: CGRect; var end: JSONValue }
}

/// Draws the links over the board in screen points: the ribbons (CAShapeLayers), a badge on each thing that has links, and a tab for
/// a far end (another board, a task, a note, a study card). Touches pass through to the canvas except on the badges and tabs.
final class LinkOverlay: UIView {
    let ribbons = CALayer()
    private var pool: [String: UIButton] = [:]
    private var used = Set<String>()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        layer.addSublayer(ribbons)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self ? nil : v
    }

    func begin() {
        used = []
        ribbons.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    func button(_ key: String, make: () -> UIButton) -> UIButton {
        used.insert(key)
        if let b = pool[key] { return b }
        let b = make()
        addSubview(b)
        pool[key] = b
        return b
    }

    func end() {
        for (k, b) in pool where !used.contains(k) { b.removeFromSuperview(); pool[k] = nil }
    }

    func add(_ path: UIBezierPath, fill: UIColor? = nil, stroke: UIColor? = nil, dash: Bool = false) {
        let l = CAShapeLayer()
        l.path = path.cgPath
        l.fillColor = fill?.cgColor ?? UIColor.clear.cgColor
        l.strokeColor = stroke?.cgColor
        l.lineWidth = stroke == nil ? 0 : 1.5
        if dash { l.lineDashPattern = [5, 4] }
        ribbons.addSublayer(l)
    }
}

/// Links on the board (nexus docs/data-format.md "The board redesign's additions" › Links; the laptop's app/boardlinks.js): the Link
/// button turns Link mode on (tap one thing, then another; drag over a PDF passage to pull it out as an excerpt or link it), the Links
/// menu shows them all, lists them, picks their colour and links the picked thing to a board, a task or a note. A link shows when its
/// thing is picked or its badge tapped; a far end is a tab to peek at or open.
extension BoardController {
    func setUpLinks() {
        linkOverlay.frame = view.bounds
        linkOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(linkOverlay, aboveSubview: canvas)
        // a link opened from another board: look at its end here, its links shown
        if let fe = focusEnd, let b = endBox(fe) {
            focus = b.insetBy(dx: -40, dy: -40)
            links.pinned = fe["on"]?.string
            for l in linkItems where BoardLinks.side(l, on: links.pinned ?? "") != nil { links.flash[l.id] = Date().addingTimeInterval(4) }
        }
    }

    var linkItems: [BoardItem] { content.items.filter(BoardLinks.isLink) }

    // MARK: where things are

    func screenPoint(_ b: CGPoint) -> CGPoint {
        let z = canvas.zoomScale, o = canvas.contentOffset, f = canvas.frame.origin
        return CGPoint(x: (b.x + offset.x) * z - o.x + f.x, y: (b.y + offset.y) * z - o.y + f.y)
    }

    func screenRect(_ r: CGRect) -> CGRect {
        let p = screenPoint(r.origin), z = canvas.zoomScale
        return CGRect(x: p.x, y: p.y, width: r.width * z, height: r.height * z)
    }

    /// A stroke's box (board units), from the strokes as last read or saved.
    func strokeBox(_ id: String) -> CGRect? {
        guard let s = content.strokes.first(where: { $0.id == id }) else { return nil }
        var r = CGRect.null
        for p in s.points where p.count >= 2 {
            let w = p.count > 6 ? p[6] : 2
            r = r.union(CGRect(x: p[0] - w / 2, y: p[1] - w / 2, width: w, height: w))
        }
        return r.isNull ? nil : r.insetBy(dx: -3, dy: -3)
    }

    func thingBox(_ id: String) -> CGRect? {
        if let it = content.items.first(where: { $0.id == id }), !BoardLinks.isLink(it) { return box(of: it) }
        return strokeBox(id)
    }

    /// Where an end on this board is (board units): its words in a text block, its passage or page in a PDF, else the whole thing.
    func endBox(_ e: JSONValue?) -> CGRect? {
        guard let e, BoardLinks.kind(e) == .here, let id = e["on"]?.string else { return nil }
        guard let it = content.items.first(where: { $0.id == id && !BoardLinks.isLink($0) }) else { return strokeBox(id) }
        if it.type == "pdf", let p = pdfs[id], let pg = e["page"]?.number, Int(pg) >= 1, Int(pg) <= p.frames.count {
            let f = p.frames[Int(pg) - 1]
            guard BoardLinks.isPdfSpot(e) else { return f }
            let b = BoardLinks.spotBox(.init(x: Double(f.minX), y: Double(f.minY), w: Double(f.width), h: Double(f.height)), e)
            return CGRect(x: b[0], y: b[1], width: max(4, b[2] - b[0]), height: max(4, b[3] - b[1]))
        }
        if it.type == "text", let at = e["at"], let md = content.texts[id], let r = BoardLinks.find(md, at),
           let v = itemViews[id] as? TextBlockView, let w = v.rect(ofMarkdown: r) {
            return w.insetBy(dx: -2, dy: -1).offsetBy(dx: CGFloat(it.x), dy: CGFloat(it.y))
        }
        return box(of: it)
    }

    func task(_ id: String?) -> NexusTask? {
        guard let id else { return nil }
        if let store { return store.snapshot.tasks[id] }
        if links.tasks == nil { links.tasks = DataFolder.load(root).tasks }
        return links.tasks?[id]
    }

    /// The words for an end, as the Links list and the tabs show them.
    func endText(_ e: JSONValue?) -> String {
        var ctx = BoardLinks.LabelContext()
        switch BoardLinks.kind(e) {
        case .task:
            ctx.taskTitle = task(e?["task"]?.string)?.title
        case .deck:
            ctx.cardFront = cardFront(deck: e?["deck"]?.string, card: e?["card"]?.string)
        case .here:
            let id = e?["on"]?.string ?? ""
            if let it = content.items.first(where: { $0.id == id && !BoardLinks.isLink($0) }) {
                ctx.kind = it.type
                if it.type == "text" { ctx.text = content.texts[id] }
                if it.type == "pdf" { ctx.pdfName = pdfs[id]?.name }
            } else if strokeBox(id) != nil { ctx.kind = "stroke" } else { ctx.missing = true }
        default:
            break
        }
        return BoardLinks.label(e, ctx)
    }

    /// A study card's front, read from its deck file (`- id: <card>` and its `front:` line).
    func cardFront(deck: String?, card: String?) -> String? {
        guard let deck, let card else { return nil }
        if let c = links.cards[deck + "#" + card] { return c.isEmpty ? nil : c }
        let found = readCardFront(deck: deck, card: card)
        links.cards[deck + "#" + card] = found ?? ""
        return found
    }

    func readCardFront(deck: String, card: String) -> String? {
        guard let text = try? String(contentsOf: root.appendingPathComponent(deck), encoding: .utf8) else { return nil }
        var inCard = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- id:") || t.hasPrefix("id:") {
                let v = t.replacingOccurrences(of: #"^-?\s*id:\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
                inCard = v == card
            } else if inCard, t.hasPrefix("front:") {
                return String(t.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
            }
        }
        return nil
    }

    // MARK: drawing

    func paintLinks() {
        guard isViewLoaded, linkOverlay.superview != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let o = linkOverlay
        o.begin()
        let all = linkItems
        let vis = view.bounds
        let now = Date()
        links.flash = links.flash.filter { $0.value > now }

        // a badge on each thing with links, the count of them
        var counts: [String: Int] = [:]
        for l in all {
            var seen = Set<String>()
            for s in ["a", "b"] where BoardLinks.kind(l.json[s]) == .here {
                if let id = l.json[s]?["on"]?.string, !seen.contains(id) { seen.insert(id); counts[id, default: 0] += 1 }
            }
        }
        for (id, n) in counts.sorted(by: { $0.key < $1.key }) {
            guard let b = thingBox(id) else { continue }
            let r = screenRect(b)
            guard r.intersects(vis) else { continue }
            let btn = o.button("badge:" + id) {
                let b = UIButton(type: .custom)
                b.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
                b.layer.cornerRadius = 11
                b.layer.borderWidth = 1.5
                b.accessibilityLabel = "Links"
                b.addAction(UIAction { [weak self] _ in self?.badgeTapped(id) }, for: .touchUpInside)
                return b
            }
            let on = links.pinned == id || selected == id
            let c = InkConvert.color(links.color)
            btn.setTitle("\(n)", for: .normal)
            btn.setTitleColor(on ? .white : c, for: .normal)
            btn.backgroundColor = on ? c : .white
            btn.layer.borderColor = c.cgColor
            let w = max(22, CGFloat(String(n).count) * 7 + 14)
            btn.frame = CGRect(x: min(vis.maxX - w - 4, max(4, r.maxX - w / 2)), y: min(vis.maxY - 26, max(4, r.minY - 12)), width: w, height: 22)
        }

        // the links shown: those of the picked or pinned thing, the ones just made, or all of them
        let focusIds = Set([selected, links.pinned].compactMap { $0 })
        let shown = all.filter { l in
            links.showAll || links.flash[l.id] != nil || focusIds.contains { BoardLinks.side(l, on: $0) != nil }
        }
        let obstacles: [CGRect] = content.items.filter { !BoardLinks.isLink($0) && $0.type != "pdf" }.map { screenRect(box(of: $0)) }.filter { $0.intersects(vis) }
        var tabsAt: [String: Int] = [:]
        for l in shown {
            let color = InkConvert.color(l.string("color") ?? BoardLinks.colors[0])
            let ea = l.json["a"], eb = l.json["b"]
            let ba = endBox(ea).map(screenRect), bb = endBox(eb).map(screenRect)
            for (e, r) in [(ea, ba), (eb, bb)] where BoardLinks.isPdfSpot(e) {
                if let r { o.add(UIBezierPath(roundedRect: r, cornerRadius: 3), fill: color.withAlphaComponent(0.16), stroke: color.withAlphaComponent(0.5)) }
            }
            switch (ba, bb) {
            case let (a?, b?):
                let aIn = a.intersects(vis), bIn = b.intersects(vis)
                if !aIn && !bIn { continue }
                if aIn && bIn {
                    ribbon(from: a, to: b, color: color, obstacles: obstacles.filter { $0 != a && $0 != b })
                } else {
                    // one end off the screen: the ribbon runs to the edge, where a tab takes you to it
                    let (near, far, side) = aIn ? (a, b, "b") : (b, a, "a")
                    let p0 = BoardLinks.edgePoint(rect(near), toward: (Double(far.midX), Double(far.midY)))
                    let q = BoardLinks.clamp(p0, (Double(far.midX), Double(far.midY)), view: rect(vis), pad: 30)
                    let tab = goTab(l, side, color: color, at: CGPoint(x: q.0, y: q.1))
                    ribbon(from: near, to: tab.frame, color: color, obstacles: [])
                }
            case let (a?, nil), let (nil, a?):
                guard a.intersects(vis) else { continue }
                let side = ba == nil ? "a" : "b"
                let key = endKey(ba == nil ? ea : eb, l)
                let n = tabsAt[key, default: 0]
                tabsAt[key] = n + 1
                let tab = farTab(l, side, color: color)
                let x = min(vis.maxX - tab.frame.width - 8, a.maxX + 36), y = min(vis.maxY - 40, max(vis.minY + 8, a.minY + CGFloat(n) * 36 - 4))
                tab.frame.origin = CGPoint(x: max(8, x), y: y)
                if x <= a.maxX { tab.frame.origin.y = min(vis.maxY - 40, a.maxY + 10 + CGFloat(n) * 36) }
                ribbon(from: a, to: tab.frame, color: color, obstacles: [])
            default:
                continue
            }
        }

        // what Link mode is holding: the first end, a passage being chosen or chosen
        if let p = links.pending, let r = endBox(p).map(screenRect) {
            o.add(UIBezierPath(roundedRect: r.insetBy(dx: -4, dy: -4), cornerRadius: 6), fill: InkConvert.color(links.color).withAlphaComponent(0.08),
                  stroke: InkConvert.color(links.color), dash: true)
        }
        if let b = links.band {
            let r = screenRect(CGRect(x: min(b.start.x, b.now.x), y: min(b.start.y, b.now.y), width: abs(b.now.x - b.start.x), height: abs(b.now.y - b.start.y)))
            o.add(UIBezierPath(rect: r), fill: UIColor.systemYellow.withAlphaComponent(0.18), stroke: .systemOrange, dash: true)
        }
        if let p = links.passage {
            o.add(UIBezierPath(roundedRect: screenRect(p.box), cornerRadius: 2), fill: UIColor.systemYellow.withAlphaComponent(0.28), stroke: .systemOrange)
        }
        o.end()
    }

    func rect(_ r: CGRect) -> [Double] { [Double(r.minX), Double(r.minY), Double(r.maxX), Double(r.maxY)] }

    /// The near thing of a link with one far end (tabs on one thing stack down).
    func endKey(_ e: JSONValue?, _ l: BoardItem) -> String {
        for s in ["a", "b"] where BoardLinks.kind(l.json[s]) == .here { return l.json[s]?["on"]?.string ?? l.id }
        return l.id
    }

    /// A soft band between two boxes (screen points), bending around the things in its way.
    func ribbon(from a: CGRect, to b: CGRect, color: UIColor, obstacles: [CGRect]) {
        let p = BoardLinks.edgePoint(rect(a), toward: (Double(b.midX), Double(b.midY)))
        let q = BoardLinks.edgePoint(rect(b), toward: (Double(a.midX), Double(a.midY)))
        let z = Double(max(0.6, min(1.4, canvas.zoomScale)))
        let c = BoardLinks.curve(p, q, obstacles: obstacles.map(rect))
        let pts = BoardLinks.band(p, q, c, w0: 9 * z, w1: 3.5 * z)
        let path = UIBezierPath()
        for (i, pt) in pts.enumerated() {
            let cg = CGPoint(x: pt.0, y: pt.1)
            if i == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
        }
        path.close()
        linkOverlay.add(path, fill: color.withAlphaComponent(0.55))
        for e in [p, q] { linkOverlay.add(UIBezierPath(ovalIn: CGRect(x: e.0 - 3.5, y: e.1 - 3.5, width: 7, height: 7)), fill: color) }
    }

    func tabButton(_ key: String) -> UIButton {
        linkOverlay.button(key) {
            var cfg = UIButton.Configuration.filled()
            cfg.cornerStyle = .capsule
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
            cfg.titleLineBreakMode = .byTruncatingTail
            let b = UIButton(configuration: cfg)
            b.accessibilityIdentifier = key
            b.layer.shadowColor = UIColor.black.cgColor
            b.layer.shadowOpacity = 0.15
            b.layer.shadowRadius = 3
            b.layer.shadowOffset = CGSize(width: 0, height: 1)
            return b
        }
    }

    func style(_ b: UIButton, _ title: String, _ icon: String, _ color: UIColor) {
        var cfg = b.configuration ?? .filled()
        var t = AttributedString(title)
        t.font = .systemFont(ofSize: 13, weight: .medium)
        cfg.attributedTitle = t
        cfg.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        cfg.imagePadding = 5
        cfg.baseBackgroundColor = .white
        cfg.baseForegroundColor = color
        b.configuration = cfg
        b.layer.borderColor = color.cgColor
        b.layer.borderWidth = 1.5
        b.layer.cornerRadius = 15
        let size = b.systemLayoutSizeFitting(CGSize(width: 260, height: 30))
        b.frame.size = CGSize(width: min(260, size.width), height: 30)
    }

    /// A far end's tab: peek at it, open it, recolour or remove the link.
    func farTab(_ l: BoardItem, _ side: String, color: UIColor) -> UIButton {
        let b = tabButton("far:\(l.id):\(side)")
        let e = l.json[side]
        let icon: String = {
            switch BoardLinks.kind(e) {
            case .task: return "checkmark.circle"
            case .note: return "doc.text"
            case .deck: return "rectangle.on.rectangle"
            default: return "arrow.up.forward.square"
            }
        }()
        style(b, endText(e), icon, color)
        b.menu = farMenu(l, side)
        b.showsMenuAsPrimaryAction = true
        return b
    }

    /// The other end is on this board but off the screen: a tab at the edge takes you there.
    func goTab(_ l: BoardItem, _ side: String, color: UIColor, at p: CGPoint) -> UIButton {
        let b = tabButton("go:\(l.id):\(side)")
        style(b, endText(l.json[side]), "arrow.right.circle", color)
        b.frame.origin = CGPoint(x: min(view.bounds.maxX - b.frame.width - 8, max(8, p.x - b.frame.width / 2)),
                                 y: min(view.bounds.maxY - 38, max(8, p.y - 15)))
        b.menu = nil
        b.showsMenuAsPrimaryAction = false
        b.addAction(UIAction(identifier: UIAction.Identifier("go")) { [weak self] _ in
            guard let self, let it = self.content.items.first(where: { $0.id == l.id }) else { return }
            self.show(end: it.json[side], link: l.id)
        }, for: .touchUpInside)
        return b
    }

    func farMenu(_ l: BoardItem, _ side: String) -> UIMenu {
        let e = l.json[side]
        var items: [UIMenuElement] = [
            UIAction(title: "Peek", image: UIImage(systemName: "eye")) { [weak self] _ in self?.peek(e, from: l.id, side: side) },
            UIAction(title: openTitle(e), image: UIImage(systemName: "arrow.up.forward.app")) { [weak self] _ in self?.open(e) },
        ]
        if BoardLinks.kind(e) == .board, let split, !isSidePane, let target = BoardLinks.board(of: e, from: path) {
            items.append(UIAction(title: "Open beside", image: UIImage(systemName: "rectangle.split.2x1")) { [weak self] _ in
                guard let self else { return }
                self.saveNow()
                split.showBoard(target, focusEnd: e?["on"] == nil ? nil : BoardLinks.end(e, readOn: self.path, shownOn: target))
            })
        }
        if !readOnly {
            items.append(colorMenu(l.id))
            items.append(UIAction(title: "Remove link", image: UIImage(systemName: "link.badge.minus"), attributes: .destructive) { [weak self] _ in
                self?.removeLink(l.id)
            })
        }
        return UIMenu(title: endText(e), children: items)
    }

    func openTitle(_ e: JSONValue?) -> String {
        switch BoardLinks.kind(e) {
        case .task: return "Open the task"
        case .note: return "Read the note"
        case .deck: return "Show the card"
        case .board: return e?["on"]?.string == nil ? "Open the board" : "Open it on its board"
        default: return "Go to it"
        }
    }

    func colorMenu(_ id: String) -> UIMenu {
        UIMenu(title: "Colour", image: UIImage(systemName: "paintpalette"), children: zip(BoardLinks.colors, BoardLinks.colorNames).map { hex, name in
            UIAction(title: name, image: UIImage(systemName: "circle.fill")?.withTintColor(InkConvert.color(hex), renderingMode: .alwaysOriginal)) { [weak self] _ in
                self?.recolor(id, hex)
            }
        })
    }

    func badgeTapped(_ id: String) {
        links.pinned = links.pinned == id ? nil : id
        paintLinks()
    }

    func flash(_ id: String, for seconds: TimeInterval = 2.6) {
        links.flash[id] = Date().addingTimeInterval(seconds)
        paintLinks()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in self?.paintLinks() }
    }

    // MARK: the bar

    /// The bar's link buttons (BoardBar's extra buttons): Link mode, and the Links menu.
    func linkBarButtons() -> [UIButton] {
        let size = UIImage.SymbolConfiguration(pointSize: 17)
        var out: [UIButton] = []
        if !readOnly {
            var c = links.mode ? UIButton.Configuration.tinted() : UIButton.Configuration.plain()
            c.image = UIImage(systemName: "link", withConfiguration: size)
            let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.toggleLinkMode() })
            b.accessibilityLabel = links.mode ? "Link mode on" : "Link mode"
            b.isSelected = links.mode
            out.append(b)
        }
        var m = UIButton.Configuration.plain()
        m.image = UIImage(systemName: "point.3.connected.trianglepath.dotted", withConfiguration: size)
        let mb = UIButton(configuration: m)
        mb.menu = linksMenu()
        mb.showsMenuAsPrimaryAction = true
        mb.accessibilityLabel = "Links"
        out.append(mb)
        return out
    }

    func linksMenu() -> UIMenu {
        var items: [UIMenuElement] = [
            UIAction(title: "Show all links", image: UIImage(systemName: "eye"), state: links.showAll ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.links.showAll.toggle()
                UserDefaults.standard.set(self.links.showAll, forKey: "board.links.showAll")
                self.paintLinks()
                self.updateBar()
            },
            UIAction(title: "All links…", image: UIImage(systemName: "list.bullet")) { [weak self] _ in self?.showLinksList() },
        ]
        if !readOnly {
            items.append(UIMenu(title: "New link colour", image: UIImage(systemName: "paintpalette"), children: zip(BoardLinks.colors, BoardLinks.colorNames).map { hex, name in
                UIAction(title: name, image: UIImage(systemName: "circle.fill")?.withTintColor(InkConvert.color(hex), renderingMode: .alwaysOriginal),
                         state: links.color == hex ? .on : .off) { [weak self] _ in
                    self?.links.color = hex
                    UserDefaults.standard.set(hex, forKey: "board.links.color")
                    self?.updateBar()
                    self?.paintLinks()
                }
            }))
            if let id = selected, let it = content.items.first(where: { $0.id == id }) {
                var here: [UIMenuElement] = [
                    UIAction(title: "Link this to…", image: UIImage(systemName: "arrow.up.forward.square")) { [weak self] _ in
                        self?.pickTarget(from: .object([("on", .string(id))]))
                    },
                    UIAction(title: "Start a link here", image: UIImage(systemName: "link")) { [weak self] _ in
                        self?.startLink(from: .object([("on", .string(id))]))
                    },
                ]
                if it.type == "text" {
                    here.append(UIAction(title: "Link words in it…", image: UIImage(systemName: "text.quote")) { [weak self] _ in self?.pickWords(id) })
                }
                items.append(UIMenu(title: "", options: .displayInline, children: here))
            }
        }
        return UIMenu(title: "Links", children: items)
    }

    @objc func toggleLinkMode() {
        links.mode.toggle()
        links.pending = nil
        links.passage = nil
        links.band = nil
        if links.mode {
            refreshStrokes()
            toast("Link mode: tap one thing, then another. Drag over a PDF passage to pull it out.")
        } else {
            toast("Link mode off")
        }
        updateBar()
        paintLinks()
    }

    func startLink(from e: JSONValue) {
        if !links.mode { links.mode = true; refreshStrokes(); updateBar() }
        links.pending = e
        toast("Now tap what to link it to")
        paintLinks()
    }

    /// The strokes as the canvas has them now, with their ids (new strokes get theirs here, as a save would give them).
    func refreshStrokes() {
        content.strokes = ledger.strokes(canvas.drawing, offset: offset, taken: Set(content.items.map(\.id)))
    }

    // MARK: Link mode

    func strokeAt(_ p: CGPoint) -> String? {
        refreshStrokes()
        let reach = 12 / canvas.zoomScale
        var best: (id: String, d: CGFloat)?
        for s in content.strokes.reversed() {
            for q in s.points where q.count >= 2 {
                let d = hypot(CGFloat(q[0]) - p.x, CGFloat(q[1]) - p.y)
                if d < reach, best == nil || d < best!.d { best = (s.id, d) }
            }
        }
        return best?.id
    }

    func pdfPage(at p: CGPoint) -> (String, Int)? {
        for (id, pp) in pdfs.sorted(by: { $0.key < $1.key }) {
            if let i = pp.frames.firstIndex(where: { $0.contains(p) }) { return (id, i) }
        }
        return nil
    }

    /// The end under a finger: an item (not a PDF), else ink, else a PDF page.
    func endAt(_ p: CGPoint) -> JSONValue? {
        if let it = hitItem(p, pdf: false) { return .object([("on", .string(it.id))]) }
        if let s = strokeAt(p) { return .object([("on", .string(s))]) }
        if let hit = pdfPage(at: p) { return .object([("on", .string(hit.0)), ("page", .number(Double(hit.1 + 1)))]) }
        return nil
    }

    func linkTapped(_ p: CGPoint) {
        guard !readOnly else { return }
        if let pas = links.passage, pas.box.insetBy(dx: -10 / canvas.zoomScale, dy: -10 / canvas.zoomScale).contains(p) {
            passageMenu(pas)
            return
        }
        links.passage = nil
        guard let end = endAt(p) else {
            if links.pending != nil { links.pending = nil; toast("Link cancelled") } else { toast("Tap a thing to link from, or drag over a PDF passage") }
            paintLinks()
            return
        }
        if let a = links.pending {
            links.pending = nil
            makeLinkHere(a, end)
        } else {
            links.pending = end
            toast("Now tap what to link it to")
        }
        paintLinks()
    }

    func linkPanShouldBegin(_ pan: UIPanGestureRecognizer) -> Bool {
        guard !readOnly else { return false }
        let z = canvas.zoomScale, t = pan.translation(in: canvas), now = boardPoint(pan)
        return pdfPage(at: CGPoint(x: now.x - t.x / z, y: now.y - t.y / z)) != nil
    }

    func linkPanned(_ g: UIPanGestureRecognizer) {
        let z = canvas.zoomScale
        switch g.state {
        case .began:
            let t = g.translation(in: canvas), now = boardPoint(g)
            let start = CGPoint(x: now.x - t.x / z, y: now.y - t.y / z)
            guard let hit = pdfPage(at: start) else { return }
            links.passage = nil
            links.band = LinkState.Band(start: start, now: now, pdf: hit.0, page: hit.1)
        case .changed:
            links.band?.now = boardPoint(g)
        case .ended:
            if let b = links.band { links.band = nil; finishPassage(b) }
        default:
            links.band = nil
        }
        paintLinks()
    }

    func finishPassage(_ b: LinkState.Band) {
        guard let p = pdfs[b.pdf], b.page < p.frames.count else { return }
        let f = p.frames[b.page]
        let r = CGRect(x: min(b.start.x, b.now.x), y: min(b.start.y, b.now.y), width: abs(b.now.x - b.start.x), height: abs(b.now.y - b.start.y)).intersection(f)
        guard !r.isNull, r.width * canvas.zoomScale > 8, r.height * canvas.zoomScale > 6 else { return }
        let frame = BoardLinks.Frame(x: Double(f.minX), y: Double(f.minY), w: Double(f.width), h: Double(f.height))
        let spot = BoardLinks.pdfSpot(frame, rect(r))
        let end = JSONValue.object([("on", .string(b.pdf)), ("page", .number(Double(b.page + 1)))] + spot)
        let sb = BoardLinks.spotBox(frame, end)
        let pas = LinkState.Passage(pdf: b.pdf, page: b.page, box: CGRect(x: sb[0], y: sb[1], width: sb[2] - sb[0], height: sb[3] - sb[1]), end: end)
        if let a = links.pending {
            links.pending = nil
            makeLinkHere(a, end)
            return
        }
        links.passage = pas
        paintLinks()
        passageMenu(pas)
    }

    func passageMenu(_ pas: LinkState.Passage) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Pull out as an excerpt", style: .default) { [weak self] _ in self?.excerpt(pas, picture: false) })
        sheet.addAction(UIAlertAction(title: "Pull out as a picture", style: .default) { [weak self] _ in self?.excerpt(pas, picture: true) })
        sheet.addAction(UIAlertAction(title: "Link from this passage", style: .default) { [weak self] _ in
            self?.links.passage = nil
            self?.startLink(from: pas.end)
        })
        sheet.addAction(UIAlertAction(title: "Link it to a board, task or note…", style: .default) { [weak self] _ in
            self?.links.passage = nil
            self?.pickTarget(from: pas.end)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.links.passage = nil; self?.paintLinks() })
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = screenRect(pas.box).intersection(view.bounds).insetBy(dx: -4, dy: -4)
        present(sheet, animated: true)
    }

    // MARK: excerpts

    /// The passage's words (PDFKit's text under the box), lines joined.
    func passageText(_ p: PdfPrintout, _ pas: LinkState.Passage) -> String {
        guard let page = p.doc.page(at: pas.page), page.rotation % 360 == 0 else { return "" }
        let mb = page.bounds(for: .mediaBox)
        func v(_ k: String) -> CGFloat { CGFloat(pas.end[k]?.number ?? 0) }
        let r = CGRect(x: mb.minX + v("fx") * mb.width, y: mb.maxY - (v("fy") + v("fh")) * mb.height, width: v("fw") * mb.width, height: v("fh") * mb.height)
        let s = page.selection(for: r)?.string ?? ""
        return s.replacingOccurrences(of: #"-\n(?=\p{Ll})"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A picture of the passage, sharp enough to read.
    func passagePNG(_ p: PdfPrintout, _ pas: LinkState.Passage) -> Data? {
        guard let page = p.doc.page(at: pas.page) else { return nil }
        let f = p.frames[pas.page]
        let scale = max(1, min(4, 900 / max(1, pas.box.width)))
        let size = CGSize(width: max(1, (pas.box.width * scale).rounded()), height: max(1, (pas.box.height * scale).rounded()))
        let full = CGSize(width: f.width * scale, height: f.height * scale)
        let pageSize = PdfPrintout.displaySize(page)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.translateBy(x: -(pas.box.minX - f.minX) * scale, y: -(pas.box.minY - f.minY) * scale)
            cg.translateBy(x: 0, y: full.height)
            cg.scaleBy(x: full.width / pageSize.width, y: -full.height / pageSize.height)
            page.draw(with: .mediaBox, to: cg)
        }
    }

    /// The passage beside its page, as a text block (a picture when it has no words, or when asked), linked to its spot.
    func excerpt(_ pas: LinkState.Passage, picture: Bool) {
        links.passage = nil
        guard !readOnly, let p = pdfs[pas.pdf], pas.page < p.frames.count else { paintLinks(); return }
        let f = p.frames[pas.page]
        let at = CGPoint(x: (f.maxX + 40).rounded(), y: pas.box.minY.rounded())
        let say = "An excerpt, linked to its page. Undo takes it back."
        let text = picture ? "" : passageText(p, pas)
        if text.filter({ !$0.isWhitespace }).count >= 2 {
            let id = BoardFormat.newId(taken: allIds)
            let it = BoardItem(id: id, type: "text", x: Double(at.x), y: Double(at.y), fields: [
                ("w", .number(Double(max(220, min(420, pas.box.width)).rounded()))), ("fill", .string(BoardLinks.excerptFill)),
            ])
            makeLinkHere(.object([("on", .string(id))]), pas.end, with: [it], texts: [id: text], say: say)
            return
        }
        guard let png = passagePNG(p, pas) else { tell("That passage couldn't be drawn."); return }
        let filesDir = boardURL.appendingPathComponent("files", isDirectory: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: filesDir.path)) ?? [])
        let name = BoardFormat.freeName("excerpt p\(pas.page + 1)", taken: taken, suffix: ".png")
        do { try FolderAccess.writeData(filesDir.appendingPathComponent(name), png) } catch { tell("Couldn't add the excerpt: \(error.localizedDescription)"); return }
        let id = BoardFormat.newId(taken: allIds)
        let it = BoardItem(id: id, type: "image", x: Double(at.x), y: Double(at.y), fields: [
            ("src", .string("files/" + name)), ("w", .number(Double(pas.box.width.rounded()))), ("h", .number(Double(pas.box.height.rounded()))),
        ])
        makeLinkHere(.object([("on", .string(id))]), pas.end, with: [it], say: say)
    }

    // MARK: making, changing, removing

    @discardableResult
    func makeLinkHere(_ a: JSONValue, _ b: JSONValue, with extra: [BoardItem] = [], texts: [String: String] = [:],
                      say: String = "Linked. Undo takes it back.") -> BoardItem? {
        guard !readOnly else { return nil }
        let bothHere = BoardLinks.kind(a) == .here && BoardLinks.kind(b) == .here
        if BoardLinks.same(a, b) || (bothHere && a["on"] == b["on"] && a["page"] == nil && b["page"] == nil && a["at"] == nil && b["at"] == nil) {
            toast("Pick two different things to link")
            return nil
        }
        if let dup = linkItems.first(where: { l in
            (BoardLinks.same(l.json["a"], a) && BoardLinks.same(l.json["b"], b)) || (BoardLinks.same(l.json["a"], b) && BoardLinks.same(l.json["b"], a))
        }) {
            flash(dup.id)
            toast("These two are linked already")
            return dup
        }
        var taken = allIds
        for it in extra { taken.insert(it.id) }
        let at: CGPoint = extra.first.map { CGPoint(x: $0.x, y: $0.y) } ?? endBox(a)?.origin ?? visibleBoard.origin
        guard let link = BoardLinks.make(id: BoardFormat.newId(taken: taken), a: a, b: b, color: links.color, by: deviceName,
                                         x: Double(at.x), y: Double(at.y)) else { return nil }
        changeItems("Link") { c in
            c.items.append(contentsOf: extra)
            c.items.append(link)
            for (k, v) in texts { c.texts[k] = v }
            if let meta = c.meta ?? (try? JSONValue.parse(BoardFormat.boardJSON())) { c.meta = BoardFormat.withFeature(meta, BoardLinks.feature) }
        }
        flash(link.id)
        toast(say)
        return link
    }

    func removeLink(_ id: String) {
        guard !readOnly else { return }
        changeItems("Remove link") { c in c.items.removeAll { $0.id == id } }
        toast("Link removed. Undo brings it back.")
    }

    func recolor(_ id: String, _ hex: String) {
        guard !readOnly else { return }
        changeItems("Link colour") { c in
            if let i = c.items.firstIndex(where: { $0.id == id }) { c.items[i] = c.items[i].with("color", .string(hex)) }
        }
        flash(id)
    }

    // MARK: going to an end

    /// An end on this board: scroll it into view, its links shown for a moment.
    func show(end e: JSONValue?, link: String?) {
        guard let b = endBox(e) else { toast("That is no longer on the board"); return }
        let z = canvas.zoomScale
        scroll(toBoard: CGPoint(x: b.midX - canvas.bounds.width / 2 / z, y: b.midY - canvas.bounds.height / 2 / z))
        links.pinned = e?["on"]?.string
        if let link { flash(link, for: 3) } else { paintLinks() }
    }

    /// Opens a far end: its board (on top of this one, Close comes back), the task's panel, the note or the card to read.
    func open(_ e: JSONValue?) {
        guard let e else { return }
        switch BoardLinks.kind(e) {
        case .here:
            show(end: e, link: nil)
        case .board:
            guard let target = BoardLinks.board(of: e, from: path) else { return }
            openBoard(target, end: e["on"] == nil ? nil : BoardLinks.end(e, readOn: path, shownOn: target))
        case .task:
            guard let store, let id = e["task"]?.string, store.snapshot.tasks[id] != nil else { toast("That task isn't in the data folder"); return }
            let host = UIHostingController(rootView: TaskDetailView(taskId: id).environment(store))
            host.modalPresentationStyle = .formSheet
            present(host, animated: true)
        case .note, .deck:
            peek(e, from: nil, side: nil)
        case nil:
            break
        }
    }

    func openBoard(_ target: String, end: JSONValue?) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(target).appendingPathComponent("board.json").path, isDirectory: &isDir) else {
            toast("That board isn't in the data folder any more")
            return
        }
        saveNow()
        let vc = BoardController(root: root, path: target, focus: nil)
        vc.focusEnd = end
        vc.store = store
        vc.onSaved = onSaved
        vc.onClose = { [weak vc] in vc?.navigationController?.popViewController(animated: true) }
        navigationController?.pushViewController(vc, animated: true)
    }

    /// A quick look at a far end without leaving the board.
    func peek(_ e: JSONValue?, from link: String?, side: String?) {
        guard let e else { return }
        var title = endText(e), detail = "", body = ""
        var actions: [LinkPeek.Action] = []
        switch BoardLinks.kind(e) {
        case .task:
            if let t = task(e["task"]?.string) {
                title = t.title
                var bits: [String] = []
                if t.done { bits.append("Done") }
                if let d = t.due { bits.append("Due " + d) }
                if let ws = t.workstream, let w = store?.snapshot.workstreams[ws] { bits.append(w.name) }
                detail = bits.joined(separator: " · ")
                body = t.note ?? ""
            } else { detail = "This task isn't in the data folder." }
            actions.append(.init(title: "Open the task") { [weak self] in self?.open(e) })
        case .note:
            let rel = e["note"]?.string ?? ""
            detail = rel
            body = (try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)) ?? "This note isn't in the data folder."
        case .deck:
            detail = e["deck"]?.string ?? ""
            body = cardFront(deck: e["deck"]?.string, card: e["card"]?.string).map { "Front: " + $0 } ?? "Card \(e["card"]?.string ?? "")"
        case .board:
            let target = BoardLinks.board(of: e, from: path) ?? ""
            detail = target
            body = e["on"] == nil ? "The whole board." : "On that board: " + BoardLinks.label(e)
            actions.append(.init(title: openTitle(e)) { [weak self] in self?.open(e) })
        default:
            body = title
            actions.append(.init(title: "Go to it") { [weak self] in self?.open(e) })
        }
        if let link, !readOnly {
            actions.append(.init(title: "Remove link", destructive: true) { [weak self] in self?.removeLink(link) })
        }
        let host = UIHostingController(rootView: LinkPeek(title: title, detail: detail, text: body, actions: actions,
                                                         close: { [weak self] in self?.dismiss(animated: true) }))
        host.modalPresentationStyle = .popover
        host.preferredContentSize = CGSize(width: 380, height: 420)
        if let link, let side, let b = linkOverlay.subviews.first(where: { $0.accessibilityIdentifier == "far:\(link):\(side)" }) {
            host.popoverPresentationController?.sourceView = b
            host.popoverPresentationController?.sourceRect = b.bounds
        } else {
            host.popoverPresentationController?.sourceView = view
            host.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            host.popoverPresentationController?.permittedArrowDirections = []
        }
        present(host, animated: true)
    }

    // MARK: linking outside the board

    /// Pick a board, a task or a note to link `from` to.
    func pickTarget(from: JSONValue) {
        let boards = Notebook.list(root).flatMap { nb in nb.allBoards.map(\.board) }.filter { $0.path != path }
        let tasks: [NexusTask] = (store?.snapshot.tasks.values.map { $0 } ?? (links.tasks ?? DataFolder.load(root).tasks).values.map { $0 })
            .filter { $0.hasId && !$0.done }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let picker = LinkTargetPicker(boards: boards.map { .init(id: $0.path, title: $0.name, detail: String($0.path.dropFirst(BoardFormat.notebooks.count + 1))) },
                                      tasks: tasks.map { .init(id: $0.id, title: $0.title, detail: $0.due.map { "Due " + $0 } ?? "") },
                                      notes: noteFiles().map { .init(id: $0, title: ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: ""), detail: $0) },
                                      onPick: { [weak self] kind, id in
                                          guard let self else { return }
                                          self.dismiss(animated: true)
                                          let end: JSONValue?
                                          switch kind {
                                          case .board: end = BoardLinks.end(for: .object([]), target: id, from: self.path)
                                          case .task: end = .object([("task", .string(id))])
                                          case .note: end = .object([("note", .string(id))])
                                          }
                                          if let end { self.makeLinkHere(from, end) }
                                      },
                                      onCancel: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: picker)
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    /// The data folder's markdown notes (not inside boards or hidden folders), as data-folder paths.
    func noteFiles() -> [String] {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        let base = root.standardizedFileURL.path
        for case let url as URL in walk {
            let name = url.lastPathComponent
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if name.lowercased().hasSuffix(".board") || name == "node_modules" { walk.skipDescendants() }
                continue
            }
            guard name.lowercased().hasSuffix(".md") else { continue }
            let p = url.standardizedFileURL.path
            if p.hasPrefix(base + "/") { out.append(String(p.dropFirst(base.count + 1))) }
            if out.count >= 3000 { break }
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Words of a text block to link: the block's text to select in, then link from them or link them to something outside.
    func pickWords(_ id: String) {
        let md = content.texts[id] ?? ""
        let vc = WordPickerController(markdown: md) { [weak self] range, outside in
            guard let self else { return }
            self.dismiss(animated: true)
            guard let at = BoardLinks.quote(md, from: range.location, to: range.location + range.length) else { return }
            let end = JSONValue.object([("on", .string(id)), ("at", at)])
            if outside { self.pickTarget(from: end) } else { self.startLink(from: end) }
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    // MARK: the Links list

    /// Every board's links, read from the tiles (this board as it is now).
    func linkIndex() -> [(String, [BoardItem])] {
        var out: [(String, [BoardItem])] = [(path, linkItems)]
        let boards = Notebook.list(root).flatMap { nb in nb.allBoards.map(\.board) }
        let fm = FileManager.default
        for b in boards where b.path != path {
            let tiles = root.appendingPathComponent(b.path).appendingPathComponent("tiles")
            var found: [BoardItem] = []
            for name in ((try? fm.contentsOfDirectory(atPath: tiles.path)) ?? []).sorted() where BoardFormat.keyOfFile(name) != nil {
                if let d = try? Data(contentsOf: tiles.appendingPathComponent(name)) { found += BoardLinks.links(inTile: String(decoding: d, as: UTF8.self)) }
            }
            if !found.isEmpty { out.append((b.path, found)) }
        }
        return out
    }

    func showLinksList() {
        let index = linkIndex()
        func boardName(_ p: String) -> String { String((p as NSString).lastPathComponent.replacingOccurrences(of: ".board", with: "")) }
        func groupTitle(_ g: String) -> String {
            switch g {
            case "here": return "On this board"
            case "task": return "Tasks"
            case "note": return "Notes"
            case "deck": return "Study cards"
            default: return g.hasPrefix("board:") ? "To " + boardName(String(g.dropFirst(6))) : g
            }
        }
        var rows: [LinksList.Row] = []
        for l in linkItems {
            // the far end decides the group; a link between two things here is "On this board"
            let far = BoardLinks.kind(l.json["b"]) != .here ? "b" : (BoardLinks.kind(l.json["a"]) != .here ? "a" : "b")
            let near = BoardLinks.other(far)
            let missing = endBox(l.json[near]) == nil && BoardLinks.kind(l.json[near]) == .here
            rows.append(.init(id: l.id, board: path, color: l.string("color") ?? BoardLinks.colors[0], near: endText(l.json[near]), far: endText(l.json[far]),
                              group: groupTitle(BoardLinks.group(of: l.json[far], from: path)), mine: true, missing: missing))
        }
        for f in BoardLinks.incoming(index, to: path) {
            let fromEnd = BoardLinks.end(f.link.json[BoardLinks.other(f.side)], readOn: f.from, shownOn: path)
            let toEnd = BoardLinks.end(f.link.json[f.side], readOn: f.from, shownOn: path)
            rows.append(.init(id: f.from + "#" + f.link.id, board: f.from, color: f.link.string("color") ?? BoardLinks.colors[0],
                              near: toEnd.map { BoardLinks.kind($0) == .here ? endText($0) : "This board" } ?? "This board",
                              far: fromEnd.map { BoardLinks.label($0) } ?? boardName(f.from), group: "From other boards", mine: false, missing: false))
        }
        var everywhere: [LinksList.Row] = []
        for (b, ls) in index where b != path {
            for l in ls {
                let a = BoardLinks.end(l.json["a"], readOn: b, shownOn: path), z = BoardLinks.end(l.json["b"], readOn: b, shownOn: path)
                everywhere.append(.init(id: b + "#" + l.id, board: b, color: l.string("color") ?? BoardLinks.colors[0], near: a.map { BoardLinks.label($0) } ?? "",
                                        far: z.map { BoardLinks.label($0) } ?? "", group: boardName(b), mine: false, missing: false))
            }
        }
        let list = LinksList(here: rows, everywhere: everywhere, readOnly: readOnly,
                             onGo: { [weak self] row in
                                 guard let self else { return }
                                 self.dismiss(animated: true)
                                 if row.mine, let l = self.content.items.first(where: { $0.id == row.id }) {
                                     let side = BoardLinks.kind(l.json["a"]) == .here ? "a" : "b"
                                     self.show(end: l.json[side], link: l.id)
                                 } else {
                                     let lid = String(row.id.split(separator: "#").last ?? "")
                                     let l = index.first(where: { $0.0 == row.board })?.1.first(where: { $0.id == lid })
                                     let side = l.map { BoardLinks.kind($0.json["a"]) == .here ? "a" : "b" } ?? "a"
                                     self.openBoard(row.board, end: l?.json[side].flatMap { BoardLinks.kind($0) == .here ? $0 : nil })
                                 }
                             },
                             onRemove: { [weak self] row in self?.removeLink(row.id) },
                             onColor: { [weak self] row, hex in self?.recolor(row.id, hex) },
                             onClose: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: list)
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }
}

extension TextBlockView {
    /// Where the markdown's characters in `range` are drawn (this view's coordinates): the block lays out its markdown as it is.
    func rect(ofMarkdown range: NSRange) -> CGRect? {
        guard let t = layout?.text, range.location >= 0, range.length > 0, NSMaxRange(range) <= t.storage.length else { return nil }
        let g = t.manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        return t.manager.boundingRect(forGlyphRange: g, in: t.container).offsetBy(dx: t.padding.x, dy: t.padding.y)
    }
}
