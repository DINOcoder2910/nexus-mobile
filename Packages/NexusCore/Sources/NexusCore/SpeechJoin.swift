import Foundation

/// What you said to the tutor, kept whole across pauses (Nov 16 fix). Apple's speech recognition (iOS 17 and later, on the device)
/// starts its transcription over after a pause of a few seconds: each result then holds only what was said since the pause, so
/// showing the latest result lost everything before it. This keeps each finished stretch and adds the stretch being said now.
///
/// A new stretch is known by any of: the recogniser marking the end of the last one (a result with `speechRecognitionMetadata`, or a
/// final one); the new result starting later in the audio than the stretch being kept (its first word's timestamp); or, when neither
/// comes, the text itself: a result under a third of the stretch so far, or shorter and not beginning with one of its first three
/// words (the recogniser revises a stretch as it goes, but a revision keeps its start and rarely shrinks). When unsure it keeps
/// both: a repeated word in the question is better than a lost sentence.
public struct SpeechJoin: Equatable {
    /// The finished stretches, oldest first.
    public private(set) var done: [String] = []
    /// The stretch being said now (the latest result's text).
    public private(set) var current = ""
    /// Where `current` starts in the audio, in seconds (nil when the recogniser didn't say).
    private var currentStart: Double?

    public init() {}

    /// Everything heard so far, one stretch after another.
    public var text: String { (done + [current]).filter { !$0.isEmpty }.joined(separator: " ") }

    /// One result from the recogniser. start: its first word's place in the audio, in seconds (nil or 0 when unknown); ended: the
    /// recogniser says this stretch is over (metadata, a final result). Returns the whole text.
    @discardableResult
    public mutating func update(_ result: String, start: Double? = nil, ended: Bool = false) -> String {
        let t = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = start.flatMap { $0 > 0 ? $0 : nil }
        if !t.isEmpty, !current.isEmpty, Self.startedOver(old: current, oldStart: currentStart, new: t, newStart: s) { close() }
        if !t.isEmpty {
            if current.isEmpty { currentStart = s }
            current = t
        }
        if ended { close() }
        return text
    }

    /// The stretch being said is over (the recogniser stopped, or is being restarted): it is kept as it is.
    public mutating func close() {
        if !current.isEmpty { done.append(current) }
        current = ""
        currentStart = nil
    }

    /// Whether `new` is a new stretch rather than the stretch `old` revised.
    static func startedOver(old: String, oldStart: Double?, new: String, newStart: Double?) -> Bool {
        if let a = oldStart, let b = newStart { return b > a + 0.5 }
        let o = words(old), n = words(new)
        guard let first = n.first, !o.isEmpty else { return false }
        if new.count >= old.count { return false }
        if new.count * 3 < old.count, o.count >= 4 { return true } // (a stretch's revisions don't drop two thirds of it)
        return !o.prefix(3).contains(first)
    }

    /// Lower-case words without punctuation (the recogniser adds and moves punctuation as it goes).
    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" }).map(String.init)
    }
}
