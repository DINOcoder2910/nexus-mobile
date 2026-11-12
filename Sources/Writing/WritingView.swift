import UIKit
import NexusCore

/// The Writing view (nexus board redesign, picture w5): one block full screen, as a page. Across the top: back to the board, the
/// board's and block's names, the word count, Comment, Comments (shows or hides them here and on the board), the block's drafts and
/// Done. Down the left: the outline (the heading you're in marked) and the block's comments; tap one to go to it. Beside the page:
/// each comment as a card next to its words, with Reply and Resolve. It is the same block on the same board: the words go to the
/// board as you type, and Done (or ⌘↩, Esc) puts you back where you were. It follows the board's light or dark look.
final class WritingViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let session: WritingSession
    private let top = UIView()
    private let titleLabel = UILabel()
    private let subLabel = UILabel()
    private let count = UILabel()
    private let commentsButton = UIButton(configuration: .gray())
    private let draftsButton = UIButton(configuration: .gray())
    private let page = UIView()
    private let side = UITableView(frame: .zero, style: .grouped)
    private let cards = UIView()
    private var headings: [(title: String, level: Int, at: Int)] = []
    private var comments: [BoardItem] = []
    private var sideWidth: NSLayoutConstraint?
    private var cardsWidth: NSLayoutConstraint?
    private var timer: Timer?
    private var scrollWatch: NSKeyValueObservation?
    private var lastCaretHeading = -1

    init(session: WritingSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var board: BoardController? { session.board }
    private var dark: Bool { board?.boardIsDark ?? false }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = dark ? .dark : .light
        view.backgroundColor = dark ? UIColor(white: 0.07, alpha: 1) : UIColor(red: 0.953, green: 0.949, blue: 0.937, alpha: 1)

        // the top bar
        top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        var back = UIButton.Configuration.plain()
        back.image = UIImage(systemName: "chevron.left")
        back.title = "Board"
        back.imagePadding = 4
        let backButton = UIButton(configuration: back, primaryAction: UIAction { [weak self] _ in self?.close() })
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subLabel.font = .systemFont(ofSize: 12)
        subLabel.textColor = .secondaryLabel
        let names = UIStackView(arrangedSubviews: [titleLabel, subLabel])
        names.axis = .vertical
        names.spacing = 1
        count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        count.textColor = .secondaryLabel
        var commentConf = UIButton.Configuration.plain()
        commentConf.image = UIImage(systemName: "text.bubble")
        commentConf.title = "Comment"
        commentConf.imagePadding = 4
        let commentButton = UIButton(configuration: commentConf, primaryAction: UIAction { [weak self] _ in self?.commentHere() })
        commentButton.isHidden = board?.readOnly ?? true
        commentsButton.addAction(UIAction { [weak self] _ in self?.toggleComments() }, for: .touchUpInside)
        draftsButton.configuration?.image = UIImage(systemName: "square.stack")
        draftsButton.showsMenuAsPrimaryAction = true
        draftsButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            guard let self, let b = self.board else { done([]); return }
            done(b.draftMenu(self.session.id))
        }])
        let done = UIButton(configuration: .filled(), primaryAction: UIAction { [weak self] _ in self?.close() })
        done.configuration?.title = "Done"
        let left = UIStackView(arrangedSubviews: [backButton, names])
        left.spacing = 8
        left.alignment = .center
        let right = UIStackView(arrangedSubviews: [count, commentButton, commentsButton, draftsButton, done])
        right.spacing = 10
        right.alignment = .center
        for v in [left, right] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; top.addSubview(v) }
        let rule = UIView()
        rule.backgroundColor = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(rule)

        // the page
        page.translatesAutoresizingMaskIntoConstraints = false
        page.backgroundColor = dark ? UIColor(white: 0.13, alpha: 1) : .white
        if let fill = session.look.fill { page.backgroundColor = fill }
        page.layer.cornerRadius = 8
        page.layer.shadowColor = UIColor.black.cgColor
        page.layer.shadowOpacity = dark ? 0 : 0.06
        page.layer.shadowRadius = 12
        page.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.addSubview(page)
        let tv = session.textView
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.textContainerInset = UIEdgeInsets(top: 56, left: 64, bottom: 280, right: 64)
        tv.alwaysBounceVertical = true
        tv.backgroundColor = .clear
        page.addSubview(tv)

        // the outline and the comments list
        side.translatesAutoresizingMaskIntoConstraints = false
        side.dataSource = self
        side.delegate = self
        side.backgroundColor = .clear
        side.separatorStyle = .none
        side.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        view.addSubview(side)

        // comment cards beside the page
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.clipsToBounds = true
        view.addSubview(cards)

        let g = view.safeAreaLayoutGuide
        let pageWidth = page.widthAnchor.constraint(equalToConstant: 780)
        pageWidth.priority = .defaultHigh
        let sw = side.widthAnchor.constraint(equalToConstant: 230)
        let cw = cards.widthAnchor.constraint(equalToConstant: 280)
        sideWidth = sw
        cardsWidth = cw
        let centred = page.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        centred.priority = .defaultLow
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: g.topAnchor),
            top.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            top.heightAnchor.constraint(equalToConstant: 56),
            left.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 8),
            left.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            right.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            left.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -12),
            rule.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: top.bottomAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            side.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 8),
            side.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
            side.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sw,
            page.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 16),
            page.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 8),
            page.leadingAnchor.constraint(greaterThanOrEqualTo: side.trailingAnchor, constant: 16),
            page.trailingAnchor.constraint(lessThanOrEqualTo: cards.leadingAnchor, constant: -16),
            pageWidth, centred,
            cards.topAnchor.constraint(equalTo: page.topAnchor),
            cards.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            cards.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            cw,
            tv.topAnchor.constraint(equalTo: page.topAnchor),
            tv.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: page.trailingAnchor),
        ])

        session.onDone = { [weak self] in self?.close() }
        session.restyle()
        scrollWatch = tv.observe(\.contentOffset) { [weak self] _, _ in DispatchQueue.main.async { self?.placeCards() } }
        refresh()
        // the outline, comments and count follow the words without redoing them on every key
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.refresh() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        session.textView.becomeFirstResponder()
        session.textView.selectedRange = NSRange(location: (session.text as NSString).length, length: 0)
        session.keepCaretVisible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // narrow screens (split view, portrait): the side columns give way to the page
        let w = view.bounds.width
        let showCards = (board?.marksShown ?? true) && !comments.isEmpty && w >= 1100
        sideWidth?.constant = w >= 900 ? 230 : 0
        side.isHidden = w < 900
        cardsWidth?.constant = showCards ? 280 : 0
        cards.isHidden = !showCards
        placeCards()
    }

    // MARK: following the words

    func refresh() {
        let text = session.text
        let ns = text as NSString
        var hs: [(title: String, level: Int, at: Int)] = []
        for line in LiveMarkdown.parse(text) {
            if case .heading(let n) = line.kind {
                let words = ns.substring(with: NSRange(location: line.content, length: line.range.location + line.range.length - line.content))
                hs.append((LiveMarkdown.visibleText(words), min(n, 4), line.range.location))
            }
        }
        let list = board.map { b in BoardMarks.marks(on: session.id, b.content.items).filter { !BoardMarks.isDone($0) && BoardMarks.kind($0) == "bubble" } } ?? []
        let caret = session.textView.selectedRange.location
        let here = hs.lastIndex { $0.at <= caret } ?? -1
        let changed = hs.map(\.title) != headings.map(\.title) || hs.map(\.at) != headings.map(\.at)
            || list.map(\.json) != comments.map(\.json) || here != lastCaretHeading
        headings = hs
        comments = list
        lastCaretHeading = here
        if changed { side.reloadData(); buildCards() }
        let c = LiveMarkdown.count(text)
        count.text = "\(c.words) words"
        titleLabel.text = hs.first?.title ?? firstLine(text)
        subLabel.text = board?.boardName
        let shown = board?.marksShown ?? true
        commentsButton.configuration = shown && !list.isEmpty ? .filled() : .gray()
        commentsButton.configuration?.image = UIImage(systemName: shown ? "text.bubble.fill" : "text.bubble")
        commentsButton.configuration?.title = list.isEmpty ? "Comments" : "Comments \(list.count)"
        commentsButton.configuration?.imagePadding = 4
        let drafts = session.item.map { BlockDrafts.list($0) } ?? []
        draftsButton.configuration?.title = drafts.count > 1 ? (drafts.first { $0.id == board?.shownDraft(session.id) }?.name ?? "Drafts") : "Drafts"
        view.setNeedsLayout()
    }

    private func firstLine(_ s: String) -> String {
        let l = s.split(separator: "\n").first.map(String.init) ?? ""
        let t = LiveMarkdown.visibleText(l).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Writing" : String(t.prefix(60))
    }

    func close() {
        timer?.invalidate()
        scrollWatch = nil
        session.textView.resignFirstResponder()
        let board = session.board
        let s = session
        dismiss(animated: true) { board?.finish(s) }
    }

    // MARK: comments

    private func commentHere() {
        guard let b = board else { return }
        b.addComment(on: session.id, range: session.textView.selectedRange)
    }

    private func toggleComments() {
        guard let b = board else { return }
        b.marksShown.toggle()
        session.restyle()
        refresh()
    }

    /// The words a comment sits on, in the block now.
    private func range(of m: BoardItem) -> NSRange? {
        guard let at = BoardMarks.anchor(m), let f = Anchor.find(session.text, at) else { return nil }
        return NSRange(location: f.from, length: f.to - f.from)
    }

    private func go(to r: NSRange) {
        let tv = session.textView
        tv.selectedRange = r
        let lm = tv.layoutManager
        let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: r.location, length: max(1, r.length)), actualCharacterRange: nil), in: tv.textContainer)
        tv.setContentOffset(CGPoint(x: 0, y: max(0, rect.minY + tv.textContainerInset.top - 80)), animated: true)
        session.restyle()
    }

    private func when(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        return Calendar.current.isDateInToday(d) ? d.formatted(date: .omitted, time: .shortened) : d.formatted(.dateTime.day().month(.abbreviated))
    }

    private var cardViews: [(id: String, view: UIView)] = []

    private func buildCards() {
        cardViews.forEach { $0.view.removeFromSuperview() }
        cardViews = comments.map { m in (m.id, card(m)) }
        cardViews.forEach { cards.addSubview($0.view) }
        placeCards()
    }

    private func card(_ m: BoardItem) -> UIView {
        let box = UIView()
        box.backgroundColor = dark ? UIColor(white: 0.17, alpha: 1) : .white
        box.layer.cornerRadius = 10
        box.layer.borderWidth = 1 / UIScreen.main.scale
        box.layer.borderColor = UIColor.separator.cgColor
        let written = m.json["strokes"] != nil && (m.string("text") ?? "").isEmpty
        let head = UILabel()
        head.font = .systemFont(ofSize: 13, weight: .semibold)
        head.text = [m.string("by") ?? "", when(m.string("made") ?? ""), written ? "written" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let body = UILabel()
        body.numberOfLines = 6
        body.font = written ? .italicSystemFont(ofSize: 14) : .systemFont(ofSize: 14)
        body.textColor = written ? .secondaryLabel : .label
        body.text = written ? "Handwritten comment" : (m.string("text") ?? "")
        let replies = BoardMarks.replies(m)
        var rows: [UIView] = [head, body]
        if !replies.isEmpty {
            let r = UILabel()
            r.font = .systemFont(ofSize: 13)
            r.textColor = .secondaryLabel
            r.numberOfLines = 3
            r.text = replies.count == 1 ? "\(replies[0].by): \(replies[0].text ?? "(written)")" : "\(replies.count) replies"
            rows.append(r)
        }
        let id = m.id
        func link(_ t: String, _ act: @escaping () -> Void) -> UIButton {
            var c = UIButton.Configuration.plain()
            c.title = t
            c.contentInsets = .zero
            c.baseForegroundColor = .tintColor
            return UIButton(configuration: c, primaryAction: UIAction { _ in act() })
        }
        if !(board?.readOnly ?? true) {
            let actions = UIStackView(arrangedSubviews: [
                link("Reply") { [weak self] in self?.board?.openMark(id) },
                link("Resolve") { [weak self] in
                    self?.board?.changeMark(id, "Resolve") { $0.with("done", .bool(true)) }
                    self?.refresh()
                },
                UIView(),
            ])
            actions.spacing = 14
            rows.append(actions)
        }
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        box.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:))))
        box.accessibilityIdentifier = id
        return box
    }

    @objc private func cardTapped(_ g: UITapGestureRecognizer) {
        guard let id = g.view?.accessibilityIdentifier, let m = comments.first(where: { $0.id == id }) else { return }
        if let r = range(of: m) { go(to: r) } else { board?.openMark(id) }
    }

    /// Each card beside its words' line, pushed down so none overlap.
    private func placeCards() {
        guard !cards.isHidden, cards.bounds.width > 0 else { return }
        let tv = session.textView
        let lm = tv.layoutManager
        var y: CGFloat = 0
        for (id, v) in cardViews {
            guard let m = comments.first(where: { $0.id == id }) else { continue }
            var want: CGFloat = y
            if let r = range(of: m), NSMaxRange(r) <= (session.text as NSString).length {
                let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: r.location, length: max(1, r.length)), actualCharacterRange: nil), in: tv.textContainer)
                want = rect.minY + tv.textContainerInset.top - tv.contentOffset.y
            }
            let size = v.systemLayoutSizeFitting(CGSize(width: cards.bounds.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            let at = max(want, y)
            v.frame = CGRect(x: 0, y: at, width: cards.bounds.width, height: size.height)
            y = at + size.height + 10
        }
    }

    // MARK: the outline and the comments list

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? max(headings.count, 1) : max(comments.count, 1)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { section == 0 ? "Outline" : "Comments" }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var c = cell.defaultContentConfiguration()
        c.textProperties.numberOfLines = 2
        cell.backgroundColor = .clear
        cell.selectionStyle = .default
        if indexPath.section == 0 {
            if headings.isEmpty {
                c.text = "Headings show here"
                c.textProperties.color = .tertiaryLabel
                cell.selectionStyle = .none
            } else {
                let h = headings[indexPath.row]
                c.text = h.title
                let here = indexPath.row == lastCaretHeading
                c.textProperties.font = .systemFont(ofSize: h.level <= 1 ? 15 : 14, weight: h.level <= 1 || here ? .semibold : .regular)
                c.textProperties.color = here ? .tintColor : (h.level <= 2 ? .label : .secondaryLabel)
                c.directionalLayoutMargins.leading = CGFloat(max(0, h.level - 1)) * 14 + 8
            }
        } else if comments.isEmpty {
            c.text = "Select words and tap Comment"
            c.textProperties.color = .tertiaryLabel
            cell.selectionStyle = .none
        } else {
            let m = comments[indexPath.row]
            let written = m.json["strokes"] != nil && (m.string("text") ?? "").isEmpty
            c.image = UIImage(systemName: written ? "pencil.tip" : "text.bubble")
            c.text = "“" + (BoardMarks.anchor(m)?.q ?? (m.string("text") ?? "")) + "”"
            c.textProperties.font = .systemFont(ofSize: 14)
        }
        c.textProperties.font = indexPath.section == 1 ? .systemFont(ofSize: 14) : c.textProperties.font
        cell.contentConfiguration = c
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            guard indexPath.row < headings.count else { return }
            go(to: NSRange(location: headings[indexPath.row].at, length: 0))
        } else {
            guard indexPath.row < comments.count else { return }
            let m = comments[indexPath.row]
            if let r = range(of: m) { go(to: r) } else { board?.openMark(m.id) }
        }
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
