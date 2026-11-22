import UIKit
import PencilKit
import NexusCore

/// The UI check's measure of a save on a full board (`-NexusTestBigBoard`, Sources/Common/TestHooks.swift): a stroke is added and the
/// board saved, ten times, and the times are shown in a label UITests/BoardSaveSpeedTests reads.
extension BoardController {
    func saveBenchIfAsked() {
        if TestHooks.isSpaceDragRun { spaceBenchIfAsked(); return }
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

    /// One save at a time with the main thread free between them (a UI test can't read the screen while the app is busy), once
    /// the board's tiles have been made in the background as on any board just opened.
    private func runSaveBench(_ label: UILabel) {
        var times: [Double] = []
        let base = visibleBoard
        var waited = 0
        func start() {
            if !content.tileMemo.primed && waited < 240 {
                waited += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { start() }
                return
            }
            save(0)
        }
        func save(_ i: Int) {
            guard i < 10 else { return done() }
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
            label.text = "save bench: \(i + 1) of 10 saves, waiting"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { save(i + 1) }
        }
        func done() {
            let sorted = times.sorted()
            let median = sorted[sorted.count / 2], worst = sorted.last ?? 0
            label.text = String(format: "save bench, %d strokes (tiles ready after %.1f s): a save takes %.0f ms (median), %.0f ms at worst",
                                canvas.drawing.strokes.count, Double(waited) * 0.5, median, worst)
        }
        start()
    }

    /// The pens file as last read or written, on one line, for UITests/SharedPensTests (`-NexusTestSharedPens`).
    func pensProbe() {
        guard BoardTools.testShared else { return }
        let label: UILabel
        if let l = view.viewWithTag(9_194) as? UILabel { label = l } else {
            label = UILabel()
            label.tag = 9_194
            label.accessibilityIdentifier = "pens-file"
            label.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
            label.textColor = .white
            label.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
            view.addSubview(label)
            label.frame = CGRect(x: 10, y: view.bounds.height - 30, width: min(600, view.bounds.width - 20), height: 22)
            label.autoresizingMask = [.flexibleTopMargin, .flexibleRightMargin]
        }
        label.text = (BoardTools.shared.lastFileText ?? "no pens file").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    /// The last stroke's ink and width, and the tool's, for UITests/PenOptionsTests (`-NexusTestPenProbe`).
    func penProbe() {
        let label: UILabel
        if let l = view.viewWithTag(9_193) as? UILabel { label = l } else {
            label = UILabel()
            label.tag = 9_193
            label.accessibilityIdentifier = "pen-probe"
            label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            label.backgroundColor = UIColor(white: 0.1, alpha: 0.7)
            view.addSubview(label)
            label.frame = CGRect(x: view.bounds.width - 330, y: view.bounds.height - 30, width: 320, height: 22)
            label.autoresizingMask = [.flexibleTopMargin, .flexibleLeftMargin]
        }
        guard let k = canvas.drawing.strokes.last else { return }
        let sizes = k.path.map { $0.size.width }.sorted()
        let mid = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
        let tool = (canvas.tool as? PKInkingTool).map { String(format: "%.2f", $0.width) } ?? "-"
        label.text = String(format: "probe %@ stroke %.2f tool %@", k.ink.inkType.rawValue, mid, tool)
    }
}
