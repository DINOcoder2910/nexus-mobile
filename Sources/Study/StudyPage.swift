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
    @State private var openTheme: String?
    @State private var openUnit: String?

    private var lib: StudyLibrary { StudyLibrary.shared }

    var body: some View {
        Group {
            if let s = lib.study(workstreamId) {
                if size == .regular {
                    HStack(spacing: 0) {
                        overview(s, wide: true)
                            .frame(minWidth: 340, idealWidth: 460, maxWidth: 560)
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
            if SpanishLibrary.shared.workstream(workstreamId) != nil {
                Section {
                    NavigationLink {
                        SpanishHome(workstreamId: workstreamId)
                    } label: {
                        Label("Spanish: checker, tutor, writing, skills", systemImage: "character.bubble")
                    }
                    .accessibilityIdentifier("study-spanish")
                    NavigationLink {
                        OralPage(workstreamId: workstreamId)
                    } label: {
                        Label("Oral practice: past orals, add a recording, the listening test", systemImage: "mic")
                    }
                    .accessibilityIdentifier("study-oral-page")
                }
            }
            UnitsSection(study: s, openTheme: $openTheme, openUnit: $openUnit)
            Section {
                if s.decks.isEmpty {
                    Text("Put a deck in study/decks/ (a YAML file of cards) on the laptop and it shows here, with spaced-repetition review.")
                        .font(.nx(.callout)).foregroundStyle(.secondary)
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
        .navigationDestination(item: $openTheme) { code in ThemeUnitsView(workstreamId: workstreamId, theme: code) }
        .navigationDestination(item: $openUnit) { code in UnitDetailView(workstreamId: workstreamId, code: code) }
    }
}

// MARK: units

/// Units covered, as the new look keeps it (picked Nov 20 2026 over unit cards; project files new-look/mockups/study-ipad-light-v2.png):
/// one card of study/units.yaml's themes, each a row with its question, its sheet count and a chip per unit (done, partly, not yet),
/// the unit studied now outlined in the subject's colour and its theme's row lifted onto the page; a legend under it. A theme's
/// row opens its units, a chip opens that unit.
struct UnitsSection: View {
    let study: StudyLibrary.Study
    @Environment(NexusStore.self) private var store
    /// What a tap opens (StudyPage's list pushes it: a navigation destination can't sit inside the lazy list).
    @Binding var openTheme: String?
    @Binding var openUnit: String?

    var body: some View {
        let units = study.units ?? []
        Section {
            if let e = study.unitsError {
                Label(e, systemImage: "exclamationmark.triangle").font(.nx(.callout)).foregroundStyle(Theme.late)
            }
            if units.isEmpty {
                if study.unitsError == nil {
                    Text("List the syllabus units in study/units.yaml (code, title, status: done, partial or not-yet) and they show here, each with its sheets.")
                        .font(.nx(.callout)).foregroundStyle(.secondary)
                }
            } else {
                card(units)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        } header: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionTitle(title: "Units covered")
                if !units.isEmpty {
                    let done = units.filter { $0.status == "done" }.count, part = units.filter { $0.status == "partial" }.count
                    Text("\(done) done\(part > 0 ? ", \(part) partly" : ""), of \(units.count)").font(.nx(.subheadline)).foregroundStyle(Kit.muted).textCase(nil)
                }
                Spacer()
            }
        }
    }

    private func card(_ units: [StudyUnits.Unit]) -> some View {
        let now = StudyUnits.current(units)
        let color = store.color(workstream: study.id)
        return VStack(spacing: 2) {
            ForEach(study.themes) { t in
                ThemeRow(study: study, theme: t, now: now, color: color, open: { openTheme = t.code }, openUnit: { openUnit = $0 })
            }
            UnitLegend()
        }
        .padding(6)
        .background(Kit.rests, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A theme of the units card: its name and question, how many sheets, and its units as chips.
private struct ThemeRow: View {
    let study: StudyLibrary.Study
    let theme: StudyUnits.Theme
    let now: String?
    let color: Color
    let open: () -> Void
    let openUnit: (String) -> Void
    @Environment(\.horizontalSizeClass) private var size

    var body: some View {
        let n = StudySheets.sheetsFor(unit: theme.code, in: study.sheets.sheets).count
        let current = theme.units.contains { $0.code == now }
        let name = Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.name.main).font(.nx(.callout, .semibold)).foregroundStyle(Kit.ink)
                if let sub = theme.name.sub { Text(sub).font(.nx(.subheadline)).foregroundStyle(Kit.muted).lineLimit(size == .regular ? 1 : 2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("study-theme-" + theme.code)
        let count = Text(sheetCount(n)).font(.nx(.subheadline)).foregroundStyle(Kit.faint).opacity(n == 0 ? 0.6 : 1).monospacedDigit()
        let chips = FlowChips(units: theme.units, now: now, color: color, openUnit: openUnit)
        // a row of three columns where there is room (the iPad's Study tab), else the chips under the name
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                name.frame(minWidth: 220)
                count.frame(width: 72, alignment: .trailing)
                chips.frame(width: 290, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 8) {
                name
                HStack(alignment: .center, spacing: 10) { chips; Spacer(minLength: 0); count }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            if current {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Kit.page).shadow(color: .black.opacity(0.07), radius: 6, y: 2)
            }
        }
    }
}

/// A theme's units as chips, wrapping onto a second line when they don't fit.
private struct FlowChips: View {
    let units: [StudyUnits.Unit]
    let now: String?
    let color: Color
    let openUnit: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(stride(from: 0, to: units.count, by: 3)), id: \.self) { i in
                    HStack(spacing: 6) {
                        ForEach(units[i..<min(i + 3, units.count)]) { u in chip(u) }
                    }
                }
            }
        }
    }

    private var chips: some View { ForEach(units) { u in chip(u) } }

    private func chip(_ u: StudyUnits.Unit) -> some View {
        Button { openUnit(u.code) } label: {
            UnitChip(code: u.code, status: u.code == now ? "now" : u.status, color: color)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(u.code) \(u.code == now ? "now" : StudyUnits.statusLabel(u.status))")
    }
}

/// One unit as the kit's chip: done (a tick on the accent's wash), partly (half a circle on amber's), not yet (a ring on a tone),
/// or the one studied now (outlined in the subject's colour, "· now").
struct UnitChip: View {
    let code: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            UnitMark(status: status, color: fg)
            Text(code).font(.nx(size: 14, .semibold, display: true, relativeTo: .subheadline)).monospacedDigit()
            if status == "now" { Text("· now").font(.nx(.caption, .medium)).opacity(0.85) }
        }
        .foregroundStyle(fg)
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .frame(height: 30)
        .background(bg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            if status == "now" { RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(color, lineWidth: 2) }
        }
    }

    private var fg: Color {
        switch status {
        case "done": return Theme.accent
        case "partial": return Theme.soon
        case "now": return color
        default: return Kit.muted
        }
    }

    private var bg: Color {
        switch status {
        case "done": return Kit.accentWash
        case "partial": return Kit.warnWash
        case "now": return Kit.page
        default: return Kit.hover
        }
    }
}

/// The chip's mark: a tick, half a circle, or a ring.
struct UnitMark: View {
    let status: String
    let color: Color

    var body: some View {
        Group {
            switch status {
            case "done":
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
            case "partial":
                ZStack {
                    Circle().strokeBorder(color, lineWidth: 1.8)
                    Circle().trim(from: 0.25, to: 0.75).fill(color).rotationEffect(.degrees(180)).padding(1)
                }
                .frame(width: 12, height: 12)
            default:
                Circle().strokeBorder(color, lineWidth: 1.8).frame(width: 12, height: 12)
            }
        }
        .foregroundStyle(color)
        .frame(width: 13, height: 13)
    }
}

/// done · partly · not yet, and how the card works.
private struct UnitLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) { UnitMark(status: "done", color: Theme.accent); Text("done") }
            HStack(spacing: 5) { UnitMark(status: "partial", color: Theme.soon); Text("partly") }
            HStack(spacing: 5) { UnitMark(status: "not-yet", color: Kit.faint); Text("not yet") }
            Spacer(minLength: 8)
            Text("Tap a unit to see its sheets")
        }
        .font(.nx(.caption))
        .foregroundStyle(Kit.faint)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
                                    Text(u.code).font(.nx(.callout, .semibold).monospacedDigit())
                                    if !u.title.isEmpty { Text(u.title).font(.nx(.callout)).foregroundStyle(.secondary).lineLimit(2) }
                                }
                                Spacer(minLength: 6)
                                let n = StudySheets.sheetsFor(unit: u.code, in: s.sheets.sheets, extra: u.sheets).count
                                if n > 0 { Text(sheetCount(n)).font(.nx(.caption)).foregroundStyle(.secondary) }
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
                    .font(.nx(.caption))
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
                        Text(code).font(.nx(.title2, .semibold).monospacedDigit())
                        if let u { StatusChip(status: u.status) }
                    }
                    if let t = u?.title ?? theme?.name.sub ?? theme?.title, !t.isEmpty { Text(t).font(.nx(.headline)) }
                    if let n = u?.notes, !n.isEmpty { Text(n).font(.nx(.callout)) }
                    if let ev = u?.evidence, !ev.isEmpty {
                        (Text("How we know: ").foregroundStyle(.secondary) + Text(ev)).font(.nx(.callout))
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                if list.isEmpty {
                    Text("No sheet is linked to this unit yet. Sheets link by their unit folder, the codes in their names and the topics in their titles.")
                        .font(.nx(.callout)).foregroundStyle(.secondary)
                } else {
                    ForEach(list) { sh in SheetRow(sheet: sh, root: store.folder, onUnit: nil) { preview = $0 } }
                }
            } header: {
                SectionTitle(title: "Sheets", count: list.count)
            } footer: {
                if !list.isEmpty {
                    Button("Show them in Practice sheets") { filter = .init(unit: code); browsing = true }
                        .font(.nx(.callout))
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
                            Text("\(d.title): \(d.practice.count) to sort, unscheduled").font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .accessibilityIdentifier("study-practice-" + d.id)
            }
        }
    }
}
