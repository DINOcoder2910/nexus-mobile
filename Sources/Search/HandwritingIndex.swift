import Foundation
import Observation
import PencilKit
import UIKit
import Vision
import NexusCore

/// Search in boards: what is handwritten on every board in `notebooks/` (read with Vision, chunk by chunk) and what is typed in
/// its text blocks, line by line, each with its place on the board (board units).
///
/// The index is the iPad's own, kept as JSON in Application Support (never in the data folder: the laptop must not see it), one
/// file per data folder. Each board has a signature (a hash of its tile files and text blocks), so a board that didn't change is
/// not read again. The work runs on a serial background queue; progress and results are published on the main thread.
/// Call the methods from the main thread.
@Observable
final class HandwritingIndex {
    static let shared = HandwritingIndex()

    /// One line found: a handwritten line (Vision) or a line of a typed block.
    struct Hit: Identifiable {
        let id: String
        let boardPath: String
        let boardName: String
        /// "Notebook › Notebook inside it", or "Notebook".
        let place: String
        let text: String
        /// Where it is on the board (board units, y down).
        let box: CGRect
        let typed: Bool
    }

    /// What one board holds, as kept on disk.
    struct Line: Codable {
        var text: String
        /// The text folded for matching (no case, no accents).
        var key: String
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var typed: Bool
        /// The chunk ("tx_ty") a handwritten line was read in, or the block id of a typed line: neighbours share it.
        var group: String
    }

    struct BoardEntry: Codable {
        var path: String
        var name: String
        var place: String
        var signature: String
        var lines: [Line]
        var indexed: Date
    }

    /// Reading boards now.
    private(set) var isIndexing = false
    /// Boards checked so far in this run, and how many there are.
    private(set) var done = 0
    private(set) var total = 0
    /// The board being read now ("Lesson 1"), when one needs reading.
    private(set) var current: String?
    /// Everything indexed, by board path.
    private(set) var boards: [String: BoardEntry] = [:]
    /// The last thing that went wrong (a board that couldn't be read, the index that couldn't be saved).
    private(set) var problem: String?

    private let worker = Worker()

    private init() {}

    /// Number of lines kept, for the status line.
    var lineCount: Int { boards.values.reduce(0) { $0 + $1.lines.count } }

    // MARK: refreshing

    /// Indexes every board of the data folder that changed since it was last read, and drops boards that are gone.
    func refresh(root: URL) { start(root: root, force: false) }

    /// Reads every board again, even unchanged ones (the Re-read button). What is found stays searchable meanwhile.
    func reread(root: URL) { start(root: root, force: true) }

    /// One board, e.g. right after it was saved. `path` is relative to the data folder ("notebooks/Chem/R3/Lesson 1.board").
    func refresh(board path: String, root: URL) {
        worker.queue.async { [weak self] in
            guard let self else { return }
            self.worker.use(root: root, publish: self.publishAll)
            let np = HandwritingIndex.nameAndPlace(path)
            let ref = BoardRef(path: path, name: np.name, place: np.place)
            self.publish(indexing: true, done: 0, total: 1, current: ref.name)
            let changed: Bool = autoreleasepool { self.worker.index(ref, root: root, force: false, reuse: [:], problem: self.publishProblem) }
            if changed { self.worker.save(problem: self.publishProblem) }
            self.publishAll(self.worker.entries)
            self.publish(indexing: false, done: 1, total: 1, current: nil)
        }
    }

    private func start(root: URL, force: Bool) {
        let gen = worker.generation.next()
        worker.queue.async { [weak self] in
            guard let self else { return }
            self.worker.use(root: root, publish: self.publishAll)
            let refs = HandwritingIndex.boardRefs(root)
            // boards that are gone; one that only moved or was renamed keeps its lines (same signature)
            let present = Set(refs.map(\.path))
            var reuse: [String: BoardEntry] = [:]
            var dropped = false
            for (p, e) in self.worker.entries where !present.contains(p) {
                reuse[e.signature] = e
                self.worker.entries[p] = nil
                dropped = true
            }
            if dropped { self.worker.save(problem: self.publishProblem) }
            self.publishAll(self.worker.entries)
            self.publish(indexing: true, done: 0, total: refs.count, current: nil)
            for (i, ref) in refs.enumerated() {
                // a newer refresh was asked for: it carries on from here (what is done is kept)
                if self.worker.generation.current != gen { return }
                self.publish(indexing: true, done: i, total: refs.count, current: ref.name)
                let changed: Bool = autoreleasepool { self.worker.index(ref, root: root, force: force, reuse: reuse, problem: self.publishProblem) }
                if changed {
                    self.worker.save(problem: self.publishProblem)
                    self.publishAll(self.worker.entries)
                }
            }
            self.publishAll(self.worker.entries)
            self.publish(indexing: false, done: refs.count, total: refs.count, current: nil)
        }
    }

    private func publish(indexing: Bool, done: Int, total: Int, current: String?) {
        DispatchQueue.main.async {
            self.isIndexing = indexing
            self.done = done
            self.total = total
            self.current = current
            if indexing && done == 0 { self.problem = nil }
        }
    }

    private func publishAll(_ entries: [String: BoardEntry]) {
        DispatchQueue.main.async { self.boards = entries }
    }

    private func publishProblem(_ text: String) {
        DispatchQueue.main.async { self.problem = text }
    }

    // MARK: searching

    /// Lines holding every word of the query (no case, no accents), best first: the whole phrase, then all words in the line,
    /// then words spread over a line and the ones just above and below it (same chunk or block). At most 200.
    func search(_ query: String) -> [Hit] {
        let words = HandwritingIndex.fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        var scored: [(score: Int, hit: Hit)] = []
        for entry in boards.values {
            // lines of one group in reading order, for the neighbours
            var byGroup: [String: [Int]] = [:]
            for (i, l) in entry.lines.enumerated() { byGroup[l.group, default: []].append(i) }
            for (_, idxs) in byGroup {
                let ordered = idxs.sorted { a, b in
                    let la = entry.lines[a], lb = entry.lines[b]
                    return la.y == lb.y ? la.x < lb.x : la.y < lb.y
                }
                for (k, i) in ordered.enumerated() {
                    let line = entry.lines[i]
                    var score = 0
                    var box = CGRect(x: line.x, y: line.y, width: line.w, height: line.h)
                    if line.key.contains(phrase) {
                        score = 300
                    } else if words.allSatisfy({ line.key.contains($0) }) {
                        score = 200
                    } else if line.key.contains(words[0]) {
                        // the rest may be on the line above or below (a phrase broken over two lines)
                        let prev: Line? = k > 0 ? entry.lines[ordered[k - 1]] : nil
                        let next: Line? = k + 1 < ordered.count ? entry.lines[ordered[k + 1]] : nil
                        let parts: [String?] = [prev?.key, line.key, next?.key]
                        let around: String = parts.compactMap { $0 }.joined(separator: " ")
                        if words.allSatisfy({ around.contains($0) }) {
                            score = 100
                            if let prev, words.contains(where: { prev.key.contains($0) }) {
                                box = box.union(CGRect(x: prev.x, y: prev.y, width: prev.w, height: prev.h))
                            }
                            if let next, words.contains(where: { next.key.contains($0) }) {
                                box = box.union(CGRect(x: next.x, y: next.y, width: next.w, height: next.h))
                            }
                        }
                    }
                    guard score > 0 else { continue }
                    // a word that starts a word counts more than one inside a word
                    let padded = " " + line.key
                    for w in words where padded.contains(" " + w) { score += 10 }
                    if line.typed { score += 1 }
                    let hit = Hit(id: entry.path + "#" + String(i), boardPath: entry.path, boardName: entry.name, place: entry.place,
                                  text: line.text, box: box, typed: line.typed)
                    scored.append((score: score, hit: hit))
                }
            }
        }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.hit.boardName != b.hit.boardName { return a.hit.boardName.localizedStandardCompare(b.hit.boardName) == .orderedAscending }
            if a.hit.box.minY != b.hit.box.minY { return a.hit.box.minY < b.hit.box.minY }
            return a.hit.box.minX < b.hit.box.minX
        }
        return scored.prefix(200).map { $0.hit }
    }

    /// Lower case, no accents, single spaces: what matching compares.
    static func fold(_ s: String) -> String {
        let f = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        return f.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: the boards of a data folder

    struct BoardRef {
        var path: String
        var name: String
        var place: String
    }

    /// Every board in `notebooks/`, in notebooks inside notebooks to any depth.
    static func boardRefs(_ root: URL) -> [BoardRef] {
        Notebook.list(root).flatMap { nb in nb.allBoards.map { BoardRef(path: $0.board.path, name: $0.board.name, place: $0.place) } }
    }

    /// "notebooks/Chem/R3/Lesson 1.board" → ("Lesson 1", "Chem › R3").
    static func nameAndPlace(_ path: String) -> (name: String, place: String) {
        var parts = path.split(separator: "/").map(String.init)
        var name = parts.popLast() ?? path
        if name.lowercased().hasSuffix(".board") { name = String(name.dropLast(6)) }
        if parts.first == BoardFormat.notebooks { parts.removeFirst() }
        return (name, parts.joined(separator: " › "))
    }
}

// MARK: - the background half

extension HandwritingIndex {
    /// A counter read and bumped from any thread.
    final class Generation {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        var current: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Everything here is touched only on `queue`.
    final class Worker {
        let queue = DispatchQueue(label: "app.nexus.handwriting-index", qos: .utility)
        let generation = Generation()
        var entries: [String: BoardEntry] = [:]
        private var fileURL: URL?

        /// Changing what is read (the language list, the chunking) re-reads every board once.
        static let recipe = "hw1|chunk1024+128|s1.5|en-US,es-ES"
        static let chunk: CGFloat = 1024
        static let margin: CGFloat = 128
        static let scale: CGFloat = 1.5

        private struct FileBody: Codable {
            var version: Int
            var boards: [String: BoardEntry]
        }

        /// Loads the index kept for this data folder (when it isn't the one loaded already).
        func use(root: URL, publish: ([String: BoardEntry]) -> Void) {
            let url = Worker.indexFile(for: root)
            guard url != fileURL else { return }
            fileURL = url
            entries = [:]
            if let d = try? Data(contentsOf: url) {
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                if let body = try? dec.decode(FileBody.self, from: d), body.version == 1 { entries = body.boards }
            }
            publish(entries)
        }

        func save(problem: (String) -> Void) {
            guard let url = fileURL else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let enc = JSONEncoder()
                enc.dateEncodingStrategy = .iso8601
                let data = try enc.encode(FileBody(version: 1, boards: entries))
                try data.write(to: url, options: .atomic)
            } catch {
                problem("Couldn't keep the handwriting index: \(error.localizedDescription)")
            }
        }

        /// Application Support/HandwritingIndex/<hash of the data folder>.json. The app's own folder moves when the app is
        /// updated, so a folder inside it is named by its path below Documents.
        static func indexFile(for root: URL) -> URL {
            let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                        ?? FileManager.default.temporaryDirectory).appendingPathComponent("HandwritingIndex", isDirectory: true)
            let docs = FolderAccess.documents.standardizedFileURL.path
            let p = root.standardizedFileURL.path
            let key = p.hasPrefix(docs) ? "documents" + String(p.dropFirst(docs.count)) : p
            var h = Hash()
            h.add(key)
            return base.appendingPathComponent(h.hex + ".json")
        }

        /// Reads one board if it changed (or `force`). True when its entry changed.
        func index(_ ref: BoardRef, root: URL, force: Bool, reuse: [String: BoardEntry], problem: (String) -> Void) -> Bool {
            let url = root.appendingPathComponent(ref.path, isDirectory: true)
            guard let sig = Worker.signature(url) else {
                // not a board (any more)
                return entries.removeValue(forKey: ref.path) != nil
            }
            if !force, var e = entries[ref.path], e.signature == sig {
                if e.name != ref.name || e.place != ref.place {
                    e.name = ref.name; e.place = ref.place; entries[ref.path] = e
                    return true
                }
                return false
            }
            if !force, var e = reuse[sig] {
                e.path = ref.path; e.name = ref.name; e.place = ref.place
                entries[ref.path] = e
                return true
            }
            let content: BoardContent
            do { content = try BoardFiles.load(url) } catch {
                problem("Couldn't read \(ref.name): \(error)")
                return entries.removeValue(forKey: ref.path) != nil
            }
            var lines = Worker.typedLines(content)
            lines.append(contentsOf: Worker.handwrittenLines(content.strokes))
            entries[ref.path] = BoardEntry(path: ref.path, name: ref.name, place: ref.place, signature: sig, lines: lines, indexed: Date())
            return true
        }

        /// A hash of board.json, every tile file and every text block, or nil when the folder has no board.json.
        static func signature(_ board: URL) -> String? {
            guard let meta = try? Data(contentsOf: board.appendingPathComponent("board.json")) else { return nil }
            var h = Hash()
            h.add(recipe)
            h.add(meta)
            let fm = FileManager.default
            for dir in ["tiles", "text"] {
                let folder = board.appendingPathComponent(dir, isDirectory: true)
                let names = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
                for n in names {
                    guard let d = try? Data(contentsOf: folder.appendingPathComponent(n)) else { continue }
                    h.add("\u{0}" + dir + "/" + n + "\u{0}")
                    h.add(d)
                }
            }
            return h.hex
        }

        // MARK: typed text

        /// Each non-empty line of each typed block, as text (markdown marks taken off), placed on the whole block.
        static func typedLines(_ c: BoardContent) -> [Line] {
            var out: [Line] = []
            for it in c.items where it.type == "text" {
                let md = c.texts[it.id] ?? ""
                let raw = md.components(separatedBy: .newlines)
                let size = it.number("size") ?? BoardFormat.defaultTextSize
                let w = it.w ?? BoardFormat.textWidth
                // the block's height, roughly: its lines wrapped at its width
                var rows: Double = 0
                for r in raw {
                    let chars = Double(max(1, r.count))
                    rows += max(1, (chars * size * 0.5 / max(40, w)).rounded(.up))
                }
                let h = it.h ?? max(size * 1.5, rows * size * 1.5 + 8)
                for r in raw {
                    let text = plain(r)
                    guard !text.isEmpty else { continue }
                    out.append(Line(text: text, key: HandwritingIndex.fold(text), x: it.x, y: it.y, w: w, h: h, typed: true, group: "t:" + it.id))
                }
            }
            return out
        }

        /// A markdown line without its marks: headings, list and checkbox markers, quotes, emphasis, highlights, code ticks, links.
        static func plain(_ line: String) -> String {
            var s = line.trimmingCharacters(in: .whitespaces)
            let leading = #"^(#{1,6}\s+|>\s*|[-*+]\s+\[[ xX]\]\s+|[-*+]\s+|\d+[.)]\s+)+"#
            s = s.replacingOccurrences(of: leading, with: "", options: .regularExpression)
            s = s.replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\[\[([^\]|]*\|)?([^\]]*)\]\]"#, with: "$2", options: .regularExpression)
            for mark in ["**", "__", "==", "~~", "`"] { s = s.replacingOccurrences(of: mark, with: "") }
            s = s.replacingOccurrences(of: #"(^|\s)[*_]([^*_]+)[*_](?=\s|$|[.,;:!?])"#, with: "$1$2", options: .regularExpression)
            s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            return s.trimmingCharacters(in: .whitespaces)
        }

        // MARK: handwriting

        /// The ink drawn black on white, one chunk (a 1024 square with ink, plus a margin so a line on the edge is read whole) at a
        /// time; each line is kept by the chunk its middle falls in. Highlighter strokes are left out (they cover the writing).
        static func handwrittenLines(_ strokes: [BoardStroke]) -> [Line] {
            var byChunk: [String: [PKStroke]] = [:]
            var origins: [String: CGPoint] = [:]
            for s in strokes where s.ink != "com.apple.ink.marker" {
                var black = s
                black.color = "#000000FF"
                for k in InkConvert.pkStrokes(black, offset: .zero) {
                    let b = k.renderBounds
                    let far: CGFloat = 1_000_000_000
                    guard !b.isNull, !b.isInfinite, b.minX.isFinite, b.minY.isFinite, b.maxX.isFinite, b.maxY.isFinite,
                          abs(b.minX) < far, abs(b.minY) < far, abs(b.maxX) < far, abs(b.maxY) < far else { continue }
                    let grown = b.insetBy(dx: -margin, dy: -margin)
                    let x0 = Int(floor(grown.minX / chunk)), x1 = Int(floor(grown.maxX / chunk))
                    let y0 = Int(floor(grown.minY / chunk)), y1 = Int(floor(grown.maxY / chunk))
                    var cells: [(Int, Int)] = []
                    if (x1 - x0 + 1) * (y1 - y0 + 1) <= 16 {
                        for tx in x0...x1 { for ty in y0...y1 { cells.append((tx, ty)) } }
                    } else {
                        // a stroke across a huge area (a long line, a frame) is read in the chunks of its ends only
                        let ends: [[Double]?] = [black.points.first, black.points.last]
                        for end in ends {
                            guard let p = end, p.count >= 2, abs(p[0]) < Double(far), abs(p[1]) < Double(far) else { continue }
                            let cell: (Int, Int) = (Int(floor(p[0] / Double(chunk))), Int(floor(p[1] / Double(chunk))))
                            if !cells.contains(where: { $0.0 == cell.0 && $0.1 == cell.1 }) { cells.append(cell) }
                        }
                    }
                    for (tx, ty) in cells {
                        let key = "\(tx)_\(ty)"
                        byChunk[key, default: []].append(k)
                        origins[key] = CGPoint(x: CGFloat(tx) * chunk, y: CGFloat(ty) * chunk)
                    }
                }
            }
            let request = makeRequest()
            var out: [Line] = []
            for key in byChunk.keys.sorted() {
                guard let pks = byChunk[key], let origin = origins[key] else { continue }
                let core = CGRect(x: origin.x, y: origin.y, width: chunk, height: chunk)
                // a chunk whose ink only reaches in from a neighbour's margin has nothing of its own to read
                guard pks.contains(where: { $0.renderBounds.intersects(core) }) else { continue }
                let found: [Line] = autoreleasepool { read(pks, core: core, group: key, request: request) }
                out.append(contentsOf: found)
            }
            return out
        }

        static func makeRequest() -> VNRecognizeTextRequest {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let want = ["en-US", "es-ES"]
            if let supported = try? request.supportedRecognitionLanguages() {
                let langs = want.filter { supported.contains($0) }
                if !langs.isEmpty { request.recognitionLanguages = langs }
            }
            return request
        }

        /// Renders one chunk (with its margin) and reads its lines.
        static func read(_ pks: [PKStroke], core: CGRect, group: String, request: VNRecognizeTextRequest) -> [Line] {
            let rect = core.insetBy(dx: -margin, dy: -margin)
            guard let cg = render(pks, rect: rect) else { return [] }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try handler.perform([request]) } catch { return [] }
            let observations: [VNRecognizedTextObservation] = request.results ?? []
            var out: [Line] = []
            for o in observations {
                guard let best = o.topCandidates(1).first, best.confidence >= 0.2 else { continue }
                let text = best.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                // normalised, origin bottom left → board units, y down
                let bb = o.boundingBox
                let x = rect.minX + bb.minX * rect.width
                let y = rect.minY + (1 - bb.maxY) * rect.height
                let w = bb.width * rect.width
                let h = bb.height * rect.height
                let mid = CGPoint(x: x + w / 2, y: y + h / 2)
                guard core.contains(mid) else { continue } // the neighbouring chunk reads it
                out.append(Line(text: text, key: HandwritingIndex.fold(text), x: Double(x), y: Double(y), w: Double(w), h: Double(h),
                                typed: false, group: group))
            }
            return out
        }

        /// The strokes in `rect` (board units) as an opaque image, black ink on white, at `scale` pixels per unit.
        static func render(_ pks: [PKStroke], rect: CGRect) -> CGImage? {
            let drawing = PKDrawing(strokes: pks)
            // PencilKit draws ink for the current appearance (black turns white in dark mode): ask for light
            var ink: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                ink = drawing.image(from: rect, scale: scale)
            }
            guard let ink else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: rect.size))
                ink.draw(in: CGRect(origin: .zero, size: rect.size))
            }
            return image.cgImage
        }
    }

    /// FNV-1a, 64 bits: a hash that is the same on every launch (Swift's `Hasher` isn't).
    struct Hash {
        private var h: UInt64 = 0xcbf2_9ce4_8422_2325
        init() {}
        mutating func add(_ data: Data) {
            var v = h
            data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                for b in buf {
                    v ^= UInt64(b)
                    v = v &* 0x0000_0100_0000_01b3
                }
            }
            h = v
        }
        mutating func add(_ s: String) { add(Data(s.utf8)) }
        var hex: String { String(h, radix: 16) }
    }
}
