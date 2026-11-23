import SwiftUI
import NexusCore

/// Check my maths (the laptop's tutor tab of the same name): lines of working checked by the computer, not guessed by a model. The shared
/// Rust core (tutor/maths.rs, the code the laptop runs) compares each line with the one before by working it out: an expression must
/// keep its value, an equation its solutions, so a sign slip or a lost solution is found. The first slip is marked, and the tutor can
/// give a hint about it (Hints only: what went wrong, not the answer).
struct MathsCheckView: View {
    let tutor: BoardTutor
    var onDone: () -> Void
    @State private var lines = ""
    @State private var result: RustCore.Maths?
    /// the text `result` is for (an edit after it hides the result until Check again)
    @State private var checked = ""
    @State private var nothingOnBoard = false
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
                            .accessibilityIdentifier("maths-from-board")
                        Spacer(minLength: 0)
                        Button { check() } label: { Label("Check", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent).tint(TutorStyle.brand)
                            .disabled(lines.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("maths-check")
                    }
                    .controlSize(.regular)
                    if nothingOnBoard {
                        Text("Select a text block with your working first, or type it here.")
                            .font(.nx(.footnote)).foregroundStyle(.secondary)
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
        .onAppear { if lines.isEmpty, let t = tutor.mathsFromBoard() { lines = t; check() } }
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

    private func fromBoard() {
        guard let t = tutor.mathsFromBoard() else { nothingOnBoard = true; return }
        nothingOnBoard = false
        lines = t
        check()
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
}
