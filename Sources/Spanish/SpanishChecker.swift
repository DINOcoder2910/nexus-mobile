import SwiftUI
import UIKit
import NexusCore

/// The checker's three layers on the iPhone and iPad, as the laptop's (nexus lang-service.js and spanishview.js runCheck): the device's
/// own Spanish dictionary (UITextChecker, offline; it also finds the accented word a misspelling is missing, cafe -> café) and
/// LanguageTool's free service answer first and their marks show at once; Claude Haiku's reading follows and wins where they disagree
/// (SpanishCheck.merge). Every check is added to the month's log and the numbers per skill are counted again (SpanishLibrary.addToLog).
enum SpanishLayers {
    /// The device's Spanish dictionary, if it has one.
    @MainActor static var language: String? { UITextChecker.availableLanguages.first { $0 == "es_ES" } ?? UITextChecker.availableLanguages.first { $0.hasPrefix("es") } }

    /// The words the dictionary does not know (two letters or more), each with the accented word it knows, or its guesses.
    @MainActor
    static func spell(_ text: String) -> (ok: Bool, error: String, words: [SpanishCheck.SpellWord]) {
        guard let lang = language else { return (false, "There is no Spanish dictionary on this \(Device.name).", []) }
        let checker = UITextChecker()
        func known(_ w: String) -> Bool {
            checker.rangeOfMisspelledWord(in: w, range: NSRange(location: 0, length: (w as NSString).length), startingAt: 0, wrap: false, language: lang).location == NSNotFound
        }
        var out: [SpanishCheck.SpellWord] = []
        for (w, at) in SpanishCheck.words(text) {
            let len = (w as NSString).length
            guard len >= 2, !known(w) else { continue }
            let accent = SpanishCheck.accentVariants(w).first(where: known)
            let guesses = accent.map { [$0] } ?? Array((checker.guesses(forWordRange: NSRange(location: 0, length: len), in: w, language: lang) ?? []).prefix(4))
            out.append(.init(word: w, start: at, end: at + len, accent: accent, suggestions: guesses))
        }
        return (true, "", out)
    }

    /// LanguageTool (POST https://api.languagetool.org/v2/check, language=es), 8 seconds at most.
    static func languageTool(_ text: String) async -> (ok: Bool, error: String, matches: [SpanishCheck.LTMatch]) {
        if SpanishDemo.active { try? await Task.sleep(for: .milliseconds(300)); return (true, "", SpanishDemo.languageTool(text)) }
        var r = URLRequest(url: URL(string: "https://api.languagetool.org/v2/check")!, timeoutInterval: 8)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        r.httpBody = Data("language=es&text=\(enc(text))&level=default".utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return (false, "LanguageTool answered \(status).", []) }
            guard let json = try? JSONValue.parse(String(decoding: data, as: UTF8.self)) else { return (false, "LanguageTool's answer could not be read.", []) }
            return (true, "", SpanishCheck.LTMatch.list(json))
        } catch {
            return (false, (error as? URLError)?.code == .timedOut ? "LanguageTool did not answer in time." : "LanguageTool could not be reached (\(error.localizedDescription)).", [])
        }
    }
}

/// One call to Claude for a JSON answer (the checker, the memory update, the marking): the app-wide Plan / API switch decides how.
enum SpanishClaude {
    static func once(model: String, system: String, prompt: String, maxTokens: Int = 4096, demo: @escaping () -> String) async throws -> String {
        if SpanishDemo.active { try? await Task.sleep(for: .milliseconds(700)); return demo() }
        let r = try await ClaudeClient.shared.stream(ClaudeRequest(model: model, system: system, messages: [.user(prompt)], maxTokens: maxTokens), onText: { _ in })
        if r.stopped { throw ClaudeError("Claude stopped before it finished.") }
        return r.text
    }
}

/// One check of a sentence, shown as it goes: the dictionary and LanguageTool first, then Claude.
@MainActor
@Observable
final class SpanishCheckRun: Identifiable {
    enum State: String { case busy, ok, off, wait }
    let id = UUID()
    let text: String
    let question: String
    let source: String
    var chat: String
    var marks: [SpanishCheck.Mark] = []
    var done = false
    var dictionary: State = .busy
    var languagetool: State = .busy
    var claude: State = .wait
    var dictError = "", ltError = "", aiError = ""
    var result: SpanishCheck.Result?
    var entry: SpanishCheck.Entry?

    init(text: String, question: String = "", source: String = "checker", chat: String = "") {
        self.text = text; self.question = question; self.source = source; self.chat = chat
    }

    /// The meaning of a word, from Claude's reading.
    func info(_ word: String) -> SpanishCheck.AI.Word? {
        let w = word.lowercased()
        return result?.words.first { $0.word.lowercased() == w }
    }

    /// Runs the three layers and saves the check to the log; returns the log entry.
    @discardableResult
    func run(_ store: NexusStore, wsId: String) async -> SpanishCheck.Entry {
        let lib = SpanishLibrary.shared
        let sentence = text
        async let lt = SpanishLayers.languageTool(sentence)
        let sp = SpanishLayers.spell(text)
        let ltr = await lt
        dictionary = sp.ok ? .ok : .off; dictError = sp.error
        languagetool = ltr.ok ? .ok : .off; ltError = ltr.error
        let algo = SpanishCheck.spellMarks(sp.words) + SpanishCheck.ltMarks(text, ltr.matches)
        marks = SpanishCheck.merge(text, algo, nil)
        claude = .busy
        var ai: SpanishCheck.AI?
        do {
            let prompt = SpanishCheck.prompt(text: text, question: question, found: algo, taught: lib.data(wsId).status)
            let text = self.text
            let reply = try await SpanishClaude.once(model: "haiku", system: SpanishCheck.system, prompt: prompt, demo: { SpanishDemo.check(text) })
            ai = SpanishCheck.readCheck(text, SpanishCheck.jsonFrom(reply))
            if ai == nil { aiError = "Claude's answer could not be read." }
        } catch {
            aiError = error.localizedDescription
        }
        claude = ai == nil ? .off : .ok
        marks = SpanishCheck.merge(text, algo, ai)
        let res = SpanishCheck.Result(marks: marks, corrected: ai?.corrected ?? SpanishCheck.corrected(text, marks), structures: ai?.structures ?? [], words: ai?.words ?? [], partial: ai == nil)
        result = res
        done = true
        let e = SpanishCheck.logEntry(at: SpanishLibrary.stamp(), source: source, text: text, question: question, result: res, chat: chat)
        entry = e
        lib.addToLog(store, wsId, e)
        return e
    }
}
