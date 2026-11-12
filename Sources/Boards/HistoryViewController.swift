import UIKit
import PencilKit
import NexusCore

/// A board's History view, as the laptop's (renderer/src/app/boardhistory.js): opened from the board's clock, it covers the board
/// with a player that replays it from empty, from every device's `history/*.jsonl` (NexusCore BoardHistory.swift): strokes appear as
/// they were written, typing in bursts, erasing and moving as they happened. Play and pause (Space), speed 1x to 64x, long pauses
/// skipped (on by default), a scrubber with the sessions marked by day. Restore to here puts the board back to that moment as one
/// change Undo takes back; Copy out brings what you drag a box around on the old board into the current one. The board itself is not
/// touched until one of those two.
final class HistoryViewController: UIViewController {
    let root: URL
    let path: String
    let now: BoardState
    var onRestore: ((BoardState, Double) -> Void)?
    var onCopyOut: ((BoardState) -> Void)?

    private let board: BoardController
    private var tl: HistoryTimeline!
    private var R: HistoryReplayer!
    private var clock: PlayClock!
    private var pos: Double = 0
    private var playing = false
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    private var cache: [String: [PKStroke]] = [:]
    private var shownKey = ""
    private var shownItems: [BoardItem]?
    private var shownTexts: [String: String] = [:]
    private var picking = false
    private var marksWidth: CGFloat = -1
    private lazy var whenFormat: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM HH:mm:ss")
        return f
    }()
    private var pickStart: CGPoint?

    private static let speeds: [Double] = [1, 2, 4, 8, 16, 32, 64]
    private var speed: Double {
        get { let v = UserDefaults.standard.double(forKey: "history.speed"); return Self.speeds.contains(v) ? v : 8 }
        set { UserDefaults.standard.set(newValue, forKey: "history.speed") }
    }
    private var skip: Bool {
        get { UserDefaults.standard.object(forKey: "history.skip") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "history.skip") }
    }

    // views
    private let stage = UIView()
    private let pickLayer = CAShapeLayer()
    private let pickView = UIView()
    private let playButton = UIButton(type: .system)
    private let slider = UISlider()
    private let marks = UIView()
    private let whenLabel = UILabel()
    private let speedButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let subLabel = UILabel()

    init(root: URL, path: String, now: BoardState) {
        self.root = root
        self.path = path
        self.now = now
        board = BoardController(root: root, path: path, focus: nil)
        board.replay = true
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var boardName: String { String((path as NSString).lastPathComponent.dropLast(6)) }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(white: 0.96, alpha: 1)

        let lines = BoardHistory.readLogs(board: root.appendingPathComponent(path, isDirectory: true), read: FolderAccess.read)
        tl = HistoryTimeline(lines, now: now)
        R = HistoryReplayer(tl)

        // the old board: the board's own view, read-only, nothing drawn on it
        addChild(board)
        _ = board.view
        board.canvas.drawingGestureRecognizer.isEnabled = false
        board.bar.isHidden = true
        board.showBarsButton.isHidden = true
        board.poll?.invalidate()
        board.offset = replayOffset()
        stage.addSubview(board.view)
        board.view.frame = stage.bounds
        board.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        board.didMove(toParent: self)

        pickView.backgroundColor = .clear
        pickView.isHidden = true
        pickView.frame = stage.bounds
        pickView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pickLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.08).cgColor
        pickLayer.strokeColor = UIColor.systemBlue.cgColor
        pickLayer.lineDashPattern = [6, 4]
        pickLayer.lineWidth = 1.5
        pickView.layer.addSublayer(pickLayer)
        pickView.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pickPan(_:))))
        stage.addSubview(pickView)

        buildChrome()
        relayout()
        pos = clock.length // it opens on the board as it is now; Play from the end starts again from the beginning
        paint(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        if tl.ev.isEmpty { tell("Nothing to replay yet: this board is empty.") }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pause()
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        let space = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(togglePlay))
        space.discoverabilityTitle = "Play or pause"
        let esc = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(close))
        esc.discoverabilityTitle = "Close the history"
        return [space, esc]
    }

    /// Room left of and above everything the board ever had, so nothing replayed falls off the canvas (it never grows while playing).
    private func replayOffset() -> CGPoint {
        var minX = 0.0, minY = 0.0
        for e in tl.ev {
            switch e.kind {
            case .stroke(let s): for p in s.points { minX = min(minX, p[0]); minY = min(minY, p[1]) }
            case .item(let it):
                minX = min(minX, it.x, it.x + min(0, it.w ?? 0)); minY = min(minY, it.y, it.y + min(0, it.h ?? 0))
            default: break
            }
        }
        let pad = Double(board.pad)
        return CGPoint(x: max(pad, pad - minX + 100), y: max(pad, pad - minY + 100))
    }

    // MARK: the frame: a header, the old board, the controls

    private func buildChrome() {
        let title = UILabel()
        title.text = "History"
        title.font = .preferredFont(forTextStyle: .headline)
        subLabel.text = boardName + (tl.rough != nil ? " · what came before the history began is shown roughly" : "")
        subLabel.font = .preferredFont(forTextStyle: .subheadline)
        subLabel.textColor = .secondaryLabel
        subLabel.lineBreakMode = .byTruncatingTail
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = "Close the history"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        let head = UIStackView(arrangedSubviews: [title, subLabel, UIView(), closeButton])
        head.spacing = 10
        head.alignment = .center
        head.isLayoutMarginsRelativeArrangement = true
        head.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        head.backgroundColor = .systemBackground

        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.accessibilityLabel = "Play"
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        playButton.widthAnchor.constraint(equalToConstant: 40).isActive = true

        slider.minimumValue = 0
        slider.addTarget(self, action: #selector(scrubbed), for: .valueChanged)
        slider.accessibilityLabel = "When"
        marks.isUserInteractionEnabled = false
        let track = UIView()
        track.addSubview(marks)
        track.addSubview(slider)
        slider.translatesAutoresizingMaskIntoConstraints = false
        marks.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            slider.leadingAnchor.constraint(equalTo: track.leadingAnchor), slider.trailingAnchor.constraint(equalTo: track.trailingAnchor),
            slider.bottomAnchor.constraint(equalTo: track.bottomAnchor), slider.topAnchor.constraint(equalTo: track.topAnchor, constant: 14),
            marks.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 14), marks.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -14),
            marks.topAnchor.constraint(equalTo: track.topAnchor), marks.bottomAnchor.constraint(equalTo: track.bottomAnchor),
        ])
        track.heightAnchor.constraint(equalToConstant: 48).isActive = true

        whenLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        whenLabel.textColor = .secondaryLabel
        whenLabel.setContentHuggingPriority(.required, for: .horizontal)
        whenLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        speedButton.showsMenuAsPrimaryAction = true
        speedButton.setContentHuggingPriority(.required, for: .horizontal)
        updateSpeedButton()
        skipButton.addTarget(self, action: #selector(toggleSkip), for: .touchUpInside)
        skipButton.setContentHuggingPriority(.required, for: .horizontal)
        updateSkipButton()

        copyButton.setTitle("Copy out", for: .normal)
        copyButton.addTarget(self, action: #selector(startPick), for: .touchUpInside)
        restoreButton.setTitle("Restore to here", for: .normal)
        restoreButton.addTarget(self, action: #selector(restoreHere), for: .touchUpInside)
        for b in [copyButton, restoreButton] {
            b.titleLabel?.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
            b.setContentHuggingPriority(.required, for: .horizontal)
        }

        let bar = UIStackView(arrangedSubviews: [playButton, track, whenLabel, speedButton, skipButton, copyButton, restoreButton])
        bar.spacing = 14
        bar.alignment = .center
        bar.isLayoutMarginsRelativeArrangement = true
        bar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 16)
        bar.backgroundColor = .systemBackground

        for v in [head, stage, bar] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            head.topAnchor.constraint(equalTo: g.topAnchor), head.leadingAnchor.constraint(equalTo: view.leadingAnchor), head.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.topAnchor.constraint(equalTo: head.bottomAnchor), stage.leadingAnchor.constraint(equalTo: view.leadingAnchor), stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.topAnchor.constraint(equalTo: stage.bottomAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: g.bottomAnchor),
        ])
        stage.clipsToBounds = true
    }

    private func updateSpeedButton() {
        speedButton.setTitle(JSONValue.format(speed) + "×", for: .normal)
        speedButton.accessibilityLabel = "Speed"
        speedButton.menu = UIMenu(title: "Speed", children: Self.speeds.map { s in
            UIAction(title: JSONValue.format(s) + "×", state: s == speed ? .on : .off) { [weak self] _ in
                self?.speed = s
                self?.updateSpeedButton()
            }
        })
    }

    private func updateSkipButton() {
        skipButton.setTitle("Skip pauses", for: .normal)
        skipButton.setImage(UIImage(systemName: skip ? "checkmark.square.fill" : "square"), for: .normal)
        skipButton.accessibilityValue = skip ? "On" : "Off"
    }

    /// The clock and the day marks (again when Skip pauses changes).
    private func relayout() {
        clock = PlayClock(tl, skip: skip)
        slider.maximumValue = Float(max(1, clock.length))
        placeMarks()
    }

    private func placeMarks() {
        marks.subviews.forEach { $0.removeFromSuperview() }
        marksWidth = marks.bounds.width
        let w = max(1, marks.bounds.width)
        var day = ""
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        for s in tl.sessions() {
            let at = CGFloat(clock.toPlay(s.start) / max(1, clock.length)) * w
            let d = f.string(from: Date(timeIntervalSince1970: s.start / 1000))
            let first = d != day
            day = d
            let tick = UIView(frame: CGRect(x: at - 1, y: first ? 12 : 16, width: 2, height: first ? 10 : 6))
            tick.backgroundColor = first ? .secondaryLabel : .tertiaryLabel
            marks.addSubview(tick)
            if first {
                let l = UILabel()
                l.text = d
                l.font = .systemFont(ofSize: 10)
                l.textColor = .secondaryLabel
                l.sizeToFit()
                l.frame.origin = CGPoint(x: min(max(0, at - l.bounds.width / 2), w - l.bounds.width), y: -2)
                marks.addSubview(l)
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if clock != nil, abs(marks.bounds.width - marksWidth) > 1 { placeMarks() }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.placeMarks() }
    }

    // MARK: playing

    @objc private func togglePlay() { playing ? pause() : play() }

    private func play() {
        if picking { endPick() }
        if pos >= clock.length - 1 { pos = 0 }
        playing = true
        lastTick = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        paintButton()
    }

    private func pause() {
        playing = false
        link?.invalidate()
        link = nil
        paintButton()
    }

    @objc private func tick(_ l: CADisplayLink) {
        let t = l.timestamp
        pos = min(clock.length, pos + (t - lastTick) * 1000 * speed)
        lastTick = t
        paint()
        if pos >= clock.length { pause() }
    }

    private func paintButton() {
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = playing ? "Pause" : "Play"
    }

    @objc private func scrubbed() {
        pos = Double(slider.value)
        paint()
    }

    @objc private func toggleSkip() {
        let t = clock.toReal(pos)
        skip.toggle()
        updateSkipButton()
        relayout()
        pos = clock.toPlay(t)
        paint(force: true)
    }

    /// The old board at the play position.
    private func paint(force: Bool = false) {
        let t = clock.toReal(pos)
        R.seek(t)
        let writing = R.writing
        let key = "\(R.applied)|" + writing.map { "\($0.s.id):\(Int($0.upTo * 60))" }.joined(separator: ",")
        if force || key != shownKey {
            shownKey = key
            let off = board.offset
            let wIds = Set(writing.map(\.s.id))
            var pk: [PKStroke] = []
            for (s, ev) in R.strokesWithEvent where !wIds.contains(s.id) {
                let k = s.id + "#" + String(ev)
                if let c = cache[k] { pk += c } else { let c = InkConvert.pkStrokes(s, offset: off); cache[k] = c; pk += c }
            }
            for w in writing { pk += InkConvert.pkStrokes(HistoryReplayer.partStroke(w.s, w.upTo), offset: off) }
            let items = R.items, texts = R.texts
            let changed = force || shownItems != items || shownTexts != texts
            if changed { shownItems = items; shownTexts = texts }
            board.showReplay(pk, items: items, texts: texts, itemsChanged: changed)
        }
        if !slider.isTracking { slider.value = Float(pos) }
        let txt = whenFormat.string(from: Date(timeIntervalSince1970: t / 1000))
        if whenLabel.text != txt { whenLabel.text = txt }
    }

    // MARK: Restore to here, Copy out

    @objc private func restoreHere() {
        pause()
        let t = clock.toReal(pos)
        R.seek(t)
        let want = R.state
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        let a = UIAlertController(title: "Put the board back as it was on \(f.string(from: Date(timeIntervalSince1970: t / 1000)))?",
                                  message: "What is on it now stays in its history, and Undo on the board takes it back.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Restore", style: .default) { [weak self] _ in
            guard let self else { return }
            let done = self.onRestore
            self.dismiss(animated: true) { done?(want, t) }
        })
        present(a, animated: true)
    }

    @objc private func startPick() {
        if picking { endPick(); return }
        pause()
        picking = true
        pickView.isHidden = false
        pickLayer.path = nil
        copyButton.setTitle("Cancel copy", for: .normal)
        subLabel.text = "Drag a box around what you want back"
    }

    private func endPick() {
        picking = false
        pickView.isHidden = true
        pickLayer.path = nil
        copyButton.setTitle("Copy out", for: .normal)
        subLabel.text = boardName + (tl.rough != nil ? " · what came before the history began is shown roughly" : "")
    }

    @objc private func pickPan(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: pickView)
        switch g.state {
        case .began: pickStart = p
        case .changed:
            if let s = pickStart { pickLayer.path = UIBezierPath(rect: CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))).cgPath }
        case .ended:
            guard let s = pickStart else { return }
            pickStart = nil
            let a = boardPoint(s), b = boardPoint(p)
            picked(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
        default:
            pickStart = nil
            pickLayer.path = nil
        }
    }

    /// A point on the stage in board units.
    private func boardPoint(_ p: CGPoint) -> CGPoint {
        let c = board.canvas, z = c.zoomScale
        let q = pickView.convert(p, to: c)
        return CGPoint(x: q.x / z - board.offset.x, y: q.y / z - board.offset.y)
    }

    private func picked(_ box: CGRect) {
        let st = R.state
        var out = BoardState()
        out.strokes = st.strokes.filter { s in s.points.contains { box.contains(CGPoint(x: $0[0], y: $0[1])) } }
        out.items = st.items.filter { box.intersects(board.box(of: $0)) }
        for it in out.items { if let md = st.texts[it.id] { out.texts[it.id] = md } }
        let n = out.strokes.count + out.items.count
        guard n > 0 else { pickLayer.path = nil; return }
        let a = UIAlertController(title: n == 1 ? "Copy 1 thing into the board?" : "Copy \(n) things into the board?",
                                  message: "What is gone comes back as it was; what changed since comes back as a copy beside it.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.pickLayer.path = nil })
        a.addAction(UIAlertAction(title: "Copy", style: .default) { [weak self] _ in
            guard let self else { return }
            let done = self.onCopyOut
            self.dismiss(animated: true) { done?(out) }
        })
        present(a, animated: true)
    }

    @objc private func close() {
        pause()
        dismiss(animated: true)
    }

    private func tell(_ message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.dismiss(animated: true) })
        present(a, animated: true)
    }
}

private extension UIFont {
    func withWeight(_ w: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: w)
    }
}
