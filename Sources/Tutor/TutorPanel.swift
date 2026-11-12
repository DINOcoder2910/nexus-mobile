import UIKit
import SwiftUI
import NexusCore

// The tutor's panel on a board (Nov 13 redesign): a chat docked on the right of the board (the bottom half on a narrow screen), the
// tutor drawing in the part of the board beside it (BoardController.tutorArea). Top: who, what it is doing, Plan / API, options,
// minimise, close. Middle: the session's turns as a chat (tutor.json, so the laptop's turns show too), the live turn as it is said (the
// sentence being said in bold, the rest still to come in grey), a your-turn card with Check my work / Hint / Show me, problems with Try
// again. Bottom: while it talks Back / Pause / Next / Stop; otherwise the ways of asking as chips (Hints only, Check my work, Hint, Try
// one, Replay); the microphone (hold to talk, or tap to start and tap to send) and typing. Minimised, it is a pill at the bottom right
// that shows the sentence being said, with Pause / Stop or Check.

/// The tutor's own blue, the same in light and dark (white words sit on it).
enum TutorStyle {
    static let brand = Color(red: 0.231, green: 0.357, blue: 0.859)
    static let brand2 = Color(red: 0.42, green: 0.33, blue: 0.90)
    static let turn = Color.blue
}

/// Places the panel over the board: beside the board under the bar on an iPad (400 wide, full height, above the keyboard), the
/// bottom half on a narrow screen, and as a pill at the bottom right when minimised.
@MainActor
final class TutorPanelHost: UIHostingController<TutorPanelRoot> {
    weak var board: BoardController?
    private var always: [NSLayoutConstraint] = []
    private var wide: [NSLayoutConstraint] = []
    private var narrow: [NSLayoutConstraint] = []
    private var pill: [NSLayoutConstraint] = []
    private var topEq: NSLayoutConstraint?
    private var topMin: NSLayoutConstraint?
    private var shown = -1

    init(board: BoardController) {
        self.board = board
        let t = board.tutor
        super.init(rootView: TutorPanelRoot(tutor: t))
        rootView = TutorPanelRoot(tutor: t,
                                  onClose: { [weak board] in board?.closeTutorPanel() },
                                  onReplay: { [weak board] in board?.openTutorReplay() },
                                  onLayout: { [weak self] in self?.place() })
        view.backgroundColor = .clear
        sizingOptions = .intrinsicContentSize
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not from a storyboard") }

    /// Once it is in the board's view.
    func attach() {
        guard let sv = view.superview, let b = board else { return }
        let v: UIView = view
        v.translatesAutoresizingMaskIntoConstraints = false
        let safe = sv.safeAreaLayoutGuide
        let top = b.topInset + 10
        let eq = v.topAnchor.constraint(equalTo: sv.topAnchor, constant: top)
        let atLeast = v.topAnchor.constraint(greaterThanOrEqualTo: sv.topAnchor, constant: top)
        always = [v.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
                  v.bottomAnchor.constraint(equalTo: sv.keyboardLayoutGuide.topAnchor, constant: -12),
                  v.leadingAnchor.constraint(greaterThanOrEqualTo: safe.leadingAnchor, constant: 12),
                  atLeast]
        let w = v.widthAnchor.constraint(equalToConstant: 400)
        w.priority = UILayoutPriority(999)
        wide = [eq, w]
        let h = v.heightAnchor.constraint(equalTo: sv.heightAnchor, multiplier: 0.5)
        h.priority = UILayoutPriority(999)
        narrow = [v.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12), h]
        pill = [v.widthAnchor.constraint(lessThanOrEqualToConstant: 440)]
        topEq = eq
        topMin = atLeast
        NSLayoutConstraint.activate(always)
        place()
    }

    /// Under the bar (its height changes when it hides or goes narrow), and the layout for the width and for the pill.
    func place() {
        guard let sv = view.superview, let b = board, let topEq, let topMin else { return }
        let top = b.topInset + 10
        if topEq.constant != top { topEq.constant = top; topMin.constant = top }
        let mode = b.tutor.compact ? 2 : sv.bounds.width < 600 ? 1 : 0
        guard mode != shown else { return }
        shown = mode
        NSLayoutConstraint.deactivate(wide + narrow + pill)
        NSLayoutConstraint.activate(mode == 0 ? wide : mode == 1 ? narrow : pill)
    }
}

/// The panel, or the pill when minimised.
struct TutorPanelRoot: View {
    @Bindable var tutor: BoardTutor
    var onClose: () -> Void = {}
    var onReplay: () -> Void = {}
    var onLayout: () -> Void = {}

    var body: some View {
        Group {
            if tutor.compact {
                TutorPill(tutor: tutor).fixedSize()
            } else {
                TutorPanel(tutor: tutor, onClose: onClose, onReplay: onReplay)
            }
        }
        .onChange(of: tutor.compact) { _, _ in onLayout() }
    }
}

// MARK: - the panel

struct TutorPanel: View {
    @Bindable var tutor: BoardTutor
    var onClose: () -> Void
    var onReplay: () -> Void
    @State private var typed = ""
    @State private var voiceSettings = false
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            chatList
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
        .sheet(isPresented: $voiceSettings) {
            NavigationStack {
                Form { TutorSettings() }
                    .navigationTitle("Tutor's voice")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { voiceSettings = false } } }
            }
        }
    }

    // MARK: top

    private var header: some View {
        HStack(spacing: 10) {
            TutorAvatar(phase: tutor.phase, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tutor").font(.headline)
                TutorStatus(tutor: tutor)
            }
            Spacer(minLength: 4)
            ClaudeModeChip(small: true)
            Menu { options } label: { HeaderIcon(symbol: "ellipsis") }
                .accessibilityLabel("Tutor options")
            Button { typing = false; tutor.compact = true } label: { HeaderIcon(symbol: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimise the tutor")
            Button(action: onClose) { HeaderIcon(symbol: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the tutor")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var options: some View {
        Toggle(isOn: $tutor.hints) { Label("Hints only", systemImage: "lightbulb") }
        Button { tutor.practice() } label: { Label("Give me a practice problem", systemImage: "square.and.pencil") }
        Button { tutor.ask(BoardTutor.explainWords) } label: { Label("Explain what's on my board", systemImage: "text.magnifyingglass") }
        Button(action: onReplay) { Label("Replay the explanations", systemImage: "play.rectangle") }
            .disabled(!tutor.canReplay || tutor.busy)
        Divider()
        Button { voiceSettings = true } label: { Label("Voice and speed…", systemImage: "speaker.wave.2") }
    }

    // MARK: the chat

    private var chatList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tutor.chat.isEmpty && !tutor.live { welcome }
                    ForEach(Array(tutor.chat.enumerated()), id: \.offset) { i, t in
                        let read: (() -> Void)? = tutor.busy ? nil : { tutor.readAloud(t.lines) }
                        let inline: String? = i == tutor.chat.count - 1 && tutor.yourTurn != nil && !tutor.live ? nil : t.yourTurn
                        VStack(alignment: .leading, spacing: 8) {
                            QuestionBubble(text: t.q, kind: BoardTutor.kind(of: t.q))
                            AnswerBubble(lines: t.lines, stopped: t.stopped, yourTurn: inline,
                                         onReplay: { n in tutor.replay(from: i, n: n) }, onRead: read)
                        }
                    }
                    if tutor.live { liveTurn }
                    if let p = tutor.problem { problemCard(p) }
                    if let ask = tutor.yourTurn, !tutor.busy, tutor.phase != .listening { yourTurnCard(ask) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(14)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: tutor.said.count) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: tutor.chat.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: tutor.phase) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: tutor.yourTurn) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    /// This turn, as it happens: what you are saying or asked, then the answer as it is said (or the dots while it thinks).
    @ViewBuilder private var liveTurn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if tutor.phase == .listening {
                QuestionBubble(text: tutor.asked, kind: .normal, listening: true)
            } else {
                QuestionBubble(text: tutor.asked, kind: tutor.askedKind)
            }
            if !tutor.said.isEmpty {
                AnswerBubble(lines: tutor.said, speaking: tutor.busy ? tutor.speaking : nil, onReplay: nil, onRead: nil)
            } else if tutor.phase == .thinking {
                ThinkingBubble(text: tutor.askedKind == .hint || tutor.hints ? "Thinking of a hint…" : tutor.askedKind == .check ? "Reading your work…" : "Thinking…")
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TutorAvatar(size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ask me about this board").font(.title3.weight(.semibold))
                    Text("I see what's on your screen, talk you through it and draw as I go.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                tip("mic.fill", "Hold the microphone and talk, or tap it to start and again to send. Or type.")
                tip("lasso", "Circle or select something first to ask about just that.")
                tip("lightbulb", "Hints only: I guide you without giving the answer away.")
                tip("hand.raised", "Talk or type while I'm explaining to cut in.")
            }
            Text("Start with").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            VStack(spacing: 8) {
                starter("Explain what's on my board", "text.magnifyingglass") { tutor.ask(BoardTutor.explainWords) }
                starter("Check my work", "checkmark.circle") { tutor.checkWork() }
                starter("Give me a practice problem", "square.and.pencil") { tutor.practice() }
            }
        }
        .padding(.top, 4)
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(TutorStyle.brand)
            Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func starter(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 20).foregroundStyle(TutorStyle.brand)
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func yourTurnCard(_ ask: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "pencil.tip.crop.circle.fill").font(.title3).foregroundStyle(TutorStyle.turn)
                Text("Your turn").font(.subheadline.weight(.bold)).foregroundStyle(TutorStyle.turn)
                Spacer()
                Text("Write it on the board").font(.caption).foregroundStyle(.secondary)
            }
            Text(BoardTutor.cleanTurn(ask)).font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { tutor.checkWork() } label: { Label("Check my work", systemImage: "checkmark.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(TutorStyle.turn)
                Button { tutor.hint() } label: { Label("Hint", systemImage: "lightbulb") }
                    .buttonStyle(.bordered)
                Button { tutor.showMe() } label: { Label("Show me", systemImage: "eye") }
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(TutorStyle.turn.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(TutorStyle.turn.opacity(0.28)))
    }

    private func problemCard(_ p: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(p).font(.callout).fixedSize(horizontal: false, vertical: true)
                if tutor.lastRequest != nil, !tutor.busy, tutor.phase != .listening {
                    Button { tutor.retry() } label: { Label("Try again", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: bottom

    private var footer: some View {
        VStack(spacing: 10) {
            if tutor.busy {
                playback
            } else if tutor.phase != .listening {
                chips
            }
            composer
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
    }

    /// While it thinks or talks: the sentence before again, pause, the next sentence, stop.
    private var playback: some View {
        HStack(spacing: 6) {
            Image(systemName: tutor.phase == .thinking ? "ellipsis" : "waveform")
                .symbolEffect(.variableColor.iterative, isActive: tutor.phase == .speaking && !tutor.paused)
                .foregroundStyle(TutorStyle.brand)
                .frame(width: 22)
            Text(tutor.phase == .thinking ? "Thinking…" : tutor.paused ? "Paused" : "Talking")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Spacer()
            RoundButton(symbol: "backward.fill", label: "Say that again") { tutor.back() }
                .disabled(tutor.phase != .speaking)
            RoundButton(symbol: tutor.paused ? "play.fill" : "pause.fill", label: tutor.paused ? "Resume" : "Pause") { tutor.pause(!tutor.paused) }
                .disabled(tutor.phase != .speaking)
            RoundButton(symbol: "forward.fill", label: "Next sentence") { tutor.next() }
                .disabled(tutor.phase != .speaking)
            RoundButton(symbol: "stop.fill", label: "Stop", tint: .red) { tutor.stop() }
        }
        .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 5)
        .background(Color(uiColor: .systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    /// The ways of asking, one tap each.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TutorChip(title: "Hints only", symbol: tutor.hints ? "lightbulb.fill" : "lightbulb", on: tutor.hints,
                     label: tutor.hints ? "Hints only: on" : "Hints only: off") { tutor.hints.toggle() }
                if tutor.yourTurn == nil {
                    TutorChip(title: "Check my work", symbol: "checkmark.circle") { tutor.checkWork() }
                    TutorChip(title: "Hint", symbol: "questionmark.bubble", label: "Give me a hint") { tutor.hint() }
                }
                TutorChip(title: "Try one", symbol: "square.and.pencil", label: "Try one") { tutor.practice() }
                if tutor.canReplay {
                    TutorChip(title: "Replay", symbol: "play.rectangle", label: "Replay the explanations", action: onReplay)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MicButton(tutor: tutor)
            if tutor.phase == .listening {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(.red)
                    Text(tutor.listenLocked ? "Listening… tap the mic to send" : "Listening… let go to send")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Button { tutor.cancelListening() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel")
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    TextField(tutor.busy ? "Type to cut in…" : "Ask the tutor…", text: $typed, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($typing)
                        .onSubmit(send)
                        .padding(.vertical, 6)
                    if tutor.busy && blank {
                        Button { tutor.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 30)).foregroundStyle(.red) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop")
                    } else {
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                                .foregroundStyle(blank ? Color.secondary.opacity(0.4) : TutorStyle.brand)
                        }
                        .buttonStyle(.plain)
                        .disabled(blank)
                        .accessibilityLabel("Ask")
                    }
                }
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).strokeBorder(Color.primary.opacity(typing ? 0.25 : 0.1)))
            }
        }
    }

    private var blank: Bool { typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        typed = ""
        typing = false
        tutor.ask(t) // (while it talks: it stops and is told how far you had heard)
    }
}

// MARK: - pieces

extension BoardTutor {
    /// A your-turn ask without a leading "Your turn:".
    static func cleanTurn(_ s: String) -> String {
        s.replacingOccurrences(of: #"^(?i)your turn:?\s*"#, with: "", options: .regularExpression)
    }
}

/// The tutor's face: a blue disc with a cap, and a dot for what it is doing.
struct TutorAvatar: View {
    var phase: BoardTutor.Phase = .idle
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [TutorStyle.brand, TutorStyle.brand2], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "graduationcap.fill").font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if phase != .idle {
                Circle().fill(TutorStatus.colour(phase))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(Circle().strokeBorder(Color(uiColor: .systemBackground), lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

/// What it is doing, in a few words with a coloured dot.
struct TutorStatus: View {
    var tutor: BoardTutor

    static func colour(_ p: BoardTutor.Phase) -> Color {
        switch p {
        case .listening: return .red
        case .thinking: return .orange
        case .speaking: return .green
        case .idle: return .secondary
        }
    }

    var text: String {
        switch tutor.phase {
        case .listening: return "Listening…"
        case .thinking: return tutor.hints ? "Thinking · hints only" : "Thinking…"
        case .speaking: return tutor.paused ? "Paused" : tutor.hints ? "Talking · hints only" : "Talking"
        case .idle: return tutor.yourTurn != nil ? "Your turn" : tutor.hints ? "Ready · hints only" : "Ready"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(tutor.phase == .idle && tutor.yourTurn != nil ? TutorStyle.turn : TutorStatus.colour(tutor.phase)).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A round icon button in the header.
struct HeaderIcon: View {
    var symbol: String
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 30, height: 30)
            .background(Color(uiColor: .tertiarySystemFill), in: Circle())
    }
}

/// A round button on the talking bar.
struct RoundButton: View {
    var symbol: String
    var label: String
    var tint: Color = .primary
    var action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? tint : Color.secondary.opacity(0.4))
                .frame(width: 34, height: 34)
                .background(Color(uiColor: .tertiarySystemFill).opacity(enabled ? 1 : 0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// One of the ways of asking.
struct TutorChip: View {
    var title: String
    var symbol: String
    var on = false
    var label: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 12).frame(height: 32)
            .background(on ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color(uiColor: .systemBackground)), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? Color.clear : Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? title)
    }
}

/// What you asked: your words in a blue bubble on the right, or the button you pressed as a tag.
struct QuestionBubble: View {
    var text: String
    var kind: BoardTutor.Kind
    var listening = false

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            if kind != .normal && !listening {
                Label(tag.0, systemImage: tag.1)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TutorStyle.brand)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(TutorStyle.brand.opacity(0.12), in: Capsule())
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if listening { Image(systemName: "waveform").symbolEffect(.variableColor.iterative) }
                    Text(words).fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(TutorStyle.brand.opacity(listening ? 0.7 : 1),
                            in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18, style: .continuous))
            }
        }
    }

    private var words: String {
        if listening { return text.isEmpty ? "Listening…" : text }
        return text.isEmpty ? "(asked out loud, nothing heard)" : text
    }

    private var tag: (String, String) {
        switch kind {
        case .check: return ("Check my work", "checkmark.circle.fill")
        case .hint: return (text == BoardTutor.nextHintWords ? "Next hint" : "Hint", "lightbulb.fill")
        case .practice: return ("Practice problem", "square.and.pencil")
        case .normal: return (text, "text.bubble")
        }
    }
}

/// The tutor's answer: its sentences in a grey bubble on the left (live: the one being said in bold, the rest to come in grey), what it
/// asked you to write, and Replay / Read aloud under it. Hold it to replay the board from any sentence.
struct AnswerBubble: View {
    var lines: [String]
    var speaking: Int?
    var stopped = false
    var yourTurn: String?
    var onReplay: ((Int) -> Void)?
    var onRead: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TutorAvatar(size: 24)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 8) {
                    text.font(.body).fixedSize(horizontal: false, vertical: true)
                    if let yourTurn {
                        Label { Text("Your turn: " + BoardTutor.cleanTurn(yourTurn)) } icon: { Image(systemName: "pencil.tip") }
                            .font(.footnote.weight(.medium)).foregroundStyle(TutorStyle.turn)
                    }
                    if stopped { Text("Stopped").font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 13).padding(.vertical, 10)
                .background(Color(uiColor: .secondarySystemBackground),
                            in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                .contextMenu {
                    if let onReplay {
                        ForEach(Array(lines.enumerated()), id: \.offset) { n, l in
                            Button { onReplay(n) } label: { Text("Replay from “\(String(l.prefix(48)))\(l.count > 48 ? "…" : "")”") }
                        }
                    }
                    Button { UIPasteboard.general.string = lines.joined(separator: " ") } label: { Label("Copy", systemImage: "doc.on.doc") }
                }
                if onReplay != nil || onRead != nil {
                    HStack(spacing: 16) {
                        if let onReplay {
                            Button { onReplay(0) } label: { Label("Replay", systemImage: "play.circle") }
                                .accessibilityLabel("Replay this answer on the board")
                        }
                        if let onRead {
                            Button(action: onRead) { Label("Read aloud", systemImage: "speaker.wave.2") }
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            Spacer(minLength: 24)
        }
    }

    private var text: Text {
        lines.enumerated().reduce(Text("")) { acc, e in
            let piece = Text((e.offset > 0 ? " " : "") + e.element)
            guard let s = speaking else { return acc + piece }
            if e.offset == s { return acc + piece.fontWeight(.semibold).foregroundColor(.primary) }
            return acc + piece.foregroundColor(e.offset < s ? .primary : .secondary)
        }
    }
}

/// The dots while it thinks.
struct ThinkingBubble: View {
    var text: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TutorAvatar(size: 24)
            HStack(spacing: 10) {
                TimelineView(.animation(minimumInterval: 0.15)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            Circle().frame(width: 7, height: 7).opacity(0.3 + 0.7 * max(0, sin(t * 5 - Double(i) * 0.8)))
                        }
                    }
                }
                Text(text).font(.subheadline)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground),
                        in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
            Spacer(minLength: 24)
        }
    }
}

/// The microphone: hold to talk (let go to ask), or tap to start and tap again to ask.
struct MicButton: View {
    @Bindable var tutor: BoardTutor
    var size: CGFloat = 42
    @State private var down: Date?
    @State private var stopOnRelease = false

    var body: some View {
        let on = tutor.phase == .listening
        ZStack {
            Circle().fill(on ? Color.red : TutorStyle.brand)
            Image(systemName: on ? "waveform" : "mic.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: on)
        }
        .frame(width: size, height: size)
        .scaleEffect(down != nil ? 0.92 : 1)
        .animation(.easeOut(duration: 0.12), value: down != nil)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard down == nil else { return }
                down = Date()
                stopOnRelease = tutor.phase == .listening || tutor.listenLocked
                if !stopOnRelease { tutor.startListening() }
            }
            .onEnded { _ in
                let held = down.map { Date().timeIntervalSince($0) } ?? 0
                down = nil
                if stopOnRelease { tutor.stopListening() } else if held < 0.35 { tutor.listenLocked = true } else { tutor.stopListening() }
            })
        .accessibilityElement()
        .accessibilityLabel(on ? "Send what you said" : "Talk to the tutor")
        .accessibilityHint("Hold to talk, or tap to start and tap again to send")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if tutor.phase == .listening { tutor.stopListening() } else { tutor.startListening(locked: true) } }
    }
}

// MARK: - minimised

/// The panel made small: the tutor's face, what it is doing and the sentence being said, Pause / Stop (or Check my work, or the
/// microphone), and a tap to open the chat again.
struct TutorPill: View {
    @Bindable var tutor: BoardTutor

    var body: some View {
        HStack(spacing: 10) {
            Button { tutor.compact = false } label: {
                HStack(spacing: 10) {
                    TutorAvatar(phase: tutor.phase, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tutor.phase == .idle && tutor.yourTurn != nil ? "Your turn" : "Tutor").font(.subheadline.weight(.semibold))
                        Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 220, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the tutor")
            if tutor.busy {
                RoundButton(symbol: tutor.paused ? "play.fill" : "pause.fill", label: tutor.paused ? "Resume" : "Pause") { tutor.pause(!tutor.paused) }
                    .disabled(tutor.phase != .speaking)
                RoundButton(symbol: "stop.fill", label: "Stop", tint: .red) { tutor.stop() }
            } else if tutor.yourTurn != nil {
                Button { tutor.checkWork() } label: { Label("Check", systemImage: "checkmark.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(TutorStyle.turn).controlSize(.small)
                    .accessibilityLabel("Check my work")
            } else {
                MicButton(tutor: tutor, size: 34)
            }
            Button { tutor.compact = false } label: { HeaderIcon(symbol: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the whole chat")
        }
        .padding(.leading, 8).padding(.trailing, 10).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 4)
    }

    private var caption: String {
        switch tutor.phase {
        case .listening: return tutor.asked.isEmpty ? "Listening…" : tutor.asked
        case .thinking: return "Thinking…"
        case .speaking:
            if tutor.paused { return "Paused" }
            let i = min(max(tutor.speaking, 0), tutor.said.count - 1)
            return i >= 0 ? tutor.said[i] : "Talking"
        case .idle:
            if let y = tutor.yourTurn { return BoardTutor.cleanTurn(y) }
            return tutor.problem ?? "Tap to open the chat"
        }
    }
}
