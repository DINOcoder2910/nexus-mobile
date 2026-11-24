import UIKit
import PencilKit
import NexusCore

/// The iPhone's tools (the Nov 20 mockup, project files new-look/mockups/iphone-draw-light.png): a pill floating at the foot of the board
/// with the everyday tools and +, so the top bar keeps only the way back, the board's name, undo, redo and ⋯. Tapping the tool that is
/// already picked opens its sheet (Pen or Pencil, the width, the colours). A picked thing's actions (Type, Delete, a card's Use) sit in a
/// smaller pill above it. Only on an iPhone held upright: a turned iPhone has room for the wide bar, and an iPad keeps its bar.
final class PhoneToolPill: UIView {
    static let height: CGFloat = 54
    /// The pill's tools, in the mockup's order; Hand last. The Pencil is reached from the Pen's sheet and Insert space from +.
    static let tools: [BoardTool] = [.pen, .highlighter, .eraser, .lasso, .text, .shapes, .hand]

    weak var bar: BoardBar?
    private let back = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    /// The picked thing's actions, above the pill.
    let actionsPill = UIView()
    private let actionsBack = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let actions = UIStackView()
    /// The tool's sheet while it is open.
    weak var sheet: PhoneToolSheet?

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "phone-tool-pill"
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 4)
        back.layer.cornerRadius = 20
        back.layer.cornerCurve = .continuous
        back.clipsToBounds = true
        back.layer.borderWidth = 1 / UIScreen.main.scale
        back.layer.borderColor = Kit.ui.line.cgColor
        back.translatesAutoresizingMaskIntoConstraints = false
        addSubview(back)
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: leadingAnchor), back.trailingAnchor.constraint(equalTo: trailingAnchor),
            back.topAnchor.constraint(equalTo: topAnchor), back.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        // the tools sit in the middle while they fit, and scroll on a small iPhone
        let middle = stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor)
        middle.isActive = true
        stack.distribution = .equalSpacing

        actionsPill.accessibilityIdentifier = "phone-item-actions"
        actionsPill.layer.cornerRadius = 18
        actionsPill.layer.shadowColor = UIColor.black.cgColor
        actionsPill.layer.shadowOpacity = 0.1
        actionsPill.layer.shadowRadius = 10
        actionsBack.layer.cornerRadius = 18
        actionsBack.clipsToBounds = true
        actionsBack.translatesAutoresizingMaskIntoConstraints = false
        actionsPill.addSubview(actionsBack)
        actions.axis = .horizontal
        actions.spacing = 6
        actions.alignment = .center
        actions.translatesAutoresizingMaskIntoConstraints = false
        actionsPill.addSubview(actions)
        NSLayoutConstraint.activate([
            actionsBack.leadingAnchor.constraint(equalTo: actionsPill.leadingAnchor), actionsBack.trailingAnchor.constraint(equalTo: actionsPill.trailingAnchor),
            actionsBack.topAnchor.constraint(equalTo: actionsPill.topAnchor), actionsBack.bottomAnchor.constraint(equalTo: actionsPill.bottomAnchor),
            actions.leadingAnchor.constraint(equalTo: actionsPill.leadingAnchor, constant: 8),
            actions.trailingAnchor.constraint(equalTo: actionsPill.trailingAnchor, constant: -8),
            actions.centerYAnchor.constraint(equalTo: actionsPill.centerYAnchor),
        ])
        actionsPill.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        back.layer.borderColor = Kit.ui.line.cgColor
    }

    /// Whether the pill shows now: an upright iPhone's board, with its bar showing and something it may change.
    func syncShown() {
        guard let bar, let b = bar.board else { isHidden = true; actionsPill.isHidden = true; return }
        let on = bar.pill && !bar.isHidden && !b.readOnly
        isHidden = !on
        alpha = bar.alpha
        actionsPill.alpha = bar.alpha
        if !on { actionsPill.isHidden = true }
    }

    /// Where the two pills sit in the board's view (the board's layout calls it).
    func place(in view: UIView) {
        if superview !== view { view.addSubview(self) }
        if actionsPill.superview !== view { view.addSubview(actionsPill) }
        let safe = view.safeAreaInsets
        let w = min(view.bounds.width - safe.left - safe.right - 32, 420)
        let y = view.bounds.height - max(safe.bottom, 12) - PhoneToolPill.height - 4
        frame = CGRect(x: ((view.bounds.width - w) / 2).rounded(), y: y.rounded(), width: w, height: PhoneToolPill.height)
        let fit = actions.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let aw = min(w, fit.width + 16)
        actionsPill.frame = CGRect(x: ((view.bounds.width - aw) / 2).rounded(), y: frame.minY - 10 - 44, width: aw, height: 44)
        view.bringSubviewToFront(self)
        view.bringSubviewToFront(actionsPill)
    }

    /// How much of the foot of the board the pill covers (the quick ring and the board's scrolling keep clear of it).
    var coveredHeight: CGFloat { isHidden ? 0 : PhoneToolPill.height + 16 }

    // MARK: building

    func refresh(_ b: BoardController) {
        guard let bar else { return }
        bar.clear(stack)
        let tools = BoardTools.shared
        let now = tools.tool
        // Insert space picked adds its button: the tools narrow a little so + stays on an iPhone's screen
        let width: CGFloat = now == .space ? 36 : 42
        for t in PhoneToolPill.tools {
            // the Pen's place shows the Pencil while it is picked (its sheet switches between the two)
            let shown: BoardTool = t == .pen && now == .pencil ? .pencil : t
            stack.addArrangedSubview(toolButton(shown, picked: now == shown, b: b, width: width))
        }
        if now == .space { stack.addArrangedSubview(toolButton(.space, picked: true, b: b, width: width)) }
        let line = bar.divider()
        stack.addArrangedSubview(line)
        // + opens a sheet like the tools', not a menu: on iOS 26 a menu from the pill brought the keyboard up over itself
        // (docs/ci-lessons.md, Nov 24), and a sheet has room for the choices with their names
        var pc = UIButton.Configuration.plain()
        pc.image = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        pc.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
        let plus = UIButton(configuration: pc, primaryAction: UIAction { [weak self, weak b] _ in
            if let b { self?.openSheet(b, insert: true) }
        })
        plus.tintColor = .label
        plus.accessibilityLabel = "Insert"
        plus.accessibilityIdentifier = "phone-tool-plus"
        stack.addArrangedSubview(plus)

        // the picked thing's actions
        bar.clear(actions)
        if let it = b.selectedItem {
            if it.type == "text" { actions.addArrangedSubview(bar.textButton("Type", "character.cursor.ibeam") { [weak b] in b?.editSelected() }) }
            if it.type == "tool" { b.toolCardButtons(it).forEach { actions.addArrangedSubview($0) } }
            actions.addArrangedSubview(bar.textButton("Delete", "trash") { [weak b] in b?.deleteSelected() })
            actionsPill.isHidden = isHidden
        } else {
            actionsPill.isHidden = true
        }
        if let v = superview { place(in: v) }
        sheet?.build()
    }

    private func toolButton(_ t: BoardTool, picked: Bool, b: BoardController, width: CGFloat = 42) -> UIView {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: t.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 8, bottom: 12, trailing: 8)
        c.background.cornerRadius = 12
        if picked { c.background.backgroundColor = Kit.ui.hover }
        c.baseForegroundColor = Kit.ui.ink
        let button = UIButton(configuration: c, primaryAction: UIAction { [weak self, weak b] _ in
            guard let b else { return }
            if BoardTools.shared.tool == t { self?.openSheet(b) } else { b.selectTool(t) }
        })
        button.accessibilityLabel = t.title
        button.accessibilityIdentifier = "phone-tool-\(t.rawValue)"
        button.accessibilityHint = picked ? "Tap again for its colours and sizes" : nil
        if picked { button.accessibilityTraits.insert(.selected) }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        // an ink's colour as a short line under it, as in the mockup
        if t.inks {
            let hex = BoardTools.shared.color(t)
            let mark = UIView()
            mark.isUserInteractionEnabled = false
            let ink = InkConvert.color(hex)
            mark.backgroundColor = bar?.dark == true ? PKInkingTool.convertColor(ink, from: .light, to: .dark) : ink
            mark.layer.cornerRadius = 1.5
            mark.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(mark)
            NSLayoutConstraint.activate([
                mark.widthAnchor.constraint(equalToConstant: 16), mark.heightAnchor.constraint(equalToConstant: 3),
                mark.centerXAnchor.constraint(equalTo: button.centerXAnchor), mark.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -4),
            ])
        }
        return button
    }

    func openSheet(_ b: BoardController, insert: Bool = false) {
        guard sheet == nil, let bar else { return }
        let s = PhoneToolSheet(bar: bar, insert: insert)
        sheet = s
        b.present(s, animated: true)
    }
}

/// The picked tool's sheet on the iPhone: its kind (Pen or Pencil; the pen's kind), Width and Colour as in the mockup, and whatever else
/// the tool's row holds on the iPad (the eraser's kind, Insert space's choices, a hint). Its parts come from the bar's own tool row, so
/// a control added there shows here too.
final class PhoneToolSheet: UIViewController {
    weak var bar: BoardBar?
    /// + 's sheet: what can be put on the board, and Insert space, instead of the picked tool's settings.
    let insert: Bool
    private let scroll = UIScrollView()
    private let content = UIStackView()

    init(bar: BoardBar, insert: Bool = false) {
        self.bar = bar
        self.insert = insert
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let s = sheetPresentationController {
            s.detents = [.custom(identifier: .init("tool")) { [weak self] ctx in min(ctx.maximumDetentValue, (self?.wanted ?? 360)) }, .large()]
            s.prefersGrabberVisible = true
            s.largestUndimmedDetentIdentifier = .init("tool") // the board stays bright: a colour shows on the ink straight away
            s.preferredCornerRadius = 24
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var wanted: CGFloat = 360

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Kit.ui.page
        view.accessibilityIdentifier = "phone-tool-sheet"
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        content.axis = .vertical
        content.spacing = 14
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 22),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -22),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 26),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
        ])
        build()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if bar?.phonePill.sheet === self { bar?.phonePill.sheet = nil }
    }

    /// Builds the sheet again from the tool as it is now (a colour or a width was picked).
    func build() {
        guard isViewLoaded, let bar, let b = bar.board else { return }
        bar.clear(content)
        let tools = BoardTools.shared
        let t = tools.tool

        // the head: the tool's name (or Insert) and Done
        let title = UILabel()
        title.text = insert ? "Insert" : t.title
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = Kit.ui.ink
        var dc = UIButton.Configuration.plain()
        dc.title = "Done"
        dc.baseForegroundColor = Kit.ui.accent
        dc.contentInsets = .zero
        let done = UIButton(configuration: dc, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        done.accessibilityIdentifier = "phone-tool-sheet-done"
        let head = UIStackView(arrangedSubviews: [title, bar.spacer(), done])
        head.alignment = .center
        content.addArrangedSubview(head)

        if insert { fillInsert(b) } else { fillTool(b, t) }
        view.layoutIfNeeded()
        let h = content.systemLayoutSizeFitting(CGSize(width: view.bounds.width - 44, height: 0),
                                                withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
        let want = min(560, h + 60)
        if abs(want - wanted) > 1 {
            wanted = want
            sheetPresentationController?.animateChanges { sheetPresentationController?.invalidateDetents() }
        }
    }

    /// + 's choices as rows: each closes the sheet, then runs (a picker opens over the board, not over the sheet).
    private func fillInsert(_ b: BoardController) {
        let all = b.insertChoices()
        for c in all where !c.shape { content.addArrangedSubview(choiceRow(c.title, c.symbol, picked: false, c.run)) }
        let space = BoardTool.space
        content.addArrangedSubview(choiceRow(space.title, space.symbol, picked: BoardTools.shared.tool == .space) { [weak b] in b?.selectTool(.space) })
        content.addArrangedSubview(section("Shape"))
        for c in all where c.shape { content.addArrangedSubview(choiceRow(c.title, c.symbol, picked: false, c.run)) }
    }

    private func choiceRow(_ title: String, _ symbol: String, picked: Bool, _ run: @escaping () -> Void) -> UIView {
        var c = UIButton.Configuration.plain()
        c.title = title
        c.image = UIImage(systemName: symbol)
        c.imagePadding = 14
        c.baseForegroundColor = Kit.ui.ink
        c.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4)
        if picked { c.background.backgroundColor = Kit.ui.hover; c.background.cornerRadius = 10 }
        let button = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in
            guard let self else { run(); return }
            self.dismiss(animated: true) { run() }
        })
        button.contentHorizontalAlignment = .leading
        button.accessibilityLabel = title
        if picked { button.accessibilityTraits.insert(.selected) }
        return button
    }

    /// The picked tool's settings: Pen | Pencil, then what its iPad row holds as Width, Colour and the rest.
    private func fillTool(_ b: BoardController, _ t: BoardTool) {
        guard let bar else { return }
        // Pen | Pencil, as the mockup's kinds
        if t == .pen || t == .pencil {
            let kinds = UISegmentedControl(items: ["Pen", "Pencil"])
            kinds.selectedSegmentIndex = t == .pencil ? 1 : 0
            kinds.accessibilityIdentifier = "phone-tool-kind"
            kinds.addAction(UIAction { [weak b] a in
                let i = (a.sender as? UISegmentedControl)?.selectedSegmentIndex ?? 0
                b?.selectTool(i == 1 ? .pencil : .pen)
            }, for: .valueChanged)
            kinds.heightAnchor.constraint(equalToConstant: 40).isActive = true
            content.addArrangedSubview(kinds)
        }

        // everything the tool's row holds on the iPad, sorted into Width, Colour and the rest
        bar.clear(bar.rowStack)
        bar.fillToolRow(b)
        let parts = bar.rowStack.arrangedSubviews
        parts.forEach { bar.rowStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        var colours: [UIView] = [], widths: [UIView] = [], rest: [UIView] = []
        for v in parts {
            if v.backgroundColor == .separator, v.subviews.isEmpty { continue } // a divider
            if v.accessibilityLabel == "Colour" { colours.append(v) }
            else if let l = v.accessibilityLabel, BoardTools.widthNames.contains(l) || l == "Width" { widths.append(v) }
            else { rest.append(v) }
        }
        for v in rest {
            if let l = v as? UILabel { l.numberOfLines = 0; l.font = .systemFont(ofSize: 15) }
            let row = UIStackView(arrangedSubviews: [v, bar.spacer()])
            row.alignment = .center
            content.addArrangedSubview(row)
        }
        if !widths.isEmpty {
            content.addArrangedSubview(section("Width"))
            let row = UIStackView(arrangedSubviews: widths.map(cell))
            row.distribution = .fillEqually
            row.accessibilityIdentifier = "phone-tool-widths"
            content.addArrangedSubview(row)
        }
        if !colours.isEmpty {
            content.addArrangedSubview(section("Colour"))
            let grid = UIStackView()
            grid.axis = .vertical
            grid.spacing = 8
            grid.accessibilityIdentifier = "phone-tool-colours"
            var i = 0
            while i < colours.count {
                let line = Array(colours[i..<min(i + 5, colours.count)]).map(cell)
                let row = UIStackView(arrangedSubviews: line + (0..<(5 - line.count)).map { _ in UIView() })
                row.distribution = .fillEqually
                grid.addArrangedSubview(row)
                i += 5
            }
            content.addArrangedSubview(grid)
            content.addArrangedSubview(hint("Touch and hold a colour to change it."))
        }
    }

    private func section(_ s: String) -> UILabel {
        let l = UILabel()
        l.text = s
        l.font = .systemFont(ofSize: 15)
        l.textColor = Kit.ui.muted
        return l
    }

    private func hint(_ s: String) -> UILabel {
        let l = section(s)
        l.font = .systemFont(ofSize: 13)
        l.numberOfLines = 0
        return l
    }

    /// One control in the middle of a 44-point cell, so rows of them spread across the sheet.
    private func cell(_ v: UIView) -> UIView {
        let c = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(v)
        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: c.centerXAnchor), v.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            c.heightAnchor.constraint(equalToConstant: 48),
        ])
        // the colours a little bigger than on the iPad's row
        if v.accessibilityLabel == "Colour" { v.transform = CGAffineTransform(scaleX: 1.35, y: 1.35) }
        return c
    }
}
