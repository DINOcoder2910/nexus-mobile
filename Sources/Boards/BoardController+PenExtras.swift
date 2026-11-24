import UIKit
import SwiftUI
import PencilKit
import NexusCore

/// The pen panel's extras, as on the laptop (desktop/src/board/Board.tsx; mockups new-look/mockups/ipad-pen-sizes-edit,
/// ipad-pen-copy-stroke, ipad-lasso-restyle):
/// - Copy from a stroke (the eyedropper after the sizes): tap any stroke and draw with its pen, or keep its width as a size;
/// - touch and hold a size: set its width with a slider, Save as my default (shared with the laptop through nexus-pens.json) or
///   Reset sizes;
/// - with the Select tool, a colour or a size in the row changes the lassoed ink, one step of Undo, with Undo in the note too.
/// PencilKit doesn't say which strokes its lasso holds, so the board follows the lasso's path itself (the drawing gesture) and takes
/// the strokes mostly inside it (NexusCore PenExtras.lassoed), only while PencilKit has something lassoed.
struct LassoPick {
    /// The picked strokes' places in the drawing.
    var indices: [Int]
    /// How many strokes the drawing had then (a stroke added or taken away ends the pick).
    var count: Int
    /// After a restyle the drawing was set again, so PencilKit's own lasso is gone and the board shows the picked box itself.
    var ours: Bool
    /// Each picked stroke's bounds then: when they change, PencilKit moved what it lassoed.
    var boxes: [CGRect]
}

extension BoardController {
    // MARK: the lasso's strokes

    /// Whether PencilKit holds something in its lasso (it can be copied).
    var canvasHasSelection: Bool { canvas.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil) }

    /// How many strokes a colour or size in the row would change now (0: none).
    var lassoedCount: Int { currentLassoPick()?.indices.count ?? 0 }

    /// The pick, while it still stands: PencilKit still holds it, or the board drew its own box after a restyle.
    func currentLassoPick() -> LassoPick? {
        guard let p = lassoPick, BoardTools.shared.tool == .lasso, p.count == canvas.drawing.strokes.count else { return nil }
        return p.ours || canvasHasSelection ? p : nil
    }

    /// The lasso tracer moved (any tool): with the Select tool, its path is the lasso's.
    @objc func lassoTraced(_ g: UIGestureRecognizer) {
        guard BoardTools.shared.tool == .lasso else { if !lassoTrace.isEmpty { lassoTrace = [] }; return }
        let z = max(canvas.zoomScale, 0.1)
        let at = g.location(in: canvas)
        let p = CGPoint(x: at.x / z, y: at.y / z)
        switch g.state {
        case .began:
            // a pan begins a little way in: start where the finger or Pencil first touched
            let moved = (g as? UIPanGestureRecognizer)?.translation(in: canvas) ?? .zero
            lassoTrace = [CGPoint(x: (at.x - moved.x) / z, y: (at.y - moved.y) / z), p]
            lassoMoved = false
            hidePickBox()
        case .changed:
            lassoTrace.append(p)
        case .ended:
            lassoTrace.append(p)
            let trace = lassoTrace, moved = lassoMoved
            lassoTrace = []
            // PencilKit settles its lasso as the gesture ends: look a moment later
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.pickLassoed(trace, moved: moved) }
        default:
            lassoTrace = []
        }
    }

    /// The strokes a finished lasso holds (or, when the gesture moved what was lassoed, the same ones where they are now).
    func pickLassoed(_ trace: [CGPoint], moved: Bool) {
        defer { bar.refresh() }
        if TestHooks.isLassoBoxRun, let f = trace.first, let l = trace.last {
            let box = CGRect(x: min(f.x, l.x), y: min(f.y, l.y), width: abs(l.x - f.x), height: abs(l.y - f.y))
            let s = canvas.drawing.strokes
            let picked = s.indices.filter { i in strokePoints(s[i]).allSatisfy { box.contains(CGPoint(x: $0.x, y: $0.y)) } }
            lassoPick = picked.isEmpty ? nil : LassoPick(indices: picked, count: s.count, ours: true, boxes: picked.map { s[$0].renderBounds })
            showPickBox()
            return
        }
        guard canvasHasSelection else { lassoPick = nil; return }
        if var p = lassoPick, p.count == canvas.drawing.strokes.count {
            // the gesture dragged what was lassoed (PencilKit moved it): the same strokes stay picked, where they are now
            let s = canvas.drawing.strokes
            let now = p.indices.map { s.indices.contains($0) ? s[$0].renderBounds : .null }
            if moved || now != p.boxes {
                p.ours = false
                p.boxes = now
                lassoPick = p
                return
            }
        }
        guard trace.count >= 3 else { lassoPick = nil; return }
        let poly = trace.map { SIMD2<Double>(Double($0.x), Double($0.y)) }
        var box = CGRect.null
        for q in trace { box = box.union(CGRect(x: q.x, y: q.y, width: 0.1, height: 0.1)) }
        let strokes = canvas.drawing.strokes
        var picked: [Int] = []
        for (i, k) in strokes.enumerated() where k.renderBounds.intersects(box) {
            if PenExtras.lassoed(strokePoints(k), by: poly) { picked.append(i) }
        }
        lassoPick = picked.isEmpty ? nil : LassoPick(indices: picked, count: strokes.count, ours: false, boxes: picked.map { strokes[$0].renderBounds })
    }

    /// The drawing changed: a lassoed stroke moved keeps the pick (the same places), anything else ends it.
    func lassoDrawingChanged() {
        if !lassoTrace.isEmpty { lassoMoved = true }
        guard let p = lassoPick else { return }
        if p.count != canvas.drawing.strokes.count { clearLassoPick() } else if p.ours { showPickBox() }
    }

    func clearLassoPick() {
        lassoPick = nil
        hidePickBox()
    }

    /// A stroke's points in the drawing's units, a few board units apart.
    func strokePoints(_ k: PKStroke) -> [SIMD2<Double>] {
        k.path.interpolatedPoints(by: .distance(4)).map {
            let q = $0.location.applying(k.transform)
            return SIMD2<Double>(Double(q.x), Double(q.y))
        }
    }

    /// A stroke's width: the middle of its points' widths.
    func strokeWidth(_ k: PKStroke) -> Double { PenExtras.width(k.path.map { Double(max($0.size.width, $0.size.height)) }) }

    /// A colour or size tapped in the Select tool's row: the lassoed strokes in it, one step of Undo.
    func restyleLassoed(color: String? = nil, step: Int? = nil) {
        guard !readOnly else { return }
        guard let p = currentLassoPick(), !p.indices.isEmpty else {
            toast("Circle some ink first, then tap a colour or size")
            return
        }
        let tools = BoardTools.shared
        let before = canvas.drawing
        var strokes = before.strokes
        var shownWidth: Double?
        for i in p.indices where strokes.indices.contains(i) {
            let k = strokes[i]
            let ink = color.map { PKInk(k.ink.inkType, color: InkConvert.color($0)) } ?? k.ink
            var path = k.path
            if let step {
                let t = BoardTools.tool(of: k.ink.inkType)
                let row = BoardTools.drawnWidths(t, ink: k.ink.inkType, widths: tools.ownWidths(t))
                let want = row[min(max(0, step), row.count - 1)]
                let now = strokeWidth(k)
                if shownWidth == nil { shownWidth = Double(want) }
                if now > 0 {
                    let f = want / CGFloat(now)
                    let pts = k.path.map { q in
                        PKStrokePoint(location: q.location, timeOffset: q.timeOffset, size: CGSize(width: q.size.width * f, height: q.size.height * f),
                                      opacity: q.opacity, force: q.force, azimuth: q.azimuth, altitude: q.altitude)
                    }
                    path = PKStrokePath(controlPoints: pts, creationDate: k.path.creationDate)
                }
            }
            strokes[i] = PKStroke(ink: ink, path: path, transform: k.transform, mask: k.mask)
        }
        setDrawingQuietly(PKDrawing(strokes: strokes), undoTo: before, name: "Change ink")
        strokeCount = canvas.drawing.strokes.count
        changed()
        lassoPick = LassoPick(indices: p.indices, count: strokes.count, ours: true, boxes: p.indices.map { strokes.indices.contains($0) ? strokes[$0].renderBounds : .null })
        showPickBox()
        bar.refresh()
        let words = PenExtras.restyleText(count: p.indices.count, color: color, width: shownWidth)
        undoToast.show(words, in: view) { [weak self] in
            self?.undo()
            self?.clearLassoPick()
            self?.bar.refresh()
        }
    }

    /// The board's own dashed box round the picked strokes (after a restyle PencilKit's lasso is gone).
    func showPickBox() {
        guard let p = lassoPick else { hidePickBox(); return }
        let s = canvas.drawing.strokes
        var box = CGRect.null
        for i in p.indices where s.indices.contains(i) { box = box.union(s[i].renderBounds) }
        guard !box.isNull else { hidePickBox(); return }
        let z = max(canvas.zoomScale, 0.1)
        pickRing.path = UIBezierPath(rect: box.insetBy(dx: -8 / z, dy: -8 / z)).cgPath
        pickRing.fillColor = UIColor.clear.cgColor
        pickRing.strokeColor = Kit.ui.accent.cgColor
        pickRing.lineWidth = 1.5 / z
        pickRing.lineDashPattern = [NSNumber(value: Double(6 / z)), NSNumber(value: Double(4 / z))]
        if pickRing.superlayer == nil { overWorld.layer.addSublayer(pickRing) }
        pickRing.isHidden = false
    }

    func hidePickBox() { pickRing.isHidden = true }

    // MARK: copy a pen from a stroke

    var copyingStroke: Bool { copyBanner != nil }

    /// The eyedropper: a note at the top ("Tap any stroke to copy its pen", Cancel); the next tap on the board picks a stroke.
    func startCopyFromStroke() {
        if copyingStroke { endCopyFromStroke(); return }
        if writing != nil { endWriting() }
        let cover = UIView(frame: CGRect(x: 0, y: bar.frame.maxY, width: view.bounds.width, height: max(0, view.bounds.height - bar.frame.maxY)))
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .clear
        cover.accessibilityIdentifier = "copy-stroke-cover"
        let tap = UITapGestureRecognizer(target: self, action: #selector(copyTapped(_:)))
        tap.allowedTouchTypes = BoardController.anyTouch
        cover.addGestureRecognizer(tap)

        let pill = UIView()
        pill.backgroundColor = UIColor(white: 0.1, alpha: 0.92)
        pill.layer.cornerRadius = 12
        pill.translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "eyedropper"))
        icon.tintColor = .white
        let words = UILabel()
        words.text = "Tap any stroke to copy its pen"
        words.textColor = .white
        words.font = UIFont.nx(15, .medium)
        words.accessibilityIdentifier = "copy-stroke-note"
        var c = UIButton.Configuration.plain()
        c.title = "Cancel"
        c.baseForegroundColor = UIColor(white: 0.75, alpha: 1)
        let cancel = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.endCopyFromStroke() })
        cancel.accessibilityIdentifier = "copy-stroke-cancel"
        let row = UIStackView(arrangedSubviews: [icon, words, cancel])
        row.spacing = 10
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(row)
        cover.addSubview(pill)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
            pill.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            pill.topAnchor.constraint(equalTo: cover.topAnchor, constant: 12),
        ])
        view.addSubview(cover)
        copyBanner = cover
        bar.refresh()
    }

    func endCopyFromStroke() {
        copyBanner?.removeFromSuperview()
        copyBanner = nil
        bar.refresh()
    }

    @objc func copyTapped(_ g: UITapGestureRecognizer) {
        let z = max(canvas.zoomScale, 0.1)
        let at = g.location(in: canvas)
        let p = CGPoint(x: at.x / z, y: at.y / z)
        guard let i = strokeIndex(at: p, reach: 14 / z) else {
            toast("No stroke there: tap on ink to copy its pen")
            return
        }
        endCopyFromStroke()
        showCopied(canvas.drawing.strokes[i])
    }

    /// A stroke just drawn: the size and width it was drawn with, so Copy from a stroke picks that size (by its path's creation
    /// date, for this session).
    func noteDrawnWith() {
        guard let k = canvas.drawing.strokes.last, let ink = canvas.tool as? PKInkingTool, ink.inkType == k.ink.inkType else { return }
        let t = BoardTools.tool(of: k.ink.inkType)
        drawnWith[k.path.creationDate] = (BoardTools.shared.widthIndex(t), Double(ink.width))
    }

    /// The topmost stroke within `reach` of `p` (the drawing's units), if any.
    func strokeIndex(at p: CGPoint, reach: CGFloat) -> Int? {
        let strokes = canvas.drawing.strokes
        for i in strokes.indices.reversed() {
            let k = strokes[i]
            guard k.renderBounds.insetBy(dx: -reach, dy: -reach).contains(p) else { continue }
            for q in k.path.interpolatedPoints(by: .distance(2)) {
                let at = q.location.applying(k.transform)
                if hypot(at.x - p.x, at.y - p.y) <= reach + max(q.size.width, q.size.height) / 2 { return i }
            }
        }
        return nil
    }

    /// The copied stroke ringed, and a card under it: "Pen · 5.5 px · red", Draw with it, Save as a size.
    func showCopied(_ k: PKStroke) {
        let tools = BoardTools.shared
        let t = BoardTools.tool(of: k.ink.inkType)
        // drawn here this session: the size it was drawn with; else read from its points (PencilKit's point sizes follow the
        // tool's width only roughly, and for touches hardly at all, so a step read from them can be off)
        let known = drawnWith[k.path.creationDate]
        let w = known?.width ?? strokeWidth(k)
        let hex = Pens.short(Pens.color(InkConvert.hex(k.ink.color)) ?? "#1B1B1B")
        let words = PenExtras.strokeText(ink: t == .highlighter ? "Highlighter" : t.title, width: w, color: hex)
        let row = BoardTools.drawnWidths(t, ink: k.ink.inkType, widths: tools.ownWidths(t)).map { Double($0) }
        let step = known?.step ?? PenExtras.nearestStep(w, in: row)
        let range = k.ink.inkType.validWidthRange

        let z = max(canvas.zoomScale, 0.1)
        let ring = k.renderBounds.insetBy(dx: -12 / z, dy: -12 / z)
        pickRing.path = UIBezierPath(roundedRect: ring, cornerRadius: min(ring.height / 2, 40 / z)).cgPath
        pickRing.fillColor = UIColor.clear.cgColor
        pickRing.strokeColor = Kit.ui.accent.cgColor
        pickRing.lineWidth = 3 / z
        pickRing.lineDashPattern = nil
        if pickRing.superlayer == nil { overWorld.layer.addSublayer(pickRing) }
        pickRing.isHidden = false

        let kind: BoardTools.PenKind? = k.ink.inkType == .monoline ? .monoline : k.ink.inkType == .fountainPen ? .fountain : k.ink.inkType == .pen ? .pen : nil
        let use = { [weak self] (keep: Bool) in
            guard let self else { return }
            self.dismiss(animated: true)
            self.hidePickBox()
            if keep { tools.setOwnWidth(t, step, CGFloat(PenExtras.settable(w, range: Double(range.lowerBound)...Double(range.upperBound)))) }
            if t == .pen, let kind { tools.penKind = kind }
            let replaced = tools.take(t, color: hex, step: step)
            self.toolChanged()
            self.toast(keep ? "Saved as the \(BoardTools.widthNames[step]) size: \(PenExtras.widthText(w))"
                            : replaced ? "Drawing with it (its colour took the picked colour's place)" : "Drawing with it")
        }
        let card = StrokeCopyCard(words: words, color: Color(uiColor: InkConvert.color(hex)), width: w,
                                  draw: { use(false) }, save: { use(true) })
        let host = UIHostingController(rootView: card.tint(Theme.accent))
        host.modalPresentationStyle = .popover
        host.preferredContentSize = CGSize(width: 340, height: 132)
        host.popoverPresentationController?.sourceView = view
        host.popoverPresentationController?.sourceRect = overWorld.convert(ring, to: view)
        host.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        host.presentationController?.delegate = PopoverEnds.shared
        PopoverEnds.shared.ended = { [weak self] in self?.hidePickBox() }
        present(host, animated: true)
    }

    // MARK: a size's own width

    /// Touch and hold a size: its width on a slider, the line it draws, Save as my default and Reset sizes.
    func editSize(_ t: BoardTool, _ i: Int) {
        guard !readOnly, presentedViewController == nil else { return }
        let tools = BoardTools.shared
        let k = t == .shapes ? BoardTool.pen : t
        let own = tools.ownWidths(k)
        guard own.indices.contains(i) else { return }
        let r = tools.inkType(k)?.validWidthRange ?? 0.2...120
        let range = max(0.2, Double(r.lowerBound))...min(120, Double(r.upperBound))
        let start = min(range.upperBound, max(range.lowerBound, Double(own[i])))
        let name = BoardTools.widthNames[i]
        let card = SizeEditCard(title: name + " size", value: start, range: range, color: Color(uiColor: InkConvert.color(tools.color(k))),
                                canReset: tools.hasOwnWidths(k),
                                save: { [weak self] w in
                                    tools.setOwnWidth(k, i, CGFloat(PenExtras.settable(w, range: range)))
                                    tools.setWidthIndex(t, i)
                                    self?.dismiss(animated: true)
                                    self?.toolChanged()
                                    self?.toast("\(name) is \(PenExtras.widthText(PenExtras.settable(w, range: range))) now, here and on the laptop")
                                },
                                reset: { [weak self] in
                                    tools.resetWidths(k)
                                    self?.dismiss(animated: true)
                                    self?.toolChanged()
                                    self?.toast("Sizes back to the built-in ones")
                                })
        let host = UIHostingController(rootView: card.tint(Theme.accent))
        host.modalPresentationStyle = .popover
        host.preferredContentSize = CGSize(width: 400, height: 210)
        let dot = findView(in: bar) { $0.accessibilityLabel == name && $0 is UIButton }
        host.popoverPresentationController?.sourceView = dot ?? bar
        host.popoverPresentationController?.sourceRect = dot?.bounds ?? CGRect(x: bar.bounds.midX, y: bar.bounds.height - 30, width: 1, height: 1)
        host.popoverPresentationController?.permittedArrowDirections = [.up]
        present(host, animated: true)
    }

    func findView(in v: UIView, _ match: (UIView) -> Bool) -> UIView? {
        if match(v), v.window != nil, !v.isHidden { return v }
        for s in v.subviews { if let f = findView(in: s, match) { return f } }
        return nil
    }
}

/// Clears the copied stroke's ring when its card is closed by a tap outside it.
final class PopoverEnds: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = PopoverEnds()
    var ended: (() -> Void)?
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { ended?(); ended = nil }
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
}

/// The card under a copied stroke.
struct StrokeCopyCard: View {
    let words: String
    let color: Color
    let width: Double
    let draw: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                WaveLine(width: width, color: color).frame(width: 64, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(words).font(.nx(.headline, .semibold)).foregroundStyle(Kit.ink).accessibilityIdentifier("copy-stroke-words")
                    Text("from this stroke").font(.nx(.subheadline)).foregroundStyle(Kit.muted)
                }
            }
            HStack(spacing: 10) {
                Button("Draw with it", action: draw).buttonStyle(.kitPrimary).accessibilityIdentifier("copy-stroke-draw")
                Button("Save as a size", action: save).buttonStyle(.kit).accessibilityIdentifier("copy-stroke-save")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Touch and hold a size: its width.
struct SizeEditCard: View {
    let title: String
    @State var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let canReset: Bool
    let save: (Double) -> Void
    let reset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.nx(.subheadline, .semibold)).foregroundColor(Kit.ink)
                    + Text("  hold any size to change it").font(.nx(.subheadline)).foregroundColor(Kit.muted)
                Spacer()
                Text(PenExtras.widthText(PenExtras.settable(value, range: range))).font(.nx(.subheadline)).monospacedDigit()
                    .foregroundStyle(Kit.ink).accessibilityIdentifier("size-edit-value")
            }
            Slider(value: $value, in: range).accessibilityIdentifier("size-edit-slider").accessibilityLabel("Width")
            WaveLine(width: value, color: color).frame(height: 40)
            HStack(spacing: 12) {
                Button("Save as my default") { save(value) }.buttonStyle(.kitPrimary).accessibilityIdentifier("size-edit-save")
                Button("Reset sizes", action: reset).buttonStyle(.kit).disabled(!canReset).accessibilityIdentifier("size-edit-reset")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A wave drawn at a width, in an ink's colour.
struct WaveLine: View {
    let width: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            Path { p in
                let w = g.size.width, h = g.size.height, pad: CGFloat = 10
                p.move(to: CGPoint(x: pad, y: h / 2))
                var x = pad
                while x <= w - pad {
                    let f = (x - pad) / max(1, w - 2 * pad)
                    p.addLine(to: CGPoint(x: x, y: h / 2 + sin(f * .pi * 2) * h * 0.22))
                    x += 3
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: CGFloat(min(max(width, 0.5), 24)), lineCap: .round, lineJoin: .round))
        }
    }
}

/// A note at the foot of the board with an Undo button ("Changed 4 strokes to blue, 5 px  Undo"); it goes by itself after a while.
final class UndoToast: UIView {
    private let words = UILabel()
    private let button = UIButton(type: .system)
    private var action: (() -> Void)?
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.1, alpha: 0.92)
        layer.cornerRadius = 12
        words.textColor = .white
        words.font = UIFont.nx(15, .medium)
        words.accessibilityIdentifier = "undo-toast-words"
        var c = UIButton.Configuration.plain()
        c.title = "Undo"
        c.baseForegroundColor = Theme.uiDynamic(light: "#7DDCA6", dark: "#7DDCA6")
        button.configuration = c
        button.accessibilityIdentifier = "undo-toast-undo"
        button.addAction(UIAction { [weak self] _ in
            let a = self?.action
            self?.hide()
            a?()
        }, for: .primaryActionTriggered)
        let row = UIStackView(arrangedSubviews: [words, button])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ text: String, in host: UIView, undo: @escaping () -> Void) {
        words.text = text
        action = undo
        if superview !== host {
            removeFromSuperview()
            host.addSubview(self)
            NSLayoutConstraint.activate([
                centerXAnchor.constraint(equalTo: host.centerXAnchor),
                bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            ])
        }
        host.bringSubviewToFront(self)
        layer.removeAllAnimations()
        alpha = 1
        isHidden = false
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: w)
    }

    func hide() {
        hideWork?.cancel()
        action = nil
        UIView.animate(withDuration: 0.25, animations: { self.alpha = 0 }, completion: { _ in if self.alpha == 0 { self.isHidden = true } })
    }
}