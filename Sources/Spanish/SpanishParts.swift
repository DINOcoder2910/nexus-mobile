import SwiftUI
import UIKit
import WebKit
import NexusCore

// The pieces every Spanish screen shares: the host (SpanishDict beside the screen on the iPad, as a sheet on the iPhone; the Add a card
// sheet; a file shown read-only), the checker's result (the sentence with its marks, each word a button with its meaning), and the
// colours of a mark.

/// What a word's or a mark's popover can ask the screen for.
struct SpanishActions {
    var dict: (String) -> Void = { _ in }
    var addCard: (SpanishCards.Draft) -> Void = { _ in }
    var showFile: (String, String) -> Void = { _, _ in }
}
private struct SpanishActionsKey: EnvironmentKey { static let defaultValue = SpanishActions() }
extension EnvironmentValues {
    var spanish: SpanishActions {
        get { self[SpanishActionsKey.self] }
        set { self[SpanishActionsKey.self] = newValue }
    }
}

enum SpanishColors {
    static func of(_ kind: String) -> Color { kind == "good" ? Theme.accent : kind == "accent" ? Theme.soon : Theme.late }
}

/// A Spanish screen's frame: SpanishDict (a panel on the right on the iPad, a sheet on the iPhone), the Add a card sheet and the file
/// viewer, opened from anywhere inside through `\.spanish`.
struct SpanishHost<Content: View>: View {
    let workstreamId: String
    @ViewBuilder var content: Content
    @State private var dict: URL?
    @State private var card: SpanishCardTarget?
    @State private var file: SpanishFileTarget?

    var body: some View {
        let actions = SpanishActions(dict: { dict = SpanishDict.url($0) }, addCard: { card = SpanishCardTarget(draft: $0) }, showFile: { file = SpanishFileTarget(path: $0, title: $1) })
        Group {
            if Device.isPhone {
                content
                    .sheet(isPresented: Binding(get: { dict != nil }, set: { if !$0 { dict = nil } })) {
                        SpanishDictPanel(url: $dict).presentationDetents([.medium, .large])
                    }
            } else {
                HStack(spacing: 0) {
                    content.frame(maxWidth: .infinity)
                    if dict != nil {
                        Divider()
                        SpanishDictPanel(url: $dict).frame(width: 400)
                            .transition(.move(edge: .trailing))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: dict != nil)
            }
        }
        .environment(\.spanish, actions)
        .sheet(item: $card) { t in SpanishAddCardSheet(workstreamId: workstreamId, draft: t.draft) }
        .sheet(item: $file) { f in SpanishFileSheet(path: f.path, title: f.title) }
    }
}

struct SpanishCardTarget: Identifiable { let id = UUID(); let draft: SpanishCards.Draft }
struct SpanishFileTarget: Identifiable { let id = UUID(); let path: String; let title: String }

// MARK: SpanishDict

enum SpanishDict {
    /// https://www.spanishdict.com/translate/<word> (the home page for no word), as the laptop's spanishdict.js.
    static func url(_ word: String) -> URL {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !w.isEmpty, let e = w.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { return URL(string: "https://www.spanishdict.com/")! }
        return URL(string: "https://www.spanishdict.com/translate/" + e)!
    }
}

/// The real SpanishDict site, with Back, Open in Safari and Close. (The UI check opens no site: it shows the word it would look up.)
struct SpanishDictPanel: View {
    @Binding var url: URL?
    @StateObject private var web = SpanishWeb()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("SpanishDict").font(.headline)
                Spacer()
                Button { web.back() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back").disabled(!web.canGoBack)
                Button { openURL(web.current ?? url ?? SpanishDict.url("")) } label: { Image(systemName: "safari") }
                    .accessibilityLabel("Open in Safari")
                Button { url = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Close SpanishDict")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if SpanishDemo.active {
                VStack(spacing: 8) {
                    Image(systemName: "book").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(url?.absoluteString ?? "").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("spanishdict-page")
            } else {
                SpanishWebView(web: web, url: url)
            }
        }
        .background(Color(.systemBackground))
    }
}

final class SpanishWeb: NSObject, ObservableObject, WKNavigationDelegate {
    weak var view: WKWebView?
    @Published var canGoBack = false
    @Published var current: URL?
    func back() { view?.goBack() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { canGoBack = webView.canGoBack; current = webView.url }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { canGoBack = webView.canGoBack; current = webView.url }
}

struct SpanishWebView: UIViewRepresentable {
    let web: SpanishWeb
    let url: URL?
    func makeUIView(context: Context) -> WKWebView {
        let v = WKWebView(frame: .zero)
        v.navigationDelegate = web
        v.allowsBackForwardNavigationGestures = true
        web.view = v
        if let url { v.load(URLRequest(url: url)) }
        context.coordinator.loaded = url
        return v
    }
    func updateUIView(_ v: WKWebView, context: Context) {
        if let url, url != context.coordinator.loaded { context.coordinator.loaded = url; v.load(URLRequest(url: url)) }
    }
    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var loaded: URL? }
}

// MARK: a file, read-only

struct SpanishFileSheet: View {
    let path: String
    let title: String
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text ?? "This file is not there yet.")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .status) { Text(path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
            }
            .task { text = try? FolderAccess.read(store.folder.appendingPathComponent(path)) }
        }
    }
}

// MARK: the checker's result

/// Words in rows that wrap, as a paragraph.
struct SpanishFlow: Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { y += line + lineSpacing; x = 0; line = 0 }
            x += z.width + spacing; line = max(line, z.height); widest = max(widest, x)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + z.width > bounds.maxX { y += line + lineSpacing; x = bounds.minX; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; line = max(line, z.height)
        }
    }
}

/// The sentence: a mark is a button (its fix and rule), any other word a button too (its meaning, SpanishDict, Add to vocab).
struct SpanishSentence: View {
    let text: String
    let marks: [SpanishCheck.Mark]
    var run: SpanishCheckRun?
    var font: Font = .title3

    struct Piece: Identifiable { let id: Int; let word: String; let mark: SpanishCheck.Mark?; let after: String }

    static func pieces(_ text: String, _ marks: [SpanishCheck.Mark]) -> [Piece] {
        var out: [Piece] = []
        var lead = ""
        func add(_ word: String, _ mark: SpanishCheck.Mark?) { out.append(Piece(id: out.count, word: lead + word, mark: mark, after: "")); lead = "" }
        func tail(_ s: String) { if out.isEmpty { lead += s } else { let p = out.removeLast(); out.append(Piece(id: p.id, word: p.word, mark: p.mark, after: p.after + s)) } }
        for r in SpanishCheck.runs(text, marks) {
            if let m = r.mark { add(r.text, m); continue }
            let ns = r.text as NSString
            var at = 0
            for w in SpanishCheck.words(r.text) {
                if w.at > at { tail(ns.substring(with: NSRange(location: at, length: w.at - at))) }
                add(w.word, nil)
                at = w.at + (w.word as NSString).length
            }
            if at < ns.length { tail(ns.substring(from: at)) }
        }
        if !lead.isEmpty { out.append(Piece(id: out.count, word: "", mark: nil, after: lead)) }
        return out
    }

    var body: some View {
        SpanishFlow {
            ForEach(Self.pieces(text, marks)) { p in
                HStack(spacing: 0) {
                    if !p.word.isEmpty { SpanishToken(word: p.word, mark: p.mark, run: run) }
                    if !p.after.isEmpty { Text(p.after) }
                }
            }
        }
        .font(font)
    }
}

struct SpanishToken: View {
    let word: String
    let mark: SpanishCheck.Mark?
    let run: SpanishCheckRun?
    @State private var open = false
    @Environment(\.spanish) private var actions

    var body: some View {
        Button { open = true } label: {
            Text(word)
                .foregroundStyle(mark == nil ? Color.primary : mark!.kind == "good" ? Theme.accent : Color.primary)
                .underline(mark != nil, color: mark.map { SpanishColors.of($0.kind) })
                .padding(.vertical, 1)
                .background(mark.map { SpanishColors.of($0.kind).opacity(0.13) } ?? Color.clear, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mark.map { m in m.kind == "good" ? "\(word), right" : "\(word), should be \(m.right)" } ?? word)
        .popover(isPresented: $open) {
            pop.font(.body).padding(16).frame(minWidth: 240, idealWidth: 300, maxWidth: 360).presentationCompactAdaptation(.popover)
        }
    }

    private var lookup: String {
        guard let m = mark else { return run?.info(word)?.lemma.nonEmpty ?? word }
        return (m.kind == "good" ? m.wrong : m.right.nonEmpty ?? m.wrong).split(separator: " ").last.map(String.init) ?? word
    }

    @ViewBuilder
    private var pop: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let m = mark {
                if m.kind == "good" {
                    Label { Text("Right: ").bold() + Text(m.wrong) } icon: { Image(systemName: "checkmark") }.foregroundStyle(Theme.accent)
                } else {
                    (Text(m.wrong).strikethrough() + Text(" → ") + Text(m.right.isEmpty ? "?" : m.right).bold()).font(.headline)
                }
                Text(Spanish.skillName(m.skill) + (m.by != "claude" ? " · " + (m.by == "dictionary" ? "dictionary" : "LanguageTool") : ""))
                    .font(.subheadline).foregroundStyle(.secondary)
                if !m.why.isEmpty { Text(m.why).font(.callout) }
                if let s = Spanish.skill[m.skill] { Text(s.rule).font(.footnote).foregroundStyle(.secondary) }
            } else {
                let info = run?.info(word)
                HStack(spacing: 4) {
                    Text(word).font(.headline)
                    if let l = info?.lemma, !l.isEmpty, l.lowercased() != word.lowercased() { Text("from").foregroundStyle(.secondary); Text(l).italic() }
                }
                if let info {
                    if !info.form.isEmpty { Text(info.form).font(.subheadline).foregroundStyle(.secondary) }
                    if !info.meaning.isEmpty { Text(info.meaning).font(.callout) }
                } else {
                    Text(run?.result?.partial == true ? "Claude did not read this sentence, so there is no meaning here." : run?.done == true ? "No meaning for this word." : "The meaning comes when Claude has read the sentence.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button { open = false; actions.dict(lookup) } label: { Label("SpanishDict", systemImage: "book") }
                if let d = cardDraft {
                    Button { open = false; actions.addCard(d) } label: { Label("Add to vocab", systemImage: "plus") }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            .lineLimit(1)
            .fixedSize()
        }
    }

    private var cardDraft: SpanishCards.Draft? {
        let deck = ""
        if let m = mark {
            guard let i = run?.info(m.right) ?? run?.info(m.wrong) else { return nil }
            return SpanishCards.draft(word: i.word, lemma: i.lemma, form: i.form, meaning: i.meaning, deck: deck)
        }
        let i = run?.info(word)
        return SpanishCards.draft(word: i?.word ?? word, lemma: i?.lemma ?? "", form: i?.form ?? "", meaning: i?.meaning ?? "", deck: deck)
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// The on-screen keyboard covers half the screen, so the Spanish pages hide it once Check or Mark is pressed (the answer shows
/// below), and the iPhone's keyboard gets a Done button (the iPad's has its own hide key).
enum SpanishKeyboard {
    @MainActor static func hide() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

extension View {
    /// A Done button above the iPhone's keyboard. One per page.
    func spanishKeyboardDone() -> some View {
        toolbar {
            if Device.isPhone {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                        .accessibilityIdentifier("spanish-keyboard-done")
                }
            }
        }
    }
}

/// A finished or running check: the sentence, the mistakes with their fixes, the structures, the three layers.
struct SpanishResultView: View {
    let run: SpanishCheckRun
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SpanishSentence(text: run.text, marks: run.marks, run: run, font: compact ? .body : .title3)
            let ms = SpanishCheck.mistakesOf(run.marks)
            if run.done && ms.isEmpty {
                Label(run.result?.partial == true ? "The dictionary and the grammar checker found nothing." : "No mistakes.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.accent).font(.callout.weight(.medium))
                    .accessibilityIdentifier("spanish-no-mistakes")
            }
            if !ms.isEmpty {
                if run.done, let c = run.result?.corrected, c != run.text {
                    (Text("Fixed  ").foregroundStyle(.secondary) + Text(c)).font(.callout)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ms) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Circle().fill(SpanishColors.of(m.kind)).frame(width: 7, height: 7)
                                Text(m.wrong).strikethrough() + Text(" → ") + Text(m.right.isEmpty ? "?" : m.right).bold()
                                Text(Spanish.skillName(m.skill)).font(.caption).foregroundStyle(.secondary)
                            }
                            if !m.why.isEmpty && !compact { Text(m.why).font(.footnote).foregroundStyle(.secondary).padding(.leading, 13) }
                        }
                    }
                }
                .font(.callout)
            }
            if let st = run.result?.structures, !st.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Uses").font(.caption).foregroundStyle(.secondary)
                    SpanishFlow(spacing: 6, lineSpacing: 6) {
                        ForEach(Array(st.enumerated()), id: \.offset) { _, s in
                            Text(s.name).font(.caption)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }
            layers
        }
    }

    private var layers: some View {
        HStack(spacing: 12) {
            layer("Dictionary", run.dictionary, run.dictError)
            layer("LanguageTool", run.languagetool, run.ltError)
            layer("Claude", run.claude, run.aiError)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func layer(_ name: String, _ s: SpanishCheckRun.State, _ why: String) -> some View {
        HStack(spacing: 3) {
            switch s {
            case .ok: Image(systemName: "checkmark").foregroundStyle(Theme.accent)
            case .busy: ProgressView().controlSize(.mini)
            case .off, .wait: Circle().fill(Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
            }
            Text(name + (s == .off ? " (not used)" : s == .busy ? "…" : ""))
        }
        .help(why)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("spanish-layer-\(name)")
    }
}
