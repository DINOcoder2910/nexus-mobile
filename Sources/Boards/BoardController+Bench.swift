import UIKit
import PencilKit
import NexusCore

/// The UI check's measure of a save on a full board (`-NexusTestBigBoard`, Sources/Common/TestHooks.swift): a stroke is added and the
/// board saved, ten times, and the times are shown in a label UITests/BoardSpeedTests reads. Beside them, what the save used to do
/// on this board (every tile as text three times, every canvas stroke into the files' form), timed the same way.
extension BoardController {
    func saveBenchIfAsked() {
        guard TestHooks.isBigBoardRun, !readOnly, view.viewWithTag(9_191) == nil else { return }
        let label = UILabel()
        label.tag = 9_191
        label.accessibilityIdentifier = "save-bench"
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        label.numberOfLines = 0
        label.text = "save bench: waiting"
        view.addSubview(label)
        label.frame = CGRect(x: 20, y: view.bounds.height - 120, width: min(680, view.bounds.width - 40), height: 80)
        label.autoresizingMask = [.flexibleTopMargin]
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.runSaveBench(label) }
    }

    private func runSaveBench(_ label: UILabel) {
        var times: [Double] = []
        let base = visibleBoard
        for i in 0..<10 {
            // a written letter: one new stroke near the top left of the screen
            let x = base.minX + 120 + CGFloat(i) * 20 + offset.x, y = base.minY + 140 + offset.y
            let pts = (0..<40).map { k -> PKStrokePoint in
                let t = CGFloat(k) / 39
                return PKStrokePoint(location: CGPoint(x: x + t * 14, y: y + sin(t * 9) * 6), timeOffset: Double(t) * 0.3,
                                     size: CGSize(width: 2.4, height: 2.4), opacity: 1, force: 0.6, azimuth: 1.2, altitude: 1.1)
            }
            var d = canvas.drawing
            d.strokes.append(PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: pts, creationDate: Date())))
            canvas.drawing = d
            dirty = true
            let t0 = CACurrentMediaTime()
            saveNow()
            times.append((CACurrentMediaTime() - t0) * 1000)
        }
        // what a save used to cost here: every tile as text, three times, and every canvas stroke turned into the files' form
        let t1 = CACurrentMediaTime()
        for _ in 0..<3 {
            var byKey: [String: (s: [BoardStroke], i: [BoardItem])] = [:]
            for s in content.strokes { byKey[s.tileKey, default: ([], [])].s.append(s) }
            for it in content.items { byKey[it.tileKey, default: ([], [])].i.append(it) }
            for (_, t) in byKey { _ = BoardFiles.tileJSON(strokes: t.s, items: t.i) }
        }
        for k in canvas.drawing.strokes { _ = InkConvert.boardStroke(k, offset: offset, id: "") }
        let old = (CACurrentMediaTime() - t1) * 1000
        let sorted = times.sorted()
        let median = sorted[sorted.count / 2], worst = sorted.last ?? 0
        label.text = String(format: "save bench, %d strokes: a save now takes %.0f ms (median), %.0f ms at worst; the old way's extra work alone: %.0f ms",
                            canvas.drawing.strokes.count, median, worst, old)
    }
}
