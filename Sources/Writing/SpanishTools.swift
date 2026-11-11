import UIKit
import NexusCore

/// Spanish blocks (`lang: "es"`, or words that read as Spanish): a row of á é í ó ú ñ ü ¿ ¡, a Spanish keyboard when one is set up,
/// Check Spanish (the iPad's own Spanish dictionary, offline: each word it doesn't know, with its guesses; a fix goes in as a Review
/// suggestion so you see what changed), and Practice mode (a timer, and every check off until it ends).
extension BoardController {
    func spanishMenu(_ id: String) -> [UIMenuElement] {
        guard let it = content.items.first(where: { $0.id == id }) else { return [] }
        let lang = it.string("lang")
        let practicing = Practice.isOn(it)
        var out: [UIMenuElement] = [
            UIMenu(title: "Language", image: UIImage(systemName: "globe"), children: [
                UIAction(title: "Detect", subtitle: BlockFacts.lang(nil, content.texts[shownKey(id)] ?? "") == "es" ? "Reads as Spanish" : nil,
                         state: lang == nil ? .on : .off) { [weak self] _ in self?.setBlockField(id, "lang", nil) },
                UIAction(title: "English", state: lang == "en" ? .on : .off) { [weak self] _ in self?.setBlockField(id, "lang", .string("en")) },
                UIAction(title: "Spanish", state: lang == "es" ? .on : .off) { [weak self] _ in self?.setBlockField(id, "lang", .string("es")) },
            ]),
            UIAction(title: "Check Spanish", image: UIImage(systemName: "checkmark.seal"), attributes: practicing ? .disabled : []) { [weak self] _ in
                self?.openSpanishCheck(id)
            },
        ]
        if practicing {
            out.append(UIAction(title: "End practice", image: UIImage(systemName: "stop.circle")) { [weak self] _ in self?.endPractice(id) })
        } else {
            out.append(UIMenu(title: "Practice mode", subtitle: "No checks, with a timer", image: UIImage(systemName: "timer"), children: [15, 30, 45, 60, 90].map { m in
                UIAction(title: "\(m) minutes") { [weak self] _ in self?.startPractice(id, minutes: Double(m)) }
            }))
        }
        return out
    }

    func startPractice(_ id: String, minutes: Double) {
        setBlockField(id, "practice", Practice.field(minutes: minutes))
        tell("Practice: \(Int(minutes)) minutes. Spelling, autocorrect and Writing Tools are off until it ends.", brief: true)
    }

    func endPractice(_ id: String) {
        setBlockField(id, "practice", nil)
    }

    /// The practice timer ran out: say so, and offer to end it (the words are checked again then).
    func practiceOver(_ id: String) {
        let a = UIAlertController(title: "Time's up", message: "Your practice time is over. End practice to turn the checks back on, or keep going.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "End practice", style: .default) { [weak self] _ in self?.endPractice(id) })
        a.addAction(UIAlertAction(title: "Keep going", style: .cancel))
        presentOver(a)
    }

    func openSpanishCheck(_ id: String) {
        commitTyping(id)
        let vc = SpanishCheckController(board: self, id: id)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        presentOver(nav)
    }

    /// Puts a correction into a block's words: as a Review suggestion ({~~old~>new~~}) or straight in.
    func correct(_ id: String, range: NSRange, with fix: String, asSuggestion: Bool) {
        let key = shownKey(id)
        if blockLocked(id) { tellLocked(id); return }
        if let w = session(for: id), w.key == key {
            let s = w.text as NSString
            guard NSMaxRange(range) <= s.length else { return }
            let old = s.substring(with: range)
            let put = asSuggestion ? "{~~\(old)~>\(fix)~~}" : fix
            w.apply(MDEdit(s.replacingCharacters(in: range, with: put), NSRange(location: range.location + (put as NSString).length, length: 0)))
            return
        }
        let md = (content.texts[key] ?? "") as NSString
        guard NSMaxRange(range) <= md.length else { return }
        let old = md.substring(with: range)
        let put = asSuggestion ? "{~~\(old)~>\(fix)~~}" : fix
        changeItems("Correct") { $0.texts[key] = md.replacingCharacters(in: range, with: put) }
    }
}

/// Check Spanish: the words the iPad's Spanish dictionary doesn't know, each with its guesses. Tap a guess to fix the word.
final class SpanishCheckController: UITableViewController {
    weak var board: BoardController?
    let id: String
    private var issues: [(range: NSRange, word: String, guesses: [String])] = []
    private var asSuggestions = true
    private let language: String?

    init(board: BoardController, id: String) {
        self.board = board
        self.id = id
        language = UITextChecker.availableLanguages.first { $0 == "es_ES" } ?? UITextChecker.availableLanguages.first { $0.hasPrefix("es") }
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Check Spanish"
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        reload()
    }

    private var words: String { board.map { $0.content.texts[$0.shownKey(id)] ?? "" } ?? "" }

    /// The words to leave alone: markdown marks, code, maths, links' targets, and suggestions already made.
    static func skipped(_ md: String) -> [NSRange] {
        var out: [NSRange] = []
        for line in LiveMarkdown.parse(md) {
            for m in line.marks { out.append(m.range) }
            for sp in line.spans {
                switch sp.kind {
                case .code, .math, .link, .wikilink, .nexusTask, .added, .deleted: out.append(sp.range)
                default: break
                }
            }
            if case .code = line.kind { out.append(line.range) }
            if case .fence = line.kind { out.append(line.range) }
        }
        return out
    }

    private func reload() {
        issues = []
        guard let language else { tableView.reloadData(); return }
        let md = words
        let ns = md as NSString
        let skip = SpanishCheckController.skipped(md)
        let checker = UITextChecker()
        var at = 0
        while at < ns.length {
            let r = checker.rangeOfMisspelledWord(in: md, range: NSRange(location: 0, length: ns.length), startingAt: at, wrap: false, language: language)
            guard r.location != NSNotFound else { break }
            at = NSMaxRange(r)
            if skip.contains(where: { NSIntersectionRange($0, r).length > 0 }) { continue }
            let guesses = checker.guesses(forWordRange: r, in: md, language: language) ?? []
            issues.append((r, ns.substring(with: r), Array(guesses.prefix(5))))
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 + max(issues.count, 1) }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 { return 1 }
        if issues.isEmpty { return 1 }
        return max(1, issues[section - 1].guesses.count)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section > 0, !issues.isEmpty else { return nil }
        return "“\(issues[section - 1].word)”"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var c = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            c.text = "Show fixes as suggestions"
            c.secondaryText = "So you can see what changed, and accept or reject it in Review"
            let sw = UISwitch()
            sw.isOn = asSuggestions
            sw.addAction(UIAction { [weak self] a in self?.asSuggestions = (a.sender as? UISwitch)?.isOn ?? true }, for: .valueChanged)
            cell.accessoryView = sw
            cell.selectionStyle = .none
        } else if language == nil {
            c.text = "The Spanish dictionary isn't on this iPad"
            c.secondaryText = "Add a Spanish keyboard in Settings › General › Keyboard to get it."
            cell.selectionStyle = .none
        } else if issues.isEmpty {
            c.text = "No spelling mistakes found"
            c.image = UIImage(systemName: "checkmark.circle")
            cell.selectionStyle = .none
        } else {
            let issue = issues[indexPath.section - 1]
            if issue.guesses.isEmpty {
                c.text = "No suggestions"
                c.textProperties.color = .secondaryLabel
                cell.selectionStyle = .none
            } else {
                c.text = issue.guesses[indexPath.row]
                c.image = UIImage(systemName: "arrow.turn.down.right")
            }
        }
        cell.contentConfiguration = c
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section > 0, indexPath.section - 1 < issues.count, let b = board else { return }
        let issue = issues[indexPath.section - 1]
        guard indexPath.row < issue.guesses.count else { return }
        b.correct(id, range: issue.range, with: issue.guesses[indexPath.row], asSuggestion: asSuggestions)
        reload()
    }
}
