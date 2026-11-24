import UIKit
import NexusCore

/// Insert › Mark as question, as on the laptop (nexus `Board.tsx` markQuestion, backend `bank_add`): the next drag draws a box round
/// a question (on class slides, a printout, a photo, your notes) and it goes into the subject's question bank as a question of this
/// board (c1, c2, …), with the words under the box read off a printout it is over for its marks, command term and type. A Schoology
/// class board's codes become its unit. The laptop's decision model doesn't run here, so a question with no codes waits for a unit
/// (pick one on its page in the bank).
extension BoardController {
    func markQuestion() {
        guard !readOnly else { toast("This board is read-only"); return }
        guard questionSubject() != nil else {
            toast("File this board's notebook under a subject first (one with a Study folder)")
            return
        }
        // a text block being typed in gives up the keyboard first, so the box gets the drag
        view.window?.endEditing(true)
        view.subviews.first { $0 is QuestionBoxView }?.removeFromSuperview()
        let box = QuestionBoxView(frame: view.bounds)
        box.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        box.onDone = { [weak self, weak box] r in
            box?.removeFromSuperview()
            guard let self, let r else { return }
            self.addQuestion(r, from: box)
        }
        view.addSubview(box)
        toast("Draw a box round the question")
    }

    /// The subject (a workstream with a study folder) this board belongs to: the workstream whose folder holds it, the one its
    /// notebook's notebook.json names, else the one whose name the notebook has.
    func questionSubject() -> String? {
        guard let store else { return nil }
        let studies = StudyLibrary.shared
        if studies.studies.isEmpty { studies.load(store) }
        if let id = WriteOnIt.subject(of: path, store.writeSubjects()), studies.study(id) != nil { return id }
        guard path.hasPrefix("notebooks/"), let nb = path.split(separator: "/").dropFirst().first.map(String.init) else { return nil }
        let meta = (try? FolderAccess.read(root.appendingPathComponent("notebooks/\(nb)/notebook.json"))).flatMap { try? JSONValue.parse($0) }
        if let id = meta?["subject"]?.string, studies.study(id) != nil { return id }
        let byName = studies.studies.filter { SubjectNotebooks.belongs(nb, to: $0.workstream.name) }
        return byName.count == 1 ? byName[0].id : nil
    }

    private func addQuestion(_ r: CGRect, from box: QuestionBoxView?) {
        guard let store, let id = questionSubject(), let study = StudyLibrary.shared.study(id) else { return }
        // the box on the board (units)
        let a = view.convert(r.origin, to: canvas), b = view.convert(CGPoint(x: r.maxX, y: r.maxY), to: canvas)
        let z = canvas.zoomScale
        let rect = CGRect(x: a.x / z - offset.x, y: a.y / z - offset.y, width: (b.x - a.x) / z, height: (b.y - a.y) / z)
        guard rect.width > 8, rect.height > 8 else { return }
        let lib = BankLibrary.shared
        lib.refresh(study, root: root)
        let words = BankPdf.words(root: root, board: path, items: content.items, rect: rect)
        guard let q = lib.addMarked(store, id, board: path, rect: [rect.minX, rect.minY, rect.maxX, rect.maxY], words: words) else {
            toast(lib.problem ?? "Couldn't add it to the question bank", hold: 3)
            lib.problem = nil
            return
        }
        let unit = lib.bank(id)?.questions[path]?.merged(q)?["topics"]?.array?.compactMap(\.string) ?? []
        toast("\(QuestionBank.qName(q)) is in the question bank" + (unit.isEmpty ? "; pick its unit there" : " (\(unit.joined(separator: ", ")))"), hold: 3)
    }
}

/// The box drawn for Mark as question: a dashed rectangle that follows the finger or the Pencil; a tap without a drag gives up.
final class QuestionBoxView: UIView {
    var onDone: ((CGRect?) -> Void)?
    private let shape = CAShapeLayer()
    private var start: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.06)
        shape.fillColor = UIColor.systemGreen.withAlphaComponent(0.10).cgColor
        shape.strokeColor = UIColor.systemGreen.cgColor
        shape.lineWidth = 2
        shape.lineDashPattern = [6, 4]
        layer.addSublayer(shape)
        accessibilityIdentifier = "question-box"
        isAccessibilityElement = true
        accessibilityLabel = "Draw a box round the question"
    }

    required init?(coder: NSCoder) { fatalError() }

    private func rect(to p: CGPoint) -> CGRect {
        guard let s = start else { return .zero }
        return CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        start = touches.first?.location(in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        shape.path = UIBezierPath(roundedRect: rect(to: p), cornerRadius: 4).cgPath
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { onDone?(nil); return }
        let r = rect(to: p)
        onDone?(r.width > 12 && r.height > 12 ? r : nil)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { onDone?(nil) }
}
