import AVFoundation
import NaturalLanguage
import Speech
import UIKit

/// The iPad's voices: Apple's, free and offline. Settings › Tutor › Voice keeps a voice for English and one for Spanish (any accent
/// the iPad has), and a speed. The tutor and Read aloud both speak through `Speaker.shared`, which picks the voice by the language of
/// each sentence, so a Spanish example inside an English answer is said in Spanish.
enum Voices {
    static let englishKey = "voiceEnglish", spanishKey = "voiceSpanish", rateKey = "voiceRate", listenKey = "tutorListen"

    struct Option: Identifiable, Hashable {
        var id: String
        var name: String
        var language: String
        /// "United States", "Mexico"...
        var accent: String
        /// Default, Enhanced, Premium.
        var quality: String
        var rank: Int
    }

    /// Every voice the iPad has for a language ("en", "es"), best first within each accent; novelty and eloquence voices left out.
    static func options(_ lang: String) -> [Option] {
        let here = Locale.current
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(lang + "-") || $0.language == lang }.compactMap { v in
            if v.voiceTraits.contains(.isNoveltyVoice) { return nil }
            if v.identifier.contains("eloquence") { return nil }
            let region = v.language.split(separator: "-").dropFirst().first.map(String.init) ?? ""
            let accent = here.localizedString(forRegionCode: region) ?? region
            let q: (String, Int) = v.quality == .premium ? ("Premium", 3) : v.quality == .enhanced ? ("Enhanced", 2) : ("Default", 1)
            return Option(id: v.identifier, name: v.name, language: v.language, accent: accent, quality: q.0, rank: q.1)
        }.sorted { ($0.accent, -$0.rank, $0.name) < ($1.accent, -$1.rank, $1.name) }
    }

    /// The chosen voice for a language, or the iPad's best for it (US English, Spain's Spanish first).
    static func voice(_ lang: String) -> AVSpeechSynthesisVoice? {
        let key = lang == "es" ? spanishKey : englishKey
        if let id = UserDefaults.standard.string(forKey: key), let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        let all = options(lang)
        let want = lang == "es" ? "es-ES" : "en-US"
        let best = all.filter { $0.language == want }.max { $0.rank < $1.rank } ?? all.max { $0.rank < $1.rank }
        return best.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) } ?? AVSpeechSynthesisVoice(language: want)
    }

    /// 0.35 (slow) ... 0.65 (fast); Apple's normal is 0.5.
    static var rate: Float {
        get { let r = UserDefaults.standard.float(forKey: rateKey); return r > 0 ? r : AVSpeechUtteranceDefaultSpeechRate }
        set { UserDefaults.standard.set(newValue, forKey: rateKey) }
    }

    /// "en" or "es" for a sentence (English when unsure).
    static func language(of text: String) -> String {
        let r = NLLanguageRecognizer()
        r.languageConstraints = [.english, .spanish]
        r.processString(text)
        guard let (lang, p) = r.languageHypotheses(withMaximum: 1).first else { return "en" }
        return lang == .spanish && p > 0.7 ? "es" : "en"
    }

    /// The language the tutor listens in: the iPad's own, unless Settings says otherwise.
    static var listenLocale: Locale {
        if let id = UserDefaults.standard.string(forKey: listenKey), !id.isEmpty { return Locale(identifier: id) }
        return Locale.current
    }
}

/// Says sentences one after another. `say` returns once that sentence starts being spoken (so a drawing goes with it); `onWord` gives
/// the range of the word being said (Read aloud highlights it).
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Speaker()
    let synth = AVSpeechSynthesizer()
    private var started: [ObjectIdentifier: CheckedContinuation<Void, Never>] = [:]
    private var finished: [CheckedContinuation<Void, Never>] = []
    var onWord: ((NSRange, AVSpeechUtterance) -> Void)?
    var onFinish: ((AVSpeechUtterance) -> Void)?

    override init() {
        super.init()
        synth.delegate = self
        synth.usesApplicationAudioSession = true
    }

    var speaking: Bool { synth.isSpeaking }

    func utterance(_ text: String, lang: String? = nil) -> AVSpeechUtterance {
        let u = AVSpeechUtterance(string: text)
        u.voice = Voices.voice(lang ?? Voices.language(of: text))
        u.rate = Voices.rate
        u.postUtteranceDelay = 0.05
        return u
    }

    /// Queues a sentence; returns when it starts.
    func say(_ text: String, lang: String? = nil) async {
        Audio.prepareForSpeaking()
        let u = utterance(text, lang: lang)
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            started[ObjectIdentifier(u)] = c
            synth.speak(u)
        }
    }

    /// Speaks a whole text now (Read aloud), replacing whatever was being said.
    @discardableResult
    func read(_ text: String, lang: String? = nil) -> AVSpeechUtterance {
        stop()
        Audio.prepareForSpeaking()
        let u = utterance(text, lang: lang)
        synth.speak(u)
        return u
    }

    /// Returns when nothing is left to say.
    func untilDone() async {
        guard synth.isSpeaking else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in finished.append(c) }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        release()
    }

    private func release() {
        for c in started.values { c.resume() }
        started = [:]
        for c in finished { c.resume() }
        finished = []
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        let key = ObjectIdentifier(u)
        Task { @MainActor in self.started.removeValue(forKey: key)?.resume() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance u: AVSpeechUtterance) {
        Task { @MainActor in self.onWord?(range, u) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let key = ObjectIdentifier(u)
        Task { @MainActor in
            self.started.removeValue(forKey: key)?.resume()
            self.onFinish?(u)
            if !self.synth.isSpeaking { for c in self.finished { c.resume() }; self.finished = [] }
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        let key = ObjectIdentifier(u)
        Task { @MainActor in
            self.started.removeValue(forKey: key)?.resume()
            self.onFinish?(u)
            if !self.synth.isSpeaking { for c in self.finished { c.resume() }; self.finished = [] }
        }
    }
}

/// The audio session, shared by speaking, listening and recording a class: play and record at once, through the speaker.
enum Audio {
    static func prepareForSpeaking() { configure() }

    static func configure() {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playAndRecord {
            try? s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth, .mixWithOthers])
        }
        try? s.setActive(true)
    }

    static func askMicrophone() async -> Bool {
        await withCheckedContinuation { c in AVAudioApplication.requestRecordPermission { c.resume(returning: $0) } }
    }
}

/// Hearing the question: Apple's speech recognition on the iPad (offline when the iPad has the language), while the button is held.
@MainActor
final class Listener {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var best = ""
    private var done: CheckedContinuation<String, Never>?
    var onPartial: ((String) -> Void)?

    static func ask() async -> String? {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speech == .authorized else { return "Nexus isn't allowed to use speech recognition. Turn it on in iPad Settings › Nexus." }
        guard await Audio.askMicrophone() else { return "Nexus isn't allowed to use the microphone. Turn it on in iPad Settings › Nexus." }
        return nil
    }

    /// Starts listening; nil, or why it can't.
    func start() -> String? {
        best = ""
        guard let r = SFSpeechRecognizer(locale: Voices.listenLocale) ?? SFSpeechRecognizer(), r.isAvailable else {
            return "Speech recognition isn't available right now."
        }
        recognizer = r
        Audio.configure()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if r.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        request = req
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return "No microphone found." }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in req.append(buf) }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); return "The microphone couldn't start: \(error.localizedDescription)" }
        task = r.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true || error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text, !text.isEmpty { self.best = text; self.onPartial?(text) }
                if final { self.finish() }
            }
        }
        return nil
    }

    /// Stops and returns what was heard (waits briefly for the last words).
    func stop() async -> String {
        guard request != nil else { return best }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            done = c
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.finish()
            }
        }
    }

    func cancel() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        task?.cancel()
        finish()
    }

    private func finish() {
        task = nil
        request = nil
        if let d = done { done = nil; d.resume(returning: best) }
    }
}
