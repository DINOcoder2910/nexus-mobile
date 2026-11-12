import UIKit
import PencilKit
import NexusCore

/// The board's paper colour and pattern (board.json `paper`, NexusCore Paper), drawn behind everything in screen space for the
/// part of the board on screen, so it zooms with the writing and costs nothing off screen.
final class PaperView: UIView {
    var paper = Paper.plain { didSet { if paper != oldValue { setNeedsDisplay() } } }
    var dark = false { didSet { if dark != oldValue { backgroundColor = PaperView.back(dark); setNeedsDisplay() } } }
    private var visible = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var zoom: CGFloat = 1

    static func back(_ dark: Bool) -> UIColor {
        dark ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
             : UIColor(red: 0xFB / 255, green: 0xFA / 255, blue: 0xF7 / 255, alpha: 1)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        isUserInteractionEnabled = false
        contentMode = .redraw
        backgroundColor = PaperView.back(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The board rectangle on screen (board units) and the zoom (points per unit).
    func show(visible: CGRect, zoom: CGFloat) {
        guard visible != self.visible || zoom != self.zoom else { return }
        self.visible = visible
        self.zoom = zoom
        if paper.kind != .plain { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        PaperView.back(dark).setFill()
        cg.fill(rect)
        let r = (x: Double(visible.minX), y: Double(visible.minY), w: Double(visible.width), h: Double(visible.height))
        let p = paper.pattern(visible: r, zoom: Double(zoom))
        guard p.alpha > 0 else { return }
        let ink = dark ? UIColor.white : UIColor.black
        let z = zoom
        func sx(_ x: Double) -> CGFloat { (CGFloat(x) - visible.minX) * z }
        func sy(_ y: Double) -> CGFloat { (CGFloat(y) - visible.minY) * z }
        if p.dots {
            let r = min(1.6, max(0.8, 1.15 * z.squareRoot()))
            ink.withAlphaComponent(CGFloat((dark ? 0.26 : 0.24) * p.alpha)).setFill()
            let path = CGMutablePath()
            for y in p.ys {
                let yy = sy(y)
                for x in p.xs { path.addEllipse(in: CGRect(x: sx(x) - r, y: yy - r, width: r * 2, height: r * 2)) }
            }
            cg.addPath(path)
            cg.fillPath()
            return
        }
        let w = bounds.width, h = bounds.height
        let px = 1 / max(1, traitCollection.displayScale)
        func stroke(_ strong: Bool, _ lines: (CGMutablePath) -> Void) {
            let path = CGMutablePath()
            lines(path)
            guard !path.isEmpty else { return }
            cg.setStrokeColor(ink.withAlphaComponent(CGFloat((strong ? 0.2 : 0.1) * p.alpha)).cgColor)
            cg.setLineWidth(strong ? max(px, 1) : max(px, 0.75))
            cg.addPath(path)
            cg.strokePath()
        }
        for strong in [false, true] {
            stroke(strong) { path in
                for (i, x) in p.xs.enumerated() where p.strongX.contains(i) == strong {
                    path.move(to: CGPoint(x: sx(x), y: 0)); path.addLine(to: CGPoint(x: sx(x), y: h))
                }
                for (i, y) in p.ys.enumerated() where p.strongY.contains(i) == strong {
                    path.move(to: CGPoint(x: 0, y: sy(y))); path.addLine(to: CGPoint(x: w, y: sy(y)))
                }
            }
        }
    }
}

/// Dark boards: the paper, the canvas (PencilKit shows the ink in its dark colours), the bar and the items switch together; PDF
/// pages are dimmed a little. Follows the iPad unless the board menu says always or never (app-wide).
extension BoardController {
    var systemDark: Bool {
        (view.window?.windowScene?.traitCollection.userInterfaceStyle ?? UIScreen.main.traitCollection.userInterfaceStyle) == .dark
    }

    var boardIsDark: Bool {
        switch BoardTools.shared.dark {
        case .always: return true
        case .never: return false
        case .follow: return systemDark
        }
    }

    func applyTheme() {
        guard isViewLoaded else { return }
        let dark = boardIsDark
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        if overrideUserInterfaceStyle != style || paperView.dark != dark {
            overrideUserInterfaceStyle = style
            canvas.overrideUserInterfaceStyle = style
            paperView.dark = dark
            view.backgroundColor = PaperView.back(dark)
            for p in pdfs.values { p.setDim(dark) }
            rebuildItems()
            for v in itemViews.values { v.setNeedsDisplay() }
        }
        applyTool()
        bar.dark = dark
    }

    /// Watch the iPad's light / dark setting (the board itself is overridden, so its own traits don't change).
    func watchSystemStyle() {
        guard themeWatch == nil, let scene = view.window?.windowScene else { return }
        themeWatch = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (_: UIWindowScene, _: UITraitCollection) in
            self?.applyTheme()
        }
    }

    /// board.json's paper.
    var paper: Paper { Paper(content.meta?["paper"]) }

    func setPaper(_ p: Paper) {
        guard !readOnly, var meta = content.meta ?? (try? JSONValue.parse(BoardFormat.boardJSON())) else { return }
        meta = meta.setting("paper", p.json)
        content.meta = meta
        paperView.paper = p
        changed()
        bar.refresh()
    }
}
