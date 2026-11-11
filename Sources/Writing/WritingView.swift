import UIKit
import NexusCore

/// The Writing view: one block full screen (⌘↩, or the block's menu), with wide margins, its headings as an outline down the side
/// and the word count. It is the same block on the same board: the words go to the board as you type, and Done (or ⌘↩, Esc) puts
/// you back where you were.
final class WritingViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let session: WritingSession
    private let outline = UITableView(frame: .zero, style: .plain)
    private var headings: [(title: String, level: Int, at: Int)] = []
    private let count = UILabel()
    private var timer: Timer?

    init(session: WritingSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(red: 0.984, green: 0.98, blue: 0.969, alpha: 1)

        let tv = session.textView
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.textContainerInset = UIEdgeInsets(top: 48, left: 24, bottom: 240, right: 24)
        tv.alwaysBounceVertical = true
        if let fill = session.look.fill { tv.backgroundColor = fill.withAlphaComponent(0.35) }
        view.addSubview(tv)

        outline.translatesAutoresizingMaskIntoConstraints = false
        outline.dataSource = self
        outline.delegate = self
        outline.backgroundColor = .clear
        outline.separatorStyle = .none
        outline.register(UITableViewCell.self, forCellReuseIdentifier: "h")
        view.addSubview(outline)

        let done = UIButton(configuration: .filled())
        done.configuration?.title = "Done"
        done.translatesAutoresizingMaskIntoConstraints = false
        done.addAction(UIAction { [weak self] _ in self?.close() }, for: .touchUpInside)
        view.addSubview(done)

        count.translatesAutoresizingMaskIntoConstraints = false
        count.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        count.textColor = .secondaryLabel
        view.addSubview(count)

        let g = view.safeAreaLayoutGuide
        let width = tv.widthAnchor.constraint(equalToConstant: 760)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            outline.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            outline.topAnchor.constraint(equalTo: g.topAnchor, constant: 60),
            outline.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -12),
            outline.widthAnchor.constraint(equalToConstant: 200),
            tv.topAnchor.constraint(equalTo: g.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tv.centerXAnchor.constraint(equalTo: g.centerXAnchor, constant: 60),
            width,
            tv.leadingAnchor.constraint(greaterThanOrEqualTo: outline.trailingAnchor, constant: 8),
            tv.trailingAnchor.constraint(lessThanOrEqualTo: g.trailingAnchor, constant: -8),
            done.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            done.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            count.centerYAnchor.constraint(equalTo: done.centerYAnchor),
            count.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -16),
        ])

        session.onDone = { [weak self] in self?.close() }
        session.restyle()
        refresh()
        // the outline and count follow the words without redoing them on every key
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.refresh() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.textView.becomeFirstResponder()
        session.textView.selectedRange = NSRange(location: (session.text as NSString).length, length: 0)
        session.keepCaretVisible()
    }

    func refresh() {
        let lines = LiveMarkdown.parse(session.text)
        let ns = session.text as NSString
        var hs: [(title: String, level: Int, at: Int)] = []
        for line in lines {
            if case .heading(let n) = line.kind {
                let words = ns.substring(with: NSRange(location: line.content, length: line.range.location + line.range.length - line.content))
                hs.append((LiveMarkdown.visibleText(words), min(n, 4), line.range.location))
            }
        }
        if hs.map({ $0.title }) != headings.map({ $0.title }) || hs.map({ $0.at }) != headings.map({ $0.at }) {
            headings = hs
            outline.reloadData()
        }
        let c = LiveMarkdown.count(session.text)
        count.text = "\(c.words) words · \(c.characters) characters"
    }

    func close() {
        timer?.invalidate()
        session.textView.resignFirstResponder()
        let board = session.board
        let s = session
        dismiss(animated: true) { board?.finish(s) }
    }

    // MARK: the outline

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { headings.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "h", for: indexPath)
        let h = headings[indexPath.row]
        var c = cell.defaultContentConfiguration()
        c.text = h.title
        c.textProperties.font = UIFont.systemFont(ofSize: h.level <= 1 ? 15 : 14, weight: h.level <= 2 ? .semibold : .regular)
        c.textProperties.color = h.level <= 2 ? .label : .secondaryLabel
        c.textProperties.numberOfLines = 2
        c.directionalLayoutMargins.leading = CGFloat(max(0, h.level - 1)) * 12 + 8
        cell.contentConfiguration = c
        cell.backgroundColor = .clear
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let at = headings[indexPath.row].at
        let tv = session.textView
        tv.selectedRange = NSRange(location: at, length: 0)
        let r = tv.layoutManager.boundingRect(forGlyphRange: tv.layoutManager.glyphRange(forCharacterRange: NSRange(location: at, length: 1), actualCharacterRange: nil), in: tv.textContainer)
        tv.setContentOffset(CGPoint(x: 0, y: max(0, r.minY + tv.textContainerInset.top - 24)), animated: true)
    }
}

/// Find and replace across every block on the board (⌘F): matches listed with their words around them; tap one to open its block
/// there; Replace all is one undo step.
final class FindReplaceController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {
    weak var board: BoardController?
    private let find = UITextField()
    private let replace = UITextField()
    private let list = UITableView(frame: .zero, style: .insetGrouped)
    private var hits: [(id: String, range: NSRange, snippet: String)] = []

    init(board: BoardController) {
        self.board = board
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        preferredContentSize = CGSize(width: 520, height: 600)
        for (f, p) in [(find, "Find on this board"), (replace, "Replace with")] {
            f.placeholder = p
            f.borderStyle = .roundedRect
            f.clearButtonMode = .whileEditing
            f.autocorrectionType = .no
            f.autocapitalizationType = .none
            f.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(f)
        }
        find.returnKeyType = .search
        find.delegate = self
        find.addAction(UIAction { [weak self] _ in self?.search() }, for: .editingChanged)

        let all = UIButton(configuration: .filled())
        all.configuration?.title = "Replace all"
        all.translatesAutoresizingMaskIntoConstraints = false
        all.addAction(UIAction { [weak self] _ in self?.replaceAll() }, for: .touchUpInside)
        view.addSubview(all)

        let close = UIButton(configuration: .plain())
        close.configuration?.title = "Close"
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
        view.addSubview(close)

        list.translatesAutoresizingMaskIntoConstraints = false
        list.dataSource = self
        list.delegate = self
        list.register(UITableViewCell.self, forCellReuseIdentifier: "hit")
        view.addSubview(list)

        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            find.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 8),
            find.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            find.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            replace.topAnchor.constraint(equalTo: find.bottomAnchor, constant: 8),
            replace.leadingAnchor.constraint(equalTo: find.leadingAnchor),
            replace.trailingAnchor.constraint(equalTo: all.leadingAnchor, constant: -8),
            all.centerYAnchor.constraint(equalTo: replace.centerYAnchor),
            all.trailingAnchor.constraint(equalTo: find.trailingAnchor),
            list.topAnchor.constraint(equalTo: replace.bottomAnchor, constant: 8),
            list.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        find.becomeFirstResponder()
    }

    func search() {
        hits = []
        guard let b = board, let q = find.text, !q.isEmpty else { list.reloadData(); return }
        // blocks in reading order: top to bottom, then left to right
        let blocks = b.content.items.filter { $0.type == "text" }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        for it in blocks {
            let md = b.content.texts[it.id] ?? ""
            let ns = md as NSString
            for r in MarkdownEdit.find(q, in: md) {
                let a = max(0, r.location - 30), e = min(ns.length, r.location + r.length + 30)
                let snippet = (a > 0 ? "…" : "") + ns.substring(with: NSRange(location: a, length: e - a)).replacingOccurrences(of: "\n", with: " ") + (e < ns.length ? "…" : "")
                hits.append((it.id, r, snippet))
            }
        }
        list.reloadData()
    }

    func replaceAll() {
        guard let b = board, let q = find.text, !q.isEmpty else { return }
        let with = replace.text ?? ""
        b.endWriting()
        var n = 0
        b.changeItems("Replace") { c in
            for (id, md) in c.texts {
                let r = MarkdownEdit.replace(q, with: with, in: md)
                if r.count > 0 { c.texts[id] = r.text; n += r.count }
            }
        }
        search()
        b.tell(n == 1 ? "Replaced 1" : "Replaced \(n)", brief: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        search()
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { hits.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let q = find.text, !q.isEmpty else { return nil }
        return hits.count == 1 ? "1 match" : "\(hits.count) matches"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "hit", for: indexPath)
        var c = cell.defaultContentConfiguration()
        c.text = hits[indexPath.row].snippet
        c.textProperties.numberOfLines = 2
        cell.contentConfiguration = c
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let hit = hits[indexPath.row]
        guard let b = board, let it = b.content.items.first(where: { $0.id == hit.id }) else { return }
        dismiss(animated: true) {
            b.scroll(toBoard: CGPoint(x: it.x - 60, y: it.y - 80))
            b.beginWriting(it)
            b.writing?.textView.selectedRange = hit.range
        }
    }
}
