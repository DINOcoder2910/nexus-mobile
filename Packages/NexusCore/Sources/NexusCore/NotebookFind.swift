import Foundation

/// Finding a notebook or a board by its name (the sidebar's "Find a notebook or board" field and Move to…'s search), over every
/// notebook and board in the data folder, without opening a single level of the tree: the names come from the paths the sidebar's
/// walk already has (`NotebookScan`). Case, accents and the curly apostrophe don't matter; each word typed must be in the name or
/// in where it sits ("week 1 chem" finds Week 1 in Chemistry). The best come first: the name itself, a name that starts with what
/// was typed, every word at the start of a word of the name, every word in the name, then the ones matched by their place; among
/// equals, the ones opened lately (`recent`), notebooks before boards, the shallower, then by name.
public enum NotebookFind {
    public struct Entry: Hashable, Sendable, Identifiable {
        public enum Kind: Hashable, Sendable { case notebook, board }
        public var kind: Kind
        /// The folder, relative to the data folder ("notebooks/School/Chemistry/Week 1/Calorimetry.board").
        public var path: String
        /// "Calorimetry" (a board's name has no ".board").
        public var name: String
        /// Where it sits, without "notebooks": "School › Chemistry › Week 1"; empty for a top-level notebook.
        public var place: String
        /// 0 for a top-level notebook; a board is one deeper than its notebook.
        public var depth: Int
        let key: String
        let placeKey: String
        public var id: String { path }
        /// "School › Chemistry › Week 1" (where it sits, then its name).
        public var placeAndName: String { place.isEmpty ? name : place + " › " + name }

        public init(kind: Kind, path: String) {
            self.kind = kind
            self.path = path
            var parts = path.split(separator: "/").map(String.init)
            var last = parts.popLast() ?? path
            if kind == .board, last.lowercased().hasSuffix(".board") { last = String(last.dropLast(6)) }
            if parts.first == BoardFormat.notebooks { parts.removeFirst() }
            name = last
            place = parts.joined(separator: " › ")
            depth = parts.count
            key = NotebookFind.fold(last)
            placeKey = NotebookFind.fold(parts.joined(separator: " "))
        }
    }

    /// The entries for these notebook and board paths (notebooks first, each list in the order given).
    public static func entries(notebooks: [String], boards: [String]) -> [Entry] {
        notebooks.map { Entry(kind: .notebook, path: $0) } + boards.map { Entry(kind: .board, path: $0) }
    }

    /// Lower case, without accents, the curly apostrophe as a straight one, runs of spaces as one.
    public static func fold(_ s: String) -> String {
        let f = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
        return f.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The entries that match `query`, best first, at most `limit`. Nothing for an empty query.
    public static func search(_ query: String, in entries: [Entry], recent: [String] = [], limit: Int = 50) -> [Entry] {
        let q = fold(query)
        let terms = q.split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        var rank: [String: Int] = [:]
        for (i, p) in recent.enumerated() where rank[p] == nil { rank[p] = i }
        var scored: [(score: Int, entry: Entry)] = []
        for e in entries {
            guard let s = score(e, q, terms) else { continue }
            scored.append((s, e))
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score < b.score }
            let ra = rank[a.entry.path] ?? Int.max, rb = rank[b.entry.path] ?? Int.max
            if ra != rb { return ra < rb }
            if a.entry.kind != b.entry.kind { return a.entry.kind == .notebook }
            if a.entry.depth != b.entry.depth { return a.entry.depth < b.entry.depth }
            let byName = a.entry.name.localizedStandardCompare(b.entry.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return a.entry.path < b.entry.path
        }
        return scored.prefix(max(0, limit)).map(\.entry)
    }

    /// How well `e` matches (lower is better), or nil when a word typed is in neither its name nor its place.
    static func score(_ e: Entry, _ q: String, _ terms: [String]) -> Int? {
        var allInName = true
        for t in terms {
            if e.key.contains(t) { continue }
            guard e.placeKey.contains(t) else { return nil }
            allInName = false
        }
        if e.key == q { return 0 }
        if e.key.hasPrefix(q) { return 1 }
        guard allInName else { return 4 }
        if terms.allSatisfy({ atWordStart($0, in: e.key) }) { return 2 }
        return 3
    }

    /// Is `term` in `s` where a word starts (at the start, or after a space, a dash or any other mark)?
    static func atWordStart(_ term: String, in s: String) -> Bool {
        var from = s.startIndex
        while from < s.endIndex, let r = s.range(of: term, range: from..<s.endIndex) {
            if r.lowerBound == s.startIndex { return true }
            let before = s[s.index(before: r.lowerBound)]
            if !(before.isLetter || before.isNumber) { return true }
            from = s.index(after: r.lowerBound)
        }
        return false
    }
}

/// A short list of paths kept newest first (the sidebar's pinned notebooks and boards, Move to…'s recent places), as the app keeps
/// it in its settings ("a|b": `|` can't be in a Windows name), following a notebook or board that moved or was renamed.
public enum PathList {
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: "|").map(String.init).filter { seen.insert($0).inserted }
    }

    public static func join(_ list: [String]) -> String { list.joined(separator: "|") }

    /// `path` first, once, and at most `max` in all.
    public static func adding(_ path: String, to text: String, max: Int) -> String {
        var l = parse(text)
        l.removeAll { $0 == path }
        l.insert(path, at: 0)
        return join(Array(l.prefix(Swift.max(0, max))))
    }

    /// `path` at the end (pinned in the order they were pinned), or taken off when it is there.
    public static func toggling(_ path: String, in text: String) -> String {
        var l = parse(text)
        if l.contains(path) { l.removeAll { $0 == path } } else { l.append(path) }
        return join(l)
    }

    public static func removing(_ path: String, from text: String) -> String {
        join(parse(text).filter { $0 != path })
    }

    /// The paths after `from` moved or was renamed to `to`: it, and everything under it, follow.
    public static func renaming(_ from: String, to: String, in list: [String]) -> [String] {
        list.map { p in
            if p == from { return to }
            if p.hasPrefix(from + "/") { return to + p.dropFirst(from.count) }
            return p
        }
    }

    /// The same for the kept text; the same text when nothing in it moved.
    public static func renaming(_ from: String, to: String, in text: String) -> String {
        let l = parse(text)
        let moved = renaming(from, to: to, in: l)
        return moved == l ? text : join(moved)
    }
}
