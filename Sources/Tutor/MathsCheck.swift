import SwiftUI
import NexusCore

/// Check my maths (the laptop's tutor tab of the same name): lines of working checked by the computer, not guessed by a model. The shared
/// Rust core (tutor/maths.rs, the code the laptop runs) compares each line with the one before by working it out: an expression must
/// keep its value, an equation its solutions, so a sign slip or a lost solution is found. The first slip is marked, and the tutor can
/// give a hint about it (Hints only: what went wrong, not the answer). The working can be typed, taken from a text block, or read off
/// the screen: Claude reads the question and the handwritten working from a picture of the board (it only copies them out; the core
/// does the checking), or, without Claude, Vision reads the handwriting. It stays editable, so a misread line can be fixed.
struct MathsCheckView: View {
    let tutor: BoardTutor
    var onDone: () -> Void
    @State private var lines = ""
    @State private var result: RustCore.Maths?
    /// the text `result` is for (an edit after it hides the result until Check again)
    @State private var checked = ""
    @State private var nothingOnBoard = false
    /// reading the handwriting on screen
    @State private var reading = false
    /// the working in the box was read off the screen (a note says by whom, and to fix a misread line)
    @State private var fromInk: MathsReading.Reader?
    /// the question read off the screen with the working
    @State private var question: String?
    @FocusState private var typing: Bool

    init(tutor: BoardTutor, onDone: @escaping () -> Void) {
        self.tutor = tutor
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("One line of working a line. Nexus checks each against the line before by working it out, so a slip is found, not guessed.")
                        .font(.nx(.subheadline)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    editor
                    HStack(spacing: 10) {
                        Button { fromBoard() } label: { Label("From the board", systemImage: "text.viewfinder") }
                            .buttonStyle(.bordered)
                            .disabled(reading)
                            .accessibilityIdentifier("maths-from-board")
                        if reading {
                            ProgressView().controlSize(.small)
                            Text("Reading your board…").font(.nx(.footnote)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button { check() } label: { Label("Check", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent).tint(TutorStyle.brand)
                            .disabled(lines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("maths-check")
                    }
                    .controlSize(.regular)
                    if nothingOnBoard {
                        Text("Nothing to read: write your working on the board where you can see it, select a text block, or type it here.")
                            .font(.nx(.footnote)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let q = question {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("The question").font(.nx(.caption, .semibold)).foregroundStyle(.secondary)
                            Text(q).font(.nx(.callout)).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("maths-question")
                    }
                    if let by = fromInk {
                        Label(by == .claude ? "Claude copied this off your board. If a line was misread, fix it above and Check again."
                                            : "Read from your handwriting. If a line was misread, fix it above and Check again.",
                              systemImage: "pencil.and.scribble")
                            .font(.nx(.footnote)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("maths-from-ink")
                    }
                    if let r = result, checked == lines {
                        results(r)
                        verdict(r)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Check my maths")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) } }
        }
        .onAppear {
            guard lines.isEmpty else { return }
            if let t = tutor.mathsFromBoard() { lines = t; check() }
            else if tutor.inkOnScreen { readInk() }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $lines)
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .focused($typing)
                .accessibilityIdentifier("maths-input")
            if lines.isEmpty {
                Text("2x + 6 = 14\n2x = 8\nx = 4")
                    .font(.system(.body, design: .monospaced)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .padding(8)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One row a written line: ✓ follows, ✗ the slip, – not compared (the first line, or one it couldn't read), with why.
    private func results(_ r: RustCore.Maths) -> some View {
        let src = lines.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(src.enumerated()), id: \.offset) { i, l in
                if i < r.lines.count, let c = r.lines[i] {
                    lineRow(l, c, first: r.first == i)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maths-result")
    }

    private func lineRow(_ text: String, _ c: RustCore.Maths.Line, first: Bool) -> some View {
        let mark = c.ok == true ? "checkmark.circle.fill" : c.ok == false ? "xmark.circle.fill" : "minus.circle"
        let tint: Color = c.ok == true ? .green : c.ok == false ? .red : .secondary
        let fill: Color = first ? Color.red.opacity(0.09) : Color(uiColor: .secondarySystemBackground)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: mark).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(text.trimmingCharacters(in: .whitespaces)).font(.system(.callout, design: .monospaced))
                if !c.why.isEmpty {
                    Text(c.why).font(.nx(.caption)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("maths-line")
        .accessibilityValue(c.ok == true ? "good" : c.ok == false ? "bad" : "none")
    }

    private func verdict(_ r: RustCore.Maths) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let n = r.firstWritten {
                Label("Line \(n) is the first slip", systemImage: "exclamationmark.triangle.fill")
                    .font(.nx(.subheadline, .semibold)).foregroundStyle(.orange)
            } else {
                Label("Every line follows from the one before", systemImage: "checkmark.seal.fill")
                    .font(.nx(.subheadline, .semibold)).foregroundStyle(.green)
            }
            if let a = r.answer {
                Text("The first equation's solutions: \(a)").font(.nx(.footnote)).foregroundStyle(.secondary)
            }
            if r.first != nil {
                Button { hint(r) } label: { Label("Ask the tutor for a hint", systemImage: "lightbulb") }
                    .buttonStyle(.borderedProminent).tint(TutorStyle.brand)
                    .disabled(tutor.busy)
                    .accessibilityIdentifier("maths-hint")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("maths-verdict")
    }

    private func check() {
        result = RustCore.checkMaths(lines.components(separatedBy: "\n"))
        checked = lines
        typing = false // (the keyboard down, so the marks show)
    }

    /// A text block being written in or selected, else the handwriting on screen.
    private func fromBoard() {
        nothingOnBoard = false
        if let t = tutor.mathsFromBoard() { fromInk = nil; question = nil; lines = t; check() } else { readInk() }
    }

    private func readInk() {
        reading = true
        Task { @MainActor in
            let r = await tutor.mathsFromScreen()
            reading = false
            guard let r else { nothingOnBoard = true; return }
            nothingOnBoard = false
            fromInk = r.reader
            question = r.question
            lines = r.lines.joined(separator: "\n")
            check()
        }
    }

    /// The laptop's words for it: the working, the line that doesn't follow and why, and a hint asked for, not the answer.
    private func hint(_ r: RustCore.Maths) {
        guard let f = r.first else { return }
        let src = lines.components(separatedBy: "\n")
        let bad = f < src.count ? src[f].trimmingCharacters(in: .whitespaces) : ""
        let why = r.lines[f]?.why ?? ""
        let working = src.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        let asked = question.map { "The question: \($0)\n" } ?? ""
        onDone()
        tutor.ask("\(asked)I'm checking my working:\n\(working)\nNexus found that the line \"\(bad)\" does not follow from the one before (\(why)). Give me a hint about what went wrong, not the answer.", kind: .hint)
    }

    /// A line of the board's words as working: $ signs and a list mark off (as the laptop takes them).
    nonisolated static func clean(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: #"^\$\$?|\$\$?$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Handwritten lines (each with its place on the board) as lines of working, top to bottom: pieces read side by side (Vision
    /// can split a line, or a chunk edge does) join into one line, left to right. A capital X is the variable x (Vision often reads
    /// a handwritten x as X).
    nonisolated static func rows(_ found: [(text: String, box: CGRect)]) -> [String] {
        var rows: [[(text: String, box: CGRect)]] = []
        for f in found.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let last = rows.last?.last, abs(f.box.midY - last.box.midY) < max(f.box.height, last.box.height) * 0.5 {
                rows[rows.count - 1].append(f)
            } else {
                rows.append([f])
            }
        }
        return rows.map { row in
            let s = row.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
            return clean(s.replacingOccurrences(of: "X", with: "x"))
        }.filter { !$0.isEmpty }
    }
}

extension BoardTutor {
    /// Check my maths' "From the board": the words of the text block being written in, or else the one selected, a line of working a
    /// line (blank lines left out). Nil when there is none.
    func mathsFromBoard() -> String? {
        var md: String?
        if let w = board.writing { md = w.textView.text }
        else if let it = board.selectedItem, it.type == "text" { md = board.content.texts[board.shownKey(it.id)] }
        guard let md else { return nil }
        let lines = md.components(separatedBy: "\n").map(MathsCheckView.clean).filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// `-NexusTestFakeHandwriting` (UITests/TutorPanelTests): the board counts as having ink on screen, and with -NexusTutorDemo the
    /// reading is a canned reply in Claude's place, as the simulator's board has no handwriting.
    static let fakeHandwriting = ProcessInfo.processInfo.arguments.contains("-NexusTestFakeHandwriting")

    /// The strokes on screen (less the bar and the tutor's panel), as the tutor sees them.
    private var strokesOnScreen: [BoardStroke] {
        let visible = board.boardRect(ofView: board.tutorArea)
        return board.content.strokes.filter { st in st.points.contains { visible.contains(CGPoint(x: $0[0], y: $0[1])) } }
    }

    var inkOnScreen: Bool { BoardTutor.fakeHandwriting || !strokesOnScreen.isEmpty }

    /// Check my maths off the screen: Claude reads the question and the working from a picture of the board (it copies, the core
    /// checks); without Claude (no plan or key, offline) Vision reads the handwriting. Nil when there is nothing to read.
    func mathsFromScreen() async -> MathsReading? {
        if let r = await mathsByClaude() { return r }
        return await mathsByVision()
    }

    private func mathsByClaude() async -> MathsReading? {
        let text: String
        if TutorDemo.active {
            guard BoardTutor.fakeHandwriting else { return nil }
            try? await Task.sleep(for: .milliseconds(800))
            text = MathsReading.demoReply
        } else {
            let area = board.tutorArea
            let visible = board.boardRect(ofView: area)
            guard let image = snapshot(visible: visible, frame: [visible.minX, visible.minY], area: area, grid: false) else { return nil }
            var req = ClaudeRequest(model: BoardTutor.model, system: MathsReading.prompt,
                                    messages: [ClaudeMessage(role: "user", content: [.image(mediaType: "image/jpeg", base64: image.base64EncodedString()),
                                                                                       .text("Copy out the question and my working.")])])
            req.maxTokens = 1024
            req.effort = "low"
            guard let reply = try? await ClaudeClient.shared.stream(req, onText: { _ in }) else { return nil }
            text = reply.text
        }
        return MathsReading.parse(text)
    }

    private func mathsByVision() async -> MathsReading? {
        let strokes = strokesOnScreen
        guard !strokes.isEmpty else { return nil }
        let lines = await Task.detached(priority: .userInitiated) { HandwritingIndex.Worker.handwrittenLines(strokes).lines }.value
        let rows = MathsCheckView.rows(lines.map { (text: $0.text, box: CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)) })
        return rows.isEmpty ? nil : MathsReading(question: nil, lines: rows, reader: .vision)
    }
}

/// What was read off the screen for Check my maths: the question (when one is there) and the working, a line of working a line, the
/// first line being the equation or expression the question gives when the working doesn't write it.
struct MathsReading {
    enum Reader { case claude, vision }
    var question: String?
    var lines: [String]
    var reader: Reader

    /// Claude only copies: it never checks, corrects or finishes the working (the core does the checking).
    static let prompt = """
    You copy a student's maths off a picture of their iPad board for a program that checks each line by working it out. Reply with \
    one JSON object and nothing else:
    {"question": "<the question as written, if one is on the board, else null>", "start": "<the equation or expression the question \
    gives to work on, as a line of working, else null>", "lines": ["<each line of the student's working, top to bottom>"]}
    Write maths as plain text: ^ for powers (x^2), sqrt(...), (a)/(b) for fractions, * only where a product needs it, = between the \
    sides. Copy exactly what is written, mistakes included: never correct, finish or add a line. Leave out words, labels like (a), \
    arrows, ticks and anything crossed out. A line with several steps joined by = stays one line. Handwriting you can't read: your \
    best reading of it.
    """

    /// The demo's stand-in for Claude (TutorPanelTests): the question gives the equation, the working starts after it.
    static let demoReply = "Here it is:\n{\"question\": \"Solve 2x + 6 = 14.\", \"start\": \"2x + 6 = 14\", \"lines\": [\"2x = 8\", \"x = -4\"]}"

    /// Claude's reply (the JSON object in it) as a reading; the question's equation goes first unless the working starts with it.
    static func parse(_ reply: String) -> MathsReading? {
        guard let a = reply.firstIndex(of: "{"), let z = reply.lastIndex(of: "}"), a < z,
              let obj = try? JSONSerialization.jsonObject(with: Data(reply[a...z].utf8)) as? [String: Any] else { return nil }
        var lines = (obj["lines"] as? [Any] ?? []).compactMap { $0 as? String }.map(MathsCheckView.clean).filter { !$0.isEmpty }
        let squash = { (s: String) in s.filter { !$0.isWhitespace } }
        if let start = (obj["start"] as? String).map(MathsCheckView.clean), !start.isEmpty, squash(start) != squash(lines.first ?? "") {
            lines.insert(start, at: 0)
        }
        guard !lines.isEmpty else { return nil }
        let q = (obj["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MathsReading(question: q?.isEmpty == false ? q : nil, lines: lines, reader: .claude)
    }
}
