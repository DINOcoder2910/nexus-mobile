import Foundation
import NexusRust

/// The shared Rust core (nexus `core/`, the code the laptop's new app runs) as NexusCore uses it. Packages/NexusCore/Rust holds a copy
/// (tools/rust-core/copy.sh) that CI builds for the iPad, the simulator and the Mac; NexusRust is the Swift UniFFI wrote for it. Most
/// answers cross as JSON text, the same shapes the laptop's backend hands its screens, and are read into NexusCore's types here.
public enum RustCore {
    /// Which core this build carries, e.g. "nexus-core 0.1.0 (d82054f)".
    public static var version: String { coreVersion() }

    static func json(_ text: String) -> JSONValue? { try? JSONValue.parse(text) }

    /// The core's `[{"problem", "text"}]`.
    static func problems(_ text: String) -> [(problem: String, text: String)] {
        (json(text)?.array ?? []).map { ($0["problem"]?.string ?? "", $0["text"]?.string ?? "") }
    }

    /// The core's events (a JSON array of `{"say", "n"}` and `{"step"}`) as TutorEvents. A step the core passed is read into a
    /// TutorStep by TutorSteps.check, which keeps a clean step as it is; one the iPad can't draw goes to `refused`.
    static func events(_ text: String, refused: inout [(problem: String, text: String)]) -> [TutorEvent] {
        var out: [TutorEvent] = []
        for e in json(text)?.array ?? [] {
            if let s = e["say"]?.string { out.append(.say(s, n: Int(e["n"]?.number ?? 0))); continue }
            guard let raw = e["step"] else { continue }
            let r = TutorSteps.check(raw)
            if let s = r.step { out.append(.step(s)) } else { refused.append((r.problem ?? "refused", String(raw.text.prefix(200)))) }
        }
        return out
    }

    // MARK: the tutor

    /// One drawing step as Claude wrote it: the clean step (the laptop's shape) or why it is left out.
    public static func checkStep(_ raw: JSONValue) -> (step: JSONValue?, problem: String?) {
        let r = tutorCheckStep(raw: raw.text)
        return (r.step.flatMap { json($0) }, r.problem)
    }

    /// What the voice says for one piece of prose (markdown taken out).
    public static func speakable(_ text: String) -> String { tutorSpeakable(text: text) }

    /// The drawing steps' guide, as the laptop sends it.
    public static var stepsPrompt: String { tutorStepsPrompt() }

    // MARK: Check my maths

    /// Lines of working checked by the computer (the core's tutor/maths.rs), never guessed by a model: each written line against the
    /// one before, the first slip, and the first equation's solutions.
    public struct Maths: Equatable {
        public struct Line: Equatable {
            /// true follows from the line before, false the slip, nil not read or nothing to compare with
            public var ok: Bool?
            /// in words, for the tutor and the screen
            public var why: String
        }
        /// one a line as written; nil for a blank line
        public var lines: [Line?]
        /// the first slip's line (counting blank ones), or nil when every line follows
        public var first: Int?
        /// the first equation's solutions, e.g. "x = 0 or x = 4"
        public var answer: String?

        /// The first slip counted as the student counts lines (blank ones left out), from 1.
        public var firstWritten: Int? { first.map { f in lines.prefix(f + 1).filter { $0 != nil }.count } }
        /// Something was read and compared.
        public var compared: Bool { lines.contains { $0?.ok != nil } }
    }

    public static func checkMaths(_ lines: [String]) -> Maths {
        let m = mathsCheck(lines: lines)
        return Maths(lines: m.lines.map { l in l.map { Maths.Line(ok: $0.ok, why: $0.why) } }, first: m.first.map { Int($0) }, answer: m.answer)
    }

    // MARK: capture and study cards

    /// The capture line as the laptop reads it (the core's capture.rs): `{kind, ok, title, facts, subtasks, flags, match, spans}`.
    public static func capture(_ text: String, today: String, plan: String? = nil, workstreamTags: [String] = []) -> JSONValue {
        json(captureParse(text: text, today: today, plan: plan, workstreamTags: workstreamTags)) ?? .null
    }

    /// A study card (`{state, due, s, d, reps, lapses, last}`) after a grade, 1 Again .. 4 Easy, the day starting at `dayStart`.
    public static func review(card: JSONValue, grade: Int, now: Int64, dayStart: Int) -> JSONValue {
        json(fsrsReview(card: card.text, grade: UInt8(max(1, min(4, grade))), nowMs: now, dayStart: UInt32(max(0, dayStart)))) ?? .null
    }
}

/// The tutor's reply, read as it streams in by the shared Rust core (tutor/reply.rs, what the laptop's new app runs). Claude writes
/// what it says as plain prose and each drawing step as `<step>{json}</step>` right after the sentence it goes with; `push` takes the
/// text in any pieces and hands back events in order (a sentence to say, or a clean step to draw), `end()` the rest. A step that
/// doesn't parse or that the core refuses is dropped and listed in `problems`. Not thread-safe on its own (BoardTutor locks it).
public final class TutorReader {
    let core = ReplyReader()
    var refused: [(problem: String, text: String)] = []

    public init() {}

    /// The steps left out and why: the core's, then any the iPad couldn't draw.
    public var problems: [(problem: String, text: String)] { RustCore.problems(core.problems()) + refused }
    /// How many sentences have been handed out.
    public var sentences: Int { Int(core.sentences()) }

    /// More of the reply -> the events it completes.
    public func push(_ piece: String) -> [TutorEvent] { RustCore.events(core.push(piece: piece), refused: &refused) }

    /// The reply is complete: the rest of it. A step cut off by the end is dropped.
    public func end() -> [TutorEvent] { RustCore.events(core.end(), refused: &refused) }

    /// What the voice should say for one piece of prose.
    public static func speakable(_ s: String) -> String { RustCore.speakable(s) }

    /// The UTF-16 offset just past the end of the first full sentence in `s`, or -1 (NexusCore's Swift port).
    public static func sentenceEnd(_ s: String, final: Bool = false) -> Int { SwiftTutorReader.sentenceEnd(s, final: final) }

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
