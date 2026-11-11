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
final class PdfPrintout {
    struct OutlineItem { let title: String; let page: Int; let depth: Int }

    private(set) var item: BoardItem
    let doc: PDFDocument
    let name: String
    /// Each page's whole extent on the board (a page opened in two spans both parts and the room between).
    private(set) var frames: [CGRect] = []
    private(set) var segments: [BoardFiles.PdfSegment] = []
    private var sizes: [(w: Double, h: Double)] = []
    private var views: [(outer: UIView, clip: UIView, image: UIImageView)] = []
    private var images: [UIImage?] = []
    private var rendered: [CGFloat] = []
    private var pending = Set<Int>()
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
        layOut()
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

    /// Moved, resized or opened up: the pages follow.
    func update(_ it: BoardItem) {
        item = it
        layOut()
    }

    func setDim(_ on: Bool) {
        dim = on
        for v in views { v.outer.alpha = on ? 0.85 : 1 }
    }

    /// Puts the page pieces in `container` (canvas units: board + offset).
    func place(in container: UIView, offset: CGPoint) {
        while views.count < segments.count {
            let f = UIView()
            f.isUserInteractionEnabled = false
            f.layer.shadowColor = UIColor.black.cgColor
            f.layer.shadowOpacity = 0.12
            f.layer.shadowRadius = 5
            f.layer.shadowOffset = CGSize(width: 0, height: 2)
            f.alpha = dim ? 0.85 : 1
            let clip = UIView()
            clip.clipsToBounds = true
            clip.backgroundColor = .white
            let v = UIImageView()
            v.contentMode = .scaleToFill
            clip.addSubview(v)
            f.addSubview(clip)
            container.addSubview(f)
            views.append((f, clip, v))
        }
        while views.count > segments.count { views.removeLast().outer.removeFromSuperview() }
        for (i, s) in segments.enumerated() {
            let r = PdfPrintout.rect(s).offsetBy(dx: offset.x, dy: offset.y)
            let v = views[i]
            if v.outer.frame != r {
                v.outer.frame = r
                v.clip.frame = CGRect(origin: .zero, size: r.size)
                v.outer.layer.shadowPath = UIBezierPath(rect: CGRect(origin: .zero, size: r.size)).cgPath
            }
            let ph = pageHeight(s)
            v.image.frame = CGRect(x: 0, y: -CGFloat(s.top) * ph, width: r.width, height: ph)
            if v.image.image !== images[s.page] { v.image.image = images[s.page] }
        }
    }

    func remove() {
        views.forEach { $0.outer.removeFromSuperview() }
        views = []
        images = Array(repeating: nil, count: doc.pageCount)
        rendered = Array(repeating: 0, count: doc.pageCount)
    }

    private func show(_ page: Int, _ image: UIImage?) {
        images[page] = image
        for (i, s) in segments.enumerated() where s.page == page && i < views.count { views[i].image.image = image }
    }

    /// Draws the pages near `visible` (board units) sharp enough for `zoom`, frees the far ones; returns the first page on screen (0 = none).
    @discardableResult
    func refresh(visible: CGRect, zoom: CGFloat, screenScale: CGFloat) -> Int {
        let near = visible.insetBy(dx: 0, dy: -visible.height)
        let keep = visible.insetBy(dx: 0, dy: -visible.height * 3)
        let want = min(max(zoom, 1), 3) * screenScale
        var first = 0
        for (i, f) in frames.enumerated() where i < rendered.count {
            if first == 0, f.intersects(visible) { first = i + 1 }
            if f.intersects(near) {
                if rendered[i] < want * 0.75 { render(i, scale: want) }
            } else if !f.intersects(keep), rendered[i] > 0 {
                show(i, nil)
                rendered[i] = 0
            }
        }
        return first
    }

    private func render(_ i: Int, scale: CGFloat) {
        if pending.contains(i) { return }
        pending.insert(i)
        let w = CGFloat(item.w ?? BoardFormat.pdfWidth)
        let pageSize = PdfPrintout.displaySize(doc.page(at: i))
        let frame = CGSize(width: w, height: w * pageSize.height / max(1, pageSize.width))
        var target = CGSize(width: frame.width * scale, height: frame.height * scale)
        let cap: CGFloat = 16_000_000
        if target.width * target.height > cap {
            let s = (cap / (target.width * target.height)).squareRoot()
            target = CGSize(width: target.width * s, height: target.height * s)
        }
        target = CGSize(width: max(1, target.width.rounded()), height: max(1, target.height.rounded()))
        rendered[i] = target.width / max(frame.width, 1)
        let doc = self.doc
        PdfPrintout.queue.async { [weak self] in
            var image: UIImage?
            if let page = doc.page(at: i) {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                image = UIGraphicsImageRenderer(size: target, format: format).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: target))
                    let cg = ctx.cgContext
                    cg.translateBy(x: 0, y: target.height)
                    cg.scaleBy(x: target.width / pageSize.width, y: -target.height / pageSize.height)
                    page.draw(with: .mediaBox, to: cg)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.pending.remove(i)
                if i < self.rendered.count, self.rendered[i] > 0 { self.show(i, image) }
            }
        }
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
