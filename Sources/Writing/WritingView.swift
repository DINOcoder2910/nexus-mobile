import UIKit
import NexusCore

/// The Writing view (nexus board redesign, picture w5; the laptop's docs/board-writing.md "The Writing view"): one block full
/// screen, as a page. Across the top: back to the board, the board's name › the block's title, the word count, Comments n (shows or
/// hides them here and on the board), History, the block's drafts and Done. Down the left: the outline (the heading you're in
/// marked) and the block's comments; tap one to go to it; the column is left out when there are neither. In the page's right
/// margin: each comment as a card level with its words, with a reply box, Resolve and Delete (a ghost's: Re-pin and Remove). It is
/// the same block on the same board: the words go to the board as you type, and Done (or ⌘↩, Esc) puts you back where you were.
/// Its colours follow the board: a white page on warm grey, or a dark page on a darker grey.
final class WritingViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    let session: WritingSession
    private let top = UIView()
    private let titleLabel = UILabel()
    private let count = UILabel()
    private let commentsButton = UIButton(configuration: .gray())
    private let draftsButton = UIButton(configuration: .gray())
    private let outlineButton = UIButton(configuration: .gray())
    private var backButton: UIButton?
    private var historyButton: UIButton?
    /// Below this the view is phone-sized: narrow margins, icon-only buttons (BoardBar.compactWidth's cut-off).
    private static let compactWidth: CGFloat = 560
    private let page = UIView()
    private let side = UITableView(frame: .zero, style: .grouped)
    private let cards = UIView()
    private var headings: [(title: String, level: Int, at: Int)] = []
    private var comments: [BoardItem] = []
    private var sideWidth: NSLayoutConstraint?
    private var pageWidth: NSLayoutConstraint?
    private static let margin: CGFloat = 64
    private static let cardWidth: CGFloat = 250
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
        view.backgroundColor = dark ? UIColor(red: 0x12 / 255, green: 0x12 / 255, blue: 0x14 / 255, alpha: 1)
            : UIColor(red: 0xF1 / 255, green: 0xF0 / 255, blue: 0xEC / 255, alpha: 1)

        // the top bar
        top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        var back = UIButton.Configuration.plain()
        back.image = UIImage(systemName: "chevron.left")
        back.title = "Board"
        back.imagePadding = 4
        let backButton = UIButton(configuration: back, primaryAction: UIAction { [weak self] _ in self?.close() })
        self.backButton = backButton
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        count.textColor = .secondaryLabel
        var historyConf = UIButton.Configuration.plain()
        historyConf.image = UIImage(systemName: "clock.arrow.circlepath")
        historyConf.title = "History"
        historyConf.imagePadding = 4
        let historyButton = UIButton(configuration: historyConf, primaryAction: UIAction { [weak self] _ in self?.openHistory() })
        self.historyButton = historyButton
        // where the left column doesn't fit (portrait, split view, iPhone): the outline and comments as a menu
        outlineButton.configuration?.image = UIImage(systemName: "list.bullet.indent")
        outlineButton.showsMenuAsPrimaryAction = true
        outlineButton.accessibilityLabel = "Outline"
        outlineButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.outlineMenu() ?? []) }])
        commentsButton.addAction(UIAction { [weak self] _ in self?.toggleComments() }, for: .touchUpInside)
        draftsButton.configuration?.image = UIImage(systemName: "square.stack")
        draftsButton.showsMenuAsPrimaryAction = true
        draftsButton.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
            guard let self, let b = self.board else { done([]); return }
            done(b.draftMenu(self.session.id))
        }])
        let done = UIButton(configuration: .filled(), primaryAction: UIAction { [weak self] _ in self?.close() })
        done.configuration?.title = "Done"
        let left = UIStackView(arrangedSubviews: [backButton, titleLabel])
        left.spacing = 8
        left.alignment = .center
        let right = UIStackView(arrangedSubviews: [count, outlineButton, commentsButton, historyButton, draftsButton, done])
        right.spacing = 10
        right.alignment = .center
        for v in [left, right] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; top.addSubview(v) }
        let rule = UIView()
        rule.backgroundColor = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(rule)

        // the page
        page.translatesAutoresizingMaskIntoConstraints = false
        page.backgroundColor = dark ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1) : .white
        if let fill = session.look.fill { page.backgroundColor = fill }
        page.layer.cornerRadius = 8
        page.layer.shadowColor = UIColor.black.cgColor
        page.layer.shadowOpacity = dark ? 0 : 0.06
        page.layer.shadowRadius = 12
        page.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.addSubview(page)
        // the words: the laptop's editor in a web view (the page's padding is the margins), or the plain text view
        let tv = session.editorView
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.transform = .identity
        if let r = session.rich {
            session.pageInsets = UIEdgeInsets(top: 56, left: Self.margin, bottom: 280, right: Self.margin)
            r.web.scrollView.alwaysBounceVertical = true
            r.web.scrollView.keyboardDismissMode = .none
        } else {
            session.textView.textContainerInset = UIEdgeInsets(top: 56, left: Self.margin, bottom: 280, right: Self.margin)
            session.textView.alwaysBounceVertical = true
        }
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

        // comment cards in the page's right margin (over the text view, which leaves the margin empty)
        cards.translatesAutoresizingMaskIntoConstraints = false
        cards.clipsToBounds = true
        page.addSubview(cards)

        let g = view.safeAreaLayoutGuide
        let pw = page.widthAnchor.constraint(equalToConstant: 780)
        pw.priority = .defaultHigh
        pageWidth = pw
        let sw = side.widthAnchor.constraint(equalToConstant: 230)
        sideWidth = sw
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
            page.trailingAnchor.constraint(lessThanOrEqualTo: g.trailingAnchor, constant: -16),
            pw, centred,
            cards.topAnchor.constraint(equalTo: page.topAnchor),
            cards.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            cards.trailingAnchor.constraint(equalTo: page.trailingAnchor, constant: -20),
            cards.widthAnchor.constraint(equalToConstant: Self.cardWidth),
            tv.topAnchor.constraint(equalTo: page.topAnchor),
            tv.bottomAnchor.constraint(equalTo: page.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: page.trailingAnchor),
        ])

        session.onDone = { [weak self] in self?.close() }
        session.restyle()
        let scroller: UIScrollView = session.rich?.web.scrollView ?? session.textView
        scrollWatch = scroller.observe(\.contentOffset) { [weak self] _, _ in DispatchQueue.main.async { self?.placeCards() } }
        refresh()
        // the outline, comments and count follow the words without redoing them on every key
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.refresh() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if session.rich != nil {
            session.openRich(caret: "end")
            session.focus()
            return
        }
        session.textView.becomeFirstResponder()
        session.textView.selectedRange = NSRange(location: (session.text as NSString).length, length: 0)
        session.keepCaretVisible()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // narrow screens (split view, portrait): the left column gives way to the page; cards need a page wide enough for a margin
        let w = view.bounds.width
        let compact = w < Self.compactWidth
        let showSide = w >= 900 && !(headings.isEmpty && comments.isEmpty)
        sideWidth?.constant = showSide ? 230 : 0
        side.isHidden = !showSide
        outlineButton.isHidden = showSide || (headings.isEmpty && comments.isEmpty)
        titleLabel.isHidden = compact
        count.isHidden = compact
        backButton?.configuration?.title = compact ? nil : "Board"
        historyButton?.configuration?.title = compact ? nil : "History"
        let margin = compact ? 20 : Self.margin
        let showCards = (board?.marksShown ?? true) && !comments.isEmpty && w >= 1000
        let right = showCards ? Self.cardWidth + 40 : margin
        pageWidth?.constant = showCards ? 780 + right - Self.margin : 780
        let inset = UIEdgeInsets(top: compact ? 24 : 56, left: margin, bottom: 280, right: right)
        if session.rich != nil {
            if session.pageInsets != inset { session.pageInsets = inset; session.restyle() }
        } else if session.textView.textContainerInset != inset {
            session.textView.textContainerInset = inset
        }
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
        let caret = session.selectedRange.location
        let here = hs.lastIndex { $0.at <= caret } ?? -1
        let changed = hs.map(\.title) != headings.map(\.title) || hs.map(\.at) != headings.map(\.at)
            || list.map(\.json) != comments.map(\.json) || here != lastCaretHeading
        headings = hs
        comments = list
        lastCaretHeading = here
        if changed { side.reloadData(); buildCards() }
        let c = LiveMarkdown.count(text)
        count.text = "\(c.words) words"
        titleLabel.text = [board?.boardName ?? "", hs.first?.title ?? firstLine(text)].filter { !$0.isEmpty }.joined(separator: " › ")
        let shown = board?.marksShown ?? true
        commentsButton.configuration = shown && !list.isEmpty ? .filled() : .gray()
        commentsButton.configuration?.image = UIImage(systemName: shown ? "text.bubble.fill" : "text.bubble")
        let compact = view.bounds.width < Self.compactWidth
        commentsButton.configuration?.title = compact ? (list.isEmpty ? nil : "\(list.count)") : (list.isEmpty ? "Comments" : "Comments \(list.count)")
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
        session.unfocus()
        let board = session.board
        let s = session
        dismiss(animated: true) { board?.finish(s) }
    }

    // MARK: comments

    /// The board's history player: the writing view closes first (it is the board's history, not the block's).
    private func openHistory() {
        let b = board
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { b?.openHistory() }
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
        if session.rich != nil {
            // the page puts the selection in view itself
            session.selectedRange = r
            session.restyle()
            return
        }
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
            r.numberOfLines = 8
            r.text = replies.map { "\($0.by): \($0.text ?? "(written)")" }.joined(separator: "\n")
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
            let ghost = range(of: m) == nil
            if !ghost {
                let field = UITextField()
                field.placeholder = "Reply"
                field.font = .systemFont(ofSize: 14)
                field.borderStyle = .roundedRect
                field.returnKeyType = .send
                field.addAction(UIAction { [weak self, weak field] _ in
                    guard let self, let b = self.board, let t = field?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return }
                    b.changeMark(id, "Reply") { BoardMarks.reply($0, text: t, by: b.deviceName) }
                    field?.text = ""
                    self.rebuildSoon()
                }, for: .editingDidEndOnExit)
                rows.append(field)
            }
            let actions = UIStackView(arrangedSubviews: ghost ? [
                link("Re-pin") { [weak self] in self?.board?.repin(id); self?.rebuildSoon() },
                link("Remove") { [weak self] in self?.board?.changeMark(id, "Remove comment") { _ in nil }; self?.rebuildSoon() },
                UIView(),
            ] : [
                link("Resolve") { [weak self] in self?.board?.changeMark(id, "Resolve") { $0.with("done", .bool(true)) }; self?.rebuildSoon() },
                link("Delete") { [weak self] in self?.board?.changeMark(id, "Delete comment") { _ in nil }; self?.rebuildSoon() },
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

    /// After a card's action: the list and cards again, once the change is in.
    private func rebuildSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.comments = []
            self.refresh()
            self.session.restyle()
        }
    }

    @objc private func cardTapped(_ g: UITapGestureRecognizer) {
        guard let id = g.view?.accessibilityIdentifier, let m = comments.first(where: { $0.id == id }) else { return }
        if let r = range(of: m) { go(to: r) } else { board?.openMark(id) }
    }

    /// Each card beside its words' line, pushed down so none overlap.
    private func placeCards() {
        guard !cards.isHidden, cards.bounds.width > 0 else { return }
        if let r = session.rich {
            // where each comment's words are in the page, asked of the page (page points, not scrolled)
            let list = cardViews.map { c in comments.first { $0.id == c.id }.flatMap { range(of: $0) } ?? NSRange(location: NSNotFound, length: 0) }
            let asked = list.filter { $0.location != NSNotFound }
            r.rects(asked) { [weak self] rects in
                guard let self else { return }
                var k = 0
                let tops: [CGFloat?] = list.map { l in
                    guard l.location != NSNotFound else { return nil }
                    defer { k += 1 }
                    return rects[k].map { $0.minY - r.web.scrollView.contentOffset.y - 4 }
                }
                self.stackCards(tops)
            }
            return
        }
        let tv = session.textView
        let lm = tv.layoutManager
        var y: CGFloat = 0
        for (id, v) in cardViews {
            guard let m = comments.first(where: { $0.id == id }) else { continue }
            var want: CGFloat = y
            if let r = range(of: m), NSMaxRange(r) <= (session.text as NSString).length {
                let rect = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: NSRange(location: r.location, length: max(1, r.length)), actualCharacterRange: nil), in: tv.textContainer)
                want = rect.minY + tv.textContainerInset.top - tv.contentOffset.y - 4
            }
            let size = v.systemLayoutSizeFitting(CGSize(width: cards.bounds.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            let at = max(want, y)
            v.frame = CGRect(x: 0, y: at, width: cards.bounds.width, height: size.height)
            y = at + size.height + 10
        }
    }

    /// The cards at these heights (nil: under the one before), pushed down so none overlap.
    private func stackCards(_ tops: [CGFloat?]) {
        var y: CGFloat = 0
        for (k, c) in cardViews.enumerated() {
            let v = c.view
            let size = v.systemLayoutSizeFitting(CGSize(width: cards.bounds.width, height: 0), withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel)
            let at = max((k < tops.count ? tops[k] : nil) ?? y, y)
            v.frame = CGRect(x: 0, y: at, width: cards.bounds.width, height: size.height)
            y = at + size.height + 10
        }
    }

    // MARK: the outline and the comments list

    /// The left column as a menu, for widths it doesn't fit.
    private func outlineMenu() -> [UIMenuElement] {
        let outline = headings.enumerated().map { k, h in
            UIAction(title: String(repeating: "   ", count: max(0, h.level - 1)) + h.title, state: k == lastCaretHeading ? .on : .off) { [weak self] _ in
                self?.go(to: NSRange(location: h.at, length: 0))
            }
        }
        let marks = comments.map { m in
            UIAction(title: "“" + (BoardMarks.anchor(m)?.q ?? (m.string("text") ?? "")) + "”", image: UIImage(systemName: "text.bubble")) { [weak self] _ in
                guard let self else { return }
                if let r = self.range(of: m) { self.go(to: r) } else { self.board?.openMark(m.id) }
            }
        }
        var out: [UIMenuElement] = []
        if !outline.isEmpty { out.append(UIMenu(title: "Outline", options: .displayInline, children: outline)) }
        if !marks.isEmpty { out.append(UIMenu(title: "Comments", options: .displayInline, children: marks)) }
        return out
    }

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
            b.writing?.selectedRange = hit.range
        }
    }
}
