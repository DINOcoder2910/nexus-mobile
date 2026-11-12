import UIKit
import SwiftUI
import PencilKit
import NexusCore

/// The tutor on an iPad board (nexus docs/data-format.md "Tutor steps" and "Tutor sessions"; the laptop's app/tutor.js): hold the tutor
/// button and ask out loud, or type. It sees the part of the board on screen (a picture with a grid of the turn's coordinates, the
/// handwriting read from it, the typed blocks), talks back in Apple's voices and draws as it speaks. The conversation is the board's
/// `tutor.json`, the laptop's own file, so a session carries on on either device.
@MainActor
@Observable
final class BoardTutor {
    enum Phase { case idle, listening, thinking, speaking }

    var phase: Phase = .idle
    var open = false
    /// What was asked (live while listening).
    var asked = ""
    /// What the tutor has said this turn.
    var said: [String] = []
    var problem: String?
    /// Whether the board's tutor.json has an explanation Replay can play again (the panel's Replay button).
    var canReplay = false
    /// The strip's (the laptop's bar): paused; hints only; the answer ended with "your turn" (what to write, waiting for Check my work);
    /// the session's earlier turns for the transcript.
    var paused = false
    var hints = false
    var yourTurn: String?
    var transcript: [TurnLines] = []
    struct TurnLines: Identifiable { let id: Int; let q: String; let lines: [String] }

    unowned let board: BoardController
    let drawer: TutorDrawer
    private let listener = Listener()
    @ObservationIgnored private var session: TutorSession?
    @ObservationIgnored private var sessionReadOnly = false
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Each turn's number: a stopped or cut-off turn's late events are dropped (a new turn may already be running).
    @ObservationIgnored private var turnN = 0
    /// The sentences of this answer the voice has started (told to the next turn if you cut in), and the cut-off answer's.
    @ObservationIgnored private var heard: [String] = []
    @ObservationIgnored private var cutoff: (said: String, at: Date)?
    @ObservationIgnored private var lastAsk: String?
    @ObservationIgnored private var pendingAsk: String?

    static let model = "sonnet"
    static let focusSeconds: TimeInterval = 60
    static let cutoffSeconds: TimeInterval = 120

    init(board: BoardController) {
        self.board = board
        drawer = TutorDrawer(board: board)
    }

    var busy: Bool { phase == .thinking || phase == .speaking }

    // MARK: asking out loud

    func startListening() {
        guard phase == .idle || busy else { return }
        if busy { stop() } // (talking over it cuts it off: the next turn is told how far you heard)
        Task {
            if let why = await Listener.ask() { problem = why; return }
            problem = nil
            asked = ""
            said = []
            open = true
            listener.onPartial = { [weak self] t in self?.asked = t }
            if let why = listener.start() { problem = why; phase = .idle; return }
            phase = .listening
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func stopListening() {
        guard phase == .listening else { return }
        Task {
            let words = await listener.stop()
            asked = words
            phase = .idle
            ask(words)
        }
    }

    // MARK: one turn

    enum Kind { case normal, check, practice }

    /// One question. Asked while it talks (typed or out loud), it cuts the answer off first. kind: Check my work (the board's picture
    /// is checked against what the last turn asked) or Try one (a practice problem); hints only and what you selected or just circled
    /// go with it too.
    func ask(_ words: String, kind: Kind = .normal) {
        guard !board.readOnly else { problem = "This board is read-only here, so the tutor can't draw on it."; return }
        if busy { stop() }
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        var asking = TutorPrompt.Asking(hints: hints, practice: kind == .practice)
        if let c = cutoff, Date().timeIntervalSince(c.at) < BoardTutor.cutoffSeconds { asking.interrupted = c.said }
        cutoff = nil
        if kind == .check { asking.check = lastAsk ?? yourTurn ?? "the next step" }
        let focus = kind == .normal ? focusBox() : nil
        asked = w
        said = []
        heard = []
        problem = nil
        yourTurn = nil
        open = true
        phase = .thinking
        turnN += 1
        let me = turnN
        task = Task { await run(w, me: me, asking: asking, focus: focus) }
    }

    func stop() {
        if busy { cutoff = (heard.joined(separator: " "), Date()) } // (an answer stopped part way: what you had heard of it)
        turnN += 1
        task?.cancel()
        listener.cancel()
        if paused { paused = false }
        Speaker.shared.stop()
        drawer.finishNow()
        if phase != .idle { phase = .idle }
    }

    // MARK: the strip's buttons (the laptop's bar)

    func pause(_ on: Bool) {
        guard busy || !on else { return }
        paused = on
        Speaker.shared.pause(on)
    }
    /// Back: the sentence before is said again, then this one. Next: on to the next sentence now (its drawing goes with it).
    func back() {
        if paused { pause(false) }
        Speaker.shared.onAgain = { [weak self] s in self?.said.append(s) } // (said again: shown once more)
        Speaker.shared.back()
    }
    func next() { if paused { pause(false) }; Speaker.shared.skip() }
    func checkWork() { ask("Check my work.", kind: .check) }
    func nextHint() { ask("Next hint, please.") }
    func practice() { ask("Give me a practice problem like this one.", kind: .practice) }
    /// A line of the transcript: replay the board from there.
    func replay(from turn: Int, n: Int) { board.openTutorReplay(from: (turn, n)) }

    /// Point and ask: the block you selected, else the stroke you wrote in the last minute (a circle round something), once.
    private func focusBox() -> CGRect? {
        if let it = board.selectedItem { return board.box(of: it) }
        if let s = board.lastStroke, !s.asked, Date().timeIntervalSince(s.at) < BoardTutor.focusSeconds {
            board.lastStroke?.asked = true
            return s.box
        }
        return nil
    }

    private func run(_ words: String, me: Int, asking given: TutorPrompt.Asking, focus: CGRect?) async {
        var asking = given
        let started = Date()
        var s = loadSession()
        board.saveNow()

        // what is on screen, and where this turn draws
        let visible = board.visibleBoard
        let vis = TutorBox(visible.minX, visible.minY, visible.width, visible.height)
        let frame = TutorPrompt.frame(visible: vis, content: contentBoxes(in: visible))
        drawer.turn(at: frame)
        let image = snapshot(visible: visible, frame: frame)
        let strokes = board.content.strokes.filter { st in st.points.contains { visible.contains(CGPoint(x: $0[0], y: $0[1])) } }
        let lines: [HandwritingIndex.Line] = await Task.detached(priority: .userInitiated) { HandwritingIndex.Worker.handwrittenLines(strokes) }.value
        let rel = { (x: Double, y: Double, w: Double, h: Double) in TutorBox(x - frame[0], y - frame[1], w, h) }
        let handwriting = lines.map { TutorPrompt.Seen(text: $0.text, box: rel($0.x, $0.y, $0.w, $0.h)) }
        let typed: [TutorPrompt.Seen] = board.content.items.filter { $0.type == "text" }.compactMap { it in
            let b = board.box(of: it)
            guard b.intersects(visible) else { return nil }
            let md = (board.content.texts[it.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return md.isEmpty ? nil : TutorPrompt.Seen(text: md.replacingOccurrences(of: "\n", with: " / "), box: rel(b.minX, b.minY, b.width, b.height))
        }
        let viewBox = TutorBox(vis.x - frame[0], vis.y - frame[1], vis.w, vis.h)
        if let f = focus { asking.selection = rel(f.minX, f.minY, f.width, f.height) }
        let text = TutorPrompt.iPadTurn(words: words, board: drawer.summary(), view: image == nil ? nil : viewBox, handwriting: handwriting, typed: typed, asking: asking)

        var messages: [ClaudeMessage] = s.history().map { $0.role == "user" ? .user($0.text) : .assistant($0.text) }
        var content: [ClaudeBlock] = []
        if let image { content.append(.image(mediaType: "image/jpeg", base64: image.base64EncodedString())) }
        content.append(.text(text))
        messages.append(ClaudeMessage(role: "user", content: content))
        var req = ClaudeRequest(model: BoardTutor.model, system: TutorPrompt.iPadSystem(), messages: messages)
        req.maxTokens = 2048
        req.effort = "low"
        req.sessionId = s.planResume

        // the reply: read as it streams, said and drawn in order
        let reader = LockedReader()
        let (events, sink) = AsyncStream<TutorEvent>.makeStream()
        pendingAsk = nil
        let player = Task { @MainActor in
            for await e in events {
                if self.turnN != me { continue }
                switch e {
                case .say(let sentence, let n):
                    self.said.append(sentence)
                    if self.phase == .thinking { self.phase = .speaking }
                    await Speaker.shared.say(sentence)
                    if self.turnN != me { continue }
                    self.heard.append(sentence)
                    // the sentence has started: the gestures made while the one before was said go
                    self.drawer.spoken(n)
                case .step(let st):
                    if st.type == "yourturn" { self.pendingAsk = st.ask }
                    await self.drawer.draw(st)
                }
            }
        }
        var reply: ClaudeReply?
        do {
            reply = try await ClaudeClient.shared.stream(req) { piece in
                for e in reader.push(piece) { sink.yield(e) }
            }
        } catch {
            if turnN == me { problem = (error as? ClaudeError)?.message ?? error.localizedDescription }
        }
        for e in reader.end() { sink.yield(e) }
        sink.finish()
        await player.value
        if turnN == me { await Speaker.shared.untilDone(); drawer.ended() }
        if !drawer.problems.isEmpty { print("tutor:", drawer.problems.joined(separator: "; ")); drawer.problems = [] }

        if let reply, !reply.text.isEmpty {
            s.add(.init(at: started, you: words, reply: reply.text, mode: reply.mode.rawValue, model: reply.model, cost: reply.cost,
                        ms: reply.msToFirstText, sessionId: reply.sessionId))
            session = s
            saveSession(s)
            checkReplay()
        }
        guard turnN == me else { return } // (stopped, or cut off by a new question: that one owns the panel now)
        if paused { paused = false }
        if let ask = pendingAsk {
            // your turn: the strip waits with Check my work, and the Pencil writes
            yourTurn = ask
            lastAsk = ask
            board.selectTool(.pen)
        }
        if phase != .idle { phase = .idle }
    }

    /// Everything on the board that a turn should keep clear of, in view.
    private func contentBoxes(in visible: CGRect) -> [TutorBox] {
        var out: [TutorBox] = []
        for k in board.canvas.drawing.strokes {
            let r = k.renderBounds.offsetBy(dx: -board.offset.x, dy: -board.offset.y)
            if r.intersects(visible) { out.append(TutorBox(r.minX, r.minY, r.width, r.height)) }
        }
        for it in board.content.items where it.type != "pdf" {
            let r = board.box(of: it)
            if r.intersects(visible) { out.append(TutorBox(r.minX, r.minY, r.width, r.height)) }
        }
        // a PDF's page fills the screen: keep clear of the page in view only
        for p in board.pdfs.values {
            for f in p.frames where f.intersects(visible) { out.append(TutorBox(f.minX, f.minY, f.width, f.height)) }
        }
        return out
    }

    // MARK: the picture of the board

    /// The board on screen, with a faint grid of the turn's coordinates (every 100 units, numbered), as a JPEG at most 1568 px long.
    private func snapshot(visible: CGRect, frame: [Double]) -> Data? {
        let v = board.view!
        let bounds = board.canvas.frame
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let hidden = board.tutorPanelView?.isHidden
        board.tutorPanelView?.isHidden = true
        defer { if let hidden { board.tutorPanelView?.isHidden = hidden } }
        let scale = min(1568 / max(bounds.width, bounds.height), 2)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = true
        let img = UIGraphicsImageRenderer(size: bounds.size, format: fmt).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))
            v.drawHierarchy(in: CGRect(x: -bounds.minX, y: -bounds.minY, width: v.bounds.width, height: v.bounds.height), afterScreenUpdates: true)
            // the grid: board x = frame x + k * 100
            let per = bounds.width / visible.width
            let g = ctx.cgContext
            g.setStrokeColor(UIColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 0.22).cgColor)
            g.setLineWidth(1 / scale)
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                                                        .foregroundColor: UIColor(red: 0.15, green: 0.35, blue: 0.8, alpha: 0.85),
                                                        .backgroundColor: UIColor.white.withAlphaComponent(0.75)]
            let step = visible.width > 2400 ? 500.0 : visible.width > 1200 ? 200.0 : 100.0
            var k = ceil((visible.minX - frame[0]) / step)
            while frame[0] + k * step <= visible.maxX {
                let x = (frame[0] + k * step - visible.minX) * per
                g.move(to: CGPoint(x: x, y: 0)); g.addLine(to: CGPoint(x: x, y: bounds.height)); g.strokePath()
                NSString(string: String(Int(k * step))).draw(at: CGPoint(x: x + 2, y: 2), withAttributes: attrs)
                k += 1
            }
            k = ceil((visible.minY - frame[1]) / step)
            while frame[1] + k * step <= visible.maxY {
                let y = (frame[1] + k * step - visible.minY) * per
                g.move(to: CGPoint(x: 0, y: y)); g.addLine(to: CGPoint(x: bounds.width, y: y)); g.strokePath()
                NSString(string: String(Int(k * step))).draw(at: CGPoint(x: 2, y: y + 2), withAttributes: attrs)
                k += 1
            }
        }
        return img.jpegData(compressionQuality: 0.72)
    }

    // MARK: the session file

    private var sessionURL: URL { board.boardURL.appendingPathComponent(TutorSession.file) }

    private func loadSession() -> TutorSession {
        if let session { return session }
        let text = (try? Data(contentsOf: sessionURL)).map { String(decoding: $0, as: UTF8.self) }
        let p = TutorSession.parse(text)
        sessionReadOnly = !p.ok && text != nil
        session = p.session
        return p.session
    }

    private func saveSession(_ s: TutorSession) {
        guard !sessionReadOnly else { return }
        // another device may have added turns since: keep theirs, then ours
        if let d = try? Data(contentsOf: sessionURL) {
            let disk = TutorSession.parse(String(decoding: d, as: UTF8.self))
            if disk.ok, disk.session.turns.count > s.turns.count - 1, !s.turns.isEmpty {
                var merged = disk.session
                merged.turns.append(s.turns[s.turns.count - 1])
                if let id = s.sessionId { merged.sessionId = id }
                session = merged
                try? FolderAccess.write(sessionURL, merged.serialized)
                board.onSaved?(board.path)
                return
            }
        }
        do { try FolderAccess.write(sessionURL, s.serialized) } catch { problem = "Couldn't save the tutor's conversation: \(error.localizedDescription)" }
        board.onSaved?(board.path)
    }

    var turnCount: Int { session?.turns.count ?? 0 }

    /// Reads the session file again for `canReplay` (another device may have added turns).
    func checkReplay() {
        let p = TutorSession.parse(try? FolderAccess.read(sessionURL))
        canReplay = p.ok && !p.session.replayTurns().isEmpty
        transcript = p.ok ? p.session.transcript().enumerated().map { TurnLines(id: $0.offset, q: $0.element.q, lines: $0.element.lines) } : []
    }
}

/// TutorReader behind a lock: the reply's pieces may arrive on any thread.
final class LockedReader: @unchecked Sendable {
    private let lock = NSLock()
    private let reader = TutorReader()
    func push(_ s: String) -> [TutorEvent] { lock.lock(); defer { lock.unlock() }; return reader.push(s) }
    func end() -> [TutorEvent] { lock.lock(); defer { lock.unlock() }; return reader.end() }
}

// MARK: - on the board

private var tutorKey: UInt8 = 0
private var panelKey: UInt8 = 0

extension BoardController {
    /// This board's tutor (made the first time it is used).
    var tutor: BoardTutor {
        if let t = objc_getAssociatedObject(self, &tutorKey) as? BoardTutor { return t }
        let t = BoardTutor(board: self)
        objc_setAssociatedObject(self, &tutorKey, t, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return t
    }

    var tutorPanelView: UIView? { (objc_getAssociatedObject(self, &panelKey) as? UIViewController)?.view }

    /// Whether the tutor is answering (its own ink is not "what you just circled").
    var tutorIsBusy: Bool { (objc_getAssociatedObject(self, &tutorKey) as? BoardTutor)?.busy ?? false }

    /// The tutor button for the bar: hold to ask out loud, tap to open the panel (and type).
    func tutorButton() -> UIButton {
        var c = UIButton.Configuration.plain()
        c.image = UIImage(systemName: "graduationcap", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
        c.cornerStyle = .medium
        let b = TutorHoldButton(configuration: c)
        b.tintColor = .label
        b.accessibilityLabel = "Tutor: hold to ask, tap to type"
        b.toolTip = "Tutor: hold to ask, tap to type"
        b.onTap = { [weak self] in self?.toggleTutorPanel() }
        b.onHoldStart = { [weak self] in self?.showTutorPanel(); self?.tutor.startListening() }
        b.onHoldEnd = { [weak self] in self?.tutor.stopListening() }
        return b
    }

    func toggleTutorPanel() {
        // End typing first: hiding alone leaves the keyboard up, typing into a box nobody can see.
        if let v = tutorPanelView, !v.isHidden { v.endEditing(true); v.isHidden = true; tutor.open = false } else { showTutorPanel() }
    }

    func showTutorPanel() {
        tutor.open = true
        tutor.checkReplay()
        if let v = tutorPanelView { v.isHidden = false; view.bringSubviewToFront(v); return }
        let host = UIHostingController(rootView: TutorPanel(tutor: tutor, onClose: { [weak self] in self?.toggleTutorPanel() },
                                                    onReplay: { [weak self] in self?.openTutorReplay() }))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            // Above the keyboard while it is up (the guide sits on the safe area's bottom when it is down).
            host.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
            host.view.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            // 380 wide, or the screen's width less a margin on an iPhone
            { () -> NSLayoutConstraint in let w = host.view.widthAnchor.constraint(equalToConstant: 380); w.priority = .defaultHigh; return w }(),
            host.view.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
        ])
        host.didMove(toParent: self)
        objc_setAssociatedObject(self, &panelKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Leaving the board: stop talking and drawing.
    func tutorBoardClosing() {
        if let t = objc_getAssociatedObject(self, &tutorKey) as? BoardTutor { t.stop() }
    }
}

/// A bar button that tells a tap from a hold (hold = ask out loud while held).
final class TutorHoldButton: UIButton {
    var onTap: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    private var timer: Timer?
    private var holding = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        holding = false
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            self?.holding = true
            self?.onHoldStart?()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        timer?.invalidate()
        if holding { onHoldEnd?() } else { onTap?() }
        holding = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        timer?.invalidate()
        if holding { onHoldEnd?() }
        holding = false
    }
}

/// The tutor's panel at the bottom right of a board: what you asked, what it says, hold to talk, type (also while it talks: that cuts
/// in), and the laptop's bar: Back / Pause / Next / Stop while it talks, Hints only, the transcript (a line replays from there), and after
/// an answer Check my work (your turn), Next hint and Try one. The Plan/API chip.
struct TutorPanel: View {
    @Bindable var tutor: BoardTutor
    var onClose: () -> Void
    var onReplay: () -> Void = {}
    @State private var typed = ""
    @State private var pressing = false
    @State private var showTranscript = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill").foregroundStyle(.tint)
                Text("Tutor").font(.headline)
                ClaudeModeChip()
                Spacer()
                Button { tutor.hints.toggle() } label: { Image(systemName: tutor.hints ? "lightbulb.fill" : "lightbulb") }
                    .foregroundStyle(tutor.hints ? Color.yellow : Color.secondary)
                    .accessibilityLabel(tutor.hints ? "Hints only: on" : "Hints only: off")
                if !tutor.transcript.isEmpty {
                    Button { showTranscript.toggle() } label: { Image(systemName: "list.bullet.rectangle") }
                        .foregroundStyle(showTranscript ? Color.accentColor : Color.secondary)
                        .accessibilityLabel("Transcript")
                }
                if tutor.canReplay && !tutor.busy && tutor.phase != .listening {
                    Button(action: onReplay) { Label("Replay", systemImage: "play.fill").font(.callout) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Replay the explanation, pointing and marks included")
                }
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Close the tutor")
            }
            if showTranscript { transcriptList }
            if !tutor.asked.isEmpty || tutor.phase == .listening {
                Text(tutor.asked.isEmpty ? "Listening…" : tutor.asked)
                    .font(.callout).foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            if !tutor.said.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(tutor.said.joined(separator: " ")).font(.body).frame(maxWidth: .infinity, alignment: .leading).id("end")
                    }
                    .frame(maxHeight: 180)
                    .onChange(of: tutor.said.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                }
            } else if tutor.phase == .thinking {
                HStack(spacing: 8) { ProgressView(); Text(tutor.hints ? "Thinking (hints only)…" : "Thinking…").foregroundStyle(.secondary) }
            }
            if tutor.busy { controls }
            if !tutor.busy && tutor.phase != .listening { afterAnswer }
            if let p = tutor.problem { Text(p).font(.footnote).foregroundStyle(.red) }
            HStack(spacing: 10) {
                talkButton
                TextField(tutor.busy ? "Type to cut in" : "Ask by typing", text: $typed, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .onSubmit(send)
                if tutor.busy && typed.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { tutor.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                        .accessibilityLabel("Stop")
                } else {
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Ask")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    /// While it talks: the sentence before again, pause, the next sentence, stop.
    private var controls: some View {
        HStack(spacing: 18) {
            Button { tutor.back() } label: { Image(systemName: "backward.end.fill") }.accessibilityLabel("Say that again")
            Button { tutor.pause(!tutor.paused) } label: { Image(systemName: tutor.paused ? "play.fill" : "pause.fill") }
                .accessibilityLabel(tutor.paused ? "Resume" : "Pause")
            Button { tutor.next() } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Next sentence")
            Button { tutor.stop() } label: { Image(systemName: "stop.fill") }.accessibilityLabel("Stop")
            if tutor.paused { Text("Paused").font(.footnote).foregroundStyle(.secondary) }
        }
        .font(.title3)
        .buttonStyle(.borderless)
    }

    /// After an answer: your turn (Check my work), the next hint, a practice problem.
    @ViewBuilder private var afterAnswer: some View {
        if let ask = tutor.yourTurn {
            HStack(spacing: 8) {
                Image(systemName: "pencil.tip").foregroundStyle(.blue)
                Text(ask.replacingOccurrences(of: #"^(?i)your turn:?\s*"#, with: "", options: .regularExpression))
                    .font(.callout).lineLimit(3)
            }
        }
        if tutor.yourTurn != nil || !tutor.said.isEmpty {
            HStack(spacing: 8) {
                if tutor.yourTurn != nil {
                    Button { tutor.checkWork() } label: { Label("Check my work", systemImage: "checkmark.circle") }
                        .buttonStyle(.borderedProminent)
                }
                if tutor.hints { Button { tutor.nextHint() } label: { Text("Next hint") }.buttonStyle(.bordered) }
                if tutor.yourTurn == nil { Button { tutor.practice() } label: { Text("Try one") }.buttonStyle(.bordered) }
            }
            .controlSize(.small)
        }
    }

    /// The session's turns, a line at a time: tap one to replay the board from there.
    private var transcriptList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tap a line to replay the board from there.").font(.caption).foregroundStyle(.secondary)
                ForEach(tutor.transcript) { t in
                    if !t.q.isEmpty { Text("“\(t.q)”").font(.callout.italic()).foregroundStyle(.secondary) }
                    ForEach(Array(t.lines.enumerated()), id: \.offset) { i, line in
                        Button { tutor.replay(from: t.id, n: i) } label: {
                            Text(line).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private var talkButton: some View {
        Image(systemName: tutor.phase == .listening ? "waveform.circle.fill" : "mic.circle.fill")
            .font(.system(size: 34))
            .foregroundStyle(tutor.phase == .listening ? Color.red : Color.accentColor)
            .symbolEffect(.pulse, isActive: tutor.phase == .listening)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressing { pressing = true; tutor.startListening() } }
                .onEnded { _ in pressing = false; tutor.stopListening() })
            .accessibilityLabel("Hold to ask out loud (cuts in while it talks)")
    }

    private func send() {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        typed = ""
        typing = false
        tutor.ask(t) // (while it talks: it stops and is told how far you had heard)
    }
}
