import UIKit
import NexusCore

/// The text view a block is typed in: TextKit 1 with MDLayoutManager, so marks hide as they do on the board. It keeps an undo of
/// its own while it is open (undo per block, as on the laptop); the board's undo gets one step for the whole typing when it closes.
final class BlockTextView: UITextView {
    private let ownUndo = UndoManager()
    override var undoManager: UndoManager? { ownUndo }
    weak var session: WritingSession?

    override var keyCommands: [UIKeyCommand]? {
        var out: [UIKeyCommand] = []
        func key(_ input: String, _ mods: UIKeyModifierFlags, _ action: String, _ title: String) {
            let k = UIKeyCommand(title: title, image: nil, action: #selector(nexusKey(_:)), input: input, modifierFlags: mods, propertyList: action)
            k.wantsPriorityOverSystemBehavior = true
            out.append(k)
        }
        key("b", .command, "bold", "Bold")
        key("i", .command, "italic", "Italic")
        key("u", .command, "underline", "Underline")
        key("x", [.command, .shift], "strike", "Strikethrough")
        key("h", [.command, .shift], "highlight", "Highlight")
        key("`", .command, "code", "Code")
        key("1", [.command, .shift], "title", "Title")
        key("1", .command, "h1", "Heading 1")
        key("2", .command, "h2", "Heading 2")
        key("3", .command, "h3", "Heading 3")
        key("0", .command, "body", "Body")
        key("7", [.command, .shift], "numbers", "Numbered list")
        key("8", [.command, .shift], "bullets", "Bulleted list")
        key("l", .command, "checklist", "Checklist")
        key(".", [.command, .shift], "quote", "Quote")
        key("k", .command, "link", "Link")
        key("\r", .command, "writing", "Writing view")
        key("f", .command, "find", "Find and replace")
        key(UIKeyCommand.inputEscape, [], "done", "Done")
        key("\t", [], "indent", "Indent")
        key("\t", .shift, "outdent", "Outdent")
        // Word's accent keys (the laptop's): a dead key, then the letter
        key("'", .command, "dead:acute", "Acute accent (then a vowel)")
        key("~", [.command, .shift], "dead:tilde", "Tilde (then n)")
        key("`", [.command, .shift], "dead:tilde", "Tilde (then n)")
        key(":", [.command, .shift], "dead:umlaut", "Diaeresis (then u)")
        key(";", [.command, .shift], "dead:umlaut", "Diaeresis (then u)")
        key("/", [.command, .alternate, .shift], "insert:¿", "¿")
        key("?", [.command, .alternate, .shift], "insert:¿", "¿")
        key("1", [.command, .alternate, .shift], "insert:¡", "¡")
        key("!", [.command, .alternate, .shift], "insert:¡", "¡")
        return out
    }

    /// A Spanish block asks for a Spanish keyboard when one is set up (its spelling and suggestions then follow).
    override var textInputMode: UITextInputMode? {
        if session?.isSpanish == true, let es = UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage?.hasPrefix("es") == true }) {
            return es
        }
        return super.textInputMode
    }

    @objc func nexusKey(_ sender: UIKeyCommand) {
        guard let action = sender.propertyList as? String else { return }
        session?.perform(action)
    }

    /// Paste as plain text: the words are markdown already.
    override func paste(_ sender: Any?) {
        guard let s = UIPasteboard.general.string else { super.paste(sender); return }
        insertText(s)
    }
}

/// One block being typed in, over the board: the text view sits over the block in screen space and draws its words at the board's
/// zoom (so they stay sharp), styled live. Every change goes straight into the board's content and is saved with it.
final class WritingSession: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
    weak var board: BoardController?
    let id: String
    let textView: BlockTextView
    let manager: MDLayoutManager
    let storage: NSTextStorage
    let container: NSTextContainer
    /// The zoom the words are styled at; while pinching the view is scaled from it, and restyled when the pinch ends.
    private(set) var scale: CGFloat
    var look: BlockLook
    /// The block's size on the board (units), from its laid-out words.
    var displaySize: CGSize = .zero
    /// The board's items and words when typing started, for the board's undo.
    var before: ([BoardItem], [String: String])
    var startText: String
    /// Which words are open: the block's id for its current draft, `<id>~<draft>` for another one (BlockDrafts.key).
    private(set) var key: String
    private var applying = false
    private var lastTyped: Int? = nil
    /// A dead accent key waiting for its letter ("acute", "tilde", "umlaut").
    var deadKey: String?
    private var practiceTimer: Timer?
    private var practiceOver = false
    private var keyboard: CGRect = .zero
    lazy var bar = FormatBar(session: self)
    /// The block's drafts as tabs above it (only when it has drafts).
    lazy var tabs = DraftTabs(session: self)

    /// In the Writing view: the text view scrolls on its own and is not placed over the board.
    let fullscreen: Bool
    /// The board's ink when typing started (Push things below may move it).
    var beforeStrokes: [BoardStroke] = []
    /// The Writing view closes itself on Done.
    var onDone: (() -> Void)?

    init(board: BoardController, item: BoardItem, fullscreen: Bool = false) {
        self.board = board
        self.fullscreen = fullscreen
        id = item.id
        scale = fullscreen ? 1.25 : board.canvas.zoomScale
        look = BlockLook(item)
        before = (board.content.items, board.content.texts)
        key = board.shownKey(item.id)
        startText = board.content.texts[key] ?? ""
        let c = NSTextContainer(size: CGSize(width: 100, height: 10_000_000))
        c.lineFragmentPadding = 0
        c.widthTracksTextView = true
        let m = MDLayoutManager()
        m.addTextContainer(c)
        let st = NSTextStorage()
        st.addLayoutManager(m)
        container = c
        manager = m
        storage = st
        textView = BlockTextView(frame: .zero, textContainer: c)
        super.init()
        textView.session = self
        textView.delegate = self
        textView.isScrollEnabled = fullscreen
        textView.backgroundColor = .clear
        if !fullscreen { textView.layer.anchorPoint = .zero }
        textView.autocapitalizationType = .sentences
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.inputAccessoryView = bar
        textView.text = startText
        applyPractice()

        let tick = UITapGestureRecognizer(target: self, action: #selector(tappedInside(_:)))
        tick.delegate = self
        textView.addGestureRecognizer(tick)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    var text: String { textView.text ?? "" }
    var item: BoardItem? { board?.content.items.first { $0.id == id } }

    // MARK: drawing and placing

    /// Style the words for the selection at the current scale.
    func restyle() {
        guard textView.markedTextRange == nil else { return }
        let sel = textView.selectedRange
        let result = BlockStyler.style(storage, look: look, scale: scale, selection: sel)
        manager.quoteStep = result.quoteStep
        if fullscreen, let b = board {
            // the writing view shows the words each open comment is on, like the board does
            let n = storage.length
            for r in b.markedRanges(id) where r.location >= 0 && NSMaxRange(r) <= n && r.length > 0 {
                storage.addAttribute(.backgroundColor, value: UIColor.systemPurple.withAlphaComponent(0.16), range: r)
            }
        }
        var typing = textView.typingAttributes
        typing[BlockStyler.hiddenKey] = nil
        typing[BlockStyler.glyphKey] = nil
        typing[BlockStyler.markKey] = nil
        typing[.foregroundColor] = look.color
        textView.typingAttributes = typing
        bar.refresh()
    }

    /// The block's size on the board for its words now (and the board's own view of it, kept in step while hidden).
    func measure() {
        guard let b = board, let it = item else { return }
        let layout = TextBlockRender.layout(text, item: it)
        displaySize = layout.size
        b.textSizes[id] = layout.size
        if let v = b.itemViews[id] as? TextBlockView {
            v.update(md: text, item: it)
            v.frame.origin = CGPoint(x: it.x + b.offset.x, y: it.y + b.offset.y)
        }
    }

    /// Put the text view over the block (screen space), scaled from its styling scale to the board's zoom.
    func place() {
        guard !fullscreen, let b = board, let it = item else { return }
        let z = b.canvas.zoomScale
        let box = TextBlockRender.box(it)
        let s = scale
        textView.textContainerInset = UIEdgeInsets(top: box.padY * s, left: box.padX * s, bottom: box.padY * s, right: box.padX * s)
        manager.ensureLayout(for: container)
        let own = ceil(max(manager.usedRect(for: container).height, manager.mathBottom())) + 2 * box.padY * s
        let size = CGSize(width: displaySize.width * s, height: max(displaySize.height * s, own))
        if textView.bounds.size != size { textView.bounds = CGRect(origin: .zero, size: size) }
        textView.layer.position = b.viewPoint(board: CGPoint(x: it.x, y: it.y))
        let k = z / s
        textView.transform = abs(k - 1) < 0.0005 ? .identity : CGAffineTransform(scaleX: k, y: k)
        tabs.place(over: textView.frame)
        if let fill = look.fill {
            textView.backgroundColor = fill
            textView.layer.cornerRadius = 4 * s
        } else {
            textView.backgroundColor = UIColor(white: 1, alpha: 0.001)
            textView.layer.cornerRadius = 0
        }
    }

    /// The pinch ended: draw the words at the new zoom.
    func rescale() {
        guard !fullscreen, let b = board else { return }
        let z = b.canvas.zoomScale
        guard abs(z - scale) > 0.001 else { place(); return }
        scale = z
        restyle()
        place()
    }

    /// The block's look changed (size, colour, fill, font, styles…).
    func lookChanged() {
        guard let it = item else { return }
        look = BlockLook(it)
        if Practice.isOn(it) != (practiceTimer != nil) { applyPractice() }
        restyle()
        measure()
        place()
    }

    // MARK: typing

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if applying { return true }
        if board?.blockLocked(id) == true {
            board?.tellLocked(id)
            return false
        }
        lastTyped = nil
        if text == "\n", let e = MarkdownEdit.newline(self.text, range) {
            apply(e)
            return false
        }
        if let dead = deadKey, (text as NSString).length == 1 {
            deadKey = nil
            let out = Accents.apply(dead, text)
            if out != text {
                apply(MDEdit((self.text as NSString).replacingCharacters(in: range, with: out), NSRange(location: range.location + (out as NSString).length, length: 0)))
                return false
            }
        }
        if look.review, textView.markedTextRange == nil {
            // Review mode: the change becomes a suggestion (a deletion with the caret at its start is the Delete key)
            let sel = textView.selectedRange
            let forward = text.isEmpty && range.length > 0 && sel.length == 0 && sel.location == range.location
            apply(Review.type(self.text, range: range, with: text, forward: forward))
            return false
        }
        if (text as NSString).length == 1, range.length == 0 { lastTyped = range.location + 1 }
        return true
    }

    // MARK: Review mode

    var suggestions: [Suggestion] { Review.suggestions(text) }

    func acceptHere(_ accept: Bool) {
        guard let s = Review.at(text, textView.selectedRange) else {
            board?.tell("Put the caret in a suggestion first.", brief: true)
            return
        }
        apply(accept ? Review.accept(text, s) : Review.reject(text, s))
    }

    func reviewAll(_ accept: Bool) {
        let t = Review.all(text, accept: accept)
        guard t != text else { return }
        apply(MDEdit(t, NSRange(location: min(textView.selectedRange.location, (t as NSString).length), length: 0)))
    }

    /// Selects the next suggestion after the caret (from the top again at the end).
    func nextSuggestion() {
        let all = suggestions
        guard !all.isEmpty else { board?.tell("No suggestions in this block.", brief: true); return }
        let caret = NSMaxRange(textView.selectedRange)
        let s = all.first { $0.range.location >= caret } ?? all[0]
        textView.selectedRange = s.range
        restyle()
        keepCaretVisible()
    }

    func textViewDidChange(_ textView: UITextView) {
        if applying { return }
        board?.tellTyping(id)
        edited()
        if look.chem, !practicing, let caret = lastTyped {
            lastTyped = nil
            // a moment later, so undo takes the formula back on its own
            DispatchQueue.main.async { [weak self] in self?.convertChemistry(caret: caret) }
        }
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        if applying { return }
        restyle()
        keepCaretVisible()
    }

    /// The words changed: style them, size the block, hand them to the board (saved shortly).
    func edited() {
        restyle()
        measure()
        place()
        board?.typed(id, key: key, text)
        keepCaretVisible()
    }

    /// Another draft is shown, or the drafts changed under the open block: show the words the board now has for it.
    /// The typing so far must already be an undo step (BoardController.commitTyping).
    func reload() {
        guard let b = board else { return }
        key = b.shownKey(id)
        let words = b.content.texts[key] ?? ""
        startText = words
        before = (b.content.items, b.content.texts)
        if text != words {
            applying = true
            textView.text = words
            textView.selectedRange = NSRange(location: (words as NSString).length, length: 0)
            applying = false
        }
        textView.undoManager?.removeAllActions()
        if let it = item { look = BlockLook(it) }
        restyle()
        measure()
        place()
        tabs.refresh()
    }

    func convertChemistry(caret: Int) {
        guard caret <= (text as NSString).length, let c = Chem.convert(text, caret: caret) else { return }
        let m = NSMutableString(string: text)
        m.replaceCharacters(in: c.range, with: c.with)
        let delta = (c.with as NSString).length - c.range.length
        let sel = textView.selectedRange
        apply(MDEdit(m as String, NSRange(location: max(0, sel.location + delta), length: sel.length)))
    }

    /// Make an edit through the text view, so it is one step of the block's undo.
    func apply(_ e: MDEdit) {
        let old = text as NSString
        let new = e.text as NSString
        var p = 0
        while p < old.length, p < new.length, old.character(at: p) == new.character(at: p) { p += 1 }
        var s = 0
        while s < old.length - p, s < new.length - p, old.character(at: old.length - 1 - s) == new.character(at: new.length - 1 - s) { s += 1 }
        let middle = new.substring(with: NSRange(location: p, length: new.length - p - s))
        applying = true
        if let a = textView.position(from: textView.beginningOfDocument, offset: p),
           let b = textView.position(from: a, offset: old.length - p - s),
           let range = textView.textRange(from: a, to: b) {
            textView.replace(range, withText: middle)
        } else {
            textView.text = e.text
        }
        let len = (textView.text as NSString).length
        let loc = min(e.selection.location, len)
        textView.selectedRange = NSRange(location: loc, length: min(e.selection.length, len - loc))
        applying = false
        edited()
    }

    // MARK: the edit menu (Comment)

    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let b = board else { return nil }
        let id = self.id
        var extra: [UIMenuElement] = [
            UIAction(title: "Comment", image: UIImage(systemName: "text.bubble")) { [weak b] _ in b?.addComment(on: id, range: range) },
        ]
        if range.length > 0 {
            let said = BlockFacts.plainText((textView.text as NSString).substring(with: range))
            extra.append(UIAction(title: "Read aloud", image: UIImage(systemName: "speaker.wave.2")) { [weak b] _ in
                b?.showReadBar()
                ReadAloud.shared.read(said)
            })
        }
        extra.append(UIAction(title: "Make a flashcard", image: UIImage(systemName: "rectangle.on.rectangle.angled")) { [weak b] _ in
            b?.makeFlashcard(from: id, range: range)
        })
        if b.content.items.contains(where: { $0.id == id }) {
            extra.append(UIAction(title: "Add a Nexus task", image: UIImage(systemName: "checkmark.circle.badge.plus")) { [weak b] _ in
                b?.addNexusTask(from: id, range: range)
            })
        }
        return UIMenu(children: suggestedActions + [UIMenu(options: .displayInline, children: extra)])
    }

    // MARK: words from the other device

    /// The laptop's words for this open block arrived (live editing, piece 11): `base` is the words both last agreed on, `theirs`
    /// the laptop's now. Merges them into what is being typed (LiveBoard.mergeBlock), keeps the caret where it was in the words
    /// and leaves the merge out of the block's undo. False on a clash on the same line: nothing changes, and the caller keeps
    /// these words and makes the laptop's a draft (LiveBoard.clashDraft).
    @discardableResult
    func takeRemote(base: String?, theirs: String) -> Bool {
        let mine = text
        guard let merged = LiveBoard.mergeBlock(base: base, mine: mine, theirs: theirs) else { return false }
        guard merged != mine else { return true }
        if textView.markedTextRange != nil { textView.unmarkText() }
        let old = text as NSString
        let new = merged as NSString
        var p = 0
        while p < old.length, p < new.length, old.character(at: p) == new.character(at: p) { p += 1 }
        var s = 0
        while s < old.length - p, s < new.length - p, old.character(at: old.length - 1 - s) == new.character(at: new.length - 1 - s) { s += 1 }
        let gone = NSRange(location: p, length: old.length - p - s)
        let middle = new.substring(with: NSRange(location: p, length: new.length - p - s))
        let delta = new.length - old.length
        func moved(_ i: Int) -> Int {
            if i <= gone.location { return i }
            if i >= gone.location + gone.length { return i + delta }
            return p + (middle as NSString).length
        }
        let sel = textView.selectedRange
        let from = moved(sel.location)
        let to = moved(sel.location + sel.length)
        applying = true
        // the block's undo history refers to places in the old words, so it starts over (the board's undo still has the whole typing)
        textView.undoManager?.removeAllActions()
        storage.beginEditing()
        storage.replaceCharacters(in: gone, with: middle)
        storage.endEditing()
        textView.selectedRange = NSRange(location: min(from, new.length), length: max(0, min(to, new.length) - min(from, new.length)))
        applying = false
        edited()
        return true
    }

    // MARK: the bar's and the keys' actions

    func perform(_ action: String) {
        let t = text
        let sel = textView.selectedRange
        switch action {
        case "bold": apply(MarkdownEdit.wrap(t, sel, "**"))
        case "italic": apply(MarkdownEdit.wrap(t, sel, "*"))
        case "underline": apply(MarkdownEdit.wrap(t, sel, "<u>", "</u>"))
        case "strike": apply(MarkdownEdit.wrap(t, sel, "~~"))
        case "highlight": apply(MarkdownEdit.highlight(t, sel, color: "yellow"))
        case "code": apply(MarkdownEdit.wrap(t, sel, "`"))
        case "title": apply(MarkdownEdit.setStyle(t, sel, .title))
        case "h1": apply(MarkdownEdit.setStyle(t, sel, .h1))
        case "h2": apply(MarkdownEdit.setStyle(t, sel, .h2))
        case "h3": apply(MarkdownEdit.setStyle(t, sel, .h3))
        case "body": apply(MarkdownEdit.setStyle(t, sel, .body))
        case "quote": apply(MarkdownEdit.setStyle(t, sel, .quote))
        case "codeblock": apply(MarkdownEdit.setStyle(t, sel, .code))
        case "bullets": apply(MarkdownEdit.toggleLinePrefix(t, sel, "- "))
        case "numbers": apply(MarkdownEdit.toggleLinePrefix(t, sel, "1. "))
        case "checklist": apply(MarkdownEdit.toggleLinePrefix(t, sel, "- [ ] "))
        case "link": apply(MarkdownEdit.link(t, sel))
        case "indent", "outdent":
            if let e = MarkdownEdit.indent(t, sel, out: action == "outdent") { apply(e) } else if action == "indent" { textView.insertText("\t") }
        case "done": if fullscreen { onDone?() } else { board?.endWriting() }
        case "writing": if fullscreen { onDone?() } else { board?.openWritingView(id) }
        case "find": board?.openFind(id)
        default:
            if action.hasPrefix("dead:") { deadKey = String(action.dropFirst(5)) }
            else if action.hasPrefix("insert:") { insert(String(action.dropFirst(7))) }
        }
    }

    /// The bar's Link button (⌘K stays `perform("link")`): links the selection, or the word at the caret; with neither, asks for
    /// the address and types `[address](address)` only on OK, so a tap never leaves a stray `[]()`.
    func linkFromBar() {
        if board?.blockLocked(id) == true { board?.tellLocked(id); return }
        let sel = textView.selectedRange
        if let e = MarkdownEdit.linkWords(text, sel) { apply(e); return }
        let a = UIAlertController(title: "Link", message: "The address to link to.", preferredStyle: .alert)
        a.addTextField { f in
            f.placeholder = "https://"
            f.keyboardType = .URL
            f.autocapitalizationType = .none
            f.autocorrectionType = .no
            f.clearButtonMode = .whileEditing
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.textView.becomeFirstResponder() })
        a.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak a] _ in
            guard let self else { return }
            self.textView.becomeFirstResponder()
            let t = self.text
            let len = (t as NSString).length
            let at = NSRange(location: min(sel.location, len), length: 0)
            if let e = MarkdownEdit.linkAddress(t, at, a?.textFields?.first?.text ?? "") { self.apply(e) }
        })
        board?.presentOver(a)
    }

    /// Types `s` at the caret (the accent row, ¿ and ¡).
    func insert(_ s: String) {
        if board?.blockLocked(id) == true { board?.tellLocked(id); return }
        let sel = textView.selectedRange
        if look.review { apply(Review.type(text, range: sel, with: s)); return }
        apply(MDEdit((text as NSString).replacingCharacters(in: sel, with: s), NSRange(location: sel.location + (s as NSString).length, length: 0)))
    }

    // MARK: Spanish blocks and practice mode

    /// The block is Spanish: its own `lang`, else what its words look like (as the laptop guesses it).
    var isSpanish: Bool { BlockFacts.lang(item, text) == "es" }

    var practicing: Bool { item.map(Practice.isOn) ?? false }

    /// Practice mode turns every check off: spelling, autocorrect, predictions and Writing Tools; it is back on when practice ends.
    func applyPractice() {
        let on = practicing
        // a Spanish block is spellchecked only with a Spanish dictionary (an English one would flag every word), and never with `check: false`
        let spanishOff = isSpanish && (item?.json["check"]?.bool == false
            || !UITextInputMode.activeInputModes.contains { $0.primaryLanguage?.hasPrefix("es") == true })
        textView.spellCheckingType = on || spanishOff ? .no : .default
        textView.autocorrectionType = on ? .no : .default
        textView.inlinePredictionType = on ? .no : .default
        if #available(iOS 18.0, *) { textView.writingToolsBehavior = on ? .none : .default }
        if textView.isFirstResponder { textView.reloadInputViews() }
        practiceTimer?.invalidate()
        practiceTimer = nil
        practiceOver = false
        if on {
            practiceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tickPractice() }
        }
        bar.refresh()
    }

    func tickPractice() {
        bar.refresh()
        guard let it = item, let left = Practice.left(it), left <= 0, !practiceOver else { return }
        practiceOver = true
        board?.practiceOver(id)
    }

    func stopTimers() {
        practiceTimer?.invalidate()
        practiceTimer = nil
    }

    func setStyle(_ style: BlockStyle) { apply(MarkdownEdit.setStyle(text, textView.selectedRange, style)) }
    func highlight(_ color: String) { apply(MarkdownEdit.highlight(text, textView.selectedRange, color: color)) }
    func textColor(_ color: String) { apply(MarkdownEdit.textColor(text, textView.selectedRange, color: color)) }
    var currentStyle: BlockStyle { MarkdownEdit.style(text, at: textView.selectedRange.location) }

    // MARK: ticking a checkbox while typing

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        taskLine(at: g.location(in: textView)) != nil
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { false }

    func taskLine(at p: CGPoint) -> Int? {
        let inset = textView.textContainerInset
        return manager.taskLine(at: CGPoint(x: p.x - inset.left, y: p.y - inset.top))
    }

    @objc func tappedInside(_ g: UITapGestureRecognizer) {
        guard let line = taskLine(at: g.location(in: textView)), let md = TextLook.toggleTask(text, line: line) else { return }
        apply(MDEdit(md, textView.selectedRange))
    }

    // MARK: the keyboard

    @objc func keyboardChanged(_ n: Notification) {
        if n.name == UIResponder.keyboardWillHideNotification {
            keyboard = .zero
        } else if let r = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            keyboard = r
        }
        DispatchQueue.main.async { [weak self] in self?.keepCaretVisible() }
    }

    /// Scroll the board so the caret isn't under the keyboard or off the screen.
    func keepCaretVisible() {
        if fullscreen {
            if let end = textView.selectedTextRange?.end { textView.scrollRectToVisible(textView.caretRect(for: end).insetBy(dx: 0, dy: -40), animated: false) }
            return
        }
        guard let b = board, let end = textView.selectedTextRange?.end, textView.window != nil else { return }
        let caret = textView.convert(textView.caretRect(for: end), to: b.view)
        guard caret.minY.isFinite, caret.height > 0 else { return }
        let kb = b.view.convert(keyboard, from: nil)
        let bottom = keyboard == .zero ? b.view.bounds.maxY : min(b.view.bounds.maxY, kb.minY)
        let margin: CGFloat = 40
        var dy: CGFloat = 0
        if caret.maxY > bottom - margin { dy = caret.maxY - (bottom - margin) }
        // the board's bar covers topInset (the safe area and the bar), not just the safe area
        let top = b.topInset + 16
        if caret.minY < top { dy = caret.minY - top }
        guard abs(dy) > 1 else { return }
        var o = b.canvas.contentOffset
        o.y = max(0, o.y + dy)
        b.canvas.setContentOffset(o, animated: false)
    }
}
