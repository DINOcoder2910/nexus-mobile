import UIKit
import NexusCore

/// The block's Styles (its `styles`, nexus docs/data-format.md "Typed blocks"): the font for the whole block, and for each of the
/// seven styles its size, weight, colour, line spacing, space before and after, and indent. Only what differs from the default is
/// written; Reset takes a style back. Each change is one undo step and shows at once on the open block.
final class StylesController: UIViewController {
    weak var board: BoardController?
    let id: String
    private var style: BlockStyle
    private let picker = UISegmentedControl(items: BlockStyle.allCases.map(\.label))
    private let rows = UIStackView()

    init(board: BoardController, id: String, style: BlockStyle) {
        self.board = board
        self.id = id
        self.style = style
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private var item: BoardItem? { board?.content.items.first { $0.id == id } }

    /// The style's look with no changes of the block's own (units), and with them.
    private func looks() -> (plain: BlockLook.Style, own: BlockLook.Style)? {
        guard let it = item else { return nil }
        var plain = BlockLook(it)
        plain.styles = nil
        return (plain.style(style), BlockLook(it).style(style))
    }

    private var own: [(String, JSONValue)] { item?.json["styles"]?[style.rawValue]?.object ?? [] }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Styles"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        picker.selectedSegmentIndex = BlockStyle.allCases.firstIndex(of: style) ?? 4
        picker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.style = BlockStyle.allCases[self.picker.selectedSegmentIndex]
            self.fill()
        }, for: .valueChanged)
        rows.axis = .vertical
        rows.spacing = 12
        let scroll = UIScrollView()
        let content = UIStackView(arrangedSubviews: [picker, rows])
        content.axis = .vertical
        content.spacing = 18
        for v in [scroll, content] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(scroll)
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
        ])
        fill()
    }

    // MARK: rows

    private func label(_ s: String) -> UILabel {
        let l = UILabel()
        l.text = s
        l.font = .preferredFont(forTextStyle: .body)
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }

    private func row(_ title: String, _ control: UIView, changed: Bool) -> UIView {
        let t = label(title)
        if changed { t.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .semibold) }
        let r = UIStackView(arrangedSubviews: [t, UIView(), control])
        r.alignment = .center
        r.spacing = 10
        return r
    }

    /// A number with − and + and its value.
    private func stepper(_ key: String, value: Double, step: Double, range: ClosedRange<Double>, format: @escaping (Double) -> String) -> UIView {
        let v = UILabel()
        v.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        v.text = format(value)
        v.textColor = .secondaryLabel
        let s = UIStepper()
        s.minimumValue = range.lowerBound
        s.maximumValue = range.upperBound
        s.stepValue = step
        s.value = min(max(value, range.lowerBound), range.upperBound)
        s.addAction(UIAction { [weak self, weak v] a in
            guard let st = a.sender as? UIStepper else { return }
            let n = (st.value * 100).rounded() / 100
            v?.text = format(n)
            self?.set(key, .number(n))
        }, for: .valueChanged)
        let r = UIStackView(arrangedSubviews: [v, s])
        r.spacing = 10
        r.alignment = .center
        return r
    }

    private func fill() {
        for v in rows.arrangedSubviews { v.removeFromSuperview() }
        guard let l = looks(), let it = item else { return }
        let o = own
        func has(_ k: String) -> Bool { o.contains { $0.0 == k } }
        let cur = l.own

        // the block's font (one per block)
        let family = BlockLook(it).family
        let font = UIButton(configuration: .gray())
        font.configuration?.title = BlockLook.families.first { $0.key == family }?.label ?? "Sans"
        font.showsMenuAsPrimaryAction = true
        font.menu = UIMenu(children: BlockLook.families.map { f in
            UIAction(title: f.label, state: f.key == family ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.board?.setBlockField(self.id, "font", f.key == "sans" ? nil : .string(f.key))
                self.fill()
            }
        })
        rows.addArrangedSubview(row("Font (whole block)", font, changed: family != "sans"))
        let sep = UIView(); sep.backgroundColor = .separator; sep.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
        rows.addArrangedSubview(sep)

        rows.addArrangedSubview(row("Size", stepper("size", value: Double(cur.size), step: 1, range: 6...200) { "\(Int($0)) pt" }, changed: has("size")))

        let weights: [(Double, String)] = [(300, "Light"), (400, "Regular"), (500, "Medium"), (600, "Semibold"), (700, "Bold"), (800, "Heavy"), (900, "Black")]
        let ownWeight = o.first { $0.0 == "weight" }?.1.number
        let weight = UIButton(configuration: .gray())
        let shownWeight = ownWeight ?? (style == .title ? 700 : [.h1, .h2, .h3].contains(style) ? 650 : 400)
        weight.configuration?.title = weights.min { abs($0.0 - shownWeight) < abs($1.0 - shownWeight) }?.1 ?? "Regular"
        weight.showsMenuAsPrimaryAction = true
        weight.menu = UIMenu(children: weights.map { w in
            UIAction(title: w.1, state: ownWeight == w.0 ? .on : .off) { [weak self] _ in self?.set("weight", .number(w.0)); self?.fill() }
        })
        rows.addArrangedSubview(row("Weight", weight, changed: has("weight")))

        let colours: [(String?, String)] = [(nil, "Block's colour")] + TextLook.colors.map { ($0.hex.uppercased(), $0.label) }
        let ownColour = o.first { $0.0 == "color" }?.1.string
        let colour = UIButton(configuration: .gray())
        colour.configuration?.title = colours.first { $0.0 == ownColour }?.1 ?? "Custom"
        colour.showsMenuAsPrimaryAction = true
        colour.menu = UIMenu(children: colours.map { c in
            UIAction(title: c.1, image: c.0.map { swatch(BlockLook.hex($0)) }, state: ownColour == c.0 ? .on : .off) { [weak self] _ in
                self?.set("color", c.0.map { .string($0) }); self?.fill()
            }
        })
        rows.addArrangedSubview(row("Colour", colour, changed: has("color")))

        rows.addArrangedSubview(row("Line spacing", stepper("line", value: Double(cur.line), step: 0.05, range: 0.8...4) { String(format: "%.2f×", $0) }, changed: has("line")))
        rows.addArrangedSubview(row("Space before", stepper("before", value: Double(cur.before).rounded(), step: 1, range: 0...400) { "\(Int($0))" }, changed: has("before")))
        rows.addArrangedSubview(row("Space after", stepper("after", value: Double(cur.after).rounded(), step: 1, range: 0...400) { "\(Int($0))" }, changed: has("after")))
        rows.addArrangedSubview(row("Indent", stepper("indent", value: Double(cur.indent).rounded(), step: 4, range: 0...400) { "\(Int($0))" }, changed: has("indent")))

        var reset = UIButton.Configuration.plain()
        reset.title = "Reset \(style.label) to the default"
        let r = UIButton(configuration: reset, primaryAction: UIAction { [weak self] _ in self?.resetStyle() })
        r.isEnabled = !o.isEmpty
        rows.addArrangedSubview(r)
        let note = UILabel()
        note.text = "Changes apply to this block only. Bold names are this block's own."
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        rows.addArrangedSubview(note)
    }

    private func swatch(_ c: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
            c.setFill(); UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 14, height: 14)).fill()
        }
    }

    /// Sets one value of this style (nil takes it off); a style left with nothing goes, and so does `styles` when empty.
    private func set(_ key: String, _ value: JSONValue?) {
        guard let b = board, let it = item else { return }
        var all = it.json["styles"] ?? .object([])
        var one = all[style.rawValue] ?? .object([])
        one = one.setting(key, value)
        all = all.setting(style.rawValue, (one.object?.isEmpty ?? true) ? nil : one)
        b.setBlockField(id, "styles", (all.object?.isEmpty ?? true) ? nil : all)
    }

    private func resetStyle() {
        guard let b = board, let it = item, var all = it.json["styles"] else { return }
        all = all.setting(style.rawValue, nil)
        b.setBlockField(id, "styles", (all.object?.isEmpty ?? true) ? nil : all)
        fill()
    }
}

extension BoardController {
    func openStyles(_ id: String, style: BlockStyle) {
        let vc = StylesController(board: self, id: id, style: style)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        nav.preferredContentSize = CGSize(width: 480, height: 620)
        presentOver(nav)
    }
}
