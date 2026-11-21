import AVFoundation
import Speech
import NexusCore
import UIKit

/// Sound into words, on this device, free and offline. iOS 26 and later: Apple's SpeechTranscriber (SpeechAnalyzer), made for long
/// recordings and conversations; its language model is downloaded by iOS once. Earlier iOS: the older on-device recogniser.
enum Transcriber {
    /// The language to listen for: the device's own when it is English or Spanish, else English.
    static var locale: Locale {
        let id = Locale.current.identifier
        return id.hasPrefix("en") || id.hasPrefix("es") ? Locale.current : Locale(identifier: "en-US")
    }

    static func transcribe(_ audio: URL, locale: Locale = Transcriber.locale) async throws -> Recordings.Transcript {
        guard FileManager.default.fileExists(atPath: audio.path) else { throw RecError("there is no sound file") }
        if #available(iOS 26.0, *) {
            return try await analyzer(audio, locale)
        }
        return try await older(audio, locale)
    }

    // MARK: iOS 26: SpeechAnalyzer

    @available(iOS 26.0, *)
    private static func analyzer(_ url: URL, _ want: Locale) async throws -> Recordings.Transcript {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: want) else {
            throw RecError("this device can't transcribe \(want.identifier)")
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await install.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        let collect = Task { () throws -> [Recordings.Segment] in
            var out: [Recordings.Segment] = []
            for try await r in transcriber.results {
                let text = String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = r.range.start.seconds, end = r.range.end.seconds
                out.append(.init(start: start.isFinite ? start : 0, end: end.isFinite ? end : 0, text: text))
            }
            return out
        }
        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let segments = try await collect.value
        return Recordings.Transcript(language: locale.identifier, engine: "apple-speechtranscriber", segments: segments)
    }

    // MARK: earlier iOS: the on-device recogniser

    private static func older(_ url: URL, _ locale: Locale) async throws -> Recordings.Transcript {
        let ok: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard ok == .authorized else { throw RecError("Nexus needs speech recognition: allow it in Settings › Nexus") }
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else { throw RecError("speech recognition isn't available") }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        req.addsPunctuation = true
        if r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        let words: [SFTranscriptionSegment] = try await withCheckedThrowingContinuation { c in
            var done = false
            _ = r.recognitionTask(with: req) { result, error in
                guard !done else { return }
                if let error { done = true; c.resume(throwing: error); return }
                if let result, result.isFinal { done = true; c.resume(returning: result.bestTranscription.segments) }
            }
        }
        // words into stretches: a new one after a pause of 0.8 s or at the end of a sentence
        var out: [Recordings.Segment] = []
        for w in words {
            let start = w.timestamp, end = w.timestamp + w.duration
            if var last = out.last, start - last.end < 0.8, !(last.text.hasSuffix(".") || last.text.hasSuffix("?") || last.text.hasSuffix("!")) {
                last.text += " " + w.substring
                last.end = end
                out[out.count - 1] = last
            } else {
                out.append(.init(start: start, end: end, text: w.substring))
            }
        }
        return Recordings.Transcript(language: locale.identifier, engine: "apple-sfspeech", segments: out)
    }
}

/// Asking Claude to prepare a recording: the transcript, the pictures (at most 8), the subjects and the calendar event at that time.
@MainActor
enum RecordingPrep {
    static let model = "sonnet"

    static func prepare(path: String, meta: Recordings.Meta, store: NexusStore) async throws -> Recordings.Proposal {
        let folder = store.folder.appendingPathComponent(path)
        guard let text = try? FolderAccess.read(folder.appendingPathComponent(Recordings.transcriptFile)), let v = try? JSONValue.parse(text),
              let transcript = Recordings.Transcript(json: v) else { throw RecError("the transcript can't be read") }
        let subjects = store.snapshot.workstreams.values.filter { !$0.parked && !$0.finished }.sorted { $0.name < $1.name }
            .map { Recordings.Subject(id: $0.id, name: $0.name, kind: $0.kind) }
        let event = eventAt(meta)
        let pics = pick(meta.pictures, 8)
        var blocks: [ClaudeBlock] = []
        for p in pics {
            if let img = UIImage(contentsOfFile: folder.appendingPathComponent(p.file).path), let data = RecordingService.jpeg(img, longest: 1200) {
                blocks.append(.text("Picture at \(Recordings.clock(p.at)):"))
                blocks.append(.image(mediaType: "image/jpeg", base64: data.base64EncodedString()))
            }
        }
        let prompt = Recordings.prompt(meta: meta, transcript: transcript, subjects: subjects, event: event, today: store.today, pictures: pics)
        let req = ClaudeRequest(model: model, system: Recordings.system, messages: [ClaudeMessage(role: "user", content: blocks + [.text(prompt)])],
                                maxTokens: 8000, cacheSystem: false)
        let reply = try await ClaudeClient.shared.stream(req) { _ in }
        guard var p = Recordings.parseReply(reply.text, subjects: Set(subjects.map(\.id))) else {
            throw RecError("its answer couldn't be read")
        }
        p.model = reply.model
        p.made = Recordings.iso(Date())
        return p
    }

    /// The calendar event that was on when the recording started ("Econ IA check-in, 14:00–14:30").
    static func eventAt(_ meta: Recordings.Meta) -> String? {
        guard let d = meta.startedDate else { return nil }
        let cal = AppServices.calendar
        guard cal.canRead else { return nil }
        let day = Recordings.localDay(d)
        let near = cal.events(on: day).filter { !$0.allDay && $0.start.addingTimeInterval(-15 * 60) <= d && $0.end > d }
        return near.first.map { "\($0.title), \($0.timeText)" + ($0.location.map { ", \($0)" } ?? "") }
    }

    /// At most `n` pictures, spread over the recording.
    static func pick(_ all: [Recordings.Picture], _ n: Int) -> [Recordings.Picture] {
        guard all.count > n else { return all }
        return (0..<n).map { all[$0 * all.count / n] }
    }
}
