import UIKit
import PDFKit
import PencilKit
import NexusCore

/// Where an item sits on the board (board units), as the laptop's `boxOf`: a line or arrow gets room for its width and head.
func boardBox(_ it: BoardItem, textSize: CGSize? = nil) -> CGRect {
    let x = it.x, y = it.y
    switch it.type {
    case "shape":
        let w = it.w ?? 100, h = it.h ?? 60
        if it.shape == "line" || it.shape == "arrow" {
            let pad = (it.number("width") ?? 2) * 2 + (it.shape == "arrow" ? 12 : 0)
            return CGRect(x: min(x, x + w) - pad, y: min(y, y + h) - pad, width: abs(w) + 2 * pad, height: abs(h) + 2 * pad)
        }
        return CGRect(x: min(x, x + w), y: min(y, y + h), width: abs(w), height: abs(h))
    case "text":
        let s = textSize ?? CGSize(width: it.w ?? BoardFormat.textWidth, height: 40)
        return CGRect(x: x, y: y, width: s.width, height: s.height)
    case "tool":
        return CGRect(x: x, y: y, width: max(ToolCatalog.minW, it.w ?? 480), height: max(ToolCatalog.minH, it.h ?? 360))
    default:
        if it.isForeign { return CGRect(x: x, y: y, width: it.w ?? BoardFormat.foreignSize.w, height: it.h ?? BoardFormat.foreignSize.h) }
        return CGRect(x: x, y: y, width: it.w ?? 0, height: it.h ?? 0)
    }
}

/// A rectangle, ellipse, line or arrow, drawn as the laptop draws it (boarditems.js drawShape).
/// An item a newer Nexus made (a type this app doesn't know): a grey dashed box saying so. The item is kept and written back as it is.
final class ForeignItemView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = UIColor.black.withAlphaComponent(0.04)
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.black.withAlphaComponent(0.3).cgColor
        label.text = "Made by a newer Nexus"
        label.font = .systemFont(ofSize: 12)
        label.textColor = UIColor.black.withAlphaComponent(0.5)
        label.textAlignment = .center
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ it: BoardItem, offset: CGPoint) {
        frame = boardBox(it).offsetBy(dx: offset.x, dy: offset.y)
        label.frame = bounds
    }
}

final class ShapeItemView: UIView {
    private let body = CAShapeLayer()
    private let head = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        for l in [body, head] {
            l.lineCap = .round
            l.lineJoin = .round
            layer.addSublayer(l)
        }
        head.fillColor = UIColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ it: BoardItem, offset: CGPoint) {
        let w = it.w ?? 100, h = it.h ?? 60
        let sw = max(0.5, it.number("width") ?? 2)
        let kind = it.shape ?? "rect"
        let pad = sw * 2 + (kind == "arrow" ? sw * 4 + 8 : 0)
        let x0 = min(it.x, it.x + w) - pad, y0 = min(it.y, it.y + h) - pad
        frame = CGRect(x: x0 + offset.x, y: y0 + offset.y, width: abs(w) + 2 * pad, height: abs(h) + 2 * pad)
        let ax = it.x - x0, ay = it.y - y0, bx = ax + w, by = ay + h
        // on a dark board, colours show as PencilKit shows ink there (black becomes white)
        let dark = traitCollection.userInterfaceStyle == .dark
        func shown(_ hex: String) -> CGColor {
            let c = InkConvert.color(hex)
            return (dark ? PKInkingTool.convertColor(c, from: .light, to: .dark) : c).cgColor
        }
        let stroke = shown(it.string("color") ?? "#1B1B1BFF")
        let fill: CGColor = it.string("fill").map(shown) ?? UIColor.clear.cgColor
        body.frame = bounds
        head.frame = bounds
        body.strokeColor = stroke
        head.strokeColor = stroke
        body.lineWidth = sw
        head.lineWidth = sw
        let path: UIBezierPath
        head.path = nil
        switch kind {
        case "rect":
            let r = CGRect(x: min(ax, bx), y: min(ay, by), width: abs(w), height: abs(h))
            path = UIBezierPath(roundedRect: r, cornerRadius: min(6, abs(w) / 4, abs(h) / 4))
            body.fillColor = fill
        case "ellipse":
            path = UIBezierPath(ovalIn: CGRect(x: min(ax, bx), y: min(ay, by), width: abs(w), height: abs(h)))
            body.fillColor = fill
        default:
            path = UIBezierPath()
            path.move(to: CGPoint(x: ax, y: ay))
            path.addLine(to: CGPoint(x: bx, y: by))
            body.fillColor = UIColor.clear.cgColor
            if kind == "arrow" {
                let len = max(hypot(w, h), 1), ux = w / len, uy = h / len, s = min(len * 0.4, 8 + sw * 3)
                let p = UIBezierPath()
                p.move(to: CGPoint(x: bx - ux * s - uy * s * 0.55, y: by - uy * s + ux * s * 0.55))
                p.addLine(to: CGPoint(x: bx, y: by))
                p.addLine(to: CGPoint(x: bx - ux * s + uy * s * 0.55, y: by - uy * s - ux * s * 0.55))
                head.path = p.cgPath
            }
        }
        body.path = path.cgPath
    }
}

/// An image or a screen clip from the board's files/, read at a size that suits the board (big photos are scaled down).
final class ImageItemView: UIImageView {
    private(set) var src: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        contentMode = .scaleToFill
        backgroundColor = UIColor(white: 0.9, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(_ it: BoardItem, offset: CGPoint, url: URL?) {
        frame = CGRect(x: it.x + offset.x, y: it.y + offset.y, width: max(1, it.w ?? 200), height: max(1, it.h ?? 150))
        guard it.src != src else { return }
        src = it.src
        image = nil
        guard let url else { return }
        let want = CGSize(width: 2048, height: 2048)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let img = UIImage(contentsOfFile: url.path)
            let small: UIImage?
            if let img, img.size.width > want.width || img.size.height > want.height {
                small = img.preparingThumbnail(of: CGSize(width: min(want.width, img.size.width * want.height / max(img.size.height, 1)),
                                                          height: min(want.height, img.size.height * want.width / max(img.size.width, 1))))
            } else { small = img }
            DispatchQueue.main.async {
                guard let self, self.src == it.src else { return }
                self.image = small
                self.backgroundColor = small == nil ? UIColor(white: 0.9, alpha: 1) : .clear
            }
        }
    }
}

/// The dashed box around the selected item, with a handle to resize it (kept the same size on screen at any zoom).
final class SelectionView: UIView {
    let handle = UIView()
    private let border = CAShapeLayer()
    var resizable = true { didSet { handle.isHidden = !resizable } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor.systemBlue.cgColor
        border.lineDashPattern = [6, 4]
        layer.addSublayer(border)
        handle.backgroundColor = .white
        handle.layer.borderColor = UIColor.systemBlue.cgColor
        addSubview(handle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ rect: CGRect, zoom: CGFloat) {
        let pad = 4 / zoom
        frame = rect.insetBy(dx: -pad, dy: -pad)
        border.frame = bounds
        border.lineWidth = 1.5 / zoom
        border.lineDashPattern = [NSNumber(value: Double(6 / zoom)), NSNumber(value: Double(4 / zoom))]
        border.path = UIBezierPath(rect: bounds).cgPath
        let s = 16 / zoom
        handle.frame = CGRect(x: bounds.maxX - s / 2, y: bounds.maxY - s / 2, width: s, height: s)
        handle.layer.cornerRadius = s / 2
        handle.layer.borderWidth = 2 / zoom
    }
}

/// A PDF printout on the board: its pages down from the item's x, y, each `w` wide and `gap` apart, with any room opened in it
/// (board.json's `space`: above a page, after it, or the page opened in two). Each piece of a page is its own view showing that
/// part of the page's picture. Only pages near the view are drawn, and pages far away are freed, so long PDFs stay light.
/// A page's picture is sharp up to 150 %; closer in, a close-up of just the part on screen is drawn over it once the board stops
/// moving (NexusCore `PdfSharpness`), so deep zoom never asks for a picture of the whole page bigger than the iPad can hold.
final class PdfPrintout {
    struct OutlineItem { let title: String; let page: Int; let depth: Int }

    private(set) var item: BoardItem
    let doc: PDFDocument
    let name: String
    /// Each page's whole extent on the board (a page opened in two spans both parts and the room between).
    private(set) var frames: [CGRect] = []
    private(set) var segments: [BoardFiles.PdfSegment] = []
    private var sizes: [(w: Double, h: Double)] = []
    private var views: [(outer: UIView, clip: UIView, image: UIImageView, shade: UIView)] = []
    private var images: [UIImage?] = []
    /// Pixels per board unit of each page's picture on show (0: none).
    private var rendered: [CGFloat] = []
    /// Pages being drawn.
    private var pending = Set<Int>()
    /// Bumped when a page's picture is let go, so a draw still under way for it is dropped when it lands.
    private var generation: [Int] = []
    /// When a page's draw last failed (out of memory): it is tried again a little later, not on every move.
    private var failedAt: [Int: Date] = [:]
    /// The close-up over each piece of a page in view at deep zoom, by segment index: its view, the board rect it shows, its sharpness.
    private var closeUps: [Int: (view: UIImageView, rect: CGRect, scale: CGFloat)] = [:]
    private var closeUpGen = 0
    private var closeUpWork: DispatchWorkItem?
    private var last: (visible: CGRect, zoom: CGFloat, screenScale: CGFloat)?
    private var memoryWatch: NSObjectProtocol?
    private var dim = false
    private static let queue = DispatchQueue(label: "app.nexus.pdf-render", qos: .userInitiated)

    init?(item: BoardItem, url: URL) {
        guard let doc = PDFDocument(url: url) else { return nil }
        self.item = item
        self.doc = doc
        name = url.deletingPathExtension().lastPathComponent
        sizes = (0..<doc.pageCount).map { i in
            let s = PdfPrintout.displaySize(doc.page(at: i))
            return (w: Double(s.width), h: Double(s.height))
        }
        images = Array(repeating: nil, count: doc.pageCount)
        rendered = Array(repeating: 0, count: doc.pageCount)
        generation = Array(repeating: 0, count: doc.pageCount)
        layOut()
        memoryWatch = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.lowMemory()
        }
    }

    deinit {
        if let memoryWatch { NotificationCenter.default.removeObserver(memoryWatch) }
        closeUpWork?.cancel()
    }

    static func displaySize(_ page: PDFPage?) -> CGSize {
        guard let page else { return CGSize(width: 612, height: 792) }
        let box = page.bounds(for: .mediaBox)
        return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    private func layOut() {
        segments = BoardFiles.pdfSegments(item, sizes: sizes)
        frames = BoardFiles.pdfFrames(item, sizes: sizes).map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) }
    }

    var box: CGRect { frames.reduce(CGRect.null) { $0.union($1) } }

    /// A segment's place on the board.
    static func rect(_ s: BoardFiles.PdfSegment) -> CGRect { CGRect(x: s.x, y: s.y, width: s.w, height: s.h) }

    /// The whole page's height on the board.
    func pageHeight(_ s: BoardFiles.PdfSegment) -> CGFloat {
        CGFloat(s.bottom > s.top ? s.h / (s.bottom - s.top) : s.h)
    }

    /// Page `i`'s own size (PDF points, turned as shown) and its size on the board.
    private func pageSize(_ i: Int) -> CGSize { CGSize(width: sizes[i].w, height: sizes[i].h) }
    private func boardSize(_ i: Int) -> CGSize {
        let w = CGFloat(item.w ?? BoardFormat.pdfWidth)
        return CGSize(width: w, height: w * CGFloat(sizes[i].h / max(1, sizes[i].w)))
    }

    /// Moved, resized or opened up: the pages follow.
    func update(_ it: BoardItem) {
        item = it
        layOut()
        dropCloseUps()
        scheduleCloseUps()
    }

    func setDim(_ on: Bool) {
        dim = on
        // a shade over the page rather than see-through views: a see-through view with views inside is drawn off screen first,
        // which at deep zoom is a huge extra picture
        for v in views { v.shade.alpha = on ? 0.15 : 0 }
    }

    /// Puts the page pieces in `container` (canvas units: board + offset).
    func place(in container: UIView, offset: CGPoint) {
        if views.count != segments.count { dropCloseUps() }
        while views.count < segments.count {
            let f = UIView()
            f.isUserInteractionEnabled = false
            f.layer.shadowColor = UIColor.black.cgColor
            f.layer.shadowOpacity = 0.12
            f.layer.shadowRadius = 5
            f.layer.shadowOffset = CGSize(width: 0, height: 2)
            let clip = UIView()
            clip.clipsToBounds = true
            clip.backgroundColor = .white
            let v = UIImageView()
            v.contentMode = .scaleToFill
            clip.addSubview(v)
            let shade = UIView()
            shade.backgroundColor = .black
            shade.alpha = dim ? 0.15 : 0
            shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            clip.addSubview(shade)
            f.addSubview(clip)
            container.addSubview(f)
            views.append((f, clip, v, shade))
        }
        while views.count > segments.count { views.removeLast().outer.removeFromSuperview() }
        for (i, s) in segments.enumerated() {
            let r = PdfPrintout.rect(s).offsetBy(dx: offset.x, dy: offset.y)
            let v = views[i]
            if v.outer.frame != r {
                v.outer.frame = r
                v.clip.frame = CGRect(origin: .zero, size: r.size)
                v.shade.frame = v.clip.bounds
                v.outer.layer.shadowPath = UIBezierPath(rect: CGRect(origin: .zero, size: r.size)).cgPath
            }
            let ph = pageHeight(s)
            v.image.frame = CGRect(x: 0, y: -CGFloat(s.top) * ph, width: r.width, height: ph)
            if v.image.image !== images[s.page] { v.image.image = images[s.page] }
        }
    }

    func remove() {
        closeUpWork?.cancel()
        dropCloseUps()
        views.forEach { $0.outer.removeFromSuperview() }
        views = []
        images = Array(repeating: nil, count: doc.pageCount)
        rendered = Array(repeating: 0, count: doc.pageCount)
        generation = generation.map { $0 + 1 }
        pending = []
    }

    private func show(_ page: Int, _ image: UIImage?) {
        images[page] = image
        for (i, s) in segments.enumerated() where s.page == page && i < views.count { views[i].image.image = image }
    }

    /// Lets page `i`'s picture go (a draw under way for it is dropped when it lands).
    private func free(_ i: Int) {
        generation[i] += 1
        pending.remove(i)
        rendered[i] = 0
        show(i, nil)
    }

    /// Draws the pages near `visible` (board units) sharp enough for `zoom`, frees the far ones; returns the first page on screen (0 = none).
    @discardableResult
    func refresh(visible: CGRect, zoom: CGFloat, screenScale: CGFloat) -> Int {
        last = (visible, zoom, screenScale)
        let near = visible.insetBy(dx: 0, dy: -visible.height)
        let keep = visible.insetBy(dx: 0, dy: -visible.height * 3)
        var first = 0
        for (i, f) in frames.enumerated() where i < rendered.count {
            if first == 0, f.intersects(visible) { first = i + 1 }
            if f.intersects(near) {
                if pending.contains(i) { continue }
                if let t = failedAt[i], Date().timeIntervalSince(t) < 1 { continue }
                let want = pageScale(i, zoom: zoom, screenScale: screenScale)
                if PdfSharpness.needsRedraw(have: Double(rendered[i]), want: Double(want)) { render(i, scale: want) }
            } else if !f.intersects(keep), rendered[i] > 0 || pending.contains(i) {
                free(i)
            }
        }
        scheduleCloseUps()
        return first
    }

    /// The pixels per board unit page `i`'s whole picture should have at `zoom`.
    private func pageScale(_ i: Int, zoom: CGFloat, screenScale: CGFloat) -> CGFloat {
        let b = boardSize(i)
        return CGFloat(PdfSharpness.pageScale(zoom: Double(zoom), screenScale: Double(screenScale), w: Double(b.width), h: Double(b.height)))
    }

    private func render(_ i: Int, scale: CGFloat) {
        pending.insert(i)
        let frame = boardSize(i), size = pageSize(i)
        let target = CGSize(width: max(1, (frame.width * scale).rounded()), height: max(1, (frame.height * scale).rounded()))
        let gen = generation[i], doc = self.doc
        PdfPrintout.queue.async { [weak self] in
            let image = PdfPrintout.draw(doc, page: i, pageSize: size, target: target, pageRect: CGRect(origin: .zero, size: target))
            DispatchQueue.main.async {
                guard let self, i < self.generation.count, self.generation[i] == gen else { return }
                self.pending.remove(i)
                guard let image else { return self.failed(i) }
                self.failedAt[i] = nil
                // what was actually drawn counts, so the page is only drawn again when the zoom changes enough
                self.rendered[i] = target.width / max(frame.width, 1)
                self.show(i, image)
            }
        }
    }

    /// A draw came back empty (the iPad was short of memory): the old picture stays, and it is tried again in a second.
    private func failed(_ i: Int) {
        failedAt[i] = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, let last = self.last else { return }
            self.refresh(visible: last.visible, zoom: last.zoom, screenScale: last.screenScale)
        }
    }

    /// Draws a page so that the whole page lands on `pageRect` (pixels) of a `target`-sized picture (only the part inside is kept);
    /// nil when there wasn't memory for it.
    private static func draw(_ doc: PDFDocument, page i: Int, pageSize: CGSize, target: CGSize, pageRect: CGRect) -> UIImage? {
        autoreleasepool { () -> UIImage? in
            guard let page = doc.page(at: i) else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: target))
                let cg = ctx.cgContext
                cg.translateBy(x: pageRect.minX, y: pageRect.maxY)
                cg.scaleBy(x: pageRect.width / pageSize.width, y: -pageRect.height / pageSize.height)
                page.draw(with: .mediaBox, to: cg)
            }
            guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
            return image
        }
    }

    // MARK: close-ups at deep zoom

    /// Once the board has stopped moving for a moment, draws close-ups of the pieces in view (or lets them go when not needed).
    private func scheduleCloseUps() {
        closeUpWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.drawCloseUps() }
        closeUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func drawCloseUps() {
        guard let last else { return }
        let visible = last.visible
        closeUpGen += 1
        let gen = closeUpGen
        var wanted = Set<Int>()
        for (si, s) in segments.enumerated() where si < views.count && s.page < sizes.count {
            let r = PdfPrintout.rect(s)
            guard r.intersects(visible) else { continue }
            let pageHave = max(rendered[s.page], pageScale(s.page, zoom: last.zoom, screenScale: last.screenScale))
            guard let c = PdfSharpness.closeUp(segment: (Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)),
                                               visible: (Double(visible.minX), Double(visible.minY), Double(visible.width), Double(visible.height)),
                                               zoom: Double(last.zoom), screenScale: Double(last.screenScale), pageHave: Double(pageHave)) else { continue }
            wanted.insert(si)
            let rect = CGRect(x: c.rect.x, y: c.rect.y, width: c.rect.w, height: c.rect.h)
            let scale = CGFloat(c.scale)
            // the one on show still covers what's in view, sharply enough
            if let have = closeUps[si], have.rect.contains(r.intersection(visible)), have.scale >= scale * 0.85 { continue }
            drawCloseUp(si, s, rect: rect, scale: scale, gen: gen)
        }
        for si in Array(closeUps.keys) where !wanted.contains(si) {
            closeUps[si]?.view.removeFromSuperview()
            closeUps[si] = nil
        }
    }

    private func drawCloseUp(_ si: Int, _ s: BoardFiles.PdfSegment, rect: CGRect, scale: CGFloat, gen: Int) {
        let target = CGSize(width: max(1, (rect.width * scale).rounded()), height: max(1, (rect.height * scale).rounded()))
        let kx = target.width / rect.width, ky = target.height / rect.height
        let ph = pageHeight(s)
        let page = CGRect(x: CGFloat(s.x), y: CGFloat(s.y) - CGFloat(s.top) * ph, width: CGFloat(s.w), height: ph) // the whole page on the board
        let pageRect = CGRect(x: (page.minX - rect.minX) * kx, y: (page.minY - rect.minY) * ky, width: page.width * kx, height: page.height * ky)
        let size = pageSize(s.page), doc = self.doc
        PdfPrintout.queue.async { [weak self] in
            let image = PdfPrintout.draw(doc, page: s.page, pageSize: size, target: target, pageRect: pageRect)
            DispatchQueue.main.async {
                guard let self, self.closeUpGen == gen, si < self.views.count, si < self.segments.count, self.segments[si] == s, let image else { return }
                let v: UIImageView
                if let have = self.closeUps[si] { v = have.view } else {
                    v = UIImageView()
                    v.contentMode = .scaleToFill
                    let clip = self.views[si].clip
                    clip.insertSubview(v, belowSubview: self.views[si].shade)
                }
                v.image = image
                v.frame = rect.offsetBy(dx: -CGFloat(s.x), dy: -CGFloat(s.y)) // the clip's own units: the piece's top left is 0, 0
                self.closeUps[si] = (v, rect, scale)
            }
        }
    }

    private func dropCloseUps() {
        closeUpGen += 1
        for c in closeUps.values { c.view.removeFromSuperview() }
        closeUps = [:]
    }

    /// The iPad is short of memory: keep only what's on screen.
    private func lowMemory() {
        dropCloseUps()
        guard let last else { return }
        for (i, f) in frames.enumerated() where i < rendered.count && !f.intersects(last.visible) && (rendered[i] > 0 || pending.contains(i)) { free(i) }
        scheduleCloseUps()
    }

    /// The PDF's own chapter list.
    func outline() -> [OutlineItem] {
        guard let root = doc.outlineRoot else { return [] }
        var out: [OutlineItem] = []
        func walk(_ node: PDFOutline, _ depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                let page = child.destination?.page ?? (child.action as? PDFActionGoTo)?.destination.page
                if let page { out.append(OutlineItem(title: child.label ?? "Untitled", page: doc.index(for: page), depth: depth)) }
                if depth < 4 { walk(child, depth + 1) }
            }
        }
        walk(root, 0)
        return out
    }
}
