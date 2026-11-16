import SwiftUI
import NexusCore

/// The tutor chat's page: the conversation (the tutor's questions as checker cards, its card offers), the composer, and after End chat
/// the memory review. On the iPad the conversation sits in a readable column; on the iPhone it fills the screen.
struct SpanishChatView: View {
    let workstreamId: String
    /// When the chat was pushed over History or Skills: back to the Spanish page itself, not to that list.
    var onClose: (() -> Void)? = nil
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var size
    var lib: SpanishLibrary { .shared }

    var body: some View {
        SpanishHost(workstreamId: workstreamId) {
            if let c = lib.chats[workstreamId] {
                SpanishChatBody(chat: c, wide: size == .regular)
                    .navigationTitle(c.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("End chat") { if c.end(store) { close() } }
                                .disabled(c.busy || c.review != nil)
                                .accessibilityIdentifier("spanish-end-chat")
                        }
                        if !Device.isPhone {
                            ToolbarItem(placement: .primaryAction) { SpanishModelMenu { c.model = $0 } }
                        }
                    }
                    .onChange(of: c.closed) { _, closed in if closed { close() } }
            } else {
                EmptyNote(title: "No chat open", icon: "bubble.left.and.bubble.right")
            }
        }
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }
}

struct SpanishChatBody: View {
    @Bindable var chat: SpanishChat
    var wide: Bool
    @Environment(NexusStore.self) private var store
    @Environment(\.spanish) private var actions
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.messages.isEmpty && !chat.busy {
                            Text("Ask anything, or say what to practise (\"quiz me on the preterite\", \"teach me the negative imperative\"). The tutor asks you to write and checks it with the checker.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { i, m in message(i, m) }
                        if chat.busy { streaming.id("stream") }
                        if !chat.error.isEmpty { Label(chat.error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Theme.late) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                    .frame(maxWidth: wide ? 760 : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: chat.stream.count / 80) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            Divider()
            if chat.review != nil { SpanishMemoryReview(chat: chat).frame(maxWidth: wide ? 760 : .infinity) } else { composer }
        }
        .spanishKeyboardDone()
    }

    // MARK: messages

    @ViewBuilder
    private func message(_ i: Int, _ m: SpanishChat.Msg) -> some View {
        switch m.role {
        case "user":
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
            }
        case "check":
            VStack(alignment: .leading, spacing: 6) {
                Label("Checked", systemImage: "checkmark.seal").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let r = m.run { SpanishResultView(run: r, compact: true) } else { Text(m.text).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        default:
            VStack(alignment: .leading, spacing: 10) {
                if !m.text.isEmpty { Self.markdown(m.text) }
                ForEach(Array(m.cards.enumerated()), id: \.offset) { _, c in offer(c) }
                if let q = m.check { checkCard(i, m, q) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func markdown(_ text: String) -> some View {
        let a = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        return Text(a).textSelection(.enabled)
    }

    private func offer(_ c: SpanishCards.Draft) -> some View {
        HStack(spacing: 8) {
            Text(c.front).bold() + Text(" = \(c.back)")
            Text(Spanish.decks.first { $0.id == c.deck }?.title ?? c.deck).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button { actions.addCard(c) } label: { Label("Add to deck", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.small)
        }
        .font(.callout)
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func checkCard(_ i: Int, _ m: SpanishChat.Msg, _ q: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(q).font(.callout.weight(.semibold))
            if let r = m.run {
                SpanishResultView(run: r, compact: true)
            } else if chat.liveCheck == i {
                SpanishAnswerField { chat.answer(store, at: i, $0) }
            } else {
                Text(m.answered ? "Answered below." : "Not answered.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Theme.claudeTint, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.claude.opacity(0.25)))
        .accessibilityIdentifier("spanish-check-card")
    }

    private var streaming: some View {
        let r = SpanishMemory.parseReply(chat.stream)
        return Group {
            if r.text.isEmpty {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
            } else {
                Self.markdown(r.text)
            }
        }
    }

    // MARK: the composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message the tutor", text: $chat.draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .focused($typing)
                .onSubmit { chat.send(store, chat.draft) }
                .accessibilityIdentifier("spanish-chat-input")
            if chat.busy {
                Button { chat.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                    .accessibilityLabel("Stop")
            } else {
                Button { chat.send(store, chat.draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send")
            }
            ClaudeModeChip(small: true).padding(.bottom, 6)
        }
        .padding(.horizontal).padding(.vertical, 10)
        .frame(maxWidth: wide ? 760 : .infinity)
    }
}

/// An answer to a check card: one line (Return checks it) and Check.
struct SpanishAnswerField: View {
    var onCheck: (String) -> Void
    @State private var text = ""
    var body: some View {
        HStack(spacing: 8) {
            TextField("Your answer in Spanish", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { SpanishKeyboard.hide(); onCheck(text) }
                .accessibilityIdentifier("spanish-answer")
            Button("Check") { SpanishKeyboard.hide(); onCheck(text) }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

/// After End chat: what the tutor will remember. Each profile block's change can be undone (or kept again), Claude can be told what is
/// wrong (Revise), and nothing is written until Save.
struct SpanishMemoryReview: View {
    @Bindable var chat: SpanishChat
    @Environment(NexusStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = chat.review {
                    switch r.phase {
                    case .working:
                        HStack(spacing: 8) { ProgressView(); Text("Claude is writing the chat's summary and updating your profile…").foregroundStyle(.secondary) }
                    case .error:
                        Label(r.error, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.late)
                        HStack {
                            Button("Try again") { chat.consolidate(store, feedback: "") }.buttonStyle(.borderedProminent)
                            Button("Close without updating the memory") { chat.skipMemory(store) }
                        }
                    case .review:
                        review(r)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 420)
        .background(Color.secondary.opacity(0.05))
        .accessibilityIdentifier("spanish-memory-review")
    }

    @ViewBuilder
    private func review(_ r: SpanishChat.Review) -> some View {
        if let mem = r.memory {
            Text("What the tutor will remember").font(.headline)
            (Text(mem.title).bold() + Text(": " + mem.summary)).font(.callout)
            if r.changes.isEmpty {
                Text("Nothing in your profile changes.").font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Your profile changes like this. Undo any part you disagree with, or tell Claude what to change.").font(.footnote).foregroundStyle(.secondary)
                ForEach(r.changes) { c in
                    let kept = r.keep.contains(c.block)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.title).bold()
                            Spacer()
                            Button(kept ? "Undo" : "Keep it") {
                                if kept { _ = chat.review?.keep.remove(c.block) } else { _ = chat.review?.keep.insert(c.block) }
                            }
                            .controlSize(.small)
                        }
                        ForEach(c.added, id: \.self) { l in Text("+ " + l).foregroundStyle(Theme.accent) }
                        ForEach(c.removed, id: \.self) { l in Text("− " + l).foregroundStyle(Theme.late).strikethrough() }
                    }
                    .font(.callout)
                    .opacity(kept ? 1 : 0.45)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            let notes = Array(Set(mem.notes.map(\.skill) + mem.taught.map(\.skill))).sorted()
            if !notes.isEmpty { Text("Notes added for: " + notes.map(Spanish.skillName).joined(separator: ", ") + ".").font(.footnote).foregroundStyle(.secondary) }
            TextField("Tell Claude what is wrong (\"I already know ser and estar\"), then Revise", text: Binding(get: { chat.review?.feedback ?? "" }, set: { chat.review?.feedback = $0 }), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Save") { if let msg = chat.saveMemory(store) { store.toast = .init(message: msg) } }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("spanish-memory-save")
                Button("Revise") {
                    let f = (chat.review?.feedback ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !f.isEmpty { chat.consolidate(store, feedback: f) }
                }
                .disabled((chat.review?.feedback ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
                Button("Don't update the memory") { chat.skipMemory(store) }.font(.callout)
            }
        }
    }
}
