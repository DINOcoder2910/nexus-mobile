import SwiftUI
import NexusCore

/// The task panel: everything about one task, editable in place and saved at once (Undo on the bar for each change).
/// Waiting on, repeats, tags and the note are written as the laptop writes them (NexusCore TaskFields).
struct TaskDetailView: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let taskId: String

    @State private var title = ""
    @State private var newSubtask = ""
    @State private var pickDay = Date()
    @State private var pickTime = Date()
    @State private var withTime = false
    @State private var showDayPicker = false
    @FocusState private var titleFocused: Bool
    @State private var waitingText = ""
    @State private var tagsText = ""
    @State private var noteText = ""
    @FocusState private var focus: Field?

    private enum Field { case waiting, tags, note }

    var body: some View {
        NavigationStack {
            if let t = store.task(taskId) {
                form(t)
                    .navigationTitle(store.workstreamName(t))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { commitTitle(t); commitFields(t); dismiss() } }
                    }
                    .onAppear { title = t.title; fill(t) }
                    .onChange(of: t.title) { _, new in if !titleFocused { title = new } }
                    .onChange(of: store.snapshot.loadedAt) { _, _ in if focus == nil, let now = store.task(taskId) { fill(now) } }
                    .onChange(of: focus) { old, _ in if let old, let now = store.task(taskId) { commit(old, now) } }
            } else {
                EmptyNote(title: "This task is gone", detail: "It was removed or moved since.", icon: "questionmark.circle")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
            }
        }
    }

    @ViewBuilder
    private func form(_ t: NexusTask) -> some View {
        let editable = store.canEdit(t)
        let p = store.planning
        Form {
            if !editable {
                Section {
                    Label(t.hasId ? (store.snapshot.readOnlyReason ?? "\(t.file) does not parse, so it is read-only here.")
                                  : "This task has no id yet. Open the folder in Nexus on the laptop once and it gets one; then it can be edited here.",
                          systemImage: "lock")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                if let crumb = p.crumb(t), let parent = t.parent.flatMap({ store.task($0) }) {
                    Button { store.open(parent) } label: {
                        Label(crumb, systemImage: "arrow.turn.left.up").font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    TickRing(task: t)
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit { commitTitle(t) }
                        .disabled(!editable)
                }
                Toggle(isOn: Binding(get: { t.key }, set: { store.setKey(t, $0) })) { Label("Key date ★", systemImage: "star") }
                    .disabled(!editable).tint(Theme.key)
            }

            Section("Deadline") {
                if let due = t.due {
                    DatePicker(selection: Binding(get: { Days.date(due) ?? Date() }, set: { store.setDue(t, Days.iso($0)) }), displayedComponents: .date) {
                        Label(Days.relative(due, today: store.today), systemImage: "flag")
                            .foregroundStyle(Days.between(store.today, due) < 0 ? Theme.late : .primary)
                    }
                    .disabled(!editable)
                    if editable { Button("Remove the deadline", role: .destructive) { store.setDue(t, nil) } }
                } else {
                    if let above = p.deadline(t) { Text("The task above is due \(Days.label(above))").font(.callout).foregroundStyle(.secondary) }
                    if editable {
                        HStack {
                            Button("Today") { store.setDue(t, store.today) }
                            Button("Tomorrow") { store.setDue(t, Days.add(store.today, 1)) }
                            Button("In a week") { store.setDue(t, Days.add(store.today, 7)) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section {
                ForEach(t.plan.sorted { $0.raw < $1.raw }, id: \.raw) { e in
                    HStack {
                        Label(Days.label(e.day) + (e.time.map { " · \($0)" } ?? ""), systemImage: e.day < store.today ? "calendar.badge.exclamationmark" : "calendar")
                            .foregroundStyle(e.day < store.today ? .secondary : .primary)
                        if e.day == store.today { Text("Today").font(.caption).foregroundStyle(Theme.planned) }
                        Spacer()
                        if editable {
                            Button { store.unplan(t, from: e.day) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if editable {
                    HStack {
                        if !t.plannedDays.contains(store.today) { Button("Today") { store.plan(t, on: store.today) } }
                        if !t.plannedDays.contains(Days.add(store.today, 1)) { Button("Tomorrow") { store.plan(t, on: Days.add(store.today, 1)) } }
                        Button("Pick a day…") { showDayPicker.toggle() }
                    }
                    .buttonStyle(.bordered)
                    if showDayPicker {
                        DatePicker("Day", selection: $pickDay, displayedComponents: .date)
                        Toggle("At a time", isOn: $withTime)
                        if withTime { DatePicker("Time", selection: $pickTime, displayedComponents: .hourAndMinute) }
                        Button("Plan it") {
                            let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = Locale(identifier: "en_US_POSIX")
                            store.plan(t, on: Days.iso(pickDay), time: withTime ? f.string(from: pickTime) : nil)
                            showDayPicker = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } header: { Text("Planned") } footer: { Text("The days you will work on it, each with an optional time.") }

            Section("Estimate") {
                HStack {
                    Text(t.est ?? (p.estimate(t).map { "\(hoursText($0)) (its subtasks)" } ?? "None")).foregroundStyle(t.est == nil ? .secondary : .primary)
                    Spacer()
                    if editable {
                        Menu("Change") {
                            ForEach(["15m", "30m", "45m", "1h", "1h30", "2h", "3h", "4h"], id: \.self) { e in Button(e) { store.setEstimate(t, e) } }
                            if t.est != nil { Button("None", role: .destructive) { store.setEstimate(t, nil) } }
                        }
                    }
                }
            }

            Section {
                ForEach(store.snapshot.children(of: t)) { c in
                    TaskRow(task: c, showWorkstream: false, showCrumb: false, compact: true)
                }
                if editable {
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        TextField("Add a subtask", text: $newSubtask)
                            .submitLabel(.done)
                            .onSubmit {
                                let text = newSubtask.trimmingCharacters(in: .whitespaces)
                                guard !text.isEmpty else { return }
                                store.add(title: text, workstream: t.workstream, parent: t)
                                newSubtask = ""
                            }
                    }
                }
            } header: {
                if let pr = p.progress(t) { Text("Subtasks · \(pr.done)/\(pr.total)") } else { Text("Subtasks") }
            }

            waitingSection(t, editable: editable)
            repeatSection(t, editable: editable)

            Section {
                TextField("Tags, e.g. #summative #lab", text: $tagsText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .tags)
                    .submitLabel(.done)
                    .onSubmit { commit(.tags, t) }
                    .disabled(!editable)
            } header: { Text("Tags") }

            Section {
                TextEditor(text: $noteText)
                    .frame(minHeight: 90)
                    .focused($focus, equals: .note)
                    .disabled(!editable)
            } header: { Text("Note") } footer: { Text("Saved when you leave the note or press Done.") }

            if let e = t.email {
                Section { LabeledContent("Email", value: e.hasPrefix("gmail/") ? "Gmail message" : e.hasPrefix("outlook/") ? "Outlook message" : e) }
            }

            Section {
                Toggle(isOn: Binding(get: { t.ownSomeday }, set: { store.setSomeday(t, $0) })) { Label("Someday", systemImage: "moon.zzz") }
                    .disabled(!editable)
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.file).font(.caption.monospaced())
                    if let a = t.added { Text("Added \(Days.label(String(a.prefix(10))))") }
                    if let d = t.doneOn { Text("Done \(Days.label(d))") }
                }
            }
        }
    }

    // MARK: waiting, repeats, tags, note

    @ViewBuilder
    private func waitingSection(_ t: NexusTask, editable: Bool) -> some View {
        Section {
            TextField("Waiting on someone? Their name", text: $waitingText)
                .focused($focus, equals: .waiting)
                .submitLabel(.done)
                .onSubmit { commit(.waiting, t) }
                .disabled(!editable)
            if t.waitingOn != nil {
                if let since = t.waitingSince {
                    DatePicker(selection: Binding(get: { Days.date(since) ?? Date() },
                                                  set: { store.setWaiting(t, on: t.waitingOn, since: Days.iso($0)) }),
                               displayedComponents: .date) {
                        Text("Since (\(Days.between(since, store.today)) days)")
                    }
                    .disabled(!editable)
                }
                if editable { Button("Not waiting any more") { waitingText = ""; store.setWaiting(t, on: nil, since: nil) } }
            }
        } header: { Text("Waiting on") }
    }

    @ViewBuilder
    private func repeatSection(_ t: NexusTask, editable: Bool) -> some View {
        Section {
            HStack {
                Text(t.every?.text ?? (t.everyRaw.map { "As written: \($0)" } ?? "Doesn't repeat"))
                    .foregroundStyle(t.every == nil ? .secondary : .primary)
                Spacer()
                if editable {
                    Menu("Change") {
                        Button("Every day") { store.setRepeat(t, NexusCore.Repeat(freq: "day", until: t.every?.until)) }
                        Button("Every weekday") { store.setRepeat(t, NexusCore.Repeat(freq: "weekdays", until: t.every?.until)) }
                        Menu("Every week on…") {
                            ForEach(Self.weekdays, id: \.self) { d in
                                Button(Self.dayName(d)) { store.setRepeat(t, NexusCore.Repeat(freq: "week", on: [d], until: t.every?.until)) }
                            }
                        }
                        if t.every != nil || t.everyRaw != nil {
                            Button("Doesn't repeat", role: .destructive) { store.setRepeat(t, nil) }
                        }
                    }
                }
            }
            if let r = t.every {
                Toggle("Until a day", isOn: Binding(get: { r.until != nil }, set: { on in
                    store.setRepeat(t, NexusCore.Repeat(freq: r.freq, on: r.on, until: on ? Days.add(store.today, 28) : nil))
                }))
                .disabled(!editable)
                if let u = r.until {
                    DatePicker("Last day", selection: Binding(get: { Days.date(u) ?? Date() },
                                                               set: { store.setRepeat(t, NexusCore.Repeat(freq: r.freq, on: r.on, until: Days.iso($0))) }),
                               displayedComponents: .date)
                        .disabled(!editable)
                }
            }
        } header: { Text("Repeats") }
    }

    private static let weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private static func dayName(_ d: String) -> String {
        ["mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "fri": "Friday", "sat": "Saturday", "sun": "Sunday"][d] ?? d
    }

    /// The text fields from the file (when the task changed and nothing is being typed).
    private func fill(_ t: NexusTask) {
        waitingText = t.waitingOn ?? ""
        tagsText = t.tags.map { "#" + $0 }.joined(separator: " ")
        noteText = (t.note ?? "").trimmingCharacters(in: .newlines)
    }

    /// Saves one text field if it changed.
    private func commit(_ f: Field, _ t: NexusTask) {
        guard store.canEdit(t) else { return }
        switch f {
        case .waiting:
            let w = waitingText.trimmingCharacters(in: .whitespacesAndNewlines)
            if w != (t.waitingOn ?? "") { store.setWaiting(t, on: w, since: t.waitingSince ?? store.today) }
        case .tags:
            let tags = tagsText.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
            let clean = tags.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }.filter { !$0.isEmpty }
            if clean != t.tags { store.setTags(t, clean) }
        case .note:
            let n = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            if n != (t.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines) { store.setNote(t, n) }
        }
    }

    private func commitFields(_ t: NexusTask) {
        for f in [Field.waiting, .tags, .note] {
            if let now = store.task(taskId) { commit(f, now) } else { commit(f, t) }
        }
    }

    private func commitTitle(_ t: NexusTask) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty, clean != t.title, store.canEdit(t) { store.setTitle(t, clean) }
    }
}
