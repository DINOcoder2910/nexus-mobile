import SwiftUI
import PDFKit
import Vision
import CryptoKit
import UniformTypeIdentifiers
import NexusCore

/// Upload a sheet, as the laptop's Study tab does it (studyfile.js; the rules in NexusCore StudyUpload): choose files or scan pages, say
/// what each is if you know, then for each: its text (a PDF's text layer; the scanned pages read on the device, offline), the same bytes
/// looked for among the sheets (SHA-256 of the files of the same size), one Claude call with a digest of it and the folder's layout
/// (page pictures when the text is too thin, or when Claude was unsure and you ask it to look), the text compared with the sheets that
/// look alike, then the proposal as a form you edit: unit folder, sheet folder, title, details, the path it makes, the duplicates.
/// "File it" writes it there, never over another file, keeps the notes in study/sheets.yaml, and can be undone.
@MainActor @Observable
final class SheetUpload {
    enum Status: Equatable { case describe, reading, ocr, claude, compare, ready, filing, filed, skipped, error }

    struct Near: Hashable { var path: String; var share: Int }

    struct Form: Equatable {
        var unitFolder = "", existing = "", title = "", details = "", era = "", ms = "with", fileName = "", role = "paper", notes = "", codes = ""
    }

    @MainActor @Observable
    final class Item: Identifiable {
        let id = UUID()
        let name: String
        let data: Data
        var status = Status.describe
        var note = ""
        var pages: [String] = []
        /// text | ocr | images
        var how = "text"
        var nPages = 1
        var ocrNeed: [Int] = []
        var ocrDone: Set<Int> = []
        var ocrPlan = 0
        var ocrError: String?
        var sent: [Int] = []
        var exact: [String] = []
        var near: [Near] = []
        var same: [String] = []
        var error: String?
        var proposal: StudyUpload.Proposal?
        var form = Form()
        var tokens: Int?
        // once filed: what Undo takes back
        var target: String?
        var made: [String] = []
        var indexKey: String?
        var indexWritten = false
        var indexBefore: SheetIndex.Entry?
        @ObservationIgnored var doc: PDFDocument?
        init(name: String, data: Data) { self.name = name; self.data = data }
        var isPdf: Bool { name.lowercased().hasSuffix(".pdf") }
        var isImage: Bool { name.range(of: #"\.(png|jpe?g|heic)$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    let workstreamId: String
    var items: [Item] = []
    /// The last file filed, for its Undo.
    var lastFiled: Item?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var bytesCache: [String: Data] = [:]
    @ObservationIgnored private var shingleCache: [String: Set<String>] = [:]

    static let maxBytes = 80 * 1024 * 1024
    static let ocrFirstN = 3, maxPages = 80, ocrMax = 30

    init(workstreamId: String) { self.workstreamId = workstreamId }

    var study: StudyLibrary.Study? { StudyLibrary.shared.study(workstreamId) }
    var current: Item? { items.first { ![.filed, .skipped].contains($0.status) } }
    var describing: Bool { items.contains { $0.status == .describe } }
    var done: Bool { !items.isEmpty && items.allSatisfy { [.filed, .skipped].contains($0.status) } }

    /// "sonnet" (the default) or "haiku" (quicker, cheaper): Study's own choice, as on the laptop.
    static var model: String {
        get { UserDefaults.standard.string(forKey: "studyUploadModel") == "haiku" ? "haiku" : "sonnet" }
        set { UserDefaults.standard.set(newValue, forKey: "studyUploadModel") }
    }

    func add(_ files: [(name: String, data: Data)]) {
        let busy = items.contains { ![.filed, .skipped, .describe].contains($0.status) }
        for f in files {
            let it = Item(name: f.name, data: f.data)
            if busy { it.status = .reading }
            items.append(it)
        }
        if busy { Task { await sortQueue() } }
    }

    /// The files you've described (or left blank) go off to be read.
    func sortAll() {
        for it in items where it.status == .describe { it.note = it.note.trimmingCharacters(in: .whitespacesAndNewlines); it.status = .reading }
        Task { await sortQueue() }
    }

    func cancel() { items.forEach { $0.doc = nil }; items = [] }

    private func sortQueue() async {
        guard !running else { return }
        running = true
        defer { running = false }
        while let it = items.first(where: { $0.status == .reading }) { await prepare(it) }
    }

    private func live(_ it: Item) -> Bool { items.contains { $0 === it } }

    // MARK: reading one file

    private func prepare(_ it: Item) async {
        guard let s = study else { it.status = .error; it.error = "The study folder is gone."; return }
        do {
            if it.data.count > Self.maxBytes { throw ClaudeError("it is larger than 80 MB") }
            let hash = Self.sha256(it.data)
            await read(it)
            guard live(it) else { return }
            // the same bytes: only files of the same size can be
            let root = StudyLibrary.shared.folderURL
            for sh in s.sheets.sheets { for f in sh.files {
                let u = root.appendingPathComponent(f.path)
                let size = (try? u.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
                if size == it.data.count, let d = try? Data(contentsOf: u), Self.sha256(d) == hash { it.exact.append(f.path) }
            } }
            it.same = StudyUpload.sameNameFiles(s.sheets, it.name).filter { !it.exact.contains($0) }
            it.status = .claude
            await askClaude(it, pics: it.how == "images" && it.note.isEmpty ? StudyUpload.picturePages(it.nPages) : [])
            guard live(it) else { return }
            it.status = .compare
            await nearCopies(it)
            it.status = .ready
        } catch {
            it.status = .error
            it.error = "Could not read \(it.name): \(error.localizedDescription)."
        }
        if it.status == .ready && it.note.isEmpty { Task { await ocrRest(it) } }
    }

    /// A PDF's text page by page; its pages without text are scans, read on the device (the first ones and the last now, the rest
    /// after the form is up). Too little text even then: Claude sees pictures of the pages.
    private func read(_ it: Item) async {
        it.pages = []; it.how = "text"; it.nPages = 1; it.ocrDone = []; it.sent = []; it.ocrError = nil
        if it.isPdf {
            it.doc = PDFDocument(data: it.data)
            if let doc = it.doc {
                it.nPages = doc.pageCount
                for i in 0..<min(doc.pageCount, Self.maxPages) { it.pages.append(doc.page(at: i)?.string ?? "") }
                it.ocrNeed = StudyUpload.thinPages(it.pages, max: Self.ocrMax)
                let first = StudyUpload.ocrFirst(it.ocrNeed, pages: it.pages.count, k: Self.ocrFirstN)
                if !first.isEmpty && it.note.isEmpty {
                    it.how = "ocr"; it.status = .ocr; it.ocrPlan = first.count
                    for i in first { guard live(it) else { return }; await ocrPage(it, i) }
                }
            }
        } else if it.isImage {
            it.pages = [""]
            if it.note.isEmpty { it.how = "ocr"; it.status = .ocr; it.ocrPlan = 1; it.ocrNeed = [1]; await ocrPage(it, 1) }
        } else if it.name.range(of: #"\.(txt|md)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            it.pages = [String(decoding: it.data, as: UTF8.self)]
        } else {
            it.pages = [""] // (a Word file: Claude goes by its name and your words)
        }
        if it.how == "ocr" && StudyUpload.isThin(it.pages) { it.how = "images" }
    }

    private func ocrPage(_ it: Item, _ i: Int) async {
        defer { it.ocrDone.insert(i) }
        guard let img = image(it, page: i, width: 1700) else { return }
        let text = await Task.detached(priority: .userInitiated) { Self.ocr(img) }.value
        if it.pages.indices.contains(i - 1) { it.pages[i - 1] = text }
    }

    nonisolated static func ocr(_ cg: CGImage) -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["en-US"]
        do { try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([req]) } catch { return "" }
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Page `i` (from 1) as a picture `width` pixels wide; an image file is itself.
    private func image(_ it: Item, page i: Int, width: CGFloat) -> CGImage? {
        if let doc = it.doc, let p = doc.page(at: i - 1) {
            let box = p.bounds(for: .mediaBox)
            guard box.width > 0 else { return nil }
            let k = width / box.width
            return p.thumbnail(of: CGSize(width: width, height: box.height * k), for: .mediaBox).cgImage
        }
        return it.isImage ? UIImage(data: it.data)?.cgImage : nil
    }

    /// The rest of a scan's pages, read after the form is up (it sharpens the duplicate check; the form stays as you left it).
    private func ocrRest(_ it: Item) async {
        let rest = it.ocrNeed.filter { !it.ocrDone.contains($0) }
        guard !rest.isEmpty, it.doc != nil else { return }
        for i in rest {
            guard live(it), it.doc != nil, it.status == .ready || it.status == .claude || it.status == .compare else { return }
            await ocrPage(it, i)
        }
        if live(it) && it.status == .ready { await nearCopies(it) }
    }

    // MARK: Claude

    private func askClaude(_ it: Item, pics: [Int]) async {
        guard let s = study else { return }
        let root = s.sheetsRoot, model = s.sheets
        var blocks: [ClaudeBlock] = []
        for p in pics {
            if it.doc != nil, let img = image(it, page: p, width: 1200), let jpg = UIImage(cgImage: img).jpegData(compressionQuality: 0.8) {
                blocks.append(.image(mediaType: "image/jpeg", base64: jpg.base64EncodedString()))
            } else if it.isImage, let jpg = UIImage(data: it.data)?.jpegData(compressionQuality: 0.8) {
                blocks.append(.image(mediaType: "image/jpeg", base64: jpg.base64EncodedString()))
            }
        }
        let seen = it.note.isEmpty ? it.pages : it.pages + [it.note]
        let text = it.note.isEmpty ? StudyUpload.digest(it.pages) : String(decoding: Array((it.pages.first ?? "").utf16.prefix(1500)), as: UTF16.self)
        let units = (s.units ?? []).map { "\($0.code): \($0.title)" }.joined(separator: "\n")
        let prompt = StudyUpload.readPrompt(fileName: it.name, text: text, hint: StudyUpload.keywordHint(seen),
                                            summary: StudyUpload.folderSummary(model, root: root, focus: StudyUpload.focusFolders(model, root: root, pages: seen)),
                                            units: units, how: it.how, pages: it.nPages, images: blocks.isEmpty ? [] : pics, note: it.note)
        it.error = nil
        var reply: String?
        do {
            if UploadDemo.on {
                try? await Task.sleep(for: .seconds(1))
                reply = UploadDemo.reply(it.name)
            } else {
                let req = ClaudeRequest(model: Self.model, system: StudyUpload.system,
                                        messages: [ClaudeMessage(role: "user", content: blocks + [.text(prompt + "\n\n" + StudyUpload.answerFormat())])],
                                        maxTokens: 4096, cacheSystem: false)
                let r = try await ClaudeClient.shared.stream(req) { _ in }
                reply = r.text
                if let u = r.usage { it.tokens = u.allInput + u.outputTokens }
            }
        } catch {
            it.error = "Claude could not sort it (\(error.localizedDescription.replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression))). Fill in where it goes yourself."
        }
        if !blocks.isEmpty { it.sent += pics }
        var proposal: StudyUpload.Proposal?
        if let reply {
            switch StudyUpload.readAnswer(StudyUpload.answerFromText(reply), fileName: it.name, model: model, root: root) {
            case .ok(let p): proposal = p
            case .failed(let e): it.error = e + " Fill in where it goes yourself."
            }
        }
        let p = proposal ?? fallback(it)
        it.proposal = p
        it.form = Form(unitFolder: p.unitFolder, existing: p.existingSheet ?? "", title: p.title, details: p.details, era: p.era ?? "", ms: p.ms,
                       fileName: p.fileName, role: p.role, notes: p.notes, codes: p.codes.joined(separator: ", "))
    }

    private func fallback(_ it: Item) -> StudyUpload.Proposal {
        var p = StudyUpload.Proposal()
        let role = StudySheets.fileRole(it.name)
        p.role = role
        if let s = study, let g = s.sheets.groups.first { p.unitFolder = StudySheets.relIn(s.sheetsRoot, g.path) }
        p.title = StudySheets.safeName((it.name as NSString).deletingPathExtension)
        p.ms = role == "ms" ? "only" : "with"
        p.fileName = StudySheets.fileNameFor(it.name, role: role)
        return p
    }

    /// "Tell Claude": your words, and it answers again.
    func tell(_ it: Item, _ text: String) {
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        it.note = note; it.status = .claude; it.near = []
        Task {
            await askClaude(it, pics: [])
            guard live(it) else { return }
            await nearCopies(it)
            it.status = .ready
        }
    }

    /// "Read 3 more pages": pictures of pages 1, 2 and the last again, and of 3 pages Claude has not seen.
    func readMore(_ it: Item) {
        let pics = StudyUpload.picturePages(it.nPages, sent: it.sent, extra: 3)
        guard !pics.isEmpty else { return }
        it.status = .claude
        Task { await askClaude(it, pics: pics); if live(it) { it.status = .ready } }
    }

    func morePictures(_ it: Item) -> (pages: [Int], extra: Int) {
        guard it.doc != nil || it.isImage else { return ([], 0) }
        let n = it.doc != nil ? it.nPages : 1
        let pics = StudyUpload.picturePages(n, sent: it.sent, extra: 3)
        return (pics, pics.filter { ![1, 2, n].contains($0) }.count)
    }

    // MARK: near copies

    private func nearCopies(_ it: Item) async {
        guard let s = study else { return }
        let mine = StudyUpload.shingles(it.pages.joined(separator: "\n"))
        guard mine.count >= StudyUpload.minShingles else { return }
        let root = StudyLibrary.shared.folderURL
        for p in StudyUpload.compareCandidates(s.sheets, root: s.sheetsRoot, proposal: it.proposal, fileName: it.name) {
            if it.exact.contains(p) || it.near.contains(where: { $0.path == p }) { continue }
            let theirs: Set<String>
            if let c = shingleCache[p] { theirs = c } else {
                let u = root.appendingPathComponent(p)
                let t = await Task.detached(priority: .utility) { Self.text(of: u) }.value
                theirs = StudyUpload.shingles(t)
                shingleCache[p] = theirs
            }
            let share = StudyUpload.overlap(mine, theirs)
            if share >= StudyUpload.near { it.near.append(Near(path: p, share: Int((share * 100).rounded()))) }
        }
        it.near.sort { $0.share > $1.share }
    }

    nonisolated static func text(of url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf" {
            guard let d = PDFDocument(url: url) else { return "" }
            return (0..<min(d.pageCount, 20)).compactMap { d.page(at: $0)?.string }.joined(separator: "\n")
        }
        if ["txt", "md"].contains(url.pathExtension.lowercased()) { return (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
        return ""
    }

    nonisolated static func sha256(_ d: Data) -> String { SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined() }

    // MARK: filing

    func target(_ f: Form) -> String? {
        guard let s = study else { return nil }
        return StudyUpload.targetPath(root: s.sheetsRoot, .init(unitFolder: f.unitFolder, existingSheet: f.existing.isEmpty ? nil : f.existing, title: f.title,
                                                                details: f.details, ms: f.ms, era: f.era.isEmpty ? nil : f.era,
                                                                fileName: StudySheets.fileNameFor(f.fileName, role: f.role)), max: StudyUpload.pathRoom)
    }

    /// The units typed in the form: "r2.2, R2.3" -> ["R2.2", "R2.3"].
    static func codes(_ text: String) -> [String] {
        var out: [String] = []
        for c in text.uppercased().components(separatedBy: CharacterSet(charactersIn: " ,;\t\n")) where c.range(of: #"^[SR][1-3](\.[0-9]{1,2})?$"#, options: .regularExpression) != nil {
            if !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// Writes the file where the form says (never over another: "name (2).pdf"), and its notes and units into study/sheets.yaml.
    func file(_ it: Item, store: NexusStore) -> String? {
        let f = it.form
        guard !f.unitFolder.trimmingCharacters(in: .whitespaces).isEmpty, !f.existing.isEmpty || !f.title.trimmingCharacters(in: .whitespaces).isEmpty,
              !f.fileName.trimmingCharacters(in: .whitespaces).isEmpty else { return "Give it a unit folder, a sheet title and a file name." }
        guard let s = study, let first = target(f) else { return "The study folder is gone." }
        let root = StudyLibrary.shared.folderURL, fm = FileManager.default
        it.status = .filing
        var path = first
        let slash = first.range(of: "/", options: .backwards)?.lowerBound ?? first.startIndex
        let dot = first.range(of: ".", options: .backwards).map { $0.lowerBound > slash ? $0.lowerBound : first.endIndex } ?? first.endIndex
        var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(path).path) { path = String(first[..<dot]) + " (\(n))" + String(first[dot...]); n += 1 }
        // the folders this filing makes (Undo removes them again while they are empty), deepest first
        var made: [String] = []
        var parts = path.components(separatedBy: "/"); parts.removeLast()
        let rootDepth = s.sheetsRoot.components(separatedBy: "/").count
        while parts.count > rootDepth, !fm.fileExists(atPath: root.appendingPathComponent(parts.joined(separator: "/")).path) {
            made.append(parts.joined(separator: "/")); parts.removeLast()
        }
        do {
            try fm.createDirectory(at: root.appendingPathComponent(path).deletingLastPathComponent(), withIntermediateDirectories: true)
            try FolderAccess.writeData(root.appendingPathComponent(path), it.data)
        } catch {
            it.status = .ready
            it.error = "Could not file it: \(error.localizedDescription)"
            return nil
        }
        it.status = .filed; it.target = path; it.made = made; it.doc = nil
        // what was confirmed beyond the name (the notes; the units) is kept in study/sheets.yaml by sheet folder
        let key = StudySheets.relIn(s.sheetsRoot, StudySheets.dirOf(path))
        let notes = f.notes.trimmingCharacters(in: .whitespacesAndNewlines), units = Self.codes(f.codes)
        if !notes.isEmpty || !units.isEmpty {
            let r = StudyLibrary.shared.keepSheetInfo(store, workstream: workstreamId, key: key, file: StudySheets.base(path), notes: notes, units: units)
            it.indexKey = key; it.indexWritten = r.written; it.indexBefore = r.before
        }
        store.didWrite()
        StudyLibrary.shared.load(store)
        lastFiled = it
        return nil
    }

    func skip(_ it: Item) { it.status = .skipped; it.doc = nil }

    /// Takes the last filed file back out (and the folders it made, while empty, and its sheets.yaml entry).
    func undo(_ it: Item, store: NexusStore) -> String {
        guard let path = it.target else { return "" }
        let root = StudyLibrary.shared.folderURL, fm = FileManager.default
        do {
            try fm.removeItem(at: root.appendingPathComponent(path))
            for d in it.made {
                let u = root.appendingPathComponent(d)
                if ((try? fm.contentsOfDirectory(atPath: u.path)) ?? ["x"]).isEmpty { try? fm.removeItem(at: u) } else { break }
            }
            if it.indexWritten, let key = it.indexKey { StudyLibrary.shared.restoreSheetInfo(store, workstream: workstreamId, key: key, before: it.indexBefore) }
            it.target = nil
            if lastFiled === it { lastFiled = nil }
            store.didWrite()
            StudyLibrary.shared.load(store)
            return "Taken back out"
        } catch {
            return "Could not take it back: \(error.localizedDescription)"
        }
    }
}

/// The upload's demo (the UI check, `-NexusStudyUploadDemo`): a sample worksheet is there to upload, and Claude's answer is canned.
enum UploadDemo {
    static var on: Bool { ProcessInfo.processInfo.arguments.contains("-NexusStudyUploadDemo") }

    static let sample = (name: "redox-hl-worksheet.pdf", data: SampleFolder.pdf([
        "Redox reactions: HL worksheet (25 marks)",
        "1. Deduce the oxidation state of manganese in KMnO4. [1]",
        "2. Write the half-equation for the reduction of MnO4- in acid. [2]",
        "3. Identify the oxidising agent in Zn + Cu2+ -> Zn2+ + Cu. [1]",
        "4. Describe how a voltaic cell produces electricity. [3]",
        "5. Balance the redox equation for dichromate and iron(II) ions. [3]",
        "Reactivity 3.2: electron transfer reactions. 2025 syllabus.",
    ]))

    static func reply(_ fileName: String) -> String {
        """
        ```json
        {"summary": "An HL worksheet on redox: oxidation states, half-equations, voltaic cells (R3.2), 25 marks.", "title": "Redox", \
        "units": [{"code": "R3.2", "section": ""}], "primaryUnit": "R3.2", "kind": "worksheet", "level": "HL", "marks": 25, "minutes": null, \
        "pages": 1, "hasMarkscheme": false, "role": "paper", "era": "2025", "unitFolder": "Reactivity 3.2 — Redox", "existingSheet": null, \
        "details": "HL worksheet, 25 mk", "fileName": "Redox worksheet.pdf", "duplicates": [], \
        "notes": "Question 4 is on voltaic cells, which come later in R3.2.", "unsure": false, "reason": ""}
        ```
        """
    }
}

// MARK: the sheet

struct UploadSheetView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var size
    let workstreamId: String

    @State private var up: SheetUpload
    @State private var importing = false
    @State private var scanning = false
    @State private var message: String?
    @State private var model = SheetUpload.model

    init(workstreamId: String) {
        self.workstreamId = workstreamId
        _up = State(initialValue: SheetUpload(workstreamId: workstreamId))
    }

    var body: some View {
        NavigationStack {
            Group {
                if up.items.isEmpty || up.done {
                    start
                } else if up.describing {
                    describe
                } else if let it = up.current {
                    UploadItemView(up: up, it: it, message: $message)
                } else {
                    start
                }
            }
            .navigationTitle("Upload a sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(up.items.isEmpty || up.done ? "Done" : up.items.count > 1 ? "Cancel all" : "Cancel") { up.cancel(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 10) {
                        ClaudeModeChip(small: true)
                        Menu {
                            Picker("Claude", selection: $model) {
                                Text("Sonnet").tag("sonnet")
                                Text("Haiku (quicker, cheaper)").tag("haiku")
                            }
                        } label: { Label("Model", systemImage: "ellipsis.circle") }
                    }
                }
            }
            .onChange(of: model) { _, m in SheetUpload.model = m }
            .safeAreaInset(edge: .bottom) {
                if let m = message {
                    Text(m).font(.callout).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 8)
                        .task(id: m) { try? await Task.sleep(for: .seconds(4)); if message == m { message = nil } }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .png, .jpeg, .heic, .plainText, UTType(filenameExtension: "md") ?? .plainText,
                                                                   UTType(filenameExtension: "docx") ?? .data], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            var files: [(name: String, data: Data)] = []
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: u) { files.append((u.lastPathComponent, d)) }
            }
            if up.done { up.items = [] }
            up.add(files)
        }
        .onAppear {
            if UploadDemo.on && up.items.isEmpty { up.add([UploadDemo.sample]) }
        }
    }

    // MARK: choosing

    private var start: some View {
        List {
            if let it = up.lastFiled, let t = it.target {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Filed \(StudySheets.base(t))", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.headline)
                        Text(t.replacingOccurrences(of: (up.study?.sheetsRoot ?? "") + "/", with: "").components(separatedBy: "/").dropLast().joined(separator: " › "))
                            .font(.callout).foregroundStyle(.secondary)
                        Button("Undo") { message = up.undo(it, store: store) }.buttonStyle(.bordered)
                            .accessibilityIdentifier("upload-undo")
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Button { importing = true } label: { Label("Choose files", systemImage: "folder") }
                    .accessibilityIdentifier("upload-choose")
                if ScanCamera.isSupported {
                    Button { scan() } label: { Label("Scan pages", systemImage: "doc.viewfinder") }
                }
            } footer: {
                Text("A PDF, a photo of a sheet, or a Word file. Claude reads it and says where it goes in \(up.study?.config.sheets ?? "the sheets folder"); you check, and file it.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func scan() {
        guard let top = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
        var vc = top
        while let p = vc.presentedViewController { vc = p }
        ScanCamera.present(from: vc) { pages in
            guard !pages.isEmpty else { return }
            ScanPDF.make(pages) { r in
                guard let r else { return }
                if up.done { up.items = [] }
                up.add([(r.name + ".pdf", r.data)])
            }
        }
    }

    // MARK: before anything is read: say what each file is, if you know

    private var describe: some View {
        List {
            Section {
                ForEach(up.items.filter { $0.status == .describe }) { it in
                    DescribeRow(it: it) { up.sortAll() }
                }
            } footer: {
                Text("Know what it is? Say so and Claude goes by that, without reading the whole sheet. Leave it blank and Claude reads it.")
            }
            Section {
                Button { up.sortAll() } label: { Text("Sort it").font(.headline).frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("upload-sort")
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct DescribeRow: View {
    @Bindable var it: SheetUpload.Item
    let go: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(it.name, systemImage: "doc").font(.subheadline.weight(.semibold)).lineLimit(1)
            TextField("e.g. Energetics HL test, 40 marks, R1.1 and R1.2, with markscheme", text: $it.note, axis: .vertical)
                .lineLimit(1...3)
                .onSubmit(go)
        }
        .padding(.vertical, 2)
    }
}

/// One file: what is happening to it, then Claude's proposal as a form.
private struct UploadItemView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    let up: SheetUpload
    @Bindable var it: SheetUpload.Item
    @Binding var message: String?
    @State private var tellText = ""
    @State private var newUnit = false
    @State private var moreOpen = false
    @State private var preview: URL?

    var body: some View {
        if let step = step {
            VStack(spacing: 14) {
                ProgressView()
                Text(step).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .accessibilityIdentifier("upload-step")
                if up.items.count > 1, let i = up.items.firstIndex(where: { $0 === it }) { Text("\(it.name) · \(i + 1) of \(up.items.count)").font(.caption).foregroundStyle(.tertiary) }
            }
            .padding(30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if it.status == .error {
            List {
                Section {
                    Label(it.error ?? "Something went wrong.", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.late)
                    Button("Skip it") { up.skip(it) }
                }
            }
        } else if let p = it.proposal {
            form(p)
                .quickLookPreview($preview)
        }
    }

    private var step: String? {
        switch it.status {
        case .reading: return "Reading it…"
        case .ocr: return "Reading the scan on this \(Device.name): page \(min(it.ocrDone.count + 1, max(it.ocrPlan, 1))) of \(max(it.ocrPlan, 1))…"
        case .claude: return it.sent.isEmpty ? "Claude is reading it and finding where it belongs…" : "Claude is looking at the pages…"
        case .compare: return "Comparing it with the sheets that look alike…"
        case .filing: return "Filing it…"
        default: return nil
        }
    }

    private var root: String { up.study?.sheetsRoot ?? "" }
    private func rel(_ p: String) -> String { p.hasPrefix(root + "/") ? String(p.dropFirst(root.count + 1)) : p }
    private func open(_ p: String) { preview = StudyLibrary.shared.folderURL.appendingPathComponent(p) }

    @ViewBuilder
    private func form(_ p: StudyUpload.Proposal) -> some View {
        let groups = (up.study?.sheets.groups ?? []).map { StudySheets.relIn(root, $0.path) }
        let isNew = !it.form.unitFolder.isEmpty && !groups.contains(it.form.unitFolder)
        let sheetsHere = (up.study?.sheets.sheets ?? []).filter { $0.dir && $0.group.map { StudySheets.relIn(root, $0.path) } == it.form.unitFolder }
        let more = up.morePictures(it)
        let wide = size == .regular
        Form {
            Section {
                if up.items.count > 1, let i = up.items.firstIndex(where: { $0 === it }) {
                    Text("\(it.name) · \(i + 1) of \(up.items.count)").font(.caption).foregroundStyle(.secondary)
                }
                if !p.summary.isEmpty { Label(p.summary, systemImage: "sparkles").accessibilityIdentifier("upload-summary") }
                Text(howText).font(.caption).foregroundStyle(.secondary)
                if let e = it.error { Label(e, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Theme.soon) }
                if let e = it.ocrError { Text("The scanned pages could not be read: \(e).").font(.callout).foregroundStyle(Theme.soon) }
                if p.unsure {
                    VStack(alignment: .leading, spacing: 8) {
                        (Text("Claude is not sure. ").bold() + Text(p.reason)).font(.callout)
                        if !more.pages.isEmpty {
                            Button { up.readMore(it) } label: {
                                Label(more.extra > 0 ? "Read \(more.extra) more page\(more.extra == 1 ? "" : "s")" : "Show Claude the page\(more.pages.count == 1 ? "" : "s")", systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !p.codes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(p.multi ? "Covers several units, so it goes in Multi-Topic Papers:" : "Covers:").font(.caption).foregroundStyle(.secondary)
                        FlowRow(spacing: 6) {
                            ForEach(Array((p.sections.isEmpty ? [StudyUpload.Section(name: "", codes: p.codes)] : p.sections).enumerated()), id: \.offset) { _, s in
                                Chip(text: (s.name.isEmpty ? "" : s.name + " ") + s.codes.joined(separator: ", "), color: Theme.accent)
                            }
                        }
                    }
                }
                HStack {
                    TextField("Not right? Tell Claude what this sheet is", text: $tellText)
                        .onSubmit { up.tell(it, tellText) }
                    Button("Ask again") { up.tell(it, tellText) }.disabled(tellText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Possible duplicates") {
                if it.exact.isEmpty && it.near.isEmpty && it.same.isEmpty && p.duplicates.isEmpty {
                    Text("None found: no file with the same bytes or name, and no sheet Claude or the text check flagged.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(it.exact, id: \.self) { x in dup("The same file is already here:", x, "doc.on.doc.fill") }
                ForEach(it.near, id: \.path) { x in dup("\(x.share)% of its text is in", x.path, "doc.on.doc") }
                ForEach(it.same.filter { s in !it.near.contains { $0.path == s } }, id: \.self) { x in dup("A file with the same name:", x, "doc.on.doc") }
                ForEach(p.duplicates, id: \.path) { d in
                    Label { Text("Claude: may repeat ") + Text(d.path).bold() + Text(d.why.isEmpty ? "" : " (\(d.why))") } icon: { Image(systemName: "sparkles") }.font(.callout)
                }
            }

            Section {
                Picker("Unit folder", selection: Binding(get: { isNew || newUnit ? "\u{0}new" : it.form.unitFolder }, set: { v in
                    if v == "\u{0}new" {
                        newUnit = true
                        it.form.unitFolder = StudySheets.newUnitFolderName(up.study?.sheets.groups ?? [], label: "New unit", root: root)
                    } else { newUnit = false; it.form.unitFolder = v }
                    it.form.existing = ""
                })) {
                    ForEach(groups, id: \.self) { g in Text(g.components(separatedBy: "/").joined(separator: " › ")).tag(g) }
                    Text("New unit folder…").tag("\u{0}new")
                }
                .accessibilityIdentifier("upload-unit")
                if isNew || newUnit {
                    TextField("New unit folder name", text: $it.form.unitFolder)
                }
                Picker("Sheet", selection: $it.form.existing) {
                    Text("A new sheet folder").tag("")
                    ForEach(sheetsHere, id: \.path) { s in Text(StudySheets.base(s.path)).tag(StudySheets.base(s.path)) }
                }
                if it.form.existing.isEmpty {
                    LabeledContent("Title") { TextField("Title", text: $it.form.title).multilineTextAlignment(.trailing) }
                    LabeledContent("Details") { TextField("HL test, 40 mk, 60 min", text: $it.form.details).multilineTextAlignment(.trailing) }
                }
            } header: {
                Text("Where it goes")
            }

            Section {
                DisclosureGroup("More details", isExpanded: Binding(get: { wide || moreOpen }, set: { moreOpen = $0 })) {
                    if it.form.existing.isEmpty {
                        Picker("Syllabus", selection: $it.form.era) {
                            Text("2025 syllabus").tag("2025"); Text("Before 2025").tag("pre-2025"); Text("Not marked").tag("")
                        }
                        Picker("Markscheme", selection: $it.form.ms) {
                            Text("Has one (or will)").tag("with"); Text("None (\"no MS\")").tag("none"); Text("Only a markscheme").tag("only")
                        }
                    }
                    Picker("This file is", selection: $it.form.role) {
                        Text("The paper").tag("paper"); Text("The markscheme").tag("ms"); Text("A marked copy").tag("marked")
                    }
                    LabeledContent("File name") { TextField("File name", text: $it.form.fileName).multilineTextAlignment(.trailing) }
                    LabeledContent("Units") {
                        TextField("e.g. R2.2, R2.3", text: $it.form.codes).multilineTextAlignment(.trailing)
                            .autocorrectionDisabled().textInputAutocapitalization(.characters)
                    }
                    TextField("Notes: anything to remember about this sheet", text: $it.form.notes, axis: .vertical).lineLimit(1...4)
                }
            }

            Section {
                if let t = up.target(it.form) {
                    (Text("It goes to ").foregroundStyle(.secondary) + Text(rel(t).components(separatedBy: "/").joined(separator: " › ")).bold())
                        .font(.callout)
                        .accessibilityIdentifier("upload-where")
                }
                Button {
                    if let e = up.file(it, store: store) { message = e } else if let t = it.target { message = "Filed \(StudySheets.base(t))" }
                } label: {
                    Text(it.exact.isEmpty ? "File it" : "File it anyway").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!StudyLibrary.shared.canWrite(store))
                .accessibilityIdentifier("upload-file")
                Button(up.items.count > 1 && up.items.last !== it ? "Skip, next file" : "Don’t file it", role: .destructive) { up.skip(it) }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dup(_ text: String, _ path: String, _ icon: String) -> some View {
        Button { open(path) } label: {
            Label { Text(text + " ").foregroundStyle(.primary) + Text(rel(path)).foregroundStyle(Theme.accent) } icon: { Image(systemName: icon) }
                .font(.callout)
        }
    }

    private var howText: String {
        let pages = "\(it.nPages) page\(it.nPages == 1 ? "" : "s")"
        let tokens = it.tokens.map { " · about \(Double(($0 + 50) / 100) / 10)k tokens" } ?? ""
        if !it.note.isEmpty { return "Claude went by your description (\(pages))\(tokens)." }
        let mixed = it.how == "ocr" && it.ocrNeed.count < min(it.nPages, SheetUpload.ocrMax)
        let what = mixed ? "its text and, read on this \(Device.name), its \(it.ocrNeed.count) scanned page\(it.ocrNeed.count == 1 ? "" : "s")"
            : it.how == "ocr" ? "the scan, read on this \(Device.name)" : it.how == "images" ? "pictures of its pages" : "its text"
        let pics = it.sent.isEmpty ? "" : " and pictures of page\(it.sent.count > 1 ? "s" : "") \(it.sent.map(String.init).joined(separator: ", "))"
        return "Claude read \(what)\(pics) (\(pages))\(tokens)."
    }
}
