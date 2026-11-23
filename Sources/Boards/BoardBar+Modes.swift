import UIKit
import PencilKit
import NexusCore

/// What the row under the board's top bar holds (the new look, picked Nov 20 2026: project files new-look/mockups/sketch-draw-row-fold.png).
enum BarMode: Int, CaseIterable {
    case draw, insert, view
    var title: String { self == .draw ? "Draw" : self == .insert ? "Insert" : "View" }
}

/// The new look's board bar on a wide screen:
/// - **open (A)**: the top row has the way back, the board's name, the Draw | Insert | View switch in the middle, the page and
///   zoom pills, undo, redo and the board's buttons; the row under it holds the switch's choice. Draw: the tools, every colour and
///   every size, always in view for one-tap switching, the tool's own options, the picked item's actions, and ︿ to fold.
///   Insert: text, a picture, a PDF printout, a scan, shapes, Insert space, a tool card. View: the background, dark board,
///   fingers, the ruler, the quick ring, contents, hiding the bars.
/// - **folded (B)**: one bar: "Draw ▾" (its menu switches to Insert or View, which opens the bar again), the tools, the first four
///   colours and two sizes, undo, redo, ⋯ and ﹀. The rest of the colours and sizes are a tap on ﹀ away. Swipe the bar up to
///   fold it, down to open it; it stays as you left it (UserDefaults).
extension BoardBar {
    static let foldedKey = "board.barFolded"

    func setUpModes() {
        modePill.onPick = { [weak self] m in self?.setMode(m) }
        let up = UISwipeGestureRecognizer(target: self, action: #selector(swipedUp))
        up.direction = .up
        addGestureRecognizer(up)
        let down = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown))
        down.direction = .down
        addGestureRecognizer(down)
        toolRowHeight.constant = folded ? 0 : BoardBar.rowHeight
    }

    @objc private func swipedUp() { if !compact { setFolded(true) } }
    @objc private func swipedDown() { if !compact { setFolded(false) } }

    /// Picks what the row under the top one holds (and opens the bar if it was folded).
    func setMode(_ m: BarMode) {
        let changed = m != mode
        mode = m
        modePill.set(m, animated: true)
        if folded { setFolded(false); return }
        guard changed else { return }
        // the row's new contents come up into place
        UIView.transition(with: toolRow, duration: 0.18, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.refresh() }
        toolRow.transform = CGAffineTransform(translationX: 0, y: 6)
        UIView.animate(springDuration: 0.42, bounce: 0.25) { self.toolRow.transform = .identity }
    }

    /// Folds the row into the top bar (B) or opens it again (A), with the kit's spring; remembered.
    func setFolded(_ f: Bool) {
        guard f != folded else { return }
        UserDefaults.standard.set(f, forKey: BoardBar.foldedKey)
        if f { mode = .draw; modePill.set(.draw, animated: false) }
        toolRowHeight.constant = f ? 0 : BoardBar.rowHeight
        UIView.transition(with: self, duration: 0.2, options: [.transitionCrossDissolve, .allowUserInteraction]) { self.refresh() }
        guard let host = board?.view else { return }
        host.setNeedsLayout()
        UIView.animate(springDuration: 0.45, bounce: 0.18) { host.layoutIfNeeded() }
    }

    // MARK: building

    func refreshWide(_ b: BoardController) {
        middleRow.isHidden = true
        let readOnly = b.readOnly
        HoldTarget.shared.actions.removeAll()
        clear(topRow)
        clear(toolRow)
        clear(rowStack)
        clear(rightStack)
        clear(toolsStack)
        toolRow.isHidden = folded
        modePill.set(mode, animated: false)

        let lead = UIStackView()
        lead.axis = .horizontal
        lead.spacing = 0
        lead.addArrangedSubview(icon(b.isSidePane ? "xmark" : "chevron.backward", b.isSidePane ? "Close this pane" : "Close the board") { [weak b] in b?.close() })
        if b.onSidebar != nil { lead.addArrangedSubview(icon("sidebar.left", "Sidebar") { [weak b] in b?.onSidebar?() }) }
        topRow.addArrangedSubview(lead)

        let trail = UIStackView()
        trail.axis = .horizontal
        trail.spacing = 0
        if !readOnly {
            trail.addArrangedSubview(icon("arrow.uturn.backward", "Undo") { [weak b] in b?.undo() })
            trail.addArrangedSubview(icon("arrow.uturn.forward", "Redo") { [weak b] in b?.redo() })
        }
        b.extraBarButtons().forEach { trail.addArrangedSubview($0) }
        trail.addArrangedSubview(menuButton("ellipsis.circle", "Board menu", b.boardMenu()))

        if folded {
            // B: one bar
            topRow.addArrangedSubview(modeMenu(b))
            if !readOnly {
                fillTools(b)
                topRow.addArrangedSubview(toolsScroll)
                fillFoldedInks(b)
                topRow.addArrangedSubview(rowScroll)
            } else {
                topRow.addArrangedSubview(label("Read only"))
            }
            topRow.addArrangedSubview(spacer())
            if !readOnly { trail.addArrangedSubview(icon("chevron.down", "Open the bar") { [weak self] in self?.setFolded(false) }) }
            topRow.addArrangedSubview(trail)
            updatePills()
            return
        }

        // A: the top row, with the switch in the middle
        titleButton.configuration = titleConfig(b)
        titleButton.menu = b.titleMenu()
        topRow.addArrangedSubview(titleButton)
        let left = spacer(), right = spacer()
        topRow.addArrangedSubview(left)
        if !readOnly { topRow.addArrangedSubview(modePill) }
        topRow.addArrangedSubview(right)
        let even = left.widthAnchor.constraint(equalTo: right.widthAnchor)
        even.priority = .init(200)
        even.isActive = true
        // the page and zoom pills sit in the top row, so the row under it keeps its room for the tools, colours and sizes
        if !readOnly {
            if !b.pdfs.isEmpty {
                pagePill.menu = b.pageMenu()
                trail.insertArrangedSubview(pagePill, at: 0)
            }
            zoomPill.menu = b.zoomMenu()
            trail.insertArrangedSubview(zoomPill, at: b.pdfs.isEmpty ? 0 : 1)
        }
        topRow.addArrangedSubview(trail)

        // the row under it
        guard !readOnly else {
            toolRow.addArrangedSubview(label("Read only"))
            toolRow.addArrangedSubview(spacer())
            rightStack.addArrangedSubview(zoomPill)
            toolRow.addArrangedSubview(rightStack)
            updatePills()
            return
        }
        switch mode {
        case .draw:
            fillTools(b)
            toolRow.addArrangedSubview(toolsScroll)
            toolRow.addArrangedSubview(divider())
            fillToolRow(b)
            toolRow.addArrangedSubview(rowScroll)
            toolRow.addArrangedSubview(spacer())
            if let it = b.selectedItem {
                if it.type == "text" {
                    rightStack.addArrangedSubview(textButton("Type", "character.cursor.ibeam") { [weak b] in b?.editSelected() })
                }
                if it.type == "tool" { b.toolCardButtons(it).forEach { rightStack.addArrangedSubview($0) } }
                rightStack.addArrangedSubview(textButton("Delete", "trash") { [weak b] in b?.deleteSelected() })
                rightStack.addArrangedSubview(divider())
            }
        case .insert:
            fillInsertRow(b)
            toolRow.addArrangedSubview(rowScroll)
            toolRow.addArrangedSubview(spacer())
        case .view:
            fillViewRow(b)
            toolRow.addArrangedSubview(rowScroll)
            toolRow.addArrangedSubview(spacer())
        }
        rightStack.addArrangedSubview(icon("chevron.up", "Fold the bar") { [weak self] in self?.setFolded(true) })
        toolRow.addArrangedSubview(rightStack)
        updatePills()
    }

    func titleConfig(_ b: BoardController) -> UIButton.Configuration {
        var tc = UIButton.Configuration.plain()
        tc.title = b.boardName
        tc.subtitle = b.placeName
        tc.titleLineBreakMode = .byTruncatingMiddle
        tc.subtitleLineBreakMode = .byTruncatingHead
        tc.titleAlignment = .leading
        tc.baseForegroundColor = Kit.ui.ink
        tc.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var o = a; o.font = UIFont.nx(16, .semibold); return o
        }
        tc.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
            var o = a; o.font = UIFont.nx(12); o.foregroundColor = Kit.ui.muted; return o
        }
        tc.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        return tc
    }

    /// The tools, each ink tool with a line of its colour under it, and Insert space last (Murtaza, Nov 23: it was too far away in
    /// Insert's row alone; Insert keeps it too). What + used to hold is in Insert's row, so Draw's row has room for every colour
    /// and size.
    func fillTools(_ b: BoardController) {
        let tools = BoardTools.shared
        for t in BoardTool.allCases {
            let on = tools.tool == t
            let button = icon(t.symbol, t.title, selected: on) { [weak b] in b?.selectTool(t) }
            button.accessibilityIdentifier = "board-tool-" + t.rawValue
            if t == .pen || t == .pencil || t == .highlighter {
                let u = UIView()
                u.isUserInteractionEnabled = false
                u.backgroundColor = inkShown(tools.color(t))
                u.layer.cornerRadius = 1.5
                u.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(u)
                NSLayoutConstraint.activate([
                    u.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                    u.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -3),
                    u.widthAnchor.constraint(equalToConstant: on ? 16 : 10),
                    u.heightAnchor.constraint(equalToConstant: 3),
                ])
            }
            toolsStack.addArrangedSubview(button)
        }
    }

    /// A stored ink colour as it shows on this board (PencilKit shows black as white on a dark board).
    func inkShown(_ hex: String) -> UIColor {
        let c = InkConvert.color(hex)
        return dark ? PKInkingTool.convertColor(c, from: .light, to: .dark) : c
    }

    /// The folded bar's colours and sizes: the first four colours and two sizes of the tool (the picked one always among them).
    func fillFoldedInks(_ b: BoardController) {
        let tools = BoardTools.shared
        let t = tools.tool
        guard t.inks else { return }
        rowStack.addArrangedSubview(divider())
        let colors = tools.colors(t)
        var shown = Array(colors.indices.prefix(4))
        let ci = tools.colorIndex(t)
        if !shown.contains(ci), !shown.isEmpty { shown[shown.count - 1] = ci }
        for i in shown {
            rowStack.addArrangedSubview(colorDot(colors[i], selected: ci == i, action: { [weak b] in
                tools.setColorIndex(t, i)
                b?.toolChanged()
            }, edit: { [weak b] in b?.editColor(t, i) }))
        }
        rowStack.addArrangedSubview(divider())
        let wi = tools.widthIndex(t)
        var sizes = [1, 3]
        if !sizes.contains(wi) { sizes[1] = wi }
        for i in sizes.sorted() where BoardTools.widths(t).indices.contains(i) {
            rowStack.addArrangedSubview(widthDot(3 + CGFloat(i) * 3, selected: wi == i, name: BoardTools.widthNames[i]) { [weak b] in
                tools.setWidthIndex(t, i)
                b?.toolChanged()
            })
        }
    }

    /// "Draw ▾" on the folded bar: Draw, Insert or View (the last two open the bar), then the board's own title menu.
    func modeMenu(_ b: BoardController) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.title = mode.title
        c.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold))
        c.imagePlacement = .trailing
        c.imagePadding = 4
        c.baseForegroundColor = Kit.ui.ink
        c.background.backgroundColor = Kit.ui.page
        c.background.cornerRadius = 8
        c.background.strokeColor = Kit.ui.line
        c.background.strokeWidth = 1
        c.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in var o = a; o.font = UIFont.nx(14, .semibold); return o }
        let button = UIButton(configuration: c)
        let modes = BarMode.allCases.map { m in
            UIAction(title: m.title, state: m == mode ? .on : .off) { [weak self] _ in self?.setMode(m) }
        }
        button.menu = UIMenu(children: [
            UIMenu(options: .displayInline, children: modes),
            UIMenu(title: b.boardName, options: .displayInline, children: b.titleMenu().children),
        ])
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "Bar: " + mode.title
        button.accessibilityIdentifier = "board-mode-menu"
        return button
    }

    // MARK: Insert and View

    /// A menu item as a button in the row: an action runs, a submenu opens.
    func rowButton(_ e: UIMenuElement) -> UIButton? {
        var c = UIButton.Configuration.plain()
        c.imagePadding = 6
        c.baseForegroundColor = Kit.ui.ink
        c.background.backgroundColor = Kit.ui.hover
        c.background.cornerRadius = Kit.controlRadius
        c.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 12)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in var o = a; o.font = UIFont.nx(14, .medium); return o }
        c.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let a = e as? UIAction {
            c.title = a.title
            c.image = a.image
            // the menu's own action runs as the button's: menus here are built fresh each time, so nothing else holds it
            let b = UIButton(configuration: c, primaryAction: a)
            b.accessibilityLabel = a.title
            if a.state == .on { b.configuration?.background.backgroundColor = Kit.ui.accentWash; b.accessibilityTraits.insert(.selected) }
            return b
        }
        if let m = e as? UIMenu {
            if m.options.contains(.displayInline) { return nil }
            c.title = m.title
            c.image = m.image
            c.indicator = .popup
            let b = UIButton(configuration: c)
            b.menu = m
            b.showsMenuAsPrimaryAction = true
            b.accessibilityLabel = m.title
            return b
        }
        return nil
    }

    func fillInsertRow(_ b: BoardController) {
        for e in b.insertMenu().children { if let x = rowButton(e) { rowStack.addArrangedSubview(x) } }
        rowStack.addArrangedSubview(divider())
        let space = BoardTools.shared.tool == .space
        rowStack.addArrangedSubview(rowButton(UIAction(title: BoardTool.space.title, image: UIImage(systemName: BoardTool.space.symbol), state: space ? .on : .off) { [weak b] _ in
            // its options are in Draw's row
            b?.selectTool(.space)
            b?.bar.setMode(.draw)
        })!)
        rowStack.addArrangedSubview(rowButton(UIAction(title: "Tool card", image: UIImage(systemName: "square.grid.2x2")) { [weak b] _ in b?.toggleToolPanel() })!)
    }

    func fillViewRow(_ b: BoardController) {
        let menu = b.backgroundMenu()
        let kind = b.paper.kind.rawValue.capitalized
        if let bg = rowButton(UIMenu(title: "Background: " + kind, image: UIImage(systemName: "square.grid.3x3"), children: menu.children)) {
            rowStack.addArrangedSubview(bg)
        }
        let tools = BoardTools.shared
        let dark = BoardTools.Dark.allCases.map { d in
            UIAction(title: d.title, state: tools.dark == d ? .on : .off) { [weak b] _ in
                tools.dark = d
                b?.applyTheme()
                b?.bar.refresh()
            }
        }
        if let d = rowButton(UIMenu(title: "Dark board: " + tools.dark.title, image: UIImage(systemName: "moon"), children: dark)) {
            rowStack.addArrangedSubview(d)
        }
        if !Device.isPhone {
            rowStack.addArrangedSubview(rowButton(UIAction(title: "Fingers draw", image: UIImage(systemName: "hand.draw"), state: tools.fingersDraw ? .on : .off) { [weak b] _ in
                tools.fingersDraw.toggle()
                b?.toolChanged()
            })!)
        }
        rowStack.addArrangedSubview(rowButton(UIAction(title: "Ruler", image: UIImage(systemName: "ruler"), state: b.canvas.isRulerActive ? .on : .off) { [weak b] _ in
            b?.toggleRuler()
        })!)
        rowStack.addArrangedSubview(rowButton(UIAction(title: "Quick ring", image: UIImage(systemName: "circle.circle"), state: QuickRingPrefs.on ? .on : .off) { [weak b] _ in
            QuickRingPrefs.on.toggle()
            b?.quickRingChanged()
            b?.bar.refresh()
        })!)
        if !b.pdfs.isEmpty {
            rowStack.addArrangedSubview(rowButton(UIAction(title: "Contents", image: UIImage(systemName: "list.bullet")) { [weak b] _ in
                guard let b else { return }
                b.showContents(from: b.bar.pagePill)
            })!)
        }
        rowStack.addArrangedSubview(rowButton(UIAction(title: "Hide the bars", image: UIImage(systemName: "rectangle.expand.vertical")) { [weak b] _ in
            b?.setBarsHidden(true)
        })!)
    }
}

/// Draw | Insert | View: the kit's switch in UIKit. The picked one lifts onto the page's tone and the lift slides to the next pick
/// with the kit's spring.
final class ModePill: UIView {
    var onPick: ((BarMode) -> Void)?
    private(set) var mode = BarMode.draw
    private let lift = UIView()
    private let stack = UIStackView()
    private var buttons: [UIButton] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Kit.ui.hover
        layer.cornerRadius = Kit.controlRadius
        layer.cornerCurve = .continuous
        lift.backgroundColor = Kit.ui.page
        lift.layer.cornerRadius = 8
        lift.layer.cornerCurve = .continuous
        lift.layer.shadowColor = UIColor.black.cgColor
        lift.layer.shadowOpacity = 0.1
        lift.layer.shadowRadius = 2
        lift.layer.shadowOffset = CGSize(width: 0, height: 1)
        lift.isUserInteractionEnabled = false
        addSubview(lift)
        stack.axis = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
            heightAnchor.constraint(equalToConstant: 36),
        ])
        for m in BarMode.allCases {
            var c = UIButton.Configuration.plain()
            c.title = m.title
            c.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14)
            let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.pick(m) })
            b.accessibilityLabel = m.title
            b.accessibilityIdentifier = "board-mode-" + m.title.lowercased()
            buttons.append(b)
            stack.addArrangedSubview(b)
        }
        style()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func pick(_ m: BarMode) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onPick?(m)
    }

    func set(_ m: BarMode, animated: Bool) {
        guard m != mode || !animated else { return }
        mode = m
        style()
        setNeedsLayout()
        if animated, window != nil {
            UIView.animate(springDuration: 0.4, bounce: 0.28) { self.layoutIfNeeded() }
        }
    }

    private func style() {
        for (i, b) in buttons.enumerated() {
            let on = i == mode.rawValue
            b.configuration?.baseForegroundColor = on ? Kit.ui.ink : Kit.ui.muted
            b.configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var o = a; o.font = UIFont.nx(14, on ? .semibold : .medium); return o
            }
            if on { b.accessibilityTraits.insert(.selected) } else { b.accessibilityTraits.remove(.selected) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stack.layoutIfNeeded()
        let b = buttons[mode.rawValue]
        lift.frame = stack.convert(b.frame, to: self)
        lift.layer.shadowPath = UIBezierPath(roundedRect: lift.bounds, cornerRadius: 8).cgPath
    }
}
