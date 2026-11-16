import UIKit
import NexusCore

/// The UI check's Insert space drag on a full board (`-NexusTestBigBoard -NexusTestSpaceDrag`, Sources/Common/TestHooks.swift):
/// the drag is made the way a finger makes it (SpaceLive.swift, a step every screen refresh), held still at each stage so
/// UITests/SpaceLiveTests can take a picture, and timed. A label says the stage and the times. The test and the bench talk by
/// Darwin notifications (`app.nexus.spacebench.<phase>`, and `.go` from the test), because reading the screen's elements on a
/// board this full times out; the times also go to `diagnostics/space-bench.txt`, which the UI check prints.
extension BoardController {
    func spaceBenchIfAsked() {
        guard TestHooks.isSpaceDragRun, !readOnly, view.viewWithTag(9_192) == nil else { return }
        let label = UILabel()
        label.tag = 9_192
        label.accessibilityIdentifier = "space-bench"
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0.1, alpha: 0.85)
        label.numberOfLines = 0
        label.text = "space bench: waiting"
        view.addSubview(label)
        label.frame = CGRect(x: 20, y: view.bounds.height - 110, width: min(720, view.bounds.width - 40), height: 90)
        label.autoresizingMask = [.flexibleTopMargin]
        let bench = SpaceBench(board: self, label: label)
        // the UI test says go once it is listening (the board takes a while to open in the debug build), so no stage passes
        // before it is looking
        objc_setAssociatedObject(label, &SpaceBench.key, bench, .OBJC_ASSOCIATION_RETAIN)
    }
}

/// One run of the bench (kept alive by its own steps).
@MainActor
final class SpaceBench: NSObject {
    static var key = 0
    private var started = false
    weak var board: BoardController?
    let label: UILabel
    var times: [String] = []
    var line: CGFloat = 0
    let hold: TimeInterval = 14
    private var link: CADisplayLink?
    private var step: ((CFTimeInterval) -> Bool)?

    init(board: BoardController, label: UILabel) {
        self.board = board
        self.label = label
        super.init()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                        { _, observer, _, _, _ in
                                            guard let observer else { return }
                                            let bench = Unmanaged<SpaceBench>.fromOpaque(observer).takeUnretainedValue()
                                            Task { @MainActor in bench.tapped() }
                                        }, "app.nexus.spacebench.go" as CFString, nil, .deliverImmediately)
        say("ready")
        // the stage is said again every second, so a test that starts listening late still hears it; and the bench starts on
        // its own if the test's go never arrives
        let beat = Timer(timeInterval: 1, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            MainActor.assumeIsolated { self.announce() }
        }
        RunLoop.main.add(beat, forMode: .common)
        after(60) { self.tapped() }
    }

    @objc func tapped() {
        guard !started else { return }
        started = true
        start()
    }

    func say(_ phase: String) {
        label.text = "space bench: phase \(phase)\n" + times.joined(separator: "\n")
        print("SPACEBENCH \(phase) \(times.joined(separator: " | "))")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("nexus-data/diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(("space bench: phase \(phase)\n" + times.joined(separator: "\n") + "\n").utf8)
            .write(to: dir.appendingPathComponent("space-bench.txt"), options: .atomic)
        self.phase = phase
        announce()
    }

    private var phase = "ready"

    private func announce() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFNotificationName("app.nexus.spacebench.\(phase)" as CFString), nil, nil, true)
    }

    func start() {
        guard let b = board else { return }
        var waited = 0
        func ready() {
            if !b.content.tileMemo.primed && waited < 240 {
                waited += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ready() }
                return
            }
            say("before")
            after(hold) { self.addRoom() }
        }
        ready()
    }

    func after(_ s: TimeInterval, _ f: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: f) }

    /// Drags from `from` to `to` (board units of room) over `seconds`, a step per screen refresh, timing each step.
    func drag(at line: CGFloat, from: CGFloat, to: CGFloat, seconds: Double, name: String, then: @escaping () -> Void) {
        guard let b = board else { return }
        let vis = b.visibleBoard
        let t0 = CACurrentMediaTime()
        b.beginSpaceDrag(at: line, from: CGPoint(x: vis.midX, y: line), sideways: false)
        let began = (CACurrentMediaTime() - t0) * 1000
        var moves: [Double] = []
        var gaps: [Double] = []
        var last: CFTimeInterval?
        let startAt = CACurrentMediaTime()
        run { now in
            if let last { gaps.append((now - last) * 1000) }
            last = now
            let k = min(1, (now - startAt) / seconds)
            let m0 = CACurrentMediaTime()
            b.moveSpaceDrag(b.spaceAmount(from + (to - from) * CGFloat(k)))
            moves.append((CACurrentMediaTime() - m0) * 1000)
            if k < 1 { return true }
            let sm = moves.sorted(), sg = gaps.sorted()
            self.times.append(String(format: "%@: drag began in %.0f ms; a step %.1f ms (median), %.1f ms at worst; frames %.0f ms at worst over %ld",
                                     name, began, sm[sm.count / 2], sm.last ?? 0, sg.last ?? 0, gaps.count))
            then()
            return false
        }
    }

    /// Lets go and times it: the move itself, and until the board has drawn it and the overlay is gone.
    func letGo(_ raw: CGFloat, name: String, then: @escaping () -> Void) {
        guard let b = board else { return }
        let t0 = CACurrentMediaTime()
        b.endSpaceDrag(raw)
        let done = (CACurrentMediaTime() - t0) * 1000
        func wait(_ n: Int) {
            if b.spaceLive != nil && n < 100 { after(0.02) { wait(n + 1) }; return }
            self.times.append(String(format: "%@: let go in %.0f ms, drawn after %.0f ms", name, done, (CACurrentMediaTime() - t0) * 1000))
            then()
        }
        wait(0)
    }

    func addRoom() {
        guard let b = board else { return }
        let vis = b.visibleBoard
        line = CGFloat(InsertSpace.line(Double(vis.minY + vis.height * 0.35), paper: b.paper, size: BoardTools.shared.spaceSize))
        drag(at: line, from: 0, to: 220, seconds: 1.2, name: "add") {
            self.say("adding")
            self.after(self.hold) {
                self.letGo(b.spaceAmount(220), name: "add") {
                    self.say("added")
                    self.after(self.hold) { self.takeRoom() }
                }
            }
        }
    }

    func takeRoom() {
        guard let b = board else { return }
        let at = line + b.spaceAmount(220)
        drag(at: at, from: 0, to: -120, seconds: 1, name: "take") {
            self.say("taking")
            self.after(self.hold) {
                self.letGo(b.spaceAmount(-120), name: "take") {
                    self.say("taken")
                    self.after(self.hold) { self.dark() }
                }
            }
        }
    }

    /// The same on a dark board: the moving ink must look as it does on the board.
    func dark() {
        guard let b = board else { return }
        let was = BoardTools.shared.dark
        BoardTools.shared.dark = .always
        b.applyTheme()
        after(1.5) {
            self.drag(at: self.line, from: 0, to: 160, seconds: 1, name: "dark") {
                self.say("dark")
                self.after(self.hold) {
                    b.cancelSpaceDrag()
                    BoardTools.shared.dark = was
                    b.applyTheme()
                    self.say("done")
                }
            }
        }
    }

    // a step every screen refresh while `step` says to go on
    private func run(_ f: @escaping (CFTimeInterval) -> Bool) {
        step = f
        let l = CADisplayLink(target: Ticker(self), selector: #selector(Ticker.tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    fileprivate func tick(_ l: CADisplayLink) {
        guard let step, step(l.timestamp) else {
            l.invalidate()
            link = nil
            return
        }
    }
}

/// CADisplayLink holds its target strongly: this small one passes the ticks on.
private final class Ticker: NSObject {
    weak var bench: SpaceBench?
    init(_ b: SpaceBench) { bench = b }
    @MainActor @objc func tick(_ l: CADisplayLink) {
        guard let bench else { l.invalidate(); return }
        bench.tick(l)
    }
}
