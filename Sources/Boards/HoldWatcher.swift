import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Watches the Pencil without taking its touches (the canvas keeps every one), to make a shape out of a stroke that ends in a hold,
/// as the laptop does (shapes.js): when the tip stays still for `holdTime` while still down, `onHold` runs, with the stroke as
/// written so far in `points`. Once held, the stroke stays held until the Pencil lifts (later wobble doesn't undo it).
///
/// The hold is checked two ways, so neither alone has to work: a display link while the Pencil is down (it runs in every run-loop
/// mode, unlike a plain timer, which doesn't fire while UIKit tracks touches), and, when the Pencil lifts, the touch's own timestamps
/// (how long it had been still).
final class HoldWatcher: UIGestureRecognizer {
    /// The Pencil is on the screen.
    private(set) var touching = false
    /// The stroke being written (or the one just written) ended in a hold.
    private(set) var held = false
    /// The stroke as written, in the view's coordinates (coalesced touches included).
    private(set) var points: [CGPoint] = []
    var holdTime: TimeInterval = 0.55
    /// How far (screen points) the tip may wander and still count as still.
    var still: CGFloat = 4

    /// The hold was noticed while the Pencil is still down.
    var onHold: (() -> Void)?
    /// The Pencil lifted (or the stroke was cancelled: false).
    var onEnd: ((Bool) -> Void)?

    private var anchor = CGPoint.zero
    private var lastMove: TimeInterval = 0
    private var link: CADisplayLink?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touches.first else { return }
        touching = true
        held = false
        points = [t.location(in: view)]
        anchor = t.location(in: nil)
        lastMove = t.timestamp
        startLink()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touches.first else { return }
        let all = event.coalescedTouches(for: t) ?? [t]
        for c in all { points.append(c.location(in: view)) }
        if held { return }
        for c in all {
            let p = c.location(in: nil)
            if hypot(p.x - anchor.x, p.y - anchor.y) > still {
                anchor = p
                lastMove = c.timestamp
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if !held, let t = touches.first, t.timestamp - lastMove >= holdTime { held = true }
        end(held)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        held = false
        end(false)
    }

    /// Read once by the board after the stroke lands.
    func take() -> Bool {
        let h = held
        held = false
        return h
    }

    private func end(_ wasHeld: Bool) {
        touching = false
        stopLink()
        onEnd?(wasHeld)
        // never recognises: the canvas keeps every touch
        state = .failed
    }

    private func startLink() {
        stopLink()
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick() {
        guard touching, !held else { return }
        if ProcessInfo.processInfo.systemUptime - lastMove >= holdTime {
            held = true
            stopLink()
            onHold?()
        }
    }

    override func reset() {
        super.reset()
        // (UIKit resets a failed recognizer at the end of the touch; the hold is kept for `take()`)
        stopLink()
        touching = false
    }
}
