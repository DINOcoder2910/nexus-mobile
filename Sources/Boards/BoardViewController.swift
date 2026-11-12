import UIKit
import PencilKit
import PDFKit

/// One board: a PencilKit canvas that grows as you write, over a layer of PDF pages.
/// The canvas is transparent; the page layer behind it follows the canvas's scroll and zoom.
/// Only pages within a screen of the view are drawn, and pages far away are freed, so long PDFs stay light.
final class BoardViewController: UIViewController, PKCanvasViewDelegate {
    struct OutlineItem { let title: String; let page: Int; let depth: Int }

    let board: BoardInfo
    var onClose: (() -> Void)?

    private let canvas = PKCanvasView()
    private let pageLayer = UIView()
    private let toolPicker = PKToolPicker()
    private var pdf: PDFDocument?
    private var pageFrames: [CGRect] = []
    private var pageViews: [UIImageView] = []
    private var renderedScale: [CGFloat] = []
    private var pending = Set<Int>()
    private let renderQueue = DispatchQueue(label: "app.nexus.pdf-render", qos: .userInitiated)
    private var saveWork: DispatchWorkItem?
    private var didInitialZoom = false
    private var currentPage = 0

    private let pageWidth: CGFloat = 820
    private let margin: CGFloat = 60
    private let pageGap: CGFloat = 24
    /// Room left of and above the content. A scroll view can't go below 0, so the board grows left and up
    /// by shifting everything right or down when ink comes within `edge` of the start.
    private let pad: CGFloat = 1200
    private let edge: CGFloat = 300
    private var pageOrigin = CGPoint.zero
    private var shifting = false

    init(board: BoardInfo) {
        self.board = board
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Setup

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        edgesForExtendedLayout = []
        view.backgroundColor = UIColor(white: 0.95, alpha: 1)
        title = board.name

        pageLayer.layer.anchorPoint = .zero
        pageLayer.layer.position = .zero
        view.addSubview(pageLayer)

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = Device.isPhone ? .anyInput : .pencilOnly
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 4
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = true
        canvas.overrideUserInterfaceStyle = .light
        canvas.drawing = BoardStore.loadDrawing(board.id)
        canvas.delegate = self
        view.addSubview(canvas)

        loadPDF()
        setUpBar()

        // The board is always light. Without this the picker follows the iPad's dark mode, and PencilKit
        // flips its black and white when they land on the light canvas.
        toolPicker.colorUserInterfaceStyle = .light
        toolPicker.overrideUserInterfaceStyle = .light
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0 else { return }
        if !didInitialZoom {
            didInitialZoom = true
            if pdf != nil { canvas.zoomScale = min(2, view.bounds.width / (pageWidth + 2 * margin)) }
            updateContentSize()
            if pdf != nil { goToPage(0) }
        }
        updateContentSize()
        syncPageLayer()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvas.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveNow()
    }

    private func setUpBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", style: .done, target: self, action: #selector(close))
        var items: [UIBarButtonItem] = [
            UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.forward"), style: .plain, target: self, action: #selector(redo)),
            UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), style: .plain, target: self, action: #selector(undo)),
            UIBarButtonItem(image: UIImage(systemName: "pencil.tip"), style: .plain, target: self, action: #selector(togglePolicy)),
        ]
        if pdf != nil {
            items.append(UIBarButtonItem(image: UIImage(systemName: "list.bullet"), style: .plain, target: self, action: #selector(showContents(_:))))
        }
        navigationItem.rightBarButtonItems = items
    }

    // MARK: PDF pages

    private func loadPDF() {
        guard let name = board.pdfName,
              let doc = PDFDocument(url: BoardStore.folder(board.id).appendingPathComponent(name)) else { return }
        pdf = doc
        if let saved = BoardStore.origin(board.id) {
            pageOrigin = saved
        } else {
            // Boards made before the left gutter had pages at (margin, margin): move their ink with the pages once.
            pageOrigin = CGPoint(x: pad, y: margin)
            if !canvas.drawing.strokes.isEmpty {
                canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(translationX: pad - margin, y: 0))
                BoardStore.save(canvas.drawing, id: board.id)
            }
            BoardStore.setOrigin(pageOrigin, id: board.id)
        }
        var y = pageOrigin.y
        for i in 0..<doc.pageCount {
            let size = displaySize(doc.page(at: i))
            let frame = CGRect(x: pageOrigin.x, y: y, width: pageWidth, height: pageWidth * size.height / max(size.width, 1))
            let v = UIImageView(frame: frame)
            v.backgroundColor = .white
            v.contentMode = .scaleToFill
            v.layer.shadowColor = UIColor.black.cgColor
            v.layer.shadowOpacity = 0.12
            v.layer.shadowRadius = 5
            v.layer.shadowOffset = CGSize(width: 0, height: 2)
            v.layer.shadowPath = UIBezierPath(rect: CGRect(origin: .zero, size: frame.size)).cgPath
            pageLayer.addSubview(v)
            pageFrames.append(frame)
            pageViews.append(v)
            renderedScale.append(0)
            y = frame.maxY + pageGap
        }
    }

    private func displaySize(_ page: PDFPage?) -> CGSize {
        guard let page else { return CGSize(width: 612, height: 792) }
        let box = page.bounds(for: .mediaBox)
        return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }

    private func updateVisiblePages() {
        guard let doc = pdf, !pageFrames.isEmpty else { return }
        let z = canvas.zoomScale
        let visible = CGRect(x: canvas.contentOffset.x / z, y: canvas.contentOffset.y / z,
                             width: canvas.bounds.width / z, height: canvas.bounds.height / z)
        let near = visible.insetBy(dx: 0, dy: -visible.height)
        let keep = visible.insetBy(dx: 0, dy: -visible.height * 3)
        let screenScale = view.window?.screen.scale ?? 2
        let want = min(max(z, 1), 3) * screenScale
        var first = 0
        for (i, f) in pageFrames.enumerated() {
            if first == 0, f.intersects(visible) { first = i + 1 }
            if f.intersects(near) {
                if renderedScale[i] < want * 0.75 { render(i, scale: want, doc: doc) }
            } else if !f.intersects(keep), renderedScale[i] > 0 {
                pageViews[i].image = nil
                renderedScale[i] = 0
            }
        }
        if first != currentPage {
            currentPage = first
            title = first > 0 ? "\(board.name) · p. \(first) of \(doc.pageCount)" : board.name
        }
    }

    private func render(_ i: Int, scale: CGFloat, doc: PDFDocument) {
        if pending.contains(i) { return }
        pending.insert(i)
        let frame = pageFrames[i]
        var target = CGSize(width: frame.width * scale, height: frame.height * scale)
        let cap: CGFloat = 16_000_000
        if target.width * target.height > cap {
            let s = (cap / (target.width * target.height)).squareRoot()
            target = CGSize(width: target.width * s, height: target.height * s)
        }
        target = CGSize(width: target.width.rounded(), height: target.height.rounded())
        renderedScale[i] = target.width / frame.width
        let pageSize = displaySize(doc.page(at: i))
        renderQueue.async { [weak self] in
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
                if self.renderedScale[i] > 0 { self.pageViews[i].image = image }
            }
        }
    }

    // MARK: Canvas, scroll and zoom

    private func updateContentSize() {
        let hasInk = !canvas.drawing.strokes.isEmpty
        let ink = canvas.drawing.bounds
        let pdfBottom = pageFrames.last?.maxY ?? 0
        let pdfRight = pageFrames.last?.maxX ?? 0
        let w = max(pdfRight + 1400, hasInk ? ink.maxX + 1200 : 0, view.bounds.width / canvas.zoomScale)
        let h = max(pdfBottom + 1200, hasInk ? ink.maxY + 1500 : 0, view.bounds.height * 2 / canvas.zoomScale)
        pageLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        let target = CGSize(width: w * canvas.zoomScale, height: h * canvas.zoomScale)
        if abs(canvas.contentSize.width - target.width) > 1 || abs(canvas.contentSize.height - target.height) > 1 {
            canvas.contentSize = target
        }
    }

    private func syncPageLayer() {
        let z = canvas.zoomScale, o = canvas.contentOffset
        pageLayer.transform = CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: -o.x, ty: -o.y)
        updateVisiblePages()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { syncPageLayer() }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { syncPageLayer() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateContentSize()
        syncPageLayer()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if shifting { return }
        growLeftAndUpIfNeeded()
        updateContentSize()
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Ink near the left or top edge: move everything right or down by `pad` and scroll by the same amount,
    /// so nothing moves on screen but there's room to keep going.
    private func growLeftAndUpIfNeeded() {
        guard !canvas.drawing.strokes.isEmpty else { return }
        let ink = canvas.drawing.bounds
        let dx: CGFloat = ink.minX < edge ? pad : 0
        let dy: CGFloat = ink.minY < edge ? pad : 0
        guard dx > 0 || dy > 0 else { return }
        shifting = true
        let z = canvas.zoomScale, o = canvas.contentOffset
        canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(translationX: dx, y: dy))
        canvas.undoManager?.removeAllActions()
        for i in pageFrames.indices {
            pageFrames[i] = pageFrames[i].offsetBy(dx: dx, dy: dy)
            pageViews[i].frame = pageFrames[i]
        }
        if pdf != nil {
            pageOrigin = CGPoint(x: pageOrigin.x + dx, y: pageOrigin.y + dy)
            BoardStore.setOrigin(pageOrigin, id: board.id)
        }
        updateContentSize()
        canvas.contentOffset = CGPoint(x: o.x + dx * z, y: o.y + dy * z)
        syncPageLayer()
        shifting = false
    }

    private func saveNow() {
        let drawing = canvas.drawing, id = board.id
        DispatchQueue.global(qos: .utility).async { BoardStore.save(drawing, id: id) }
    }

    // MARK: Bar actions

    @objc private func close() {
        saveNow()
        onClose?()
    }

    @objc private func undo() { canvas.undoManager?.undo() }
    @objc private func redo() { canvas.undoManager?.redo() }

    @objc private func togglePolicy(_ sender: UIBarButtonItem) {
        let pencilOnly = canvas.drawingPolicy == .pencilOnly
        canvas.drawingPolicy = pencilOnly ? .anyInput : .pencilOnly
        sender.image = UIImage(systemName: pencilOnly ? "hand.draw" : "pencil.tip")
        let note = UIAlertController(title: nil, message: pencilOnly ? "Fingers draw too" : "Pencil only: fingers scroll", preferredStyle: .alert)
        present(note, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { note.dismiss(animated: true) }
    }

    @objc private func showContents(_ sender: UIBarButtonItem) {
        guard let doc = pdf else { return }
        let list = ContentsViewController(items: outline(), pageCount: doc.pageCount)
        list.onPick = { [weak self] page in
            self?.dismiss(animated: true)
            self?.goToPage(page)
        }
        list.onAskPage = { [weak self] in
            self?.dismiss(animated: true) { self?.askPage() }
        }
        let nav = UINavigationController(rootViewController: list)
        nav.modalPresentationStyle = .popover
        nav.popoverPresentationController?.barButtonItem = sender
        nav.preferredContentSize = CGSize(width: 380, height: 560)
        present(nav, animated: true)
    }

    private func askPage() {
        guard let doc = pdf else { return }
        let alert = UIAlertController(title: "Go to page", message: "1 to \(doc.pageCount)", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            if let n = Int(alert?.textFields?.first?.text ?? "") { self?.goToPage(n - 1) }
        })
        present(alert, animated: true)
    }

    private func goToPage(_ i: Int) {
        guard !pageFrames.isEmpty else { return }
        let f = pageFrames[min(max(i, 0), pageFrames.count - 1)]
        let z = canvas.zoomScale
        let x = max(0, f.midX * z - canvas.bounds.width / 2)
        canvas.setContentOffset(CGPoint(x: x, y: max(0, (f.minY - 20) * z)), animated: false)
        syncPageLayer()
    }

    private func outline() -> [OutlineItem] {
        guard let doc = pdf, let root = doc.outlineRoot else { return [] }
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

/// The PDF's chapters (its own outline) plus "Go to page".
final class ContentsViewController: UITableViewController {
    private let items: [BoardViewController.OutlineItem]
    private let pageCount: Int
    var onPick: ((Int) -> Void)?
    var onAskPage: (() -> Void)?

    init(items: [BoardViewController.OutlineItem], pageCount: Int) {
        self.items = items
        self.pageCount = pageCount
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Contents"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : max(items.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            config.text = "Go to page…"
            config.secondaryText = "1 to \(pageCount)"
        } else if items.isEmpty {
            config.text = "This PDF has no chapter list"
            config.textProperties.color = .secondaryLabel
        } else {
            let item = items[indexPath.row]
            config.text = String(repeating: "    ", count: item.depth) + item.title
            config.secondaryText = "p. \(item.page + 1)"
        }
        cell.contentConfiguration = config
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 { onAskPage?() }
        else if !items.isEmpty { onPick?(items[indexPath.row].page) }
    }
}
