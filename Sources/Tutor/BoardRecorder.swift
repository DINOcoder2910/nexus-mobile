import AVFoundation
import UIKit
import SwiftUI
import PencilKit
import NexusCore

/// Recording a class while writing on a board (nexus docs/data-format.md "The board redesign's additions", NexusCore Recording.swift):
/// the sound goes to a temporary file while recording and into the board's `files/recording-<id>.m4a` when it stops (so sync never
/// sends half a recording), with `recordings/<id>.json` saying when each stroke and each typed word was made. Playing one back, a tap
/// on a stroke or a block plays from the moment it was written, and the notes appear in step with the sound.
@MainActor
@Observable
final class BoardRecorder {
    enum Mode { case idle, recording, playing, paused }
    var mode: Mode = .idle
    var elapsed: Double = 0
    var duration: Double = 0
    var problem: String?
    var current: BoardRecording?
    var recordings: [BoardRecording] = []
    /// Notes appear in step while playing (strokes written later are hidden).
    var inStep = true

    unowned let board: BoardController
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var temp: URL?
    @ObservationIgnored private var timer: Timer?
    /// Strokes seen while recording (by their fingerprint), until a save gives them ids.
    @ObservationIgnored private var pending: [String: Double] = [:]
    @ObservationIgnored private var seenCount = 0
    @ObservationIgnored private var hidden: Set<String>?

    init(board: BoardController) {
        self.board = board
        reload()
    }

    func reload() { recordings = BoardRecording.list(board.boardURL) }

    // MARK: recording

    func start() {
        guard mode == .idle, !board.readOnly else { return }
        Task {
            guard await Audio.askMicrophone() else { problem = "Nexus isn't allowed to use the microphone. Turn it on in iPad Settings › Nexus."; return }
            Audio.configure()
            let ids = Set(recordings.map(\.id)).union(board.allIds)
            let id = BoardFormat.newId(taken: ids)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(id).m4a")
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 22050, AVNumberOfChannelsKey: 1,
                                           AVEncoderBitRateKey: 32000, AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            do {
                let r = try AVAudioRecorder(url: url, settings: settings)
                guard r.record() else { problem = "The recording couldn't start."; return }
                recorder = r
                temp = url
                current = BoardRecording(id: id)
                pending = [:]
                seenCount = board.canvas.drawing.strokes.count
                problem = nil
                mode = .recording
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.elapsed = self?.recorder?.currentTime ?? 0 }
                }
            } catch {
                problem = "The recording couldn't start: \(error.localizedDescription)"
            }
        }
    }

    var now: Double { recorder?.currentTime ?? 0 }

    /// The drawing changed: new strokes are timed now (their ids come with the next save).
    func drawingChanged() {
        guard mode == .recording else { return }
        let strokes = board.canvas.drawing.strokes
        if strokes.count > seenCount {
            for k in strokes[seenCount...] {
                pending[InkConvert.fingerprint(InkConvert.boardStroke(k, offset: board.offset, id: ""))] = now
            }
        }
        seenCount = strokes.count
    }

    /// The board saved: the strokes timed while recording now have ids.
    func saved() {
        guard mode == .recording, !pending.isEmpty, var r = current else { return }
        for s in board.content.strokes {
            if let at = pending.removeValue(forKey: InkConvert.fingerprint(s)) { r.markStroke(s.id, at: at) }
        }
        current = r
    }

    /// Words typed into a block while recording.
    func typed(_ id: String, old: String, new: String) {
        guard mode == .recording, var r = current else { return }
        r.typing(item: id, old: old, new: new, at: now)
        current = r
    }

    func stop() {
        guard mode == .recording, let r0 = recorder, var r = current, let temp else { return }
        board.saveNow()
        saved()
        r = current ?? r
        r.duration = r0.currentTime
        r0.stop()
        recorder = nil
        timer?.invalidate()
        mode = .idle
        do {
            let data = try Data(contentsOf: temp)
            try FolderAccess.writeData(board.boardURL.appendingPathComponent(r.file), data)
            try FolderAccess.write(board.boardURL.appendingPathComponent(BoardRecording.jsonPath(r.id)), r.text)
            try? FileManager.default.removeItem(at: temp)
            board.onSaved?(board.path)
        } catch {
            problem = "Couldn't keep the recording: \(error.localizedDescription). It is still in the app's temporary files."
        }
        self.temp = nil
        current = nil
        reload()
        board.refreshExtraButtons()
    }

    // MARK: playing back

    func open(_ r: BoardRecording) {
        stopPlaying()
        guard let url = BoardFiles.resolve(r.file, board: board.boardURL, root: board.root),
              FileManager.default.fileExists(atPath: url.path) else {
            problem = "This recording's sound isn't on this iPad yet."
            return
        }
        do {
            Audio.configure()
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            player = p
            current = r
            duration = p.duration
            elapsed = 0
            mode = .paused
            problem = nil
            board.saveNow()
            board.showRecordingBar()
        } catch {
            problem = "This recording couldn't be played: \(error.localizedDescription)"
        }
    }

    func play(from t: Double? = nil) {
        guard let p = player else { return }
        if let t { p.currentTime = max(0, min(p.duration - 0.05, t)) }
        p.play()
        mode = .playing
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        tick()
    }

    func pause() {
        player?.pause()
        mode = .paused
        timer?.invalidate()
    }

    func seek(_ t: Double) {
        player?.currentTime = t
        elapsed = t
        showInStep()
    }

    private func tick() {
        guard let p = player else { return }
        elapsed = p.currentTime
        if !p.isPlaying, mode == .playing { mode = .paused; timer?.invalidate() }
        showInStep()
    }

    /// Hides what was written after this moment (only on screen: nothing is saved while playing).
    func showInStep() {
        guard let r = current, mode == .playing || mode == .paused else { return }
        let hide = inStep ? r.strokesNotYet(at: elapsed) : []
        let hideItems = inStep ? r.itemsNotYet(at: elapsed) : []
        for (id, v) in board.itemViews { v.isHidden = hideItems.contains(id) }
        if hide == hidden && board.canvas.drawing.strokes.count == expected { return }
        hidden = hide
        let strokes = board.content.strokes.filter { !hide.contains($0.id) }.flatMap { InkConvert.pkStrokes($0, offset: board.offset) }
        expected = strokes.count
        board.shifting = true
        board.canvas.drawing = PKDrawing(strokes: strokes)
        board.shifting = false
        board.canvas.drawingGestureRecognizer.isEnabled = false
    }
    @ObservationIgnored private var expected = -1

    func stopPlaying() {
        player?.stop()
        player = nil
        timer?.invalidate()
        guard mode == .playing || mode == .paused else { return }
        mode = .idle
        current = nil
        hidden = nil
        for v in board.itemViews.values { v.isHidden = false }
        board.shifting = true
        board.canvas.drawing = board.ledger.drawing(board.content.strokes, offset: board.offset)
        board.strokeCount = board.canvas.drawing.strokes.count
        board.shifting = false
        board.canvas.drawingGestureRecognizer.isEnabled = true
        board.hideRecordingBar()
    }

    /// A finger tap while a recording is open: the stroke or block under it plays from when it was written. True when it played.
    func tap(at p: CGPoint) -> Bool {
        guard let r = current, mode == .playing || mode == .paused else { return false }
        let z = board.canvas.zoomScale, reach = 22 / z
        var best: (d: CGFloat, at: Double)?
        for s in board.content.strokes {
            guard let at = r.time(ofStroke: s.id) else { continue }
            for q in s.points {
                let d = hypot(CGFloat(q[0]) - p.x, CGFloat(q[1]) - p.y)
                if d < reach, best == nil || d < best!.d { best = (d, at) }
            }
        }
        if let best { play(from: best.at - 1); return true }
        if let it = board.content.items.first(where: { $0.type == "text" && board.box(of: $0).contains(p) }) {
            let b = board.box(of: it)
            if let at = r.time(ofItem: it.id, markdown: board.content.texts[it.id] ?? "", fraction: Double((p.y - b.minY) / max(1, b.height))) {
                play(from: at - 1); return true
            }
        }
        return false
    }
}

// MARK: - on the board

private var recorderKey: UInt8 = 0
private var recordingBarKey: UInt8 = 0
private var recordingBarTopKey: UInt8 = 0

extension BoardController {
    var recorder: BoardRecorder {
        if let r = objc_getAssociatedObject(self, &recorderKey) as? BoardRecorder { return r }
        let r = BoardRecorder(board: self)
        objc_setAssociatedObject(self, &recorderKey, r, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return r
    }

    private var existingRecorder: BoardRecorder? { objc_getAssociatedObject(self, &recorderKey) as? BoardRecorder }

    /// The record button: start or stop recording, or play one of the board's recordings.
    func recordButton() -> UIButton {
        let r = recorder
        if r.mode == .recording {
            return extraButton("stop.circle.fill", "Stop recording", tinted: true) { [weak self] in self?.recorder.stop() }
        }
        let menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in done(self?.recordMenu() ?? []) }])
        return extraButton(r.recordings.isEmpty ? "mic" : "waveform", "Record", menu: menu)
    }

    private func recordMenu() -> [UIMenuElement] {
        let r = recorder
        var children: [UIMenuElement] = []
        if !readOnly {
            children.append(UIAction(title: "Record", image: UIImage(systemName: "record.circle")) { [weak self] _ in
                self?.recorder.start()
                self?.showRecordingBar()
            })
        }
        let f = DateFormatter()
        f.dateStyle = .medium; f.timeStyle = .short
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for rec in r.recordings.reversed() {
            let when = iso.date(from: rec.started).map { f.string(from: $0) } ?? rec.id
            let mins = Int(rec.duration / 60), secs = Int(rec.duration) % 60
            children.append(UIAction(title: when, subtitle: String(format: "%d:%02d", mins, secs), image: UIImage(systemName: "play.circle")) { [weak self] _ in
                self?.recorder.open(rec)
            })
        }
        if children.isEmpty { children.append(UIAction(title: "No recordings on this board", attributes: .disabled) { _ in }) }
        return children
    }

    func showRecordingBar() {
        if let v = objc_getAssociatedObject(self, &recordingBarKey) as? UIViewController { v.view.isHidden = false; view.bringSubviewToFront(v.view); placeRecordingBar(); refreshExtraButtons(); return }
        let host = UIHostingController(rootView: RecordingBar(rec: recorder))
        host.view.backgroundColor = .clear
        host.sizingOptions = .intrinsicContentSize
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let top = host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: recordingBarGap())
        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            top,
        ])
        host.didMove(toParent: self)
        objc_setAssociatedObject(self, &recordingBarKey, host, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &recordingBarTopKey, top, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        refreshExtraButtons()
    }

    /// How far below the safe area's top the recording bar sits: 8 pt under the board's bar (topInset + 8).
    private func recordingBarGap(barsHidden: Bool? = nil) -> CGFloat {
        (barsHidden ?? bar.isHidden) ? 8 : BoardBar.height + 8
    }

    /// Puts the recording bar under the board's bar again (call when the bars are hidden or shown).
    func placeRecordingBar(barsHidden: Bool? = nil) {
        guard let top = objc_getAssociatedObject(self, &recordingBarTopKey) as? NSLayoutConstraint else { return }
        top.constant = recordingBarGap(barsHidden: barsHidden)
    }

    func hideRecordingBar() {
        (objc_getAssociatedObject(self, &recordingBarKey) as? UIViewController)?.view.isHidden = true
        refreshExtraButtons()
    }

    // hooks the board calls

    func recordingDrawingChanged() { existingRecorder?.drawingChanged() }
    func recordingSaved() { existingRecorder?.saved() }
    func recordingTyped(_ id: String, old: String, new: String) { existingRecorder?.typed(id, old: old, new: new) }
    /// A finger tap: true when a recording took it (played from there).
    func recordingTap(_ p: CGPoint) -> Bool { existingRecorder?.tap(at: p) ?? false }
    func recordingBoardClosing() {
        guard let r = existingRecorder else { return }
        if r.mode == .recording { r.stop() }
        r.stopPlaying()
    }
}

/// The pill at the top of the board while recording or playing.
struct RecordingBar: View {
    @Bindable var rec: BoardRecorder

    var body: some View {
        HStack(spacing: 12) {
            switch rec.mode {
            case .recording:
                Circle().fill(.red).frame(width: 10, height: 10).symbolEffect(.pulse)
                Text("Recording " + clock(rec.elapsed)).monospacedDigit()
                Button("Stop") { rec.stop() }.buttonStyle(.borderedProminent).tint(.red)
            case .playing, .paused:
                Button { rec.mode == .playing ? rec.pause() : rec.play() } label: {
                    Image(systemName: rec.mode == .playing ? "pause.fill" : "play.fill").frame(width: 22)
                }
                Text(clock(rec.elapsed)).monospacedDigit().font(.callout)
                Slider(value: Binding(get: { rec.elapsed }, set: { rec.seek($0) }), in: 0...max(1, rec.duration)).frame(width: 240)
                Text(clock(rec.duration)).monospacedDigit().font(.callout).foregroundStyle(.secondary)
                Toggle(isOn: Binding(get: { rec.inStep }, set: { rec.inStep = $0; rec.showInStep() })) { Text("In step").font(.callout) }
                    .toggleStyle(.button)
                Button { rec.stopPlaying() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close the recording")
            case .idle:
                EmptyView()
            }
            if let p = rec.problem { Text(p).font(.footnote).foregroundStyle(.red).frame(maxWidth: 260) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .opacity(rec.mode == .idle && rec.problem == nil ? 0 : 1)
    }

    func clock(_ t: Double) -> String {
        let s = Int(max(0, t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
