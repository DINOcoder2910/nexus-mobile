import AVFoundation
import SwiftUI
import UIKit
import NexusCore

/// Recording a meeting, a class or a filmed class, from any screen (the Recordings screen, the quick page, Siri, the Action button).
/// One recording at a time, app-wide. The sound (or the film) goes to a temporary file while recording and into the recording's folder
/// when it stops, so sync never sends half a file. Then the same device turns it into words (Transcriber) and asks Claude to prepare
/// it (RecordingPrep); the user reviews and accepts on the recording's page (RecordingPage). NexusCore Recordings.swift has the format.
@MainActor
@Observable
final class RecordingService: NSObject {
    static let shared = RecordingService()

    struct Active: Equatable {
        /// "recordings/2026-11-21 1430 Meeting"
        var path: String
        var meta: Recordings.Meta
        var began: Date
        var filming: Bool
        /// Snap pressed while filming: the moments to take a picture of from the film when it stops.
        var marks: [Double] = []
    }

    private(set) var active: Active?
    private(set) var elapsed: Double = 0
    /// What each recording being worked on is doing now ("Turning into words…"), by path.
    private(set) var working: [String: String] = [:]
    /// Why the last step failed, by path (shown on its page with Try again).
    private(set) var problems: [String: String] = [:]
    /// Goes up when a recording changed, so lists read the folder again.
    private(set) var version = 0
    /// Shown as an alert by the screen that asked.
    var problem: String?
    /// The camera sheet for a snap while recording sound.
    var snapping = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var tempURL: URL?
    let camera = FilmCamera()
    @ObservationIgnored private var interruption: NSObjectProtocol?

    private var store: NexusStore { AppServices.store }
    private var root: URL { store.folder }
    var isRecording: Bool { active != nil }

    // MARK: starting and stopping

    /// Starts recording. `film` records video too (a class), with the camera's preview on the recording sheet.
    func start(_ kind: Recordings.Kind, film: Bool = false) async {
        guard active == nil else { return }
        guard store.snapshot.isDataFolder, store.snapshot.readOnlyReason == nil else {
            problem = store.snapshot.readOnlyReason ?? "Set up the Nexus folder first (Settings › Data folder)."
            return
        }
        // the demo records nothing, so it never asks (a system alert the UI tests can't see coming)
        guard RecordingDemo.on || (await RecordingService.askMicrophone()) else {
            problem = "Nexus needs the microphone to record. Allow it in Settings › Nexus."
            return
        }
        if RecordingDemo.on { startDemo(kind, film: film); return }
        let now = Date()
        let id = Recordings.newId()
        let name = Recordings.folderName(started: now, kind: kind, taken: { FileManager.default.fileExists(atPath: self.root.appendingPathComponent(Recordings.dir + "/" + $0).path) })
        let path = Recordings.dir + "/" + name
        var meta = Recordings.Meta(id: id, kind: kind, started: now, device: Device.name)
        if film { meta.video = Recordings.videoFile }
        do {
            try ensureGitignore()
            try writeMeta(path, meta)
        } catch {
            problem = "The recording couldn't start: \(error.localizedDescription)"
            return
        }
        if film {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("film-\(id).mov")
            tempURL = url
            do { try await camera.start(to: url) } catch {
                problem = "The camera couldn't start: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
                return
            }
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(id).m4a")
            tempURL = url
            do {
                try RecordingService.configureSession()
                let r = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000,
                ])
                guard r.record() else { throw RecError("the microphone didn't start") }
                recorder = r
                watchInterruptions()
            } catch {
                problem = "The recording couldn't start: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: root.appendingPathComponent(path))
                return
            }
        }
        active = Active(path: path, meta: meta, began: now, filming: film)
        elapsed = 0
        startTicking()
        store.didWrite(touched: [path])
        version += 1
    }

    /// Stops, moves the sound (and film) into the folder, then turns it into words and asks Claude.
    func stop() async {
        guard var a = active else { return }
        tick?.invalidate(); tick = nil
        if RecordingDemo.on { await stopDemo(a); return }
        a.meta.duration = elapsed
        a.meta.state = "transcribing"
        let folder = root.appendingPathComponent(a.path)
        var failed: String?
        if a.filming {
            UIApplication.shared.isIdleTimerDisabled = false
            await camera.stop()
            if let t = tempURL {
                do {
                    try move(t, to: folder.appendingPathComponent(Recordings.videoFile))
                    try await Self.exportAudio(from: folder.appendingPathComponent(Recordings.videoFile), to: folder.appendingPathComponent(Recordings.audioFile))
                    a.meta.pictures += await Self.pictures(fromFilm: folder.appendingPathComponent(Recordings.videoFile), marks: a.marks, into: folder, existing: a.meta.pictures)
                } catch { failed = "The film couldn't be saved: \(error.localizedDescription)" }
            }
        } else {
            recorder?.stop()
            recorder = nil
            if let o = interruption { NotificationCenter.default.removeObserver(o); interruption = nil }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            if let t = tempURL {
                do { try move(t, to: folder.appendingPathComponent(Recordings.audioFile)) } catch { failed = "The sound couldn't be saved: \(error.localizedDescription)" }
            }
        }
        tempURL = nil
        if let failed { a.meta.state = "failed"; a.meta.problem = failed }
        try? writeMeta(a.path, a.meta)
        active = nil
        store.didWrite(touched: [a.path])
        version += 1
        if failed == nil { await process(a.path) }
    }

    /// Snap: a photo pinned to now (sound), or a moment to take from the film (filming).
    func snap() {
        guard let a = active else { return }
        if a.filming { active?.marks.append(elapsed); return }
        snapping = true
    }

    /// The photo the camera sheet took while recording sound.
    func addPicture(_ image: UIImage, at: Double? = nil) {
        guard var a = active else { return }
        let when = at ?? elapsed
        let file = Recordings.pictureFile(at: when, taken: Set(a.meta.pictures.map(\.file)))
        guard let data = Self.jpeg(image) else { return }
        do {
            try FolderAccess.writeData(root.appendingPathComponent(a.path + "/" + file), data)
            a.meta.pictures.append(.init(file: file, at: when))
            try writeMeta(a.path, a.meta)
            active = a
            store.didWrite(touched: [a.path])
        } catch { problem = "The picture couldn't be saved: \(error.localizedDescription)" }
    }

    // MARK: after recording

    /// Turns the sound into words (when there is no transcript yet), then asks Claude to prepare it (when there is no proposal yet).
    func process(_ path: String) async {
        guard working[path] == nil else { return }
        problems[path] = nil
        let folder = root.appendingPathComponent(path)
        guard var meta = readMeta(path) else { return }
        if !FileManager.default.fileExists(atPath: folder.appendingPathComponent(Recordings.transcriptFile).path) {
            working[path] = "Turning into words…"
            version += 1
            do {
                let t = try await Transcriber.transcribe(folder.appendingPathComponent(meta.audio))
                try FolderAccess.write(folder.appendingPathComponent(Recordings.transcriptFile), t.json.pretty + "\n")
                try FolderAccess.write(folder.appendingPathComponent(Recordings.transcriptText), t.markdown(title: meta.title))
                meta.state = "done"; meta.problem = nil; meta.language = t.language
                try writeMeta(path, meta)
            } catch {
                meta.state = "failed"; meta.problem = "It couldn't be turned into words: \(error.localizedDescription)"
                try? writeMeta(path, meta)
                working[path] = nil
                problems[path] = meta.problem
                store.didWrite(touched: [path]); version += 1
                return
            }
            store.didWrite(touched: [path])
        }
        if !FileManager.default.fileExists(atPath: folder.appendingPathComponent(Recordings.proposalFile).path) {
            working[path] = "Claude is reading it…"
            version += 1
            do {
                let p = try await RecordingPrep.prepare(path: path, meta: meta, store: store)
                try FolderAccess.write(folder.appendingPathComponent(Recordings.proposalFile), p.json.pretty + "\n")
                store.didWrite(touched: [path])
            } catch {
                problems[path] = "Claude couldn't prepare it: \(error.localizedDescription)"
            }
        }
        working[path] = nil
        version += 1
    }

    /// Any recording this device made that stopped part way (the app was closed while it worked): carry on.
    func resume() {
        for e in Recordings.list(root) where e.meta.device == Device.name && working[e.path] == nil && active?.path != e.path {
            switch e.status {
            case .transcribing, .preparing: Task { await process(e.path) }
            case .recording:
                // the app ended while recording: the sound in the temporary file is lost
                var m = e.meta
                m.state = "failed"; m.problem = "Nexus closed while this was recording, so the sound was lost."
                try? writeMeta(e.path, m)
            default: break
            }
        }
    }

    /// Something wrote a recording's files (accepting, a subject changed): the lists read the folder again.
    func changed() { version += 1 }

    // MARK: files

    func readMeta(_ path: String) -> Recordings.Meta? {
        guard let text = try? FolderAccess.read(root.appendingPathComponent(path + "/" + Recordings.metaFile)), let v = try? JSONValue.parse(text) else { return nil }
        return Recordings.Meta(json: v)
    }

    func writeMeta(_ path: String, _ m: Recordings.Meta) throws {
        try FolderAccess.write(root.appendingPathComponent(path + "/" + Recordings.metaFile), m.json.pretty + "\n")
    }

    /// recordings/.gitignore, so videos stay out of the GitHub backup (written once; the user's own lines are kept).
    private func ensureGitignore() throws {
        let url = root.appendingPathComponent(Recordings.gitignorePath)
        let cur = (try? FolderAccess.read(url)) ?? ""
        if cur.contains("*.mov") { return }
        try FolderAccess.write(url, cur.isEmpty ? Recordings.gitignore : cur + (cur.hasSuffix("\n") ? "" : "\n") + Recordings.gitignore)
    }

    private func move(_ from: URL, to: URL) throws {
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: to.path) { try FileManager.default.removeItem(at: to) }
        try FileManager.default.moveItem(at: from, to: to)
    }

    static func jpeg(_ image: UIImage, longest: CGFloat = 2048) -> Data? {
        let s = image.size
        let k = min(1, longest / max(s.width, s.height, 1))
        guard k < 1 else { return image.jpegData(compressionQuality: 0.8) }
        let size = CGSize(width: (s.width * k).rounded(), height: (s.height * k).rounded())
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.8)
    }

    // MARK: sound plumbing

    static func askMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    static func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try s.setActive(true)
    }

    /// A phone call or Siri pauses the recorder; it carries on when the interruption ends.
    private func watchInterruptions() {
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setActive(true)
                _ = self?.recorder?.record()
            }
        }
    }

    private func startTicking() {
        tick = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let a = self.active else { return }
                self.elapsed = self.recorder?.currentTime ?? Date().timeIntervalSince(a.began)
            }
        }
    }

    /// The film's sound as audio.m4a (what the transcriber reads, and what plays on the recording's page).
    static func exportAudio(from film: URL, to out: URL) async throws {
        let asset = AVURLAsset(url: film)
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw RecError("the film's sound couldn't be read") }
        if FileManager.default.fileExists(atPath: out.path) { try FileManager.default.removeItem(at: out) }
        if #available(iOS 18.0, *) {
            try await ex.export(to: out, as: .m4a)
        } else {
            ex.outputURL = out
            ex.outputFileType = .m4a
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in ex.exportAsynchronously { c.resume() } }
            if ex.status != .completed { throw ex.error ?? RecError("the film's sound couldn't be saved") }
        }
    }

    /// Pictures from a film: the moments Snap marked, and the important moments, found where the picture changes and then holds still
    /// (a new slide, the board written on), at most one every 20 s and 40 in all.
    static func pictures(fromFilm film: URL, marks: [Double], into folder: URL, existing: [Recordings.Picture]) async -> [Recordings.Picture] {
        let asset = AVURLAsset(url: film)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let length = (try? await asset.load(.duration).seconds) ?? 0
        var taken = Set(existing.map(\.file))
        var out: [Recordings.Picture] = []
        func save(_ at: Double, note: String?) async {
            guard let cg = try? await gen.image(at: CMTime(seconds: at, preferredTimescale: 600)).image, let data = jpeg(UIImage(cgImage: cg)) else { return }
            let file = Recordings.pictureFile(at: at, taken: taken)
            if (try? FolderAccess.writeData(folder.appendingPathComponent(file), data)) != nil {
                taken.insert(file)
                out.append(.init(file: file, at: at, note: note))
            }
        }
        for m in marks where m <= length { await save(m, note: "Snapped") }
        // the important moments: a small grey picture every 4 s
        gen.maximumSize = CGSize(width: 64, height: 48)
        var samples: [(at: Double, px: [UInt8])] = []
        var t = 2.0
        while t < length {
            if let cg = try? await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image, let px = grey(cg) { samples.append((t, px)) }
            t += 4
        }
        gen.maximumSize = .zero
        var lastKept: [UInt8]?, lastAt = -100.0
        for i in samples.indices {
            let s = samples[i]
            let changed = lastKept.map { diff($0, s.px) > 0.10 } ?? true
            let steady = i + 1 < samples.count ? diff(s.px, samples[i + 1].px) < 0.04 : true
            if changed && steady && s.at - lastAt >= 20 && out.count < 40 && !marks.contains(where: { abs($0 - s.at) < 6 }) {
                await save(s.at, note: nil)
                lastKept = s.px; lastAt = s.at
            }
        }
        return out.sorted { $0.at < $1.at }
    }

    private static func grey(_ cg: CGImage) -> [UInt8]? {
        let w = 32, h = 24
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return px
    }

    /// How different two small pictures are, 0 to 1.
    private static func diff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        var sum = 0
        for i in a.indices { sum += abs(Int(a[i]) - Int(b[i])) }
        return Double(sum) / Double(a.count * 255)
    }

    // MARK: the demo (UI tests and screenshots: no microphone, no Claude)

    private func startDemo(_ kind: Recordings.Kind, film: Bool) {
        let now = Date()
        let name = Recordings.folderName(started: now, kind: kind, taken: { FileManager.default.fileExists(atPath: self.root.appendingPathComponent(Recordings.dir + "/" + $0).path) })
        var meta = Recordings.Meta(id: Recordings.newId(), kind: kind, started: now, device: Device.name)
        if film { meta.video = Recordings.videoFile }
        let path = Recordings.dir + "/" + name
        try? ensureGitignore()
        try? writeMeta(path, meta)
        active = Active(path: path, meta: meta, began: now.addingTimeInterval(-754), filming: film)
        elapsed = 754
        startTicking()
        store.didWrite(touched: [path])
        version += 1
    }

    private func stopDemo(_ a: Active) async {
        var m = a.meta
        m.duration = elapsed
        m.state = "done"
        let folder = root.appendingPathComponent(a.path)
        let t = RecordingDemo.transcript
        try? FolderAccess.write(folder.appendingPathComponent(Recordings.transcriptFile), t.json.pretty + "\n")
        try? FolderAccess.write(folder.appendingPathComponent(Recordings.transcriptText), t.markdown(title: m.title))
        try? writeMeta(a.path, m)
        active = nil
        working[a.path] = "Claude is reading it…"
        version += 1
        try? await Task.sleep(for: .seconds(2))
        try? FolderAccess.write(folder.appendingPathComponent(Recordings.proposalFile), RecordingDemo.meetingProposal.json.pretty + "\n")
        working[a.path] = nil
        store.didWrite(touched: [a.path])
        version += 1
    }
}

struct RecError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// The camera for a filmed class: the back camera and the microphone into one .mov, with a preview layer for the recording sheet.
final class FilmCamera: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var finished: CheckedContinuation<Void, Never>?
    private var configured = false

    func start(to url: URL) async throws {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        guard video else { throw RecError("Nexus needs the camera to film. Allow it in Settings › Nexus.") }
        if !configured {
            session.beginConfiguration()
            // 1080p, sharp enough for the board; .high is 4K on some iPads (an hour would be over the hub's 8 GB a file)
            session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
            guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let camIn = try? AVCaptureDeviceInput(device: cam), session.canAddInput(camIn) else {
                session.commitConfiguration(); throw RecError("there is no camera")
            }
            session.addInput(camIn)
            if let mic = AVCaptureDevice.default(for: .audio), let micIn = try? AVCaptureDeviceInput(device: mic), session.canAddInput(micIn) { session.addInput(micIn) }
            guard session.canAddOutput(output) else { session.commitConfiguration(); throw RecError("the camera can't record") }
            session.addOutput(output)
            // HEVC: about half the size of H.264 for the same picture (an hour's class is 2–3 GB)
            if let conn = output.connection(with: .video), output.availableVideoCodecTypes.contains(.hevc) {
                output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: conn)
            }
            session.commitConfiguration()
            configured = true
        }
        let s = session
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning(); c.resume() }
        }
        output.startRecording(to: url, recordingDelegate: self)
    }

    func stop() async {
        guard output.isRecording else { session.stopRunning(); return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finished = c
            output.stopRecording()
        }
        session.stopRunning()
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        finished?.resume()
        finished = nil
    }
}
