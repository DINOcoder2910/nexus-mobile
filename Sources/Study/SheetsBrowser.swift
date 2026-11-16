import SwiftUI
import QuickLook
import NexusCore

/// Practice sheets: the sheets folder as the laptop's Study tab lists it (StudySheets: one sheet per sheet folder, its paper, markscheme
/// and marked copies), searched and filtered by unit, kind, syllabus, markscheme and level, sorted by unit folder, title, marks or pages.
/// A sheet opens its paper; its other files open from their own buttons. The iPad shows the filters as a bar (`embedded`, beside the
/// rest of Study); the iPhone has a search field and a Filter menu.
struct SheetsBrowser: View {
    @Environment(NexusStore.self) private var store
    let workstreamId: String
    @Binding var filter: StudySheets.Filter
    var embedded = false

    @AppStorage("studySheetSort") private var sort = "unit"
    @State private var preview: URL?

    private var study: StudyLibrary.Study? { StudyLibrary.shared.study(workstreamId) }

    var body: some View {
        let all = study?.sheets.sheets ?? []
        let list = StudySheets.sort(StudySheets.filter(all, filter), by: sort)
        Group {
            if embedded {
                VStack(spacing: 0) {
                    bar(all, shown: list.count)
                    Divider()
                    content(all, list)
                }
            } else {
                content(all, list)
                    .searchable(text: $filter.q, prompt: "Search sheets")
                    .toolbar {
                        ToolbarItemGroup(placement: .primaryAction) {
                            filterMenu(all)
                            sortMenu
                        }
                    }
            }
        }
        .quickLookPreview($preview)
        .navigationTitle(embedded ? "" : "Practice sheets")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ all: [StudySheets.Sheet], _ list: [StudySheets.Sheet]) -> some View {
        List {
            if all.isEmpty {
                Section {
                    EmptyNote(title: "No sheets yet", detail: "Upload a sheet, or file them in \(study?.config.sheets ?? "files") on the laptop.", icon: "doc.on.doc")
                        .listRowBackground(Color.clear)
                }
            } else if list.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Text("No sheet matches these filters.").foregroundStyle(.secondary)
                        Button("Clear filters") { filter = .init() }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                    .listRowBackground(Color.clear)
                }
            } else if sort == "unit" {
                ForEach(groups(list), id: \.key) { g in
                    Section {
                        ForEach(g.sheets) { row($0) }
                    } header: {
                        Text(g.label).font(.subheadline.weight(.semibold)).textCase(nil)
                    }
                }
            } else {
                Section {
                    ForEach(list) { row($0) }
                } header: {
                    if !embedded { countText(all.count, list.count) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("study-sheets-list")
    }

    private func row(_ s: StudySheets.Sheet) -> some View {
        SheetRow(sheet: s, root: store.folder, onUnit: { filter.unit = $0 }) { preview = $0 }
    }

    private func countText(_ total: Int, _ shown: Int) -> some View {
        Text(shown == total ? sheetCount(total) : "\(shown) of \(total) sheets").textCase(nil)
    }

    /// The sheets under their unit folders, in the order they come.
    private func groups(_ list: [StudySheets.Sheet]) -> [(key: String, label: String, sheets: [StudySheets.Sheet])] {
        var out: [(key: String, label: String, sheets: [StudySheets.Sheet])] = []
        for s in list {
            let k = s.group?.path ?? ""
            if let i = out.firstIndex(where: { $0.key == k }) { out[i].sheets.append(s) }
            else { out.append((k, s.group?.label ?? "Not in a unit folder", [s])) }
        }
        return out
    }

    // MARK: the filters

    /// The iPad's bar: search, a menu for each filter (showing what it is set to), sort, the count.
    private func bar(_ all: [StudySheets.Sheet], shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Practice sheets").font(.title3.weight(.semibold))
                countText(all.count, shown).font(.callout).foregroundStyle(.secondary)
                Spacer()
                if !filter.isEmpty { Button("Clear filters") { filter = .init() }.font(.callout) }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search sheets", text: $filter.q)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("study-sheets-search")
                if !filter.q.isEmpty {
                    Button { filter.q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chipMenu(label(unitOptions(all), filter.unit, "Any unit"), on: !filter.unit.isEmpty) { picker("Unit", $filter.unit, unitOptions(all)) }
                    chipMenu(label(kindOptions(all), filter.kind, "Any kind"), on: !filter.kind.isEmpty) { picker("Kind", $filter.kind, kindOptions(all)) }
                    chipMenu(label(Self.eraOptions, filter.era, "Any syllabus"), on: !filter.era.isEmpty) { picker("Syllabus", $filter.era, Self.eraOptions) }
                    chipMenu(label(Self.msOptions, filter.ms, "Markscheme: any"), on: !filter.ms.isEmpty) { picker("Markscheme", $filter.ms, Self.msOptions) }
                    chipMenu(label(Self.levelOptions, filter.level, "HL or SL"), on: !filter.level.isEmpty) { picker("Level", $filter.level, Self.levelOptions) }
                    chipMenu("Sort: " + (StudySheets.sorts.first { $0.id == sort }?.label.lowercased() ?? "unit folder"), on: false) { sortPicker }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func chipMenu<C: View>(_ text: String, on: Bool, @ViewBuilder _ content: () -> C) -> some View {
        Menu { content() } label: {
            HStack(spacing: 4) {
                Text(text).lineLimit(1)
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .font(.callout.weight(on ? .semibold : .regular))
            .foregroundStyle(on ? Theme.accent : .primary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? Theme.accent.opacity(0.14) : Color(uiColor: .tertiarySystemFill), in: Capsule())
        }
    }

    /// The iPhone's Filter menu: every filter as a submenu, and Clear.
    private func filterMenu(_ all: [StudySheets.Sheet]) -> some View {
        Menu {
            Menu("Unit") { picker("Unit", $filter.unit, unitOptions(all)) }
            Menu("Kind") { picker("Kind", $filter.kind, kindOptions(all)) }
            Menu("Syllabus") { picker("Syllabus", $filter.era, Self.eraOptions) }
            Menu("Markscheme") { picker("Markscheme", $filter.ms, Self.msOptions) }
            Menu("Level") { picker("Level", $filter.level, Self.levelOptions) }
            if !filter.isEmpty { Button("Clear filters", role: .destructive) { filter = .init() } }
        } label: {
            Label("Filter", systemImage: filter.count > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("study-sheets-filter")
    }

    private var sortMenu: some View {
        Menu { sortPicker } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
    }

    private var sortPicker: some View {
        Picker("Sort", selection: $sort) {
            ForEach(StudySheets.sorts, id: \.id) { Text($0.label).tag($0.id) }
        }
    }

    private func picker(_ title: String, _ value: Binding<String>, _ options: [(id: String, label: String)]) -> some View {
        Picker(title, selection: value) {
            ForEach(options, id: \.id) { Text($0.label).tag($0.id) }
        }
    }

    private func label(_ options: [(id: String, label: String)], _ value: String, _ none: String) -> String {
        value.isEmpty ? none : options.first { $0.id == value }?.label ?? value
    }

    /// The units of units.yaml by theme, else every code the sheets carry.
    private func unitOptions(_ all: [StudySheets.Sheet]) -> [(id: String, label: String)] {
        var out: [(id: String, label: String)] = [("", "Any unit")]
        let themes = study?.themes ?? []
        if !themes.isEmpty {
            for t in themes {
                out.append((t.code, t.code + (t.name.sub.map { " " + $0 } ?? "")))
                for u in t.units { out.append((u.code, u.code + (u.title.isEmpty ? "" : " " + u.title))) }
            }
        } else {
            let codes = Set(all.flatMap(\.codes)).sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
            out += codes.map { ($0, $0) }
        }
        return out
    }

    private func kindOptions(_ all: [StudySheets.Sheet]) -> [(id: String, label: String)] {
        [("", "Any kind")] + StudySheets.kinds.filter { k in all.contains { $0.kind == k } }.map { ($0, $0) }
    }

    static let eraOptions: [(id: String, label: String)] = [("", "Any syllabus"), ("2025", "2025 syllabus"), ("pre-2025", "Before 2025"), ("unknown", "Not marked")]
    static let msOptions: [(id: String, label: String)] = [("", "Markscheme: any"), ("with", "Has a markscheme"), ("none", "No markscheme"), ("only", "Markscheme only")]
    static let levelOptions: [(id: String, label: String)] = [("", "HL or SL"), ("HL", "HL"), ("SL", "SL")]
}

/// One sheet: its title (opens the paper), its kind and facts, syllabus and markscheme, the units it covers (each narrows the list
/// to that unit), its files, and the notes kept when it was uploaded.
struct SheetRow: View {
    let sheet: StudySheets.Sheet
    let root: URL
    var onUnit: ((String) -> Void)?
    let open: (URL) -> Void

    var body: some View {
        let s = sheet
        let facts = StudySheets.factsLine(s)
        let extra = Self.extraDetails(s)
        let files = Self.ordered(s)
        VStack(alignment: .leading, spacing: 6) {
            Button { openFirst() } label: {
                Text(s.title).font(.body.weight(.medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            Text(([s.kind, facts] + (extra.isEmpty ? [] : [extra.joined(separator: ", ")])).filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            FlowRow(spacing: 6) {
                if let e = s.era { Chip(text: e == "2025" ? "2025" : "pre-2025", color: e == "2025" ? Theme.planned : Theme.soon) }
                Chip(text: s.ms == "only" ? "MS only" : s.ms == "none" ? "no MS" : "MS")
                ForEach(Array(shownCodes(s).prefix(4)), id: \.self) { c in
                    if let onUnit {
                        Button { onUnit(c) } label: { Chip(text: c, color: Theme.accent) }.buttonStyle(.borderless)
                            .accessibilityLabel("Only \(c)")
                    } else {
                        Chip(text: c, color: Theme.accent)
                    }
                }
            }
            if files.count > 1 {
                FlowRow(spacing: 6) {
                    ForEach(files, id: \.file.path) { f in
                        Button { open(root.appendingPathComponent(f.file.path)) } label: {
                            Label(f.label, systemImage: f.file.role == "ms" ? "checkmark.seal" : f.file.role == "marked" ? "pencil" : "doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            if !s.notes.isEmpty {
                Label(s.notes, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("study-sheet")
    }

    private func openFirst() {
        guard let f = sheet.files.first(where: { $0.role == "paper" }) ?? sheet.files.first else { return }
        open(root.appendingPathComponent(f.path))
    }

    /// The codes, a theme left out when one of its units is there.
    private func shownCodes(_ s: StudySheets.Sheet) -> [String] {
        s.codes.filter { c in !StudySheets.isTheme(c) || !s.codes.contains { $0.hasPrefix(c + ".") } }
    }

    /// The files in pairs, each paper with its markscheme ("Paper 1", "Markscheme 1", "Paper 2", ...), papers first.
    static func ordered(_ s: StudySheets.Sheet) -> [(file: StudySheets.File, label: String)] {
        var stems: [String] = []
        for f in s.files { let st = StudySheets.stemOf(f.name); if !stems.contains(st) { stems.append(st) } }
        let order = ["paper": 0, "ms": 1, "marked": 2]
        let many = { (role: String) in s.files.filter { $0.role == role }.count > 1 }
        let files = s.files.enumerated().sorted { a, b in
            let sa = stems.firstIndex(of: StudySheets.stemOf(a.element.name)) ?? 0, sb = stems.firstIndex(of: StudySheets.stemOf(b.element.name)) ?? 0
            if sa != sb { return sa < sb }
            let ra = order[a.element.role] ?? 3, rb = order[b.element.role] ?? 3
            if ra != rb { return ra < rb }
            let c = a.element.name.localizedCompare(b.element.name)
            return c == .orderedSame ? a.offset < b.offset : c == .orderedAscending
        }.map(\.element)
        var nth: [String: Int] = [:]
        return files.map { f in
            nth[f.role, default: 0] += 1
            let name = f.role == "ms" ? "Markscheme" : f.role == "marked" ? "Marked copy" : "Paper"
            let word = f.name.range(of: #"\.docx?$"#, options: [.regularExpression, .caseInsensitive]) != nil ? " (Word)" : ""
            return (f, name + (many(f.role) ? " \(nth[f.role]!)" : "") + word)
        }
    }

    /// The parts of the details the kind and the facts line do not already say ("large question bank" stays; "SL & HL", "40 mk" go).
    static let said: Set<String> = ["hl", "sl", "&", "+", "and", "test", "mcq", "paper", "2", "structured", "question", "questions", "bank", "worksheet", "worked", "set", "mock", "exam", "only", "ms", "no"]
    static func extraDetails(_ s: StudySheets.Sheet) -> [String] {
        s.details.map { d -> String in
            let x = d.replacingOccurrences(of: #"\b[0-9]+\s*(mk|pp?|min|Q)\b"#, with: "", options: .regularExpression)
            return x.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }.filter { x in
            !x.isEmpty && x.lowercased().components(separatedBy: CharacterSet(charactersIn: " \t\n,")).contains { !$0.isEmpty && !said.contains($0) }
        }
    }
}

/// Small views in rows that wrap onto the next line when they don't fit.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > w { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing
            line = max(line, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            line = max(line, s.height)
        }
    }
}
