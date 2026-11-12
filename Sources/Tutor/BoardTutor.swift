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
    /// The ways of asking: a question, Check my work (the board's picture against what it asked), Try one (a practice problem), a hint
    /// (one hints-only turn, even with Hints only off).
    enum Kind { case normal, check, practice, hint }

    var phase: Phase = .idle
    var open = false
    /// Shrunk to a pill at the bottom right, so the whole board shows while it draws.
    var compact = false
    /// What was asked this turn (live while listening), and how.
    var asked = ""
    var askedKind: Kind = .normal
    /// What the tutor has said this turn, and the sentence being said now (an index into `said`; -1 before the first starts).
    var said: [String] = []
    var speaking = -1
    /// This turn shows as the chat's last turn until it is saved into `chat`.
    var live = false
    var problem: String?
    /// Whether the board's tutor.json has an explanation Replay can play again.
    var canReplay = false
    /// The laptop's bar: paused; hints only; the answer ended with "your turn" (what to write, waiting for Check my work).
    var paused = false
    var hints = false
    var yourTurn: String?
    /// The session's turns (tutor.json), oldest first: the chat.
    var chat: [TutorSession.ChatTurn] = []
    /// The microphone was tapped, not held: it listens until it is tapped again.
    var listenLocked = false

    unowned let board: BoardController
    let drawer: TutorDrawer
    private let listener = Listener()
    @ObservationIgnored private var session: TutorSession?
    @ObservationIgnored private var sessionReadOnly = false
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Each turn's number: a stopped or cut-off turn's late events are dropped (a new turn may already be running).
    @ObservationIgnored private var turnN = 0
    /// The turn the chat shows as live (it stops being live once it is saved).
    @ObservationIgnored private var liveTurn = 0
    /// The sentences of this answer the voice has started (told to the next turn if you cut in), and the cut-off answer's.
    @ObservationIgnored private var heard: [String] = []
    @ObservationIgnored private var cutoff: (said: String, at: Date)?
    @ObservationIgnored private var lastAsk: String?
    @ObservationIgnored private var pendingAsk: String?
    /// The last question (Try again after a problem).
    @ObservationIgnored private(set) var lastRequest: (words: String, kind: Kind)?
    /// The microphone is being started (asking for permission); a release before it is up stops it as soon as it is.
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var stopWanted = false

    static let model = "sonnet"
    static let focusSeconds: TimeInterval = 60
    static let cutoffSeconds: TimeInterval = 120

    /// What the panel's buttons ask in words (they are the question in the chat and in tutor.json, as the laptop's bar asks).
    static let checkWords = "Check my work."
    static let hintWords = "Give me a hint."
    static let nextHintWords = "Next hint, please."
    static let practiceWords = "Give me a practice problem like this one."
    static let showWords = "Show me how to do this step."
    static let explainWords = "Explain what's on my board."

    /// A saved question's kind, from its words (the chat marks the buttons' questions).
    static func kind(of q: String) -> Kind {
        switch q {
        case checkWords: return .check
        case hintWords, nextHintWords: return .hint
        case practiceWords: return .practice
        default: return .normal
        }
    }

    init(board: BoardController) {
        self.board = board
        drawer = TutorDrawer(board: board)
    }

    var busy: Bool { phase == .thinking || phase == .speaking }

    // MARK: asking out loud

    /// Hold (or tap) the microphone. Talking over the tutor cuts it off: the next turn is told how far you heard.
    func startListening(locked: Bool = false) {
        guard (phase == .idle || busy), !starting else { return }
        if busy { stop() }
        starting = true
        stopWanted = false
        listenLocked = locked
        Task {
            defer { starting = false }
            if let why = await Listener.ask() { problem = why; listenLocked = false; return }
            problem = nil
            asked = ""
            askedKind = .normal
            said = []
            speaking = -1
            yourTurn = nil
            live = true
            open = true
            listener.onPartial = { [weak self] t in self?.asked = t }
            if let why = listener.start() { problem = why; phase = .idle; live = false; listenLocked = false; return }
            phase = .listening
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if stopWanted { stopListening() }
        }
    }

    /// Let go of the microphone (or tap it again): what you said is asked.
    func stopListening() {
        if starting && phase != .listening { stopWanted = true; return }
        guard phase == .listening else { return }
        listenLocked = false
        Task {
            let words = await listener.stop()
            asked = words
            phase = .idle
            ask(words)
        }
    }

    /// Stop listening without asking.
    func cancelListening() {
        stopWanted = false
        listenLocked = false
        guard phase == .listening else { return }
        listener.cancel()
        phase = .idle
        live = false
        asked = ""
    }

    // MARK: one turn

    /// One question. Asked while it talks (typed or out loud), it cuts the answer off first. kind: Check my work (the board's picture
    /// is checked against what the last turn asked), Try one (a practice problem) or a hint; hints only and what you selected or just
    /// circled go with it too.
    func ask(_ words: String, kind: Kind = .normal) {
        guard !board.readOnly else { problem = "This board is read-only here, so the tutor can't draw on it."; return }
        if busy { stop() }
        if phase == .listening { cancelListening() }
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        lastRequest = (w, kind)
        var asking = TutorPrompt.Asking(hints: hints || kind == .hint, practice: kind == .practice)
        if let c = cutoff, Date().timeIntervalSince(c.at) < BoardTutor.cutoffSeconds { asking.interrupted = c.said }
        cutoff = nil
        if kind == .check { asking.check = lastAsk ?? yourTurn ?? "the next step" }
        let focus = kind == .normal || kind == .hint ? focusBox() : nil
        checkReplay() // (the chat as saved now: this turn shows after it)
        asked = w
        askedKind = kind
        said = []
        speaking = -1
        heard = []
        problem = nil
        yourTurn = nil
        live = true
        open = true
        phase = .thinking
        turnN += 1
        let me = turnN
        liveTurn = me
        task = Task { await run(w, me: me, asking: asking, focus: focus) }
    }

    func stop() {
        if busy { cutoff = (heard.joined(separator: " "), Date()) } // (an answer stopped part way: what you had heard of it)
        turnN += 1
        task?.cancel()
        listener.cancel()
        listenLocked = false
        if paused { paused = false }
        Speaker.shared.stop()
        drawer.finishNow()
        if phase != .idle { phase = .idle }
    }

    /// Ask the last question again (after a problem).
    func retry() {
        guard let r = lastRequest else { return }
        ask(r.words, kind: r.kind)
    }

    // MARK: the panel's buttons (the laptop's bar)

    func pause(_ on: Bool) {
        guard busy || !on else { return }
        paused = on
        Speaker.shared.pause(on)
    }
    /// Back: the sentence before is said again, then this one. Next: on to the next sentence now (its drawing goes with it).
    func back() {
        if paused { pause(false) }
        Speaker.shared.onAgain = nil
        if Speaker.shared.back(), speaking > 0 { speaking -= 1 }
    }
    func next() { if paused { pause(false) }; Speaker.shared.skip() }
    func checkWork() { ask(BoardTutor.checkWords, kind: .check) }
    /// One hint: the next one if the last turn was a hint too.
    func hint() { ask(askedKind == .hint && !live ? BoardTutor.nextHintWords : BoardTutor.hintWords, kind: .hint) }
    func nextHint() { ask(BoardTutor.nextHintWords, kind: .hint) }
    func practice() { ask(BoardTutor.practiceWords, kind: .practice) }
    func showMe() { ask(BoardTutor.showWords) }
    /// A sentence of the chat: replay the board from there.
    func replay(from turn: Int, n: Int) { board.openTutorReplay(from: (turn, n)) }
    /// Read an answer aloud again (the voice only).
    func readAloud(_ lines: [String]) {
        guard !busy else { return }
        Speaker.shared.read(lines.joined(separator: " "))
    }

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

        // what is on screen (less the bar and the open panel), and where this turn draws
        let area = board.tutorArea
        let visible = board.boardRect(ofView: area)
        let vis = TutorBox(visible.minX, visible.minY, visible.width, visible.height)
        let frame = TutorPrompt.frame(visible: vis, content: contentBoxes(in: visible))
        drawer.turn(at: frame)
        let image = snapshot(visible: visible, frame: frame, area: area)
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
                    let i = self.said.count - 1
                    if self.phase == .thinking { self.phase = .speaking }
                    if TutorDemo.active { await TutorDemo.pace(sentence) } else { await Speaker.shared.say(sentence) }
                    if self.turnN != me { continue }
                    self.speaking = i
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
            let onText: (String) -> Void = { piece in
                for e in reader.push(piece) { sink.yield(e) }
            }
            if TutorDemo.active { reply = await TutorDemo.stream(words, asking: asking, onText: onText) } else {
                reply = try await ClaudeClient.shared.stream(req, onText: onText)
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
            if liveTurn == me, chat.count > 0 { live = false } // (saved: the chat has it now)
        }
        guard turnN == me else { return } // (stopped, or cut off by a new question: that one owns the panel now)
        if paused { paused = false }
        speaking = said.count
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
    private func snapshot(visible: CGRect, frame: [Double], area: CGRect) -> Data? {
        let v = board.view!
        let bounds = area
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

    /// Reads the session file again for the chat and `canReplay` (another device may have added turns).
    func checkReplay() {
        let p = TutorSession.parse(try? FolderAccess.read(sessionURL))
        canReplay = p.ok && !p.session.replayTurns().isEmpty
        chat = p.ok ? p.session.chat() : []
        // a your turn from before (this board opened again): Check my work still checks it
        if !busy, phase != .listening, !live, yourTurn == nil, let last = chat.last?.yourTurn { yourTurn = last; lastAsk = last }
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

    /// The bar's tutor button tapped: open the panel (or the pill, opened up), or close it.
    func toggleTutorPanel() {
        if let v = tutorPanelView, !v.isHidden, !tutor.compact { closeTutorPanel() } else { tutor.compact = false; showTutorPanel() }
    }

    /// Close the panel. End typing first: hiding alone leaves the keyboard up, typing into a box nobody can see. Listening stops;
    /// an answer goes on (the bar's button opens it again).
    func closeTutorPanel() {
        guard let v = tutorPanelView else { return }
        v.endEditing(true)
        tutor.cancelListening()
        v.isHidden = true
        tutor.open = false
    }

    func showTutorPanel() {
        tutor.open = true
        tutor.checkReplay()
        if let host = objc_getAssociatedObject(self, &panelKey) as? TutorPanelHost {
            host.view.isHidden = false
            view.bringSubviewToFront(host.view)
            host.place()
            return
        }
        let host = TutorPanelHost(board: self)
        addChild(host)
        view.addSubview(host.view)
        host.attach()
        host.didMove(toParent: self)
        objc_setAssociatedObject(self, &panelKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Keeps the panel under the bar as the board lays out (BoardController.viewDidLayoutSubviews).
    func layOutTutorPanel() {
        (objc_getAssociatedObject(self, &panelKey) as? TutorPanelHost)?.place()
    }

    /// Where the tutor looks and draws, in the view's points: the board on screen less the bar, and less the panel while it is open
    /// (beside it on an iPad, above it on a narrow screen), so it never draws under the panel.
    var tutorArea: CGRect {
        var r = canvas.frame
        let top = topInset
        if r.minY < top { r.size.height -= top - r.minY; r.origin.y = top }
        if let v = tutorPanelView, !v.isHidden, !tutor.compact, v.frame.width > 0 {
            let p = v.frame
            if p.width < r.width * 0.6 { r.size.width = max(240, p.minX - 8 - r.minX) } else { r.size.height = max(200, p.minY - 8 - r.minY) }
        }
        return r
    }

    /// A rectangle of the view (points) as board units.
    func boardRect(ofView r: CGRect) -> CGRect {
        let z = canvas.zoomScale
        let vb = visibleBoard
        return CGRect(x: vb.minX + (r.minX - canvas.frame.minX) / z, y: vb.minY + (r.minY - canvas.frame.minY) / z, width: r.width / z, height: r.height / z)
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
