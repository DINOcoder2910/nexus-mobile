import UIKit
import NexusCore

/// Spanish underlines on a board's typed blocks, as the laptop has them (nexus desktop/src/board/spanish.ts): each paragraph of a Spanish
/// block is read by the checker (Claude Haiku, Spanish › Check's prompt) a moment after the typing stops, once for the words it has; its
/// mistakes are underlined (red, an accent amber) in the open block, plain or rich editor, and on the closed block, and a tap on one shows
/// the fix with Apply. These checks are not counted in the skills' numbers. Check it now reads the whole block (ending practice) and is
/// counted; Correct this makes a corrected draft with every fix as a Review suggestion. The live corrections switch (Spanish ›
/// "Live corrections", the block's Spanish menu) turns the as-you-write checks off everywhere; a block's "Check my Spanish" for that block.
/// The pure half is NexusCore's SpanishBlock.swift.
@MainActor
final class BoardSpanish {
    static let shared = BoardSpanish()

    /// Live corrections: on unless switched off (shared with the Spanish screen).
    static let liveKey = "spanish.live"
    static var liveOn: Bool {
        get { UserDefaults.standard.object(forKey: liveKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: liveKey); shared.redraw() }
    }
    private static let knownKey = "nexus.board.esKnown"

    private(set) var known: SpanishBlock.Known
    private var waiting: [String] = []
    private var running = false
    private var told = false
    private let boards = NSHashTable<BoardController>.weakObjects()
    /// For the tests and the block dump: checks asked for, and the counted ones.
    private(set) var checks = 0
    private(set) var counted = 0

    private init() {
        known = SpanishBlock.Known.decode(UserDefaults.standard.string(forKey: Self.knownKey))
    }

    private func keep() { UserDefaults.standard.set(known.encode(), forKey: Self.knownKey) }

    /// A board that shows typed blocks: drawn again when a check comes back.
    func watch(_ b: BoardController) { if !boards.contains(b) { boards.add(b) } }

    /// The marks over a block's words now (nothing when the block isn't checked).
    func placed(_ item: BoardItem?, _ md: String) -> [SpanishBlock.Placed] {
        guard let item, SpanishBlock.checking(item, md) else { return [] }
        return SpanishBlock.place(md, known: known.get)
    }

    /// The block's paragraphs that haven't been read, sent one at a time (when live corrections are on and the block is checked).
    func scan(_ item: BoardItem?, _ md: String, board: BoardController) {
        guard Self.liveOn, let item, SpanishBlock.checking(item, md) else { return }
        watch(board)
        for p in SpanishBlock.paragraphs(md) where SpanishBlock.worth(p.text) && !known.has(p.text) && !waiting.contains(p.text) {
            waiting.append(p.text)
        }
        guard !running, !waiting.isEmpty else { return }
        running = true
        let ws = workstream(board)
        Task { @MainActor [weak board] in
            while !self.waiting.isEmpty {
                let t = self.waiting.removeFirst()
                if self.known.has(t) { continue }
                do {
                    self.known.set(t, try await self.check(t, ws: ws, log: nil))
                } catch {
                    self.known.set(t, [])
                    if !self.told { self.told = true; board?.tell("The Spanish couldn't be checked: \(error.localizedDescription)") }
                }
                self.keep()
                self.redraw()
            }
            self.running = false
        }
    }

    /// The Spanish workstream a board belongs to (its folder), else the first one: whose taught tenses the checker is told, and whose
    /// log Check it now is counted in.
    func workstream(_ b: BoardController) -> String? {
        let lib = SpanishLibrary.shared
        if lib.workstreams.isEmpty, let store = b.store { lib.refreshIfChanged(store) }
        return (lib.workstreams.first { b.path.hasPrefix($0.folder + "/") } ?? lib.first)?.id
    }

    /// The checker on some words -> its mistakes over them (offsets in `text`). `log`: the store to count it in (Check it now).
    func check(_ text: String, ws: String?, log: NexusStore?) async throws -> [SpanishCheck.Mark] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        checks += 1
        let lib = SpanishLibrary.shared
        let taught = ws.map { lib.data($0).status } ?? [:]
        let reply = try await SpanishClaude.once(model: "haiku", system: SpanishCheck.system, prompt: SpanishCheck.prompt(text: t, taught: taught), demo: { SpanishDemo.check(t) })
        guard let ai = SpanishCheck.readCheck(t, SpanishCheck.jsonFrom(reply)) else { throw ClaudeError("Claude's answer could not be read.") }
        if let store = log, let ws {
            counted += 1
            let all = SpanishCheck.merge(t, [], ai)
            let res = SpanishCheck.Result(marks: all, corrected: ai.corrected, structures: ai.structures, words: ai.words, partial: false)
            lib.addToLog(store, ws, SpanishCheck.logEntry(at: SpanishLibrary.stamp(), source: "board", text: t, result: res))
        }
        return SpanishBlock.marks(text, ai)
    }

    /// Every open board's blocks drawn again with what is known now.
    func redraw() {
        for b in boards.allObjects { b.spanishRedraw() }
    }

    // MARK: the block menu's actions

    /// Practice ends and the whole block is read (counted): its mistakes underlined, and how many said.
    func checkNow(_ b: BoardController, _ id: String) async {
        b.commitTyping(id)
        if let it = b.content.items.first(where: { $0.id == id }), Practice.isOn(it) { b.endPractice(id) }
        let md = b.content.texts[b.shownKey(id)] ?? ""
        let whole = SpanishBlock.whole(md)
        guard !whole.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { b.tell("There are no words to check yet.", brief: true); return }
        watch(b)
        b.tell("Checking the Spanish…", brief: true)
        let marks: [SpanishCheck.Mark]
        do { marks = try await check(whole.text, ws: workstream(b), log: b.store) } catch {
            b.tell("The Spanish couldn't be checked: \(error.localizedDescription)")
            return
        }
        for p in SpanishBlock.split(md, marks) where SpanishBlock.worth(p.text) { known.set(p.text, p.marks) }
        keep()
        redraw()
        let n = marks.count
        b.tell(n == 0 ? "No mistakes found." : n == 1 ? "1 thing to look at: it is underlined." : "\(n) things to look at: they are underlined.", brief: true)
    }

    /// Every fix the checker has, as Review suggestions in a corrected draft (Apply or Reject each one).
    func correct(_ b: BoardController, _ id: String) async {
        b.commitTyping(id)
        let md = b.content.texts[b.shownKey(id)] ?? ""
        let whole = SpanishBlock.whole(md)
        guard !whole.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { b.tell("There are no words to correct yet.", brief: true); return }
        watch(b)
        b.tell("Reading the Spanish for Correct this…", brief: true)
        let marks: [SpanishCheck.Mark]
        do { marks = try await check(whole.text, ws: workstream(b), log: b.store) } catch {
            b.tell("The Spanish couldn't be checked: \(error.localizedDescription)")
            return
        }
        for p in SpanishBlock.split(md, marks) where SpanishBlock.worth(p.text) { known.set(p.text, p.marks) }
        keep()
        redraw()
        guard (b.content.texts[b.shownKey(id)] ?? "") == md else { b.tell("The words changed while they were checked: Correct this again."); return }
        let fixes = SpanishBlock.fixes(SpanishBlock.place(md, known: known.get))
        guard !fixes.isEmpty else { b.tell("Nothing to correct: no mistakes found.", brief: true); return }
        _ = b.correctAsDraft(id, fixes: fixes)
    }

    /// A tap on an underline: the mistake, its fix and why, with Apply (the words go in as they are, as on the laptop).
    func showFix(_ b: BoardController, _ id: String, _ p: SpanishBlock.Placed, from rect: CGRect, in view: UIView) {
        let m = p.mark
        let skill = Spanish.skills.first { $0.id == m.skill }?.name ?? m.skill
        let a = UIAlertController(title: m.right.isEmpty ? m.wrong : "\(m.wrong) → \(m.right)",
                                  message: [m.why, skill].filter { !$0.isEmpty }.joined(separator: "\n\n"), preferredStyle: .actionSheet)
        if !m.right.isEmpty {
            a.addAction(UIAlertAction(title: "Apply", style: .default) { [weak b] _ in
                guard let b else { return }
                let md = (b.writing?.id == id ? b.writing?.text : nil) ?? b.content.texts[b.shownKey(id)] ?? ""
                let ns = md as NSString
                guard NSMaxRange(p.range) <= ns.length, ns.substring(with: p.range) == m.wrong else { b.tell("Those words changed: check again.", brief: true); return }
                b.correct(id, range: p.range, with: m.right, asSuggestion: false)
            })
        }
        a.addAction(UIAlertAction(title: m.right.isEmpty ? "OK" : "Close", style: .cancel))
        a.popoverPresentationController?.sourceView = view
        a.popoverPresentationController?.sourceRect = rect
        a.view.accessibilityIdentifier = "es-fix"
        b.presentOver(a)
    }
}

// MARK: the board

extension BoardController {
    /// A closed block's underlines: (range in its markdown, error | accent).
    func spanishMarks(_ it: BoardItem, _ md: String) -> [(range: NSRange, kind: String)] {
        BoardSpanish.shared.watch(self)
        return BoardSpanish.shared.placed(it, md).map { ($0.range, $0.mark.kind) }
    }

    /// A check came back (or the switches changed): the closed blocks and the open one drawn again.
    func spanishRedraw() {
        for it in content.items where it.type == "text" {
            guard let v = itemViews[it.id] as? TextBlockView else { continue }
            v.spanish = spanishMarks(it, content.texts[shownKey(it.id)] ?? "")
        }
        writing?.spanishChanged()
        writingFull?.spanishChanged()
        if TextBlockView.dumping { spanishDump() }
    }

    /// For the UI test (`-debug.blockDump YES`): how many underlines the board shows, open and closed, and the checks asked for, on a
    /// near-invisible label on the window (the board keeps its blocks out of the accessibility tree).
    func spanishDump() {
        var closed = 0
        for it in content.items where it.type == "text" { closed += (itemViews[it.id] as? TextBlockView)?.spanish.count ?? 0 }
        let open = (writingFull ?? writing)?.spanishPlaced.count ?? 0
        let text = "es closed:\(closed) open:\(open) checks:\(BoardSpanish.shared.checks) counted:\(BoardSpanish.shared.counted) live:\(BoardSpanish.liveOn ? "on" : "off")"
        guard let w = view.window else { return }
        let label = (w.viewWithTag(0x6E5E) as? UILabel) ?? {
            let v = UILabel(frame: CGRect(x: 4, y: 0, width: 4, height: 4))
            v.tag = 0x6E5E; v.alpha = 0.02; v.isAccessibilityElement = true; v.accessibilityIdentifier = "esdump"
            w.addSubview(v)
            return v
        }()
        w.bringSubviewToFront(label)
        label.accessibilityLabel = text
    }
}

// MARK: the open block

extension WritingSession {
    /// The marks over the words as they are now.
    var spanishPlaced: [SpanishBlock.Placed] { BoardSpanish.shared.placed(item, text) }

    /// Read the block's new paragraphs `after` seconds from now (again from the start at each change, so it waits for a pause).
    func spanishLater(_ after: TimeInterval) {
        spanishTimer?.invalidate()
        spanishTimer = Timer.scheduledTimer(withTimeInterval: after, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let b = self.board else { return }
                BoardSpanish.shared.scan(self.item, self.text, board: b)
            }
        }
    }

    /// The words changed: the underlines follow them now, and the new words are read after a pause.
    func spanishEdited() {
        spanishSend()
        spanishLater(2.5)
    }

    /// What is known changed (a check came back, a switch).
    func spanishChanged() {
        if rich != nil { spanishSend() } else { restyle() }
    }

    /// The rich editor's underlines (markdown offsets), sent when they changed.
    func spanishSend() {
        guard let r = rich else { return }
        let list = spanishList()
        guard list != sentSpanish else { return }
        sentSpanish = list
        r.setSpanish(list)
    }

    func spanishList() -> [[String]] {
        spanishPlaced.map { [String($0.range.location), String(NSMaxRange($0.range)), $0.mark.kind] }
    }

    /// The plain editor's underlines, put on the styled words (MDLayoutManager draws them).
    func spanishStyle() {
        let n = storage.length
        storage.removeAttribute(BlockStyler.spanishKey, range: NSRange(location: 0, length: n))
        for p in spanishPlaced where p.range.length > 0 && NSMaxRange(p.range) <= n {
            storage.addAttribute(BlockStyler.spanishKey, value: p.mark.kind, range: p.range)
        }
    }

    /// The underline under a point in the plain text view, if any.
    func spanishAt(_ point: CGPoint) -> SpanishBlock.Placed? {
        let placed = spanishPlaced
        guard !placed.isEmpty, storage.length > 0 else { return nil }
        let inset = textView.textContainerInset
        let p = CGPoint(x: point.x - inset.left, y: point.y - inset.top)
        let g = manager.glyphIndex(for: p, in: container)
        guard manager.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: container).insetBy(dx: -2, dy: -4).contains(p) else { return nil }
        let i = manager.characterIndexForGlyph(at: g)
        return placed.first { NSLocationInRange(i, $0.range) }
    }

    /// A tap on an underline in the plain editor.
    func spanishTapped(_ point: CGPoint) -> Bool {
        guard let p = spanishAt(point), let b = board else { return false }
        let inset = textView.textContainerInset
        var r = manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: p.range, actualCharacterRange: nil), in: container)
        r = r.offsetBy(dx: inset.left, dy: inset.top)
        BoardSpanish.shared.showFix(b, id, p, from: r, in: textView)
        return true
    }

    /// A tap on an underline in the rich editor (where it starts in the markdown; its box in the page).
    func richSpanishTapped(at: Int, rect: CGRect) {
        guard let b = board, let p = spanishPlaced.first(where: { $0.range.location == at }) else { return }
        BoardSpanish.shared.showFix(b, id, p, from: rect, in: editorView)
    }
}
