import UIKit
import NexusCore

/// "Add a Nexus task" from typed words (never automatic: a checkbox stays a checkbox). The title starts as the chosen words; pick
/// where it goes; nothing is added until Add. The words then become a task chip, `[title](nexus-task:<id>)`.
final class AddTaskSheet: UIViewController, UITextFieldDelegate {
    private let titleField = UITextField()
    private let whereButton = UIButton(configuration: .gray())
    private var workstream: String?
    private let choices: [(id: String?, name: String)]
    private let onAdd: (String, String?) -> Void

    init(title: String, choices: [(id: String?, name: String)], onAdd: @escaping (String, String?) -> Void) {
        self.choices = choices
        self.onAdd = onAdd
        super.init(nibName: nil, bundle: nil)
        titleField.text = title
        modalPresentationStyle = .formSheet
        preferredContentSize = CGSize(width: 440, height: 230)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let bar = UINavigationBar()
        let nav = UINavigationItem(title: "Add a Nexus task")
        nav.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let add = UIBarButtonItem(title: "Add", primaryAction: UIAction { [weak self] _ in self?.add() })
        add.style = .done
        nav.rightBarButtonItem = add
        bar.items = [nav]

        titleField.borderStyle = .roundedRect
        titleField.placeholder = "Task"
        titleField.clearButtonMode = .whileEditing
        titleField.returnKeyType = .done
        titleField.delegate = self
        titleField.addAction(UIAction { [weak self] _ in self?.refresh() }, for: .editingChanged)

        let label = UILabel()
        label.text = "Goes to"
        label.textColor = .secondaryLabel
        whereButton.showsMenuAsPrimaryAction = true
        whereButton.changesSelectionAsPrimaryAction = false
        whereButton.menu = UIMenu(children: choices.map { c in
            UIAction(title: c.name) { [weak self] _ in self?.workstream = c.id; self?.refresh() }
        })
        let row = UIStackView(arrangedSubviews: [label, whereButton])
        row.spacing = 10
        let note = UILabel()
        note.text = "The words become a link to the task. Ticking it in Nexus ticks it here too."
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [titleField, row, note])
        stack.axis = .vertical
        stack.spacing = 14
        for v in [bar, stack] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        titleField.becomeFirstResponder()
    }

    private var cleanTitle: String { (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    private func refresh() {
        var c = whereButton.configuration
        c?.title = choices.first { $0.id == workstream }?.name ?? "Inbox"
        whereButton.configuration = c
        navigationItemAdd?.isEnabled = !cleanTitle.isEmpty
    }

    private var navigationItemAdd: UIBarButtonItem? {
        (view.subviews.first { $0 is UINavigationBar } as? UINavigationBar)?.items?.first?.rightBarButtonItem
    }

    private func add() {
        guard !cleanTitle.isEmpty else { return }
        let t = cleanTitle, w = workstream, done = onAdd
        dismiss(animated: true) { done(t, w) }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        add()
        return false
    }
}

extension BoardController {
    /// Add a Nexus task from words of a block (its edit menu): the careful sheet, then the words become the task's chip.
    func addNexusTask(from blockId: String, range: NSRange) {
        guard let store, !readOnly else {
            tell("Tasks can be added from a board in the data folder.", brief: true)
            return
        }
        commitTyping(blockId)
        let key = shownKey(blockId)
        let md = content.texts[key] ?? ""
        let s = md as NSString
        var r = NSIntersectionRange(range, NSRange(location: 0, length: s.length))
        if r.length == 0 {
            // nothing chosen: the line the caret is on, without its list mark
            let line = s.lineRange(for: NSRange(location: min(r.location, max(0, s.length - 1)), length: 0))
            let text = s.substring(with: line)
            let lead = MarkdownEdit.listPrefix(text)
            r = NSRange(location: line.location + lead, length: max(0, line.length - lead - (text.hasSuffix("\n") ? 1 : 0)))
        }
        let words = LiveMarkdown.visibleText(s.substring(with: r)).trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = store.snapshot.groups.sorted { $0.order < $1.order }
        var choices: [(id: String?, name: String)] = [(nil, "Inbox")]
        for g in groups {
            for wid in g.workstreams {
                guard let w = store.snapshot.workstreams[wid], !w.parked, !w.finished else { continue }
                choices.append((w.id, w.name))
            }
        }
        let sheet = AddTaskSheet(title: words, choices: choices) { [weak self, weak store] title, ws in
            guard let self, let store, let id = store.add(title: title, workstream: ws) else { return }
            let chip = "[\(title.replacingOccurrences(of: "]", with: ")"))](nexus-task:\(id))"
            if let w = self.session(for: blockId), w.key == key {
                let now = w.text as NSString
                let rr = NSIntersectionRange(r, NSRange(location: 0, length: now.length))
                w.apply(MDEdit(now.replacingCharacters(in: rr, with: chip), NSRange(location: rr.location + (chip as NSString).length, length: 0)))
            } else {
                let next = s.replacingCharacters(in: r, with: chip)
                self.changeItems("Add a Nexus task") { $0.texts[key] = next }
            }
            self.tell("Added “\(title)” to \(choices.first { $0.id == ws }?.name ?? "Inbox").", brief: true)
        }
        presentOver(sheet)
    }
}
