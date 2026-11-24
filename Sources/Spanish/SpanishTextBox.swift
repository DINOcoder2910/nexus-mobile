import SwiftUI
import UIKit
import NexusCore

/// The tutor's message box (the laptop's SpanishBox.tsx in the Spanish tutor): what a board's Spanish block has, in a box. Each
/// paragraph that doesn't read as English is read by the checker (Haiku, not counted in the skills' numbers) a moment after the typing
/// stops, once for its words (what is known is shared with the boards: BoardSpanish); its mistakes are wavy underlines, red or an accent
/// amber, and a tap on one shows the fix with Apply. It follows the one Live corrections switch. Return sends; the keyboard's own
/// autocorrect and spelling are off, so the words are his own until the checker reads them. A check question's answer box
/// (SpanishAnswerField) is never checked before it is sent.
struct SpanishTextBox: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// The Spanish workstream (whose taught tenses the checker is told).
    var wsId: String?
    var identifier: String
    /// Return (and the send button beside it).
    var onSubmit: () -> Void
    var maxLines = 6
    /// false for a piece of writing (Writing's essay box): Return starts a new line and nothing is sent.
    var returnSends = true
    /// The box's least height in lines (an essay box starts tall).
    var minLines = 1

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let storage = NSTextStorage()
        let layout = MDLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let v = UITextView(frame: .zero, textContainer: container)
        v.delegate = context.coordinator
        v.font = UIFont.preferredFont(forTextStyle: .body)
        v.adjustsFontForContentSizeCategory = true
        v.textColor = .label
        v.backgroundColor = .secondarySystemBackground
        v.layer.cornerRadius = 8
        v.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        v.autocorrectionType = .no
        v.spellCheckingType = .no
        v.smartQuotesType = .no
        v.autocapitalizationType = .sentences
        v.returnKeyType = returnSends ? .send : .default
        v.isScrollEnabled = false
        v.accessibilityIdentifier = identifier
        v.accessibilityLabel = placeholder
        v.text = text
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)
        context.coordinator.view = v
        context.coordinator.watch()
        context.coordinator.restyle()
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) {
        context.coordinator.parent = self
        // only a change made elsewhere (a stem put in, the box emptied after sending) is copied in. SwiftUI can update the view in
        // the middle of a key's insert, before textViewDidChange has passed the new letter on; copying the binding in then took the
        // letter back out (a long piece lost a letter every line or two).
        let c = context.coordinator
        if text != c.pushed {
            c.pushed = text
            if v.text != text {
                v.text = text
                c.restyle()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView v: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 300
        let fit = v.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        let line = (v.font ?? UIFont.preferredFont(forTextStyle: .body)).lineHeight
        let most = line * CGFloat(maxLines) + v.textContainerInset.top + v.textContainerInset.bottom
        let least = line * CGFloat(minLines) + v.textContainerInset.top + v.textContainerInset.bottom
        let scroll = fit > most
        if v.isScrollEnabled != scroll { DispatchQueue.main.async { v.isScrollEnabled = scroll } }
        return CGSize(width: w, height: max(least, min(fit, most)))
    }

    static func dismantleUIView(_ v: UITextView, coordinator: Coordinator) { coordinator.stop() }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: SpanishTextBox
        weak var view: UITextView?
        private var timer: Timer?
        private var watching: UUID?

        /// The text last passed to the binding (or copied in from it).
        var pushed: String

        init(_ p: SpanishTextBox) { parent = p; pushed = p.text }

        func watch() { watching = BoardSpanish.shared.onChange { [weak self] in self?.restyle() } }
        func stop() {
            timer?.invalidate(); timer = nil
            if let w = watching { BoardSpanish.shared.stopWatching(w) }
        }

        /// The paragraphs a check reads: two words or more, not English.
        static func lines(_ text: String) -> [String] {
            text.components(separatedBy: "\n").filter { SpanishBlock.worth($0) && BlockFacts.lang(nil, $0) != "en" }
        }

        /// The underlines over the words as they are now. The text storage is touched only when they differ from what it shows (the
        /// underlines it has already move with the words), so a key typed doesn't redo the storage.
        func restyle() {
            guard let v = view else { return }
            let s = v.textStorage
            let text = v.text ?? ""
            var want: [(NSRange, String)] = []
            if BoardSpanish.liveOn {
                let ok = Set(Self.lines(text))
                var at = 0
                for line in text.components(separatedBy: "\n") {
                    let n = (line as NSString).length
                    if ok.contains(line) {
                        for m in BoardSpanish.shared.known.get(line) ?? [] where m.s >= 0 && m.e > m.s && m.e <= n {
                            want.append((NSRange(location: at + m.s, length: m.e - m.s), m.kind))
                        }
                    }
                    at += n + 1
                }
            }
            if Self.runs(s) != Self.runs(want, length: s.length) {
                let all = NSRange(location: 0, length: s.length)
                s.beginEditing()
                s.removeAttribute(BlockStyler.spanishKey, range: all)
                for (r, kind) in want where NSMaxRange(r) <= s.length { s.addAttribute(BlockStyler.spanishKey, value: kind, range: r) }
                s.endEditing()
                v.setNeedsDisplay()
            }
            dump()
        }

        /// The underlined runs a text shows (adjacent marks of one kind read as one run, as the storage keeps them).
        static func runs(_ s: NSAttributedString) -> [String] {
            var out: [String] = []
            s.enumerateAttribute(BlockStyler.spanishKey, in: NSRange(location: 0, length: s.length)) { val, r, _ in
                if let val { out.append("\(r.location):\(r.length):\(val)") }
            }
            return out
        }
        static func runs(_ marks: [(NSRange, String)], length: Int) -> [String] {
            let a = NSMutableAttributedString(string: String(repeating: " ", count: length))
            for (r, kind) in marks where NSMaxRange(r) <= length { a.addAttribute(BlockStyler.spanishKey, value: kind, range: r) }
            return runs(a)
        }

        /// Read the new paragraphs after a pause (again from the start at each change).
        func later() {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, BoardSpanish.liveOn, let v = self.view else { return }
                    BoardSpanish.shared.ask(Self.lines(v.text ?? ""), ws: self.parent.wsId) { AppServices.store.toast = .init(message: $0) }
                }
            }
        }

        func textViewDidChange(_ v: UITextView) {
            pushed = v.text
            parent.text = v.text
            restyle()
            later()
        }

        func textView(_ v: UITextView, shouldChangeTextIn range: NSRange, replacementText t: String) -> Bool {
            if t == "\n" && parent.returnSends { parent.onSubmit(); return false }
            return true
        }

        // MARK: a tap on an underline: the fix, with Apply

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { mark(at: g.location(in: view)) != nil }

        private func mark(at p: CGPoint) -> (range: NSRange, mark: SpanishCheck.Mark)? {
            guard let v = view, BoardSpanish.liveOn else { return nil }
            let lm = v.layoutManager
            let pt = CGPoint(x: p.x - v.textContainerInset.left, y: p.y - v.textContainerInset.top)
            let i = lm.characterIndex(for: pt, in: v.textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
            guard i < v.textStorage.length, v.textStorage.attribute(BlockStyler.spanishKey, at: i, effectiveRange: nil) != nil else { return nil }
            var at = 0
            for line in (v.text ?? "").components(separatedBy: "\n") {
                let n = (line as NSString).length
                if i >= at && i <= at + n {
                    for m in BoardSpanish.shared.known.get(line) ?? [] where at + m.s <= i && i < at + m.e {
                        return (NSRange(location: at + m.s, length: m.e - m.s), m)
                    }
                    return nil
                }
                at += n + 1
            }
            return nil
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let v = view, let hit = mark(at: g.location(in: v)) else { return }
            let m = hit.mark
            let skill = Spanish.skills.first { $0.id == m.skill }?.name ?? m.skill
            let a = UIAlertController(title: m.right.isEmpty ? m.wrong : "\(m.wrong) → \(m.right)",
                                      message: [m.why, skill].filter { !$0.isEmpty }.joined(separator: "\n\n"), preferredStyle: .actionSheet)
            if !m.right.isEmpty {
                a.addAction(UIAlertAction(title: "Apply", style: .default) { [weak self, weak v] _ in
                    guard let self, let v else { return }
                    let ns = (v.text ?? "") as NSString
                    guard NSMaxRange(hit.range) <= ns.length, ns.substring(with: hit.range) == m.wrong else { return }
                    v.text = ns.replacingCharacters(in: hit.range, with: m.right)
                    v.selectedRange = NSRange(location: hit.range.location + (m.right as NSString).length, length: 0)
                    self.textViewDidChange(v)
                })
            }
            a.addAction(UIAlertAction(title: m.right.isEmpty ? "OK" : "Close", style: .cancel))
            let r = v.layoutManager.boundingRect(forGlyphRange: v.layoutManager.glyphRange(forCharacterRange: hit.range, actualCharacterRange: nil), in: v.textContainer)
            a.popoverPresentationController?.sourceView = v
            a.popoverPresentationController?.sourceRect = r.offsetBy(dx: v.textContainerInset.left, dy: v.textContainerInset.top)
            a.view.accessibilityIdentifier = "es-fix"
            var top = v.window?.rootViewController
            while let next = top?.presentedViewController { top = next }
            top?.present(a, animated: true)
        }

        /// For the UI check (-debug.blockDump): how many underlines the box shows, and the checks asked.
        private func dump() {
            guard TextBlockView.dumping, let v = view, let w = v.window else { return }
            var n = 0
            v.textStorage.enumerateAttribute(BlockStyler.spanishKey, in: NSRange(location: 0, length: v.textStorage.length)) { val, _, _ in if val != nil { n += 1 } }
            let label = (w.viewWithTag(0x6E5F) as? UILabel) ?? {
                let l = UILabel(frame: CGRect(x: 4, y: 0, width: 4, height: 4))
                l.tag = 0x6E5F; l.alpha = 0.02; l.isAccessibilityElement = true; l.accessibilityIdentifier = "esbox"
                w.addSubview(l)
                return l
            }()
            let said = "es box:\(n) checks:\(BoardSpanish.shared.checks) live:\(BoardSpanish.liveOn ? "on" : "off")"
            guard label.accessibilityLabel != said else { return }
            w.bringSubviewToFront(label)
            label.accessibilityLabel = said
        }
    }
}
