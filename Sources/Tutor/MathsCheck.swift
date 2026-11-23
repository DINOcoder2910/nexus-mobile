import SwiftUI
import NexusCore

/// Check my maths (the laptop's tutor tab of the same name): lines of working checked by the computer, not guessed by a model. The shared
/// Rust core (tutor/maths.rs, the code the laptop runs) compares each line with the one before by working it out: an expression must
/// keep its value, an equation its solutions, so a sign slip or a lost solution is found. The first slip is marked, and the tutor can
/// give a hint about it (Hints only: what went wrong, not the answer). The working can be typed, taken from a text block, or read from
/// the handwriting on screen (Vision, as search and the tutor read it), and stays editable so a misread line can be fixed.
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
    /// the working in the box was read from handwriting (a note says to fix a misread line)
    @State private var fromInk = false
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
                            Text("Reading your handwriting…").font(.nx(.footnote)).foregroundStyle(.secondary)
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
                    if fromInk {
                        Label("Read from your handwriting. If a line was misread, fix it above and Check again.", systemImage: "pencil.and.scribble")
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
        if let t = tutor.mathsFromBoard() { fromInk = false; lines = t; check() } else { readInk() }
    }

    private func readInk() {
        reading = true
        Task { @MainActor in
            let t = await tutor.mathsFromHandwriting()
            reading = false
            guard let t else { nothingOnBoard = true; return }
            nothingOnBoard = false
            fromInk = true
            lines = t
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
        onDone()
        tutor.ask("I'm checking my working:\n\(working)\nNexus found that the line \"\(bad)\" does not follow from the one before (\(why)). Give me a hint about what went wrong, not the answer.", kind: .hint)
    }

    /// A line of the board's words as working: $ signs and a list mark off (as the laptop takes them).
    static func clean(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: #"^\$\$?|\$\$?$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^[-*]\s+"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Handwritten lines (each with its place on the board) as lines of working, top to bottom: pieces read side by side (Vision
    /// can split a line, or a chunk edge does) join into one line, left to right. A capital X is the variable x (Vision often reads
    /// a handwritten x as X).
    static func rows(_ found: [(text: String, box: CGRect)]) -> [String] {
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

    /// `-NexusTestFakeHandwriting` (UITests/TutorPanelTests): handwriting as Vision might hand it back, out of order and one line in
    /// two pieces, as the simulator's board has no ink to read.
    static let fakeHandwriting = ProcessInfo.processInfo.arguments.contains("-NexusTestFakeHandwriting")

    /// The strokes on screen (less the bar and the tutor's panel), as the tutor sees them.
    private var strokesOnScreen: [BoardStroke] {
        let visible = board.boardRect(ofView: board.tutorArea)
        return board.content.strokes.filter { st in st.points.contains { visible.contains(CGPoint(x: $0[0], y: $0[1])) } }
    }

    var inkOnScreen: Bool { BoardTutor.fakeHandwriting || !strokesOnScreen.isEmpty }

    /// Check my maths' handwriting: the ink on screen read with Vision (as search and the tutor read it), a line of working a line,
    /// top to bottom. Nil when there is no ink or nothing could be read.
    func mathsFromHandwriting() async -> String? {
        let found: [(text: String, box: CGRect)]
        if BoardTutor.fakeHandwriting {
            found = [(text: "x = -4", box: CGRect(x: 40, y: 300, width: 120, height: 40)), (text: "= 14", box: CGRect(x: 200, y: 104, width: 90, height: 40)),
                     (text: "2X + 6", box: CGRect(x: 40, y: 100, width: 140, height: 40)), (text: "2x = 8", box: CGRect(x: 40, y: 200, width: 120, height: 40))]
        } else {
            let strokes = strokesOnScreen
            guard !strokes.isEmpty else { return nil }
            let lines = await Task.detached(priority: .userInitiated) { HandwritingIndex.Worker.handwrittenLines(strokes).lines }.value
            found = lines.map { (text: $0.text, box: CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)) }
        }
        let rows = MathsCheckView.rows(found)
        return rows.isEmpty ? nil : rows.joined(separator: "\n")
    }
}
