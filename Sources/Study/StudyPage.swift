import SwiftUI
import QuickLook
import NexusCore

/// A workstream's Study, what the laptop's Study tab has: the units covered (study/units.yaml, each with its sheets), Memorize (the
/// decks, and Practice classifying for a deck with a practice list), the chemistry tools, and the practice sheets (a browser over the
/// sheets folder, with Upload a sheet). The iPad shows the sheets beside the rest; the iPhone gives them their own screen.
struct StudyPage: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    let workstreamId: String

    @State private var filter = StudySheets.Filter()
    @State private var uploading = false
    @State private var preview: URL?

    private var lib: StudyLibrary { StudyLibrary.shared }

    var body: some View {
        Group {
            if let s = lib.study(workstreamId) {
                if size == .regular {
                    HStack(spacing: 0) {
                        overview(s, wide: true)
                            .frame(minWidth: 320, idealWidth: 400, maxWidth: 440)
                        Divider().ignoresSafeArea()
                        SheetsBrowser(workstreamId: workstreamId, filter: $filter, embedded: true)
                    }
                } else {
                    overview(s, wide: false)
                }
            } else {
                EmptyNote(title: "No study folder here", detail: "A workstream's Study comes from its study/ folder, which the laptop's Study tab makes.", icon: "questionmark.folder")
            }
        }
        .navigationTitle(lib.study(workstreamId).map { "\($0.workstream.name) · Study" } ?? "Study")
        .navigationBarTitleDisplayMode(.inline)
        .studyRefresh(store)
        .quickLookPreview($preview)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { uploading = true } label: { Label("Upload a sheet", systemImage: "doc.badge.plus") }
                    .disabled(!lib.canWrite(store) || lib.study(workstreamId) == nil)
                    .accessibilityIdentifier("study-upload")
            }
        }
        .sheet(isPresented: $uploading) {
            UploadSheetView(workstreamId: workstreamId)
        }
    }

    @ViewBuilder
    private func overview(_ s: StudyLibrary.Study, wide: Bool) -> some View {
        List {
            UnitsSection(study: s)
            Section {
                if s.decks.isEmpty {
                    Text("Put a deck in study/decks/ (a YAML file of cards) on the laptop and it shows here, with spaced-repetition review.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    DeckRows(study: s)
                    PracticeRows(study: s)
                }
            } header: {
                SectionTitle(title: "Memorize")
            }
            if s.isChemistry {
                Section {
                    StudyToolRows()
                } header: {
                    SectionTitle(title: "Tools")
                }
            }
            if !wide {
                Section {
                    NavigationLink {
                        SheetsBrowser(workstreamId: workstreamId, filter: $filter, embedded: false)
                    } label: {
                        Label {
                            HStack {
                                Text("Practice sheets")
                                Spacer()
                                Text("\(s.sheets.sheets.count)").foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "doc.on.doc") }
                    }
                    .accessibilityIdentifier("study-sheets")
                    Button { uploading = true } label: { Label("Upload a sheet", systemImage: "doc.badge.plus") }
                        .disabled(!lib.canWrite(store))
                } header: {
                    SectionTitle(title: "Practice sheets")
                } footer: {
                    Text("From \(s.config.sheets) in this workstream.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { lib.load(store) }
    }
}

// MARK: units

/// Units covered: each theme of study/units.yaml as a row with its units' progress; a theme opens its units.
struct UnitsSection: View {
    let study: StudyLibrary.Study

    var body: some View {
        let units = study.units ?? []
        Section {
            if let e = study.unitsError {
                Label(e, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Theme.late)
            }
            if units.isEmpty {
                if study.unitsError == nil {
                    Text("List the syllabus units in study/units.yaml (code, title, status: done, partial or not-yet) and they show here, each with its sheets.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ForEach(study.themes) { t in
                    NavigationLink {
                        ThemeUnitsView(workstreamId: study.id, theme: t.code)
                    } label: {
                        ThemeRow(study: study, theme: t)
                    }
                    .accessibilityIdentifier("study-theme-" + t.code)
                }
            }
        } header: {
            HStack {
                SectionTitle(title: "Units covered")
                Spacer()
                if !units.isEmpty {
                    let done = units.filter { $0.status == "done" }.count, part = units.filter { $0.status == "partial" }.count
                    Text("\(done) done\(part > 0 ? ", \(part) partly" : ""), of \(units.count)").font(.caption).foregroundStyle(.secondary).textCase(nil)
                }
            }
        }
    }
}

private struct ThemeRow: View {
    let study: StudyLibrary.Study
    let theme: StudyUnits.Theme

    var body: some View {
        let n = StudySheets.sheetsFor(unit: theme.code, in: study.sheets.sheets).count
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(theme.name.main).font(.body.weight(.semibold))
                Spacer(minLength: 6)
                Text(sheetCount(n)).font(.caption).foregroundStyle(.secondary)
            }
            if let sub = theme.name.sub { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            // a dot per unit, by how far it is covered
            HStack(spacing: 4) {
                ForEach(theme.units) { u in StatusDot(status: u.status) }
            }
            .accessibilityLabel(theme.units.map { "\($0.code) \(StudyUnits.statusLabel($0.status))" }.joined(separator: ", "))
        }
        .padding(.vertical, 2)
    }
}

/// A unit's status as a dot: filled when done, half when partly, an outline when not yet.
struct StatusDot: View {
    let status: String
    var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: 1.5)
            if status == "done" { Circle().fill(color) }
            if status == "partial" { Circle().trim(from: 0.25, to: 0.75).fill(color).rotationEffect(.degrees(180)) }
        }
        .frame(width: 10, height: 10)
    }
    private var color: Color { status == "done" ? Theme.accent : status == "partial" ? Theme.soon : Color.secondary }
}

/// A unit's status as a chip.
struct StatusChip: View {
    let status: String
    var body: some View {
        Chip(text: StudyUnits.statusLabel(status), icon: status == "done" ? "checkmark" : nil,
             color: status == "done" ? Theme.accent : status == "partial" ? Theme.soon : .secondary, strong: status == "done")
    }
}

/// One theme's units.
struct ThemeUnitsView: View {
    @Environment(NexusStore.self) private var store
    let workstreamId: String
    let theme: String

    var body: some View {
        let s = StudyLibrary.shared.study(workstreamId)
        let t = s?.themes.first { $0.code == theme }
        List {
            if let s, let t {
                Section {
                    NavigationLink {
                        UnitDetailView(workstreamId: workstreamId, code: t.code)
                    } label: {
                        HStack {
                            Text("Every sheet in \(t.name.main)")
                            Spacer()
                            Text("\(StudySheets.sheetsFor(unit: t.code, in: s.sheets.sheets).count)").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    if let sub = t.name.sub { Text(sub).textCase(nil) }
                }
                Section {
                    ForEach(t.units) { u in
                        NavigationLink {
                            UnitDetailView(workstreamId: workstreamId, code: u.code)
                        } label: {
                            HStack(spacing: 10) {
                                StatusDot(status: u.status)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(u.code).font(.callout.weight(.semibold).monospacedDigit())
                                    if !u.title.isEmpty { Text(u.title).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                                }
                                Spacer(minLength: 6)
                                let n = StudySheets.sheetsFor(unit: u.code, in: s.sheets.sheets, extra: u.sheets).count
                                if n > 0 { Text(sheetCount(n)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .accessibilityIdentifier("study-unit-" + u.code)
                    }
                } footer: {
                    HStack(spacing: 14) {
                        ForEach(StudyUnits.statuses, id: \.id) { st in
                            HStack(spacing: 4) { StatusDot(status: st.id); Text(st.label.lowercased()) }
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t?.name.main ?? theme)
        .navigationBarTitleDisplayMode(.inline)
        .studyRefresh(store)
    }
}

/// A unit (or a whole theme): how far it is covered, why, and its sheets.
struct UnitDetailView: View {
    @Environment(NexusStore.self) private var store
    let workstreamId: String
    let code: String
    @State private var preview: URL?
    @State private var filter = StudySheets.Filter()
    @State private var browsing = false

    var body: some View {
        let s = StudyLibrary.shared.study(workstreamId)
        let u = s?.units?.first { $0.code == code }
        let theme = u == nil ? s?.themes.first { $0.code == code } : nil
        let list = s.map { StudySheets.sheetsFor(unit: code, in: $0.sheets.sheets, extra: u?.sheets ?? []) } ?? []
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(code).font(.title2.weight(.semibold).monospacedDigit())
                        if let u { StatusChip(status: u.status) }
                    }
                    if let t = u?.title ?? theme?.name.sub ?? theme?.title, !t.isEmpty { Text(t).font(.headline) }
                    if let n = u?.notes, !n.isEmpty { Text(n).font(.callout) }
                    if let ev = u?.evidence, !ev.isEmpty {
                        (Text("How we know: ").foregroundStyle(.secondary) + Text(ev)).font(.callout)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                if list.isEmpty {
                    Text("No sheet is linked to this unit yet. Sheets link by their unit folder, the codes in their names and the topics in their titles.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(list) { sh in SheetRow(sheet: sh, root: store.folder, onUnit: nil) { preview = $0 } }
                }
            } header: {
                SectionTitle(title: "Sheets", count: list.count)
            } footer: {
                if !list.isEmpty {
                    Button("Show them in Practice sheets") { filter = .init(unit: code); browsing = true }
                        .font(.callout)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(code)
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .navigationDestination(isPresented: $browsing) {
            SheetsBrowser(workstreamId: workstreamId, filter: $filter, embedded: false)
        }
    }
}

func sheetCount(_ n: Int) -> String { "\(n) \(n == 1 ? "sheet" : "sheets")" }

// MARK: Practice classifying, from the Study page

/// A row for each deck with a practice list.
struct PracticeRows: View {
    let study: StudyLibrary.Study

    var body: some View {
        ForEach(study.decks) { f in
            if let d = f.deck, !d.practice.isEmpty {
                NavigationLink {
                    PracticeView(workstreamId: study.id, path: f.path)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.grid.2x2").foregroundStyle(.secondary).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Practice classifying")
                            Text("\(d.title): \(d.practice.count) to sort, unscheduled").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .accessibilityIdentifier("study-practice-" + d.id)
            }
        }
    }
}
