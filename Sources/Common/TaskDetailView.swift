import SwiftUI
import NexusCore

/// The task panel, as the new laptop app has it (switch-over step 4b, Nov 21 2026; nexus `desktop/src/screens/TaskPanel.tsx`): the
/// subject (a menu that moves it), the title with its tick and ★, then Deadline, Planned, Estimate, Repeats, Waiting on, Tags and
/// Someday as rows, the subtasks as a checklist, the time tracked, the notes, and the file with Delete. Dates are typed as capture
/// reads them ("fri", "12 nov", "thu 4pm"), or picked. Every change is saved at once (Undo on the bar for each).
struct TaskDetailView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let taskId: String

    @State private var title = ""
    @FocusState private var titleFocused: Bool
    @State private var dueText = ""
    @State private var planText = ""
    @State private var badDate: String?
    @State private var waitingText = ""
    @State private var tagText = ""
    @State private var noteText = ""
    @State private var sure = false
    @State private var pickDue = false
    @FocusState private var focus: Field?

    private enum Field { case waiting, note }
    static let estimates = ["15m", "30m", "45m", "1h", "1h30m", "2h", "3h"]

    var body: some View {
        NavigationStack {
            if let t = store.task(taskId) {
                panel(t)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { commitTitle(t); commitFields(t); dismiss() } }
                        // the laptop's "drag a task onto Claude": the conversation, told which task this is
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                commitTitle(t); commitFields(t)
                                let looking = "the task “\(t.text)” (id \(t.id) in \(t.file))"
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + (Device.isPhone ? 0.45 : 0.1)) { ClaudeChatSession.open(looking: looking) }
                            } label: {
                                Label("Ask Claude", systemImage: "sparkles")
                            }
                            .accessibilityIdentifier("task-ask-claude")
                        }
                    }
                    .onAppear { title = t.title; fill(t) }
                    .onChange(of: t.title) { _, new in if !titleFocused { title = new } }
                    .onChange(of: store.snapshot.loadedAt) { _, _ in if focus == nil, let now = store.task(taskId) { fill(now) } }
                    .onChange(of: focus) { old, _ in if let old, let now = store.task(taskId) { commit(old, now) } }
                    .onChange(of: titleFocused) { _, now in if !now, let cur = store.task(taskId) { commitTitle(cur) } }
            } else {
                EmptyNote(title: "This task is gone", detail: "It was removed or moved since.", icon: "questionmark.circle")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            }
        }
    }

    // MARK: the panel

    private func panel(_ t: NexusTask) -> some View {
        let editable = store.canEdit(t)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !editable {
                    Label(t.hasId ? (store.snapshot.readOnlyReason ?? "\(t.file) does not parse, so it is read-only here.")
                                  : "This task has no id yet. Open the folder in Nexus on the laptop once and it gets one; then it can be edited here.",
                          systemImage: "lock")
                        .font(.nx(.callout)).foregroundStyle(Kit.muted)
                }
                head(t, editable: editable)
                VStack(spacing: 0) {
                    row("Deadline", icon: "calendar") { deadline(t) }
                    row("Planned", icon: "calendar.day.timeline.left") { planned(t) }
                    row("Estimate", icon: "clock") { estimate(t) }
                    row("Repeats", icon: "arrow.clockwise") { repeats(t) }
                    row("Waiting on", icon: "questionmark.circle") { waiting(t) }
                    row("Tags", icon: "tag") { tagsField(t) }
                    row("Someday", icon: "archivebox") { someday(t) }
                }
                .disabled(!editable)
                let files = store.files(of: t)
                if !files.isEmpty {
                    row("Files", icon: "paperclip") {
                        HStack(spacing: 8) {
                            TaskFileChips(files: files)
                            if let pdf = files.first(where: { $0.kind == "pdf" }) {
                                Button { commitTitle(t); commitFields(t); store.writeOn(pdf: pdf.path) } label: {
                                    Label("Write on it", systemImage: "pencil.and.scribble")
                                }
                                .buttonStyle(KitButtonStyle(kind: .tone, small: true))
                                .accessibilityIdentifier("panel-write-on")
                            }
                        }
                    }
                }
                subtasks(t)
                VStack(alignment: .leading, spacing: 4) { TaskTimeSection(task: t, editable: editable) }
                    .font(.nx(.callout))
                notes(t, editable: editable)
                TaskActivitySection(task: t) // what happened to it (TaskActivitySection.swift)
                if let e = t.email {
                    Label(e.hasPrefix("gmail/") ? "From a Gmail message" : e.hasPrefix("outlook/") ? "From an Outlook message" : e, systemImage: "envelope")
                        .font(.nx(.footnote)).foregroundStyle(Kit.muted)
                }
                foot(t, editable: editable)
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Kit.page)
    }

    /// The subject (a menu that moves the task), the parents, the title with its tick and ★.
    private func head(_ t: NexusTask, editable: Bool) -> some View {
        let color = store.color(t)
        let parents = store.snapshot.ancestors(of: t)
        return VStack(alignment: .leading, spacing: 10) {
            Menu {
                Section("Move to") {
                    Button { store.moveTask(t, to: nil) } label: { Label("Inbox", systemImage: t.workstream == nil && t.parent == nil ? "checkmark" : "tray") }
                    ForEach(store.snapshot.groups) { g in
                        ForEach(store.snapshot.workstreams(in: g).filter { !$0.parked && !$0.finished }) { w in
                            Button { store.moveTask(t, to: w.id) } label: {
                                if w.id == t.workstream && t.parent == nil { Label(w.name, systemImage: "checkmark") } else { Text(w.name) }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    SubjectDot(color: color)
                    Text(store.workstreamName(t)).font(.nx(.subheadline, .medium)).foregroundStyle(color)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                }
                .padding(.horizontal, 12).frame(height: 30)
                .background(color.opacity(0.13), in: Capsule())
            }
            .disabled(!editable)
            .accessibilityIdentifier("panel-ws")
            if !parents.isEmpty {
                HStack(spacing: 4) {
                    ForEach(parents) { p in
                        Button(p.text + " ›") { store.open(p) }.font(.nx(.footnote)).foregroundStyle(Kit.muted).buttonStyle(.plain).lineLimit(1)
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                TickRing(task: t).padding(.top, 5)
                TextField("Title", text: $title, axis: .vertical)
                    .font(.nx(size: 24, .semibold, display: true))
                    .foregroundStyle(Kit.ink)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit { commitTitle(t) }
                    .disabled(!editable)
                    .accessibilityIdentifier("panel-title")
                Button { store.setKey(t, !t.key) } label: {
                    Image(systemName: t.key ? "star.fill" : "star").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(t.key ? Theme.key : Kit.faint)
                        .frame(width: 38, height: 38)
                        .background(t.key ? Theme.key.opacity(0.14) : Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!editable)
                .accessibilityLabel(t.key ? "Not a key date" : "Key date")
                .accessibilityIdentifier("panel-star")
            }
            if t.done, let d = t.doneOn {
                Text("Done " + TimeWords.dayName(String(d.prefix(10)), today: store.today)).font(.nx(.callout, .medium)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Kit.accentWash, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: the rows

    private func row<V: View>(_ label: String, icon: String, @ViewBuilder _ value: () -> V) -> some View {
        let narrow = Device.isPhone
        let l = Label(label, systemImage: icon).font(.nx(.subheadline)).foregroundStyle(Kit.muted).labelStyle(PanelLabel())
        return Group {
            if narrow {
                VStack(alignment: .leading, spacing: 8) { l; value() }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) { l.frame(width: 120, alignment: .leading); value().frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .padding(.vertical, 10)
    }

    private struct PanelLabel: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 8) { configuration.icon.font(.system(size: 13)).frame(width: 18); configuration.title }
        }
    }

    /// "Fri 27 Nov · in 6 days"
    private func inDays(_ iso: String) -> String {
        let n = Days.between(store.today, iso)
        let rel = n == 0 ? "today" : n == 1 ? "tomorrow" : n > 1 ? "in \(n) days" : "\(-n) day\(n == -1 ? "" : "s") late"
        return Days.label(iso) + " · " + rel
    }

    private func input(_ text: Binding<String>, _ placeholder: String, id: String, onSubmit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .font(.nx(.subheadline)).autocorrectionDisabled().textInputAutocapitalization(.never)
            .submitLabel(.done).onSubmit(onSubmit)
            .padding(.horizontal, 12).frame(height: 36)
            .background(badDate == id ? Theme.late.opacity(0.10) : Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier(id)
    }

    /// What a typed date means, as capture reads it: "x by <text>" for a deadline, "x on <text>" for a planned day.
    private func readDate(_ text: String, due: Bool) -> String? {
        let p = CaptureParse.parseLine("x \(due ? "by" : "on") \(text)", in: nil, today: store.today, commands: false)
        guard p.kind == .task else { return nil }
        return due ? p.facts.due : p.facts.plan.first
    }

    @ViewBuilder
    private func deadline(_ t: NexusTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let d = t.due {
                    Text(inDays(d)).font(.nx(.subheadline, .medium)).foregroundStyle(d < store.today ? Theme.late : Kit.ink)
                        .accessibilityIdentifier("panel-due")
                    Button { store.setDue(t, nil) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Kit.faint) }
                        .buttonStyle(.plain).accessibilityLabel("No deadline")
                }
                if t.due != nil {
                    DatePicker("Deadline", selection: Binding(get: { t.due.flatMap(Days.date) ?? Date() }, set: { store.setDue(t, Days.iso($0)) }),
                               displayedComponents: .date)
                        .labelsHidden()
                } else {
                    // no deadline shows as none, not as today's date in a picker
                    Text("None").font(.nx(.subheadline)).foregroundStyle(Kit.faint)
                    Button { withAnimation(Kit.snap) { pickDue.toggle() } } label: {
                        Label("Pick a day", systemImage: "calendar").font(.nx(.subheadline))
                    }
                    .buttonStyle(KitButtonStyle(kind: .tone, small: true))
                    .accessibilityIdentifier("panel-due-pick")
                }
            }
            if t.due == nil && pickDue {
                DatePicker("Deadline", selection: Binding(get: { Date() }, set: { store.setDue(t, Days.iso($0)); pickDue = false }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden().frame(maxWidth: 340)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            input($dueText, t.due == nil ? "fri, 12 nov, next week…" : "Change: fri, 12 nov…", id: "panel-due-in") {
                guard !dueText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                if let d = readDate(dueText, due: true) { store.setDue(t, d); dueText = ""; badDate = nil } else { badDate = "panel-due-in" }
            }
        }
    }

    private func planLabel(_ e: PlanEntry) -> String {
        let day = TimeWords.dayName(e.day, today: store.today)
        let d = day.prefix(1).uppercased() + day.dropFirst()
        return d + (e.time.flatMap { TodayPlan.clock($0) }.map { " " + TimeWords.clockAp($0) } ?? "")
    }

    @ViewBuilder
    private func planned(_ t: NexusTask) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowRow(spacing: 6) {
                ForEach(t.plan.sorted { $0.raw < $1.raw }, id: \.raw) { e in
                    HStack(spacing: 6) {
                        Text(planLabel(e)).foregroundStyle(e.day < store.today ? Kit.faint : Kit.ink)
                        Button { store.unplan(t, from: e.day) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Kit.faint) }
                            .buttonStyle(.plain).accessibilityLabel("Take off this day")
                    }
                    .font(.nx(.subheadline)).padding(.horizontal, 10).frame(height: 30)
                    .background(Kit.rests, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                if !t.plannedDays.contains(store.today) {
                    Button("Today") { store.plan(t, on: store.today) }.buttonStyle(KitButtonStyle(kind: .plain, small: true))
                }
                if !t.plannedDays.contains(Days.add(store.today, 1)) {
                    Button("Tomorrow") { store.plan(t, on: Days.add(store.today, 1)) }.buttonStyle(KitButtonStyle(kind: .plain, small: true))
                }
            }
            input($planText, "Add a day: today, thu 4pm…", id: "panel-plan-in") {
                guard !planText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                if let raw = readDate(planText, due: false), let e = PlanEntry(raw) {
                    store.setPlan(t, t.plan.filter { $0.day != e.day } + [e])
                    planText = ""; badDate = nil
                } else { badDate = "panel-plan-in" }
            }
        }
    }

    private static func minutes(_ s: String?) -> Int {
        var t = NexusTask(id: "x", title: "x", file: "", workstream: nil)
        t.est = s
        return TodayPlan.minutes(t)
    }

    private func option(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.nx(.subheadline, on ? .medium : .regular)).foregroundStyle(on ? Theme.accent : Kit.ink)
                .padding(.horizontal, 11).frame(height: 32)
                .background(on ? Kit.accentWash : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func estimate(_ t: NexusTask) -> some View {
        let cur = Self.minutes(t.est)
        return FlowRow(spacing: 4) {
            ForEach(Self.estimates, id: \.self) { e in
                let m = Self.minutes(e)
                option(TimeWords.dur(m), on: cur == m) { store.setEstimate(t, cur == m ? nil : e) }
            }
            if cur > 0 && !Self.estimates.contains(where: { Self.minutes($0) == cur }) {
                option(TimeWords.dur(cur), on: true) { store.setEstimate(t, nil) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel-est")
    }

    private func repeats(_ t: NexusTask) -> some View {
        let freq = t.every?.freq ?? "never"
        return VStack(alignment: .leading, spacing: 4) {
            FlowRow(spacing: 4) {
                ForEach([("never", "Never"), ("day", "Daily"), ("weekdays", "Weekdays"), ("week", "Weekly")], id: \.0) { k, l in
                    option(l, on: freq == k) {
                        store.setRepeat(t, k == "never" ? nil : NexusCore.Repeat(freq: k, on: k == "week" ? (t.every?.on ?? []) : [], until: t.every?.until))
                    }
                }
            }
            if let r = t.every { Text(r.text).font(.nx(.footnote)).foregroundStyle(Kit.faint) }
            else if let raw = t.everyRaw { Text("As written: \(raw)").font(.nx(.footnote)).foregroundStyle(Kit.faint) }
        }
    }

    private func waiting(_ t: NexusTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Nobody. Type a name", text: $waitingText)
                .font(.nx(.subheadline)).focused($focus, equals: .waiting).submitLabel(.done).onSubmit { commit(.waiting, t) }
                .padding(.horizontal, 12).frame(height: 36)
                .background(Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("panel-wait")
            if let s = t.waitingSince { Text("since \(Days.label(s))").font(.nx(.footnote)).foregroundStyle(Kit.faint) }
        }
    }

    private func tagsField(_ t: NexusTask) -> some View {
        FlowRow(spacing: 6) {
            ForEach(t.tags, id: \.self) { g in
                HStack(spacing: 6) {
                    Text("#" + g)
                    Button { store.setTags(t, t.tags.filter { $0 != g }) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Kit.faint) }
                        .buttonStyle(.plain).accessibilityLabel("Remove \(g)")
                }
                .font(.nx(.subheadline)).padding(.horizontal, 10).frame(height: 30)
                .background(Kit.rests, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            TextField("+ tag", text: $tagText)
                .font(.nx(.subheadline)).autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.done)
                .onSubmit {
                    let g = tagText.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).split(separator: " ").joined(separator: "-")
                    tagText = ""
                    if !g.isEmpty && !t.tags.contains(g) { store.setTags(t, t.tags + [g]) }
                }
                .padding(.horizontal, 10).frame(width: 120, height: 30)
                .background(Kit.rests, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityIdentifier("panel-tag")
        }
    }

    private func someday(_ t: NexusTask) -> some View {
        HStack(spacing: 10) {
            Toggle("Someday", isOn: Binding(get: { t.ownSomeday }, set: { store.setSomeday(t, $0) }))
                .labelsHidden().tint(Theme.accent).fixedSize()
                .accessibilityIdentifier("panel-someday")
            Text(t.ownSomeday ? "Parked: off Today, the Planner and the other lenses" : "Park it out of the way")
                .font(.nx(.footnote)).foregroundStyle(Kit.faint)
        }
    }

    // MARK: subtasks, notes, the file

    private func subtasks(_ t: NexusTask) -> some View {
        let kids = store.snapshot.children(of: t)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Subtasks").font(.nx(.headline, .semibold)).foregroundStyle(Kit.ink)
                if !kids.isEmpty { Text("\(kids.filter(\.done).count) of \(kids.count) done").font(.nx(.subheadline)).foregroundStyle(Kit.faint) }
            }
            Rectangle().fill(Kit.line).frame(height: 1)
            PanelChecklist(task: t)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel-subtasks")
    }

    private func notes(_ t: NexusTask, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.nx(.headline, .semibold)).foregroundStyle(Kit.ink)
            TextEditor(text: $noteText)
                .font(.nx(.body))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(10)
                .background(Kit.rests, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if noteText.isEmpty {
                        Text("Anything worth remembering: links, what the teacher said, page numbers.")
                            .font(.nx(.body)).foregroundStyle(Kit.faint).padding(.horizontal, 15).padding(.vertical, 18).allowsHitTesting(false)
                    }
                }
                .focused($focus, equals: .note)
                .disabled(!editable)
                .accessibilityIdentifier("panel-note")
        }
    }

    private func foot(_ t: NexusTask, editable: Bool) -> some View {
        HStack(spacing: 10) {
            Label(t.file + (t.added.map { " · added " + Days.label(String($0.prefix(10))) } ?? ""), systemImage: "doc")
                .font(.nx(.footnote)).foregroundStyle(Kit.faint).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if editable {
                if sure {
                    Button("Keep") { withAnimation(Kit.snap) { sure = false } }.buttonStyle(KitButtonStyle(kind: .plain, small: true))
                    Button("Delete it") { store.delete(t); dismiss() }
                        .buttonStyle(KitButtonStyle(kind: .tone, small: true)).foregroundStyle(Theme.late)
                        .accessibilityIdentifier("panel-delete-yes")
                } else {
                    Button("Delete") { withAnimation(Kit.snap) { sure = true } }.buttonStyle(KitButtonStyle(kind: .plain, small: true))
                        .accessibilityIdentifier("panel-delete")
                }
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(Kit.line).frame(height: 1) }
    }

    // MARK: saving the typed fields

    /// The text fields from the file (when the task changed and nothing is being typed).
    private func fill(_ t: NexusTask) {
        waitingText = t.waitingOn ?? ""
        noteText = (t.note ?? "").trimmingCharacters(in: .newlines)
    }

    /// Saves one text field if it changed.
    private func commit(_ f: Field, _ t: NexusTask) {
        guard store.canEdit(t) else { return }
        switch f {
        case .waiting:
            let w = waitingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if w != (t.waitingOn ?? "") { store.setWaiting(t, on: w.isEmpty ? nil : w, since: w.isEmpty ? nil : (t.waitingSince ?? store.today)) }
        case .note:
            let n = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            if n != (t.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines) { store.setNote(t, n) }
        }
    }

    private func commitFields(_ t: NexusTask) {
        for f in [Field.waiting, .note] {
            if let now = store.task(taskId) { commit(f, now) } else { commit(f, t) }
        }
    }

    private func commitTitle(_ t: NexusTask) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != t.title, store.canEdit(t) { store.setTitle(t, clean) }
    }
}
