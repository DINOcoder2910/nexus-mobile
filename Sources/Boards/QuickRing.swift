import UIKit

/// The quick ring's settings: on or off, and where it sits (its side, how far down, tucked into the edge). Kept between boards and
/// launches, the same on every board.
enum QuickRingPrefs {
    private static var d: UserDefaults { .standard }
    static var on: Bool {
        get { d.object(forKey: "board.ring.on") as? Bool ?? true }
        set { d.set(newValue, forKey: "board.ring.on") }
    }
    /// true: the right side of the screen.
    static var right: Bool {
        get { d.object(forKey: "board.ring.right") as? Bool ?? true }
        set { d.set(newValue, forKey: "board.ring.right") }
    }
    /// How far down the screen, 0 at the top and 1 at the bottom.
    static var down: CGFloat {
        get { CGFloat(d.object(forKey: "board.ring.down") as? Double ?? 0.62) }
        set { d.set(Double(newValue), forKey: "board.ring.down") }
    }
    static var tucked: Bool {
        get { d.bool(forKey: "board.ring.tucked") }
        set { d.set(newValue, forKey: "board.ring.tucked") }
    }
}

/// One choice in the ring's fan: a tool, one of the ink's colours or one of its sizes.
enum RingChoice: Equatable {
    case tool(BoardTool)
    case color(Int)
    case size(Int)
}

/// The quick ring: a small round button that floats over the board at the edge of the screen and shows the tool, colour and size in
/// use. Tap it and a fan of choices springs open toward the middle of the screen (four tools, three of the ink's colours, two sizes):
/// tap one. Or hold it and, without lifting, slide onto a choice and let go; sliding back to the button changes nothing. A double tap
/// goes back to the last tool. Drag the button to move it (it settles on the nearer side), push it into the edge and it tucks away as
/// a small tab; tap the tab to bring it back. It fades while you write. A pick flies into the button, which pops with a ripple in the
/// new colour.
final class QuickRing: UIView {
    weak var board: BoardController?

    // sizes, from the prototype (new-look/prototypes/ring-demo.html)
    static let bubbleSize: CGFloat = 62
    static let coreSize: CGFloat = 42
    static let innerRadius: CGFloat = 40
    static let outerRadius: CGFloat = 150
    static let itemRadius: CGFloat = 98
    static let holdReach: CGFloat = 320
    static let holdTime: TimeInterval = 0.3
    static let doubleTapTime: TimeInterval = 0.32
    static let sideInset: CGFloat = 50
    static let tuckZone: CGFloat = 40
    static let plate = UIColor(red: 28 / 255, green: 28 / 255, blue: 26 / 255, alpha: 0.94)
    static let plateHot = UIColor(red: 58 / 255, green: 58 / 255, blue: 54 / 255, alpha: 0.97)

    private enum State { case idle, pressing, moving, holdOpen, tapOpen, tucked }
    private var state = State.idle

    let bubble = UIView()
    private let core = UIView()
    private let coreIcon = UIImageView()
    private let badge = UIView()
    private let badgeDot = UIView()
    private let progress = CAShapeLayer()
    let tab = UIView()
    private let fan = UIView()
    private var items: [RingItemView] = []
    private let label = PaddedLabel()
    private let caption = PaddedLabel()

    private var centre = CGPoint.zero
    private var pressStart = CGPoint.zero
    private var grabOffset = CGPoint.zero
    private var holdTimer: Timer?
    private var lastTap: Date?
    private var touchBeganOnBubble = false
    private var hot: Int?
    private var restoreTimer: Timer?
    private let select = UISelectionFeedbackGenerator()
    private let thump = UIImpactFeedbackGenerator(style: .medium)
    private let tick = UIImpactFeedbackGenerator(style: .light)

    var isOpen: Bool { state == .holdOpen || state == .tapOpen }
    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        accessibilityIdentifier = "quick-ring-layer"

        fan.isUserInteractionEnabled = false
        fan.isHidden = true
        addSubview(fan)

        bubble.frame = CGRect(x: 0, y: 0, width: Self.bubbleSize, height: Self.bubbleSize)
        bubble.backgroundColor = Self.plate
        bubble.layer.cornerRadius = Self.bubbleSize / 2
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.28
        bubble.layer.shadowRadius = 10
        bubble.layer.shadowOffset = CGSize(width: 0, height: 4)
        bubble.isUserInteractionEnabled = false
        bubble.isAccessibilityElement = true
        bubble.accessibilityIdentifier = "quick-ring"
        bubble.accessibilityTraits = .button
        bubble.accessibilityHint = "Tap for tools, colours and sizes. Hold and slide to pick one."
        addSubview(bubble)

        let ring = UIBezierPath(arcCenter: CGPoint(x: Self.bubbleSize / 2, y: Self.bubbleSize / 2), radius: Self.bubbleSize / 2 + 3,
                                startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: true)
        progress.path = ring.cgPath
        progress.fillColor = UIColor.clear.cgColor
        progress.strokeColor = Kit.ui.accent.cgColor
        progress.lineWidth = 3
        progress.lineCap = .round
        progress.strokeEnd = 0
        bubble.layer.addSublayer(progress)

        core.frame = CGRect(x: (Self.bubbleSize - Self.coreSize) / 2, y: (Self.bubbleSize - Self.coreSize) / 2, width: Self.coreSize, height: Self.coreSize)
        core.layer.cornerRadius = Self.coreSize / 2
        core.isUserInteractionEnabled = false
        bubble.addSubview(core)
        coreIcon.frame = core.bounds.insetBy(dx: 10, dy: 10)
        coreIcon.contentMode = .scaleAspectFit
        coreIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        core.addSubview(coreIcon)

        badge.frame = CGRect(x: Self.bubbleSize - 20, y: Self.bubbleSize - 20, width: 20, height: 20)
        badge.backgroundColor = UIColor(white: 0.98, alpha: 1)
        badge.layer.cornerRadius = 10
        badge.layer.borderColor = Self.plate.cgColor
        badge.layer.borderWidth = 2
        badge.isUserInteractionEnabled = false
        bubble.addSubview(badge)
        badgeDot.backgroundColor = UIColor(white: 0.1, alpha: 1)
        badge.addSubview(badgeDot)

        tab.frame = CGRect(x: 0, y: 0, width: 22, height: 76)
        tab.backgroundColor = Self.plate
        tab.layer.cornerRadius = 11
        tab.layer.shadowColor = UIColor.black.cgColor
        tab.layer.shadowOpacity = 0.22
        tab.layer.shadowRadius = 6
        tab.isHidden = true
        tab.isUserInteractionEnabled = false
        tab.isAccessibilityElement = true
        tab.accessibilityIdentifier = "quick-ring-tab"
        tab.accessibilityLabel = "Bring back the quick ring"
        tab.accessibilityTraits = .button
        for i in 0..<3 {
            let grip = UIView(frame: CGRect(x: 7, y: 28 + CGFloat(i) * 8, width: 8, height: 2))
            grip.backgroundColor = UIColor(white: 1, alpha: 0.55)
            grip.layer.cornerRadius = 1
            tab.addSubview(grip)
        }
        addSubview(tab)

        for l in [label, caption] {
            l.font = UIFont.nx(14, .semibold)
            l.textColor = .white
            l.backgroundColor = Self.plate
            l.layer.cornerRadius = 12
            l.layer.masksToBounds = true
            l.alpha = 0
            l.textAlignment = .center
            l.isUserInteractionEnabled = false
            addSubview(l)
        }
        label.accessibilityIdentifier = "quick-ring-label"
        caption.font = UIFont.nx(13, .medium)
        caption.accessibilityIdentifier = "quick-ring-caption"
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: where it sits

    private var safe: UIEdgeInsets { superview?.safeAreaInsets ?? .zero }
    /// The band the ring may sit in: below the board's bar, above the bottom edge.
    private var band: ClosedRange<CGFloat> {
        let top = (board?.topInset ?? safe.top) + Self.bubbleSize / 2 + 12
        let bottom = bounds.height - safe.bottom - Self.bubbleSize / 2 - 12
        return top...max(top, bottom)
    }

    private var placedFor = (CGSize.zero, CGFloat(-1))

    /// Called from the board's layout: places the ring again only when the screen's size or the bar's height changed (a layout pass
    /// for anything else leaves an open fan alone).
    func layOut(top: CGFloat) {
        guard placedFor.0 != bounds.size || placedFor.1 != top else { return }
        placedFor = (bounds.size, top)
        place()
    }

    /// Puts the ring where its settings say (after a turn, a resize or the bar folding).
    func place() {
        guard bounds.width > 0 else { return }
        if isOpen { close(animated: false) }
        let y = band.lowerBound + (band.upperBound - band.lowerBound) * min(1, max(0, QuickRingPrefs.down))
        centre = CGPoint(x: QuickRingPrefs.right ? bounds.width - safe.right - Self.sideInset : safe.left + Self.sideInset, y: y)
        bubble.transform = .identity
        bubble.center = centre
        layOutTab()
        if QuickRingPrefs.tucked { state = .tucked; bubble.alpha = 0; bubble.isHidden = true; tab.isHidden = false; tab.alpha = 1 }
        else { if state == .tucked { state = .idle }; bubble.isHidden = false; bubble.alpha = 1; tab.isHidden = true }
        refresh()
    }

    private func layOutTab() {
        tab.center = CGPoint(x: QuickRingPrefs.right ? bounds.width - safe.right - 11 + 4 : safe.left + 11 - 4, y: centre.y)
    }

    // MARK: touches

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isHidden || alpha < 0.01 { return false }
        if isOpen || state == .pressing || state == .moving { return true }
        if state == .tucked { return tab.frame.insetBy(dx: -14, dy: -10).contains(point) }
        return bubble.frame.insetBy(dx: -6, dy: -6).contains(point)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { self.point(inside: point, with: event) ? self : nil }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        wake()
        switch state {
        case .tucked:
            untuck()
        case .tapOpen:
            touchBeganOnBubble = hypot(p.x - centre.x, p.y - centre.y) < Self.innerRadius
            if !touchBeganOnBubble { setHot(hit(p, reach: Self.outerRadius + 20)) }
        case .idle:
            state = .pressing
            pressStart = p
            grabOffset = CGPoint(x: centre.x - p.x, y: centre.y - p.y)
            select.prepare(); thump.prepare()
            UIView.animate(withDuration: 0.16) { self.bubble.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }
            progress.removeAllAnimations()
            let a = CABasicAnimation(keyPath: "strokeEnd")
            a.fromValue = 0; a.toValue = 1; a.duration = Self.holdTime
            a.fillMode = .forwards; a.isRemovedOnCompletion = false
            progress.add(a, forKey: "hold")
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdTime, repeats: false) { [weak self] _ in self?.held() }
        default: break
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        switch state {
        case .pressing:
            if hypot(p.x - pressStart.x, p.y - pressStart.y) > 10 {
                holdTimer?.invalidate()
                progress.removeAllAnimations()
                state = .moving
                UIView.animate(withDuration: 0.2) { self.bubble.transform = CGAffineTransform(scaleX: 1.08, y: 1.08) }
            }
        case .moving:
            centre = CGPoint(x: min(bounds.width, max(0, p.x + grabOffset.x)), y: min(band.upperBound, max(band.lowerBound, p.y + grabOffset.y)))
            bubble.center = centre
        case .holdOpen:
            setHot(hit(p, reach: Self.holdReach))
        case .tapOpen:
            if !touchBeganOnBubble { setHot(hit(p, reach: Self.outerRadius + 20)) }
        default: break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        switch state {
        case .pressing:
            holdTimer?.invalidate()
            progress.removeAllAnimations()
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.6) { self.bubble.transform = .identity }
            state = .idle
            if let t = lastTap, Date().timeIntervalSince(t) < Self.doubleTapTime { lastTap = nil; swapToLast(); return }
            lastTap = Date()
            open(hold: false)
        case .moving:
            settle()
        case .holdOpen:
            if let i = hit(p, reach: Self.holdReach) { pick(i) }
            else {
                close(animated: true)
                if hypot(p.x - centre.x, p.y - centre.y) < Self.innerRadius { say("Slid back: nothing changed") }
            }
        case .tapOpen:
            if touchBeganOnBubble {
                if let t = lastTap, Date().timeIntervalSince(t) < Self.doubleTapTime { lastTap = nil; close(animated: false); swapToLast(); return }
                close(animated: true)
            } else if let i = hit(p, reach: Self.outerRadius + 20) { pick(i) }
            else { close(animated: true) }
        default: break
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        holdTimer?.invalidate()
        progress.removeAllAnimations()
        switch state {
        case .pressing: state = .idle; UIView.animate(withDuration: 0.2) { self.bubble.transform = .identity }
        case .moving: settle()
        case .holdOpen: close(animated: true)
        default: break
        }
    }

    private func held() {
        guard state == .pressing else { return }
        thump.impactOccurred()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.6) { self.bubble.transform = .identity }
        progress.removeAllAnimations()
        open(hold: true)
    }

    // MARK: the fan

    /// The choices, top to bottom of the fan: four tools, three of the ink's colours, two of its sizes.
    var choices: [RingChoice] {
        let tools = BoardTools.shared
        let ink = Self.inkTool
        var colors = [0, 1, 2]
        let picked = tools.colorIndex(ink)
        if !colors.contains(picked) { colors[2] = picked }
        return [.tool(.pen), .tool(.highlighter), .tool(.eraser), .tool(.lasso)] + colors.map { .color($0) } + [.size(1), .size(4)]
    }

    /// The ink the colours and sizes belong to: the tool in use when it inks, else the last inking tool, else the pen.
    static var inkTool: BoardTool {
        let t = BoardTools.shared
        if t.tool.inks && t.tool != .shapes { return t.tool }
        if t.previousTool.inks && t.previousTool != .shapes { return t.previousTool }
        return .pen
    }

    /// Which way the fan opens: toward the middle of the screen.
    private var facing: CGFloat { atan2(bounds.midY - centre.y, bounds.midX - centre.x) }

    private func angles(_ n: Int) -> [CGFloat] {
        let span = CGFloat.pi * 0.98
        let step = span / CGFloat(n)
        let start = facing - span / 2 + step / 2
        return (0..<n).map { start + CGFloat($0) * step }
    }

    private func open(hold: Bool) {
        let list = choices
        let a = angles(list.count)
        let step = a.count > 1 ? a[1] - a[0] : .pi
        let size = (Self.outerRadius + 80) * 2
        fan.frame = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
        fan.subviews.forEach { $0.removeFromSuperview() }
        items = list.enumerated().map { i, c in
            let v = RingItemView(frame: fan.bounds, choice: c, angle: a[i], span: step, current: isCurrent(c))
            v.accessibilityIdentifier = "ring-item-\(i)"
            fan.addSubview(v)
            return v
        }
        fan.isHidden = false
        state = hold ? .holdOpen : .tapOpen
        hot = nil
        bringSubviewToFront(bubble)
        bringSubviewToFront(label)
        bubble.accessibilityValue = "Open"
        UIAccessibility.post(notification: .layoutChanged, argument: items.first)
        for (i, v) in items.enumerated() {
            if reduceMotion {
                v.alpha = 0
                UIView.animate(withDuration: 0.15) { v.alpha = 1 }
                continue
            }
            v.alpha = 0
            v.transform = CGAffineTransform(rotationAngle: (QuickRingPrefs.right ? -1 : 1) * 28 * .pi / 180).scaledBy(x: 0.2, y: 0.2)
            UIView.animate(withDuration: 0.52, delay: Double(i) * 0.022, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.5,
                           options: [.allowUserInteraction, .beginFromCurrentState]) {
                v.transform = .identity
                v.alpha = 1
            }
        }
        if hold { say("Slide onto a choice, let go to pick it") }
    }

    func close(animated: Bool) {
        guard isOpen else { return }
        state = .idle
        bubble.accessibilityValue = nil
        setHot(nil)
        let gone = items
        items = []
        let fanView = fan
        if !animated || reduceMotion {
            gone.forEach { $0.removeFromSuperview() }
            fanView.isHidden = true
            return
        }
        for (i, v) in gone.reversed().enumerated() {
            UIView.animate(withDuration: 0.2, delay: Double(i) * 0.012, options: [.curveEaseIn, .beginFromCurrentState]) {
                v.transform = CGAffineTransform(rotationAngle: (QuickRingPrefs.right ? -1 : 1) * 18 * .pi / 180).scaledBy(x: 0.3, y: 0.3)
                v.alpha = 0
            } completion: { _ in
                v.removeFromSuperview()
                if fanView.subviews.isEmpty { fanView.isHidden = true }
            }
        }
    }

    /// The choice under `p`, or nil (on the button itself, or too far away).
    private func hit(_ p: CGPoint, reach: CGFloat) -> Int? {
        let dx = p.x - centre.x, dy = p.y - centre.y
        let r = hypot(dx, dy)
        guard r >= Self.innerRadius, r <= reach, !items.isEmpty else { return nil }
        let a = atan2(dy, dx)
        var best: (Int, CGFloat)?
        for (i, v) in items.enumerated() {
            var d = abs(a - v.angle)
            if d > .pi { d = 2 * .pi - d }
            if best == nil || d < best!.1 { best = (i, d) }
        }
        guard let b = best, b.1 <= (items.first?.span ?? 0) * 0.75 else { return nil }
        return b.0
    }

    private func setHot(_ i: Int?) {
        guard i != hot else { return }
        hot = i
        if i != nil { select.selectionChanged(); select.prepare() }
        for (j, v) in items.enumerated() {
            let near = i.map { abs($0 - j) == 1 } ?? false
            v.setHot(j == i, near: near)
        }
        if let i, items.indices.contains(i) {
            let v = items[i]
            label.text = v.title
            label.sizeToFit()
            label.bounds.size = CGSize(width: label.bounds.width + 20, height: 26)
            let r = Self.outerRadius + 34
            let c = CGPoint(x: centre.x + cos(v.angle) * r, y: centre.y + sin(v.angle) * r)
            let w = label.bounds.width / 2
            label.center = CGPoint(x: min(bounds.width - w - 8, max(w + 8, c.x)), y: min(bounds.height - 20, max(20, c.y)))
            UIView.animate(withDuration: 0.12) { self.label.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.12) { self.label.alpha = 0 }
        }
    }

    private func isCurrent(_ c: RingChoice) -> Bool {
        let t = BoardTools.shared
        switch c {
        case .tool(let x): return t.tool == x
        case .color(let i): return t.tool.inks && t.colorIndex(Self.inkTool) == i
        case .size(let i): return t.tool.inks && t.widthIndex(Self.inkTool) == i
        }
    }

    // MARK: picking

    private func pick(_ i: Int) {
        guard items.indices.contains(i), let b = board else { close(animated: true); return }
        let v = items[i]
        let choice = v.choice
        tick.impactOccurred()
        // the picked choice flies into the button
        if !reduceMotion, let ghost = v.chip.snapshotView(afterScreenUpdates: false) {
            ghost.center = v.chip.convert(CGPoint(x: v.chip.bounds.midX, y: v.chip.bounds.midY), to: self)
            ghost.transform = v.chip.transform
            insertSubview(ghost, belowSubview: bubble)
            v.chip.alpha = 0
            UIView.animate(withDuration: 0.34, delay: 0, options: [.curveEaseIn]) {
                ghost.center = self.centre
                ghost.transform = CGAffineTransform(scaleX: 0.35, y: 0.35)
                ghost.alpha = 0.2
            } completion: { _ in ghost.removeFromSuperview() }
        }
        close(animated: true)
        let tools = BoardTools.shared
        let ink = Self.inkTool
        switch choice {
        case .tool(let t): b.selectTool(t)
        case .color(let i):
            tools.setColorIndex(ink, i)
            if tools.tool != ink { b.selectTool(ink) } else { b.toolChanged() }
        case .size(let i):
            tools.setWidthIndex(ink, i)
            if tools.tool != ink { b.selectTool(ink) } else { b.toolChanged() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.3)) { [weak self] in
            self?.refresh()
            self?.pop()
        }
    }

    /// Double tap: back to the tool before this one (as the Pencil's double tap does).
    private func swapToLast() {
        guard let b = board else { return }
        let t = BoardTools.shared
        let back = t.previousTool == t.tool ? BoardTool.pen : t.previousTool
        tick.impactOccurred()
        if reduceMotion { b.selectTool(back); refresh(); return }
        var flip = CATransform3DIdentity
        flip.m34 = -1 / 400
        UIView.animate(withDuration: 0.14, delay: 0, options: [.curveEaseIn]) {
            self.core.layer.transform = CATransform3DRotate(flip, .pi / 2, 0, 1, 0)
        } completion: { _ in
            b.selectTool(back)
            self.refresh()
            self.core.layer.transform = CATransform3DRotate(flip, -.pi / 2, 0, 1, 0)
            UIView.animate(withDuration: 0.36, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.4) {
                self.core.layer.transform = CATransform3DIdentity
            }
            self.ripple()
        }
        say("Back to " + back.title)
    }

    private func pop() {
        guard !reduceMotion else { return }
        bubble.transform = CGAffineTransform(scaleX: 1.24, y: 1.24)
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.45, initialSpringVelocity: 0.8, options: [.allowUserInteraction]) {
            self.bubble.transform = .identity
        }
        ripple()
    }

    /// A ring in the ink's colour spreading out from the button.
    private func ripple() {
        let t = BoardTools.shared
        let color = t.tool.inks ? InkConvert.color(t.color(Self.inkTool)) : UIColor.white
        let r = CAShapeLayer()
        let s = Self.bubbleSize
        r.frame = CGRect(x: centre.x - s / 2, y: centre.y - s / 2, width: s, height: s)
        r.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: s, height: s)).cgPath
        r.fillColor = UIColor.clear.cgColor
        r.strokeColor = color.cgColor
        r.lineWidth = 3
        layer.insertSublayer(r, below: bubble.layer)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1; grow.toValue = 2.5
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9; fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [grow, fade]
        g.duration = 0.6
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        r.opacity = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { r.removeFromSuperlayer() }
        r.add(g, forKey: "ripple")
        CATransaction.commit()
    }

    // MARK: moving and tucking

    /// Let go after a drag: to the nearer side, or tucked into the edge when pushed into it.
    private func settle() {
        state = .idle
        let right = centre.x > bounds.midX
        let pushed = right ? centre.x > bounds.width - safe.right - Self.tuckZone : centre.x < safe.left + Self.tuckZone
        QuickRingPrefs.right = right
        let span = band.upperBound - band.lowerBound
        QuickRingPrefs.down = span > 0 ? (centre.y - band.lowerBound) / span : 0.5
        centre.x = right ? bounds.width - safe.right - Self.sideInset : safe.left + Self.sideInset
        if pushed { tuck(); return }
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4, options: [.allowUserInteraction]) {
            self.bubble.center = self.centre
            self.bubble.transform = .identity
        }
    }

    private func tuck() {
        QuickRingPrefs.tucked = true
        state = .tucked
        layOutTab()
        tab.isHidden = false
        let out: CGFloat = QuickRingPrefs.right ? 40 : -40
        tab.transform = CGAffineTransform(translationX: out, y: 0)
        tab.alpha = 1
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn]) {
            self.bubble.center = CGPoint(x: self.centre.x + out * 2, y: self.centre.y)
            self.bubble.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
            self.bubble.alpha = 0
        } completion: { _ in
            self.bubble.isHidden = true
            self.bubble.transform = .identity
            self.bubble.center = self.centre
        }
        UIView.animate(withDuration: 0.5, delay: 0.15, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5) { self.tab.transform = .identity }
        say("Tucked away: tap the tab to bring it back")
    }

    private func untuck() {
        QuickRingPrefs.tucked = false
        state = .idle
        let out: CGFloat = QuickRingPrefs.right ? 40 : -40
        bubble.isHidden = false
        bubble.center = CGPoint(x: centre.x + out * 2, y: centre.y)
        bubble.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        bubble.alpha = 0
        refresh()
        UIView.animate(withDuration: 0.2) { self.tab.transform = CGAffineTransform(translationX: out, y: 0) } completion: { _ in
            self.tab.isHidden = true
            self.tab.transform = .identity
        }
        UIView.animate(withDuration: 0.55, delay: 0.05, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
            self.bubble.center = self.centre
            self.bubble.transform = .identity
            self.bubble.alpha = 1
        } completion: { _ in self.ripple() }
    }

    // MARK: writing, showing what's in use

    /// The Pencil or a finger went down on the board: the ring steps back so it isn't in the way.
    func writing(_ on: Bool) {
        restoreTimer?.invalidate()
        if on {
            if isOpen { close(animated: true) }
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.alpha = 0.28 }
        } else {
            restoreTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.wake() }
        }
    }

    private func wake() {
        restoreTimer?.invalidate()
        guard alpha < 1 else { return }
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.alpha = 1 }
    }

    /// The button shows the tool in use: the ink's colour and its size.
    func refresh() {
        let t = BoardTools.shared
        let tool = t.tool
        coreIcon.image = UIImage(systemName: tool.symbol)
        if tool.inks {
            let c = InkConvert.color(t.color(tool))
            core.backgroundColor = c
            coreIcon.tintColor = Self.light(c) ? UIColor(white: 0.1, alpha: 1) : .white
        } else {
            core.backgroundColor = UIColor(white: 0.98, alpha: 1)
            coreIcon.tintColor = UIColor(white: 0.1, alpha: 1)
        }
        badge.isHidden = !tool.inks
        if tool.inks {
            let n = BoardTools.widths(tool).count
            let d = 3 + CGFloat(t.widthIndex(tool)) / CGFloat(max(1, n - 1)) * 9
            badgeDot.frame = CGRect(x: (20 - d) / 2, y: (20 - d) / 2, width: d, height: d)
            badgeDot.layer.cornerRadius = d / 2
        }
        var words = [tool.title]
        if tool.inks {
            words.append(Self.colorName(t.color(tool), marker: tool == .highlighter))
            words.append(BoardTools.widthNames[min(BoardTools.widthNames.count - 1, t.widthIndex(tool))])
        }
        bubble.accessibilityLabel = "Quick ring: " + words.joined(separator: ", ")
    }

    private func say(_ text: String) {
        caption.text = text
        caption.sizeToFit()
        caption.bounds.size = CGSize(width: caption.bounds.width + 20, height: 26)
        let w = caption.bounds.width / 2
        let x = QuickRingPrefs.right ? centre.x - Self.bubbleSize / 2 - 12 - w : centre.x + Self.bubbleSize / 2 + 12 + w
        let y = isOpen ? centre.y + Self.outerRadius + 24 : centre.y
        caption.center = CGPoint(x: min(bounds.width - w - 8, max(w + 8, x)), y: min(bounds.height - safe.bottom - 20, max(20, y)))
        caption.layer.removeAllAnimations()
        caption.alpha = 0
        UIView.animate(withDuration: 0.18) { self.caption.alpha = 1 } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 1.4, options: [.allowUserInteraction]) { self.caption.alpha = 0 }
        }
    }

    static func light(_ c: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.62
    }

    /// A colour's name for the label and VoiceOver: the favourites by name, any other colour as "Your colour".
    static func colorName(_ hex: String, marker: Bool) -> String {
        let pens = ["Black", "Blue", "Red", "Green", "Orange", "Purple", "Grey", "Teal", "Pink", "Brown"]
        let markers = ["Yellow", "Green", "Pink", "Blue", "Orange", "Purple", "Coral", "Grey"]
        let base = marker ? BoardTools.markerColors : BoardTools.penColors
        let names = marker ? markers : pens
        if let i = base.firstIndex(where: { $0.caseInsensitiveCompare(hex) == .orderedSame }), names.indices.contains(i) { return names[i] }
        return "Your colour"
    }
}

/// One wedge of the fan: its dark slice and the choice on it (a tool's icon, a colour's dot, a size's dot).
final class RingItemView: UIView {
    let choice: RingChoice
    let angle: CGFloat
    let span: CGFloat
    let chip = UIView()
    private let wedge = CAShapeLayer()
    let title: String

    init(frame: CGRect, choice: RingChoice, angle: CGFloat, span: CGFloat, current: Bool) {
        self.choice = choice
        self.angle = angle
        self.span = span
        let tools = BoardTools.shared
        let ink = QuickRing.inkTool
        switch choice {
        case .tool(let t): title = t.title
        case .color(let i): title = QuickRing.colorName(tools.colors(ink)[min(i, tools.colors(ink).count - 1)], marker: ink == .highlighter)
        case .size(let i): title = BoardTools.widthNames[min(i, BoardTools.widthNames.count - 1)]
        }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        let m = CGPoint(x: bounds.midX, y: bounds.midY)
        let gap: CGFloat = 0.012
        let path = UIBezierPath()
        path.addArc(withCenter: m, radius: QuickRing.outerRadius, startAngle: angle - span / 2 + gap, endAngle: angle + span / 2 - gap, clockwise: true)
        path.addArc(withCenter: m, radius: QuickRing.innerRadius, startAngle: angle + span / 2 - gap, endAngle: angle - span / 2 + gap, clockwise: false)
        path.close()
        wedge.path = path.cgPath
        wedge.fillColor = QuickRing.plate.cgColor
        wedge.shadowPath = path.cgPath
        wedge.shadowColor = UIColor.black.cgColor
        wedge.shadowOpacity = 0.18
        wedge.shadowRadius = 8
        wedge.shadowOffset = CGSize(width: 0, height: 3)
        layer.addSublayer(wedge)

        let s: CGFloat = 38
        chip.frame = CGRect(x: m.x + cos(angle) * QuickRing.itemRadius - s / 2, y: m.y + sin(angle) * QuickRing.itemRadius - s / 2, width: s, height: s)
        chip.layer.cornerRadius = s / 2
        chip.isUserInteractionEnabled = false
        addSubview(chip)
        switch choice {
        case .tool(let t):
            let icon = UIImageView(image: UIImage(systemName: t.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
            icon.tintColor = .white
            icon.contentMode = .center
            icon.frame = chip.bounds
            chip.addSubview(icon)
            if current { chip.backgroundColor = UIColor(white: 1, alpha: 0.16) }
        case .color(let i):
            let colors = tools.colors(ink)
            let dot = UIView(frame: chip.bounds.insetBy(dx: 7, dy: 7))
            dot.backgroundColor = InkConvert.color(colors[min(i, colors.count - 1)])
            dot.layer.cornerRadius = dot.bounds.width / 2
            dot.layer.borderColor = UIColor(white: 1, alpha: current ? 0.95 : 0.25).cgColor
            dot.layer.borderWidth = current ? 3 : 1
            chip.addSubview(dot)
        case .size(let i):
            let n = BoardTools.widths(ink).count
            let d = 4 + CGFloat(i) / CGFloat(max(1, n - 1)) * 14
            let dot = UIView(frame: CGRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d))
            dot.backgroundColor = .white
            dot.layer.cornerRadius = d / 2
            chip.addSubview(dot)
            if current { chip.layer.borderColor = UIColor(white: 1, alpha: 0.7).cgColor; chip.layer.borderWidth = 2 }
        }
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = current ? [.button, .selected] : .button
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Only the chip counts for VoiceOver and UI tests: the view itself fills the whole fan.
    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(chip.frame, in: self) }
        set { super.accessibilityFrame = newValue }
    }

    func setHot(_ on: Bool, near: Bool) {
        let scale: CGFloat = on ? 1.34 : near ? 1.1 : 1
        wedge.fillColor = (on ? QuickRing.plateHot : QuickRing.plate).cgColor
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.6, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.chip.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
}

/// A label with room around its words.
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
}
