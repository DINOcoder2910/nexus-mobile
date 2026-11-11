import Foundation

// The capture line, read as the laptop reads it: a port of the laptop's renderer/src/taskparse.js (the parser), dates.js (the words
// for days), the capture half of store/vindex.js (`matchCapture`: which workstream the words name), captureland.js (where the line
// lands, "@fri") and capturechips.js (the preview's wording). "physics hw sheet by fri; q1-5 by thu on wed 45m" is a task titled
// "physics hw sheet", due Friday, with a subtask "q1-5" due Thursday, planned Wednesday, 45 minutes. The laptop's
// dev/unit-taskparse.mjs is the reference; CaptureParseTests.swift ports its table.
//
// The grammar (all optional, case-insensitive):
//   by / due / for / before + a date: the deadline          on / do + a date: a planned day (several are kept)
//   a bare date (friday, tomorrow, 12 nov, in 3 days, next week, eow): the deadline
//   4pm, at 16:00, 4:30pm: a time on the planned day (no day: today; "every fri 4pm": the next Friday). Right after a deadline
//     ("by fri 5pm", "by 5pm" = today), or when the only date is a deadline, it is dropped and flagged: deadlines are whole days.
//   1h, 30m, 1h30, 90 min, 2 hrs, ~2h, for 45m: the estimate        !, a trailing ! on a word, ★, *: key (★)
//   daily, weekly, every day / week / weekday / mon: repeat
//   waiting on / wait for <person>: waiting, since today
//   #word: a tag (or a workstream)     ; a; b: subtasks, each parsed the same way     "quoted words": kept, never parsed or matched
//   sat, sun, may, mar: words, unless after by/on/due/before or inside a date with a number ("may 3", "sat 14 nov")
//   a line starting with / (Claude) or > (the command palette) is not a task (unless `commands` is false).
// Only the first deadline, time, estimate and repeat count; a second one stays in the title as typed.
//
// Positions (spans, ignore) count Characters of the typed text (the laptop counts UTF-16 units; the same for plain text).
// Facts come out in the shapes the files use: due "YYYY-MM-DD", plan ["YYYY-MM-DD" or "YYYY-MM-DD HH:MM"], est "1h30m".

// MARK: - What a parse returns

public struct CaptureRepeat: Equatable {
    /// "day", "weekdays" or "week"
    public var freq: String
    /// "mon" ... "sun" for "every mon", else nil
    public var on: String?
    public init(freq: String, on: String? = nil) { self.freq = freq; self.on = on }
}

public struct CaptureWaiting: Equatable {
    public var on: String
    public var since: String
    public init(on: String, since: String) { self.on = on; self.since = since }
}

public struct CaptureFacts: Equatable {
    public var due: String?
    public var key = false
    /// "YYYY-MM-DD" or "YYYY-MM-DD HH:MM", as the files write a plan
    public var plan: [String] = []
    /// as the laptop writes it: "45m", "2h", "1h30m"
    public var est: String?
    public var waiting: CaptureWaiting?
    public var every: CaptureRepeat?
    public var tags: [String] = []
    public init() {}

    public var planEntries: [PlanEntry] { plan.compactMap { PlanEntry($0) } }
}

public struct CaptureFlag: Equatable {
    public enum Code: String {
        /// a time typed on a deadline (deadlines are whole days)
        case timeDropped = "time-dropped"
        /// sat / sun / may / mar kept as a word
        case ambiguous
        /// a deadline before today
        case pastDate = "past-date"
        case noTitle = "no-title"
    }
    public var code: Code
    public var text: String?
    public var time: String?
    public var date: String?
    public init(code: Code, text: String? = nil, time: String? = nil, date: String? = nil) {
        self.code = code; self.text = text; self.time = time; self.date = date
    }
}

/// Where a fact was typed: Characters `start..<end` of the line. `part` 0 is the task, 1... its subtasks.
public struct CaptureSpan: Equatable {
    public enum Kind: String {
        case due, plan, time, dropped, est, key, every, waiting, tag
        /// the #tag naming the workstream
        case ws
        /// a `;` that starts a subtask
        case sub
    }
    public var start: Int
    public var end: Int
    public var kind: Kind
    public var part: Int
    public var tag: String?
    public init(start: Int, end: Int, kind: Kind, part: Int = 0, tag: String? = nil) {
        self.start = start; self.end = end; self.kind = kind; self.part = part; self.tag = tag
    }
}

/// A part of the line the user took back (the laptop's Backspace on a highlight): its words are plain title words, never read or
/// matched. Kind `.sub`: the `;` there does not split; `.key`: only the ★ mark there.
public struct CaptureIgnore: Equatable {
    public var start: Int
    public var end: Int
    public var kind: CaptureSpan.Kind
    public init(start: Int, end: Int, kind: CaptureSpan.Kind) { self.start = start; self.end = end; self.kind = kind }
}

public struct CaptureSubtask: Equatable {
    public var ok: Bool
    public var title: String
    public var facts: CaptureFacts
    public var flags: [CaptureFlag]
}

public struct CaptureParsed: Equatable {
    public enum Kind: String { case empty, claude, palette, task }
    public var kind: Kind
    /// the line, for `.claude` and `.palette`
    public var text = ""
    /// there is a title to add
    public var ok = false
    public var title = ""
    public var facts = CaptureFacts()
    public var subtasks: [CaptureSubtask] = []
    public var flags: [CaptureFlag] = []
    /// the words left for workstream matching (matched words stay in the title; quoted words never match)
    public var matchText = ""
    /// every #tag typed, the workstream one included
    public var matchTags: [String] = []
    /// the #tag that names a workstream (it left `facts.tags`), or nil
    public var workstreamTag: String?
    public var spans: [CaptureSpan] = []

    public init(kind: Kind) { self.kind = kind }
    /// The subtasks that have a title (the ones to add).
    public var subtasksToAdd: [CaptureSubtask] { subtasks.filter(\.ok) }
}

// MARK: - The parser

public enum CaptureParse {
    static let dueWords: Set<String> = ["by", "due", "for", "before"]
    static let planWords: Set<String> = ["on", "do"]
    /// after these the ambiguous words are dates
    static let safePrefix: Set<String> = ["by", "on", "due", "before"]
    static let ambiguous: Set<String> = ["sat", "sun", "may", "mar"]
    /// "email tom", "do it now": names and words, not dates
    static let notDates: Set<String> = ["now", "tom", "tod", "yesterday", "yday"]
    static let honorific: Set<String> = ["mr", "mrs", "ms", "miss", "mx", "dr", "prof", "sir", "madam"]
    /// "wait for it", "waiting on the results": not a person, so not a waiting fact
    static let notPeople: Set<String> = ["it", "this", "that", "the", "a", "an", "my", "your", "his", "her", "their", "our", "them", "him", "me", "us", "you"]
    static let dayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    static let monthNames = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    static let hourUnits: Set<String> = ["h", "hr", "hrs", "hour", "hours"]
    static let minuteUnits: Set<String> = ["m", "min", "mins", "minute", "minutes"]

    static func dayOf(_ w: String?) -> Int {
        guard let w, w.count >= 3 else { return -1 }
        return dayNames.firstIndex { $0.hasPrefix(w) } ?? -1
    }

    // MARK: small readers

    /// "4pm", "4:30pm", "4 pm", "16:00" -> "HH:MM", else nil
    public static func timeOf(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let g = CaptureRx.groups(#"^([0-9]{1,2})(?::([0-9]{2}))?\s?(am|pm)$"#, t) {
            let h = Int(g[1] ?? "") ?? 0, mi = Int(g[2] ?? "0") ?? 0
            guard h >= 1 && h <= 12 && mi <= 59 else { return nil }
            return pad2((h % 12) + (g[3] == "pm" ? 12 : 0)) + ":" + pad2(mi)
        }
        if let g = CaptureRx.groups(#"^([0-9]{1,2}):([0-9]{2})$"#, t), let h = Int(g[1] ?? ""), let mi = Int(g[2] ?? ""), h <= 23, mi <= 59 {
            return pad2(h) + ":" + pad2(mi)
        }
        return nil
    }

    /// "1h", "30m", "1h30", "1h30m", "1.5h", "90 min", "2 hrs", "~2h" -> minutes, else nil
    public static func estimateOf(_ s: String) -> Int? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("~") { t = String(t.dropFirst()) }
        t = String(t.filter { !$0.isWhitespace })
        var n: Int?
        // (absurdly long numbers are not estimates: they would overflow Int)
        if let g = CaptureRx.groups(#"^([0-9]+(?:\.[0-9]+)?)(h|hr|hrs|hour|hours)$"#, t), let v = Double(g[1] ?? ""), v * 60 < 1e9 {
            n = Int((v * 60).rounded())
        } else if let g = CaptureRx.groups(#"^([0-9]+)(m|min|mins|minute|minutes)$"#, t) {
            n = Int(g[1] ?? "")
        } else if let g = CaptureRx.groups(#"^([0-9]+)h([0-9]{1,2})(m|min|mins)?$"#, t), let h = Int(g[1] ?? ""), h < 10_000_000, let m = Int(g[2] ?? "") {
            n = h * 60 + m
        }
        guard let v = n, v > 0 else { return nil }
        return v
    }

    /// Minutes as the laptop writes an estimate (planner.js estToken): "45m", "2h", "1h30m"; nil for none.
    public static func estToken(_ minutes: Int) -> String? {
        guard minutes > 0 else { return nil }
        let h = minutes / 60, m = minutes % 60
        return h > 0 && m > 0 ? "\(h)h\(m)m" : h > 0 ? "\(h)h" : "\(m)m"
    }

    // MARK: tokens

    struct Tok {
        var raw: String
        var norm: String
        var quoted: Bool
        var lit = false
        /// a mark typed on its own and taken back: keeps its space in the title
        var own = false
        var used = false
        var key = false
        var marks: [(Int, Int)] = []
        var pre = ""
        var suf = ""
        var start: Int
        var end: Int
    }

    typealias Lit = (Int, Int, Bool) -> Bool

    /// The end (index of the closing mark) of a quoted run starting at `k`, or nil.
    static func quoteEnd(_ s: [Character], _ k: Int) -> Int? {
        let close: Character
        if s[k] == "\"" { close = "\"" } else if s[k] == "\u{201C}" { close = "\u{201D}" } else { return nil }
        var j = k + 1
        while j < s.count { if s[j] == close { return j }; j += 1 }
        return nil
    }

    static let leadPunct: Set<Character> = ["(", "[", "{"]
    static let trailPunct: Set<Character> = [")", "]", "}", ",", ".", ";", ":", "?"]
    static func normOf(_ w: String) -> String {
        var c = Array(w.lowercased())
        while let f = c.first, leadPunct.contains(f) { c.removeFirst() }
        while let l = c.last, trailPunct.contains(l) { c.removeLast() }
        return String(c)
    }

    /// ";" splits the line into the task and its subtasks, except inside "quotes" and where it was taken back.
    static func splitParts(_ s: [Character], base: Int, lit: @escaping Lit) -> (parts: [(text: [Character], base: Int)], seps: [Int]) {
        var inQuote = [Bool](repeating: false, count: s.count)
        var k = 0
        while k < s.count {
            if let e = quoteEnd(s, k) { for q in k...e { inQuote[q] = true }; k = e + 1 } else { k += 1 }
        }
        var parts: [(text: [Character], base: Int)] = [], seps: [Int] = [], from = 0
        for i in 0..<s.count where s[i] == ";" && !inQuote[i] && !lit(base + i, base + i + 1, true) {
            parts.append((text: Array(s[from..<i]), base: base + from)); seps.append(base + i); from = i + 1
        }
        parts.append((text: Array(s[from..<s.count]), base: base + from))
        return (parts, seps)
    }

    static let markChars: Set<Character> = ["!", "★", "*"]
    /// A quoted run is one token with its words as typed (the quote marks go); `key` is set by a !, ★ or * mark.
    static func tokenize(_ s: [Character], base: Int, lit: @escaping Lit) -> [Tok] {
        var out: [Tok] = []
        var k = 0
        while k < s.count {
            if s[k].isWhitespace { k += 1; continue }
            if let e = quoteEnd(s, k) {
                let inner = String(s[(k + 1)..<e]).trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(Tok(raw: inner, norm: "", quoted: true, start: base + k, end: base + e + 1))
                k = e + 1
                continue
            }
            var e = k
            while e < s.count && !s[e].isWhitespace { e += 1 }
            let start = base + k, end = base + e
            var word = Array(s[k..<e])
            k = e
            if word.allSatisfy({ markChars.contains($0) }) {
                if lit(start, end, false) {
                    out.append(Tok(raw: String(word), norm: "", quoted: false, lit: true, own: true, start: start, end: end))
                } else {
                    out.append(Tok(raw: "", norm: "", quoted: false, used: true, key: true, marks: [(start, end)], start: start, end: end))
                }
                continue
            }
            var key = false, pre = "", suf = "", ws = start, we = end
            var marks: [(Int, Int)] = []
            var t = 0
            while t < word.count && (word[word.count - 1 - t] == "!" || word[word.count - 1 - t] == "★") { t += 1 }
            if t > 0 {
                let ms = String(word.suffix(t)); word.removeLast(t); we = end - t
                if lit(we, end, false) { suf = ms } else { key = true; marks.append((we, end)) }
            }
            var l = 0
            while l < word.count && word[l] == "★" { l += 1 }
            if l > 0 {
                let mp = String(word.prefix(l)); word.removeFirst(l); ws = start + l
                if lit(start, ws, false) { pre = mp } else { key = true; marks.append((start, ws)) }
            }
            let raw = String(word)
            let isLit = lit(ws, we, false)
            out.append(Tok(raw: raw, norm: isLit ? "" : normOf(raw), quoted: false, lit: isLit, key: key, marks: marks, pre: pre, suf: suf, start: ws, end: we))
        }
        return out
    }

    // MARK: one line (a task or a subtask)

    struct LineResult {
        var title: String
        var facts: CaptureFacts
        var flags: [CaptureFlag]
        var match: String
        var tags: [String]
        var spans: [CaptureSpan]
    }

    static func isTag(_ w: String) -> Bool {
        guard w.hasPrefix("#") else { return false }
        var letter = false
        for u in w.unicodeScalars.dropFirst() {
            if isLetter(u) { letter = true; continue }
            if isNumber(u) || u == "_" || u == "/" || u == "-" { continue }
            return false
        }
        return letter
    }

    static func parseOne(_ text: [Character], today: String, plan ctxPlan: String?, base: Int, lit: @escaping Lit) -> LineResult {
        var T = tokenize(text, base: base, lit: lit)
        var spans: [CaptureSpan] = []
        var facts = CaptureFacts()
        var flags: [CaptureFlag] = []
        var tags: [String] = []
        var plans: [String] = []
        var matchExtra: [String] = []
        let key = T.contains { $0.key }
        for t in T { for (a, b) in t.marks { spans.append(CaptureSpan(start: a, end: b, kind: .key)) } }
        var time: (time: String, text: String)?
        var timeSpan: Int?
        var dueEnd = -1
        var waitPhrase = ""

        func isFree(_ j: Int) -> Bool { j >= 0 && j < T.count && !T[j].used && !T[j].quoted && !T[j].norm.isEmpty }
        // the parts of the line a fact used: one span per fact, from its first word to its last
        func take(_ i: Int, _ n: Int, _ kind: CaptureSpan.Kind, tag: String? = nil) {
            for k in i..<(i + n) { T[k].used = true }
            spans.append(CaptureSpan(start: T[i].start, end: T[i + n - 1].end, kind: kind, tag: tag))
        }
        func words(_ i: Int, _ n: Int) -> String { T[i..<(i + n)].map(\.raw).joined(separator: " ") }

        // a date starting at token j: the longest run of up to 5 words (a weekday may lead a full date: "fri 13 nov")
        func dateAt(_ j: Int, _ pre: String?) -> (date: String, n: Int)? {
            if j > 0 && j - 1 < T.count && T[j - 1].norm == "last" { return nil } // "last fri recap" looks back
            var n = min(5, T.count - j)
            while n >= 1 {
                defer { n -= 1 }
                if !(j..<(j + n)).allSatisfy({ isFree($0) }) { continue }
                let ws = T[j..<(j + n)].map(\.norm)
                let s = ws.joined(separator: " ")
                if ws.contains(where: { $0.contains("/") }) || notDates.contains(s) || CaptureRx.test(#"(^| )(ago|yesterday|yday|last)( |$)"#, s) { continue }
                if CaptureRx.test(#"^(?!next |this )\S+ (days?|weeks?|months?|years?)$"#, s) { continue } // "3 days" stays words: "in 3 days" is the date
                if n == 1 && ambiguous.contains(s) && !safePrefix.contains(pre ?? "") { continue }
                var date = parseNaturalDate(s, today: today)
                if date == nil && n >= 3 && dayOf(ws[0]) >= 0 && s.contains(where: { $0.isASCII && $0.isNumber }) {
                    date = parseNaturalDate(ws.dropFirst().joined(separator: " "), today: today)
                }
                if let d = date { return (d, n) }
            }
            return nil
        }
        func timeAt(_ j: Int) -> (time: String, n: Int)? {
            guard isFree(j) else { return nil }
            if let t = timeOf(T[j].norm) { return (t, 1) }
            if CaptureRx.test(#"^[0-9]{1,2}(:[0-9]{2})?$"#, T[j].norm) && isFree(j + 1) && (T[j + 1].norm == "am" || T[j + 1].norm == "pm"),
               let t2 = timeOf(T[j].norm + T[j + 1].norm) { return (t2, 2) }
            return nil
        }
        func estAt(_ j: Int) -> (mins: Int, n: Int)? {
            guard isFree(j) else { return nil }
            if let e = estimateOf(T[j].norm) { return (e, 1) }
            if CaptureRx.test(#"^~?[0-9]+(\.[0-9]+)?$"#, T[j].norm) && isFree(j + 1)
                && (hourUnits.contains(T[j + 1].norm) || minuteUnits.contains(T[j + 1].norm)),
               let e2 = estimateOf(T[j].norm + T[j + 1].norm) { return (e2, 2) }
            return nil
        }
        func isFact(_ j: Int) -> Bool {
            guard j >= 0 && j < T.count else { return false }
            return dateAt(j, nil) != nil || timeAt(j) != nil || estAt(j) != nil || dueWords.contains(T[j].norm) || planWords.contains(T[j].norm)
        }
        func setDue(_ date: String, _ text: String) {
            facts.due = date
            if date < today { flags.append(CaptureFlag(code: .pastDate, text: text, date: date)) }
        }
        func setTime(_ t: (time: String, n: Int), _ i: Int, _ n: Int, _ deadline: Bool) {
            if deadline { flags.append(CaptureFlag(code: .timeDropped, text: words(i, n), time: t.time)) }
            else { time = (t.time, words(i, n)) }
        }

        var i = 0
        while i < T.count {
            defer { i += 1 }
            if !isFree(i) { continue }
            let w = T[i].norm
            let nw: String? = isFree(i + 1) ? T[i + 1].norm : nil
            // #tag (a workstream when it names one; the caller decides)
            if isTag(w) {
                var c = Array(T[i].raw)
                while let f = c.first, leadPunct.contains(f) { c.removeFirst() }
                if c.first == "#" { c.removeFirst() }
                while let l = c.last, trailPunct.contains(l) { c.removeLast() }
                let tg = String(c)
                if !tags.contains(tg) { tags.append(tg) }
                take(i, 1, .tag, tag: tg)
                continue
            }
            // waiting on / wait for <person>: the next word (two after Mr, Ms, Dr...), then capitalised words, up to 4, until a fact
            if facts.waiting == nil && (w == "waiting" || w == "wait") && (nw == "on" || nw == "for") && isFree(i + 2)
                && !notPeople.contains(T[i + 2].norm) && !isFact(i + 2) {
                var j = i + 3
                if honorific.contains(T[i + 2].norm) && isFree(j) { j += 1 }
                while j - (i + 2) < 4 && isFree(j) && startsUpper(T[j].raw) && !isFact(j) { j += 1 }
                let who = trimTrailing(T[(i + 2)..<j].map(\.raw).joined(separator: " "), ",.;:")
                facts.waiting = CaptureWaiting(on: who, since: today)
                matchExtra.append(who)
                waitPhrase = trimTrailing(words(i, j - i), ",.;:")
                take(i, j - i, .waiting)
                i = j - 1
                continue
            }
            // repeat
            if facts.every == nil && (w == "daily" || w == "weekly") {
                facts.every = CaptureRepeat(freq: w == "daily" ? "day" : "week"); take(i, 1, .every); continue
            }
            if facts.every == nil && w == "every", let nw {
                let k = dayOf(nw)
                var every: CaptureRepeat?
                if nw == "day" { every = CaptureRepeat(freq: "day") }
                else if nw == "week" { every = CaptureRepeat(freq: "week") }
                else if nw == "weekday" || nw == "weekdays" { every = CaptureRepeat(freq: "weekdays") }
                else if k >= 0 { every = CaptureRepeat(freq: "week", on: String(dayNames[k].prefix(3))) }
                if let every { facts.every = every; take(i, 2, .every); i += 1; continue }
            }
            // estimate ("for 45m" too)
            if facts.est == nil {
                let own = estAt(i)
                if let e = own ?? (w == "for" ? estAt(i + 1) : nil) {
                    let n = own != nil ? e.n : e.n + 1
                    facts.est = estToken(e.mins); take(i, n, .est); i += n - 1; continue
                }
            }
            // time ("at 4pm" too)
            if time == nil {
                let at = w == "at" ? timeAt(i + 1) : nil
                if let t = at ?? timeAt(i) {
                    let dropped = dueEnd == i
                    setTime(t, at != nil ? i + 1 : i, t.n, dropped)
                    let n = t.n + (at != nil ? 1 : 0)
                    take(i, n, dropped ? .dropped : .time)
                    if !dropped { timeSpan = spans.count - 1 }
                    i += n - 1
                    continue
                }
            }
            // dates, after by / due / for / before (the deadline) or on / do (a planned day), or bare (the deadline)
            let pre: CaptureSpan.Kind? = dueWords.contains(w) ? .due : planWords.contains(w) ? .plan : nil
            if let pre {
                if let hit = dateAt(i + 1, w), pre == .plan || facts.due == nil {
                    if pre == .due { setDue(hit.date, words(i + 1, hit.n)); dueEnd = i + 1 + hit.n }
                    else if !plans.contains(hit.date) { plans.append(hit.date) }
                    take(i, 1 + hit.n, pre); i += hit.n; continue
                }
                // "by 5pm" (today) and "by 5pm fri": a deadline with a time, which is dropped
                if w != "for" && pre == .due && facts.due == nil, let t = timeAt(i + 1) {
                    let after = dateAt(i + 1 + t.n, nil)
                    setDue(after?.date ?? today, after.map { words(i + 1 + t.n, $0.n) } ?? "today")
                    setTime(t, i + 1, t.n, true)
                    let n = 1 + t.n + (after?.n ?? 0)
                    take(i, n, .due); i += n - 1; continue
                }
            }
            if facts.due == nil, let hit = dateAt(i, nil) {
                setDue(hit.date, words(i, hit.n)); take(i, hit.n, .due); i += hit.n - 1; dueEnd = i + 1; continue
            }
            if ambiguous.contains(w) && T[i].raw != T[i].raw.uppercased() { flags.append(CaptureFlag(code: .ambiguous, text: T[i].raw)) } // "SAT" is plainly the word
        }

        // the planned days: the typed ones, else the context's day; a time goes on the first, or on today when there is no date at all
        // (on the next of its day for "every fri 4pm")
        var days = plans
        if days.isEmpty, let c = ctxPlan { days = [c] }
        if let time {
            if !days.isEmpty { days[0] = days[0] + " " + time.time }
            else if facts.due != nil {
                flags.append(CaptureFlag(code: .timeDropped, text: time.text, time: time.time))
                if let ts = timeSpan { spans[ts].kind = .dropped }
            } else if let on = facts.every?.on, let d = parseNaturalDate("this " + on, today: today) { days.append(d + " " + time.time) }
            else { days.append(today + " " + time.time) }
        }
        facts.key = key
        facts.plan = days
        facts.tags = tags

        // the title: what is left, as typed (quote marks gone; a ! or ★ taken back stays on its word), loose punctuation at the ends trimmed
        var title = ""
        for t in T {
            let piece = t.pre + (t.used ? "" : t.raw) + t.suf
            if piece.isEmpty { continue }
            if !title.isEmpty && (t.own || !piece.allSatisfy({ ",.;:!?)]".contains($0) })) { title += " " }
            title += piece
        }
        title = trimEnds(title)
        if title.isEmpty && !waitPhrase.isEmpty { title = waitPhrase } // "waiting on Mr Daniel" alone keeps the phrase as its title
        if title.isEmpty { flags.append(CaptureFlag(code: .noTitle)) }
        let match = (T.filter { !$0.used && !$0.quoted && !$0.lit && !$0.raw.isEmpty }.map(\.raw) + matchExtra).joined(separator: " ")
        return LineResult(title: title, facts: facts, flags: flags, match: match, tags: tags, spans: spans)
    }

    // MARK: the API

    /// The laptop's parseTask. `today` "YYYY-MM-DD"; `plan`: the day a context plans the task for (a typed planned day replaces it);
    /// `workstreamTag(tag)`: true when a #tag names a workstream (the first such tag leaves `facts.tags` and becomes `workstreamTag`);
    /// `commands` false reads a leading / or > as part of a task (the iPad has no Claude panel or palette).
    public static func parse(_ text: String, today: String, plan: String? = nil, workstreamTag: ((String) -> Bool)? = nil,
                             ignore: [CaptureIgnore] = [], commands: Bool = true) -> CaptureParsed {
        let src = Array(text)
        var lo = 0, hi = src.count
        while lo < hi && src[lo].isWhitespace { lo += 1 }
        while hi > lo && src[hi - 1].isWhitespace { hi -= 1 }
        if lo == hi { return CaptureParsed(kind: .empty) }
        let raw = Array(src[lo..<hi])
        if commands && (raw[0] == "/" || raw[0] == ">") {
            var p = CaptureParsed(kind: raw[0] == "/" ? .claude : .palette); p.text = String(raw); return p
        }
        let ign = ignore.filter { $0.end > $0.start }
        let lit: Lit = { a, b, sep in ign.contains { g in (sep ? g.kind == .sub : g.kind != .sub) && g.start < b && a < g.end } }
        let split = splitParts(raw, base: lo, lit: lit)
        let head = split.parts[0]
        var main = parseOne(head.text, today: today, plan: plan, base: head.base, lit: lit)
        var spans = main.spans.map { s -> CaptureSpan in var c = s; c.part = 0; return c }
        for at in split.seps { spans.append(CaptureSpan(start: at, end: at + 1, kind: .sub)) }
        var subtasks: [CaptureSubtask] = []
        for s in split.parts.dropFirst() {
            if String(s.text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let p = parseOne(s.text, today: today, plan: nil, base: s.base, lit: lit)
            for sp in p.spans { var c = sp; c.part = subtasks.count + 1; spans.append(c) }
            subtasks.append(CaptureSubtask(ok: !p.title.isEmpty, title: p.title, facts: p.facts, flags: p.flags))
        }
        var wsTag: String?
        if let wt = workstreamTag, !main.facts.tags.isEmpty {
            wsTag = main.facts.tags.first(where: wt)
            if let w = wsTag { main.facts.tags.removeAll { $0 == w } }
        }
        if let w = wsTag { for k in spans.indices where spans[k].part == 0 && spans[k].kind == .tag && spans[k].tag == w { spans[k].kind = .ws } }
        spans.sort { $0.start < $1.start }
        var out = CaptureParsed(kind: .task)
        out.ok = !main.title.isEmpty
        out.title = main.title
        out.facts = main.facts
        out.subtasks = subtasks
        out.flags = main.flags
        out.matchText = main.match
        out.matchTags = main.tags
        out.workstreamTag = wsTag
        out.spans = spans
        return out
    }

    /// The laptop's captureland.parseLine: `parse` with the folder deciding which #tag names a workstream, and "@fri" (the old capture
    /// mark, only at a word's start, so "bob@x.com" is left alone) read as "by fri". Spans and `ignore` stay in the typed text's positions.
    public static func parseLine(_ text: String, in snapshot: Snapshot?, today: String, plan: String? = nil,
                                 ignore: [CaptureIgnore] = [], commands: Bool = true) -> CaptureParsed {
        var wt: ((String) -> Bool)?
        if let snap = snapshot { wt = { (t: String) -> Bool in tagWorkstream(t, in: snap) != nil } }
        let s = Array(text)
        let atMarks = (0..<s.count).filter { k in
            s[k] == "@" && (k == 0 || s[k - 1].isWhitespace) && k + 1 < s.count && (s[k + 1].isLetter || s[k + 1].isNumber)
        }
        if atMarks.isEmpty { return parse(text, today: today, plan: plan, workstreamTag: wt, ignore: ignore, commands: commands) }
        // "@" -> "by ", with the way back: fwd[i] is where the typed i-th character went, back[j] where the j-th came from
        var out: [Character] = [], back: [Int] = [], fwd = [Int](repeating: 0, count: s.count + 1), k = 0
        for at in atMarks {
            if ignore.contains(where: { $0.kind != .sub && $0.start <= at && at < $0.end }) { continue } // taken back: "@fri" stays as typed
            while k < at { fwd[k] = out.count; back.append(k); out.append(s[k]); k += 1 }
            fwd[k] = out.count; back.append(contentsOf: [k, k, k]); out.append(contentsOf: Array("by ")); k += 1
        }
        while k < s.count { fwd[k] = out.count; back.append(k); out.append(s[k]); k += 1 }
        fwd[s.count] = out.count; back.append(s.count)
        let clamp = { (v: Int) in max(0, min(s.count, v)) }
        let ign = ignore.map { CaptureIgnore(start: fwd[clamp($0.start)], end: fwd[clamp($0.end)], kind: $0.kind) }
        var p = parse(String(out), today: today, plan: plan, workstreamTag: wt, ignore: ign, commands: commands)
        p.spans = p.spans.map { sp in
            var c = sp
            c.start = back[sp.start]
            c.end = sp.end > sp.start ? back[sp.end - 1] + 1 : back[sp.start]
            return c
        }
        return p
    }

    // MARK: helpers

    static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
    static func isLetter(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }
    static func isNumber(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }
    static func startsUpper(_ s: String) -> Bool { s.unicodeScalars.first.map { $0.properties.generalCategory == .uppercaseLetter } ?? false }
    static func trimTrailing(_ s: String, _ chars: String) -> String {
        var c = Array(s)
        while let l = c.last, chars.contains(l) { c.removeLast() }
        return String(c)
    }
    /// trims whitespace and , ; : – — - from both ends
    static func trimEnds(_ s: String) -> String {
        let loose = ",;:\u{2013}\u{2014}-"
        var c = Array(s)
        while let f = c.first, f.isWhitespace || loose.contains(f) { c.removeFirst() }
        while let l = c.last, l.isWhitespace || loose.contains(l) { c.removeLast() }
        return String(c)
    }
}

// MARK: - Days in words (dates.js)

extension CaptureParse {
    static let numberWords: [String: Int] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
                                             "eight": 8, "nine": 9, "ten": 10, "couple": 2]
    static func countOf(_ s: String) -> Int? {
        // (at most 6 digits, so the day arithmetic below never overflows)
        if !s.isEmpty && s.allSatisfy({ $0.isASCII && $0.isNumber }) { return s.count <= 6 ? Int(s) : nil }
        return numberWords[s]
    }
    static func dowIndex(_ w: String) -> Int { dayNames.firstIndex { $0 == w || (w.count >= 3 && $0.hasPrefix(w)) } ?? -1 }
    static func monIndex(_ w: String) -> Int { monthNames.firstIndex { $0 == w || (w.count >= 3 && $0.hasPrefix(w)) } ?? -1 }

    // plain day arithmetic (no Calendar, no time zone): days since 1970-01-01, and back
    static func dayNumber(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
    static func civil(_ n: Int) -> (y: Int, m: Int, d: Int) {
        let z = n + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
    static func isoOf(_ y: Int, _ m: Int, _ d: Int) -> String {
        let ys = String(y)
        return String(repeating: "0", count: max(0, 4 - ys.count)) + ys + "-" + pad2(m) + "-" + pad2(d)
    }
    static func isoOf(_ n: Int) -> String { let c = civil(n); return isoOf(c.y, c.m, c.d) }
    static func partsOf(_ iso: String) -> (y: Int, m: Int, d: Int)? {
        let p = iso.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return (y, m, d)
    }
    static func daysIn(_ y: Int, _ m: Int) -> Int {
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(0, min(11, m - 1))]
    }
    /// JavaScript's new Date(y, m0, d): a month or day out of range rolls over.
    static func rolled(_ y: Int, _ m0: Int, _ d: Int) -> Int {
        let yy = y + (m0 >= 0 ? m0 / 12 : -((11 - m0) / 12))
        let mm = ((m0 % 12) + 12) % 12
        return dayNumber(yy, mm + 1, 1) + d - 1
    }
    /// 0 = Sunday ... 6 = Saturday
    static func weekdayOf(_ n: Int) -> Int { (((n % 7) + 7) % 7 + 4) % 7 }

    /// "tomorrow", "next fri", "in 3 weeks", "oct 12", "12th of october", "2026-11-01", "next week" (its Monday), "eow" (the coming
    /// Sunday), "weekend", "eom", "eoy", "3 days ago", "10/12" -> "YYYY-MM-DD" from `today`, else nil.
    public static func parseNaturalDate(_ input: String, today: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if let l = s.last, l == "." || l == "," { s.removeLast() }
        guard !s.isEmpty, let tp = partsOf(today) else { return nil }
        let t = dayNumber(tp.y, tp.m, tp.d)
        let dow = weekdayOf(t)
        if let g = CaptureRx.groups(#"^([0-9]{4})-([0-9]{2})-([0-9]{2})$"#, s), let y = Int(g[1] ?? ""), let m = Int(g[2] ?? ""), let d = Int(g[3] ?? "") {
            guard m >= 1 && m <= 12 && d >= 1 && d <= daysIn(y, m) else { return nil }
            return isoOf(y, m, d)
        }
        switch s {
        case "today", "now", "tod", "tonight": return isoOf(t)
        case "tomorrow", "tmrw", "tom", "tmr": return isoOf(t + 1)
        case "yesterday", "yday": return isoOf(t - 1)
        case "eow", "end of week": return isoOf(t + (7 - dow) % 7)
        case "next week": return isoOf(t + 7 - (dow + 6) % 7) // the Monday that starts it
        case "weekend", "this weekend": return isoOf(t + (dow == 0 ? 0 : 6 - dow)) // the coming Saturday (today on a Saturday or a Sunday)
        case "eom", "end of month": return isoOf(rolled(tp.y, tp.m, 0))
        case "eoy", "end of year": return isoOf(tp.y, 12, 31)
        default: break
        }
        if let g = CaptureRx.groups(#"^(?:in )?([A-Za-z0-9_]+) (day|days|week|weeks|month|months|year|years)(?: from now)?$"#, s),
           let n = countOf(g[1] ?? ""), let unit = g[2] {
            if unit.hasPrefix("day") { return isoOf(t + n) }
            if unit.hasPrefix("week") { return isoOf(t + 7 * n) }
            if unit.hasPrefix("month") { return isoOf(rolled(tp.y, tp.m - 1 + n, tp.d)) }
            return isoOf(rolled(tp.y + n, tp.m - 1, tp.d))
        }
        if let g = CaptureRx.groups(#"^([A-Za-z0-9_]+) (day|days|week|weeks) ago$"#, s), let n = countOf(g[1] ?? "") {
            return isoOf(t - n * ((g[2] ?? "").hasPrefix("week") ? 7 : 1))
        }
        if let g = CaptureRx.groups(#"^(next|this|last|coming)? ?([a-z]{3,9})$"#, s), let w = g[2], dowIndex(w) >= 0 {
            let target = dowIndex(w), mod = g[1] ?? ""
            let fwd = (target - dow + 7) % 7
            // bare weekday and "next": strictly after today. "this": today or later. "last": strictly before today.
            let diff = mod == "this" ? fwd : mod == "last" ? (fwd == 0 ? -7 : fwd - 7) : (fwd == 0 ? 7 : fwd)
            return isoOf(t + diff)
        }
        // "oct 12", "12 oct", "october 12 2026", "12th of october"
        if let g = CaptureRx.groups(#"^([a-z]{3,9}) ([0-9]{1,2})(?:st|nd|rd|th)?(?:,? ([0-9]{4}))?$"#, s), let w = g[1], monIndex(w) >= 0, let d = Int(g[2] ?? "") {
            return fromMD(t, monIndex(w), d, g[3].flatMap { Int($0) })
        }
        if let g = CaptureRx.groups(#"^([0-9]{1,2})(?:st|nd|rd|th)? (?:of )?([a-z]{3,9})(?:,? ([0-9]{4}))?$"#, s), let w = g[2], monIndex(w) >= 0, let d = Int(g[1] ?? "") {
            return fromMD(t, monIndex(w), d, g[3].flatMap { Int($0) })
        }
        if let g = CaptureRx.groups(#"^([0-9]{1,2})/([0-9]{1,2})(?:/([0-9]{2,4}))?$"#, s), let m = Int(g[1] ?? ""), let d = Int(g[2] ?? "") {
            let y = g[3].flatMap { ys in Int(ys).map { ys.count == 2 ? 2000 + $0 : $0 } }
            return fromMD(t, m - 1, d, y)
        }
        return nil
    }

    /// A month (0-based) and day; with no year, the next time it comes round.
    static func fromMD(_ today: Int, _ mon: Int, _ day: Int, _ year: Int?) -> String? {
        guard mon >= 0 && mon <= 11 && day >= 1 && day <= 31 else { return nil }
        let y = year ?? civil(today).y
        guard day <= daysIn(y, mon + 1) else { return nil }
        let n = dayNumber(y, mon + 1, day)
        if year == nil && n < today { return isoOf(rolled(y + 1, mon, day)) }
        return isoOf(n)
    }
}

// MARK: - Which workstream the words name (vindex.js matchCapture, captureland.js)

public struct CaptureCandidate: Equatable {
    public var workstream: Workstream
    /// "fullname", "id", "alias", "name", "start" or "group"
    public var how: String
    /// the words it matched, in the order typed
    public var words: [String]
}

public struct CaptureMatch: Equatable {
    /// the best match, or nil (the Inbox)
    public var workstream: Workstream?
    /// the others, best first
    public var alternatives: [Workstream]
    public var matches: [CaptureCandidate]
}

public struct CaptureLanding: Equatable {
    public enum How: String { case tag, words, context, inbox }
    /// where it goes; nil = the Inbox
    public var workstream: Workstream?
    public var how: How
    /// a guess from the words (the laptop draws its chip outlined)
    public var guessed: Bool { how == .words }
    /// the words the guess came from ("phys")
    public var from: String
    /// the task file it is written into
    public var file: String
    public var label: String
    /// the other places it could go, in the laptop's Tab order: the guess, workstreams sharing its first word, the last used, the Inbox (nil)
    public var alternatives: [Workstream?]
}

extension CaptureParse {
    /// everyday words that never match a name (or the start of one): "call the dentist" must not land in Theory of Knowledge.
    /// An id or alias still matches exactly.
    static let stopWords: Set<String> = Set(("the and for with from into onto over about this that these those then than are was were has have had not but all any "
        + "can get got one out our you your its his her him she they them who why how what when where which will would should could may might must "
        + "also just only very more most some such each both few now off too via per due ask buy see let put set use try").split(separator: " ").map(String.init))

    static func isAZ09(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
    /// a name's words: lower case, split on anything that is not a-z or 0-9
    static func nameWords(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !isAZ09($0) }).map(String.init)
    }
    /// The words of a line that can name a workstream: quoted runs, @, # and / words left out, ends trimmed to a-z 0-9.
    static func captureWords(_ text: String) -> [String] {
        let s = CaptureRx.replace(#""[^"]*"|“[^”]*”|'[^']*'(?=\s|$)"#, in: text, with: " ")
        return s.split(whereSeparator: { $0.isWhitespace }).compactMap { w -> String? in
            guard let f = w.first, f != "@", f != "#", f != "/" else { return nil }
            var c = Array(w.lowercased())
            while let x = c.first, !isAZ09(x) { c.removeFirst() }
            while let x = c.last, !isAZ09(x) { c.removeLast() }
            return c.isEmpty ? nil : String(c)
        }
    }

    /// Every workstream in sidebar order (groups in order, each group's workstreams).
    static func sidebar(_ s: Snapshot) -> [Workstream] { s.groups.flatMap { s.workstreams(in: $0) } }

    /// A group's `default:` workstream (an id in the group, or a folder name in it), or nil.
    public static func groupDefault(_ g: WorkGroup, in s: Snapshot) -> Workstream? {
        guard let d = g.defaultWorkstream, !d.isEmpty else { return nil }
        if let w = s.workstreams[d], w.group == g.id { return w }
        return s.workstreams.values.first { $0.folder == g.id + "/" + d }
    }

    /// Which workstream the words name: its id, an alias, its whole name, a word or the start of a word of its name (3 letters or
    /// more, not an everyday word); a group's id, label or the start of a word of its label names the group's default workstream.
    /// Whole words; the strongest kind of match, then the most words, then active ones, then the earliest word, then sidebar order.
    public static func matchCapture(_ text: String, in s: Snapshot) -> CaptureMatch {
        let words = captureWords(text)
        let all = sidebar(s)
        var order: [String: Int] = [:]
        for (k, w) in all.enumerated() where order[w.id] == nil { order[w.id] = k }
        struct Cand { var ws: Workstream; var tier: Int; var how: String; var words: Set<Int>; var first: Int }
        var cand: [String: Cand] = [:]
        var seen: [String] = []
        func add(_ ws: Workstream?, _ tier: Int, _ wi: Int, _ how: String) {
            guard let ws else { return }
            var c = cand[ws.id] ?? Cand(ws: ws, tier: 9, how: "", words: [], first: wi)
            if cand[ws.id] == nil { seen.append(ws.id) }
            if tier < c.tier { c.tier = tier; c.how = how }
            c.words.insert(wi); c.first = min(c.first, wi)
            cand[ws.id] = c
        }
        // a workstream's whole name typed out ("physics ia", "chemistry ee") is as explicit as its id, short words included
        for ws in all {
            let nw = nameWords(ws.name)
            guard nw.count >= 2, nw.count <= words.count else { continue }
            for i in 0...(words.count - nw.count) where (0..<nw.count).allSatisfy({ words[i + $0] == nw[$0] }) {
                for k in 0..<nw.count { add(ws, 0, i + k, "fullname") }
                break
            }
        }
        for (wi, w) in words.enumerated() {
            let loose = w.count >= 3 && !stopWords.contains(w)
            for ws in all {
                if ws.id.lowercased() == w { add(ws, 0, wi, "id") }
                else if ws.aliases.contains(where: { $0.lowercased() == w }) { add(ws, 0, wi, "alias") }
                else if loose {
                    let nw = nameWords(ws.name)
                    if nw.contains(w) { add(ws, 1, wi, "name") } else if nw.contains(where: { $0.hasPrefix(w) }) { add(ws, 2, wi, "start") }
                }
            }
            for g in s.groups {
                guard let def = groupDefault(g, in: s) else { continue }
                if g.id.lowercased() == w || g.label.lowercased() == w { add(def, 0, wi, "group") }
                else if loose {
                    let nw = nameWords(g.label)
                    if nw.contains(w) { add(def, 1, wi, "group") } else if nw.contains(where: { $0.hasPrefix(w) }) { add(def, 2, wi, "group") }
                }
            }
        }
        let ranked = seen.compactMap { cand[$0] }.sorted { a, b in
            if a.tier != b.tier { return a.tier < b.tier }
            if a.words.count != b.words.count { return a.words.count > b.words.count }
            let aa = a.ws.status == "active" ? 0 : 1, ba = b.ws.status == "active" ? 0 : 1
            if aa != ba { return aa < ba }
            if a.first != b.first { return a.first < b.first }
            return (order[a.ws.id] ?? Int.max) < (order[b.ws.id] ?? Int.max)
        }
        let matches = ranked.map { c in CaptureCandidate(workstream: c.ws, how: c.how, words: c.words.sorted().map { words[$0] }) }
        return CaptureMatch(workstream: matches.first?.workstream, alternatives: matches.dropFirst().map(\.workstream), matches: matches)
    }

    /// The workstream a #tag names ("#physics-hl" reads as "physics hl"), or nil.
    public static func tagWorkstream(_ tag: String, in s: Snapshot) -> Workstream? {
        guard !tag.isEmpty else { return nil }
        let words = CaptureRx.replace(#"[_\-]+"#, in: tag, with: " ")
        return matchCapture(words, in: s).workstream
    }

    static func firstWord(_ name: String) -> String { nameWords(name).first ?? "" }

    /// Where a parsed line lands: a #tag naming a workstream, then the words, then the context's workstream (the page it was added
    /// from), then the Inbox. `recent`: the last workstreams used (ids), for the alternatives.
    public static func land(_ p: CaptureParsed, in s: Snapshot, context: String? = nil, recent: [String] = []) -> CaptureLanding {
        var ws: Workstream?
        var how = CaptureLanding.How.inbox
        var from: [String] = []
        if let tag = p.workstreamTag, let w = tagWorkstream(tag, in: s) { ws = w; how = .tag }
        if ws == nil && p.kind == .task {
            let m = matchCapture(p.matchText, in: s)
            if let w = m.workstream { ws = w; how = .words; from = m.matches[0].words }
        }
        if ws == nil, let c = context, let w = s.workstreams[c] { ws = w; how = .context }
        var alts: [Workstream?] = []
        func push(_ w: Workstream?) { if !alts.contains(where: { $0?.id == w?.id }) { alts.append(w) } }
        if let g = ws {
            push(g)
            let fw = firstWord(g.name)
            if !fw.isEmpty { for o in sidebar(s) where o.id != g.id && !o.parked && firstWord(o.name) == fw { push(o) } }
        } else { push(nil) }
        for id in recent.prefix(3) { if let w = s.workstreams[id] { push(w) } }
        push(nil)
        return CaptureLanding(workstream: ws, how: how, from: how == .words ? from.joined(separator: " ") : "",
                              file: ws?.tasksFile ?? "inbox.yaml", label: ws?.name ?? "Inbox", alternatives: alts)
    }
}

// MARK: - The preview's wording (capturechips.js)

public struct CaptureChip: Equatable {
    public enum Kind: String { case ws, due, dropped, plan, est, key, every, waiting, tag, subs }
    public var kind: Kind
    public var text: String
    /// the workstream chip: " from “phys”" for a guess, " this page" for the context's workstream, else ""
    public var tail = ""
    /// the workstream chip: its id (nil = the Inbox)
    public var workstream: String?
}

extension CaptureParse {
    /// "today", "tomorrow", else "Fri 30 Oct"
    public static func dayWords(_ iso: String, today: String) -> String {
        if iso == today { return "today" }
        if let tp = partsOf(today), iso == isoOf(dayNumber(tp.y, tp.m, tp.d) + 1) { return "tomorrow" }
        return Days.label(iso)
    }

    /// One chip per fact, in the laptop's order: the workstream (or "Inbox"), the deadline, a dropped time, planned days, estimate,
    /// "★ key date", repeat, waiting, #tags, "3 subtasks".
    public static func chips(_ p: CaptureParsed, landing: CaptureLanding?, today: String) -> [CaptureChip] {
        guard p.kind == .task else { return [] }
        var out: [CaptureChip] = []
        let f = p.facts
        if let land = landing {
            let tail = land.guessed && !land.from.isEmpty ? " from “\(land.from)”" : land.how == .context ? " this page" : ""
            out.append(CaptureChip(kind: .ws, text: land.label, tail: tail, workstream: land.workstream?.id))
        }
        if let due = f.due {
            var t = "due " + dayWords(due, today: today)
            if let a = partsOf(today), let b = partsOf(due) {
                let n = dayNumber(b.y, b.m, b.d) - dayNumber(a.y, a.m, a.d)
                if n >= 2 { t += " · in \(n) days" }
            }
            out.append(CaptureChip(kind: .due, text: t))
        }
        for fl in p.flags where fl.code == .timeDropped { out.append(CaptureChip(kind: .dropped, text: fl.text ?? fl.time ?? "")) }
        for pl in f.plan {
            let parts = pl.split(separator: " ").map(String.init)
            out.append(CaptureChip(kind: .plan, text: "on " + dayWords(parts.first ?? pl, today: today) + (parts.count > 1 ? " " + parts[1] : "")))
        }
        if let est = f.est { out.append(CaptureChip(kind: .est, text: est)) }
        if f.key { out.append(CaptureChip(kind: .key, text: "★ key date")) }
        if let e = f.every {
            let text = e.on.map { "every " + $0 } ?? (e.freq == "day" ? "daily" : e.freq == "weekdays" ? "every weekday" : e.freq == "week" ? "weekly" : "repeats")
            out.append(CaptureChip(kind: .every, text: text))
        }
        if let w = f.waiting { out.append(CaptureChip(kind: .waiting, text: "waiting on " + w.on)) }
        for t in f.tags { out.append(CaptureChip(kind: .tag, text: "#" + t)) }
        let subs = p.subtasksToAdd.count
        if subs > 0 { out.append(CaptureChip(kind: .subs, text: subs == 1 ? "1 subtask" : "\(subs) subtasks")) }
        return out
    }
}

// MARK: - Regular expressions, compiled once

enum CaptureRx {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    static func re(_ pattern: String) -> NSRegularExpression {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        // the patterns are constants of this file; a bad one is a programming error the tests catch
        let r = try! NSRegularExpression(pattern: pattern, options: [])
        cache[pattern] = r
        return r
    }

    /// The groups of the first match (0 = the whole match; nil for a group that took no part), or nil when it does not match.
    static func groups(_ pattern: String, _ s: String) -> [String?]? {
        guard let m = re(pattern).firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i -> String? in
            let r = m.range(at: i)
            guard r.location != NSNotFound, let rr = Range(r, in: s) else { return nil }
            return String(s[rr])
        }
    }

    static func test(_ pattern: String, _ s: String) -> Bool {
        re(pattern).firstMatch(in: s, options: [], range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func replace(_ pattern: String, in s: String, with template: String) -> String {
        re(pattern).stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}
