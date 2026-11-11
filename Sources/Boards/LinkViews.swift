import SwiftUI
import UIKit
import NexusCore

/// A quick look at a link's far end: what it is, its words, and what you can do with it.
struct LinkPeek: View {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        var destructive = false
        let run: () -> Void
        init(title: String, destructive: Bool = false, run: @escaping () -> Void) { self.title = title; self.destructive = destructive; self.run = run }
    }

    let title: String
    let detail: String
    let text: String
    let actions: [Action]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).lineLimit(3)
            if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
            if !text.isEmpty {
                ScrollView { Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxHeight: 280)
                    .padding(10)
                    .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                ForEach(actions) { a in
                    Button(role: a.destructive ? .destructive : nil) { close(); a.run() } label: { Text(a.title) }
                        .buttonStyle(.bordered)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 320, alignment: .topLeading)
    }
}

/// Pick a board, a task or a note to link something to.
struct LinkTargetPicker: View {
    enum Kind: String, CaseIterable, Identifiable {
        case board = "Boards", task = "Tasks", note = "Notes"
        var id: String { rawValue }
    }
    struct Entry: Identifiable { let id: String; let title: String; let detail: String }

    let boards: [Entry]
    let tasks: [Entry]
    let notes: [Entry]
    let onPick: (Kind, String) -> Void
    let onCancel: () -> Void
    @State private var kind = Kind.board
    @State private var query = ""

    var entries: [Entry] {
        let all = kind == .board ? boards : kind == .task ? tasks : notes
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) || $0.detail.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Link to", selection: $kind) { ForEach(Kind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                if entries.isEmpty {
                    Text(query.isEmpty ? "Nothing here yet." : "Nothing matches “\(query)”.").foregroundStyle(.secondary)
                }
                ForEach(entries.prefix(400)) { e in
                    Button { onPick(kind, e.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.title).foregroundStyle(.primary).lineLimit(2)
                            if !e.detail.isEmpty { Text(e.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Link to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) } }
        }
    }
}

/// All the links: this board's (grouped by where their far end is, and those from other boards), or every board's.
struct LinksList: View {
    struct Row: Identifiable {
        let id: String
        let board: String
        let color: String
        let near: String
        let far: String
        let group: String
        let mine: Bool
        let missing: Bool
    }

    let here: [Row]
    let everywhere: [Row]
    let readOnly: Bool
    let onGo: (Row) -> Void
    let onRemove: (Row) -> Void
    let onColor: (Row, String) -> Void
    let onClose: () -> Void
    @State private var all = false
    @State private var query = ""

    var rows: [Row] {
        let list = all ? everywhere : here
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? list : list.filter { "\($0.near) \($0.far) \($0.group)".lowercased().contains(q) }
    }

    struct Group: Identifiable { let id: String; let rows: [Row] }

    var groups: [Group] {
        var order: [String] = []
        var by: [String: [Row]] = [:]
        for r in rows {
            if by[r.group] == nil { order.append(r.group) }
            by[r.group, default: []].append(r)
        }
        return order.map { Group(id: $0, rows: by[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("Which links", selection: $all) {
                    Text("This board").tag(false)
                    Text("Every board").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if rows.isEmpty {
                    Text(all ? "No links on any other board yet." : "No links on this board yet. Turn on Link mode (the link button), tap one thing, then another. On a PDF, drag over a passage to pull it out as an excerpt.")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { g in
                    Section(g.id) {
                        ForEach(g.rows) { r in row(r) }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
        }
    }

    @ViewBuilder
    func row(_ r: Row) -> some View {
        let line = Button { onGo(r) } label: {
            HStack(spacing: 10) {
                Circle().fill(Color(uiColor: InkConvert.color(r.color))).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.near).foregroundStyle(r.missing ? .secondary : .primary).lineLimit(1)
                    Text("↔ " + r.far).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        if r.mine && !readOnly {
            line
                .swipeActions { Button("Remove", role: .destructive) { onRemove(r) } }
                .contextMenu {
                    ForEach(BoardLinks.colors.indices, id: \.self) { i in
                        Button(BoardLinks.colorNames[i]) { onColor(r, BoardLinks.colors[i]) }
                    }
                    Button("Remove link", role: .destructive) { onRemove(r) }
                }
        } else {
            line
        }
    }
}

/// A text block's words to pick for a link: select them, then link from them (tap the other end) or link them to a board, task or note.
final class WordPickerController: UIViewController {
    let markdown: String
    let onDone: (NSRange, Bool) -> Void
    private let textView = UITextView()

    init(markdown: String, onDone: @escaping (NSRange, Bool) -> Void) {
        self.markdown = markdown
        self.onDone = onDone
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pick the words"
        view.backgroundColor = .systemBackground
        textView.text = markdown
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.frame = view.bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(textView)
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "Link from them", image: nil, primaryAction: UIAction { [weak self] _ in self?.done(outside: false) }, menu: nil),
            UIBarButtonItem(title: "Link to…", image: nil, primaryAction: UIAction { [weak self] _ in self?.done(outside: true) }, menu: nil),
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    private func done(outside: Bool) {
        let r = textView.selectedRange
        guard r.location != NSNotFound, r.location <= (markdown as NSString).length else { return }
        onDone(r, outside)
    }
}
