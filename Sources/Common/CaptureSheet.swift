import SwiftUI
import NexusCore

/// Add a task. The line is read as the laptop reads it (NexusCore's CaptureParse): "physics hw sheet by fri; q1-5 by thu on wed 45m"
/// is "physics hw sheet", due Friday, in the workstream its words name, with a subtask "q1-5" due Thursday, planned Wednesday, 45
/// minutes. A preview under the line shows what was read. The field buttons (workstream, deadline, planned day, ★, estimate) show
/// what the task will have, typed or picked; a value picked with them wins over the typed one, until a new one is typed. A typed
/// repeat, waiting on and #tags are written too. Return adds it and keeps the sheet open for the next one.
struct CaptureSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let start: NexusStore.CaptureStart

    @State private var title = ""
    /// the line as read, and where it lands (updated as it is typed)
    @State private var parsed = CaptureParsed(kind: .empty)
    @State private var landed: CaptureLanding?
    // what the buttons picked; each `...Picked` false = use the typed value (or the context's)
    @State private var workstream: String?
    @State private var workstreamPicked = false
    @State private var due: String?
    @State private var duePicked = false
    @State private var plan: String?
    @State private var planPicked = false
    @State private var key = false
    @State private var keyPicked = false
    @State private var est: String?
    @State private var estPicked = false
    @State private var added: [String] = []
    @State private var pickingDue = false
    @State private var pickingPlan = false
    @FocusState private var focused: Bool

    var parent: NexusTask? { store.task(start.parent) }
    /// the workstream of the place the sheet was opened from
    var context: String? { parent?.workstream ?? start.workstream }

    // MARK: what the task will have

    var effWorkstream: String? { workstreamPicked ? workstream : (landed?.workstream?.id ?? context) }
    var effDue: String? { duePicked ? due : parsed.facts.due }
    var effPlan: [PlanEntry] {
        if planPicked { return plan.map { [PlanEntry(day: $0)] } ?? [] }
        if parsed.kind == .task { return parsed.facts.planEntries }
        return start.plan.map { [PlanEntry(day: $0)] } ?? []
    }
    var effKey: Bool { keyPicked ? key : parsed.facts.key }
    var effEst: String? { estPicked ? est : parsed.facts.est }
    var estOptions: [String] {
        let base = ["15m", "30m", "45m", "1h", "1h30", "2h", "3h"]
        if let e = effEst, !base.contains(e) { return base + [e] }
        return base
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(parent == nil ? "What needs doing?" : "Subtask", text: $title, axis: .vertical)
                        .font(.title3)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addIt)
                    if let parent { Label("Under “\(parent.text)”", systemImage: "arrow.turn.down.right").font(.callout).foregroundStyle(.secondary) }
                    preview
                }
                Section {
                    if parent == nil {
                        Picker(selection: Binding(get: { effWorkstream }, set: { workstream = $0; workstreamPicked = true })) {
                            Text("Inbox").tag(String?.none)
                            ForEach(store.snapshot.groups) { g in
                                Section(g.label) {
                                    ForEach(store.snapshot.workstreams(in: g).filter { !$0.finished || $0.id == effWorkstream }) { w in
                                        Text(w.name).tag(Optional(w.id))
                                    }
                                }
                            }
                        } label: { Label("Workstream", systemImage: "folder") }
                    }
                    dayRow("Deadline", icon: "flag", value: Binding(get: { effDue }, set: { due = $0; duePicked = true }), picking: $pickingDue)
                    dayRow("Planned for", icon: "calendar", value: Binding(get: { effPlan.first?.day }, set: { plan = $0; planPicked = true }),
                           picking: $pickingPlan)
                    Toggle(isOn: Binding(get: { effKey }, set: { key = $0; keyPicked = true })) { Label("Key date ★", systemImage: "star") }.tint(Theme.key)
                    Picker(selection: Binding(get: { effEst }, set: { est = $0; estPicked = true })) {
                        Text("None").tag(String?.none)
                        ForEach(estOptions, id: \.self) { Text($0).tag(Optional($0)) }
                    } label: { Label("Estimate", systemImage: "hourglass") }
                }
                if !added.isEmpty {
                    Section("Added") { ForEach(added, id: \.self) { Label($0, systemImage: "checkmark").foregroundStyle(.secondary) } }
                }
            }
            .navigationTitle(parent == nil ? "New task" : "New subtask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(added.isEmpty ? "Cancel" : "Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: addIt).disabled(!(parsed.kind == .task && parsed.ok)) }
            }
            .onAppear {
                reparse()
                focused = true
            }
            .onChange(of: title) { reparse() }
        }
    }

    // MARK: the preview

    /// The chips for what the line says, with the buttons' picks in place of the typed values.
    private var chips: [CaptureChip] {
        guard parsed.kind == .task else { return [] }
        var shown = parsed
        shown.facts.due = effDue
        shown.facts.plan = effPlan.map(\.raw)
        shown.facts.key = effKey
        shown.facts.est = effEst
        var out = CaptureParse.chips(shown, landing: parent == nil ? landed : nil, today: store.today)
        if workstreamPicked, let i = out.firstIndex(where: { $0.kind == .ws }) {
            out[i].workstream = workstream
            out[i].text = store.workstream(workstream)?.name ?? "Inbox"
            out[i].tail = ""
        }
        return out
    }

    @ViewBuilder
    private var preview: some View {
        let main = chips
        if !main.isEmpty {
            chipRow(main)
            ForEach(Array(parsed.subtasksToAdd.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").imageScale(.small).foregroundStyle(.secondary)
                    Text(s.title).font(.callout)
                    chipRow(subChips(s))
                }
            }
        }
    }

    private func subChips(_ s: CaptureSubtask) -> [CaptureChip] {
        var p = CaptureParsed(kind: .task)
        p.ok = s.ok; p.title = s.title; p.facts = s.facts; p.flags = s.flags
        return CaptureParse.chips(p, landing: nil, today: store.today)
    }

    private func chipRow(_ list: [CaptureChip]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, c in chipView(c) }
            }
        }
    }

    @ViewBuilder
    private func chipView(_ c: CaptureChip) -> some View {
        switch c.kind {
        case .ws: Chip(text: c.text + c.tail, icon: c.workstream == nil ? "tray" : "folder", color: store.color(workstream: c.workstream), strong: true)
        case .due: Chip(text: c.text, icon: "flag", color: Theme.late)
        case .dropped: Chip(text: c.text + " left out: deadlines are whole days", icon: "clock", color: .secondary)
        case .plan: Chip(text: c.text, icon: "calendar", color: Theme.planned)
        case .est: Chip(text: c.text, icon: "hourglass", color: .secondary)
        case .key: Chip(text: c.text, color: Theme.key, strong: true)
        case .every: Chip(text: c.text, icon: "repeat", color: .secondary)
        case .waiting: Chip(text: c.text, icon: "person", color: .secondary)
        case .tag: Chip(text: c.text, icon: "number", color: .secondary)
        case .subs: Chip(text: c.text, icon: "list.bullet.indent", color: .secondary)
        }
    }

    // MARK: reading the line

    private func reparse() {
        let old = parsed
        let oldTag = landed?.how == .tag ? landed?.workstream?.id : nil
        // a leading / or > is part of the title here: the iPad has no Claude panel or command palette
        let p = CaptureParse.parseLine(title, in: store.snapshot, today: store.today, plan: start.plan, commands: false)
        let l = CaptureParse.land(p, in: store.snapshot, context: context)
        // typing a new value after picking one wins, as on the laptop (a workstream only by a #tag, not by a guess from the words)
        if let d = p.facts.due, d != old.facts.due { duePicked = false }
        let typedPlan = p.spans.contains { $0.part == 0 && ($0.kind == .plan || $0.kind == .time) }
        if typedPlan && p.facts.plan != old.facts.plan { planPicked = false }
        if let e = p.facts.est, e != old.facts.est { estPicked = false }
        if p.facts.key && !old.facts.key { keyPicked = false }
        if l.how == .tag, l.workstream?.id != oldTag { workstreamPicked = false }
        parsed = p
        landed = l
    }

    @ViewBuilder
    private func dayRow(_ label: String, icon: String, value: Binding<String?>, picking: Binding<Bool>) -> some View {
        let today = store.today
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Menu(value.wrappedValue.map { Days.relative($0, today: today) } ?? "None") {
                Button("None") { value.wrappedValue = nil; picking.wrappedValue = false }
                Button("Today") { value.wrappedValue = today }
                Button("Tomorrow") { value.wrappedValue = Days.add(today, 1) }
                Button("Pick a day…") { picking.wrappedValue = true; if value.wrappedValue == nil { value.wrappedValue = Days.add(today, 1) } }
            }
        }
        if picking.wrappedValue, let v = value.wrappedValue {
            DatePicker(label, selection: Binding(get: { Days.date(v) ?? Date() }, set: { value.wrappedValue = Days.iso($0) }), displayedComponents: .date)
                .datePickerStyle(.graphical)
        }
    }

    // MARK: adding

    private func addIt() {
        let p = parsed
        guard p.kind == .task, p.ok else { return }
        let ws = effWorkstream
        guard let id = store.add(title: p.title, workstream: ws, parent: parent, due: effDue, plan: effPlan, key: effKey, est: effEst,
                                 extras: p.facts) else { return }
        // the `; a; b` subtasks, each with its own facts, under the task just added
        var subs = 0
        for s in p.subtasksToAdd {
            let sid = store.add(title: s.title, workstream: ws, parent: store.task(id), due: s.facts.due, plan: s.facts.planEntries,
                                key: s.facts.key, est: s.facts.est, extras: s.facts)
            if sid != nil { subs += 1 }
        }
        added.append(subs == 0 ? p.title : subs == 1 ? "\(p.title) (+1 subtask)" : "\(p.title) (+\(subs) subtasks)")
        title = ""
        due = nil; duePicked = false
        key = false; keyPicked = false
        est = nil; estPicked = false
        pickingDue = false
        focused = true
    }
}
