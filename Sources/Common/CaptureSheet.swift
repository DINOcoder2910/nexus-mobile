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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    card
                    fields
                    if pickingDue || pickingPlan { picker }
                    if !added.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Added").font(.nx(.subheadline, .semibold)).foregroundStyle(Kit.muted)
                            ForEach(added, id: \.self) { Label($0, systemImage: "checkmark").font(.nx(.callout)).foregroundStyle(Kit.muted) }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
            }
            .background(Kit.page)
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
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

    // MARK: the line, and what was read

    /// The line at the bottom, as the laptop's capture bar: a plus, the words, and the round Add.
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Image(systemName: "plus").font(.system(size: 15, weight: .medium)).foregroundStyle(Kit.faint).padding(.bottom, 9)
            TextField(parent == nil ? "What needs doing? “chem lab report by fri 2h; data; graph by mon”" : "Subtask", text: $title, axis: .vertical)
                .font(.nx(size: 18))
                .lineLimit(1...4)
                .focused($focused)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(addIt)
                .padding(.vertical, 7)
                .accessibilityIdentifier("capture-field")
            Button(action: addIt) {
                Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(parsed.kind == .task && parsed.ok ? Theme.accent : Kit.faint, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!(parsed.kind == .task && parsed.ok))
            .accessibilityLabel("Add it")
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .background(Kit.page, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.accent.opacity(focused ? 0.55 : 0.2), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 2)
        .padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 6)
        .background(Kit.page.opacity(0.94))
    }

    /// The line with what it set lit up: deadlines and planned days amber, the rest on a tone, a dropped time struck through.
    private var lit: Text {
        let chars = Array(title)
        var spans = parsed.spans.filter { $0.start >= 0 && $0.end <= chars.count && $0.start < $0.end }.sorted { $0.start < $1.start }
        spans = spans.reduce(into: []) { out, s in if let l = out.last, s.start < l.end { return }; out.append(s) }
        var out = Text("")
        var at = 0
        for s in spans {
            if s.start > at { out = out + Text(String(chars[at..<s.start])).foregroundColor(Kit.ink) }
            let w = String(chars[s.start..<s.end])
            switch s.kind {
            case .due, .plan, .time: out = out + Text(w).foregroundColor(Theme.soon).fontWeight(.medium)
            case .dropped: out = out + Text(w).foregroundColor(Kit.faint).strikethrough()
            case .ws: out = out + Text(w).foregroundColor(Theme.accent).fontWeight(.medium)
            case .key: out = out + Text(w).foregroundColor(Theme.key).fontWeight(.semibold)
            case .sub: out = out + Text(w).foregroundColor(Kit.faint)
            default: out = out + Text(w).foregroundColor(Kit.muted).fontWeight(.medium)
            }
            at = s.end
        }
        if at < chars.count { out = out + Text(String(chars[at...])).foregroundColor(Kit.ink) }
        return out
    }

    /// What will be added: the title, the chips of what it read, its subtasks, the warnings, and where it goes.
    @ViewBuilder
    private var card: some View {
        let main = chips
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(parent.map { "Under “\($0.text)”" } ?? "Add a task").font(.nx(.subheadline)).foregroundStyle(Kit.faint)
                if parsed.kind == .task && parsed.ok {
                    (effKey ? Text("★ ").foregroundColor(Theme.key) : Text(""))
                        + Text(parsed.title).foregroundColor(Kit.ink)
                }
            }
            .font(.nx(size: 18, .semibold))
            if title.isEmpty {
                Text("Type a task the way you'd say it: “physics sheet by fri 45m”, “email Ms Chen on mon 4pm”, “lab ★”. A “;” starts a subtask.")
                    .font(.nx(.callout)).foregroundStyle(Kit.muted)
            } else {
                lit.font(.nx(.callout)).padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("capture-lit")
            }
            if !main.isEmpty {
                FlowRow(spacing: 6) { ForEach(Array(main.enumerated()), id: \.offset) { _, c in chipView(c) } }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("capture-chips")
            }
            ForEach(Array(parsed.subtasksToAdd.enumerated()), id: \.offset) { _, s in
                HStack(spacing: 8) {
                    Circle().strokeBorder(Kit.faint, lineWidth: 1.5).frame(width: 11, height: 11)
                    Text(s.title).font(.nx(.callout)).foregroundStyle(Kit.ink)
                    let extra = subChips(s).map(\.text).joined(separator: " · ")
                    if !extra.isEmpty { Text("· " + extra).font(.nx(.callout)).foregroundStyle(Kit.faint) }
                }
            }
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
                Label(w, systemImage: "questionmark.circle").font(.nx(.footnote)).foregroundStyle(Theme.soon)
            }
            if parent == nil && parsed.kind == .task { goesTo }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kit.page, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Kit.line))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .animation(Kit.snap, value: parsed)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture-preview")
    }

    /// What the line said that needs a look.
    private var warnings: [String] {
        guard parsed.kind == .task else { return [] }
        return parsed.flags.compactMap { f in
            switch f.code {
            case .timeDropped: return "\(f.text ?? f.time ?? "The time") left out: a deadline is a whole day (use “on” to plan a time)"
            case .pastDate: return "\(f.text ?? "That date") is before today"
            case .ambiguous: return "“\(f.text ?? "")” kept as a word: say “by \(f.text ?? "")” for the day"
            case .noTitle: return nil
            }
        }
    }

    /// "Goes to Chemistry HL  classes/chemistry/tasks.yaml", and the other places it could go.
    private var goesTo: some View {
        let ws = effWorkstream
        let file = store.workstream(ws)?.tasksFile ?? "inbox.yaml"
        let others = (landed?.alternatives ?? []).filter { $0?.id != ws }.prefix(3)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { goesWords(ws, file); Spacer(minLength: 8); alternatives(Array(others)) }
            VStack(alignment: .leading, spacing: 6) { goesWords(ws, file); alternatives(Array(others)) }
        }
        .font(.nx(.footnote))
    }

    private func goesWords(_ ws: String?, _ file: String) -> some View {
        (Text("Goes to ").foregroundColor(Kit.muted) + Text(store.workstream(ws)?.name ?? "Inbox").foregroundColor(Kit.ink).fontWeight(.semibold)
            + Text("  " + file).foregroundColor(Kit.faint))
            .lineLimit(1)
            .accessibilityIdentifier("capture-goes")
    }

    private func alternatives(_ list: [Workstream?]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, w in
                Button(w?.name ?? "Inbox") { workstream = w?.id; workstreamPicked = true }
                    .foregroundStyle(Kit.muted).buttonStyle(.plain)
            }
        }
    }

    // MARK: the field buttons

    private var fields: some View {
        FlowRow(spacing: 8) {
            if parent == nil {
                Menu {
                    Picker("Workstream", selection: Binding(get: { effWorkstream }, set: { workstream = $0; workstreamPicked = true })) {
                        Text("Inbox").tag(String?.none)
                        ForEach(store.snapshot.groups) { g in
                            Section(g.label) {
                                ForEach(store.snapshot.workstreams(in: g).filter { !$0.finished || $0.id == effWorkstream }) { w in
                                    Text(w.name).tag(Optional(w.id))
                                }
                            }
                        }
                    }
                } label: { fieldLabel(store.workstream(effWorkstream)?.name ?? "Inbox", icon: "folder", on: effWorkstream != nil, dot: store.color(workstream: effWorkstream)) }
            }
            dayMenu("Deadline", icon: "flag", value: Binding(get: { effDue }, set: { due = $0; duePicked = true }), picking: $pickingDue, other: $pickingPlan)
            dayMenu("Planned", icon: "calendar", value: Binding(get: { effPlan.first?.day }, set: { plan = $0; planPicked = true }), picking: $pickingPlan, other: $pickingDue)
            Button { key = !effKey; keyPicked = true } label: { fieldLabel(effKey ? "★ Key date" : "☆ Key date", icon: nil, on: effKey, tint: Theme.key) }
                .buttonStyle(.plain)
            Menu {
                Picker("Estimate", selection: Binding(get: { effEst }, set: { est = $0; estPicked = true })) {
                    Text("None").tag(String?.none)
                    ForEach(estOptions, id: \.self) { Text($0).tag(Optional($0)) }
                }
            } label: { fieldLabel(effEst ?? "Estimate", icon: "clock", on: effEst != nil) }
        }
    }

    private func fieldLabel(_ text: String, icon: String?, on: Bool, dot: Color? = nil, tint: Color = Theme.accent) -> some View {
        HStack(spacing: 6) {
            if let dot, on { SubjectDot(color: dot, size: 7) } else if let icon { Image(systemName: icon).font(.system(size: 12)) }
            Text(text).lineLimit(1)
        }
        .font(.nx(.subheadline, on ? .medium : .regular))
        .foregroundStyle(on ? (dot ?? tint) : Kit.muted)
        .padding(.horizontal, 12).frame(height: 32)
        .background(on ? (dot ?? tint).opacity(0.13) : Kit.rests, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func dayMenu(_ label: String, icon: String, value: Binding<String?>, picking: Binding<Bool>, other: Binding<Bool>) -> some View {
        let today = store.today
        return Menu {
            Button("None") { value.wrappedValue = nil; picking.wrappedValue = false }
            Button("Today") { value.wrappedValue = today }
            Button("Tomorrow") { value.wrappedValue = Days.add(today, 1) }
            Button("Pick a day…") { other.wrappedValue = false; picking.wrappedValue = true; if value.wrappedValue == nil { value.wrappedValue = Days.add(today, 1) } }
        } label: {
            fieldLabel(value.wrappedValue.map { label + " " + Days.relative($0, today: today) } ?? label, icon: icon, on: value.wrappedValue != nil,
                       tint: label == "Deadline" ? Theme.soon : Theme.accent)
        }
    }

    @ViewBuilder
    private var picker: some View {
        let due = pickingDue
        let value = due ? Binding(get: { effDue }, set: { self.due = $0; duePicked = true }) : Binding(get: { effPlan.first?.day }, set: { plan = $0; planPicked = true })
        if let v = value.wrappedValue {
            DatePicker(due ? "Deadline" : "Planned", selection: Binding(get: { Days.date(v) ?? Date() }, set: { value.wrappedValue = Days.iso($0) }), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding(10)
                .background(Kit.rests, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

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

    private func subChips(_ s: CaptureSubtask) -> [CaptureChip] {
        var p = CaptureParsed(kind: .task)
        p.ok = s.ok; p.title = s.title; p.facts = s.facts; p.flags = s.flags
        return CaptureParse.chips(p, landing: nil, today: store.today)
    }

    /// A chip as the laptop's preview draws it: the subject outlined in its colour ("from “chem”" when guessed), a deadline amber.
    @ViewBuilder
    private func chipView(_ c: CaptureChip) -> some View {
        let tone: Color = {
            switch c.kind {
            case .ws: return store.color(workstream: c.workstream)
            case .due, .key: return c.kind == .key ? Theme.key : Theme.soon
            case .plan: return Theme.accent
            default: return Kit.muted
            }
        }()
        HStack(spacing: 5) {
            if c.kind == .ws { SubjectDot(color: tone, size: 7) }
            Text(c.kind == .dropped ? c.text + " left out" : c.text).fontWeight(c.kind == .ws ? .semibold : .regular)
            if !c.tail.isEmpty { Text(c.tail).foregroundStyle(Kit.faint) }
        }
        .font(.nx(.subheadline))
        .foregroundStyle(tone)
        .strikethrough(c.kind == .dropped)
        .padding(.horizontal, 10).frame(height: 30)
        .background(c.kind == .ws ? Color.clear : tone.opacity(c.kind == .est || c.kind == .tag || c.kind == .subs || c.kind == .every || c.kind == .waiting || c.kind == .dropped ? 0.10 : 0.13),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(c.kind == .ws ? tone : .clear, lineWidth: 1.5))
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
