import UIKit
import PencilKit
import PDFKit
import NexusCore

/// One board of the data folder, in the laptop's format (NexusCore Board.swift): a PencilKit canvas on top for the ink, and under it
/// the board's items, back to front: PDF printouts, images, shapes, typed text. Both layers follow the canvas's scroll and zoom.
///
/// Canvas units are board units plus `offset`: a scroll view can't go below 0, so the canvas keeps room left of and above the
/// content, and grows that room (moving everything, so nothing moves on screen) when you write near the edge.
/// Saving writes only the tiles that changed, 600 ms after an edit and on leaving; another device's write is read in when there
/// is nothing unsaved here.
final class BoardController: UIViewController, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    let root: URL
    let path: String
    var focus: CGRect?
    var onClose: (() -> Void)?
    /// After a save: the board's path (sync and the handwriting index pick it up).
    var onSaved: ((String) -> Void)?

    var boardURL: URL { root.appendingPathComponent(path, isDirectory: true) }
    var boardName: String { String((path as NSString).lastPathComponent.dropLast(6)) }

    // the board
    var content = BoardContent()
    let ledger = InkLedger()
    var dirty = false
    var loadProblem: String?
    var stamps: [String: String] = [:]

    // views
    let canvas = PKCanvasView()
    let world = UIView()
    /// Above the ink: revision tape covers what is drawn too. Moves with `world`.
    let overWorld = UIView()
    let pdfLayer = UIView(), imageLayer = UIView(), shapeLayer = UIView(), textLayer = UIView()
    let selection = SelectionView()
    let toolPicker = PKToolPicker()
    let hold = HoldWatcher(target: nil, action: nil)
    var pdfs: [String: PdfPrintout] = [:]
    var itemViews: [String: UIView] = [:]
    var textSizes: [String: CGSize] = [:]
    var selected: String? { didSet { showSelection(); updateBar() } }

    var offset = CGPoint(x: 1200, y: 1200)
    let pad: CGFloat = 1200
    let edge: CGFloat = 300
    var shifting = false
    var didFirstLayout = false
    var currentPage = ""
    var saveWork: DispatchWorkItem?
    var poll: Timer?
    let live = LiveState()
    var strokeCount = 0
    var drag: Drag?
    // typing (BoardController+Writing.swift)
    var writing: WritingSession?
    var pushedBottom: [String: CGFloat] = [:]
    var pushedBy: [String: CGFloat] = [:]
    /// The draft this iPad shows for a block (each device's own view; nil or missing: the current draft).
    var viewingDraft: [String: String] = [:]
    /// The block open in the Writing view (full screen), if any.
    weak var writingFull: WritingSession?
    /// Where each comment's bubble is drawn (board units), for taps and selection.
    var markBoxes: [String: CGRect] = [:]
    /// The user's tasks, for "Add a Nexus task" from typed words.
    weak var store: NexusStore?
    /// Revision tape lifted on this iPad (each device's own; the file doesn't keep it).
    var peeking: Set<String> = []

    // hold to make a shape (BoardController+Snap.swift)
    let snapOverlay = UIView(), snapLine = CAShapeLayer(), snapHalo = CAShapeLayer()
    var pendingShape: Shapes.Recognized?
    var awaitingSnap: Int?
    let toastLabel = UILabel()

    // the bar, the paper, dark boards, Insert space (BoardController+Bar, BoardTheme, BoardController+Space)
    let bar = BoardBar()
    let paperView = PaperView()
    let showBarsButton = UIButton(type: .system)
    var themeWatch: (any UITraitChangeRegistration)?
    var colorEdit: (BoardTool, Int)?
    var spaceStart: CGFloat?
    let spaceGuide = UIView(), spaceBand = CAShapeLayer(), spaceLine = CAShapeLayer(), spaceLabel = UILabel()
    var lastZoomLabel = 0
    var lastBarKey = ""
    /// Set when the board sits beside the sidebar: the bar's sidebar button calls it.
    var onSidebar: (() -> Void)?

    init(root: URL, path: String, focus: CGRect?) {
        self.root = root
        self.path = path
        self.focus = focus
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var readOnly: Bool { content.readOnly != nil || loadProblem != nil }

    // MARK: setup

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        edgesForExtendedLayout = []
        view.backgroundColor = PaperView.back(false)
        title = boardName
        paperView.frame = view.bounds
        paperView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(paperView)

        world.layer.anchorPoint = .zero
        world.layer.position = .zero
        for l in [pdfLayer, imageLayer, shapeLayer, textLayer] {
            l.isUserInteractionEnabled = false
            world.addSubview(l)
        }
        world.addSubview(selection)
        selection.isHidden = true
        world.isUserInteractionEnabled = false
        view.addSubview(world)

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .pencilOnly
        canvas.minimumZoomScale = 0.2
        canvas.maximumZoomScale = 5
        canvas.bouncesZoom = false // a bounce moved the canvas without telling us, so the items and PDF slid off the ink
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.alwaysBounceHorizontal = true
        canvas.overrideUserInterfaceStyle = .light
        view.addSubview(canvas)
        overWorld.layer.anchorPoint = .zero
        overWorld.layer.position = .zero
        overWorld.isUserInteractionEnabled = false
        view.insertSubview(overWorld, aboveSubview: canvas)

        load()
        canvas.delegate = self
        setUpGestures()
        setUpSnap()
        setUpSpaceGuide()
        setUpBar()
        applyTool()

        NotificationCenter.default.addObserver(self, selector: #selector(saveNowSelector), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mathDrawn), name: BlockStyler.mathReady, object: nil)
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkOutside() }
        setUpLive()
    }

    deinit { poll?.invalidate() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard view.bounds.width > 0 else { return }
        layOutBar()
        if !didFirstLayout {
            didFirstLayout = true
            updateContentSize()
            if focus != nil || !restorePlace() { showStart() }
        }
        updateContentSize()
        syncWorld()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        watchSystemStyle()
        applyTheme()
        if !readOnly { canvas.becomeFirstResponder() }
        if let p = loadProblem ?? content.readOnly { tell(p) } else { showHintOnce() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if presentedViewController == nil { endWriting() }
        rememberPlace()
        tutorBoardClosing()
        recordingBoardClosing()
        saveNow()
        poll?.invalidate()
    }

    // MARK: reading

    func load() {
        do {
            content = try BoardFiles.load(boardURL)
            loadProblem = nil
        } catch {
            content = BoardContent()
            loadProblem = "\(error)"
        }
        stamps = fileStamps()
        let b = contentBounds(includeInk: false, strokes: content.strokes)
        offset = CGPoint(x: max(pad, pad - (b?.minX ?? 0)), y: max(pad, pad - (b?.minY ?? 0)))
        shifting = true
        canvas.drawing = ledger.drawing(content.strokes, offset: offset)
        strokeCount = canvas.drawing.strokes.count
        shifting = false
        canvas.undoManager?.removeAllActions()
        paperView.paper = paper
        rebuildItems()
        dirty = false
    }

    /// Everything on the board (board units): the ink and the items.
    func contentBounds(includeInk: Bool = true, strokes: [BoardStroke]? = nil) -> CGRect? {
        var r = CGRect.null
        if let strokes {
            for s in strokes { for p in s.points { r = r.union(CGRect(x: p[0], y: p[1], width: 0.1, height: 0.1)) } }
        } else if includeInk, !canvas.drawing.strokes.isEmpty {
            r = canvas.drawing.bounds.offsetBy(dx: -offset.x, dy: -offset.y)
        }
        for it in content.items { r = r.union(box(of: it)) }
        return r.isNull ? nil : r
    }

    func box(of it: BoardItem) -> CGRect {
        if it.type == "pdf", let p = pdfs[it.id] { return p.box }
        if it.type == "mark" { return markBoxes[it.id] ?? CGRect(x: it.x, y: it.y, width: MarkView.size, height: MarkView.size) }
        return boardBox(it, textSize: textSizes[it.id])
    }

    /// Where to look first: the place asked for, the first PDF page, or the top left of what is there.
    func showStart() {
        let W = view.bounds.width, top = topInset, H = view.bounds.height - top
        if let f = focus {
            let z = min(2, max(0.5, min(W / max(f.width + 200, 1), H / max(f.height + 200, 1))))
            canvas.zoomScale = z
            updateContentSize()
            scroll(toBoard: CGPoint(x: f.midX - W / 2 / z, y: f.midY - (H / 2 + top) / z))
        } else if let pdf = content.items.first(where: { $0.type == "pdf" }) {
            let w = pdf.w ?? BoardFormat.pdfWidth
            let z = min(1.5, max(0.3, (W - 80) / (w + 80)))
            canvas.zoomScale = z
            updateContentSize()
            scroll(toBoard: CGPoint(x: pdf.x - 40 / z, y: pdf.y - (24 + top) / z))
        } else if let b = contentBounds() {
            canvas.zoomScale = 1
            updateContentSize()
            scroll(toBoard: CGPoint(x: b.minX - 60, y: b.minY - 60 - top))
        } else {
            canvas.zoomScale = 1
            updateContentSize()
            scroll(toBoard: CGPoint(x: -60, y: -60 - top))
        }
    }

    func scroll(toBoard p: CGPoint) {
        let z = canvas.zoomScale
        canvas.setContentOffset(CGPoint(x: max(0, (p.x + offset.x) * z), y: max(0, (p.y + offset.y) * z)), animated: false)
        syncWorld()
    }

    // MARK: items on screen

    func resolve(_ src: String?) -> URL? { src.flatMap { BoardFiles.resolve($0, board: boardURL, root: root) } }

    /// Brings the item views in line with `content.items` (made, moved, removed).
    func rebuildItems() {
        let ids = Set(content.items.map(\.id))
        for (id, v) in itemViews where !ids.contains(id) { v.removeFromSuperview(); itemViews[id] = nil; textSizes[id] = nil }
        for (id, p) in pdfs where !ids.contains(id) { p.remove(); pdfs[id] = nil }
        for it in content.items.sorted(by: { $0.id < $1.id }) {
            switch it.type {
            case "pdf":
                if let p = pdfs[it.id] {
                    if p.item.src == it.src { p.update(it) } else { p.remove(); pdfs[it.id] = nil }
                }
                if pdfs[it.id] == nil, let url = resolve(it.src), let p = PdfPrintout(item: it, url: url) {
                    p.setDim(paperView.dark)
                    pdfs[it.id] = p
                }
                pdfs[it.id]?.place(in: pdfLayer, offset: offset)
            case "image":
                let v = (itemViews[it.id] as? ImageItemView) ?? ImageItemView(frame: .zero)
                if v.superview == nil { imageLayer.addSubview(v); itemViews[it.id] = v }
                v.update(it, offset: offset, url: resolve(it.src))
            case "shape":
                let v = (itemViews[it.id] as? ShapeItemView) ?? ShapeItemView(frame: .zero)
                if v.superview == nil { shapeLayer.addSubview(v); itemViews[it.id] = v }
                v.update(it, offset: offset)
            case "text":
                let v = (itemViews[it.id] as? TextBlockView) ?? TextBlockView()
                if v.superview == nil { textLayer.addSubview(v); itemViews[it.id] = v }
                let md = content.texts[shownKey(it.id)] ?? ""
                v.update(md: md, item: it)
                v.marked = markedRanges(it.id)
                v.setRenderScale(canvas.zoomScale)
                textSizes[it.id] = v.frame.size
                v.frame.origin = CGPoint(x: it.x + offset.x, y: it.y + offset.y)
            case "mark":
                break // placed below, once the blocks they sit on are laid out
            case "tape":
                let v = (itemViews[it.id] as? TapeView) ?? TapeView(frame: .zero)
                if v.superview == nil { overWorld.addSubview(v); itemViews[it.id] = v }
                v.update(it, offset: offset, peeking: peeking.contains(it.id))
            default:
                let v = (itemViews[it.id] as? ForeignItemView) ?? ForeignItemView(frame: .zero)
                if v.superview == nil { shapeLayer.addSubview(v); itemViews[it.id] = v }
                v.update(it, offset: offset)
            }
        }
        for it in content.items where it.type == "mark" { placeMark(it) }
        showSelection()
        updateContentSize()
        syncWorld()
        updateBar()
    }

    func showSelection() {
        guard let id = selected, let it = content.items.first(where: { $0.id == id }) else {
            selection.isHidden = true
            return
        }
        selection.isHidden = false
        selection.resizable = it.type != "pdf" && !readOnly
        selection.show(box(of: it).offsetBy(dx: offset.x, dy: offset.y), zoom: canvas.zoomScale)
        world.bringSubviewToFront(selection)
    }

    // MARK: scroll, zoom, growing

    func updateContentSize() {
        let z = canvas.zoomScale
        let b = contentBounds() ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let w = max(b.maxX + offset.x + 1400, view.bounds.width / z)
        let h = max(b.maxY + offset.y + 1500, view.bounds.height * 2 / z)
        world.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        overWorld.bounds = world.bounds
        let target = CGSize(width: w * z, height: h * z)
        if abs(canvas.contentSize.width - target.width) > 1 || abs(canvas.contentSize.height - target.height) > 1 {
            canvas.contentSize = target
        }
    }

    /// The part of the board on screen (board units).
    var visibleBoard: CGRect {
        let z = canvas.zoomScale
        return CGRect(x: canvas.contentOffset.x / z - offset.x, y: canvas.contentOffset.y / z - offset.y,
                      width: canvas.bounds.width / z, height: canvas.bounds.height / z)
    }

    func syncWorld() {
        let z = canvas.zoomScale, o = canvas.contentOffset
        world.transform = CGAffineTransform(a: z, b: 0, c: 0, d: z, tx: -o.x, ty: -o.y)
        overWorld.transform = world.transform
        let vis = visibleBoard
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        var page = ""
        for p in pdfs.values.sorted(by: { $0.item.id < $1.item.id }) {
            let first = p.refresh(visible: vis, zoom: z, screenScale: scale)
            if page.isEmpty, first > 0 { page = (pdfs.count > 1 ? p.name + " · " : "") + "p. \(first) of \(p.doc.pageCount)" }
        }
        paperView.show(visible: vis, zoom: z)
        let zl = Int((z * 100).rounded())
        if page != currentPage || zl != lastZoomLabel {
            currentPage = page
            lastZoomLabel = zl
            title = page.isEmpty ? boardName : boardName + " · " + page
            bar.updatePills()
        }
        writing?.place()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { syncWorld() }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { syncWorld(); showSelection() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        updateContentSize()
        syncWorld()
        sharpenText()
        writing?.rescale()
    }

    /// Typed text draws itself: draw it again at the new zoom so it stays sharp.
    func sharpenText() {
        let z = canvas.zoomScale
        for v in itemViews.values { (v as? TextBlockView)?.setRenderScale(z) }
    }

    /// Something near the left or top edge: move everything right or down and scroll by the same amount, so nothing moves on screen.
    func growIfNeeded() {
        guard let b = contentBounds() else { return }
        let dx: CGFloat = b.minX + offset.x < edge ? edge - (b.minX + offset.x) + pad : 0
        let dy: CGFloat = b.minY + offset.y < edge ? edge - (b.minY + offset.y) + pad : 0
        guard dx > 0 || dy > 0 else { return }
        shifting = true
        let z = canvas.zoomScale, o = canvas.contentOffset
        offset = CGPoint(x: offset.x + dx, y: offset.y + dy)
        canvas.drawing = canvas.drawing.transformed(using: CGAffineTransform(translationX: dx, y: dy))
        canvas.undoManager?.removeAllActions()
        rebuildItems()
        updateContentSize()
        canvas.contentOffset = CGPoint(x: o.x + dx * z, y: o.y + dy * z)
        syncWorld()
        shifting = false
    }

    // MARK: ink

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if shifting { return }
        let n = canvas.drawing.strokes.count
        if n == strokeCount + 1 { strokeLanded() }
        strokeCount = canvas.drawing.strokes.count
        recordingDrawingChanged()
        if selected != nil { selected = nil }
        growIfNeeded()
        updateContentSize()
        changed()
    }

    // MARK: saving

    func changed() {
        guard !readOnly else { return }
        dirty = true
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    @objc func saveNowSelector() { saveNow() }

    func saveNow() {
        saveWork?.cancel()
        guard dirty, !readOnly else { return }
        let taken = Set(content.items.map(\.id))
        content.strokes = ledger.strokes(canvas.drawing, offset: offset, taken: taken)
        recordingSaved()
        do {
            // what the laptop wrote since this board was read is merged in first, never written over (BoardController+Live)
            let merged = try reconcileBeforeSave()
            content = merged.content
            let ch = BoardFiles.changes(content)
            var wrote = Set(ch.tiles.keys.map(BoardFormat.tileFile) + ch.texts.keys.map(BoardFormat.textFile) + ch.removedTexts.map(BoardFormat.textFile))
            if content.meta != content.metaOnDisk { wrote.insert("board.json") }
            content = try BoardFiles.save(content, to: boardURL, write: { url, text in try FolderAccess.write(url, text) },
                                          remove: { url in try FileManager.default.removeItem(at: url) })
            dirty = false
            stamps = stampsAfterSave(wrote: wrote)
            afterReconcile(merged)
            onSaved?(path)
        } catch {
            tell("Couldn't save the board: \(error.localizedDescription)")
        }
    }

    /// Size and time of each tile and text file, to notice another writer.
    func fileStamps() -> [String: String] {
        var out: [String: String] = [:]
        let fm = FileManager.default
        for dir in ["tiles", "text"] {
            let url = boardURL.appendingPathComponent(dir)
            let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
            for f in (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? [] {
                let v = try? f.resourceValues(forKeys: Set(keys))
                out[dir + "/" + f.lastPathComponent] = "\(v?.fileSize ?? 0):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            }
        }
        if let v = try? boardURL.appendingPathComponent("board.json").resourceValues(forKeys: [.contentModificationDateKey]) {
            out["board.json"] = "\(v.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        return out
    }

    /// Another device (sync) or app wrote the board: read it again, unless something here isn't saved yet (that wins on the next save).
    func checkOutside() {
        guard !dirty, presentedViewController == nil, !canvas.isTracking else { return }
        let now = fileStamps()
        guard now != stamps else { return }
        if takeOutsideWords(now) { return } // only words changed (the laptop typing): the ink and its undo stay as they are
        guard writing == nil else { return } // a block is open: the whole board is read again once it closes
        let z = canvas.zoomScale
        let look = CGPoint(x: visibleBoard.minX, y: visibleBoard.minY)
        let keep = selected
        load()
        updateContentSize()
        canvas.zoomScale = z
        updateContentSize()
        scroll(toBoard: look)
        if let keep, content.items.contains(where: { $0.id == keep }) { selected = keep } else { selected = nil }
    }

    // MARK: bar

    func updateBar() {
        guard isViewLoaded else { return }
        // rebuilt only when something it shows changed (this runs on every item move)
        let key = "\(selected ?? "")|\(pdfs.count)|\(readOnly)|\(paper.kind.rawValue)\(paper.size)|\(canvas.isRulerActive)"
        guard key != lastBarKey else { return }
        lastBarKey = key
        bar.refresh()
    }

    @objc func close() {
        rememberPlace()
        saveNow()
        onClose?()
    }

    @objc func undo() { canvas.undoManager?.undo() }
    @objc func redo() { canvas.undoManager?.redo() }

    func tell(_ message: String, brief: Bool = false) {
        guard presentedViewController == nil else { return }
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        if brief {
            present(a, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { a.dismiss(animated: true) }
        } else {
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
        }
    }

    // MARK: Contents (the PDF's chapters)

    func showContents(from anchor: UIView) {
        // the printout nearest the middle of the screen
        guard let p = nearestPrintout else { return }
        let items = p.outline().map { BoardViewController.OutlineItem(title: $0.title, page: $0.page, depth: $0.depth) }
        let list = ContentsViewController(items: items, pageCount: p.doc.pageCount)
        list.onPick = { [weak self] page in
            self?.dismiss(animated: true)
            self?.goTo(page: page, in: p)
        }
        list.onAskPage = { [weak self] in
            self?.dismiss(animated: true) { self?.askPage(p) }
        }
        let nav = UINavigationController(rootViewController: list)
        nav.modalPresentationStyle = .popover
        nav.popoverPresentationController?.sourceView = anchor
        nav.popoverPresentationController?.sourceRect = anchor.bounds
        nav.preferredContentSize = CGSize(width: 380, height: 560)
        present(nav, animated: true)
    }

    func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX), dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    func askPage(_ p: PdfPrintout) {
        let alert = UIAlertController(title: "Go to page", message: "1 to \(p.doc.pageCount)", preferredStyle: .alert)
        alert.addTextField { $0.keyboardType = .numberPad }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self, weak alert] _ in
            if let n = Int(alert?.textFields?.first?.text ?? "") { self?.goTo(page: n - 1, in: p) }
        })
        present(alert, animated: true)
    }

    func goTo(page i: Int, in p: PdfPrintout) {
        guard !p.frames.isEmpty else { return }
        let f = p.frames[min(max(i, 0), p.frames.count - 1)]
        let z = canvas.zoomScale
        scroll(toBoard: CGPoint(x: f.midX - canvas.bounds.width / 2 / z, y: f.minY - (20 + topInset) / z))
    }
}
