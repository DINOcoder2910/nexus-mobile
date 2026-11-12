import Foundation

/// A review session over one deck, a port of the laptop's app/studyreview.js (its startSession, nextCard, grade, undo): the due
/// cards first (most overdue first), then new ones up to a limit; a card graded Again, or coming back within 20 minutes, is asked
/// again before the end; Undo takes the last grade back. Pure: the clock is passed in, and each grade hands back the card's new
/// state for the caller to keep in its ReviewBook and write.
public struct StudySession: Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case flip, type, mcq
        public var label: String { self == .flip ? "Flip and grade" : self == .type ? "Type the answer" : "Multiple choice" }
        public var detail: String {
            switch self {
            case .flip: return "See it, recall it, show the answer, grade yourself."
            case .type: return "Checked for you: SO4 2-, SO4^2- and SO₄²⁻ all count."
            case .mcq: return "Pick one of four."
            }
        }
    }
    public enum Phase: Sendable { case ask, shown, end }

    /// A card coming back within this long is asked again in the same session.
    public static let soon: Int64 = 20 * FSRS.minute

    public let deck: StudyDeck
    public let dir: StudyDeck.Direction
    public let mode: Mode
    /// A flip deck: which side is shown first.
    public let show: StudyDeck.Show?
    public let tag: String
    /// Every card once, unscheduled: nothing is written.
    public let practise: Bool
    public let seed: String
    public let total: Int

    public private(set) var queue: [String]
    public private(set) var current: String?
    public private(set) var phase: Phase = .ask
    public private(set) var result: StudyDeck.Verdict?
    public private(set) var typed = ""
    public private(set) var picked: Int?
    public private(set) var choices: (options: [String], correct: Int)?
    public private(set) var done = 0
    public private(set) var right = 0
    /// The schedule of this deck and direction as the session has it (the real one, or a scratch copy when practising).
    public private(set) var states: [String: SRSCard]
    private var reviewed = Set<String>()
    private var history: [Step] = []
    private let ids: [String]

    struct Step: Sendable { var card: String; var prev: SRSCard?; var queue: [String]; var done: Int; var right: Int; var reviewed: Set<String> }

    /// nil when there is nothing to review.
    public init?(deck: StudyDeck, dir: StudyDeck.Direction, mode: Mode, show: StudyDeck.Show = .es, tag: String = "", newLimit: Int,
                 practise: Bool = false, states: [String: SRSCard], now: Int64) {
        self.deck = deck
        self.dir = deck.flip || !deck.reversible ? .forward : dir
        self.mode = deck.flip ? .flip : mode
        self.show = deck.flip ? show : nil
        self.tag = deck.flip ? tag : ""
        self.practise = practise
        ids = Self.cardIds(deck, tag: self.tag)
        let q = FSRS.sessionQueue(ids, states, now, newLimit: newLimit, all: practise)
        if q.isEmpty { return nil }
        queue = q
        total = q.count
        seed = String(now)
        self.states = practise ? [:] : states
        nextCard(now)
    }

    /// The cards a session asks: every card, or a flip deck's cards with the tag.
    public static func cardIds(_ deck: StudyDeck, tag: String) -> [String] {
        deck.cards.filter { tag.isEmpty || $0.tags.contains(tag) }.map(\.id)
    }

    public var card: StudyDeck.Card? { current.flatMap { id in deck.cards.first { $0.id == id } } }

    /// The current card as asked: its prompt, answer and what else counts.
    public var side: StudyDeck.Side? {
        guard let c = card else { return nil }
        return show.map { StudyDeck.flipSide(c, $0, seed: seed) } ?? StudyDeck.side(c, dir)
    }

    /// The grade Enter takes: none for flip (you grade yourself), Good when right, Hard for capitals only, else Again.
    public var suggested: Int? {
        guard mode != .flip, phase == .shown else { return nil }
        return result == .right ? 3 : result == .case ? 2 : 1
    }

    public var canUndo: Bool { !history.isEmpty }

    /// What each grade would do now.
    public func preview(_ now: Int64) -> [FSRS.Preview] {
        FSRS.preview(current.flatMap { states[$0] } ?? SRSCard(), now)
    }

    // MARK: answering

    /// Flip: show the answer.
    public mutating func reveal() { if phase == .ask, current != nil { phase = .shown } }

    /// Type the answer: check it and show the answer.
    public mutating func submit(_ text: String) {
        guard phase == .ask, let side else { return }
        typed = text
        result = StudyDeck.check(text, side.answer, accept: side.accept)
        phase = .shown
    }

    /// Multiple choice: pick option i.
    public mutating func pick(_ i: Int) {
        guard phase == .ask, let c = choices, i >= 0, i < c.options.count else { return }
        picked = i
        result = i == c.correct ? .right : .wrong
        phase = .shown
    }

    /// Grade the shown card (1 Again … 4 Easy). Returns the card and its new state to keep, or nil when practising (nothing is kept).
    @discardableResult
    public mutating func grade(_ g: Int, now: Int64) -> (card: String, state: SRSCard)? {
        guard phase == .shown, let cur = current else { return nil }
        let prev = states[cur]
        var next = FSRS.review(prev ?? SRSCard(), g, now)
        next.log = (prev?.log ?? []) + [.init(at: now, grade: min(4, max(1, g)), mode: mode.rawValue)]
        history.append(Step(card: cur, prev: prev, queue: queue, done: done, right: right, reviewed: reviewed))
        states[cur] = next
        if !reviewed.contains(cur) { reviewed.insert(cur); if g >= 3 { right += 1 } }
        done += 1
        if g == 1 || (!practise && next.due <= now + Self.soon) { if !queue.contains(cur) { queue.append(cur) } }
        nextCard(now)
        return practise ? nil : (cur, next)
    }

    /// Takes the last grade back: that card is asked again. Returns the card and its state before (nil: it had none), or nil when
    /// there is nothing to undo or the session is practising.
    @discardableResult
    public mutating func undo() -> (card: String, state: SRSCard?)? {
        guard let last = history.popLast() else { return nil }
        states[last.card] = last.prev
        queue = last.queue; done = last.done; right = last.right; reviewed = last.reviewed
        current = last.card; phase = .ask; typed = ""; result = nil; picked = nil
        choices = mode == .mcq ? card.map { deck.choices($0, dir, seed: seed + String(done)) } : nil
        return practise ? nil : (last.card, last.prev)
    }

    private mutating func nextCard(_ now: Int64) {
        if queue.isEmpty && !practise {
            // learning cards that come back soon are asked again now
            if let back = FSRS.comingBack(ids, states, now + Self.soon, []).first { queue.append(back) }
        }
        current = queue.isEmpty ? nil : queue.removeFirst()
        phase = current == nil ? .end : .ask
        typed = ""; result = nil; picked = nil
        choices = mode == .mcq ? card.map { deck.choices($0, dir, seed: seed + String(done)) } : nil
    }

    // MARK: a deck's numbers

    /// A flip deck's new cards started today (the first grade of a card today makes it one of today's).
    public static func newToday(_ states: [String: SRSCard], now: Int64) -> Int {
        let today = Days.today(now: Date(timeIntervalSince1970: Double(now) / 1000))
        let start = ReviewBook.parseTime(today + "T00:00:00") ?? now
        return states.values.filter { s in s.log.first.map { $0.at >= start && $0.at <= now } ?? false }.count
    }

    /// "Next card due in 3 days." (or "" when no card is waiting).
    public static func nextDueText(_ states: [String: SRSCard], ids: [String], now: Int64) -> String {
        let keep = Set(ids)
        guard let first = states.filter({ keep.contains($0.key) && $0.value.state != .new && $0.value.due > now }).map(\.value.due).min() else { return "" }
        return "Next card due in \(FSRS.untilWords(first, now))."
    }
}

/// Where the decks are: each workstream with a `study/` folder, its decks (`study/decks/**/*.yaml`) and its review file.
public enum StudyFolder {
    public struct DeckFile: Identifiable, Sendable {
        /// From the data folder: "classes/chem-hl/study/decks/ions.yaml".
        public var path: String
        /// The file's name without .yaml (the deck's id when it has none).
        public var fileId: String
        public var deck: StudyDeck?
        public var error: String?
        public var problems: [String]
        public var id: String { path }
        /// The id review.yaml keys the deck by.
        public var deckId: String { deck?.id ?? fileId }
    }

    public static func studyPath(_ w: Workstream) -> String { w.folder + "/study" }
    public static func reviewPath(_ w: Workstream) -> String { w.folder + "/study/review.yaml" }

    /// The workstreams that have a study folder, in sidebar order.
    public static func workstreams(_ root: URL, _ snapshot: Snapshot) -> [Workstream] {
        var isDir: ObjCBool = false
        return snapshot.groups.flatMap { snapshot.workstreams(in: $0) }.filter { w in
            FileManager.default.fileExists(atPath: root.appendingPathComponent(studyPath(w)).path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// A workstream's deck files, sorted as the laptop sorts them (conflict copies left out: they are not data).
    public static func deckPaths(_ root: URL, _ w: Workstream) -> [String] {
        let base = studyPath(w) + "/decks"
        let dir = root.appendingPathComponent(base)
        guard let walk = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [String] = []
        let prefix = dir.standardizedFileURL.path
        for case let url as URL in walk {
            let ext = url.pathExtension.lowercased()
            guard ext == "yaml" || ext == "yml", (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let path = base + "/" + rel
            if SyncPaths.isConflictCopy(path) || SyncPaths.isIgnored(path) { continue }
            out.append(path)
        }
        return out.sorted(by: jsLess)
    }

    /// Reads and parses one deck file.
    public static func readDeck(_ root: URL, _ path: String, read: (URL) throws -> String) -> DeckFile {
        let name = (path as NSString).lastPathComponent
        let fileId = name.replacingOccurrences(of: #"\.ya?ml$"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard let text = try? read(root.appendingPathComponent(path)) else {
            return DeckFile(path: path, fileId: fileId, deck: nil, error: "could not be read", problems: [])
        }
        let p = StudyDeck.parse(text, fileId: fileId)
        return DeckFile(path: path, fileId: fileId, deck: p.deck, error: p.error, problems: p.problems)
    }

    /// The hub's conflict copies of a workstream's review file, to fold in.
    public static func reviewConflictCopies(_ root: URL, _ w: Workstream) -> [String] {
        let dir = studyPath(w)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(dir).path)) ?? []
        return names.filter(ReviewBook.isConflictCopy).sorted(by: jsLess).map { dir + "/" + $0 }
    }
}
