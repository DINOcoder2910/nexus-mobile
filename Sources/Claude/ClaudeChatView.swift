import SwiftUI
import NexusCore

/// The Claude conversation, the laptop's Claude panel on the iPhone and iPad: Claude reads your files and proposes each change as a card
/// you Accept or Reject. `conversation` picks which one (`main`, or `apps` for Applications); `context` is added to every message (the
/// screen's own facts, as Applications' schools).
///
/// Each device has its own layout. The iPad shows the model menu, the Plan / API chip and the commands in view (the commands as cards on an
/// empty conversation); the iPhone keeps only the chip in view, with the model, New conversation and Earlier conversations behind the ⋯
/// menu and the commands behind the / button beside the box.
struct ClaudeChatView: View {
    var conversation: String = "main"
    var context: (@MainActor () -> String)? = nil
    /// Shown as the side column or a sheet: a close button.
    var onClose: (() -> Void)? = nil

    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    @State private var showEarlier = false
    @FocusState private var focused: Bool

    private var convo: ClaudeConversation { ClaudeChatSession.shared.conversation(conversation) }
    /// The iPad's roomy layout (the side column on an iPad is narrow too, but still an iPad).
    private var wide: Bool { !Device.isPhone }

    var body: some View {
        let c = convo
        VStack(spacing: 0) {
            messages(c)
            Divider()
            inputBar(c)
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(conversation == "apps" ? "Applications · Claude" : "Claude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(c) }
        .sheet(isPresented: $showEarlier) { EarlierConversations(conversation: conversation) }
        .onAppear { if let context { c.context = context } }
    }

    // MARK: header

    @ToolbarContentBuilder
    private func toolbar(_ c: ClaudeConversation) -> some ToolbarContent {
        if let onClose {
            ToolbarItem(placement: .cancellationAction) {
                Button { onClose() } label: { Label("Close", systemImage: wide ? "sidebar.trailing" : "xmark") }
                    .accessibilityIdentifier("claude-close")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if wide { modelMenu(c) }
            ClaudeModeChip(small: !wide)
            Menu {
                if !wide {
                    Picker("Model", selection: Binding(get: { c.model }, set: { c.model = $0 })) {
                        ForEach(Self.models, id: \.id) { m in Text(m.name).tag(m.id) }
                    }
                }
                Button { c.clear() } label: { Label("New conversation", systemImage: "square.and.pencil") }.disabled(c.busy || c.isEmpty)
                Button { showEarlier = true } label: { Label("Earlier conversations", systemImage: "clock.arrow.circlepath") }
                if c.pendingCount > 1 {
                    Button { c.acceptAll() } label: { Label("Accept all \(c.pendingCount) changes", systemImage: "checkmark.circle") }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .accessibilityIdentifier("claude-menu")
        }
    }

    struct ModelChoice: Identifiable { let id: String; let name: String }
    static let models = [ModelChoice(id: "sonnet", name: "Sonnet"), ModelChoice(id: "haiku", name: "Haiku"), ModelChoice(id: "opus", name: "Opus")]

    private func modelMenu(_ c: ClaudeConversation) -> some View {
        Menu {
            Picker("Model", selection: Binding(get: { c.model }, set: { c.model = $0 })) {
                ForEach(Self.models, id: \.id) { m in Text(m.name).tag(m.id) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(Self.models.first { $0.id == c.model }?.name ?? c.model)
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .font(.callout.weight(.medium))
        }
        .accessibilityIdentifier("claude-model")
    }

    // MARK: the messages

    private func messages(_ c: ClaudeConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if c.isEmpty && !c.busy { emptyState(c) }
                    ForEach(c.items) { item in row(item, c).id(item.id) }
                    if c.busy { working(c) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, wide ? 20 : 14)
                .padding(.vertical, 14)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: c.version) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) } }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func row(_ item: ChatItem, _ c: ClaudeConversation) -> some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: wide ? 80 : 40)
                Text(item.text)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.claudeTint, in: RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
            }
        case .claude:
            Text(Self.markdown(item.text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .lookup:
            Label(item.text, systemImage: "doc.text.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .change:
            ChangeCard(item: item, conversation: c, wide: wide)
        case .note:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: item.retry ? "exclamationmark.triangle" : "info.circle")
                Text(item.text).fixedSize(horizontal: false, vertical: true)
                if item.retry && item.id == c.items.last?.id {
                    Button("Try again") { c.retry() }.buttonStyle(.borderless).fontWeight(.semibold)
                }
            }
            .font(.callout)
            .foregroundStyle(item.retry ? Theme.late : .secondary)
            .accessibilityIdentifier("claude-note")
        }
    }

    private func working(_ c: ClaudeConversation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let words = ClaudeChat.words(c.streaming)
            if !words.isEmpty { Text(Self.markdown(words)).frame(maxWidth: .infinity, alignment: .leading) }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(c.status ?? "Thinking").font(.callout).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("claude-working")
        }
    }

    /// An empty conversation: what Claude can do, and the commands (cards on the iPad; a short list on the iPhone).
    private func emptyState(_ c: ClaudeConversation) -> some View {
        let about = c.looking.map { $0.lowercased() == "today" ? "today" : $0 } ?? "your plans and files"
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Claude", systemImage: "sparkles").font(.title3.weight(.semibold)).foregroundStyle(Theme.claude)
                Text("Ask about \(about). Claude reads your data folder and shows each change as a card for you to accept or reject.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if conversation == "main" {
                // today in brief (Home has it too): what Claude knows about your day before you ask
                DayBriefCard(showsGreeting: true)
                if wide {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(ClaudeChat.commands) { cmd in commandCard(cmd, c) }
                    }
                } else {
                    VStack(spacing: 8) { ForEach(ClaudeChat.commands.prefix(3)) { cmd in commandCard(cmd, c) } }
                }
            }
        }
        .padding(.top, wide ? 20 : 8)
    }

    private func commandCard(_ cmd: ClaudeChat.Command, _ c: ClaudeConversation) -> some View {
        Button { runCommand(cmd, c) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: cmd.icon).foregroundStyle(Theme.claude).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cmd.title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Text(cmd.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("command" + cmd.id.replacingOccurrences(of: "/", with: "-"))
    }

    /// A command runs at once, except New meeting note, which needs a name: it goes into the box.
    private func runCommand(_ cmd: ClaudeChat.Command, _ c: ClaudeConversation) {
        if cmd.id == "/new-meeting" { c.draft = "/new-meeting "; focused = true; return }
        c.send(cmd.id)
    }

    // MARK: the box

    private func inputBar(_ c: ClaudeConversation) -> some View {
        @Bindable var c = c
        return VStack(spacing: 6) {
            if c.pendingCount > 1 && wide {
                HStack {
                    Text("\(c.pendingCount) changes wait for you").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Accept all") { c.acceptAll() }.font(.caption.weight(.semibold)).buttonStyle(.borderless)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                if conversation == "main" {
                    Menu {
                        ForEach(ClaudeChat.commands) { cmd in
                            Button { runCommand(cmd, c) } label: { Label(cmd.title, systemImage: cmd.icon) }
                        }
                    } label: {
                        Image(systemName: "slash.circle").font(.title2).foregroundStyle(Theme.claude)
                    }
                    .disabled(c.busy)
                    .accessibilityLabel("Commands")
                    .accessibilityIdentifier("claude-commands")
                }
                TextField(placeholder(c), text: $c.draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .submitLabel(.send)
                    .onSubmit { send(c) }
                    .accessibilityIdentifier("claude-input")
                if c.busy {
                    Button { c.stop() } label: { Image(systemName: "stop.circle.fill").font(.title) }
                        .tint(Theme.late)
                        .accessibilityLabel("Stop")
                        .accessibilityIdentifier("claude-stop")
                } else {
                    Button { send(c) } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                        .tint(Theme.claude)
                        .disabled(c.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.snapshot.isDataFolder)
                        .accessibilityLabel("Send")
                        .accessibilityIdentifier("claude-send")
                }
            }
        }
        .padding(.horizontal, wide ? 16 : 10)
        .padding(.vertical, 10)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func placeholder(_ c: ClaudeConversation) -> String {
        guard let l = c.looking, !l.isEmpty else { return "Ask Claude…" }
        return l.lowercased() == "today" ? "Ask about today…" : "Ask about \(l)…"
    }

    private func send(_ c: ClaudeConversation) {
        let t = c.draft
        guard !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !c.busy else { return }
        c.draft = ""
        c.send(t)
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// A proposed change: the file, its changed lines, and Accept / Reject (then Saved with Undo, Rejected, or why it can't be saved).
struct ChangeCard: View {
    let item: ChatItem
    let conversation: ClaudeConversation
    var wide = true
    @State private var expanded = false

    var body: some View {
        let lines = ClaudeChat.diff(item.before ?? "", item.after ?? "")
        let long = lines.count > 14
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: item.isNew ? "doc.badge.plus" : "pencil.line").foregroundStyle(Theme.claude)
                Text(item.path ?? "").font(.caption.monospaced().weight(.semibold)).lineLimit(1).truncationMode(.head)
                if item.isNew { Text("New file").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.claudeTint, in: Capsule()) }
                Spacer(minLength: 0)
                if item.auto { Text("Placed").font(.caption2.weight(.semibold)).foregroundStyle(Theme.planned) }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            if item.before != nil || item.after != nil {
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((long && !expanded ? Array(lines.prefix(12)) : lines).enumerated()), id: \.offset) { _, l in line(l) }
                    if long {
                        Button(expanded ? "Show less" : "Show all \(lines.count) lines") { expanded.toggle() }
                            .font(.caption).buttonStyle(.borderless).padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(item.state == .pending ? Theme.claude.opacity(0.45) : Color.secondary.opacity(0.2)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("change-card")
    }

    @ViewBuilder
    private func line(_ l: ClaudeChat.Line) -> some View {
        switch l {
        case .same(let s): code(" " + s, .secondary, .clear)
        case .removed(let s): code("−" + s, Theme.late, Theme.late.opacity(0.10))
        case .added(let s): code("+" + s, Theme.planned, Theme.planned.opacity(0.12))
        case .gap(let n): Text("⋯ \(n) unchanged line\(n == 1 ? "" : "s")").font(.caption2).foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.vertical, 2)
        }
    }

    private func code(_ s: String, _ fg: Color, _ bg: Color) -> some View {
        Text(s.isEmpty ? " " : s)
            .font(.system(size: wide ? 12 : 11, design: .monospaced))
            .foregroundStyle(fg)
            .lineLimit(wide ? 3 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 1)
            .background(bg)
    }

    @ViewBuilder
    private var footer: some View {
        switch item.state ?? .pending {
        case .pending:
            HStack(spacing: 10) {
                Button { conversation.accept(item.id) } label: { Label("Accept", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .accessibilityIdentifier("change-accept")
                Button { conversation.reject(item.id) } label: { Label("Reject", systemImage: "xmark") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("change-reject")
                Spacer(minLength: 0)
            }
            .font(.callout.weight(.medium))
            .controlSize(.small)
        case .accepted:
            HStack(spacing: 10) {
                Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.planned)
                Spacer(minLength: 0)
                Button("Undo") { conversation.undo(item.id) }.buttonStyle(.borderless).accessibilityIdentifier("change-undo")
            }
            .font(.callout.weight(.medium))
        case .rejected:
            Label("Rejected", systemImage: "xmark.circle").font(.callout).foregroundStyle(.secondary)
        case .undone:
            Label("Put back as it was", systemImage: "arrow.uturn.backward.circle").font(.callout).foregroundStyle(.secondary)
        case .failed, .stale:
            Label(item.problem ?? "Couldn't use this change.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(Theme.late)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Earlier conversations of a kind (the last 15), to read again or take back up.
struct EarlierConversations: View {
    let conversation: String
    @Environment(\.dismiss) private var dismiss
    @State private var list: [ClaudeArchive.File] = []

    var body: some View {
        NavigationStack {
            List {
                if list.isEmpty {
                    Text("Nothing yet. New conversation keeps the one you leave here.").foregroundStyle(.secondary)
                }
                ForEach(list, id: \.id) { f in
                    Button {
                        ClaudeChatSession.shared.conversation(conversation).resume(f)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(f.items.first { $0.kind == .user }?.text ?? "Conversation").lineLimit(2).foregroundStyle(.primary)
                            Text("\(f.updated.formatted(date: .abbreviated, time: .shortened)) · \(f.items.filter { $0.kind == .user }.count) messages")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Earlier conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { list = ClaudeArchive.list(key: conversation) }
        }
        .presentationDetents([.medium, .large])
    }
}
