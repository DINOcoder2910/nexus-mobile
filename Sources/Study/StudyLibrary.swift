import SwiftUI
import NexusCore

/// The study decks in the data folder and their schedules: each workstream with a `study/` folder, its decks and its
/// `study/review.yaml`, as the laptop's Study tab has them. The decks arrive with sync like any other file and are only read here;
/// the review file is written after each grade, merged card by card with what is on disk (NexusCore ReviewBook.reconcile), so a
/// deck reviewed on the laptop and on the phone keeps both. A conflict copy the hub made of the review file is folded in and removed.
@Observable
final class StudyLibrary {
    static let shared = StudyLibrary()

    struct Study: Identifiable {
        var workstream: Workstream
        var decks: [StudyFolder.DeckFile]
        var book: ReviewBook
        /// review.yaml does not parse: it is kept aside before the next save (as the laptop does).
        var reviewBroken = false
        /// The review file as this app last read or wrote it.
        var lastWritten: String?
        /// study/study.yaml: where the sheets are, the language.
        var config = StudyUnits.Config()
        /// study/units.yaml (nil: there is none, or it does not read: `unitsError`).
        var units: [StudyUnits.Unit]?
        var unitsError: String?
        /// study/sheets.yaml: what an upload kept about each sheet folder.
        var sheetIndex: [String: SheetIndex.Entry] = [:]
        /// The practice sheets in the sheets folder, with what sheets.yaml adds.
        var sheets = StudySheets.Model()
        var id: String { workstream.id }
        /// The sheets folder, from the data folder ("classes/chem-hl/files").
        var sheetsRoot: String { workstream.folder + "/" + config.sheets }
        var themes: [StudyUnits.Theme] { StudyUnits.themesOf(units ?? []) }
        /// A chemistry workstream gets the VSEPR chart, Enthalpies and Molecules (the laptop's hasVsepr).
        var isChemistry: Bool { (workstream.name + " " + workstream.folder).range(of: "chem", options: .caseInsensitive) != nil }
        var isSpanish: Bool { config.language == "spanish" }
    }

    private(set) var studies: [Study] = []
    /// A save that could not be made.
    var problem: String?
    @ObservationIgnored private var stamp = ""
    @ObservationIgnored private var folder: URL?

    func study(_ workstreamId: String) -> Study? { studies.first { $0.id == workstreamId } }
    /// The data folder the studies were read from.
    var folderURL: URL { folder ?? FolderAccess.current().url }
    var hasDecks: Bool { studies.contains { !$0.decks.isEmpty } }
    /// Any workstream with a study folder (the sidebar's Study row).
    var hasStudy: Bool { !studies.isEmpty }

    /// Every deck's numbers now.
    func counts(_ s: Study, _ f: StudyFolder.DeckFile, now: Int64 = StudyLibrary.now) -> FSRS.Counts? {
        guard let deck = f.deck else { return nil }
        let p = DeckPrefs.of(s.workstream.id, deck.id)
        let dir: StudyDeck.Direction = deck.flip || !deck.reversible ? .forward : p.dir
        return FSRS.counts(StudySession.cardIds(deck, tag: deck.flip ? p.tag : ""), s.book.states(deck.id, dir), now)
    }

    /// Cards due now in every deck (the sidebar's number).
    var dueTotal: Int {
        let now = Self.now
        return studies.reduce(0) { n, s in n + s.decks.reduce(0) { $0 + (counts(s, $1, now: now)?.due ?? 0) } }
    }

    static var now: Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

    // MARK: reading

    /// Reads the decks and review files again when any of them changed (or the folder did).
    func refreshIfChanged(_ store: NexusStore) {
        let ws = StudyFolder.workstreams(store.folder, store.snapshot)
        let now = Self.fingerprint(store.folder, ws)
        if now != stamp || folder != store.folder { load(store, ws) }
    }

    func load(_ store: NexusStore) { load(store, StudyFolder.workstreams(store.folder, store.snapshot)) }

    private func load(_ store: NexusStore, _ ws: [Workstream]) {
        let root = store.folder
        folder = root
        studies = ws.map { w -> Study in
            let decks = StudyFolder.deckPaths(root, w).map { StudyFolder.readDeck(root, $0, read: FolderAccess.read) }
            let text = try? FolderAccess.read(root.appendingPathComponent(StudyFolder.reviewPath(w)))
            var s = Study(workstream: w, decks: decks, book: ReviewBook(), lastWritten: text)
            Self.readFolder(root, &s)
            if let text {
                switch ReviewBook.parse(text) {
                case .success(let b): s.book = b
                case .failure: s.reviewBroken = true
                }
            }
            return s
        }
        if canWrite(store) { foldConflictCopies(store) }
        stamp = Self.fingerprint(root, ws)
    }

    /// The hub's conflict copies of a review file: merged in card by card (the newer review of a card wins), then removed.
    private func foldConflictCopies(_ store: NexusStore) {
        let root = store.folder
        for i in studies.indices {
            let w = studies[i].workstream
            let copies = StudyFolder.reviewConflictCopies(root, w)
            guard !copies.isEmpty, !studies[i].reviewBroken else { continue }
            var folded: [String] = []
            for p in copies {
                guard let t = try? FolderAccess.read(root.appendingPathComponent(p)), case .success(let b) = ReviewBook.parse(t) else { continue }
                studies[i].book = studies[i].book.merged(with: b)
                folded.append(p)
            }
            guard !folded.isEmpty, save(store, i) else { continue }
            for p in folded { try? FileManager.default.removeItem(at: root.appendingPathComponent(p)) }
            store.didWrite()
        }
    }

    /// study.yaml, units.yaml, sheets.yaml and the sheets folder, as the laptop's Study tab reads them.
    static func readFolder(_ root: URL, _ s: inout Study) {
        let f = StudyFolder.studyPath(s.workstream) + "/"
        func rd(_ name: String) -> String? {
            let u = root.appendingPathComponent(f + name)
            return FileManager.default.fileExists(atPath: u.path) ? try? FolderAccess.read(u) : nil
        }
        s.config = StudyUnits.parseConfig(rd("study.yaml"))
        s.sheetIndex = SheetIndex.parse(rd("sheets.yaml"))
        s.units = nil; s.unitsError = nil
        if let t = rd("units.yaml") {
            switch StudyUnits.parseUnits(t) {
            case .ok(let u): s.units = u
            case .failed(let e): s.unitsError = e
            }
        }
        let files = sheetFiles(root, s.sheetsRoot)
        s.sheets = StudySheets.withIndex(StudySheets.build(files, root: s.sheetsRoot), root: s.sheetsRoot, index: s.sheetIndex)
    }

    /// Every file in a sheets folder, from the data folder, in path order (hidden files, sync's own files and conflict copies left out).
    static func sheetFiles(_ root: URL, _ sheetsRoot: String) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(sheetsRoot).path, isDirectory: &isDir), isDir.boolValue else { return [] }
        return DataFolder.files(root, in: sheetsRoot).map(\.path)
            .filter { !SyncPaths.isIgnored($0) && !SyncPaths.isConflictCopy($0) }
            .sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    static func fingerprint(_ root: URL, _ ws: [Workstream]) -> String {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        var parts: [String] = []
        func stamp(_ u: URL) {
            let v = try? u.resourceValues(forKeys: keys)
            parts.append("\(u.lastPathComponent):\(v?.fileSize ?? -1):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        for w in ws {
            parts.append("#" + w.id)
            let dir = root.appendingPathComponent(StudyFolder.studyPath(w))
            for n in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() where n.hasPrefix("review") || n.hasPrefix("study.") || n.hasPrefix("units.") || n.hasPrefix("sheets.") {
                stamp(dir.appendingPathComponent(n))
            }
            // the sheets folder's file list (a sheet filed on the laptop, or here)
            let cfg = StudyUnits.parseConfig(try? FolderAccess.read(dir.appendingPathComponent("study.yaml")))
            parts.append(sheetFiles(root, w.folder + "/" + cfg.sheets).joined(separator: "\n"))
            for p in StudyFolder.deckPaths(root, w) { parts.append(p); stamp(root.appendingPathComponent(p)) }
        }
        return parts.joined(separator: "|")
    }

    // MARK: writing

    func canWrite(_ store: NexusStore) -> Bool { store.snapshot.isDataFolder && store.snapshot.readOnlyReason == nil }

    /// A card's new schedule (nil: none, after Undo of its first grade), written at once.
    func keep(_ store: NexusStore, workstream: String, deck: String, dir: StudyDeck.Direction, card: String, state: SRSCard?) {
        guard let i = studies.firstIndex(where: { $0.id == workstream }) else { return }
        studies[i].book[deck, dir, card] = state
        if save(store, i) { store.didWrite() }
    }

    /// Writes one workstream's review file, merged with the file on disk.
    @discardableResult
    private func save(_ store: NexusStore, _ i: Int) -> Bool {
        guard canWrite(store) else { return false }
        let root = store.folder, w = studies[i].workstream
        let url = root.appendingPathComponent(StudyFolder.reviewPath(w))
        let disk = FileManager.default.fileExists(atPath: url.path) ? (try? FolderAccess.read(url)) : nil
        let r = ReviewBook.reconcile(mine: studies[i].book, disk: disk, lastWritten: studies[i].lastWritten)
        do {
            if r.keepBrokenAside || (studies[i].reviewBroken && disk != nil && disk == studies[i].lastWritten) {
                // never written over: kept beside it first (review.broken-<day>-<n>.yaml), once
                let name = "review.broken-\(Days.today())-\(String(Self.now).suffix(6)).yaml"
                try FolderAccess.write(url.deletingLastPathComponent().appendingPathComponent(name), disk ?? "")
                problem = "study/review.yaml did not parse, so it is kept as \(name); your progress is saved again from here."
            }
            try FolderAccess.write(url, r.text)
            studies[i].book = r.book
            studies[i].lastWritten = r.text
            studies[i].reviewBroken = false
            stamp = Self.fingerprint(root, studies.map(\.workstream))
            return true
        } catch {
            problem = "Your review progress is not being saved: \(error.localizedDescription)"
            return false
        }
    }
}

extension StudyLibrary {
    /// Adds or merges one sheet folder's entry in study/sheets.yaml (an upload's notes and units). A sheets.yaml that does not parse is
    /// never written over: it is kept beside it first (sheets.broken-<day>-<n>.yaml), as review.yaml is. `before` is the entry it had.
    func keepSheetInfo(_ store: NexusStore, workstream: String, key: String, file: String, notes: String, units: [String]) -> (written: Bool, before: SheetIndex.Entry?) {
        guard canWrite(store), let i = studies.firstIndex(where: { $0.id == workstream }) else { return (false, nil) }
        guard var idx = readIndex(store, studies[i].workstream) else { return (false, nil) }
        let before = idx[key]
        idx[key] = SheetIndex.merge(idx[key], file: file, notes: notes, units: units, filed: Days.today())
        guard writeIndex(store, studies[i].workstream, idx) else { return (false, nil) }
        studies[i].sheetIndex = idx
        return (true, before)
    }

    /// Puts an entry back as it was before an upload (none: removed).
    func restoreSheetInfo(_ store: NexusStore, workstream: String, key: String, before: SheetIndex.Entry?) {
        guard canWrite(store), let i = studies.firstIndex(where: { $0.id == workstream }), var idx = readIndex(store, studies[i].workstream) else { return }
        idx[key] = before
        if writeIndex(store, studies[i].workstream, idx) { studies[i].sheetIndex = idx }
    }

    private func indexURL(_ store: NexusStore, _ w: Workstream) -> URL { store.folder.appendingPathComponent(StudyFolder.studyPath(w) + "/sheets.yaml") }

    private func readIndex(_ store: NexusStore, _ w: Workstream) -> [String: SheetIndex.Entry]? {
        let url = indexURL(store, w)
        let text = FileManager.default.fileExists(atPath: url.path) ? try? FolderAccess.read(url) : nil
        if let idx = SheetIndex.parseStrict(text) { return idx }
        let name = "sheets.broken-\(Days.today())-\(String(Self.now).suffix(6)).yaml"
        do { try FolderAccess.write(url.deletingLastPathComponent().appendingPathComponent(name), text ?? "") } catch {
            problem = "study/sheets.yaml does not parse and could not be kept aside, so the notes were not saved."
            return nil
        }
        problem = "study/sheets.yaml did not parse, so it is kept as \(name); the notes are saved again from here."
        return [:]
    }

    private func writeIndex(_ store: NexusStore, _ w: Workstream, _ idx: [String: SheetIndex.Entry]) -> Bool {
        do { try FolderAccess.write(indexURL(store, w), SheetIndex.serialize(idx)); return true } catch {
            problem = "Could not save study/sheets.yaml: \(error.localizedDescription)"
            return false
        }
    }
}

/// How a deck is reviewed on this device (mode, direction, new cards), remembered per deck as the laptop remembers it.
struct DeckPrefs: Codable, Equatable {
    var mode = StudySession.Mode.flip.rawValue
    var direction = StudyDeck.Direction.forward.rawValue
    var newLimit = 20
    /// Flip decks: which side first, new cards a day, a tag.
    var show = StudyDeck.Show.es.rawValue
    var perDay = 10
    var tag = ""

    var dir: StudyDeck.Direction { StudyDeck.Direction(rawValue: direction) ?? .forward }
    var sessionMode: StudySession.Mode { StudySession.Mode(rawValue: mode) ?? .flip }
    var showFirst: StudyDeck.Show { StudyDeck.Show(rawValue: show) ?? .es }

    private static let key = "studyDeckPrefs"
    private static func all() -> [String: DeckPrefs] {
        guard let d = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: DeckPrefs].self, from: d)) ?? [:]
    }
    static func of(_ workstream: String, _ deck: String) -> DeckPrefs { all()[workstream + "/" + deck] ?? DeckPrefs() }
    static func set(_ p: DeckPrefs, _ workstream: String, _ deck: String) {
        var a = all(); a[workstream + "/" + deck] = p
        if let d = try? JSONEncoder().encode(a) { UserDefaults.standard.set(d, forKey: key) }
    }
}
