import UIKit
import NexusCore

/// The board's bar (the redesign's Option B): a top row with the way back, where the board is, the tools, undo and redo, the
/// background and the board menu; under it a tool row with what the current tool needs (colours, widths, pen type, eraser kind,
/// shapes, Insert space's choice) and, on the right, the selected item's actions, the page, the zoom and the ruler.
final class BoardBar: UIView {
    static let topHeight: CGFloat = 52
    static let rowHeight: CGFloat = 44
    static var height: CGFloat { topHeight + rowHeight }

    weak var board: BoardController?
    var dark = false { didSet { if dark != oldValue { refresh() } } }

    private let back = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private let topRow = UIStackView()
    private let toolRow = UIStackView()
    private let toolsScroll = UIScrollView()
    private let toolsStack = UIStackView()
    private let rowScroll = UIScrollView()
    private let rowStack = UIStackView()
    private let rightStack = UIStackView()
    private let titleButton = UIButton(type: .system)
    let pagePill = UIButton(type: .system)
    let zoomPill = UIButton(type: .system)
    private let line = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        back.translatesAutoresizingMaskIntoConstraints = false
        addSubview(back)
        line.backgroundColor = UIColor.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)

        for s in [topRow, toolRow] {
            s.axis = .horizontal
            s.alignment = .center
            s.spacing = 4
            s.translatesAutoresizingMaskIntoConstraints = false
            addSubview(s)
        }
        toolsStack.axis = .horizontal
        toolsStack.spacing = 2
        toolsStack.alignment = .center
        toolsStack.translatesAutoresizingMaskIntoConstraints = false
        toolsScroll.showsHorizontalScrollIndicator = false
        toolsScroll.addSubview(toolsStack)
        rowStack.axis = .horizontal
        rowStack.spacing = 6
        rowStack.alignment = .center
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowScroll.showsHorizontalScrollIndicator = false
        rowScroll.addSubview(rowStack)
        rightStack.axis = .horizontal
        rightStack.spacing = 6
        rightStack.alignment = .center

        titleButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        titleButton.titleLabel?.lineBreakMode = .byTruncatingMiddle
        titleButton.contentHorizontalAlignment = .leading
        titleButton.tintColor = .label
        titleButton.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        titleButton.setContentHuggingPriority(.init(200), for: .horizontal)
        titleButton.showsMenuAsPrimaryAction = true

        for p in [pagePill, zoomPill] {
            var c = UIButton.Configuration.gray()
            c.cornerStyle = .capsule
            c.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
            c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
                return outgoing
            }
            p.configuration = c
            p.showsMenuAsPrimaryAction = true
        }

        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: leadingAnchor),
            back.trailingAnchor.constraint(equalTo: trailingAnchor),
            back.topAnchor.constraint(equalTo: topAnchor),
            back.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            topRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            topRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),
            topRow.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            topRow.heightAnchor.constraint(equalToConstant: BoardBar.topHeight),
            toolRow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 12),
            toolRow.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            toolRow.topAnchor.constraint(equalTo: topRow.bottomAnchor),
            toolRow.heightAnchor.constraint(equalToConstant: BoardBar.rowHeight),
            toolsStack.leadingAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.leadingAnchor),
            toolsStack.trailingAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.trailingAnchor),
            toolsStack.topAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.topAnchor),
            toolsStack.bottomAnchor.constraint(equalTo: toolsScroll.contentLayoutGuide.bottomAnchor),
            toolsStack.heightAnchor.constraint(equalTo: toolsScroll.frameLayoutGuide.heightAnchor),
            toolsScroll.heightAnchor.constraint(equalToConstant: 44),
            rowStack.leadingAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: rowScroll.contentLayoutGuide.bottomAnchor),
            rowStack.heightAnchor.constraint(equalTo: rowScroll.frameLayoutGuide.heightAnchor),
            rowScroll.heightAnchor.constraint(equalToConstant: 40),
        ])
        // the tools take the room they need, shrinking (and scrolling) only when the bar is narrow
        let toolsWidth = toolsScroll.widthAnchor.constraint(equalTo: toolsStack.widthAnchor)
        toolsWidth.priority = .init(740)
        toolsWidth.isActive = true
        toolsScroll.setContentCompressionResistancePriority(.init(300), for: .horizontal)
        let rowWidth = rowScroll.widthAnchor.constraint(equalTo: rowStack.widthAnchor)
        rowWidth.priority = .init(740)
        rowWidth.isActive = true
        rowScroll.setContentCompressionResistancePriority(.init(300), for: .horizontal)
        rowScroll.setContentHuggingPriority(.init(260), for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: building

    private func icon(_ symbol: String, _ label: String, selected: Bool = false, size: CGFloat = 17, action: @escaping () -> Void) -> UIButton {
        var c = selected ? UIButton.Configuration.tinted() : UIButton.Configuration.plain()
        c.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular))
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
        c.cornerStyle = .medium
        let b = UIButton(configuration: c, primaryAction: UIAction { _ in action() })
        b.accessibilityLabel = label
        b.toolTip = label
        b.tintColor = selected ? .tintColor : .label
        return b
    }

    private func menuButton(_ symbol: String, _ label: String, _ menu: UIMenu) -> UIButton {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
        let b = UIButton(configuration: c)
        b.menu = menu
        b.showsMenuAsPrimaryAction = true
        b.accessibilityLabel = label
        b.toolTip = label
        b.tintColor = .label
        return b
    }

    private func spacer() -> UIView {
        let v = UIView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }

    private func divider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        v.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return v
    }

    private func colorDot(_ hex: String, selected: Bool, action: @escaping () -> Void, edit: @escaping () -> Void) -> UIView {
        let b = UIButton(type: .custom)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 30).isActive = true
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let dot = UIView(frame: CGRect(x: 5, y: 5, width: 20, height: 20))
        dot.isUserInteractionEnabled = false
        dot.backgroundColor = InkConvert.color(hex)
        dot.layer.cornerRadius = 10
        dot.layer.borderWidth = 1
        dot.layer.borderColor = UIColor.label.withAlphaComponent(0.15).cgColor
        b.addSubview(dot)
        if selected {
            b.layer.cornerRadius = 15
            b.layer.borderWidth = 2
            b.layer.borderColor = UIColor.tintColor.cgColor
        }
        b.addAction(UIAction { _ in action() }, for: .primaryActionTriggered)
        let hold = UILongPressGestureRecognizer(target: nil, action: nil)
        hold.addTarget(HoldTarget.shared, action: #selector(HoldTarget.fire(_:)))
        HoldTarget.shared.actions[ObjectIdentifier(hold)] = edit
        b.addGestureRecognizer(hold)
        b.accessibilityLabel = "Colour"
        b.accessibilityHint = "Touch and hold to change this colour"
        return b
    }

    private func widthDot(_ size: CGFloat, selected: Bool, action: @escaping () -> Void) -> UIView {
        var c = selected ? UIButton.Configuration.tinted() : UIButton.Configuration.plain()
        c.cornerStyle = .capsule
        let b = UIButton(configuration: c, primaryAction: UIAction { _ in action() })
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        b.heightAnchor.constraint(equalToConstant: 32).isActive = true
        let d = min(18, max(3, size))
        let dot = UIView(frame: CGRect(x: 16 - d / 2, y: 16 - d / 2, width: d, height: d))
        dot.isUserInteractionEnabled = false
        dot.backgroundColor = .label
        dot.layer.cornerRadius = d / 2
        b.addSubview(dot)
        b.accessibilityLabel = "Width"
        return b
    }

    private func label(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        return l
    }

    private func textButton(_ title: String, _ symbol: String?, action: @escaping () -> Void) -> UIButton {
        var c = UIButton.Configuration.gray()
        c.title = title
        c.image = symbol.flatMap { UIImage(systemName: $0) }
        c.imagePadding = 5
        c.cornerStyle = .capsule
        c.buttonSize = .small
        return UIButton(configuration: c, primaryAction: UIAction { _ in action() })
    }

    private func segmented(_ items: [String], selected: Int, action: @escaping (Int) -> Void) -> UISegmentedControl {
        let s = UISegmentedControl(items: items)
        s.selectedSegmentIndex = selected
        s.addAction(UIAction { a in action((a.sender as? UISegmentedControl)?.selectedSegmentIndex ?? 0) }, for: .valueChanged)
        return s
    }

    private func clear(_ s: UIStackView) {
        for v in s.arrangedSubviews { s.removeArrangedSubview(v); v.removeFromSuperview() }
    }

    /// Builds both rows again from the board's state (a tool, colour or selection changed).
    func refresh() {
        guard let b = board else { return }
        let tools = BoardTools.shared
        let readOnly = b.readOnly
        HoldTarget.shared.actions.removeAll()

        // top row
        clear(topRow)
        let lead = UIStackView()
        lead.axis = .horizontal
        lead.spacing = 0
        lead.addArrangedSubview(icon(b.isSidePane ? "xmark" : "chevron.backward", b.isSidePane ? "Close this pane" : "Close the board") { [weak b] in b?.close() })
        if b.onSidebar != nil { lead.addArrangedSubview(icon("sidebar.left", "Sidebar") { [weak b] in b?.onSidebar?() }) }
        topRow.addArrangedSubview(lead)
        var tc = UIButton.Configuration.plain()
        tc.title = b.boardName
        tc.subtitle = b.placeName
        tc.titleLineBreakMode = .byTruncatingMiddle
        tc.subtitleLineBreakMode = .byTruncatingHead
        tc.titleAlignment = .leading
        tc.baseForegroundColor = .label
        tc.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        titleButton.configuration = tc
        titleButton.menu = b.titleMenu()
        topRow.addArrangedSubview(titleButton)

        clear(toolsStack)
        if !readOnly {
            for t in BoardTool.allCases {
                toolsStack.addArrangedSubview(icon(t.symbol, t.title, selected: tools.tool == t) { [weak b] in b?.selectTool(t) })
            }
            toolsStack.addArrangedSubview(menuButton("plus", "Insert", b.insertMenu()))
        } else {
            toolsStack.addArrangedSubview(label("Read only"))
        }
        topRow.addArrangedSubview(toolsScroll)
        let after = spacer()
        topRow.addArrangedSubview(after)
        let w = after.widthAnchor.constraint(equalTo: titleButton.widthAnchor, multiplier: 0.6)
        w.priority = .init(150)
        w.isActive = true

        let trail = UIStackView()
        trail.axis = .horizontal
        trail.spacing = 0
        if !readOnly {
            trail.addArrangedSubview(icon("arrow.uturn.backward", "Undo") { [weak b] in b?.undo() })
            trail.addArrangedSubview(icon("arrow.uturn.forward", "Redo") { [weak b] in b?.redo() })
            trail.addArrangedSubview(menuButton("square.grid.3x3", "Background", b.backgroundMenu()))
        }
        b.extraBarButtons().forEach { trail.addArrangedSubview($0) }
        trail.addArrangedSubview(menuButton("ellipsis.circle", "Board menu", b.boardMenu()))
        topRow.addArrangedSubview(trail)

        // tool row
        clear(toolRow)
        clear(rowStack)
        clear(rightStack)
        if !readOnly { fillToolRow(b) }
        toolRow.addArrangedSubview(rowScroll)
        toolRow.addArrangedSubview(spacer())

        if let it = b.selectedItem, !readOnly {
            if it.type == "text" {
                rightStack.addArrangedSubview(textButton("Type", "character.cursor.ibeam") { [weak b] in b?.editSelected() })
            }
            rightStack.addArrangedSubview(textButton("Delete", "trash") { [weak b] in b?.deleteSelected() })
            rightStack.addArrangedSubview(divider())
        }
        if !b.pdfs.isEmpty {
            pagePill.menu = b.pageMenu()
            rightStack.addArrangedSubview(pagePill)
        }
        zoomPill.menu = b.zoomMenu()
        rightStack.addArrangedSubview(zoomPill)
        if !readOnly {
            rightStack.addArrangedSubview(icon("ruler", "Ruler", selected: b.canvas.isRulerActive) { [weak b] in b?.toggleRuler() })
        }
        toolRow.addArrangedSubview(rightStack)
        updatePills()
    }

    private func fillToolRow(_ b: BoardController) {
        let tools = BoardTools.shared
        let t = tools.tool
        if t.inks {
            let colors = tools.colors(t)
            for (i, hex) in colors.enumerated() {
                rowStack.addArrangedSubview(colorDot(hex, selected: tools.colorIndex(t) == i, action: { [weak b] in
                    tools.setColorIndex(t, i)
                    b?.toolChanged()
                }, edit: { [weak b] in b?.editColor(t, i) }))
            }
            rowStack.addArrangedSubview(divider())
            for (i, w) in BoardTools.widths(t).enumerated() {
                rowStack.addArrangedSubview(widthDot(w * (t == .highlighter ? 0.5 : 2), selected: tools.widthIndex(t) == i) { [weak b] in
                    tools.setWidthIndex(t, i)
                    b?.toolChanged()
                })
            }
            if t == .pen || t == .shapes {
                rowStack.addArrangedSubview(divider())
                let kinds = BoardTools.PenKind.allCases.map { k in
                    UIAction(title: k.title, state: tools.penKind == k ? .on : .off) { [weak b] _ in
                        tools.penKind = k
                        b?.toolChanged()
                    }
                }
                var c = UIButton.Configuration.gray()
                c.title = tools.penKind.title
                c.cornerStyle = .capsule
                c.buttonSize = .small
                let k = UIButton(configuration: c)
                k.menu = UIMenu(children: kinds)
                k.showsMenuAsPrimaryAction = true
                rowStack.addArrangedSubview(k)
            }
            if t == .shapes {
                rowStack.addArrangedSubview(divider())
                rowStack.addArrangedSubview(label("Shapes snap as you draw. Or add one:"))
                for (kind, symbol, name) in [("rect", "rectangle", "Rectangle"), ("ellipse", "circle", "Ellipse"),
                                             ("line", "line.diagonal", "Line"), ("arrow", "arrow.up.right", "Arrow")] {
                    rowStack.addArrangedSubview(icon(symbol, name, size: 15) { [weak b] in b?.insertShape(kind) })
                }
            }
        } else if t == .eraser {
            rowStack.addArrangedSubview(segmented(["Whole strokes", "Part of a stroke"], selected: tools.eraserPixel ? 1 : 0) { [weak b] i in
                tools.eraserPixel = i == 1
                b?.toolChanged()
            })
            if tools.eraserPixel {
                for (i, w) in BoardTools.widths(.eraser).enumerated() {
                    rowStack.addArrangedSubview(widthDot(w / 3, selected: tools.widthIndex(.eraser) == i) { [weak b] in
                        tools.setWidthIndex(.eraser, i)
                        b?.toolChanged()
                    })
                }
            }
        } else if t == .space {
            rowStack.addArrangedSubview(label("Drag down where you want room, up to take empty space away."))
            if !b.pdfs.isEmpty {
                rowStack.addArrangedSubview(segmented(["Open up the page", "Move the whole page"], selected: tools.spaceOpensPage ? 0 : 1) { i in
                    tools.spaceOpensPage = i == 0
                })
            }
        } else if t == .text {
            rowStack.addArrangedSubview(label("Tap where you want to type."))
        } else if t == .lasso {
            rowStack.addArrangedSubview(label("Circle ink to move it. Tap a block, picture or shape to pick it."))
        } else if t == .hand {
            rowStack.addArrangedSubview(label("The Pencil scrolls and picks things; nothing is drawn."))
        }
    }

    /// The page and zoom pills (they change while scrolling, so they're kept apart from the rest).
    func updatePills() {
        guard let b = board else { return }
        pagePill.configuration?.title = b.pageLabel.isEmpty ? "—" : b.pageLabel
        zoomPill.configuration?.title = "\(Int((b.canvas.zoomScale * 100).rounded()))%"
    }
}

/// Long-press targets for the colour dots (UIButton keeps a closure only for its primary action).
final class HoldTarget: NSObject {
    static let shared = HoldTarget()
    var actions: [ObjectIdentifier: () -> Void] = [:]

    @objc func fire(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        actions[ObjectIdentifier(g)]?()
    }
}
