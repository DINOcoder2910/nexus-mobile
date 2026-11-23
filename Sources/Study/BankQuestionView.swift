import SwiftUI
import PDFKit
import NexusCore

/// One question of the question bank, as the laptop's `BankQuestion.tsx` has it: its place on the paper's board (a picture of the
/// board there, ink included; tap it to write there), what it was sorted as and by whom, the markscheme at this question one tap
/// away (M), and the marks: 1 Done, 2 Hard, 3 Review later. J and K go to the next and the previous question of the paper; B keeps
/// your place in it (the bookmark Study shows). The laptop writes in a live clip of the board; here the board opens at the question.
struct BankQuestionView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    let workstreamId: String
    let paper: String
    @State var q: String

    @State private var showMs = false
    @State private var ms: BankPdf.Spot?
    @State private var msLooked = false
    @State private var clip: UIImage?
    @State private var clipKey = ""

    init(workstreamId: String, paper: String, q: String) {
        self.workstreamId = workstreamId
        self.paper = paper
        _q = State(initialValue: q)
    }

    private var lib: BankLibrary { BankLibrary.shared }

    var body: some View {
        let b = lib.bank(workstreamId)
        let sp = b?.questions[paper]
        let v = sp?.merged(q)
        let order = sp?.questions.keys ?? []
        let i = order.firstIndex(of: q) ?? 0
        Group {
            if let b, let v {
                if size == .regular && showMs, let ms {
                    HStack(spacing: 0) {
                        page(b, v, order: order, i: i).frame(minWidth: 380)
                        Divider().ignoresSafeArea()
                        MarkschemePane(root: store.folder, spot: ms, close: { showMs = false })
                    }
                } else {
                    page(b, v, order: order, i: i)
                }
            } else {
                EmptyNote(title: "This question isn't in the bank", detail: "The laptop may have sorted the paper again: open it from the bank.", icon: "questionmark.circle")
            }
        }
        .navigationTitle((v?["label"]?.string) ?? QuestionBank.qName(q))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { go(order, i - 1) } label: { Label("Previous question", systemImage: "chevron.up") }
                    .disabled(i <= 0).keyboardShortcut("k", modifiers: []).accessibilityIdentifier("bq-prev")
                Text("\(i + 1) of \(order.count)").font(.nx(.callout)).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityIdentifier("bq-count")
                Button { go(order, i + 1) } label: { Label("Next question", systemImage: "chevron.down") }
                    .disabled(i >= order.count - 1).keyboardShortcut("j", modifiers: []).accessibilityIdentifier("bq-next")
                Button { keepPlace() } label: { Label("Keep my place", systemImage: b?.marks.bookmark(paper) == q ? "bookmark.fill" : "bookmark") }
                    .keyboardShortcut("b", modifiers: []).accessibilityIdentifier("bq-bookmark")
            }
        }
        .sheet(isPresented: Binding(get: { showMs && size != .regular && ms != nil }, set: { if !$0 { showMs = false } })) {
            if let ms {
                NavigationStack {
                    MarkschemePane(root: store.folder, spot: ms, close: { showMs = false })
                }
                .presentationDetents([.medium, .large])
            }
        }
        .task(id: q) { await lookUpMarkscheme() }
        .task(id: "\(q)|\(placeKey(b))") { renderClip(b) }
        .studyRefresh(store)
        .task {
            while !Task.isCancelled {
                if let s = StudyLibrary.shared.study(workstreamId) { lib.refresh(s, root: store.folder) }
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .onAppear { lib.returnTo = nil }
        // on the iPhone the board covers this page, which stays: back here, nothing to go back to
        .onChange(of: store.openBoard == nil) { _, closed in
            if closed {
                lib.returnTo = nil
                BankClip.forget()
                clipKey = ""
                if let s = StudyLibrary.shared.study(workstreamId) { lib.refresh(s, root: store.folder, force: true) }
            }
        }
    }

    @ViewBuilder
    private func page(_ b: BankLibrary.Bank, _ v: JSONValue, order: [String], i: Int) -> some View {
        let r = QuestionBank.Row(paper: paper, q: q, title: "", isClass: false, facts: .object([]), sort: v)
        let place = b.places[paper + "#" + q]
        let mark = b.marks.mark(paper, q)
        let facts = b.questions[paper]?.facts.value ?? .object([])
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.topics.isEmpty ? "No unit yet" + (r.meta.isEmpty ? "" : " · " + r.meta) : r.meta)
                        .font(.nx(.callout, .medium))
                    Text(Self.sortedBy(r)).font(.nx(.caption)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("bq-facts")
                if facts["kind"]?.string == "class" {
                    Button { store.openBoard = .init(path: paper, focus: nil) } label: {
                        Label {
                            Text("From \(facts["from"]?.string ?? QuestionBank.boardName(paper))" + (facts["classDate"]?.string.map { ", class \($0)" } ?? "")
                                 + (facts["course"]?.string.map { " · \($0)" } ?? ""))
                        } icon: { Image(systemName: "rectangle.on.rectangle") }
                        .font(.nx(.callout))
                    }
                    .accessibilityIdentifier("bq-from")
                }
            }
            Section {
                if let place {
                    Button { writeHere(place) } label: {
                        Group {
                            if let clip {
                                Image(uiImage: clip).resizable().scaledToFit()
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .accessibilityLabel("The question on its board: tap to write there")
                    .accessibilityIdentifier("bq-clip")
                    Button { writeHere(place) } label: { Label("Write on it", systemImage: "pencil.and.scribble") }
                        .accessibilityIdentifier("bq-board")
                } else if paper.lowercased().hasSuffix(".pdf") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This paper has no board yet.").font(.nx(.callout)).foregroundStyle(.secondary)
                        Button { store.writeOn(pdf: paper) } label: { Label("Write on it", systemImage: "pencil.and.scribble") }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                            .accessibilityIdentifier("bq-write")
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                SectionTitle(title: place.map { $0.strokes > 0 ? "On its board · \(BankView.plural($0.strokes, "stroke"))" : "On its board" } ?? "The question")
            }
            Section {
                HStack(spacing: 8) {
                    ForEach(Array(QuestionBank.marks.enumerated()), id: \.element) { k, m in
                        Button { lib.mark(store, workstreamId, paper: paper, q: q, m) } label: {
                            HStack(spacing: 6) {
                                Text("\(k + 1)").font(.nx(.caption, .semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                                Text(QuestionBank.markWord[m] ?? m).font(.nx(.callout, .medium)).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(mark == m ? Color.white : Color.primary)
                            .background(mark == m ? BankMarks.color(m) : Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(KeyEquivalent(Character(String(k + 1))), modifiers: [])
                        .disabled(!lib.canWrite(store))
                        .accessibilityAddTraits(mark == m ? .isSelected : [])
                        .accessibilityIdentifier("bq-" + m)
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                if let ms {
                    Button { showMs.toggle() } label: {
                        Label(showMs ? "Hide the markscheme" : "Markscheme" + (ms.q.map { " at \(QuestionBank.qName($0))" } ?? ""), systemImage: "checkmark.seal")
                    }
                    .keyboardShortcut("m", modifiers: [])
                    .accessibilityIdentifier("bq-ms")
                } else if msLooked {
                    Text("No markscheme found for this paper.").font(.nx(.callout)).foregroundStyle(.secondary)
                }
            } header: {
                SectionTitle(title: "How did it go?")
            } footer: {
                if let m = mark, let at = b.marks.markedAt(paper, q) { Text("\(QuestionBank.markWord[m] ?? m), \(BankView.when(at)). Tap it again to take it back.") }
            }
            Section {
                fixRows(b, r)
            } header: {
                SectionTitle(title: "Sorted wrong? Change it")
            } footer: {
                Text("Your change is kept when the laptop sorts the paper again.")
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func fixRows(_ b: BankLibrary.Bank, _ r: QuestionBank.Row) -> some View {
        Picker("Unit", selection: Binding(get: { r.topics.first ?? "" }, set: { u in
            lib.fix(store, workstreamId, paper: paper, q: q, [("topics", u.isEmpty ? nil : JSONValue.array([.string(u)]))])
        })) {
            Text(r.fixed.contains("topics") ? "As sorted" : (r.topics.first.map { "\($0) (as sorted)" } ?? "None")).tag("")
            ForEach(b.units, id: \.code) { u in Text("\(u.code) \(u.title)").tag(u.code) }
        }
        .disabled(!lib.canWrite(store))
        .accessibilityIdentifier("bq-fix-unit")
        Picker("Type", selection: Binding(get: { r.type }, set: { t in lib.fix(store, workstreamId, paper: paper, q: q, [("type", .string(t))]) })) {
            ForEach(QuestionBank.types, id: \.self) { t in Text(QuestionBank.typeWord[t] ?? t).tag(t) }
        }
        .disabled(!lib.canWrite(store))
        .accessibilityIdentifier("bq-fix-type")
    }

    static func sortedBy(_ r: QuestionBank.Row) -> String {
        let by = ["decider": "the decision model", "claude": "Claude", "decider+claude": "the decision model and Claude", "none": "nobody yet"][r.by] ?? r.by
        var s = "Sorted by \(by)"
        if let sure = r.sure, r.by != "claude" { s += " (\(Int((sure * 100).rounded()))% sure)" }
        if !r.fixed.isEmpty { s += ", changed by you" }
        return s
    }

    // MARK: actions

    private func go(_ order: [String], _ to: Int) {
        guard order.indices.contains(to) else { return }
        clip = nil
        ms = nil
        msLooked = false
        q = order[to]
    }

    private func keepPlace() {
        lib.bookmark(store, workstreamId, paper: paper, q: q)
        let name = ((paper as NSString).lastPathComponent as NSString).deletingPathExtension
        store.toast = .init(message: "Your place in \(name) is \(QuestionBank.qName(q)).")
    }

    /// The board, opened at the question (and back to this question when it closes).
    private func writeHere(_ place: BankLibrary.Place) {
        lib.returnTo = (workstreamId, BankTarget(paper: paper, q: q))
        store.openBoard = .init(path: place.board, focus: Self.union(place.rects))
    }

    static func union(_ rects: [[Double]]) -> CGRect? {
        rects.map { CGRect(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) }.reduce(CGRect?.none) { a, r in a.map { $0.union(r) } ?? r }
    }

    private func placeKey(_ b: BankLibrary.Bank?) -> String {
        guard let p = b?.places[paper + "#" + q] else { return "" }
        return "\(p.board)|\(p.strokes)|\(p.last)|\(p.rects)"
    }

    private func lookUpMarkscheme() async {
        // a question imported with its answers' place (a textbook's answers pages: ms {page, y, path?}) has it stored, as on the laptop
        if let m = lib.bank(workstreamId)?.questions[paper]?.merged(q)?["ms"], let page = m["page"]?.number, let y = m["y"]?.number {
            ms = BankPdf.Spot(path: m["path"]?.string ?? paper, q: nil, page: Int(page), y: y)
            msLooked = true
            return
        }
        guard paper.lowercased().hasSuffix(".pdf") else { msLooked = true; return }
        let root = store.folder, paper = paper, q = q
        let msPath = lib.bank(workstreamId)?.papers.first { $0.path == paper }?.markscheme
        let spot = await Task.detached(priority: .userInitiated) { BankPdf.markschemeSpot(root: root, paper: paper, q: q, markscheme: msPath) }.value
        guard q == self.q else { return }
        ms = spot
        msLooked = true
    }

    /// The question's place on its board as a picture: the printout's pages there with the ink, each part of the place under the last.
    private func renderClip(_ b: BankLibrary.Bank?) {
        let key = placeKey(b)
        guard let place = b?.places[paper + "#" + q], key != clipKey || clip == nil else { return }
        clipKey = key
        clip = BankClip.image(root: store.folder, board: place.board, rects: place.rects, width: 900)
    }
}

/// A picture of part of a board (BoardExport's drawing: the printouts from the PDF, the items, the ink).
enum BankClip {
    @MainActor private static var cached: (path: String, board: BoardController)?

    @MainActor
    static func image(root: URL, board path: String, rects: [[Double]], width: CGFloat) -> UIImage? {
        let rs = rects.map { CGRect(x: $0[0], y: $0[1], width: $0[2] - $0[0], height: $0[3] - $0[1]) }.filter { $0.width > 1 && $0.height > 1 }
        guard let widest = rs.map(\.width).max() else { return nil }
        let b: BoardController
        if let c = cached, c.path == path, c.board.root == root {
            b = c.board
        } else {
            b = BoardController(root: root, path: path, focus: nil)
            b.replay = true // read-only, nothing logged
            b.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
            b.view.layoutIfNeeded()
            b.poll?.invalidate()
            cached = (path, b)
        }
        let k = width / widest
        let gap: CGFloat = 10
        let total = rs.reduce(0) { $0 + $1.height * k } + gap * CGFloat(max(0, rs.count - 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let full = UIGraphicsImageRenderer(size: CGSize(width: width, height: max(1, total)), format: format).image { ctx in
            var y: CGFloat = 0
            for r in rs {
                let h = r.height * k
                let page = CGRect(x: 0, y: 0, width: r.width * k, height: h)
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: 0, y: y)
                ctx.cgContext.clip(to: page)
                BoardExport.draw(b, r, in: ctx.cgContext, k: k, page: page)
                ctx.cgContext.restoreGState()
                y += h + gap
            }
        }
        return trimBottom(full)
    }

    /// The picture without the blank paper under what is there (the last question of a page runs to the page's foot), keeping a
    /// little margin.
    static func trimBottom(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return image }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return image }
        // the bitmap's first row is the picture's top; the last row with anything darker than near-white is its foot
        var last = -1
        for row in stride(from: h - 1, through: 0, by: -1) {
            let base = row * w * 4
            var ink = false
            for x in stride(from: 0, to: w, by: 2) where px[base + x * 4] < 235 || px[base + x * 4 + 1] < 235 || px[base + x * 4 + 2] < 235 {
                ink = true
                break
            }
            if ink { last = row; break }
        }
        let keep = min(h, max(last + Int(40 * image.scale), Int(120 * image.scale)))
        guard last >= 0, keep < h - Int(20 * image.scale), let cut = cg.cropping(to: CGRect(x: 0, y: 0, width: w, height: keep)) else { return image }
        return UIImage(cgImage: cut, scale: image.scale, orientation: .up)
    }

    /// Forget the board read for pictures (a board written on since shows its new ink).
    @MainActor static func forget() { cached = nil }
}

/// The markscheme at a question: its PDF, scrolled to where the answer starts.
struct MarkschemePane: View {
    let root: URL
    let spot: BankPdf.Spot
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(spot.q.map { "Markscheme at \(QuestionBank.qName($0))" } ?? "Markscheme", systemImage: "checkmark.seal")
                    .font(.nx(.callout, .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close the markscheme")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            PdfSpotView(url: root.appendingPathComponent(spot.path), page: spot.page, y: spot.y)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bq-ms-pane")
    }
}

/// A PDF shown from a place: a page and how far down it.
struct PdfSpotView: UIViewRepresentable {
    let url: URL
    let page: Int
    let y: Double

    final class Coordinator { var shown = "" }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .secondarySystemBackground
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        let key = "\(url.path)|\(page)|\(y)"
        guard context.coordinator.shown != key else { return }
        context.coordinator.shown = key
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
        guard let p = v.document?.page(at: page) else { return }
        let box = p.bounds(for: .mediaBox)
        let at = CGPoint(x: box.minX, y: min(box.maxY, box.maxY - CGFloat(y) * box.height + 24))
        DispatchQueue.main.async { v.go(to: PDFDestination(page: p, at: at)) }
    }
}
