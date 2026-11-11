import UIKit
import PencilKit
import NexusCore

/// A comment's bubble on the board: yellow when open, grey when done, dashed and faint as a ghost (its words are gone).
final class MarkView: UIView {
    static let size: CGFloat = 22
    private let icon = UIImageView()
    private let dash = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: MarkView.size, height: MarkView.size))
        icon.frame = bounds.insetBy(dx: 2, dy: 2)
        icon.contentMode = .scaleAspectFit
        addSubview(icon)
        dash.fillColor = nil
        dash.lineWidth = 1
        dash.lineDashPattern = [3, 2]
        layer.addSublayer(dash)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(_ m: BoardItem, ghost: Bool) {
        frame.size = CGSize(width: MarkView.size, height: MarkView.size)
        let done = BoardMarks.isDone(m)
        let handwritten = m.json["strokes"]?.array?.isEmpty == false
        icon.image = UIImage(systemName: handwritten ? "pencil.and.scribble" : (done ? "checkmark.bubble.fill" : "text.bubble.fill"))
        icon.tintColor = done ? UIColor.systemGray : UIColor(red: 0.95, green: 0.68, blue: 0.05, alpha: 1)
        alpha = ghost ? 0.55 : 1
        dash.path = ghost ? UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 5).cgPath : nil
        dash.strokeColor = UIColor.secondaryLabel.cgColor
        accessibilityLabel = ghost ? "Comment whose words are gone" : "Comment"
    }
}

/// One comment: the words it sits on, what it says (typed, or handwritten with the Pencil), replies, Done and Delete.
/// A ghost offers Re-pin (to the line where it waits) and Remove. Ink attached to text offers Detach.
final class MarkController: UIViewController, UITextViewDelegate {
    weak var board: BoardController?
    let id: String
    let isNew: Bool
    private let quote = UILabel()
    private let textView = UITextView()
    private let canvas = PKCanvasView()
    private let modeControl = UISegmentedControl(items: ["Type", "Write"])
    private let repliesLabel = UILabel()
    private let replyField = UITextField()
    private var startText = ""
    private var startDrawing = PKDrawing()

    init(board: BoardController, id: String, new: Bool) {
        self.board = board
        self.id = id
        self.isNew = new
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var mark: BoardItem? { board?.content.items.first { $0.id == id } }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        guard let m = mark, let b = board else { return }
        let ghost = b.markSpot(m).ghost
        let ink = BoardMarks.kind(m) == "ink"

        quote.numberOfLines = 3
        quote.font = .preferredFont(forTextStyle: .footnote)
        quote.textColor = .secondaryLabel
        if let at = BoardMarks.anchor(m) {
            quote.text = ghost ? "Its words are gone: “\(at.q)”" : "On “\(at.q)”"
        } else {
            quote.text = "Pinned to the board"
        }

        textView.font = .preferredFont(forTextStyle: .body)
        textView.text = m.string("text") ?? ""
        textView.delegate = self
        textView.layer.cornerRadius = 8
        textView.backgroundColor = .secondarySystemBackground
        textView.isEditable = !b.readOnly
        startText = textView.text

        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 2)
        canvas.backgroundColor = .secondarySystemBackground
        canvas.layer.cornerRadius = 8
        canvas.isOpaque = false
        let strokes = BoardMarks.strokes(m, absolute: false).flatMap { InkConvert.pkStrokes($0, offset: .zero) }
        canvas.drawing = PKDrawing(strokes: strokes)
        startDrawing = canvas.drawing
        canvas.isUserInteractionEnabled = !b.readOnly
        modeControl.selectedSegmentIndex = strokes.isEmpty ? 0 : 1
        modeControl.addAction(UIAction { [weak self] _ in self?.showMode() }, for: .valueChanged)

        repliesLabel.numberOfLines = 0
        repliesLabel.font = .preferredFont(forTextStyle: .subheadline)
        let replies = BoardMarks.replies(m)
        repliesLabel.text = replies.map { "\($0.by): \($0.text ?? "(handwritten)")" }.joined(separator: "\n")
        repliesLabel.isHidden = replies.isEmpty
        replyField.placeholder = "Reply"
        replyField.borderStyle = .roundedRect
        replyField.returnKeyType = .send
        replyField.addAction(UIAction { [weak self] _ in self?.sendReply() }, for: .editingDidEndOnExit)

        var actions: [UIView] = []
        func button(_ title: String, _ image: String, destructive: Bool = false, _ act: @escaping () -> Void) -> UIButton {
            var c = UIButton.Configuration.bordered()
            c.title = title
            c.image = UIImage(systemName: image)
            c.imagePadding = 4
            c.buttonSize = .small
            if destructive { c.baseForegroundColor = .systemRed }
            return UIButton(configuration: c, primaryAction: UIAction { _ in act() })
        }
        if !b.readOnly {
            if ghost {
                actions.append(button("Re-pin", "pin") { [weak self] in self?.close { b.repin($0) } })
                actions.append(button("Remove", "trash", destructive: true) { [weak self] in self?.close { b.changeMark($0, "Remove comment") { _ in nil } } })
            } else if ink {
                actions.append(button("Detach from text", "link.badge.plus") { [weak self] in self?.close { b.detachInk($0) } })
            } else {
                let done = BoardMarks.isDone(m)
                actions.append(button(done ? "Reopen" : "Done", done ? "arrow.uturn.backward" : "checkmark") { [weak self] in
                    self?.close { b.changeMark($0, done ? "Reopen comment" : "Resolve comment") { $0.with("done", .bool(!done)) } }
                })
                actions.append(button("Delete", "trash", destructive: true) { [weak self] in self?.close { b.changeMark($0, "Delete comment") { _ in nil } } })
            }
        }
        let actionRow = UIStackView(arrangedSubviews: actions + [UIView()])
        actionRow.spacing = 8

        let stack = UIStackView(arrangedSubviews: ink ? [quote, actionRow] : [quote, modeControl, textView, canvas, repliesLabel, replyField, actionRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            textView.heightAnchor.constraint(equalToConstant: 110),
            canvas.heightAnchor.constraint(equalToConstant: 140),
        ])
        modeControl.isHidden = b.readOnly
        replyField.isHidden = b.readOnly || isNew
        showMode()
    }

    private func showMode() {
        let write = modeControl.selectedSegmentIndex == 1
        textView.isHidden = write
        canvas.isHidden = !write
        if isNew, !write { textView.becomeFirstResponder() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew, modeControl.selectedSegmentIndex == 0 { textView.becomeFirstResponder() }
    }

    /// Closing saves what was typed or written; a new comment left empty goes.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard !closing else { return }
        save()
    }

    private var closing = false

    private func close(_ then: @escaping (String) -> Void) {
        save()
        closing = true
        let id = self.id
        dismiss(animated: true) { then(id) }
    }

    private func save() {
        guard let b = board, let m = mark, !b.readOnly, BoardMarks.kind(m) == "bubble" else { return }
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let drawing = canvas.drawing
        let empty = text.isEmpty && drawing.strokes.isEmpty && BoardMarks.replies(m).isEmpty
        if empty, isNew {
            // nothing said: the new comment goes, and so does its undo step
            b.content.items.removeAll { $0.id == id }
            b.canvas.undoManager?.undo()
            b.rebuildItems()
            b.changed()
            return
        }
        guard text != startText.trimmingCharacters(in: .whitespacesAndNewlines) || drawing != startDrawing else { return }
        var strokes: [BoardStroke] = []
        var taken = Set<String>()
        for k in drawing.strokes {
            let sid = BoardFormat.newId(taken: taken); taken.insert(sid)
            var s = InkConvert.boardStroke(k, offset: .zero, id: sid)
            s.points = s.points.map { p in var q = p; if q.count >= 2 { q[0] += m.x; q[1] += m.y }; return q }
            strokes.append(s)
        }
        let made = BoardMarks.make(id: m.id, kind: "bubble", on: BoardMarks.on(m), at: BoardMarks.anchor(m), x: m.x, y: m.y,
                                   text: text, strokes: strokes.isEmpty ? nil : strokes, by: m.string("by") ?? b.deviceName)
        let id = self.id
        b.changeMark(id, "Comment") { old in
            var next = old.with("text", .string(text))
            next = next.with("strokes", made.json["strokes"])
            return next
        }
        startText = text
        startDrawing = drawing
    }

    private func sendReply() {
        let t = (replyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let b = board else { return }
        b.changeMark(id, "Reply") { BoardMarks.reply($0, text: t, by: b.deviceName) }
        replyField.text = ""
        let replies = mark.map(BoardMarks.replies) ?? []
        repliesLabel.text = replies.map { "\($0.by): \($0.text ?? "(handwritten)")" }.joined(separator: "\n")
        repliesLabel.isHidden = replies.isEmpty
    }
}

/// Every comment on the board, in reading order, open ones first: tap one to go to it. Show or hide them all from here.
final class CommentsListController: UITableViewController {
    weak var board: BoardController?
    private var rows: [BoardItem] = []

    init(board: BoardController) {
        self.board = board
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Comments"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        reload()
    }

    private func reload() {
        guard let b = board else { return }
        rows = b.content.items.filter { BoardMarks.isMark($0) && BoardMarks.kind($0) == "bubble" }.sorted {
            let d0 = BoardMarks.isDone($0), d1 = BoardMarks.isDone($1)
            if d0 != d1 { return !d0 }
            let p0 = b.markSpot($0).point, p1 = b.markSpot($1).point
            return p0.y != p1.y ? p0.y < p1.y : p0.x < p1.x
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : max(rows.count, 1) }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        guard let b = board else { return cell }
        var c = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            c.text = "Show comments"
            let sw = UISwitch()
            sw.isOn = b.marksShown
            sw.addAction(UIAction { [weak b] a in b?.marksShown = (a.sender as? UISwitch)?.isOn ?? true }, for: .valueChanged)
            cell.accessoryView = sw
            cell.selectionStyle = .none
        } else if rows.isEmpty {
            c.text = "No comments yet"
            c.secondaryText = "Select words in a block and choose Comment."
            cell.selectionStyle = .none
        } else {
            let m = rows[indexPath.row]
            let text = m.string("text") ?? ""
            c.text = text.isEmpty ? (m.json["strokes"]?.array?.isEmpty == false ? "Handwritten comment" : "Empty comment") : text
            let quote = BoardMarks.anchor(m).map { "“\($0.q)”" } ?? "On the board"
            let ghost = b.markSpot(m).ghost
            c.secondaryText = [quote, ghost ? "words gone" : nil, BoardMarks.isDone(m) ? "done" : nil].compactMap { $0 }.joined(separator: " · ")
            c.image = UIImage(systemName: BoardMarks.isDone(m) ? "checkmark.bubble" : "text.bubble")
            c.textProperties.numberOfLines = 2
        }
        cell.contentConfiguration = c
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.section == 1, !rows.isEmpty, let b = board else { return }
        let id = rows[indexPath.row].id
        (navigationController ?? self).dismiss(animated: true) { b.goToMark(id) }
    }
}
