import SwiftUI
import NexusCore

/// A workstream's page (nil = the Inbox): its open tasks as a tree, Someday, recently done, its notes.md and its files.
struct WorkstreamView: View {
    @Environment(NexusStore.self) private var store
    let workstreamId: String?

    @State private var folded: Set<String> = []
    @State private var showSomeday = false
    @State private var showDone = false
    @State private var allDone = false
    @State private var allFiles = false
    @State private var notes: String?
    @State private var files: [FileItem] = []

    struct FileItem: Identifiable {
        var path: String
        var modified: Date
        var id: String { path }
    }

    init(workstreamId: String?) {
        self.workstreamId = workstreamId
    }

    private var ws: Workstream? { store.workstream(workstreamId) }
    private var name: String { ws?.name ?? "Inbox" }

    var body: some View {
        List {
            if workstreamId != nil && ws == nil {
                Section {
                    EmptyNote(title: "This workstream is not in the folder", detail: "It may have been renamed or moved on the laptop.", icon: "questionmark.folder")
                        .listRowBackground(Color.clear)
                }
            } else {
                headerSection
                tasksSection
                studySection
                somedaySection
                doneSection
                notesSection
                filesSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { store.reload() }
        .task(id: "\(workstreamId ?? "")|\(store.snapshot.loadedAt.timeIntervalSince1970)") { load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: add) { Label("Add a task", systemImage: "plus") }
                    .disabled(store.snapshot.readOnlyReason != nil)
            }
        }
    }

    /// Every task of this workstream (or the Inbox), any depth, in file order.
    private var all: [NexusTask] {
        let s = store.snapshot
        return s.order.compactMap { s.tasks[$0] }.filter { $0.workstream == workstreamId }
    }

    private func add() { store.capture = .init(workstream: workstreamId, parent: nil, plan: nil) }

    // MARK: header

    private var headerSection: some View {
        let s = store.snapshot
        let open = all.filter { !$0.done && !$0.someday }.count
        let group = ws.flatMap { w in s.groups.first { $0.id == w.group }?.label }
        let facts = [ws?.kind?.capitalized, group, "\(open) open"].compactMap { $0 }
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle().fill(workstreamId == nil ? Color.secondary : store.color(workstream: workstreamId)).frame(width: 14, height: 14)
                    Text(name).font(.title2.weight(.semibold))
                    if ws?.parked == true { Chip(text: "Parked", icon: "pause.circle", strong: true) }
                    Spacer(minLength: 0)
                }
                Text(facts.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                if workstreamId == nil {
                    Text("Tasks that capture could not place in a workstream. Open one to move it, or tick it off.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: tasks

    private var tasksSection: some View {
        let s = store.snapshot
        let tops = store.planning.top(of: workstreamId).filter { !$0.done && !$0.someday }
        let rows = TaskTree.rows(tops, in: s, folded: folded, keep: { !$0.done && !$0.someday })
        return Section {
            if tops.isEmpty {
                Text(workstreamId == nil ? "Nothing here: everything found its place." : "No open tasks.")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                TaskTreeRow(row: r, folded: $folded)
                    .taskSwipes(r.task, store: store)
            }
            Button(action: add) { Label("Add a task", systemImage: "plus") }
                .disabled(store.snapshot.readOnlyReason != nil)
        } header: {
            SectionTitle(title: "Tasks", count: tops.count)
        }
    }

    // MARK: Someday

    @ViewBuilder
    private var somedaySection: some View {
        let s = store.snapshot
        // Its own Someday tasks, not the ones already under a Someday parent (they show in that parent's tree).
        let roots = all.filter { t in t.ownSomeday && !t.done && !(t.parent.flatMap { s.tasks[$0]?.someday } ?? false) }
        if !roots.isEmpty {
            Section {
                if showSomeday {
                    ForEach(TaskTree.rows(roots, in: s, folded: folded, keep: { !$0.done })) { r in
                        TaskTreeRow(row: r, folded: $folded)
                            .taskSwipes(r.task, store: store)
                    }
                }
            } header: {
                foldHeader("Someday", count: roots.count, open: $showSomeday)
            }
        }
    }

    // MARK: Done

    @ViewBuilder
    private var doneSection: some View {
        let from = Days.add(store.today, -14)
        let done = all.filter(\.done).sorted { ($0.doneOn ?? "", -$0.order) > ($1.doneOn ?? "", -$1.order) }
        let recent = done.filter { ($0.doneOn ?? "") >= from }
        let shown = allDone ? done : recent
        if !done.isEmpty {
            Section {
                if showDone {
                    if shown.isEmpty {
                        Text("Nothing ticked in the last 14 days.").foregroundStyle(.secondary)
                    }
                    ForEach(shown) { t in
                        TaskRow(task: t, showWorkstream: false, showCrumb: true, compact: true)
                            .taskSwipes(t, store: store)
                    }
                    if done.count > recent.count {
                        Button(allDone ? "Show the last 14 days" : "Show all \(done.count)") {
                            withAnimation(.snappy) { allDone.toggle() }
                        }
                    }
                }
            } header: {
                foldHeader(allDone ? "Done" : "Done in the last 14 days", count: shown.count, open: $showDone)
            }
        }
    }

    // MARK: study (the laptop's Study tab: this workstream's decks)

    @ViewBuilder
    private var studySection: some View {
        if let id = workstreamId, let study = StudyLibrary.shared.study(id), !study.decks.isEmpty {
            Section {
                DeckRows(study: study)
            } header: {
                SectionTitle(title: "Study", count: nil)
            }
        }
    }

    // MARK: notes and files

    @ViewBuilder
    private var notesSection: some View {
        if let text = notes, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Section {
                NoteText(text: text).padding(.vertical, 6)
            } header: {
                SectionTitle(title: "Notes", count: nil)
            }
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        if let w = ws, !files.isEmpty {
            let limit = 25
            let shown = allFiles ? files : Array(files.prefix(limit))
            Section {
                ForEach(shown) { f in fileRow(f, folder: w.folder) }
                if files.count > limit {
                    Button(allFiles ? "Show fewer" : "Show all \(files.count) files") {
                        withAnimation(.snappy) { allFiles.toggle() }
                    }
                }
            } header: {
                SectionTitle(title: "Files", count: files.count)
            }
        }
    }

    private func fileRow(_ f: FileItem, folder: String) -> some View {
        let rel = f.path.hasPrefix(folder + "/") ? String(f.path.dropFirst(folder.count + 1)) : f.path
        let fileName = (rel as NSString).lastPathComponent
        let dir = (rel as NSString).deletingLastPathComponent
        return HStack(spacing: 12) {
            Image(systemName: Self.icon(fileName)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName).lineLimit(1)
                if !dir.isEmpty { Text(dir).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            Text(f.modified.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A doc icon by extension.
    static func icon(_ fileName: String) -> String {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "md", "txt": return "doc.text"
        case "pdf": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg": return "photo"
        case "csv", "tsv", "xlsx", "xls", "numbers": return "tablecells"
        case "doc", "docx", "pages", "rtf": return "doc"
        case "ppt", "pptx", "key": return "rectangle.on.rectangle"
        case "mp3", "m4a", "wav": return "waveform"
        case "mp4", "mov", "m4v": return "film"
        case "yaml", "yml", "json", "js", "py", "html", "css": return "curlybraces"
        case "zip": return "doc.zipper"
        default: return "doc"
        }
    }

    private func load() {
        guard let w = ws else { notes = nil; files = []; return }
        StudyLibrary.shared.refreshIfChanged(store)
        let notesPath = w.folder + "/notes.md"
        notes = DataFolder.text(store.folder, notesPath)
        files = DataFolder.files(store.folder, in: w.folder)
            .filter { $0.path != notesPath }
            .map { FileItem(path: $0.path, modified: $0.modified) }
    }

    /// A collapsible section header: chevron, title and count.
    private func foldHeader(_ title: String, count: Int, open: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { open.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(open.wrappedValue ? 90 : 0))
                SectionTitle(title: title, count: count)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// notes.md, read-only: headings bold, bullets and checkboxes as marks, code fences in mono, inline markdown kept.
private struct NoteText: View {
    let text: String
    @State private var full = false
    private let cap = 120

    init(text: String) { self.text = text }

    var body: some View {
        let lines = Self.lines(text)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array((full ? lines : Array(lines.prefix(cap))).enumerated()), id: \.offset) { _, l in
                line(l)
            }
            if lines.count > cap {
                Button(full ? "Show less" : "Show the whole note") { withAnimation(.snappy) { full.toggle() } }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    struct Line {
        var kind: Kind
        var text: String
        var indent = 0
        enum Kind { case heading1, heading2, heading3, bullet, open, ticked, code, blank, plain }
    }

    @ViewBuilder
    private func line(_ l: Line) -> some View {
        switch l.kind {
        case .heading1: Text(Self.inline(l.text)).font(.title3.weight(.semibold)).padding(.top, 6)
        case .heading2: Text(Self.inline(l.text)).font(.headline).padding(.top, 4)
        case .heading3: Text(Self.inline(l.text)).font(.subheadline.weight(.semibold)).padding(.top, 2)
        case .bullet, .open, .ticked:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(l.kind == .bullet ? "•" : l.kind == .open ? "☐" : "☑").foregroundStyle(.secondary)
                Text(Self.inline(l.text)).strikethrough(l.kind == .ticked, color: .secondary)
            }
            .padding(.leading, CGFloat(l.indent) * 14)
        case .code: Text(l.text).font(.callout.monospaced()).foregroundStyle(.secondary)
        case .blank: Color.clear.frame(height: 4)
        case .plain: Text(Self.inline(l.text))
        }
    }

    /// Splits the note into lines with a kind; drops front matter and repeated blank lines.
    static func lines(_ text: String) -> [Line] {
        var raw = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if raw.first == "---", let end = raw.dropFirst().firstIndex(of: "---") { raw.removeSubrange(0...end) }
        var out: [Line] = []
        var inCode = false
        for r in raw {
            let t = r.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") { inCode.toggle(); continue }
            if inCode { out.append(Line(kind: .code, text: r)); continue }
            if t.isEmpty {
                if let last = out.last, last.kind != .blank { out.append(Line(kind: .blank, text: "")) }
                continue
            }
            let indent = (r.prefix { $0 == " " || $0 == "\t" }.count) / 2
            if t.hasPrefix("### ") { out.append(Line(kind: .heading3, text: String(t.dropFirst(4)))) }
            else if t.hasPrefix("## ") { out.append(Line(kind: .heading2, text: String(t.dropFirst(3)))) }
            else if t.hasPrefix("# ") { out.append(Line(kind: .heading1, text: String(t.dropFirst(2)))) }
            else if t.hasPrefix("- [ ] ") || t.hasPrefix("* [ ] ") { out.append(Line(kind: .open, text: String(t.dropFirst(6)), indent: indent)) }
            else if t.lowercased().hasPrefix("- [x] ") || t.lowercased().hasPrefix("* [x] ") { out.append(Line(kind: .ticked, text: String(t.dropFirst(6)), indent: indent)) }
            else if t.hasPrefix("- ") || t.hasPrefix("* ") { out.append(Line(kind: .bullet, text: String(t.dropFirst(2)), indent: indent)) }
            else { out.append(Line(kind: .plain, text: r)) }
        }
        return out
    }

    /// Inline markdown (bold, italic, code, links), with `[[links]]` shown as their text; plain text when it does not parse.
    static func inline(_ s: String) -> AttributedString {
        let t = s.replacingOccurrences(of: #"\[\[([^\]|]+)\|([^\]]+)\]\]"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        return (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
    }
}
