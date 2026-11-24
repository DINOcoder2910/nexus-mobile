import AVFoundation
import SwiftUI
import NexusCore

/// Spanish › Oral on the iPhone and iPad: the laptop's oral files (`<workstream>/study/spanish/oral/`, nexus docs/guide.md "Oral
/// practice") read for the Oral page, and the two things the phone adds: a recording (a session with the tutor, an oral the teacher
/// marked), and a listening test read line by line. The voice models that hear them (Whisper and the two ears) run on the laptop's
/// graphics card, so the phone writes them down as waiting (`waiting: hear` in oral.yaml, a take under listening-test/phone/) and the
/// laptop's Oral page hears them the next time it is open. The pure half is NexusCore SpanishOral.swift.
@MainActor
@Observable
final class OralLibrary {
    static let shared = OralLibrary()

    /// One subject's oral files, as read.
    struct Home {
        var orals: [SpanishOral.Oral] = []
        var rows: [SpanishOral.Row] = []
        var images: [SpanishOral.Image] = []
        var settings = SpanishOral.Settings()
        /// Kept listening test results, newest first.
        var tests: [SpanishOral.TestResult] = []
        /// Takes read on a phone, newest first (heard ones too, with their result's file).
        var takes: [SpanishOral.Take] = []
        func oral(_ id: String) -> SpanishOral.Oral? { orals.first { $0.id == id } }
        var waiting: Int { orals.filter { $0.waiting == "hear" }.count + takes.filter { $0.heard.isEmpty }.count }
    }

    private(set) var homes: [String: Home] = [:]
    /// A save that could not be made (shown as an alert).
    var problem: String?
    @ObservationIgnored private var stamps: [String: String] = [:]

    func home(_ wsId: String) -> Home { homes[wsId] ?? Home() }
    func canWrite(_ store: NexusStore) -> Bool { store.snapshot.isDataFolder && store.snapshot.readOnlyReason == nil }

    /// `classes/spanish-ab/study/spanish/oral`
    static func base(_ w: Workstream) -> String { w.folder + "/" + SpanishOral.dir }
    func url(_ store: NexusStore, _ w: Workstream, _ rel: String) -> URL { store.folder.appendingPathComponent(Self.base(w) + "/" + rel) }

    // MARK: reading

    func refreshIfChanged(_ store: NexusStore, _ w: Workstream) {
        let fp = SpanishLibrary.fingerprint(store.folder, w)
        if fp != stamps[w.id] || homes[w.id] == nil { load(store, w); stamps[w.id] = fp }
    }

    func load(_ store: NexusStore, _ w: Workstream) {
        let fm = FileManager.default
        let dir = store.folder.appendingPathComponent(Self.base(w), isDirectory: true)
        func read(_ rel: String) -> String? {
            let u = dir.appendingPathComponent(rel)
            return fm.fileExists(atPath: u.path) ? try? FolderAccess.read(u) : nil
        }
        func names(_ rel: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir.appendingPathComponent(rel).path)) ?? []).filter { !$0.hasPrefix(".") && !SyncPaths.isConflictCopy($0) }
        }
        var h = Home()
        h.settings = SpanishOral.parseSettings(read("settings.yaml"))
        h.images = SpanishOral.parseImages(read("images.yaml"))
        h.orals = names("orals").compactMap { id in read("orals/\(id)/oral.yaml").flatMap { SpanishOral.parseOral($0, id: id) } }
        h.rows = SpanishOral.rows(h.orals, settings: h.settings, images: h.images)
        h.tests = names("listening-test").filter { $0.lowercased().hasSuffix(".yaml") }.sorted(by: >)
            .compactMap { f in read("listening-test/\(f)").flatMap { SpanishOral.parseTest($0, file: f) } }
        h.takes = names("listening-test/phone").sorted(by: >).compactMap { s in read("listening-test/phone/\(s)/take.yaml").flatMap { SpanishOral.parseTake($0, stamp: s) } }
        homes[w.id] = h
    }

    // MARK: adding a recording

    /// Copies the recording into orals/<id>/ and writes its oral.yaml, waiting for the laptop to hear it. Returns the oral's id.
    @discardableResult
    func add(_ store: NexusStore, _ w: Workstream, _ r: SpanishOral.NewRecording, audio: URL, day: Date) throws -> String {
        guard canWrite(store) else { throw ClaudeError(store.snapshot.readOnlyReason ?? "The data folder is read-only.") }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let started = Days.iso(day) + String(format: "T%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        var id = SpanishOral.oralId(started)
        let taken = Set(home(w.id).orals.map(\.id)).union((try? FileManager.default.contentsOfDirectory(atPath: url(store, w, "orals").path)) ?? [])
        while taken.contains(id) { id += "b" }
        let ext = audio.pathExtension.isEmpty ? "m4a" : audio.pathExtension.lowercased()
        let file = "recording.\(ext)"
        let access = audio.startAccessingSecurityScopedResource()
        defer { if access { audio.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: audio)
        try FolderAccess.writeData(url(store, w, "orals/\(id)/\(file)"), data)
        try FolderAccess.write(url(store, w, "orals/\(id)/oral.yaml"), SpanishOral.newOral(r, id: id, started: started, recording: file, device: Device.name))
        store.didWrite(touched: [Self.base(w) + "/orals/\(id)"])
        load(store, w)
        return id
    }

    // MARK: the listening test

    /// Writes a take: each line's recording beside take.yaml, for the laptop's ears.
    func saveTake(_ store: NexusStore, _ w: Workstream, _ lines: [(id: String, file: URL)]) throws {
        guard canWrite(store) else { throw ClaudeError(store.snapshot.readOnlyReason ?? "The data folder is read-only.") }
        let now = Date()
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        var stamp = f.string(from: now)
        while FileManager.default.fileExists(atPath: url(store, w, "listening-test/phone/\(stamp)").path) { stamp += "b" }
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let rel = "listening-test/phone/\(stamp)"
        for l in lines { try FolderAccess.writeData(url(store, w, "\(rel)/\(l.id).m4a"), try Data(contentsOf: l.file)) }
        try FolderAccess.write(url(store, w, "\(rel)/take.yaml"), SpanishOral.takeYaml(at: f.string(from: now), device: Device.name, lines: lines.map(\.id)))
        store.didWrite(touched: [Self.base(w) + "/" + rel])
        load(store, w)
    }
}

/// The microphone for the Oral page: one recording at a time, AAC at 16 kHz mono (what the laptop's ears hear), into a temporary file.
/// The UI check (-NexusSpanishDemo) records nothing and asks for no microphone: a stop gives a small file of silence-shaped bytes.
@MainActor
@Observable
final class OralMic {
    private(set) var on = false
    private(set) var seconds: Double = 0
    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private var began = Date()

    /// Starts; nil when it started, else why not.
    func start() async -> String? {
        guard !on else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oral-\(UUID().uuidString).m4a")
        file = url
        if !SpanishDemo.active {
            guard await RecordingService.askMicrophone() else { return "Nexus needs the microphone to record. Allow it in Settings › Nexus." }
            guard !RecordingService.shared.isRecording else { return "A recording is already running (Recordings): stop it first." }
            do {
                try RecordingService.configureSession()
                let r = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000])
                guard r.record() else { return "The microphone didn't start." }
                recorder = r
            } catch { return "The microphone didn't start: \(error.localizedDescription)" }
        }
        on = true
        seconds = 0
        began = Date()
        tick = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in if let s = self, s.on { s.seconds = Date().timeIntervalSince(s.began) } }
        }
        return nil
    }

    /// Stops; the recording's file.
    func stop() -> URL? {
        guard on else { return nil }
        on = false
        tick?.invalidate(); tick = nil
        if SpanishDemo.active {
            if let file { try? Data(repeating: 0, count: 2048).write(to: file) }
        } else {
            recorder?.stop(); recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        return file
    }

    func cancel() {
        if let u = stop() { try? FileManager.default.removeItem(at: u) }
    }

    static func time(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

/// Playing an oral's recording on its page.
@MainActor
@Observable
final class OralPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var playing = false
    @ObservationIgnored private var player: AVAudioPlayer?

    func toggle(_ url: URL) -> String? {
        if playing { player?.pause(); playing = false; return nil }
        do {
            if player?.url != url {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                player = try AVAudioPlayer(contentsOf: url)
                player?.delegate = self
            }
            playing = player?.play() ?? false
            return playing ? nil : "The recording couldn't play."
        } catch { return "The recording couldn't play: \(error.localizedDescription)" }
    }

    func stop() { player?.stop(); playing = false }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playing = false }
    }
}
