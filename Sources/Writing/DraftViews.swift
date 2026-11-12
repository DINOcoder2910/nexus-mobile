import UIKit
import NexusCore

/// The open block's drafts as small tabs just above it (only when it has drafts): tap one to show it, + for a new draft.
/// A locked draft has a lock; the current one is in bold.
final class DraftTabs: UIView {
    weak var session: WritingSession?
    private let stack = UIStackView()

    init(session: WritingSession) {
        self.session = session
        super.init(frame: .zero)
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Puts the tabs above the block (view coordinates of the board), or hides them for a block without drafts.
    func place(over frame: CGRect) {
        guard let s = session, !s.fullscreen, let b = s.board, let it = s.item, !BlockDrafts.list(it).isEmpty else {
            isHidden = true
            return
        }
        if superview !== b.view { b.view.insertSubview(self, aboveSubview: s.textView); refresh() }
        isHidden = false
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        self.frame = CGRect(x: frame.minX, y: frame.minY - size.height - 4, width: max(size.width, 40), height: size.height)
    }

    func refresh() {
        guard let s = session, let b = s.board, let it = s.item else { return }
        for v in stack.arrangedSubviews { v.removeFromSuperview() }
        let all = BlockDrafts.list(it)
        let cur = BlockDrafts.current(it)
        let shown = b.shownDraft(s.id)
        for d in all {
            var c = UIButton.Configuration.filled()
            c.cornerStyle = .capsule
            c.buttonSize = .mini
            c.title = d.name
            c.image = d.locked ? UIImage(systemName: "lock.fill") : nil
            c.imagePadding = 3
            c.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 9)
            let on = d.id == shown
            c.baseBackgroundColor = on ? BlockLook.accent : UIColor.secondarySystemBackground
            c.baseForegroundColor = on ? .white : .label
            c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { a in
                var a = a
                a.font = UIFont.systemFont(ofSize: 12, weight: d.id == cur ? .semibold : .regular)
                return a
            }
            let button = UIButton(configuration: c)
            button.accessibilityLabel = d.name + (d.id == cur ? ", current draft" : "") + (d.locked ? ", locked" : "")
            button.addAction(UIAction { [weak b] _ in b?.viewDraft(s.id, d.id) }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        var plus = UIButton.Configuration.plain()
        plus.image = UIImage(systemName: "plus")
        plus.buttonSize = .mini
        let add = UIButton(configuration: plus)
        add.accessibilityLabel = "New draft"
        add.addAction(UIAction { [weak b] _ in b?.newDraft(s.id) }, for: .touchUpInside)
        stack.addArrangedSubview(add)
        if superview != nil, !isHidden { place(over: s.textView.frame) }
    }
}

/// Compare a draft with the one it was made from: what changed there since (when anything did), then the two side by side by line,
/// with Bring them over.
final class DraftCompareController: UIViewController {
    weak var board: BoardController?
    let id: String
    let draft: String
    private let textView = UITextView()

    init(board: BoardController, id: String, draft: String) {
        self.board = board
        self.id = id
        self.draft = draft
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        textView.isEditable = false
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        textView.translatesAutoresizingMaskIntoConstraints = false
        let bar = UINavigationBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        let nav = UINavigationItem(title: "Compare drafts")
        nav.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        nav.rightBarButtonItem = UIBarButtonItem(title: "Bring them over", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let b = self.board, id = self.id, d = self.draft
            self.dismiss(animated: true) { b?.bringOver(id, into: d) }
        })
        bar.items = [nav]
        view.addSubview(bar)
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        fill(nav)
    }

    private func fill(_ nav: UINavigationItem) {
        guard let b = board, let it = b.content.items.first(where: { $0.id == id }) else { return }
        let all = BlockDrafts.list(it)
        guard let d = all.first(where: { $0.id == draft }) else { return }
        let fromName = all.first { $0.id == d.from }?.name ?? "the old draft"
        let out = NSMutableAttributedString()
        let body = UIFont.systemFont(ofSize: 15)
        let head = UIFont.systemFont(ofSize: 13, weight: .semibold)
        func add(_ s: String, _ font: UIFont, _ color: UIColor = .label, back: UIColor? = nil, strike: Bool = false) {
            var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            if let back { a[.backgroundColor] = back }
            if strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: s, attributes: a))
        }
        func lines(_ changes: [BlockDrafts.LineChange]) {
            for ch in changes {
                switch ch {
                case .same(let l): add("  " + l + "\n", body, .secondaryLabel)
                case .added(let l): add("+ " + l + "\n", body, BlockLook.added, back: BlockLook.added.withAlphaComponent(0.08))
                case .removed(let l): add("− " + l + "\n", body, BlockLook.deleted, back: BlockLook.deleted.withAlphaComponent(0.08), strike: true)
                }
            }
        }
        let since = BlockDrafts.changedSince(b.content, id: id, draft: draft) ?? []
        if since.isEmpty {
            add("Nothing changed in \(fromName) since \(d.name) was made.\n\n", head, .secondaryLabel)
            nav.rightBarButtonItem?.isEnabled = false
        } else {
            add("CHANGED IN \(fromName.uppercased()) SINCE \(d.name.uppercased()) WAS MADE\n", head, .secondaryLabel)
            let snap = b.content.texts[BlockDrafts.snapKey(id, draft)] ?? ""
            lines(BlockDrafts.compare(snap, BlockDrafts.words(b.content, id, d.from)).filter {
                if case .same = $0 { return false } else { return true }
            })
            add("\n", body)
        }
        add("\(fromName.uppercased()) → \(d.name.uppercased())\n", head, .secondaryLabel)
        lines(BlockDrafts.compare(BlockDrafts.words(b.content, id, d.from), BlockDrafts.words(b.content, id, draft)))
        textView.attributedText = out
    }
}
