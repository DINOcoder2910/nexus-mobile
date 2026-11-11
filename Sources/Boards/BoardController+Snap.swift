import UIKit
import PencilKit
import NexusCore

/// Hold to make a shape (the laptop's shapes.js, NexusCore Shapes): write a line, circle, ellipse, rectangle or triangle and keep the
/// Pencil still at the end. While you hold, the shape it will become is drawn over your stroke; when you lift, the stroke is replaced
/// by that shape in the same pen, colour and width. Undo brings the stroke back as written.
///
/// The hold is noticed three ways, so one failing doesn't stop it: the watcher's display link while the Pencil is down (and the
/// preview), the touch's timestamps when it lifts, and the stroke's own point times (`Shapes.endsInHold`).
extension BoardController {
    /// how still (screen points) and how long (seconds) a hold is
    static let holdStill: CGFloat = 4
    static let holdTime: TimeInterval = 0.55

    func setUpSnap() {
        hold.holdTime = BoardController.holdTime
        hold.still = BoardController.holdStill
        hold.onHold = { [weak self] in self?.holdNoticed() }
        hold.onEnd = { [weak self] held in self?.pencilLifted(held) }

        snapOverlay.isUserInteractionEnabled = false
        snapOverlay.frame = view.bounds
        snapOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        for l in [snapHalo, snapLine] {
            l.fillColor = nil
            l.lineCap = .round
            l.lineJoin = .round
            snapOverlay.layer.addSublayer(l)
        }
        view.addSubview(snapOverlay)
    }

    /// The Pencil has been still for a moment, still down: work out the shape from the points written so far and show it.
    func holdNoticed() {
        let z = canvas.zoomScale
        let pts = hold.points.map { SIMD2<Double>(Double($0.x / z - offset.x), Double($0.y / z - offset.y)) }
        guard let shape = Shapes.recognize(pts) else {
            pendingShape = nil
            if pathLength(pts) * Double(z) > 60 { toast("Hold noticed: no shape there") }
            return
        }
        pendingShape = shape
        showSnapPreview(shape)
    }

    func showSnapPreview(_ shape: Shapes.Recognized) {
        let z = canvas.zoomScale, o = canvas.contentOffset
        let path = UIBezierPath()
        for (i, p) in shape.points.enumerated() {
            let q = CGPoint(x: (CGFloat(p.x) + offset.x) * z - o.x, y: (CGFloat(p.y) + offset.y) * z - o.y)
            if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
        }
        let tool = toolPicker.selectedTool as? PKInkingTool
        let width = max(2, (tool?.width ?? 3) * z * 0.6)
        snapLine.path = path.cgPath
        snapLine.strokeColor = (tool?.color ?? .black).cgColor
        snapLine.lineWidth = width
        snapHalo.path = path.cgPath
        snapHalo.strokeColor = UIColor.systemBlue.withAlphaComponent(0.28).cgColor
        snapHalo.lineWidth = width + 10
        snapOverlay.isHidden = false
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func hideSnapPreview() {
        snapLine.path = nil
        snapHalo.path = nil
        snapOverlay.isHidden = true
    }

    /// The Pencil lifted. If its stroke has already landed on the canvas, snap it now; otherwise the canvas's change will.
    func pencilLifted(_ held: Bool) {
        hideSnapPreview()
        if let n = awaitingSnap {
            awaitingSnap = nil
            let landed = canvas.drawing.strokes.count == n
            if landed, held || endsInHold(canvas.drawing.strokes[n - 1]) {
                _ = hold.take()
                snapLastStroke()
            }
            pendingShape = nil
        }
    }

    /// A new stroke landed on the canvas (from canvasViewDrawingDidChange).
    func strokeLanded() {
        let n = canvas.drawing.strokes.count
        if hold.touching {
            awaitingSnap = n // the touch hasn't ended yet: pencilLifted decides
            return
        }
        let held = hold.take()
        if let last = canvas.drawing.strokes.last, held || endsInHold(last) { snapLastStroke() }
        pendingShape = nil
    }

    func endsInHold(_ k: PKStroke) -> Bool {
        let s = InkConvert.boardStroke(k, offset: offset, id: "")
        return Shapes.endsInHold(s.points, still: Double(BoardController.holdStill / canvas.zoomScale), hold: BoardController.holdTime)
    }

    /// Replace the last stroke with the shape it was meant to be (the one shown while holding, else worked out from the stroke).
    func snapLastStroke() {
        var strokes = canvas.drawing.strokes
        guard let stroke = strokes.last else { return }
        let s = InkConvert.boardStroke(stroke, offset: offset, id: "")
        guard let shape = pendingShape ?? Shapes.recognize(s.points.map { SIMD2<Double>($0[0], $0[1]) }) else {
            if pathLength(s.points.map { SIMD2<Double>($0[0], $0[1]) }) * Double(canvas.zoomScale) > 60 { toast("Hold noticed: no shape there") }
            return
        }
        pendingShape = nil
        let points = Shapes.shapePoints(shape, written: s.points)
        guard points.count >= 2 else { return }
        var snapped = s
        snapped.points = points
        snapped.ranges = nil
        guard let k = InkConvert.pkStrokes(snapped, offset: offset).first else { return }
        let before = canvas.drawing
        strokes[strokes.count - 1] = PKStroke(ink: PKInk(stroke.ink.inkType, color: stroke.ink.color), path: k.path, transform: .identity, mask: nil)
        setDrawingQuietly(PKDrawing(strokes: strokes), undoTo: before, name: "Shape")
        strokeCount = canvas.drawing.strokes.count
    }

    /// Set the drawing without it counting as a new stroke, with an undo step back to `before`.
    func setDrawingQuietly(_ drawing: PKDrawing, undoTo before: PKDrawing, name: String) {
        shifting = true
        canvas.drawing = drawing
        shifting = false
        canvas.undoManager?.registerUndo(withTarget: self) { me in
            let now = me.canvas.drawing
            me.setDrawingQuietly(before, undoTo: now, name: name)
            me.strokeCount = me.canvas.drawing.strokes.count
            me.changed()
        }
        canvas.undoManager?.setActionName(name)
    }

    func pathLength(_ p: [SIMD2<Double>]) -> Double {
        guard p.count > 1 else { return 0 }
        var L = 0.0
        for i in 1..<p.count { L += hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y) }
        return L
    }

    /// A short note at the top of the board that fades by itself (never in the way of writing).
    func toast(_ message: String) {
        toastLabel.text = "  " + message + "  "
        if toastLabel.superview == nil {
            toastLabel.font = .preferredFont(forTextStyle: .subheadline)
            toastLabel.textColor = .white
            toastLabel.backgroundColor = UIColor(white: 0.12, alpha: 0.88)
            toastLabel.layer.cornerRadius = 15
            toastLabel.layer.masksToBounds = true
            toastLabel.textAlignment = .center
            toastLabel.isUserInteractionEnabled = false
            view.addSubview(toastLabel)
        }
        toastLabel.sizeToFit()
        toastLabel.frame.size.height = 30
        toastLabel.center = CGPoint(x: view.bounds.midX, y: view.safeAreaInsets.top + 30)
        view.bringSubviewToFront(toastLabel)
        toastLabel.layer.removeAllAnimations()
        toastLabel.alpha = 1
        UIView.animate(withDuration: 0.3, delay: 1.4, options: [.beginFromCurrentState, .allowUserInteraction]) { [weak self] in
            self?.toastLabel.alpha = 0
        }
    }
}
