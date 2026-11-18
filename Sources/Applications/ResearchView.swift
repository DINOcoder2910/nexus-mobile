import SwiftUI
import NexusCore

/// Research (the laptop's grid): every school of the universities database plus yours, as All, Considering or Applying, searched, sorted
/// and filtered. The iPad shows a table of figures; the iPhone a list with the key figures under each name. A row of yours opens its
/// page; a database school opens its record, where Consider puts it on your list.
struct ResearchView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    var go: (Screen) -> Void
    @AppStorage("apps.list") private var list = "considering"
    @AppStorage("apps.sort") private var sort = "name"
    @AppStorage("apps.dir") private var dir = 1
    @AppStorage("apps.filters") private var filtersText = ""
    @State private var query = ""
    @State private var record: UniRow?
    @State private var filtering = false
    @State private var compare: Set<String> = []
    @State private var comparing = false

    static let sorts: [(String, String)] = [("name", "Name"), ("tier", "Tier"), ("acc", "Admit rate"), ("rank", "US News"), ("qs", "QS World"),
                                             ("eng", "US News Eng"), ("net", "Net price"), ("ug", "Undergrads"), ("deadline", "Next deadline")]

    var filters: Unis.Filters {
        get { (try? JSONDecoder().decode(Unis.Filters.self, from: Data(filtersText.utf8))) ?? Unis.Filters() }
        nonmutating set { filtersText = (try? String(decoding: JSONEncoder().encode(newValue), as: UTF8.self)) ?? "" }
    }

    var body: some View {
        let data = AppsData.shared
        let m = data.model(store)
        let all = m.rows(data.db)
        let rows = shown(all)
        VStack(spacing: 0) {
            header(all: all, rows: rows)
            if data.dbState == .loading && data.db == nil {
                ProgressView("Reading the universities database…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                EmptyNote(title: list == "all" ? "No school matches" : "No school in \(list == "applying" ? "Applying" : "Considering")",
                          detail: list == "all" ? "Clear the search or a filter." : "Find schools in All and choose Consider.", icon: "magnifyingglass")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if size == .regular {
                table(rows)
            } else {
                phoneList(rows)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search schools or cities")
        .sheet(item: $record) { r in UniRecordSheet(row: r, go: go) }
        .sheet(isPresented: $filtering) { FiltersSheet(filters: Binding(get: { filters }, set: { filters = $0 })) }
        .sheet(isPresented: $comparing) { CompareSheet(rows: all.filter { compare.contains($0.key) }) }
    }

    // MARK: header: the list, the active filters, sort and compare

    private func header(all: [UniRow], rows: [UniRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("List", selection: $list) {
                    Text("All").tag("all")
                    Text("Considering").tag("considering")
                    Text("Applying").tag("applying")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                Spacer(minLength: 0)
                Menu {
                    Picker("Sort by", selection: $sort) { ForEach(Self.sorts, id: \.0) { Text($0.1).tag($0.0) } }
                    Button { dir = -dir } label: { Label(dir > 0 ? "Descending" : "Ascending", systemImage: "arrow.up.arrow.down") }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down").labelStyle(.iconOnly) }
                Button { filtering = true } label: {
                    Label("Filters", systemImage: filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill").labelStyle(.iconOnly)
                }
                if !compare.isEmpty {
                    Button { comparing = true } label: { Label("Compare \(compare.count)", systemImage: "square.split.3x1") }
                        .buttonStyle(.bordered)
                }
            }
            let chips = Unis.activeFilters(filters)
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.key) { c in
                            Button { var f = filters; Unis.clearFilter(&f, c.key); filters = f } label: {
                                HStack(spacing: 3) { Text(c.label); Image(systemName: "xmark").imageScale(.small) }
                                    .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Theme.accent.opacity(0.12), in: Capsule()).foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("\(rows.count) of \(listRows(all).count) schools\(AppsData.shared.db == nil ? "" : list == "all" ? " in the universities database and yours" : "")")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: which rows, in which order

    private func listRows(_ all: [UniRow]) -> [UniRow] {
        switch list {
        case "applying": return all.filter(\.applying)
        case "considering": return all.filter { $0.mine && !$0.applying }
        default: return all
        }
    }

    private func shown(_ all: [UniRow]) -> [UniRow] {
        let f = filters
        let rows = listRows(all).filter { Unis.matches($0, query) && Unis.passes($0, f) }
        return Unis.sortRows(rows, dir: dir) { r in key(r) }
    }

    private func key(_ r: UniRow) -> Unis.Key? {
        switch sort {
        case "tier": return Unis.tierKey(r).map { .n($0) }
        case "acc": return Unis.accOf(r).map { .n($0) }
        case "rank": return Unis.rankOf(r, "usnNational").map { .n($0) }
        case "qs": return Unis.rankOf(r, "qs").map { .n($0) }
        case "eng": return Unis.rankOf(r, Unis.anyEng).map { .n($0) }
        case "net": return r.u?.net.map { .n($0) }
        case "ug": return r.u?.ug.map { .n(Double($0)) }
        case "deadline": return (r.s?.deadline ?? r.s?.nextDeadline).map { .s($0) }
        default: return .s(r.label)
        }
    }

    private func open(_ r: UniRow) {
        if let s = r.s { go(.school(s.id)) } else { record = r }
    }

    // MARK: the iPad's table

    private func table(_ rows: [UniRow]) -> some View {
        Table(rows) {
            TableColumn("School") { r in
                HStack(spacing: 8) {
                    compareBox(r)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            if r.mine { Circle().fill(store.schoolColor(r.s?.id)).frame(width: 7, height: 7) }
                            Text(r.label).font(.subheadline.weight(r.mine ? .semibold : .regular)).lineLimit(1)
                        }
                        if r.full != r.label { Text(r.full).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { open(r) }
                .contextMenu { RowMenu(row: r, go: go) }
            }
            .width(min: 200, ideal: 260)
            TableColumn("Tier") { r in TierChip(row: r) }.width(110)
            TableColumn("Admit") { r in StatCell(row: r, k: "acc", text: Unis.accOf(r).map { pct($0) }) }.width(70)
            TableColumn("US News") { r in StatCell(row: r, k: "rank", text: Unis.rankText(r, "usnNational")) }.width(70)
            TableColumn("Eng") { r in StatCell(row: r, k: "eng", text: Unis.rankText(r, Unis.anyEng)) }.width(60)
            TableColumn("Where") { r in Text([r.u?.city, r.u?.st].compactMap { $0 }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 90, ideal: 130)
            TableColumn("Size") { r in Text(r.u?.ug.map { "\($0.formatted())" } ?? "").font(.caption).foregroundStyle(.secondary) }.width(70)
            TableColumn("Status") { r in StatusCell(row: r) }.width(min: 110, ideal: 150)
        }
    }

    private func compareBox(_ r: UniRow) -> some View {
        Button { if compare.contains(r.key) { compare.remove(r.key) } else if compare.count < 3 { compare.insert(r.key) } } label: {
            Image(systemName: compare.contains(r.key) ? "checkmark.square.fill" : "square").foregroundStyle(compare.contains(r.key) ? Theme.accent : Color.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Compare")
    }

    // MARK: the iPhone's list

    private func phoneList(_ rows: [UniRow]) -> some View {
        List {
            ForEach(rows.prefix(400)) { r in
                Button { open(r) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if r.mine { Circle().fill(store.schoolColor(r.s?.id)).frame(width: 8, height: 8) }
                            Text(r.label).font(.body.weight(r.mine ? .semibold : .regular)).foregroundStyle(.primary).lineLimit(1)
                            Spacer(minLength: 4)
                            TierChip(row: r)
                        }
                        HStack(spacing: 10) {
                            if let a = Unis.accOf(r) { fact("Admit", pct(a)) }
                            if let n = Unis.rankText(r, "usnNational") { fact("US News", n) }
                            if let e = Unis.rankText(r, Unis.anyEng) { fact("Eng", e) }
                            if let st = r.u?.st { Text(st).font(.caption).foregroundStyle(.secondary) }
                        }
                        StatusCell(row: r)
                    }
                }
                .contextMenu { RowMenu(row: r, go: go) }
                .swipeActions(edge: .leading) {
                    if !r.mine {
                        Button { AppsData.shared.edit(store) { e, m in try e.consider(r, model: m, rows: m.rows(AppsData.shared.db), snapshot: store.snapshot, today: store.today).0 } } label: {
                            Label("Consider", systemImage: "plus")
                        }
                        .tint(Theme.accent)
                    }
                }
            }
            if rows.count > 400 { Text("Showing the first 400. Search or filter to find the rest.").font(.caption).foregroundStyle(.secondary) }
        }
        .listStyle(.plain)
    }

    private func fact(_ l: String, _ v: String) -> some View {
        HStack(spacing: 3) { Text(l).foregroundStyle(.secondary); Text(v) }.font(.caption)
    }
}

func pct(_ v: Double) -> String { JSONValue.format((v * 10).rounded() / 10) + "%" }

/// The figure with the shade of where it stands among every school (green good, red not).
struct StatCell: View {
    let row: UniRow
    let k: String
    let text: String?
    var body: some View {
        Text(text ?? "–").font(.subheadline.monospacedDigit()).foregroundStyle(text == nil ? .tertiary : .primary)
    }
}

/// Considering / Applying / Applied, and the round and next deadline of a school of yours.
struct StatusCell: View {
    let row: UniRow
    var body: some View {
        if let s = row.s {
            HStack(spacing: 4) {
                Text(s.applied != nil ? "Applied" : s.applying ? "Applying" : "Considering").font(.caption.weight(.medium))
                    .foregroundStyle(s.applying ? Theme.accent : .secondary)
                if let r = s.round, s.applying { Text(s.roundLabel(r)).font(.caption).foregroundStyle(.secondary) }
                if let d = s.applying ? s.deadline : s.nextDeadline { Text(Apps.short(d)).font(.caption).foregroundStyle(.secondary) }
            }
        } else if row.dropped != nil {
            Text("Removed").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// The tier as a small menu: Safety, Target, Reach, Dream, and a position 1 to 5 inside it.
struct TierChip: View {
    @Environment(NexusStore.self) private var store
    let row: UniRow
    var body: some View {
        let t = Unis.tierOf(row), lv = Unis.levelOf(row)
        Menu {
            ForEach(Unis.tiers, id: \.self) { tier in
                Menu(Unis.tierNames[tier] ?? tier) {
                    Button("No position") { set(tier, nil) }
                    ForEach(1...5, id: \.self) { n in Button("\(n) of 5") { set(tier, n) } }
                }
            }
            if t != nil { Button("No tier", role: .destructive) { set(nil, nil) } }
        } label: {
            Text(t.map { (Unis.tierNames[$0] ?? $0) + (lv.map { " \($0)" } ?? "") } ?? "Tier")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .foregroundStyle(t == nil ? Color.secondary : tierColor(t!))
                .background((t == nil ? Color.secondary : tierColor(t!)).opacity(0.12), in: Capsule())
        }
        .disabled(store.snapshot.readOnlyReason != nil || (row.u == nil && row.s == nil))
    }
    private func set(_ tier: String?, _ level: Int?) {
        AppsData.shared.edit(store) { e, m in try e.setTier(row, tier: tier, level: level, model: m) }
    }
}

func tierColor(_ t: String) -> Color {
    switch t {
    case "safety": return Theme.planned
    case "target": return Theme.claude
    case "reach": return Theme.soon
    default: return Theme.late
    }
}

/// A row's long-press menu: open, consider, start, remove, tier.
struct RowMenu: View {
    @Environment(NexusStore.self) private var store
    let row: UniRow
    var go: (Screen) -> Void
    var body: some View {
        if let s = row.s {
            Button { go(.school(s.id)) } label: { Label("Open \(s.short)", systemImage: "building.columns") }
            if !s.applying {
                Menu("Start applying") {
                    ForEach(Apps.roundKeys, id: \.self) { k in
                        Button(Apps.roundLong[k] ?? k) { AppsData.shared.edit(store) { e, m in try e.startApplying(s, round: k, model: m, snapshot: store.snapshot, today: store.today) } }
                    }
                }
            }
            Button(role: .destructive) { AppsData.shared.edit(store) { e, m in try e.remove(s, model: m) } } label: { Label("Remove from the list", systemImage: "minus.circle") }
        } else {
            Button { AppsData.shared.edit(store) { e, m in try e.consider(row, model: m, rows: m.rows(AppsData.shared.db), snapshot: store.snapshot, today: store.today).0 } } label: {
                Label(row.dropped != nil ? "Put back on the list" : "Consider", systemImage: "plus.circle")
            }
        }
        if let u = row.u?.url, let url = URL(string: u) { Link(destination: url) { Label("Website", systemImage: "safari") } }
    }
}

// MARK: - a database school's record

struct UniRecordSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let row: UniRow
    var go: (Screen) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let u = row.u {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(u.full).font(.headline)
                            Text([u.city, u.st.flatMap { Unis.states[$0] }].compactMap { $0 }.joined(separator: ", ") + (u.ctrl.flatMap { Unis.ctrlNames[$0] }.map { " · " + $0 } ?? ""))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack { Text("Tier"); Spacer(); TierChip(row: row) }
                    }
                    Section("Admissions") {
                        fact("Admit rate", u.acc.map(pct))
                        ForEach(Apps.roundKeys, id: \.self) { k in
                            if let r = u.rounds[k] {
                                fact("\(Apps.roundLong[k] ?? k) admit rate", r.rate.map(pct).map { $0 + (r.year.map { " (fall \($0))" } ?? "") })
                            }
                        }
                        fact("SAT", u.sat.map { $0.map { String(Int($0)) }.joined(separator: "–") })
                        fact("ACT", u.act.map { $0.map { String(Int($0)) }.joined(separator: "–") })
                    }
                    Section("Rankings") {
                        fact("US News", Unis.rankText(row, "usnNational"))
                        fact("US News Engineering", Unis.rankText(row, Unis.anyEng))
                        fact("QS World", Unis.rankText(row, "qs"))
                    }
                    Section("Money and outcomes") {
                        fact("Tuition", (u.tout ?? u.tin).map { "$" + Int($0).formatted() })
                        fact("Average net price", u.net.map { "$" + Int($0).formatted() })
                        fact("Graduation rate", u.grad.map(pct))
                        fact("Median earnings", u.earn.map { "$" + Int($0).formatted() })
                        fact("Undergraduates", u.ug.map { $0.formatted() })
                    }
                    if u.offersEng || u.offersCS {
                        Section("Engineering") {
                            fact("Engineering", Unis.engSizeOf(u.offersEng, u.engN).flatMap { Unis.engNames[$0] }.map { $0 + (u.engN.map { ", \($0) degrees a year" } ?? "") })
                            if !u.engFields.isEmpty { Text(u.engFields.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                            fact("Computer science", u.offersCS ? (u.csN.map { "\($0) degrees a year" } ?? "Offered") : nil)
                        }
                    }
                    Section {
                        if let a = u.admissionsUrl, let url = URL(string: a) { Link("Admissions site", destination: url) }
                        if let n = u.npcUrl, let url = URL(string: n) { Link("Net price calculator", destination: url) }
                    }
                }
            }
            .navigationTitle(row.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button("Consider") { consider(start: false, round: nil) }
                        Menu("Consider and start applying") {
                            ForEach(Apps.roundKeys, id: \.self) { k in Button(Apps.roundLong[k] ?? k) { consider(start: true, round: k) } }
                        }
                    } label: { Text(row.dropped != nil ? "Put back" : "Consider").bold() } primaryAction: { consider(start: false, round: nil) }
                    .disabled(store.snapshot.readOnlyReason != nil)
                }
            }
        }
    }

    private func consider(start: Bool, round: String?) {
        var id: String?
        let ok = AppsData.shared.edit(store) { e, m in
            let (c, i) = try e.consider(row, model: m, rows: m.rows(AppsData.shared.db), start: start, round: round, snapshot: store.snapshot, today: store.today)
            id = i
            return c
        }
        dismiss()
        if ok, let id { go(.school(id)) }
    }

    @ViewBuilder
    private func fact(_ l: String, _ v: String?) -> some View {
        if let v { HStack { Text(l); Spacer(); Text(v).foregroundStyle(.secondary) } }
    }
}

// MARK: - filters and compare

struct FiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: Unis.Filters
    @State private var f = Unis.Filters()
    @State private var state = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") { toggles(["pub", "pri"], names: Unis.ctrlNames, in: $f.type) }
                Section("Size") { toggles(["small", "medium", "large"], names: Unis.sizeNames, in: $f.size) }
                Section("Tier") { toggles(Unis.tiers + ["none"], names: Unis.tierNames.merging(["none": "No tier"]) { a, _ in a }, in: $f.tier) }
                Section("Admit rate") {
                    HStack { TextField("From %", text: $f.accMin).keyboardType(.decimalPad); Text("to"); TextField("To %", text: $f.accMax).keyboardType(.decimalPad) }
                }
                Section("Programs") {
                    Toggle("Engineering offered", isOn: $f.eng)
                    Toggle("Computer science offered", isOn: $f.cs)
                }
                Section("Ranked within") {
                    TextField("Top… (US News Engineering)", text: $f.rankTop).keyboardType(.numberPad)
                }
                Section("States") {
                    if !f.states.isEmpty { Text(f.states.joined(separator: ", ")) }
                    HStack {
                        TextField("Add a state (CA or California)", text: $state)
                        Button("Add") { if let c = Unis.stateCode(state), !f.states.contains(c) { f.states.append(c) }; state = "" }
                    }
                    if !f.states.isEmpty { Button("Clear states", role: .destructive) { f.states = [] } }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Clear all") { f = Unis.Filters() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { filters = f; dismiss() } }
            }
            .onAppear { f = filters }
        }
    }

    private func toggles(_ keys: [String], names: [String: String], in set: Binding<[String]>) -> some View {
        ForEach(keys, id: \.self) { k in
            Toggle(names[k] ?? k, isOn: Binding(get: { set.wrappedValue.contains(k) }, set: { on in
                if on { if !set.wrappedValue.contains(k) { set.wrappedValue.append(k) } } else { set.wrappedValue.removeAll { $0 == k } }
            }))
        }
    }
}

/// Up to three schools side by side.
struct CompareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [UniRow]

    var body: some View {
        let lines: [(String, (UniRow) -> String?)] = [
            ("Tier", { r in Unis.tierOf(r).map { Unis.tierText($0, Unis.levelOf(r)) } }),
            ("Admit rate", { r in Unis.accOf(r).map(pct) }),
            ("Best early rate", { r in Apps.bestEarly(r.s, r.u).map(pct) }),
            ("US News", { r in Unis.rankText(r, "usnNational") }),
            ("US News Engineering", { r in Unis.rankText(r, Unis.anyEng) }),
            ("QS World", { r in Unis.rankText(r, "qs") }),
            ("Where", { r in [r.u?.city, r.u?.st].compactMap { $0 }.joined(separator: ", ") }),
            ("Undergraduates", { r in r.u?.ug.map { $0.formatted() } }),
            ("Net price", { r in r.u?.net.map { "$" + Int($0).formatted() } }),
            ("Graduation", { r in r.u?.grad.map(pct) }),
            ("Earnings", { r in r.u?.earn.map { "$" + Int($0).formatted() } }),
            ("Next deadline", { r in r.s?.nextDeadline.map { SiteFacts.fmtDate($0) } }),
        ]
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        Text("")
                        ForEach(rows) { r in Text(r.label).font(.headline) }
                    }
                    Divider()
                    ForEach(lines, id: \.0) { l in
                        GridRow {
                            Text(l.0).foregroundStyle(.secondary)
                            ForEach(rows) { r in Text(l.1(r) ?? "–") }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - add a school

struct AddSchoolSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var go: (Screen) -> Void
    @State private var name = ""
    @State private var round = ""
    @State private var start = false

    var body: some View {
        let db = AppsData.shared.db
        let q = name.trimmingCharacters(in: .whitespaces)
        let matches: [UniSchool] = q.count < 2 ? [] : (db?.list ?? []).filter { u in
            let h = (u.name + " " + u.short + " " + u.aliases.joined(separator: " ")).lowercased()
            return q.lowercased().split(separator: " ").allSatisfy { h.contains($0) }
        }.prefix(8).map { $0 }
        NavigationStack {
            Form {
                Section {
                    TextField("School name", text: $name).accessibilityIdentifier("apps-add-name")
                } footer: { Text("Pick it from the universities database when it is there: its figures and deadlines come with it.") }
                if !matches.isEmpty {
                    Section("In the database") {
                        ForEach(matches) { u in
                            Button { add(u) } label: {
                                VStack(alignment: .leading) {
                                    Text(u.short).foregroundStyle(.primary)
                                    Text([u.full, u.city, u.st].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Picker("Round", selection: $round) {
                        Text("Not yet").tag("")
                        ForEach(Apps.roundKeys, id: \.self) { Text(Apps.roundLong[$0] ?? $0).tag($0) }
                    }
                    Toggle("Start applying now", isOn: $start)
                }
            }
            .navigationTitle("Add a school")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { add(nil) }.disabled(q.isEmpty) }
            }
        }
    }

    private func add(_ u: UniSchool?) {
        var id: String?
        let ok = AppsData.shared.edit(store) { e, m in
            if let u {
                let row = m.rows(AppsData.shared.db).first { $0.u?.id == u.id } ?? UniRow(key: "u\(u.id)", u: u, s: nil, dropped: nil, t: nil)
                if let s = row.s { id = s.id; throw AppsEditor.Failure.cannot("\(s.name) is already in the list.") }
                let (c, i) = try e.consider(row, model: m, rows: m.rows(AppsData.shared.db), start: start, round: round.isEmpty ? nil : round, snapshot: store.snapshot, today: store.today)
                id = i; return c
            }
            let (c, i) = try e.addSchool(name, model: m, round: round.isEmpty ? nil : round, start: start, snapshot: store.snapshot, today: store.today)
            id = i; return c
        }
        dismiss()
        if ok, let id { go(.school(id)) }
    }
}
