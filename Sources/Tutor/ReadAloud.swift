import UIKit
import SwiftUI
import PDFKit
import AVFoundation
import NexusCore

/// Read aloud (the board redesign's piece 13): a typed block, a PDF page or any text, in the voice chosen in Settings › Tutor (Apple's
/// voices, offline), each sentence in its own language. Other parts of the app call `ReadAloud.shared.read(_:)` (selected text in the
/// writing editor, for one); a bar shows the words as they are said, the current one marked, with a stop button.
@MainActor
@Observable
final class ReadAloud {
    static let shared = ReadAloud()

    var text = ""
    /// The word being said now, in `text` (UTF-16 range).
    var word = NSRange(location: NSNotFound, length: 0)
    var reading = false
    /// Called with each word's range while reading (a PDF page marks it on the page).
    @ObservationIgnored var onWord: ((NSRange) -> Void)?
    @ObservationIgnored private var parts: [(range: NSRange, utterance: AVSpeechUtterance)] = []

    /// Reads `text` aloud, sentence by sentence (each in its language), replacing anything being read.
    func read(_ text: String, onWord: ((NSRange) -> Void)? = nil) {
        stop()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        self.text = t
        self.onWord = onWord
        reading = true
        let sp = Speaker.shared
        sp.onWord = { [weak self] r, u in self?.said(r, in: u) }
        sp.onFinish = { [weak self] u in
            guard let self, self.parts.last?.utterance === u else { return }
            self.done()
        }
        // one utterance a sentence, so a Spanish sentence is read in the Spanish voice
        let ns = t as NSString
        var out: [(NSRange, AVSpeechUtterance)] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .bySentences) { s, r, _, _ in
            guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            out.append((r, sp.utterance(s)))
        }
        if out.isEmpty { out = [(NSRange(location: 0, length: ns.length), sp.utterance(t))] }
        parts = out
        Audio.prepareForSpeaking()
        for (_, u) in out { sp.synth.speak(u) }
    }

    private func said(_ r: NSRange, in u: AVSpeechUtterance) {
        guard let part = parts.first(where: { $0.utterance === u }) else { return }
        word = NSRange(location: part.range.location + r.location, length: r.length)
        onWord?(word)
    }

    private func done() {
        reading = false
        word = NSRange(location: NSNotFound, length: 0)
        onWord?(word)
        onWord = nil
        parts = []
    }

    func stop() {
        guard reading else { return }
        Speaker.shared.stop()
        done()
    }
}

/// The words being read, the current one marked, and a stop button.
struct ReadAloudBar: View {
    var reader = ReadAloud.shared

    var body: some View {
        if reader.reading {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                Text(around).lineLimit(2).frame(maxWidth: 520, alignment: .leading)
                Button { reader.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }.accessibilityLabel("Stop reading")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        }
    }

    /// The sentence around the word being said, that word in bold and tinted.
    var around: AttributedString {
        let ns = reader.text as NSString
        guard reader.word.location != NSNotFound, NSMaxRange(reader.word) <= ns.length else { return AttributedString(String(reader.text.prefix(160))) }
        let s = ns.rangeOfComposedCharacterSequences(for: NSRange(location: max(0, reader.word.location - 70), length: 0)).location
        let e = min(ns.length, NSMaxRange(reader.word) + 90)
        var out = AttributedString(ns.substring(with: NSRange(location: s, length: reader.word.location - s)))
        var w = AttributedString(ns.substring(with: reader.word))
        w.font = .body.bold()
        w.foregroundColor = .accentColor
        out += w
        out += AttributedString(ns.substring(with: NSRange(location: NSMaxRange(reader.word), length: e - NSMaxRange(reader.word))))
        return out
    }
}

private var readBarKey: UInt8 = 0
private var pdfMarkKey: UInt8 = 0

extension BoardController {
    /// The read aloud button: the picked block, or the PDF page in the middle of the screen (worked out when the menu opens).
    func readAloudButton() -> UIButton {
        let menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.readAloudMenu() ?? []) }])
        return extraButton("speaker.wave.2", "Read aloud", menu: menu)
    }

    private func readAloudMenu() -> [UIMenuElement] {
        var children: [UIMenuElement] = []
        if let id = selected, let it = content.items.first(where: { $0.id == id }), it.type == "text" {
            children.append(UIAction(title: "Read this block", image: UIImage(systemName: "text.bubble")) { [weak self] _ in self?.readBlock(id) })
        }
        if pagePrintout() != nil {
            children.append(UIAction(title: "Read this page", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.readPage() })
        }
        if ReadAloud.shared.reading {
            children.append(UIAction(title: "Stop reading", image: UIImage(systemName: "stop.circle")) { _ in ReadAloud.shared.stop() })
        }
        if children.isEmpty {
            children.append(UIAction(title: "Pick a text block, or show a PDF page, to read it aloud", attributes: .disabled) { _ in })
        }
        return children
    }

    func readBlock(_ id: String) {
        let md = content.texts[id] ?? ""
        showReadBar()
        ReadAloud.shared.read(md.components(separatedBy: "\n").map { HandwritingIndex.Worker.plain($0) }.joined(separator: "\n"))
    }

    /// The printout and page in the middle of the screen.
    func pagePrintout() -> (PdfPrintout, Int)? {
        let v = visibleBoard, mid = CGPoint(x: v.midX, y: v.midY)
        var best: (PdfPrintout, Int, CGFloat)?
        for p in pdfs.values {
            for (i, f) in p.frames.enumerated() {
                let d = dist(f, mid)
                if best == nil || d < best!.2 { best = (p, i, d) }
            }
        }
        guard let best, best.2 < v.height / 2 else { return nil }
        return (best.0, best.1)
    }

    func readPage() {
        guard let (p, i) = pagePrintout(), let page = p.doc.page(at: i), let text = page.string, !text.isEmpty else {
            tell("This page has no text to read (it may be a scan).", brief: true)
            return
        }
        showReadBar()
        let frame = p.frames[i]
        ReadAloud.shared.read(text) { [weak self] r in self?.markOnPage(page, frame: frame, range: r) }
    }

    /// The word being read, marked on the PDF page.
    private func markOnPage(_ page: PDFPage, frame: CGRect, range: NSRange) {
        let mark: UIView
        if let m = objc_getAssociatedObject(self, &pdfMarkKey) as? UIView { mark = m } else {
            mark = UIView()
            mark.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.35)
            mark.layer.cornerRadius = 2
            mark.isUserInteractionEnabled = false
            objc_setAssociatedObject(self, &pdfMarkKey, mark, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        guard range.location != NSNotFound, let sel = page.selection(for: range) else { mark.removeFromSuperview(); return }
        let r = sel.bounds(for: page), box = page.bounds(for: .cropBox)
        guard box.width > 0, box.height > 0, r.width > 0 else { return }
        let x = frame.minX + (r.minX - box.minX) / box.width * frame.width
        let y = frame.minY + (box.maxY - r.maxY) / box.height * frame.height
        let w = r.width / box.width * frame.width, h = r.height / box.height * frame.height
        if mark.superview == nil { world.addSubview(mark) }
        mark.frame = CGRect(x: x + offset.x - 1, y: y + offset.y - 1, width: w + 2, height: h + 2)
        // follow the reading down the page
        let v = visibleBoard
        if y + h > v.maxY - 40 || y < v.minY { glide(toBoard: CGPoint(x: v.minX, y: y - v.height * 0.3)) }
    }

    func showReadBar() {
        if objc_getAssociatedObject(self, &readBarKey) != nil { return }
        let host = UIHostingController(rootView: ReadAloudBar())
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        host.didMove(toParent: self)
        objc_setAssociatedObject(self, &readBarKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
