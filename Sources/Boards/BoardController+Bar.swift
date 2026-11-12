import UIKit
import PencilKit
import NexusCore

/// The board's own bar (BoardBar) in place of the navigation bar and PencilKit's tool picker, and what its buttons do: picking a
/// tool, colours and widths, the background, dark boards, the zoom and page pills, the ruler, hiding the bars, the Pencil's
/// double-tap, the Text tool's tap, and coming back to where you left off.
extension BoardController: UIPencilInteractionDelegate, UIColorPickerViewControllerDelegate {
    // MARK: setting up

    func setUpBar() {
        bar.board = self
        bar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: BoardBar.height)
        bar.autoresizingMask = [.flexibleWidth]
        view.addSubview(bar)

        var c = UIButton.Configuration.filled()
        c.image = UIImage(systemName: "chevron.down")
        c.cornerStyle = .capsule
        c.baseBackgroundColor = .secondarySystemBackground
        c.baseForegroundColor = .label
        showBarsButton.configuration = c
        showBarsButton.addAction(UIAction { [weak self] _ in self?.setBarsHidden(false) }, for: .primaryActionTriggered)
        showBarsButton.accessibilityLabel = "Show the bars"
        showBarsButton.isHidden = true
        view.addSubview(showBarsButton)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        view.addInteraction(pencil)

        let textTap = UITapGestureRecognizer(target: self, action: #selector(textTapped(_:)))
        textTap.name = "textTap"
        textTap.allowedTouchTypes = BoardController.anyTouch
        textTap.delegate = self
        canvas.addGestureRecognizer(textTap)

        let space = UIPanGestureRecognizer(target: self, action: #selector(spacePanned(_:)))
        space.name = "spacePan"
        space.allowedTouchTypes = BoardController.anyTouch
        space.maximumNumberOfTouches = 1
        space.delegate = self
        canvas.addGestureRecognizer(space)
        canvas.panGestureRecognizer.require(toFail: space)

        let spaceTap = UITapGestureRecognizer(target: self, action: #selector(spaceTapped(_:)))
        spaceTap.name = "spaceTap"
        spaceTap.allowedTouchTypes = BoardController.anyTouch
        spaceTap.delegate = self
        canvas.addGestureRecognizer(spaceTap)

        navigationController?.setNavigationBarHidden(true, animated: false)
        bar.refresh()
    }

    static let anyTouch = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.pencil.rawValue)]

    func layOutBar() {
        let top = view.safeAreaInsets.top
        bar.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: top + BoardBar.height)
        showBarsButton.frame = CGRect(x: view.bounds.width - view.safeAreaInsets.right - 56, y: top + 8, width: 44, height: 32)
        view.bringSubviewToFront(bar)
        view.bringSubviewToFront(showBarsButton)
    }

    /// How much of the top of the screen the bar covers.
    var topInset: CGFloat { bar.isHidden ? view.safeAreaInsets.top : view.safeAreaInsets.top + BoardBar.height }

    /// Which gestures may start for the current tool (nil: the gesture's own rule decides).
    func toolGestureShouldBegin(_ g: UIGestureRecognizer) -> Bool? {
        let t = BoardTools.shared.tool
        switch g.name {
        case "textTap": return t == .text && !readOnly
        case "spacePan": return t == .space && !readOnly
        case "spaceTap": return t == .space && !readOnly && BoardTools.shared.spaceTap != .nothing
        case "tap": return (t == .text || t == .space) && !readOnly ? false : nil
        case "itemPan": return t == .space ? false : nil
        default: return nil
        }
    }

    // MARK: tools

    var selectedItem: BoardItem? { selected.flatMap { id in content.items.first { $0.id == id } } }

    func selectTool(_ t: BoardTool) {
        if writing != nil, t != .text { endWriting() }
        BoardTools.shared.tool = t
        toolChanged()
    }

    /// A tool, colour, width or kind changed in the bar.
    func toolChanged() {
        applyTool()
        bar.refresh()
    }

    /// Puts the current tool on the canvas; tools that don't draw turn the Pencil's drawing off (it scrolls, types or makes space).
    func applyTool() {
        let tools = BoardTools.shared
        canvas.drawingPolicy = Device.isPhone || tools.fingersDraw ? .anyInput : .pencilOnly // an iPhone has no Pencil
        if !readOnly, let pk = tools.pkTool(tools.tool, dark: boardIsDark) {
            canvas.tool = pk
            canvas.drawingGestureRecognizer.isEnabled = true
        } else {
            canvas.drawingGestureRecognizer.isEnabled = false
        }
    }

    /// Touch and hold a colour to change it.
    func editColor(_ t: BoardTool, _ i: Int) {
        colorEdit = (t, i)
        let p = UIColorPickerViewController()
        p.selectedColor = InkConvert.color(BoardTools.shared.colors(t)[i])
        p.supportsAlpha = false
        p.delegate = self
        p.modalPresentationStyle = .popover
        p.popoverPresentationController?.sourceView = bar
        p.popoverPresentationController?.sourceRect = CGRect(x: 40, y: bar.bounds.height - 40, width: 200, height: 40)
        present(p, animated: true)
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        guard let e = colorEdit else { return }
        let (t, i) = e
        let hex = String(InkConvert.hex(color).prefix(7))
        BoardTools.shared.setColor(t, at: i, hex)
        BoardTools.shared.setColorIndex(t, i)
        if !continuously { toolChanged() } else { applyTool() }
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        colorEdit = nil
        toolChanged()
    }

    func toggleRuler() {
        canvas.isRulerActive.toggle()
        bar.refresh()
    }

    // The Pencil's double-tap: the eraser and back, or the last tool, as set in the iPad's Settings.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        let tools = BoardTools.shared
        switch UIPencilInteraction.preferredTapAction {
        case .switchEraser:
            if tools.tool == .eraser {
                selectTool(tools.previousTool == .eraser ? .pen : tools.previousTool)
            } else {
                selectTool(.eraser)
            }
        case .switchPrevious:
            selectTool(tools.previousTool == tools.tool ? .pen : tools.previousTool)
        default:
            break
        }
    }

    // MARK: the Text tool

    /// Tap a block to type in it, or anywhere else to start a new one there.
    @objc func textTapped(_ g: UITapGestureRecognizer) {
        if writing != nil { endWriting(); return }
        let p = boardPoint(g)
        if let it = hitItem(p, pdf: false), it.type == "text" {
            selected = it.id
            beginWriting(it, at: p)
            return
        }
        let it = newTextBlockItem(at: p) // on a PDF page: typed on that page
        let id = it.id
        changeItems("Add text") { c in
            c.items.append(it)
            c.texts[id] = ""
        }
        selected = id
        beginWriting(it)
    }

    // MARK: menus

    /// "Notebook › Section" above the board's name ("notebooks/Chem/R3/Lesson 1.board").
    var placeName: String? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 2 else { return nil }
        return parts[1..<(parts.count - 1)].joined(separator: " › ")
    }

    func titleMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Board info", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.showInfo() },
            UIMenu(title: "Side by side", image: UIImage(systemName: "rectangle.split.2x1"), children: [
                UIDeferredMenuElement.uncached { [weak self] done in done(self?.sideBySideMenu() ?? []) },
            ]),
            UIMenu(options: .displayInline, children: [
                UIAction(title: "All comments", image: UIImage(systemName: "text.bubble")) { [weak self] _ in self?.openComments() },
                UIAction(title: "Lift all revision tape", image: UIImage(systemName: "eye")) { [weak self] _ in self?.peekAll(true) },
                UIAction(title: "Cover all revision tape", image: UIImage(systemName: "eye.slash")) { [weak self] _ in self?.peekAll(false) },
            ]),
        ])
    }

    func backgroundMenu() -> UIMenu {
        let now = paper
        let kinds = Paper.Kind.allCases.map { k in
            UIAction(title: k.rawValue.capitalized, state: now.kind == k ? .on : .off) { [weak self] _ in self?.setPaper(Paper(kind: k)) }
        }
        var children: [UIMenuElement] = [UIMenu(options: .displayInline, children: kinds)]
        let sizes = Paper.sizes(now.kind)
        if sizes.count > 1 {
            let names = ["Normal", "Wide", "Wider"]
            let pick = sizes.enumerated().map { (i, s) in
                UIAction(title: names[min(i, 2)], state: now.size == s ? .on : .off) { [weak self] _ in self?.setPaper(Paper(kind: now.kind, size: s)) }
            }
            children.append(UIMenu(title: "Spacing", options: .displayInline, children: pick))
        }
        return UIMenu(title: "Background", children: children)
    }

    func boardMenu() -> UIMenu {
        let tools = BoardTools.shared
        let dark = BoardTools.Dark.allCases.map { d in
            UIAction(title: d.title, state: tools.dark == d ? .on : .off) { [weak self] _ in
                tools.dark = d
                self?.applyTheme()
                self?.bar.refresh()
            }
        }
        var items: [UIMenuElement] = [
            UIMenu(title: "Dark board", image: UIImage(systemName: "moon"), children: dark),
            UIAction(title: "Fingers draw too", image: UIImage(systemName: "hand.draw"), state: tools.fingersDraw ? .on : .off) { [weak self] _ in
                tools.fingersDraw.toggle()
                self?.toolChanged()
                self?.toast(tools.fingersDraw ? "Fingers draw too" : "Pencil only: fingers scroll and pick things")
            },
        ]
        if !pdfs.isEmpty {
            items.append(UIAction(title: "Contents", image: UIImage(systemName: "list.bullet")) { [weak self] _ in
                guard let self else { return }
                self.showContents(from: self.bar.pagePill)
            })
        }
        if !replay {
            items.append(UIAction(title: "Earlier versions", image: UIImage(systemName: "clock.arrow.circlepath")) { [weak self] _ in self?.openHistory() })
        }
        items.append(UIAction(title: "Hide the bars", image: UIImage(systemName: "rectangle.expand.vertical")) { [weak self] _ in
            self?.setBarsHidden(true)
        })
        items.append(UIAction(title: "Board info", image: UIImage(systemName: "info.circle")) { [weak self] _ in self?.showInfo() })
        return UIMenu(children: items)
    }

    /// Buttons other parts of the app put in the top row, before the board menu.
    func extraBarButtons() -> [UIButton] {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: "square.grid.2x2", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
        let tools = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.toggleToolPanel() })
        tools.tintColor = toolPanel != nil ? .tintColor : .label
        tools.accessibilityLabel = "Tools"
        tools.toolTip = "Tools"
        return [tools] + boardExtraButtons() + linkBarButtons()
    }

    var pageLabel: String { currentPage.isEmpty ? "" : currentPage }

    func pageMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "Contents", image: UIImage(systemName: "list.bullet")) { [weak self] _ in
                guard let self else { return }
                self.showContents(from: self.bar.pagePill)
            },
            UIAction(title: "Go to page…", image: UIImage(systemName: "arrow.right.doc.on.clipboard")) { [weak self] _ in
                guard let self, let p = self.nearestPrintout else { return }
                self.askPage(p)
            },
        ])
    }

    var nearestPrintout: PdfPrintout? {
        let mid = CGPoint(x: visibleBoard.midX, y: visibleBoard.midY)
        return pdfs.values.min(by: { dist($0.box, mid) < dist($1.box, mid) })
    }

    func zoomMenu() -> UIMenu {
        var items: [UIMenuElement] = []
        if let p = nearestPrintout {
            items.append(UIAction(title: "Fit the page width") { [weak self] _ in
                guard let self else { return }
                self.zoom(to: (self.view.bounds.width - 48) / max(1, p.box.width), keepX: p.box.midX)
            })
        }
        for z in [50, 75, 100, 150, 200] {
            items.append(UIAction(title: "\(z)%", state: Int((canvas.zoomScale * 100).rounded()) == z ? .on : .off) { [weak self] _ in
                self?.zoom(to: CGFloat(z) / 100, keepX: nil)
            })
        }
        return UIMenu(children: items)
    }

    /// Zoom keeping the middle of the screen where it is (or a given x in the middle).
    func zoom(to z: CGFloat, keepX: CGFloat?) {
        let z = min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, z))
        let v = visibleBoard
        let mid = CGPoint(x: keepX ?? v.midX, y: v.midY)
        canvas.zoomScale = z
        updateContentSize()
        scroll(toBoard: CGPoint(x: mid.x - canvas.bounds.width / 2 / z, y: mid.y - canvas.bounds.height / 2 / z))
        sharpenText()
        writing?.rescale()
        bar.refresh()
    }

    func setBarsHidden(_ hidden: Bool) {
        UIView.animate(withDuration: 0.2) {
            self.bar.alpha = hidden ? 0 : 1
            self.showBarsButton.alpha = hidden ? 1 : 0
        } completion: { _ in
            self.bar.isHidden = hidden
            self.showBarsButton.isHidden = !hidden
        }
        bar.isHidden = false
        showBarsButton.isHidden = false
    }

    func showInfo() {
        syncStrokes()
        let pages = pdfs.values.reduce(0) { $0 + $1.doc.pageCount }
        var lines = ["\(content.strokes.count) strokes, \(content.items.count) things on the board"]
        if pages > 0 { lines.append("\(pages) PDF pages") }
        lines.append("Background: \(paper.kind.rawValue)")
        lines.append(path)
        tell(lines.joined(separator: "\n"))
    }

    // MARK: where you left off, and the first-time hint

    func rememberPlace() {
        guard didFirstLayout else { return }
        let v = visibleBoard
        UserDefaults.standard.set([Double(v.minX), Double(v.minY), Double(canvas.zoomScale)], forKey: "board.place." + path)
    }

    /// Back where this board was left (true), unless it was never opened here.
    func restorePlace() -> Bool {
        guard let a = UserDefaults.standard.array(forKey: "board.place." + path) as? [Double], a.count == 3, a[2] > 0 else { return false }
        canvas.zoomScale = min(canvas.maximumZoomScale, max(canvas.minimumZoomScale, CGFloat(a[2])))
        updateContentSize()
        scroll(toBoard: CGPoint(x: a[0], y: a[1]))
        return true
    }

    func showHintOnce() {
        let tools = BoardTools.shared
        guard !tools.hintShown, !readOnly else { return }
        tools.hintShown = true
        toast("The Pencil writes, fingers scroll. Pick tools in the bar; double-tap the Pencil for the eraser.")
    }
}
