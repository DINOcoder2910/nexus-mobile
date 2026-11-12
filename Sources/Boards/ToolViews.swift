import UIKit
import WebKit
import NexusCore

/// One tool page in a web view (nexus docs/data-format.md "Tools on the board"). The page's text is read from the data folder and
/// loaded as a string, so it has no file access at all; requests to the internet are blocked by a content rule, every navigation away
/// from the page is cancelled, nothing is stored (a non-persistent data store) and no window can open. The page talks only through
/// postMessage: a script set before it runs marks this as its host (`window.__nexusHost`) and passes its messages on to the app.
final class ToolPage: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let web: WKWebView
    /// What the page starts with, then what it last handed back.
    private(set) var state: JSONValue?
    var dark = false
    var onState: ((JSONValue) -> Void)?
    private(set) var loaded: URL?
    private var sentInit = false

    static let bridge = """
    window.__nexusHost = true;
    window.addEventListener('message', function (e) {
      var d = e.data;
      if (!d || d.nexus !== 'tool' || d.type === 'init' || d.type === 'theme') return;
      try { window.webkit.messageHandlers.nexusTool.postMessage(JSON.stringify(d)); } catch (x) {}
    });
    """
    /// WebKit's content rules take one pattern per trigger (no alternation).
    static let rulesJSON = """
    [{"trigger":{"url-filter":"^https?:"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^wss?:"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"^ftp:"},"action":{"type":"block"}}]
    """
    private static var rules: WKContentRuleList?
    private static var compiling: [(WKContentRuleList?) -> Void]?

    /// The compiled rules (once per launch), then `go`.
    static func withRules(_ go: @escaping (WKContentRuleList?) -> Void) {
        if let rules { go(rules); return }
        if compiling != nil { compiling?.append(go); return }
        compiling = [go]
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "nexus-tool-offline", encodedContentRuleList: rulesJSON) { list, _ in
            DispatchQueue.main.async {
                ToolPage.rules = list
                let waiting = ToolPage.compiling ?? []
                ToolPage.compiling = nil
                for w in waiting { w(list) }
            }
        }
    }

    init(interactive: Bool) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        cfg.allowsInlineMediaPlayback = true
        cfg.dataDetectorTypes = []
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: ToolPage.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        cfg.userContentController = ucc
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        ucc.add(WeakMessageHandler(self), name: "nexusTool")
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = .white
        web.scrollView.backgroundColor = .white
        web.isUserInteractionEnabled = interactive
        web.scrollView.isScrollEnabled = interactive
        web.allowsLinkPreview = false
    }

    deinit { web.configuration.userContentController.removeScriptMessageHandler(forName: "nexusTool") }

    /// Shows the page at `url` (a file in the data folder) started with `state`. False when the file can't be read.
    @discardableResult
    func load(_ url: URL, state: JSONValue?) -> Bool {
        guard let html = try? FolderAccess.read(url) else { return false }
        loaded = url
        self.state = state
        sentInit = false
        ToolPage.withRules { [weak self] list in
            guard let self, self.loaded == url else { return }
            let ucc = self.web.configuration.userContentController
            ucc.removeAllContentRuleLists()
            if let list { ucc.add(list) }
            self.web.loadHTMLString(html, baseURL: nil)
        }
        return true
    }

    /// A picture of what the page shows now.
    func snapshot(_ done: @escaping (UIImage?) -> Void) {
        let c = WKSnapshotConfiguration()
        c.afterScreenUpdates = true
        web.takeSnapshot(with: c) { img, _ in done(img) }
    }

    private func sendInit() {
        guard !sentInit else { return }
        sentInit = true
        web.evaluateJavaScript(ToolCatalog.initScript(state: state, dark: dark), completionHandler: nil)
    }

    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let text = m.body as? String, let msg = ToolCatalog.message(text) else { return }
        switch msg {
        case .ready: sendInit()
        case .state(let s):
            guard s != state else { return }
            state = s
            onState?(s)
        case .size: break
        }
    }

    // a page that never says it is ready (an .html that isn't a Nexus tool) still gets its init
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sendInit() }

    // the page itself (loaded from a string, so about:blank) and nothing else: no links, no other pages
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        let s = action.request.url?.absoluteString ?? ""
        decisionHandler(s == "about:blank" || s.hasPrefix("about:srcdoc") ? .allow : .cancel)
    }
}

/// WKUserContentController keeps its handlers alive; this keeps the page's free to go.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

/// A tool card on the board, drawn as the laptop's: a head with the tool's name, then the tool live (shown, not used: the Pencil's
/// canvas lies over the board, so a card is used in the Tools panel) or a picture of it. White in both themes, as the paper is.
final class ToolCardView: UIView {
    private let head = UIView()
    private let titleLabel = UILabel()
    private let hint = UILabel()
    private let body = UIView()
    private let picture = UIImageView()
    private let missing = UILabel()
    private(set) var page: ToolPage?
    private var key = ""
    /// The state the live page was started with (a tool may hand back a tidied one; that alone is no reason to start it again).
    private var shownState: JSONValue?
    /// While the card is open in the Tools panel it isn't reloaded for each state the panel writes; it is when the panel lets go.
    var holding = false

    static let paper = UIColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let headColor = UIColor(red: 0xF5 / 255.0, green: 0xF5 / 255.0, blue: 0xF3 / 255.0, alpha: 1)
    static let ink = UIColor(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1A / 255.0, alpha: 1)
    static let quiet = UIColor(red: 0x5C / 255.0, green: 0x5C / 255.0, blue: 0x56 / 255.0, alpha: 1)
    static let line = UIColor(red: 0xE6 / 255.0, green: 0xE6 / 255.0, blue: 0xE2 / 255.0, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = ToolCardView.paper
        layer.cornerRadius = 8
        layer.borderWidth = 1
        layer.borderColor = ToolCardView.line.cgColor
        clipsToBounds = true
        head.backgroundColor = ToolCardView.headColor
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = ToolCardView.ink
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = ToolCardView.quiet
        hint.textAlignment = .right
        head.addSubview(titleLabel)
        head.addSubview(hint)
        addSubview(head)
        body.clipsToBounds = true
        addSubview(body)
        picture.contentMode = .scaleAspectFit
        missing.font = .systemFont(ofSize: 13)
        missing.textColor = ToolCardView.quiet
        missing.textAlignment = .center
        missing.numberOfLines = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `pageURL`: the tool's page in the data folder; `imageURL`: its picture, for a picture card.
    func update(_ it: BoardItem, offset: CGPoint, pageURL: URL?, imageURL: URL?) {
        frame = boardBox(it).offsetBy(dx: offset.x, dy: offset.y)
        let hh = CGFloat(ToolCatalog.headHeight)
        head.frame = CGRect(x: 0, y: 0, width: bounds.width, height: hh)
        titleLabel.frame = CGRect(x: 10, y: 0, width: bounds.width * 0.6 - 10, height: hh)
        hint.frame = CGRect(x: bounds.width * 0.6, y: 0, width: bounds.width * 0.4 - 10, height: hh)
        body.frame = CGRect(x: 0, y: hh, width: bounds.width, height: max(0, bounds.height - hh))
        for v in body.subviews { v.frame = body.bounds }
        missing.frame = body.bounds.insetBy(dx: 16, dy: 16)

        let live = it.string("show") != "picture"
        let k = (live ? "live:" : "pic:") + (it.src ?? "") + (live ? "" : "|" + (it.string("image") ?? ""))
        let state = it.json["state"]
        if k == key {
            // what it shows changed elsewhere (another device, or the panel let go): show that
            if live, !holding, let page, shownState != state, let url = page.loaded {
                shownState = state
                page.load(url, state: state)
            }
            return
        }
        key = k
        titleLabel.text = ToolCatalog.title(it.src)
        hint.text = live ? "Tap twice to use" : "Picture"
        body.subviews.forEach { $0.removeFromSuperview() }
        page = nil
        if live {
            guard let pageURL, FileManager.default.fileExists(atPath: pageURL.path) else {
                if case .builtin = ToolCatalog.parseSrc(it.src) {
                    missing.text = "This tool comes from the laptop: it shows here once Nexus on the laptop has synced it."
                } else { missing.text = "This tool can't be found: " + (it.src ?? "") }
                body.addSubview(missing)
                key = "" // look again next time: sync may bring it
                return
            }
            let p = ToolPage(interactive: false)
            p.web.frame = body.bounds
            body.addSubview(p.web)
            if p.load(pageURL, state: state) { page = p; shownState = state } else {
                p.web.removeFromSuperview()
                missing.text = "This tool couldn't be read."
                body.addSubview(missing)
            }
        } else {
            picture.image = nil
            picture.frame = body.bounds
            body.addSubview(picture)
            guard let imageURL else { return }
            let want = it.string("image")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let img = UIImage(contentsOfFile: imageURL.path)
                DispatchQueue.main.async {
                    guard let self, self.key.hasSuffix("|" + (want ?? "")) else { return }
                    self.picture.image = img
                }
            }
        }
    }
}

/// The Tools panel: slides in from the right with the Study tools and the .html files in this notebook. A tool opens in it to be
/// used; "Put on the board" leaves a live card where you look, "Picture" a picture of what it shows now. A card opened from the
/// board ("Use") is bound to it: what you do in the panel is kept on the card.
final class ToolPanelController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    struct Row {
        var src: String
        var title: String
        var detail: String
        var ready: Bool
    }

    weak var board: BoardController?
    private let header = UIView()
    private let titleLabel = UILabel()
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let toolBar = UIStackView()
    private let backButton = UIButton(type: .system)
    private let nameLabel = UILabel()
    private let putButton = UIButton(type: .system)
    private let pictureButton = UIButton(type: .system)
    private let frameView = UIView()
    private var sections: [(title: String, rows: [Row], note: String?)] = []
    private(set) var page: ToolPage?
    private(set) var openSrc: String?
    /// The card this panel is using, when it was opened from the board.
    private(set) var cardId: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .systemGroupedBackground
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.15
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = CGSize(width: -2, height: 0)

        titleLabel.text = "Tools"
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.accessibilityLabel = "Close Tools"
        close.addAction(UIAction { [weak self] _ in self?.board?.closeToolPanel() }, for: .touchUpInside)
        header.addSubview(titleLabel)
        header.addSubview(close)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        close.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 36), close.heightAnchor.constraint(equalToConstant: 36),
        ])

        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")

        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addAction(UIAction { [weak self] _ in self?.showList() }, for: .touchUpInside)
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        putButton.configuration = .filled()
        putButton.configuration?.buttonSize = .small
        putButton.addAction(UIAction { [weak self] _ in self?.put(picture: false) }, for: .touchUpInside)
        pictureButton.configuration = .gray()
        pictureButton.configuration?.buttonSize = .small
        pictureButton.setTitle("Picture", for: .normal)
        pictureButton.addAction(UIAction { [weak self] _ in self?.put(picture: true) }, for: .touchUpInside)
        toolBar.axis = .horizontal
        toolBar.spacing = 8
        toolBar.alignment = .center
        toolBar.isLayoutMarginsRelativeArrangement = true
        toolBar.layoutMargins = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 12)
        for v in [backButton, nameLabel, putButton, pictureButton] { toolBar.addArrangedSubview(v) }
        frameView.backgroundColor = .white
        frameView.clipsToBounds = true

        for v in [header, table, toolBar, frameView] { view.addSubview(v) }
        toolBar.isHidden = true
        frameView.isHidden = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        header.frame = CGRect(x: 0, y: 0, width: w, height: 48)
        table.frame = CGRect(x: 0, y: 48, width: w, height: view.bounds.height - 48)
        toolBar.frame = CGRect(x: 0, y: 48, width: w, height: 44)
        frameView.frame = CGRect(x: 0, y: 92, width: w, height: max(0, view.bounds.height - 92))
        page?.web.frame = frameView.bounds
    }

    // MARK: the list

    /// The list again (letting go of a card it was using).
    func showList() {
        letGo()
        sections = rows()
        table.reloadData()
        table.isHidden = false
        toolBar.isHidden = true
        frameView.isHidden = true
    }

    private func rows() -> [(title: String, rows: [Row], note: String?)] {
        guard let b = board else { return [] }
        let fm = FileManager.default
        let have = ToolCatalog.readIndex(try? FolderAccess.read(b.root.appendingPathComponent(ToolCatalog.indexFile))) ?? []
        let study = ToolCatalog.tools.map { t -> Row in
            let ready = have.contains(t.name) || fm.fileExists(atPath: b.root.appendingPathComponent(ToolCatalog.builtinFile(t.name)).path)
            return Row(src: ToolCatalog.builtinSrc(t.name), title: t.title, detail: ready ? t.desc : "Comes from the laptop: open Nexus there to send it", ready: ready)
        }
        var files: [Row] = []
        for d in ToolCatalog.notebookDirs(boardPath: b.path) {
            let dir = d.isEmpty ? b.root : b.root.appendingPathComponent(d, isDirectory: true)
            let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            for n in names where n.range(of: #"\.html?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                let path = d.isEmpty ? n : d + "/" + n
                let src = ToolCatalog.relative(path, fromBoard: b.path)
                files.append(Row(src: src, title: ToolCatalog.title(src), detail: path, ready: true))
            }
        }
        return [
            ("Study tools", study, nil),
            ("In this notebook", files, files.isEmpty ? "An .html file in this notebook shows up here too, and runs the same way: offline, with no access to your files." : nil),
        ]
    }

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection s: Int) -> Int { sections[s].rows.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection s: Int) -> String? { sections[s].title }
    func tableView(_ tableView: UITableView, titleForFooterInSection s: Int) -> String? { sections[s].note }

    func tableView(_ tableView: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let r = sections[ip.section].rows[ip.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: ip)
        var c = cell.defaultContentConfiguration()
        c.text = r.title
        c.secondaryText = r.detail
        c.secondaryTextProperties.color = .secondaryLabel
        c.textProperties.color = r.ready ? .label : .secondaryLabel
        cell.contentConfiguration = c
        cell.accessoryType = r.ready ? .disclosureIndicator : .none
        cell.selectionStyle = r.ready ? .default : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt ip: IndexPath) {
        tableView.deselectRow(at: ip, animated: true)
        let r = sections[ip.section].rows[ip.row]
        guard r.ready else { return }
        open(r.src, state: nil, card: nil)
    }

    // MARK: a tool open in the panel

    /// Opens `src` here; with `card`, bound to that card on the board (its state is kept on the card as you use it).
    func open(_ src: String, state: JSONValue?, card: String?) {
        guard let b = board else { return }
        letGo()
        guard let url = ToolCatalog.pageURL(src, board: b.boardURL, root: b.root), FileManager.default.fileExists(atPath: url.path) else {
            b.tell("That tool can't be found.")
            return
        }
        let p = ToolPage(interactive: true)
        p.onState = { [weak self] s in
            guard let self, let id = self.cardId else { return }
            self.board?.keepToolState(id, s)
        }
        guard p.load(url, state: state) else { b.tell("That tool couldn't be read."); return }
        page?.web.removeFromSuperview()
        page = p
        openSrc = src
        cardId = card
        if let card { b.holdToolCard(card, true) }
        frameView.addSubview(p.web)
        p.web.frame = frameView.bounds
        nameLabel.text = ToolCatalog.title(src)
        backButton.setTitle(card == nil ? " All tools" : " Done", for: .normal)
        putButton.setTitle(card == nil ? "Put on the board" : "Put a copy", for: .normal)
        pictureButton.setTitle(card == nil ? "Picture" : "Show as a picture", for: .normal)
        table.isHidden = true
        toolBar.isHidden = false
        frameView.isHidden = false
    }

    /// Lets go of the card the panel was using, and closes the tool.
    func letGo() {
        if let id = cardId { board?.holdToolCard(id, false) }
        cardId = nil
        page?.web.removeFromSuperview()
        page = nil
        openSrc = nil
    }

    private func put(picture: Bool) {
        guard let b = board, let src = openSrc, let p = page else { return }
        if !picture { b.addToolCard(src, state: p.state, image: nil, size: nil); return }
        p.snapshot { [weak self] img in
            guard let self, let b = self.board else { return }
            guard let img, let png = img.pngData() else { b.tell("The picture could not be taken."); return }
            guard let image = b.saveToolPicture(png, title: ToolCatalog.title(src)) else { return }
            if let id = self.cardId {
                b.toolCardToPicture(id, image: image)
                self.showList()
            } else {
                b.addToolCard(src, state: p.state, image: image, size: CGSize(width: img.size.width, height: img.size.height))
            }
        }
    }
}
