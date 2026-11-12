import UIKit
import NexusCore

/// Make a flashcard from typed words: a careful sheet. Front and back start from the chosen words ("term: meaning", "term — meaning"
/// or "term - meaning" split in two), you pick the deck and can flip the card, and nothing happens until you press Add.
/// For now Add copies the card, ready to paste into the deck in Study; writing straight into a deck on the iPad comes with Study there.
final class FlashcardSheet: UIViewController {
    private let front = UITextView()
    private let back = UITextView()
    private let deckButton = UIButton(configuration: .gray())
    private let preview = UILabel()
    private var deck: (path: String, title: String)?
    private let decks: [(path: String, title: String)]
    private let onAdd: (String, String, String?) -> Void

    init(words: String, decks: [(path: String, title: String)], onAdd: @escaping (String, String, String?) -> Void) {
        self.decks = decks
        self.onAdd = onAdd
        deck = decks.first
        super.init(nibName: nil, bundle: nil)
        let parts = FlashcardSheet.split(words)
        front.text = parts.0
        back.text = parts.1
        preferredContentSize = CGSize(width: 480, height: 520)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// "term: meaning", "term — meaning", "term – meaning", "term - meaning", "term = meaning" → (term, meaning).
    static func split(_ s: String) -> (String, String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for sep in [" — ", " – ", " - ", " = ", ": ", "\n"] {
            if let r = t.range(of: sep) {
                return (String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), String(t[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return (t, "")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Make a flashcard"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let add = UIBarButtonItem(title: "Add", primaryAction: UIAction { [weak self] _ in self?.add() })
        add.style = .done
        navigationItem.rightBarButtonItem = add

        func box(_ tv: UITextView, _ placeholder: String) -> UIView {
            tv.font = .preferredFont(forTextStyle: .body)
            tv.layer.cornerRadius = 10
            tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
            tv.heightAnchor.constraint(equalToConstant: 90).isActive = true
            let l = UILabel()
            l.text = placeholder
            l.font = .preferredFont(forTextStyle: .footnote)
            l.textColor = .secondaryLabel
            let s = UIStackView(arrangedSubviews: [l, tv])
            s.axis = .vertical
            s.spacing = 4
            return s
        }
        let flip = UIButton(configuration: .plain(), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            (self.front.text, self.back.text) = (self.back.text, self.front.text)
            self.refresh()
        })
        flip.configuration?.title = "Swap front and back"
        flip.configuration?.image = UIImage(systemName: "arrow.up.arrow.down")
        flip.configuration?.imagePadding = 6

        deckButton.showsMenuAsPrimaryAction = true
        deckButton.menu = UIMenu(children: decks.isEmpty ? [UIAction(title: "No decks yet", attributes: .disabled) { _ in }] : decks.map { d in
            UIAction(title: d.title, subtitle: d.path) { [weak self] _ in self?.deck = d; self?.refresh() }
        })
        let deckLabel = UILabel()
        deckLabel.text = "Deck"
        let deckRow = UIStackView(arrangedSubviews: [deckLabel, UIView(), deckButton])
        deckRow.alignment = .center

        preview.numberOfLines = 0
        preview.font = .preferredFont(forTextStyle: .footnote)
        preview.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [box(front, "Front"), box(back, "Back"), flip, deckRow, preview])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        NotificationCenter.default.addObserver(forName: UITextView.textDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private var frontText: String { front.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var backText: String { back.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func refresh() {
        deckButton.configuration?.title = deck?.title ?? "Choose a deck"
        navigationItem.rightBarButtonItem?.isEnabled = !frontText.isEmpty && !backText.isEmpty
        preview.text = frontText.isEmpty || backText.isEmpty
            ? "A card needs a front and a back."
            : "Nothing is added until you press Add. Add copies the card, ready to paste into \(deck?.title ?? "a deck") in Study."
    }

    private func add() {
        guard !frontText.isEmpty, !backText.isEmpty else { return }
        let f = frontText, b = backText, d = deck?.path, done = onAdd
        dismiss(animated: true) { done(f, b, d) }
    }
}

extension BoardController {
    /// The study decks in the data folder (`<workstream>/study/decks/*.yaml`), by their title line.
    func studyDecks() -> [(path: String, title: String)] {
        guard let store else { return [] }
        var out: [(String, String)] = []
        let fm = FileManager.default
        for w in store.snapshot.workstreams.values.sorted(by: { $0.name < $1.name }) {
            let dir = root.appendingPathComponent(w.folder).appendingPathComponent("study/decks")
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files.sorted() where f.hasSuffix(".yaml") {
                let text = (try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)) ?? ""
                let title = text.split(separator: "\n").first { $0.hasPrefix("title:") }
                    .map { String($0.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) } ?? String(f.dropLast(5))
                out.append(("\(w.folder)/study/decks/\(f)", "\(title) (\(w.name))"))
            }
        }
        return out
    }

    func makeFlashcard(from blockId: String, range: NSRange) {
        let md = content.texts[shownKey(blockId)] ?? ""
        let s = md as NSString
        var r = NSIntersectionRange(range, NSRange(location: 0, length: s.length))
        if r.length == 0 { r = s.lineRange(for: NSRange(location: min(r.location, max(0, s.length - 1)), length: 0)) }
        let words = BlockFacts.plainText(s.substring(with: r))
        let sheet = FlashcardSheet(words: words, decks: studyDecks()) { [weak self] front, back, deck in
            UIPasteboard.general.string = "\(front)\t\(back)"
            self?.tell("Card copied: \(front) / \(back)\(deck == nil ? "" : ". Paste it into the deck in Study.")", brief: true)
        }
        let nav = UINavigationController(rootViewController: sheet)
        nav.modalPresentationStyle = .formSheet
        presentOver(nav)
    }
}
