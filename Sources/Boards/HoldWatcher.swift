import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Watches the Pencil without taking its touches: when the tip stays still for a moment at the end of a stroke, `held` turns true
/// (and the Pencil's own feel gives a tick), so the board can snap that stroke to a shape when it ends, as the laptop does.
final class HoldWatcher: UIGestureRecognizer {
    private(set) var held = false
    private var anchor = CGPoint.zero
    private var timer: Timer?
    var holdTime: TimeInterval = 0.5
    var onHold: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        held = false
        anchor = touches.first?.location(in: view) ?? .zero
        restart()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let p = touches.first?.location(in: view) else { return }
        if hypot(p.x - anchor.x, p.y - anchor.y) > 3 {
            anchor = p
            held = false
            restart()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { finish() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { held = false; finish() }

    /// Read once by the board after the stroke lands.
    func take() -> Bool {
        let h = held
        held = false
        return h
    }

    private func restart() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: holdTime, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.held = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.onHold?()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        // never recognises: the canvas keeps every touch
        state = .failed
    }

    override func reset() {
        super.reset()
        timer?.invalidate()
        timer = nil
    }
}
