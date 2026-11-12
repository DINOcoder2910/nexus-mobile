import Foundation

/// The tutor's reply, read as it streams in, the same as the laptop's `renderer/src/tutor/reply.js`. Claude writes what it says as plain
/// prose and puts each drawing step on its own line as `<step>{json}</step>`, right after the sentence it goes with. `TutorReader` takes
/// the text in any pieces (`push`) and hands back events in order: a sentence to say, or a clean step to draw. `end()` flushes what is
/// left. A step that doesn't parse or that `TutorSteps.check` refuses is dropped and listed in `problems`.
///
/// Sentences split after . ! ? (and a closing quote or bracket) followed by a space, not after an abbreviation, an initial or a number;
/// a long run without one is cut at a comma or a space so the voice can start early. Markdown that slips in is taken out: the voice
/// would read it aloud.
public final class TutorReader {
    static let abbreviations: Set<String> = ["e.g", "i.e", "etc", "vs", "cf", "approx", "fig", "eq", "no", "mr", "mrs", "ms", "dr", "st", "p", "pp",
                                             "ca", "resp", "incl", "min", "max", "sec", "mol", "conc", "aq", "temp"]
    static let maxSentence = 220

    public private(set) var problems: [(problem: String, text: String)] = []
    public private(set) var sentences = 0
    var buf = ""
    var prose = ""
    var out: [TutorEvent] = []

    public init() {}

    /// What the voice should say for one piece of prose.
    public static func speakable(_ s: String) -> String {
        var t = s
        func re(_ p: String, _ with: String, _ opts: NSRegularExpression.Options = []) {
            guard let r = try? NSRegularExpression(pattern: p, options: opts) else { return }
            t = r.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: with)
        }
        re("```[\\s\\S]*?```", " ")
        re("\\*\\*|__|`", "")
        re("(^|\\s)[*_](\\S[^*_]*?)[*_](?=[\\s.,;:!?]|$)", "$1$2")
        re("^\\s{0,3}#{1,6}\\s+", "", .anchorsMatchLines)
        re("^\\s*(?:[-*•]|\\d+[.)])\\s+", "", .anchorsMatchLines)
        re("\\$+", "")
        re("\\[([^\\]]+)\\]\\([^)]*\\)", "$1")
        re("\\s+", " ")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let endRe = try! NSRegularExpression(pattern: "[.!?…]+[\"'”’)\\]]*(?=\\s)")

    /// The UTF-16 offset just past the end of the first full sentence in `s`, or -1. `final`: the text is complete, so its end counts too.
    public static func sentenceEnd(_ s: String, final: Bool = false) -> Int {
        let ns = s as NSString
        for m in endRe.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let end = m.range.location + m.range.length
            let matched = ns.substring(with: m.range)
            if matched == "." {
                let before = ns.substring(to: m.range.location)
                let word: String = {
                    guard let r = before.range(of: "[A-Za-z.]+$", options: .regularExpression) else { return "" }
                    return String(before[r])
                }()
                var key = word.lowercased()
                if key.hasSuffix(".") { key.removeLast() }
                if abbreviations.contains(key) { continue } // e.g. / Fig. / approx.
                let last2 = String(before.suffix(2))
                if word.range(of: "^[A-Z]$", options: .regularExpression) != nil,
                   last2.range(of: "\\s[A-Z]$|^[A-Z]$", options: .regularExpression) != nil { continue } // an initial: "J. Smith"
                if before.range(of: "\\d$", options: .regularExpression) != nil,
                   ns.substring(from: end).range(of: "^\\s+\\d", options: .regularExpression) != nil { continue } // "3. 4" in a list
            }
            return end
        }
        if ns.length > maxSentence {
            func lastIndex(_ needle: String, from: Int) -> Int {
                let upTo = min(ns.length, from + needle.utf16.count)
                let r = ns.range(of: needle, options: .backwards, range: NSRange(location: 0, length: upTo))
                return r.location == NSNotFound ? -1 : r.location
            }
            let cut = max(lastIndex(", ", from: maxSentence), lastIndex("; ", from: maxSentence))
            return cut > 60 ? cut + 1 : max(lastIndex(" ", from: maxSentence), 1)
        }
        return final && !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ns.length : -1
    }

    func say(_ text: String) {
        let t = TutorReader.speakable(text)
        guard t.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) }) else { return }
        out.append(.say(t, n: sentences)); sentences += 1
    }

    func flushSentences(_ final: Bool) {
        while true {
            let e = TutorReader.sentenceEnd(prose, final: final)
            if e < 0 { break }
            let ns = prose as NSString
            say(ns.substring(to: e))
            prose = ns.substring(from: e)
            if prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { prose = ""; break }
        }
    }

    func tag(_ body: String) {
        guard let v = try? JSONValue.parse(body.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            problems.append(("not JSON", String(body.prefix(200)))); return
        }
        let r = TutorSteps.check(v)
        if let s = r.step { out.append(.step(s)) } else { problems.append((r.problem ?? "refused", String(body.prefix(200)))) }
    }

    static let tagRe = try! NSRegularExpression(pattern: "<step>([\\s\\S]*?)</step>")
    static let openRe = try! NSRegularExpression(pattern: "<(?:s(?:t(?:e(?:p)?)?)?)?$")
    static let sentenceDone = try! NSRegularExpression(pattern: "(?:[.!?…][\"'”’)\\]]*\\s*|\\n\\s*)$")

    /// More of the reply -> the events it completes.
    public func push(_ piece: String) -> [TutorEvent] {
        buf += piece
        while true {
            let ns = buf as NSString
            if let m = TutorReader.tagRe.firstMatch(in: buf, range: NSRange(location: 0, length: ns.length)) {
                // a step on its own line, or after a full stop, ends the sentence before it (it is drawn while that one is said)
                prose += ns.substring(to: m.range.location)
                let pn = prose as NSString
                let done = !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && TutorReader.sentenceDone.firstMatch(in: prose, range: NSRange(location: 0, length: pn.length)) != nil
                flushSentences(done)
                tag(ns.substring(with: m.range(at: 1)))
                buf = ns.substring(from: m.range.location + m.range.length)
                continue
            }
            // no whole tag: keep back an open one (or the start of one) and read the prose before it
            let open = ns.range(of: "<step>")
            let cut: Int
            if open.location != NSNotFound { cut = open.location }
            else if let m = TutorReader.openRe.firstMatch(in: buf, range: NSRange(location: 0, length: ns.length)) { cut = m.range.location }
            else { cut = ns.length }
            prose += ns.substring(to: cut)
            buf = ns.substring(from: cut)
            flushSentences(false)
            break
        }
        defer { out = [] }
        return out
    }

    /// The reply is complete: the rest of it. A step cut off by the end is dropped.
    public func end() -> [TutorEvent] {
        if !buf.isEmpty {
            if buf.hasPrefix("<step>") { problems.append(("cut off", String(buf.prefix(200)))) } else { prose += buf }
            buf = ""
        }
        flushSentences(true)
        if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { say(prose) }
        prose = ""
        defer { out = [] }
        return out
    }

    /// A whole reply at once.
    public static func read(_ text: String) -> (events: [TutorEvent], said: [String], steps: [TutorStep], problems: [(problem: String, text: String)]) {
        let r = TutorReader()
        let events = r.push(text) + r.end()
        let said = events.compactMap { e -> String? in if case .say(let s, _) = e { return s }; return nil }
        let steps = events.compactMap { e -> TutorStep? in if case .step(let s) = e { return s }; return nil }
        return (events, said, steps, r.problems)
    }

    /// What was spoken of a reply as written.
    public static func spoken(_ text: String) -> String { read(text).said.joined(separator: " ") }
}
