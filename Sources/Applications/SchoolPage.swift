import SwiftUI
import NexusCore

/// A school's page (the laptop's appsschool.js): where it stands and what to do next, its open tasks, checklist and essays, Claude's research
/// (About), its numbers and deadlines, notes.md and sources. The iPad shows two columns; the iPhone one, with the less used actions in the
/// toolbar's menu.
struct SchoolPage: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    @Environment(\.openURL) private var openURL
    let id: String
    var go: (Screen) -> Void

    @State private var notes: String?
    @State private var editingNotes: String?
    @State private var addingReq = false
    @State private var reqText = ""
    @State private var addingEssay = false
    @State private var checking = false
    @State private var editingRound: String?
    @State private var editingOwn: String?
    @State private var ownText = ""
    @State private var addingSource = false
    @State private var sourceText = ""
    @State private var confirmStart: String?
    @State private var settingDate = false
    @State private var dateText = ""

    var body: some View {
        let data = AppsData.shared
        let m = data.model(store)
        Group {
            if let s = m.school(id) {
                content(s, m)
            } else {
                EmptyNote(title: "This school is not in the folder", detail: "It may have been renamed or removed on the laptop.", icon: "questionmark.folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(id)|\(store.snapshot.loadedAt.timeIntervalSince1970)") {
            data.loadDB()
            if let s = m.school(id) { notes = DataFolder.text(store.folder, s.folder + "/notes.md") }
        }
    }

    private func row(_ m: AppsModel, _ s: School) -> UniRow? { m.rows(AppsData.shared.db).first { $0.s?.id == s.id || $0.dropped?.id == s.id } }

    @ViewBuilder
    private func content(_ s: School, _ m: AppsModel) -> some View {
        let r = row(m, s)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(s, m, r)
                if size == .regular {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 14) { work(s, m) }.frame(maxWidth: .infinity, alignment: .top)
                        VStack(alignment: .leading, spacing: 14) { facts(s, m, r) }.frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    work(s, m)
                    facts(s, m, r)
                }
            }
            .padding(size == .regular ? 20 : 14)
        }
        .refreshable { store.reload() }
        .navigationTitle(s.short)
        .toolbar { ToolbarItem(placement: .primaryAction) { moreMenu(s, m, r) } }
        .sheet(isPresented: Binding(get: { editingNotes != nil }, set: { if !$0 { editingNotes = nil } })) {
            NotesEditor(title: "\(s.short) notes", text: editingNotes ?? "") { new in
                store.writeText(s.folder + "/notes.md", new, message: "Notes saved: \(s.short)")
                notes = DataFolder.text(store.folder, s.folder + "/notes.md")
            }
        }
        .sheet(isPresented: $addingEssay) { AddEssaySheet(school: s) }
        .sheet(isPresented: $checking) { SiteCheckSheet(school: s, start: r?.u?.admissionsUrl ?? r?.u?.url ?? "") }
        .sheet(item: Binding(get: { editingRound.map { RoundKey(k: $0) } }, set: { editingRound = $0?.k })) { k in RoundSheet(school: s, k: k.k) }
        .alert("Add to the checklist", isPresented: $addingReq) {
            TextField("Interview, portfolio…", text: $reqText)
            Button("Add") { let t = reqText; AppsData.shared.edit(store) { e, _ in try e.addRequirement(s, t) }; reqText = "" }
            Button("Cancel", role: .cancel) { reqText = "" }
        }
        .alert(ownLabel(editingOwn), isPresented: Binding(get: { editingOwn != nil }, set: { if !$0 { editingOwn = nil } })) {
            TextField("Number (empty clears it)", text: $ownText).keyboardType(.decimalPad)
            Button("Save") {
                let f = editingOwn ?? "", v = Double(ownText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
                AppsData.shared.edit(store) { e, _ in try e.setOwn(s, field: f, value: v) }
                editingOwn = nil
            }
            Button("Cancel", role: .cancel) { editingOwn = nil }
        } message: { Text("Your own figure wins over the database's.") }
        .alert("Add a source", isPresented: $addingSource) {
            TextField("https://…", text: $sourceText).keyboardType(.URL).textInputAutocapitalization(.never)
            Button("Add") { let u = sourceText.trimmingCharacters(in: .whitespaces); if !u.isEmpty { AppsData.shared.edit(store) { e, _ in try e.addSource(s, url: u) } }; sourceText = "" }
            Button("Cancel", role: .cancel) { sourceText = "" }
        }
        .alert("Your own date for \(s.short)", isPresented: $settingDate) {
            TextField("1 Nov, or 2026-11-01 (empty clears it)", text: $dateText)
            Button("Save") {
                let d = dateText.trimmingCharacters(in: .whitespaces)
                let iso = d.isEmpty ? nil : Apps.parseDateInput(d, today: store.today)
                if !d.isEmpty && iso == nil { store.problem = "\"\(d)\" is not a date Nexus can read." }
                else { AppsData.shared.edit(store) { e, _ in try e.setInternal(s, iso) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The day you want it done by, before the real deadline.") }
        .confirmationDialog("Applying ED to \(s.short)?", isPresented: Binding(get: { confirmStart != nil }, set: { if !$0 { confirmStart = nil } }), titleVisibility: .visible) {
            Button("Start applying anyway") { if let k = confirmStart { start(s, k) } }
        } message: { Text(confirmStart.flatMap { Apps.edConflict(m.schools, schoolId: s.id, round: $0) } ?? "") }
    }

    private func ownLabel(_ f: String?) -> String {
        switch f { case "acc": return "Admit rate %"; case "usn": return "US News rank"; case "usne": return "US News Engineering rank"; case "qs": return "QS World rank"; default: return "" }
    }

    // MARK: the header: status and the next step

    private func header(_ s: School, _ m: AppsModel, _ r: UniRow?) -> some View {
        AppsCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Circle().fill(store.schoolColor(s.id)).frame(width: 10, height: 10)
                            Text(s.name).font(.title3.weight(.semibold))
                        }
                        Text(statusLine(s)).font(.subheadline).foregroundStyle(.secondary)
                        if let u = r?.u { Text([u.city, u.st].compactMap { $0 }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if let r { TierChip(row: r) }
                }
                if s.dropped {
                    Button { AppsData.shared.edit(store) { e, _ in try e.restore(s) } } label: { Label("Put back on the list", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                } else if !s.applying {
                    HStack {
                        Menu {
                            ForEach(Apps.roundKeys, id: \.self) { k in
                                Button { ask(s, k, m) } label: {
                                    Text("\(Apps.roundLong[k] ?? k)\(s.research.rounds[k]?.dl.map { ", due \(Apps.short($0))" } ?? "")")
                                }
                            }
                        } label: { Label("Start applying", systemImage: "flag.checkered").frame(maxWidth: size == .regular ? nil : .infinity) }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        if m.cap.n + 1 > Apps.maxApplying { Text("That would be over the cap of \(Apps.maxApplying).").font(.caption).foregroundStyle(Theme.soon) }
                    }
                } else {
                    HStack(spacing: 10) {
                        if s.applied == nil {
                            Button { AppsData.shared.edit(store) { e, m in try e.setApplied(s, true, model: m, today: store.today) } } label: { Label("Mark as applied", systemImage: "paperplane") }
                                .buttonStyle(.borderedProminent).tint(Theme.accent)
                        } else {
                            Label("Applied \(SiteFacts.fmtDate(s.applied!))", systemImage: "paperplane.fill").foregroundStyle(Theme.planned).font(.subheadline.weight(.semibold))
                        }
                        if let d = s.deadline {
                            let days = Days.between(store.today, d)
                            Chip(text: days < 0 ? "deadline passed" : days == 0 ? "due today" : "\(days) days to the deadline", color: days < 7 ? Theme.late : days < 21 ? Theme.soon : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func statusLine(_ s: School) -> String {
        if s.dropped { return "Removed from your list" }
        if !s.applying { return "Considering" + (s.nextDeadline.map { " · next deadline \(SiteFacts.fmtDate($0))" } ?? "") }
        var bits = ["Applying"]
        if let r = s.round { bits.append(Apps.roundLong[r] ?? s.roundLabel(r)) }
        if let d = s.deadline { bits.append("due \(SiteFacts.fmtDate(d))") }
        if let i = s.internalDate { bits.append("own date \(Apps.short(i))") }
        return bits.joined(separator: " · ")
    }

    private func ask(_ s: School, _ k: String, _ m: AppsModel) {
        if Apps.edConflict(m.schools, schoolId: s.id, round: k) != nil { confirmStart = k } else { start(s, k) }
    }
    private func start(_ s: School, _ k: String) {
        AppsData.shared.edit(store) { e, m in try e.startApplying(s, round: k, model: m, snapshot: store.snapshot, today: store.today) }
    }

    private func moreMenu(_ s: School, _ m: AppsModel, _ r: UniRow?) -> some View {
        Menu {
            Section {
                Button { checking = true } label: { Label("Check the school's site", systemImage: "checkmark.seal") }
                Button { AppsData.shared.research(s, store: store) } label: { Label("Research with Claude", systemImage: "sparkles") }
                    .disabled(AppsData.shared.researching[s.id] != nil)
                if AppsData.askHandler != nil {
                    Button { AppsData.askHandler?("\(s.name)'s page", m.claudeContext(current: s, notesExist: { DataFolder.text(store.folder, $0.folder + "/notes.md") != nil })) } label: { Label("Ask Claude", systemImage: "bubble.left.and.text.bubble.right") }
                }
            }
            Section {
                if s.applying {
                    Menu("Round") {
                        ForEach(Apps.roundKeys, id: \.self) { k in
                            Button { AppsData.shared.edit(store) { e, _ in try e.setRound(s, k) } } label: { if s.round == k { Label(Apps.roundLong[k] ?? k, systemImage: "checkmark") } else { Text(Apps.roundLong[k] ?? k) } }
                        }
                    }
                    Button { dateText = s.internalDate ?? ""; settingDate = true } label: { Label("Your own date", systemImage: "calendar") }
                    if s.applied != nil {
                        Button { AppsData.shared.edit(store) { e, m in try e.setApplied(s, false, model: m, today: store.today) } } label: { Label("Not applied yet", systemImage: "arrow.uturn.backward") }
                    }
                    Button { AppsData.shared.edit(store) { e, m in try e.moveBack(s, model: m) } } label: { Label("Back to Considering", systemImage: "arrow.down.to.line") }
                }
                Button { go(.workstream(s.id)) } label: { Label("Its tasks and files", systemImage: "folder") }
                if let u = r?.u?.url, let url = URL(string: u) { Button { openURL(url) } label: { Label("Website", systemImage: "safari") } }
            }
            if let r, r.u == nil, AppsData.shared.db != nil {
                let cands = Unis.link(s, AppsData.shared.db).cands
                if !cands.isEmpty {
                    Menu("Link to the database") {
                        ForEach(cands) { u in Button(u.full) { AppsData.shared.edit(store) { e, _ in try e.link(s, to: u) } } }
                    }
                }
            }
            if !s.dropped {
                Section {
                    Button(role: .destructive) { AppsData.shared.edit(store) { e, m in try e.remove(s, model: m) } } label: { Label("Remove from the list", systemImage: "minus.circle") }
                }
            }
        } label: { Label("More", systemImage: "ellipsis.circle") }
        .disabled(store.snapshot.readOnlyReason != nil)
        .accessibilityIdentifier("school-more")
    }

    // MARK: the work: tasks, checklist, essays

    @ViewBuilder
    private func work(_ s: School, _ m: AppsModel) -> some View {
        let snap = store.snapshot
        let tasks = snap.order.compactMap { snap.tasks[$0] }.filter { $0.workstream == s.id && !$0.done && !$0.someday }
        AppsCard(title: "Tasks", count: tasks.count, action: ("Add", { store.capture = .init(workstream: s.id, parent: nil, plan: nil) })) {
            if tasks.isEmpty { Text("Nothing open.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(tasks.prefix(12)) { t in TaskRow(task: t, showWorkstream: false, showCrumb: false, compact: true) }
            if tasks.count > 12 { Button("All \(tasks.count) tasks") { go(.workstream(s.id)) }.font(.subheadline) }
        }

        if s.applying || !s.requirements.isEmpty {
            let done = s.requirements.filter { $0.done || $0.na }.count
            AppsCard(title: "Checklist", count: nil, trailing: s.requirements.isEmpty ? nil : "\(done) of \(s.requirements.count)", action: ("Add", { addingReq = true })) {
                ForEach(Array(s.requirements.enumerated()), id: \.offset) { i, q in
                    HStack(alignment: .top, spacing: 10) {
                        Button { AppsData.shared.edit(store) { e, _ in try e.toggleRequirement(s, at: i) } } label: {
                            Image(systemName: q.done ? "checkmark.circle.fill" : q.na ? "minus.circle" : "circle")
                                .foregroundStyle(q.done ? Theme.accent : .secondary).imageScale(.large)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(q.t).strikethrough(q.na).foregroundStyle(q.na ? .secondary : .primary)
                            if !q.note.isEmpty { Text(q.note).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                        if !q.src.isEmpty, let u = URL(string: q.src) { Button { openURL(u) } label: { Image(systemName: "link").font(.caption) }.buttonStyle(.plain).foregroundStyle(.secondary) }
                    }
                    .contextMenu {
                        Button { AppsData.shared.edit(store) { e, _ in try e.toggleRequirement(s, at: i, na: true) } } label: { Label(q.na ? "Needed after all" : "Not needed", systemImage: "minus.circle") }
                        Button(role: .destructive) { AppsData.shared.edit(store) { e, _ in try e.removeRequirement(s, at: i) } } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
        }

        AppsCard(title: "Essays", count: s.essays.count, action: ("Add a prompt", { addingEssay = true })) {
            if s.essays.isEmpty {
                Text(s.research.prompts.isEmpty ? "No prompts yet. Add the ones the school asks." : "\(s.research.prompts.count) prompt\(s.research.prompts.count == 1 ? "" : "s") in the research; they become essays when you start applying.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(s.essays) { e in
                EssayLine(essay: { var x = e; x.path = s.path; return x }(), model: m, master: false, cut: "", go: go)
                    .contextMenu {
                        Button(role: .destructive) { AppsData.shared.edit(store) { ed, _ in try ed.removeEssay(e, of: s) } } label: { Label("Remove this prompt", systemImage: "trash") }
                    }
            }
            if !s.essays.isEmpty && !s.applying { Text("Essays show on the board once you apply.").font(.caption).foregroundStyle(.secondary) }
        }

        let advice = CounsellorAdvice.about(s, store: store)
        if !advice.isEmpty {
            AppsCard(title: "Counsellor", count: nil) {
                ForEach(advice, id: \.line) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.line).font(.subheadline)
                        Text("\(a.who) · \(SiteFacts.fmtDate(a.date))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: the facts: About, numbers, notes, sources

    @ViewBuilder
    private func facts(_ s: School, _ m: AppsModel, _ r: UniRow?) -> some View {
        AboutCard(school: s)

        AppsCard(title: "Rounds and numbers", count: nil) {
            ForEach(Apps.roundKeys, id: \.self) { k in
                let info = Apps.roundInfo(s, r?.u, k)
                Button { editingRound = k } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.roundLabel(k)).font(.subheadline.weight(.semibold)).frame(width: 44, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(info?.dl.map { SiteFacts.fmtDate($0) } ?? "No deadline").font(.subheadline).foregroundStyle(info?.dl == nil ? .secondary : .primary)
                            if let w = info?.whence, !w.isEmpty { Text(w).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer()
                        Text(info?.rate.map(pct) ?? "–").font(.subheadline.monospacedDigit())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            ForEach([("acc", "Admit rate"), ("usn", "US News"), ("usne", "US News Engineering"), ("qs", "QS World")], id: \.0) { f in
                Button { editingOwn = f.0; ownText = own(s, f.0).map { JSONValue.format($0) } ?? "" } label: {
                    HStack {
                        Text(f.1).font(.subheadline)
                        Spacer()
                        Text(figure(s, r, f.0)).font(.subheadline.monospacedDigit()).foregroundStyle(own(s, f.0) != nil ? .primary : .secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let c = s.research.checked { Text("Site checked \(SiteFacts.fmtDate(c))\(s.research.checkedLegacy ? " (old file)" : "")").font(.caption).foregroundStyle(.secondary) }
        }

        AppsCard(title: "Notes", count: nil, action: (notes == nil ? "Add" : "Edit", { editingNotes = notes ?? "" })) {
            if let n = notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { NoteText(text: n) }
            else { Text("Nothing yet: notes.md in \(s.folder).").font(.subheadline).foregroundStyle(.secondary) }
        }

        AppsCard(title: "Sources", count: s.research.sources.count, action: ("Add", { addingSource = true })) {
            if s.research.sources.isEmpty { Text("No links yet.").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(s.research.sources, id: \.0) { k, v in
                HStack {
                    Text(k).font(.subheadline)
                    Spacer()
                    if let u = URL(string: v) { Button(SiteFacts.hostOf(v).isEmpty ? v : SiteFacts.hostOf(v)) { openURL(u) }.font(.caption).lineLimit(1) }
                }
                .contextMenu { Button(role: .destructive) { AppsData.shared.edit(store) { e, _ in try e.removeSource(s, key: k) } } label: { Label("Remove", systemImage: "trash") } }
            }
        }
    }

    private func own(_ s: School, _ f: String) -> Double? {
        switch f { case "acc": return s.research.acc; case "usn": return s.research.usn; case "usne": return s.research.usne; default: return s.research.qs }
    }
    private func figure(_ s: School, _ r: UniRow?, _ f: String) -> String {
        if let v = own(s, f) { return f == "acc" ? pct(v) : "#" + JSONValue.format(v) }
        guard let r else { return "–" }
        switch f {
        case "acc": return Unis.accOf(r).map(pct) ?? "–"
        case "usn": return Unis.rankText(r, "usnNational") ?? "–"
        case "usne": return Unis.rankText(r, Unis.anyEng) ?? "–"
        default: return Unis.rankText(r, "qs") ?? "–"
        }
    }
}

struct RoundKey: Identifiable { let k: String; var id: String { k } }

// MARK: - a card

/// A titled card, the school page's and the tracker's unit.
struct AppsCard<Content: View>: View {
    var title: String?
    var count: Int?
    var trailing: String?
    var action: (String, () -> Void)?
    @ViewBuilder var content: Content

    init(title: String? = nil, count: Int? = nil, trailing: String? = nil, action: (String, () -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.count = count; self.trailing = trailing; self.action = action; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    SectionTitle(title: title, count: count == 0 ? nil : count)
                    if let trailing { Text(trailing).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let a = action { Button(a.0, action: a.1).font(.subheadline) }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - About: Claude's research

struct AboutCard: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.openURL) private var openURL
    let school: School
    @State private var more = false

    var body: some View {
        let data = AppsData.shared
        let p = SchoolProfile(school.rawResearch["profile"])
        let busy = data.researching[school.id]
        AppsCard(title: "About", count: nil, action: busy == nil ? (p == nil ? "Research with Claude" : "Research again", { data.research(school, store: store) }) : nil) {
            if let busy { HStack(spacing: 8) { ProgressView(); Text(busy).font(.subheadline).foregroundStyle(.secondary) } }
            if let n = data.researchNote[school.id] { Text(n).font(.caption).foregroundStyle(.secondary) }
            if let p {
                if !p.brief.isEmpty { Text(p.brief).font(.subheadline) }
                if !p.city.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(p.city.name.isEmpty ? "The city" : p.city.name).font(.subheadline.weight(.semibold))
                        if !p.city.about.isEmpty { Text(p.city.about).font(.subheadline) }
                        let bits = [p.city.metro, p.city.population.isEmpty ? "" : "population \(p.city.population)", p.city.weather, p.city.cost.isEmpty ? "" : "cost of living \(p.city.cost)"].filter { !$0.isEmpty }
                        if !bits.isEmpty { Text(bits.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if !p.concerns.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Concerns").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.soon)
                        ForEach(p.concerns, id: \.l) { c in
                            Text("**\(c.l)**\(c.v.isEmpty ? "" : ": \(c.v)")").font(.subheadline)
                        }
                    }
                }
                if more || UIDevice.current.userInterfaceIdiom == .pad {
                    list("Opportunities", p.opportunities)
                    list("Things to do", p.todo)
                    if let g = p.greek, let v = SchoolProfile.greekOf(g) {
                        let lv = SchoolProfile.greekLevel(v)
                        HStack {
                            Text("Greek life").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(pct(v) + (g.of.isEmpty ? "" : " (\(g.of))")).font(.subheadline).foregroundStyle(lv < 0 ? Theme.soon : lv > 0 ? Theme.planned : .primary)
                        }
                    }
                    ForEach(p.extras, id: \.l) { x in
                        VStack(alignment: .leading, spacing: 1) { Text(x.l).font(.caption.weight(.semibold)).foregroundStyle(.secondary); Text(x.v).font(.subheadline) }
                    }
                    if !p.sources.isEmpty {
                        Text("From " + p.sources.map { SiteFacts.hostOf($0) }.filter { !$0.isEmpty }.prefix(6).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button("More about \(school.short)") { more = true }.font(.subheadline)
                }
                if let c = p.checked { Text("Researched \(SiteFacts.fmtDate(c))\(p.v < SchoolProfile.version ? ": research again for the concerns" : "")").font(.caption).foregroundStyle(.secondary) }
            } else if busy == nil {
                Text("Claude can look up what the school is like for an engineering student: each round's admit rate, the city, opportunities, Greek life and the concerns, every figure with its page.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func list(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                ForEach(items, id: \.self) { Text("• " + $0).font(.subheadline) }
            }
        }
    }
}

// MARK: - a round's deadline and rate

struct RoundSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let school: School
    let k: String
    @State private var dl = ""
    @State private var rate = ""
    @State private var label = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Deadline: 1 Nov or 2026-11-01", text: $dl)
                    TextField("Admit rate %", text: $rate).keyboardType(.decimalPad)
                    TextField("Name on the school's site (REA, EA I…)", text: $label)
                } footer: { Text("A rate typed here is yours: Claude's research never replaces it. Leave a field empty to clear it.") }
            }
            .navigationTitle(Apps.roundLong[k] ?? k)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                let r = school.research.rounds[k]
                dl = r?.dl ?? ""; rate = r?.rate.map { JSONValue.format($0) } ?? ""; label = r?.label ?? ""
            }
        }
    }

    private func save() {
        let d = dl.trimmingCharacters(in: .whitespaces)
        let iso = d.isEmpty ? nil : Apps.parseDateInput(d, today: store.today)
        if !d.isEmpty && iso == nil { store.problem = "\"\(d)\" is not a date Nexus can read."; return }
        let old = school.research.rounds[k]
        let rv = Double(rate.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: ""))
        let rateChange: Double?? = rv == old?.rate ? .none : .some(rv)
        let l = label.trimmingCharacters(in: .whitespaces)
        AppsData.shared.edit(store) { e, _ in
            try e.setRound(school, k, dl: .some(iso), rate: rateChange, label: .some(l.isEmpty ? nil : l))
        }
        dismiss()
    }
}

// MARK: - a prompt of your own

struct AddEssaySheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let school: School
    @State private var title = ""
    @State private var lim = ""
    @State private var unit = "words"

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("The prompt", text: $title, axis: .vertical).lineLimit(2...6) }
                Section {
                    TextField("Limit", text: $lim).keyboardType(.numberPad)
                    Picker("Counted in", selection: $unit) { Text("Words").tag("words"); Text("Characters").tag("characters") }
                } footer: { Text("Its kind (why us, community…) is guessed from the words; change it on the board.") }
            }
            .navigationTitle("Add a prompt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let t = title, l = Int(lim), u = unit
                        AppsData.shared.edit(store) { e, _ in try e.addEssay(school, title: t, lim: l, unit: u) }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - the counsellor's words

/// Lines of the meeting notes (a person's dated notes, "2026-10-01 meeting.md") that name the school, newest first.
enum CounsellorAdvice {
    struct Line { var line, who, date: String }

    @MainActor
    static func about(_ s: School, store: NexusStore) -> [Line] {
        let names = [s.short, s.name.replacingOccurrences(of: #"\s*\(.*\)\s*$"#, with: "", options: .regularExpression)].filter { $0.count > 2 }
        guard !names.isEmpty else { return [] }
        let pattern = "\\b(" + names.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        var out: [Line] = []
        let fm = FileManager.default
        for w in store.snapshot.workstreams.values where w.kind == "person" {
            let dir = store.folder.appendingPathComponent(w.folder)
            guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for f in files where f.lowercased().hasSuffix(".md") && f.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil {
                guard let text = DataFolder.text(store.folder, w.folder + "/" + f) else { continue }
                let date = String(f.prefix(10))
                for raw in text.components(separatedBy: "\n") {
                    if raw.trimmingCharacters(in: .whitespaces).hasPrefix("|") { continue }
                    let line = raw.replacingOccurrences(of: #"^[\s>*\-+#\d.]+"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: #"\[\[([^\]|]+\|)?([^\]]+)\]\]"#, with: "$2", options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    if line.count > 12 && line.count < 400 && re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                        out.append(Line(line: line, who: w.name, date: date))
                    }
                }
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(8))
    }
}
