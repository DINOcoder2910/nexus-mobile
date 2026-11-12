import Foundation
import Yams

/// A workstream's `study/review.yaml`: the FSRS schedule of every card, per deck and direction (nexus docs/data-format.md "Study").
/// Read and written exactly as the laptop's studydeck.js parseReview / serializeReview do: one flow line per card, times in UTC to the
/// minute, the last 40 grades. The laptop, the iPad and the iPhone all write it, and the hub merges it line by line, so before a
/// write the app merges what is on disk with what it holds, card by card (`reconcile`): the newer review of a card wins and no
/// device's grades are written over. A conflict copy the hub made (`review (conflict iPad 2026-11-12 0815).yaml`) is folded in
/// the same way (`merge`).
public struct ReviewBook: Equatable, Sendable {
    /// deck id -> its two directions.
    public var decks: [String: DeckReview] = [:]
    public init(decks: [String: DeckReview] = [:]) { self.decks = decks }

    public struct DeckReview: Equatable, Sendable {
        public var forward = CardStates()
        public var reverse = CardStates()
        public init(forward: CardStates = CardStates(), reverse: CardStates = CardStates()) { self.forward = forward; self.reverse = reverse }
        public subscript(_ dir: StudyDeck.Direction) -> CardStates {
            get { dir == .forward ? forward : reverse }
            set { if dir == .forward { forward = newValue } else { reverse = newValue } }
        }
    }

    /// Card id -> its state, in the order the file has them (new cards last).
    public struct CardStates: Equatable, Sendable {
        public private(set) var ids: [String] = []
        public private(set) var map: [String: SRSCard] = [:]
        public init() {}
        public var isEmpty: Bool { ids.isEmpty }
        public subscript(_ id: String) -> SRSCard? {
            get { map[id] }
            set {
                if let v = newValue { if map[id] == nil { ids.append(id) }; map[id] = v }
                else if map.removeValue(forKey: id) != nil { ids.removeAll { $0 == id } }
            }
        }
    }

    public func states(_ deck: String, _ dir: StudyDeck.Direction) -> [String: SRSCard] { decks[deck]?[dir].map ?? [:] }

    public subscript(_ deck: String, _ dir: StudyDeck.Direction, _ card: String) -> SRSCard? {
        get { decks[deck]?[dir][card] }
        set { var d = decks[deck] ?? DeckReview(); d[dir][card] = newValue; decks[deck] = d }
    }

    // MARK: reading

    public enum ParseError: Error, Equatable { case yaml(String) }

    public static func parse(_ text: String) -> Result<ReviewBook, ParseError> {
        let root: Node?
        do { root = try Yams.compose(yaml: text) } catch { return .failure(.yaml("study/review.yaml does not parse: " + TaskFile.yamlMessage(error))) }
        var book = ReviewBook()
        guard let decks = root?.mapping.flatMap({ TaskFile.value($0, "decks") })?.mapping else { return .success(book) }
        for (k, dn) in decks {
            let id = StudyDeck.str(k)
            guard dn.mapping != nil || dn.sequence != nil else { continue }
            var deck = book.decks[id] ?? DeckReview()
            for dir in StudyDeck.Direction.allCases {
                guard let cards = dn.mapping.flatMap({ TaskFile.value($0, dir.rawValue) })?.mapping else { continue }
                var states = CardStates()
                for (ck, cn) in cards {
                    guard let c = cn.mapping else { continue }
                    let v = { (key: String) in TaskFile.value(c, key) }
                    var log: [SRSCard.LogEntry] = []
                    for e in v("log")?.sequence ?? [] {
                        guard let x = e.sequence, x.count >= 2 else { continue }
                        let mode = x.count > 2 ? StudyDeck.str(x[2]) : ""
                        log.append(.init(at: ms(x[0]), grade: Int(number(x[1])), mode: mode == "0" || mode == "false" ? "" : mode))
                    }
                    let state = SRSCard.Phase(rawValue: StudyDeck.str(v("state"))) ?? .new
                    states[StudyDeck.str(ck)] = SRSCard(state: state, due: ms(v("due")), s: number(v("s")), d: number(v("d")),
                                                       reps: Int(number(v("reps"))), lapses: Int(number(v("lapses"))), last: ms(v("last")), log: log)
                }
                deck[dir] = states
            }
            book.decks[id] = deck
        }
        return .success(book)
    }

    /// Number(v) || 0.
    static func number(_ n: Node?) -> Double {
        let s = StudyDeck.str(n).trimmed
        guard let x = Double(s), x.isFinite else { return 0 }
        return x
    }

    /// A time: a number of milliseconds, or a date and time as Date.parse reads it ("2026-11-03T09:00Z"); 0 for none.
    static func ms(_ n: Node?) -> Int64 {
        let s = StudyDeck.str(n).trimmed
        if s.isEmpty { return 0 }
        if let x = Double(s), x.isFinite { return Int64(x) }
        return parseTime(s) ?? 0
    }

    /// The ISO forms Date.parse takes: a date alone is UTC midnight, a date and time with no zone is local time.
    public static func parseTime(_ s: String) -> Int64? {
        guard let m = StudyDeck.match(#"^([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[T ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]{1,9}))?)?)?(Z|[+-][0-9]{2}:?[0-9]{2})?$"#, s) else { return nil }
        var c = DateComponents()
        c.year = Int(m[1]); c.month = Int(m[2]); c.day = Int(m[3])
        c.hour = Int(m[4]) ?? 0; c.minute = Int(m[5]) ?? 0; c.second = Int(m[6]) ?? 0
        var cal = Calendar(identifier: .gregorian)
        let zone = m[8]
        if zone == "Z" || (zone.isEmpty && m[4].isEmpty) { cal.timeZone = TimeZone(identifier: "UTC")! }
        else if zone.isEmpty { cal.timeZone = FSRS.timeZone }
        else {
            let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
            let mins = (Int(digits.prefix(2)) ?? 0) * 60 + (Int(digits.suffix(2)) ?? 0)
            cal.timeZone = TimeZone(secondsFromGMT: (zone.hasPrefix("-") ? -1 : 1) * mins * 60)!
        }
        guard let d = cal.date(from: c) else { return nil }
        let frac = m[7].isEmpty ? 0 : Int64((Double("0." + m[7]) ?? 0) * 1000)
        return Int64((d.timeIntervalSince1970 * 1000).rounded()) + frac
    }

    // MARK: writing

    static let logMax = 40
    static let header = ["# Written by Nexus (Study › Memorize): spaced-repetition progress (FSRS) per deck, direction and card.",
                         "# due/last are UTC; s = stability (days), d = difficulty (1-10); log = [time, grade 1-4, mode]."]

    /// The file, one flow line per card, so a diff (and the hub's merge) shows which cards a session touched.
    public func serialize() -> String {
        var lines = Self.header + ["decks:"]
        for id in decks.keys.sorted(by: jsLess) {
            let d = decks[id]!
            let dirs = StudyDeck.Direction.allCases.filter { !d[$0].isEmpty }
            if dirs.isEmpty { continue }
            lines.append("  \(Self.flowKey(id)):")
            for dir in dirs {
                lines.append("    \(dir.rawValue):")
                let states = d[dir]
                for cid in Self.jsKeyOrder(states.ids) {
                    let c = states.map[cid]!
                    let log = c.log.suffix(Self.logMax).map { "[\(Self.isoOrNull($0.at)), \($0.grade), \(Self.flowString($0.mode))]" }
                    let fields = ["state: \(Self.flowString(c.state.rawValue))", "due: \(Self.isoOrNull(c.due))", "s: \(FSRS.jsNumber(c.s))",
                                  "d: \(FSRS.jsNumber(c.d))", "reps: \(c.reps)", "lapses: \(c.lapses)", "last: \(Self.isoOrNull(c.last))",
                                  "log: [\(log.joined(separator: ", "))]"]
                    lines.append("      \(Self.flowKey(cid)): {\(fields.joined(separator: ", "))}")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The order JavaScript keeps an object's keys in: whole-number keys first, smallest first, then the rest as added.
    static func jsKeyOrder(_ ids: [String]) -> [String] {
        let isIndex = { (k: String) -> Bool in
            guard StudyDeck.test("^(0|[1-9][0-9]*)$", k), let n = UInt64(k) else { return false }
            return n < 4_294_967_295
        }
        let nums = ids.filter(isIndex).sorted { UInt64($0)! < UInt64($1)! }
        return nums + ids.filter { !isIndex($0) }
    }

    static func isoOrNull(_ ms: Int64) -> String {
        guard ms != 0 else { return "null" }
        // toISOString cut to the minute (never rounded up), worked out by hand: a formatter per card is slow on a big file
        let mins = ms >= 0 ? ms / 60_000 : -((-ms + 59_999) / 60_000)
        let dayNo = mins >= 0 ? mins / 1440 : -((-mins + 1439) / 1440)
        let minOfDay = mins - dayNo * 1440
        // days since 1970-01-01 to a civil date (H. Hinnant's days_from_civil, inverted)
        let z = dayNo + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        let y = yoe + era * 400 + (m <= 2 ? 1 : 0)
        func p2(_ n: Int64) -> String { n < 10 ? "0\(n)" : "\(n)" }
        return "\(y)-\(p2(m))-\(p2(d))T\(p2(minOfDay / 60)):\(p2(minOfDay % 60))Z"
    }

    static let plainWords = #"^(true|false|null|yes|no|on|off|~)$"#

    static func flowKey(_ k: String) -> String {
        let ok = StudyDeck.test(#"^[A-Za-z0-9_][A-Za-z0-9_.-]*$"#, k) && !StudyDeck.test(plainWords, k.lowercased()) && !StudyDeck.test(#"^[0-9.]+$"#, k)
        return ok ? k : jsonString(k)
    }

    static func flowString(_ v: String) -> String {
        let ok = StudyDeck.test(#"^[A-Za-z0-9_.:-]+$"#, v) && !StudyDeck.test(plainWords, v.lowercased()) && !StudyDeck.test(#"^[0-9.]+$"#, v)
        return ok ? v : jsonString(v)
    }

    /// JSON.stringify of a string.
    static func jsonString(_ s: String) -> String {
        var out: [UInt16] = [0x22]
        for u in s.utf16 {
            switch u {
            case 0x22: out += "\\\"".utf16
            case 0x5C: out += "\\\\".utf16
            case 0x08: out += "\\b".utf16
            case 0x0C: out += "\\f".utf16
            case 0x0A: out += "\\n".utf16
            case 0x0D: out += "\\r".utf16
            case 0x09: out += "\\t".utf16
            case 0..<0x20: out += String(format: "\\u%04x", u).utf16
            default: out.append(u)
            }
        }
        out.append(0x22)
        return String(decoding: out, as: UTF16.self)
    }

    // MARK: two devices' grades

    /// Both books card by card: a card in one only is kept; a card in both takes the one reviewed last (the more reviews if at the same
    /// minute, else this book's), with both logs. Card order: this book's, then the other's new ones.
    public func merged(with other: ReviewBook) -> ReviewBook {
        var out = self
        for (id, od) in other.decks {
            for dir in StudyDeck.Direction.allCases {
                for cid in od[dir].ids {
                    let theirs = od[dir].map[cid]!
                    guard let mine = out[id, dir, cid] else { out[id, dir, cid] = theirs; continue }
                    if mine == theirs { continue }
                    var win = theirs.last > mine.last || (theirs.last == mine.last && theirs.reps > mine.reps) ? theirs : mine
                    win.log = Self.mergeLogs(mine.log, theirs.log)
                    out[id, dir, cid] = win
                }
            }
        }
        return out
    }

    static func mergeLogs(_ a: [SRSCard.LogEntry], _ b: [SRSCard.LogEntry]) -> [SRSCard.LogEntry] {
        var seen = Set<String>(), all: [SRSCard.LogEntry] = []
        for e in a + b where seen.insert("\(e.at / 60_000)|\(e.grade)|\(e.mode)").inserted { all.append(e) }
        return Array(all.enumerated().sorted { $0.element.at != $1.element.at ? $0.element.at < $1.element.at : $0.offset < $1.offset }.map(\.element).suffix(logMax))
    }

    public struct Reconciled: Equatable, Sendable {
        /// What to hold from now on (and write).
        public var book: ReviewBook
        /// The file's new text.
        public var text: String
        /// The file on disk did not parse: keep it aside first (as the laptop does: review.broken-<day>-<n>.yaml), then write.
        public var keepBrokenAside: Bool
    }

    /// Before a write: `mine` is what the app holds, `disk` the file now (nil: none), `lastWritten` the text this app last read or wrote.
    /// When the file is still what this app last saw, `mine` is written as it is (so an undone grade stays undone); when another
    /// device changed it meanwhile, the two are merged card by card.
    public static func reconcile(mine: ReviewBook, disk: String?, lastWritten: String?) -> Reconciled {
        guard let disk, disk != lastWritten else { return Reconciled(book: mine, text: mine.serialize(), keepBrokenAside: false) }
        switch parse(disk) {
        case .success(let theirs):
            let book = mine.merged(with: theirs)
            return Reconciled(book: book, text: book.serialize(), keepBrokenAside: false)
        case .failure:
            return Reconciled(book: mine, text: mine.serialize(), keepBrokenAside: true)
        }
    }

    /// A copy of review.yaml the hub kept when two devices' changes touched the same lines.
    public static func isConflictCopy(_ name: String) -> Bool {
        name.hasPrefix("review (conflict ") && name.lowercased().hasSuffix(".yaml") && SyncPaths.isConflictCopy(name)
    }
}
