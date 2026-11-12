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

    unowned let board: BoardController
    let drawer: TutorDrawer
    private let listener = Listener()
    @ObservationIgnored private var session: TutorSession?
    @ObservationIgnored private var sessionReadOnly = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var stopped = false

    static let model = "sonnet"

    init(board: BoardController) {
        self.board = board
        drawer = TutorDrawer(board: board)
    }

    var busy: Bool { phase == .thinking || phase == .speaking }

    // MARK: asking out loud

    func startListening() {
        guard phase == .idle || phase == .speaking else { return }
        if phase == .speaking { stop() }
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

    func ask(_ words: String) {
        guard !busy, !board.readOnly else {
            if board.readOnly { problem = "This board is read-only here, so the tutor can't draw on it." }
            return
        }
        let w = words.trimmingCharacters(in: .whitespacesAndNewlines)
        asked = w
        said = []
        problem = nil
        stopped = false
        open = true
        phase = .thinking
        task = Task { await run(w) }
    }

    func stop() {
        stopped = true
        task?.cancel()
        listener.cancel()
        Speaker.shared.stop()
        drawer.finishNow()
        if phase != .idle { phase = .idle }
    }

    private func run(_ words: String) async {
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
        let text = TutorPrompt.iPadTurn(words: words, board: drawer.summary(), view: image == nil ? nil : viewBox, handwriting: handwriting, typed: typed)

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
        let player = Task { @MainActor in
            for await e in events {
                if self.stopped { continue }
                switch e {
                case .say(let sentence, _):
                    self.said.append(sentence)
                    if self.phase == .thinking { self.phase = .speaking }
                    await Speaker.shared.say(sentence)
                case .step(let st):
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
            problem = (error as? ClaudeError)?.message ?? error.localizedDescription
        }
        for e in reader.end() { sink.yield(e) }
        sink.finish()
        await player.value
        if !stopped { await Speaker.shared.untilDone() }
        if !drawer.problems.isEmpty { print("tutor:", drawer.problems.joined(separator: "; ")); drawer.problems = [] }

        if let reply, !reply.text.isEmpty {
            s.add(.init(at: started, you: words, reply: reply.text, mode: reply.mode.rawValue, model: reply.model, cost: reply.cost,
                        ms: reply.msToFirstText, sessionId: reply.sessionId))
            session = s
            saveSession(s)
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
        if let v = tutorPanelView, !v.isHidden { v.isHidden = true; tutor.open = false } else { showTutorPanel() }
    }

    func showTutorPanel() {
        tutor.open = true
        if let v = tutorPanelView { v.isHidden = false; view.bringSubviewToFront(v); return }
        let host = UIHostingController(rootView: TutorPanel(tutor: tutor, onClose: { [weak self] in self?.toggleTutorPanel() }))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
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

/// The tutor's panel at the bottom right of a board: what you asked, what it says, hold to talk, type, stop, and the Plan/API chip.
struct TutorPanel: View {
    @Bindable var tutor: BoardTutor
    var onClose: () -> Void
    @State private var typed = ""
    @State private var pressing = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill").foregroundStyle(.tint)
                Text("Tutor").font(.headline)
                ClaudeModeChip()
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Close the tutor")
            }
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
                HStack(spacing: 8) { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
            }
            if let p = tutor.problem { Text(p).font(.footnote).foregroundStyle(.red) }
            HStack(spacing: 10) {
                talkButton
                TextField("Ask by typing", text: $typed, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .focused($typing)
                    .onSubmit(send)
                if tutor.busy {
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

    private var talkButton: some View {
        Image(systemName: tutor.phase == .listening ? "waveform.circle.fill" : "mic.circle.fill")
            .font(.system(size: 34))
            .foregroundStyle(tutor.phase == .listening ? Color.red : Color.accentColor)
            .symbolEffect(.pulse, isActive: tutor.phase == .listening)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressing { pressing = true; tutor.startListening() } }
                .onEnded { _ in pressing = false; tutor.stopListening() })
            .accessibilityLabel("Hold to ask out loud")
    }

    private func send() {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !tutor.busy else { return }
        typed = ""
        typing = false
        tutor.ask(t)
    }
}
