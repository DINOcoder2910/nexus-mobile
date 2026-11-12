import UIKit
import NexusCore

/// Replay, as the laptop's (app/tutorboard.js `replay`): the tutor's pointer and brief marks are never saved on the board, so Replay
/// reads the board's `tutor.json` (each turn's whole reply, gestures included) and plays every turn again from empty, each sentence said
/// by the iPad's voice and its steps drawn as it starts, the gestures in time. Nothing is asked of Claude.
///
/// It plays full screen over the board on a scratch board: a board folder in the app's temporary folder, outside the data folder, with
/// no save callback, so nothing of it is ever synced and the real board is never touched. It is removed when the replay closes (and any
/// a crash left behind, the next time one opens).
final class TutorReplayViewController: UIViewController {
    let name: String
    let turns: [[TutorEvent]]
    /// Replay from a line of the transcript: the turn and event the voice starts at (everything before is drawn at once, silent).
    let start: (turn: Int, event: Int)?
    private let scratch: URL
    private let path: String
    private var board: BoardController!
    private var drawer: TutorDrawer!
    private var task: Task<Void, Never>?
    private var stopped = false
    private var started = false
    private let subLabel = UILabel()

    static let folderPrefix = "tutor-replay-"
    /// The gap between one turn and the next, as the laptop's TURN_GAP.
    static let turnGap: Double = 48

    init(name: String, turns: [[TutorEvent]], start: (turn: Int, event: Int)? = nil) {
        self.name = name
        self.turns = turns
        self.start = start
        TutorReplayViewController.removeLeftovers()
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent(TutorReplayViewController.folderPrefix + UUID().uuidString, isDirectory: true)
        path = "replay.board"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Scratch boards a replay left (closed by a crash).
    static func removeLeftovers() {
        let fm = FileManager.default, tmp = fm.temporaryDirectory
        for f in (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [] where f.hasPrefix(folderPrefix) {
            try? fm.removeItem(at: tmp.appendingPathComponent(f, isDirectory: true))
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = .systemBackground
        try? FolderAccess.write(scratch.appendingPathComponent(path, isDirectory: true).appendingPathComponent("board.json"), BoardFormat.boardJSON())

        // the scratch board: the board's own view, no bar, nothing to draw with; no onSaved and no store, so it never syncs
        board = BoardController(root: scratch, path: path, focus: nil)
        addChild(board)
        _ = board.view
        board.canvas.drawingGestureRecognizer.isEnabled = false
        board.bar.isHidden = true
        board.showBarsButton.isHidden = true
        board.poll?.invalidate()
        drawer = TutorDrawer(board: board)

        let title = UILabel()
        title.text = "Replay: " + name
        title.font = .preferredFont(forTextStyle: .headline)
        title.lineBreakMode = .byTruncatingTail
        subLabel.font = .preferredFont(forTextStyle: .subheadline)
        subLabel.textColor = .secondaryLabel
        subLabel.text = turns.count == 1 ? "1 explanation" : "\(turns.count) explanations"
        var c = UIButton.Configuration.plain()
        c.title = "Close"
        c.image = UIImage(systemName: "xmark")
        c.imagePadding = 6
        let close = UIButton(configuration: c)
        close.accessibilityLabel = "Close the replay"
        close.addTarget(self, action: #selector(closeReplay), for: .touchUpInside)
        let head = UIStackView(arrangedSubviews: [title, subLabel, UIView(), close])
        head.spacing = 10
        head.alignment = .center
        head.isLayoutMarginsRelativeArrangement = true
        head.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
        head.backgroundColor = .systemBackground
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stage = UIView()
        stage.clipsToBounds = true
        view.addSubview(head)
        view.addSubview(stage)
        stage.addSubview(board.view)
        head.translatesAutoresizingMaskIntoConstraints = false
        stage.translatesAutoresizingMaskIntoConstraints = false
        board.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            head.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            head.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            head.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.topAnchor.constraint(equalTo: head.bottomAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            board.view.topAnchor.constraint(equalTo: stage.topAnchor),
            board.view.leadingAnchor.constraint(equalTo: stage.leadingAnchor),
            board.view.trailingAnchor.constraint(equalTo: stage.trailingAnchor),
            board.view.bottomAnchor.constraint(equalTo: stage.bottomAnchor),
        ])
        board.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        guard !started else { return }
        started = true
        task = Task { @MainActor [weak self] in await self?.play() }
    }

    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        let esc = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeReplay))
        esc.discoverabilityTitle = "Close the replay"
        return [esc]
    }

    /// Every turn again, from empty: each below the one before (as the laptop's replay), each sentence said and its steps drawn as it
    /// starts (the same order and the same start signal as a live turn).
    private func play() async {
        var n = 0
        for (ti, events) in turns.enumerated() {
            if stopped { break }
            let below = drawer.drewAll.map { [TutorSteps.jsRound($0.x), TutorSteps.jsRound($0.maxY + TutorReplayViewController.turnGap)] }
            drawer.turn(at: below ?? [0, 0])
            for (ei, e) in events.enumerated() {
                if stopped { break }
                let fast = start.map { ti < $0.turn || (ti == $0.turn && ei < $0.event) } ?? false
                drawer.pace = fast ? 60 : 1
                switch e {
                case .say(let sentence, _):
                    if fast { drawer.spoken(n); n += 1; continue }
                    await Speaker.shared.say(sentence)
                    if stopped { break }
                    drawer.spoken(n)
                    n += 1
                case .step(let s):
                    await drawer.draw(s)
                }
            }
            if !stopped { await Speaker.shared.untilDone(); drawer.ended() }
        }
        if !drawer.problems.isEmpty { print("tutor replay:", drawer.problems.joined(separator: "; ")); drawer.problems = [] }
        if !stopped { subLabel.text = "Done" }
    }

    @objc private func closeReplay() {
        stop()
        dismiss(animated: true)
    }

    private func stop() {
        guard !stopped else { return }
        stopped = true
        task?.cancel()
        Speaker.shared.stop()
        drawer?.finishNow()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stop()
        // (after the board's own pending save, which would write the folder again)
        let dir = scratch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { try? FileManager.default.removeItem(at: dir) }
    }
}

extension BoardController {
    /// Replay the tutor's explanations on this board (the panel's Replay button).
    /// from: a line of the transcript (the turn and its sentence): replay from there.
    func openTutorReplay(from: (turn: Int, n: Int)? = nil) {
        guard presentedViewController == nil else { return }
        if tutor.busy { tutor.stop() }
        let text = try? FolderAccess.read(boardURL.appendingPathComponent(TutorSession.file))
        let p = TutorSession.parse(text)
        var turns = p.ok ? p.session.replayTurns() : []
        var start: (turn: Int, event: Int)?
        if let from, p.ok, let r = p.session.replayFrom(turn: from.turn, n: from.n) { turns = r.turns; start = r.start }
        guard !turns.isEmpty else { toast("There is no tutor explanation on this board to replay."); return }
        let vc = TutorReplayViewController(name: boardName, turns: turns, start: start)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}
