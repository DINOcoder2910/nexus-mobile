import Foundation

/// An audio recording made while writing on a board (nexus docs/data-format.md "The board redesign's additions"): the sound is
/// `files/recording-<id>.m4a` (AAC, mono, about 32 kbps) and its timing is `recordings/<id>.json` in the board:
///
///     {"format": "nexus-recording/1", "id", "file": "files/recording-<id>.m4a", "started": ISO, "duration": seconds,
///      "marks": [{"stroke": "<id>", "at": 12.3}, {"item": "<id>", "text": "words typed", "at": 40.1}]}
///
/// `at` is seconds into the recording. Only the device that recorded writes it, so the hub never merges it; strokes and items don't
/// change. Tapping a stroke or a word plays from its mark; playback shows the notes appearing in step (`visibleStrokes`).
public struct BoardRecording: Equatable, Identifiable {
    public static let format = "nexus-recording/1"
    public static let dir = "recordings"

    public struct Mark: Equatable {
        public var stroke: String?
        public var item: String?
        public var text: String?
        public var at: Double
        public init(stroke: String? = nil, item: String? = nil, text: String? = nil, at: Double) {
            self.stroke = stroke; self.item = item; self.text = text; self.at = at
        }
    }

    public var id: String
    public var file: String
    public var started: String
    public var duration: Double
    public var marks: [Mark]
    /// The file as read (fields this app doesn't know are kept).
    public var raw: JSONValue?

    public init(id: String, started: Date = Date()) {
        self.id = id; file = BoardRecording.audioPath(id); self.started = TutorSession.iso(started); duration = 0; marks = []
    }

    public static func audioPath(_ id: String) -> String { "files/recording-\(id).m4a" }
    public static func jsonPath(_ id: String) -> String { "\(dir)/\(id).json" }

    // MARK: marking while recording

    /// A stroke written at `at` seconds in (kept once: the first time it is seen).
    public mutating func markStroke(_ id: String, at: Double) {
        guard !id.isEmpty, !marks.contains(where: { $0.stroke == id }) else { return }
        marks.append(Mark(stroke: id, at: BoardRecording.r1(at)))
    }

    /// Words typed into a block at `at` seconds in.
    public mutating func markTyped(item: String, text: String, at: Double) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, !t.isEmpty else { return }
        // typing goes on in small pieces: words added within 3 s of the last mark on the same block join it
        if let last = marks.last, last.item == item, at - last.at < 3, let lt = last.text {
            marks[marks.count - 1].text = lt + " " + t
            return
        }
        marks.append(Mark(item: item, text: t, at: BoardRecording.r1(at)))
    }

    static func r1(_ v: Double) -> Double { (max(0, v) * 10).rounded() / 10 }

    /// The words a block gained between two versions of its text (what was typed or pasted; nothing for a deletion).
    public static func addedText(old: String, new: String) -> String {
        let a = Array(old), b = Array(new)
        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        guard b.count - s > p else { return "" }
        // widen to whole words
        var lo = p, hi = b.count - s
        while lo > 0, !b[lo - 1].isWhitespace { lo -= 1 }
        while hi < b.count, !b[hi].isWhitespace { hi += 1 }
        return String(b[lo..<hi]).replacingOccurrences(of: #"[#*_`>\[\]]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    // MARK: playing back

    /// When a stroke was written, if during this recording.
    public func time(ofStroke id: String) -> Double? { marks.first { $0.stroke == id }?.at }

    /// When words in a block were typed: the mark on that block whose words contain `word` (the first such), else the block's first.
    public func time(ofItem id: String, word: String? = nil) -> Double? {
        let mine = marks.filter { $0.item == id }
        if let w = word?.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)), !w.isEmpty,
           let m = mine.first(where: { ($0.text ?? "").lowercased().range(of: #"\b"# + NSRegularExpression.escapedPattern(for: w) + #"\b"#, options: .regularExpression) != nil }) {
            return m.at
        }
        return mine.first?.at
    }

    /// While playing at `t`: the strokes of this recording not written yet (hidden, so the notes appear in step).
    public func strokesNotYet(at t: Double) -> Set<String> { Set(marks.filter { $0.stroke != nil && $0.at > t }.compactMap(\.stroke)) }

    /// The blocks with nothing typed yet at `t` (only blocks first typed during the recording).
    public func itemsNotYet(at t: Double) -> Set<String> {
        var first: [String: Double] = [:]
        for m in marks { if let i = m.item { first[i] = min(first[i] ?? .infinity, m.at) } }
        return Set(first.filter { $0.value > t }.keys)
    }

    // MARK: the file

    public var json: JSONValue {
        var o: [(String, JSONValue)] = [("format", .string(BoardRecording.format)), ("id", .string(id)), ("file", .string(file)),
                                        ("started", .string(started)), ("duration", .number(BoardRecording.r1(duration))),
                                        ("marks", .array(marks.map { m in
                                            var e: [(String, JSONValue)] = []
                                            if let s = m.stroke { e.append(("stroke", .string(s))) }
                                            if let i = m.item { e.append(("item", .string(i))) }
                                            if let t = m.text { e.append(("text", .string(t))) }
                                            e.append(("at", .number(m.at)))
                                            return .object(e)
                                        }))]
        if case .object(let extra)? = raw {
            for (k, v) in extra where !["format", "id", "file", "started", "duration", "marks"].contains(k) { o.append((k, v)) }
        }
        return .object(o)
    }

    public var text: String { json.pretty(indent: 1) + "\n" }

    /// Reads one; nil when it isn't a recording this app knows.
    public static func parse(_ text: String) -> BoardRecording? {
        guard let v = try? JSONValue.parse(text), v["format"]?.string == format, let id = v["id"]?.string, !id.isEmpty else { return nil }
        var r = BoardRecording(id: id)
        r.file = v["file"]?.string ?? audioPath(id)
        r.started = v["started"]?.string ?? ""
        r.duration = v["duration"]?.number ?? 0
        r.marks = (v["marks"]?.array ?? []).compactMap { m in
            guard let at = m["at"]?.number, at.isFinite else { return nil }
            let s = m["stroke"]?.string, i = m["item"]?.string
            guard s != nil || i != nil else { return nil }
            return Mark(stroke: s, item: i, text: m["text"]?.string, at: at)
        }
        r.raw = v
        return r
    }

    /// Every recording of a board folder, oldest first.
    public static func list(_ board: URL) -> [BoardRecording] {
        let dirURL = board.appendingPathComponent(dir)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dirURL.path)) ?? []).filter { $0.hasSuffix(".json") }
        return names.compactMap { n in
            (try? Data(contentsOf: dirURL.appendingPathComponent(n))).flatMap { parse(String(decoding: $0, as: UTF8.self)) }
        }.sorted { $0.started < $1.started }
    }
}
