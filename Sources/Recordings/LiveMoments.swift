import AVFoundation
import Speech
import SwiftUI
import NexusCore

/// Class moments (Nov 21): live buttons that pin the moment (Important, Lost me, Exam tip, Homework), pins found by what the teacher
/// says (live while recording a class's sound on iOS 26, and over the transcript afterwards), and a pop-up for each pin found. Each
/// part can be turned off in Settings › Recordings. The pins go into recording.json; Claude says what each moment was when it prepares
/// the recording (nexus docs/data-format.md "Recordings").
enum MomentSettings {
    /// The live buttons shown, a comma list of pin kinds.
    static let buttonsKey = "rec.moments.buttons"
    /// Pin moments by what is said (the phrases, live and afterwards).
    static let autoKey = "rec.moments.auto"
    /// While listening live, also ask Haiku about each minute (catches what the phrases miss; uses the internet and a little of the plan).
    static let claudeKey = "rec.moments.claude"
    /// A pop-up for each pin found, with Snap and Undo.
    static let popupsKey = "rec.moments.popups"
    static let allButtons = Recordings.pinKinds.joined(separator: ",")

    static var buttons: [String] {
        let on = Set((UserDefaults.standard.string(forKey: buttonsKey) ?? allButtons).split(separator: ",").map(String.init))
        return Recordings.pinKinds.filter { on.contains($0) }
    }
    private static func flag(_ k: String) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? true }
    static var auto: Bool { flag(autoKey) }
    static var claude: Bool { flag(claudeKey) }
    static var popups: Bool { flag(popupsKey) }
}

/// A pin found while recording, shown for a few seconds.
struct MomentPopup: Equatable, Identifiable {
    let id = UUID()
    let pin: Recordings.Pin
}

/// Listening along while a class's sound is recorded (iOS 26: Apple's SpeechAnalyzer on this device, offline): every finished line
/// goes to `heard` with its time in the recording. It runs beside the recorder on its own audio engine; if it can't start, the
/// recording carries on without it and the moments are found over the transcript afterwards.
@available(iOS 26.0, *)
final class LiveEars {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var feed: AsyncStream<AnalyzerInput>.Continuation?
    private var reading: Task<Void, Never>?

    func start(offset: Double, heard: @escaping @MainActor (Double, String) -> Void) async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Transcriber.locale) else {
            throw RecError("this device can't listen in \(Transcriber.locale.identifier)")
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        guard let want = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw RecError("no sound format to listen in") }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let (stream, feed) = AsyncStream<AnalyzerInput>.makeStream()
        self.feed = feed
        try await analyzer.start(inputSequence: stream)
        reading = Task {
            do {
                for try await r in transcriber.results {
                    let text = String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    let s = r.range.start.seconds
                    await heard(offset + (s.isFinite ? s : 0), text)
                }
            } catch {}
        }
        let input = engine.inputNode
        let have = input.outputFormat(forBus: 0)
        guard have.sampleRate > 0, let conv = AVAudioConverter(from: have, to: want) else { throw RecError("the microphone can't be listened to") }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: have) { buf, _ in
            let cap = AVAudioFrameCount(Double(buf.frameLength) * want.sampleRate / have.sampleRate) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: want, frameCapacity: cap) else { return }
            var given = false
            var err: NSError?
            _ = conv.convert(to: out, error: &err) { _, status in
                if given { status.pointee = .noDataNow; return nil }
                given = true
                status.pointee = .haveData
                return buf
            }
            if err == nil, out.frameLength > 0 { feed.yield(AnalyzerInput(buffer: out)) }
        }
        engine.prepare()
        try engine.start()
    }

    /// After a phone call or Siri: listen again.
    func resume() { if !engine.isRunning { try? engine.start() } }

    func stop() async {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        feed?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        reading?.cancel()
    }
}

/// Every minute while listening: the new lines to Haiku, which picks the moments the phrases missed.
@MainActor
enum MomentClaude {
    static func ask(_ lines: [Recordings.Segment]) async -> [Recordings.Pin] {
        let text = lines.map { "[\(Recordings.clock($0.start))] \($0.text)" }.joined(separator: "\n")
        let req = ClaudeRequest(model: "haiku", system: Recordings.liveSystem, messages: [ClaudeMessage(role: "user", content: [.text(text)])],
                                maxTokens: 400, cacheSystem: false)
        guard let reply = try? await ClaudeClient.shared.stream(req, onText: { _ in }) else { return [] }
        return Recordings.parseLivePins(reply.text)
    }
}

/// The live buttons while recording: one per kind turned on in Settings (a meeting or a call shows only Important), and how many
/// moments are pinned so far.
struct LiveButtons: View {
    var big: Bool
    @State private var rec = RecordingService.shared
    @AppStorage(MomentSettings.buttonsKey) private var buttons = MomentSettings.allButtons

    var body: some View {
        if let a = rec.active {
            let on = Set(buttons.split(separator: ",").map(String.init))
            let kinds = Recordings.pinKinds.filter { on.contains($0) && (a.meta.kind == .lesson || a.meta.kind == .screen || $0 == "important") }
            VStack(alignment: .leading, spacing: 6) {
                if !kinds.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(kinds, id: \.self) { k in
                            Button { rec.pin(k) } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: Recordings.pinIcon(k)).font(big ? .title3 : .body)
                                    Text(Recordings.pinLabel(k)).font(big ? .subheadline.weight(.medium) : .caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: big ? 64 : 46)
                            }
                            .buttonStyle(.bordered)
                            .tint(Self.tint(k))
                            .accessibilityLabel("Pin: " + Recordings.pinLabel(k))
                            .accessibilityIdentifier("rec-pin-\(k)")
                        }
                    }
                }
                if !a.meta.pins.isEmpty {
                    Text(Self.count(a.meta.pins)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("rec-pin-count")
                }
            }
        }
    }

    static func tint(_ kind: String) -> Color {
        switch kind {
        case "lost": return .orange
        case "exam": return .purple
        case "homework": return .blue
        default: return Theme.accent
        }
    }

    /// "3 moments pinned (1 found by what was said)".
    static func count(_ pins: [Recordings.Pin]) -> String {
        let auto = pins.filter { $0.by == "auto" }.count
        return (pins.count == 1 ? "1 moment pinned" : "\(pins.count) moments pinned") + (auto > 0 ? " (\(auto) found by what was said)" : "")
    }
}

/// The pop-up for a pin found by what was said: what was heard, Snap (the board, when not filming) and Undo. Gone after a few seconds.
struct MomentPopupView: View {
    @State private var rec = RecordingService.shared

    var body: some View {
        if let p = rec.popup {
            HStack(spacing: 12) {
                Image(systemName: Recordings.pinIcon(p.pin.kind)).font(.title3).foregroundStyle(LiveButtons.tint(p.pin.kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pinned: " + Recordings.pinLabel(p.pin.kind)).font(.subheadline.weight(.semibold))
                    if let s = p.pin.said { Text("“\(s)”").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 4)
                if rec.active?.filming == false {
                    Button { rec.snap() } label: {
                        Image(systemName: "camera.fill").font(.subheadline).frame(width: 34, height: 34).background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Snap the board")
                }
                Button("Undo") { rec.unpin(p.pin) }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("rec-popup-undo")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .frame(maxWidth: 520)
            .padding(.horizontal, 16).padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("rec-popup")
        }
    }
}

/// Settings › Recordings: the live buttons, pins by what is said, Haiku listening along, pop-ups.
struct RecordingSettings: View {
    @AppStorage(MomentSettings.buttonsKey) private var buttons = MomentSettings.allButtons
    @AppStorage(MomentSettings.autoKey) private var auto = true
    @AppStorage(MomentSettings.claudeKey) private var claude = true
    @AppStorage(MomentSettings.popupsKey) private var popups = true

    var body: some View {
        Section {
            ForEach(Recordings.pinKinds, id: \.self) { k in
                Toggle(isOn: Binding(get: { on.contains(k) }, set: { set(k, $0) })) {
                    Label(Recordings.pinLabel(k), systemImage: Recordings.pinIcon(k))
                }
                .accessibilityIdentifier("rec-setting-\(k)")
            }
        } header: { Text("Recordings: live buttons") } footer: {
            Text("While a class records, each button pins that moment. Claude says what was happening at each one, and explains the parts you pinned as Lost me.")
        }
        Section {
            Toggle("Pin moments by what's said", isOn: $auto).accessibilityIdentifier("rec-setting-auto")
            if auto {
                Toggle("Claude listens along (Haiku)", isOn: $claude)
            }
            Toggle("Pop-ups while recording", isOn: $popups).accessibilityIdentifier("rec-setting-popups")
        } footer: {
            Text("Nexus listens for things like “this comes up every year”, homework and “write this down”, and pins them" + (auto && claude ? "; Haiku catches the ones said another way (it needs the internet)" : "") + ". Filming, it takes a picture at each. A pop-up shows each one found, with Snap and Undo.")
        }
    }

    private var on: Set<String> { Set(buttons.split(separator: ",").map(String.init)) }
    private func set(_ k: String, _ v: Bool) {
        var s = on
        if v { s.insert(k) } else { s.remove(k) }
        buttons = Recordings.pinKinds.filter { s.contains($0) }.joined(separator: ",")
    }
}
