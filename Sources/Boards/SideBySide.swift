import UIKit
import PDFKit
import NexusCore

/// Side by side: the board on the left and, when asked, a second pane on the right: another board, the same board again (each
/// pane its own place and zoom; the two save through the same merge as the laptop and the iPad), or one of the board's PDFs on
/// its own. Drag the divider to share the width; close the second pane from its own bar.
final class BoardSplitController: UIViewController {
    let main: UINavigationController
    private(set) var side: UIViewController?
    private let divider = UIView()
    private let grip = UIView()
    /// The left pane's share of the width while two are shown.
    private var share: CGFloat = 0.5
    let root: URL
    weak var store: NexusStore?
    var onSaved: ((String) -> Void)?

    init(board: BoardController, root: URL) {
        main = BoardNavigationController(rootViewController: board)
        self.root = root
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(main)
        view.addSubview(main.view)
        main.didMove(toParent: self)
        divider.backgroundColor = UIColor.separator
        grip.backgroundColor = UIColor.secondaryLabel
        grip.layer.cornerRadius = 2
        divider.addSubview(grip)
        divider.isHidden = true
        divider.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragged(_:))))
        view.addSubview(divider)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        guard let side else {
            main.view.frame = b
            divider.isHidden = true
            return
        }
        let gap: CGFloat = 8
        let left = (b.width * share).rounded()
        main.view.frame = CGRect(x: 0, y: 0, width: left - gap / 2, height: b.height)
        side.view.frame = CGRect(x: left + gap / 2, y: 0, width: b.width - left - gap / 2, height: b.height)
        divider.isHidden = false
        divider.frame = CGRect(x: left - gap / 2, y: 0, width: gap, height: b.height)
        grip.frame = CGRect(x: gap / 2 - 2, y: b.height / 2 - 24, width: 4, height: 48)
    }

    @objc private func dragged(_ g: UIPanGestureRecognizer) {
        let x = g.location(in: view).x
        share = min(0.8, max(0.2, x / max(1, view.bounds.width)))
        view.setNeedsLayout()
    }

    func show(_ vc: UIViewController) {
        closeSide()
        let nav = vc is UINavigationController ? vc : UINavigationController(rootViewController: vc)
        addChild(nav)
        view.addSubview(nav.view)
        nav.didMove(toParent: self)
        side = nav
        share = 0.5
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    func closeSide() {
        guard let side else { return }
        (side as? UINavigationController)?.viewControllers.compactMap { $0 as? BoardController }.forEach { $0.saveNow() }
        side.willMove(toParent: nil)
        side.view.removeFromSuperview()
        side.removeFromParent()
        self.side = nil
        view.setNeedsLayout()
    }

    /// A board in the second pane.
    func showBoard(_ path: String, focusEnd: JSONValue? = nil) {
        let b = BoardController(root: root, path: path, focus: nil)
        b.focusEnd = focusEnd
        b.store = store
        b.onSaved = onSaved
        b.onClose = { [weak self] in self?.closeSide() }
        b.isSidePane = true
        show(b)
    }

    func showPDF(_ url: URL, title: String) {
        show(PdfPaneController(url: url, title: title, onClose: { [weak self] in self?.closeSide() }))
    }
}

/// One of a board's PDFs on its own: scroll and zoom it, search it, select its words.
final class PdfPaneController: UIViewController {
    let url: URL
    let onClose: () -> Void
    private let pdf = PDFView()

    init(url: URL, title: String, onClose: @escaping () -> Void) {
        self.url = url
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        pdf.frame = view.bounds
        pdf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pdf.autoScales = true
        pdf.displayMode = .singlePageContinuous
        pdf.displayDirection = .vertical
        pdf.document = PDFDocument(url: url)
        view.addSubview(pdf)
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.onClose() })
    }
}

extension BoardController {
    var split: BoardSplitController? {
        var p = parent
        while let v = p { if let s = v as? BoardSplitController { return s }; p = v.parent }
        return nil
    }

    /// Side by side's choices: this board again, another board, or one of this board's PDFs.
    func sideBySideMenu() -> [UIMenuElement] {
        guard let split else { return [] }
        var out: [UIMenuElement] = []
        if split.side != nil {
            out.append(UIAction(title: "Close the second pane", image: UIImage(systemName: "xmark.rectangle")) { [weak split] _ in split?.closeSide() })
        }
        out.append(UIAction(title: "This board again", subtitle: "Look at two places of it at once", image: UIImage(systemName: "rectangle.split.2x1")) { [weak self, weak split] _ in
            guard let self else { return }
            self.saveNow()
            split?.showBoard(self.path)
        })
        let boards = Notebook.list(root).flatMap { nb in nb.allBoards.map { ($0.place, $0.board) } }
            .filter { $0.1.path != path }
        if !boards.isEmpty {
            out.append(UIMenu(title: "Another board", image: UIImage(systemName: "rectangle.on.rectangle"), children: boards.prefix(60).map { place, b in
                UIAction(title: b.name, subtitle: place) { [weak split] _ in split?.showBoard(b.path) }
            }))
        }
        let pdfItems = content.items.filter { $0.type == "pdf" }
        if !pdfItems.isEmpty {
            out.append(UIMenu(title: "A PDF on its own", image: UIImage(systemName: "doc.richtext"), children: pdfItems.compactMap { it in
                guard let url = resolve(it.src) else { return nil }
                let name = url.deletingPathExtension().lastPathComponent
                return UIAction(title: name) { [weak split] _ in split?.showPDF(url, title: name) }
            }))
        }
        return out
    }
}
