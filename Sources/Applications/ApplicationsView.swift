import SwiftUI
import NexusCore

/// Applications (the laptop's Applications tab): Tracker (the runway of dates, the essay board, the write order) and Research (every school
/// of the universities database and yours). The iPad shows the tracker's parts side by side; the iPhone stacks them, with the less used
/// actions in menus.
struct ApplicationsView: View {
    @Environment(NexusStore.self) private var store
    var go: (Screen) -> Void
    @AppStorage("apps.tab") private var tab = "tracker"
    @State private var adding = false

    var body: some View {
        let data = AppsData.shared
        let m = data.model(store)
        Group {
            if tab == "research" {
                ResearchView(go: go)
            } else {
                TrackerView(model: m, go: go)
            }
        }
        .navigationTitle("Applications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    Text("Tracker").tag("tracker")
                    Text("Research").tag("research")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .accessibilityIdentifier("apps-tab")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { adding = true } label: { Label("Add a school", systemImage: "plus") }
                    if AppsData.askHandler != nil {
                        Button { AppsData.askHandler?("your applications", m.claudeContext(current: nil, notesExist: { notesExist($0) })) } label: { Label("Ask Claude about your list", systemImage: "sparkles") }
                    }
                } label: { Label("More", systemImage: "ellipsis.circle") }
                .disabled(store.snapshot.readOnlyReason != nil)
            }
        }
        .sheet(isPresented: $adding) { AddSchoolSheet(go: go) }
        .task { data.loadDB() }
    }

    private func notesExist(_ s: School) -> Bool { DataFolder.text(store.folder, s.folder + "/notes.md") != nil }
}

// MARK: - the tracker

struct TrackerView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.horizontalSizeClass) private var size
    let model: AppsModel
    var go: (Screen) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CapLine(model: model, go: go)
                if model.applying.isEmpty {
                    EmptyNote(title: "No school is Applying yet",
                              detail: "Open a school from Research or the sidebar and choose Start applying. Its essays, checklist and deadline then show here.",
                              icon: "graduationcap")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                } else {
                    RunwayStrip(model: model, go: go)
                    if size == .regular {
                        HStack(alignment: .top, spacing: 18) {
                            EssayBoard(model: model, go: go).frame(maxWidth: .infinity, alignment: .topLeading)
                            WriteOrder(model: model).frame(width: 360, alignment: .topLeading)
                        }
                    } else {
                        EssayBoard(model: model, go: go)
                        WriteOrder(model: model)
                    }
                }
            }
            .padding(size == .regular ? 20 : 14)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .refreshable { store.reload() }
    }
}

/// "3 of 10 applying" and each applying school as a chip that opens its page.
struct CapLine: View {
    @Environment(NexusStore.self) private var store
    let model: AppsModel
    var go: (Screen) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.cap.text).font(.nx(.headline))
                if model.cap.over { Chip(text: "over the cap", icon: "exclamationmark.triangle", color: Theme.late, strong: true) }
                else if model.cap.atMax { Chip(text: "at the cap", color: Theme.soon) }
                Spacer()
                Text("\(model.considering.count) considering").font(.nx(.subheadline)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.applying) { s in
                        Button { go(.school(s.id)) } label: {
                            HStack(spacing: 6) {
                                Circle().fill(store.schoolColor(s.id)).frame(width: 8, height: 8)
                                Text(s.short).font(.nx(.subheadline, .medium))
                                if let r = s.round { Text(s.roundLabel(r)).font(.nx(.caption)).foregroundStyle(.secondary) }
                                if s.applied != nil { Image(systemName: "paperplane.fill").font(.nx(.caption2)).foregroundStyle(Theme.planned) }
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("apps-school-\(s.id)")
                    }
                }
            }
        }
    }
}

// MARK: the runway

/// The gates: each date where something is due (a school's own date is soft), its days left, the hours of work before it and its schools.
struct RunwayStrip: View {
    @Environment(NexusStore.self) private var store
    let model: AppsModel
    var go: (Screen) -> Void
    @State private var open: Gate?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Runway", count: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(model.runway.gates) { g in gateCard(g) }
                    if let u = model.runway.undated, !u.items.isEmpty { gateCard(u) }
                }
                .padding(.vertical, 2)
            }
            Text("\(Apps.dur(model.runway.openHours)) of open work").font(.nx(.caption)).foregroundStyle(.secondary)
        }
        .sheet(item: $open) { g in GateSheet(gate: g, model: model, go: go) }
    }

    private func gateCard(_ g: Gate) -> some View {
        let late = (g.date ?? "9999") < model.today
        let tight = g.date != nil && Double(g.days) * 1.5 < g.hours
        return Button { open = g } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(g.date.map { Apps.short($0) } ?? "No date yet").font(.nx(.headline))
                    if g.binding { Image(systemName: "lock.fill").font(.nx(.caption2)).foregroundStyle(Theme.late) }
                }
                if g.date != nil {
                    Text(late ? "passed" : g.days == 0 ? "today" : "\(g.days) day\(g.days == 1 ? "" : "s")")
                        .font(.nx(.caption)).foregroundStyle(late ? Theme.late : tight ? Theme.soon : .secondary)
                }
                Text(g.label.isEmpty ? (g.soft ? "Your own date" : "") : g.label).font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 4) {
                    Chip(text: "\(g.items.count) to do", color: .secondary)
                    if g.hours > 0 { Chip(text: Apps.dur(g.hours), color: tight ? Theme.soon : .secondary) }
                }
            }
            .frame(width: 150, alignment: .leading)
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(g.soft ? Color.secondary.opacity(0.35) : .clear, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }
}

/// A gate opened: its work, each a task you can tick or open.
struct GateSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let gate: Gate
    let model: AppsModel
    var go: (Screen) -> Void

    var body: some View {
        NavigationStack {
            List {
                if !gate.deadlineOf.isEmpty || !gate.internalOf.isEmpty {
                    Section("Schools") {
                        ForEach(gate.deadlineOf + gate.internalOf.filter { !gate.deadlineOf.contains($0) }, id: \.self) { id in
                            if let s = model.school(id) {
                                Button { dismiss(); go(.school(id)) } label: {
                                    HStack {
                                        Text(s.name)
                                        Spacer()
                                        Text(gate.deadlineOf.contains(id) ? "\(s.round.map { s.roundLabel($0) } ?? "") deadline" : "own date").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Work") {
                    if gate.items.isEmpty { Text("Nothing open.").foregroundStyle(.secondary) }
                    ForEach(gate.items) { it in
                        if let t = store.snapshot.tasks[it.id] { TaskRow(task: t) } else { Text(it.title) }
                    }
                }
            }
            .navigationTitle(gate.date.map { SiteFacts.fmtDate($0) } ?? "No date yet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: the essay board

/// One row per kind of essay: the longest is the master you write first, the others are cut from it.
struct EssayBoard: View {
    @Environment(NexusStore.self) private var store
    let model: AppsModel
    var go: (Screen) -> Void
    @State private var picking: Apps.AppSystem?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Essays", count: model.essays.count)
                Spacer()
                ForEach(Apps.systems.filter { sys in model.applying.contains { $0.system == sys.id } }, id: \.id) { sys in
                    Button { picking = sys } label: { Label("\(sys.short) questions", systemImage: "checklist") }.font(.nx(.subheadline))
                }
            }
            if model.board.isEmpty {
                Text("No essays yet. A school's prompts become essays when it starts applying; add your own on its page.").font(.nx(.subheadline)).foregroundStyle(.secondary)
            }
            ForEach(model.board) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.fam.name).font(.nx(.subheadline, .semibold))
                        Text("\(row.count) essay\(row.count == 1 ? "" : "s")").font(.nx(.caption)).foregroundStyle(.secondary)
                        Spacer()
                    }
                    EssayLine(essay: row.master, model: model, master: true, cut: "", go: go)
                    ForEach(row.ladder, id: \.essay.id) { r in EssayLine(essay: r.essay, model: model, master: false, cut: r.cut, go: go) }
                    if !row.fam.tip.isEmpty { Text(row.fam.tip).font(.nx(.caption)).foregroundStyle(.secondary) }
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .sheet(item: $picking) { sys in SystemPicksSheet(system: sys, model: model) }
    }
}

/// An essay: its school, title, limit and Google Doc; the menu links a doc, changes its kind or marks it picked.
struct EssayLine: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.openURL) private var openURL
    let essay: Essay
    let model: AppsModel
    var master: Bool
    var cut: String
    var go: (Screen) -> Void
    @State private var linking = false
    @State private var docText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(store.schoolColor(essay.general ? "common-app" : essay.school)).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(essay.general ? essay.generalName : model.school(essay.school)?.short ?? essay.school).font(.nx(.caption, .semibold)).foregroundStyle(.secondary)
                    if master { Chip(text: "master", color: Theme.accent, strong: true) }
                    if !cut.isEmpty { Chip(text: cut, color: .secondary) }
                    if !essay.limitText.isEmpty { Text(essay.limitText).font(.nx(.caption)).foregroundStyle(.secondary) }
                }
                Text(essay.title).font(.nx(.subheadline)).lineLimit(3)
            }
            Spacer(minLength: 0)
            if !essay.doc.isEmpty, let u = URL(string: essay.doc) {
                Button { openURL(u) } label: { Image(systemName: "doc.text").foregroundStyle(Theme.accent) }.buttonStyle(.plain)
                    .accessibilityLabel("Open its Google Doc")
            }
            Menu {
                if !essay.general { Button { go(.school(essay.school)) } label: { Label("Open the school", systemImage: "building.columns") } }
                Button { docText = essay.doc; linking = true } label: { Label(essay.doc.isEmpty ? "Link a Google Doc" : "Change the doc link", systemImage: "link") }
                if !essay.doc.isEmpty {
                    Button(role: .destructive) { change("Doc link removed") { $0.doc = ""; $0.docTitle = "" } } label: { Label("Remove the doc link", systemImage: "link.badge.plus") }
                }
                Menu("Kind of essay") {
                    ForEach(Apps.families, id: \.id) { f in
                        Button { change("\(essay.title): \(f.name)") { $0.fam = f.id } } label: { if f.id == essay.fam { Label(f.name, systemImage: "checkmark") } else { Text(f.name) } }
                    }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24) }
            .disabled(store.snapshot.readOnlyReason != nil)
        }
        .alert("Google Doc link", isPresented: $linking) {
            TextField("https://docs.google.com/…", text: $docText).textInputAutocapitalization(.never).keyboardType(.URL)
            Button("Save") {
                let u = docText.trimmingCharacters(in: .whitespaces)
                change("Doc linked: \(essay.title)") { $0.doc = u }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Only the link is kept, never anything from the doc.") }
    }

    private func change(_ message: String, _ f: @escaping (inout Essay) -> Void) {
        AppsData.shared.edit(store) { e, m in try e.editEssay(essay, model: m, message: message, f) }
    }
}

/// A system's questions (the UC's Personal Insight Questions): pick the ones you answer.
struct SystemPicksSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let system: Apps.AppSystem
    let model: AppsModel
    @State private var picked: Set<String> = []

    var body: some View {
        let es = Apps.systemEssays[system.id]
        NavigationStack {
            List {
                if let es {
                    Section {
                        ForEach(es.list, id: \.id) { q in
                            Button { if picked.contains(q.id) { picked.remove(q.id) } else { picked.insert(q.id) } } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: picked.contains(q.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(picked.contains(q.id) ? Theme.accent : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(q.short).font(.nx(.subheadline, .semibold))
                                        Text(q.title).font(.nx(.caption)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("Pick \(es.pick) of \(es.list.count), \(es.lim) \(es.unit) each. They are one set for every \(system.short) campus on your list.")
                    }
                }
            }
            .navigationTitle(es?.name ?? system.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let order = es?.list.map(\.id).filter { picked.contains($0) } ?? []
                        AppsData.shared.edit(store) { e, m in try e.setSystemPicks(system.id, order, model: m) }
                        dismiss()
                    }
                    .disabled(picked.count > (es?.pick ?? 99))
                }
            }
            .onAppear { picked = Set(Apps.systemPicked(model.schools, system.id)) }
        }
    }
}

// MARK: the write order

/// The open work in the order to do it (the soonest date first; a master before its cuts), with a suggested pace. Accept plans the days.
struct WriteOrder: View {
    @Environment(NexusStore.self) private var store
    let model: AppsModel
    @State private var hours: Double?
    @State private var showAll = false

    var body: some View {
        let sg = model.suggestion(hoursPerDay: hours)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Write order", count: model.ordered.count)
            if model.ordered.isEmpty {
                Text("No open work with a date or an estimate.").font(.nx(.subheadline)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Stepper(value: Binding(get: { sg.hoursPerDay }, set: { hours = max(0.25, $0) }), in: 0.25...12, step: 0.25) {
                            Text("\(Apps.dur(sg.hoursPerDay)) a day").font(.nx(.subheadline, .semibold))
                        }
                    }
                    if let p = model.pace {
                        Text("To finish what is due \(Apps.short(p.forDate)) you need about \(Apps.dur(p.hoursPerDay)) a day.").font(.nx(.caption)).foregroundStyle(.secondary)
                    }
                    let days = sg.schedule.days
                    if let first = days.first, let last = days.last {
                        Text("\(sg.schedule.byItem.count) pieces over \(days.count) day\(days.count == 1 ? "" : "s"), \(Apps.short(first)) to \(Apps.short(last)).\(sg.schedule.late.isEmpty ? "" : " \(sg.schedule.late.count) would finish late.")")
                            .font(.nx(.caption)).foregroundStyle(sg.schedule.late.isEmpty ? Color.secondary : Theme.soon)
                    }
                    Button {
                        AppsData.shared.edit(store) { e, m in try e.acceptSchedule(m, schedule: sg.schedule, hoursPerDay: sg.hoursPerDay, snapshot: store.snapshot) }
                    } label: { Label("Accept: plan these days", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(sg.schedule.byItem.isEmpty || store.snapshot.readOnlyReason != nil)
                }
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

                let list = showAll ? model.ordered : Array(model.ordered.prefix(8))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, it in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)").font(.nx(.caption).monospacedDigit()).foregroundStyle(.secondary).frame(width: 18, alignment: .trailing)
                            Circle().fill(store.schoolColor(it.school)).frame(width: 8, height: 8).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(it.title).font(.nx(.subheadline)).lineLimit(2)
                                Text(it.why).font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                if let d = it.due { Text(Apps.short(d)).font(.nx(.caption)).foregroundStyle(it.overdue ? Theme.late : .secondary) }
                                if it.hours > 0 { Text(Apps.dur(it.hours)).font(.nx(.caption)).foregroundStyle(.secondary) }
                            }
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .onTapGesture { if store.snapshot.tasks[it.id] != nil { store.openTaskId = it.id } }
                        if i < list.count - 1 { Divider().padding(.leading, 46) }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                if model.ordered.count > 8 {
                    Button(showAll ? "Show fewer" : "Show all \(model.ordered.count)") { showAll.toggle() }.font(.nx(.subheadline))
                }
            }
        }
    }
}
