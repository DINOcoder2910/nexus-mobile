import SwiftUI
import NexusCore

/// Add a task: a title and the field buttons (workstream, deadline, planned day, ★, estimate), like the laptop's add box without
/// the typed-date reading (that comes later). Return adds it and keeps the sheet open for the next one.
struct CaptureSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let start: NexusStore.CaptureStart

    @State private var title = ""
    @State private var workstream: String?
    @State private var due: String?
    @State private var plan: String?
    @State private var key = false
    @State private var est: String?
    @State private var added: [String] = []
    @State private var pickingDue = false
    @State private var pickingPlan = false
    @FocusState private var focused: Bool

    var parent: NexusTask? { store.task(start.parent) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(parent == nil ? "What needs doing?" : "Subtask", text: $title, axis: .vertical)
                        .font(.title3)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(addIt)
                    if let parent { Label("Under “\(parent.text)”", systemImage: "arrow.turn.down.right").font(.callout).foregroundStyle(.secondary) }
                }
                Section {
                    if parent == nil {
                        Picker(selection: $workstream) {
                            Text("Inbox").tag(String?.none)
                            ForEach(store.snapshot.groups) { g in
                                Section(g.label) {
                                    ForEach(store.snapshot.workstreams(in: g).filter { !$0.finished }) { w in Text(w.name).tag(Optional(w.id)) }
                                }
                            }
                        } label: { Label("Workstream", systemImage: "folder") }
                    }
                    dayRow("Deadline", icon: "flag", value: $due, picking: $pickingDue)
                    dayRow("Planned for", icon: "calendar", value: $plan, picking: $pickingPlan)
                    Toggle(isOn: $key) { Label("Key date ★", systemImage: "star") }.tint(Theme.key)
                    Picker(selection: $est) {
                        Text("None").tag(String?.none)
                        ForEach(["15m", "30m", "45m", "1h", "1h30", "2h", "3h"], id: \.self) { Text($0).tag(Optional($0)) }
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
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: addIt).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                workstream = parent?.workstream ?? start.workstream
                plan = start.plan
                focused = true
            }
        }
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

    private func addIt() {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var isKey = key
        if text.hasSuffix(" !") || text.hasSuffix("★") { isKey = true; text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        let id = store.add(title: text, workstream: workstream, parent: parent, due: due,
                           plan: plan.map { [PlanEntry(day: $0)] } ?? [], key: isKey, est: est)
        if id != nil {
            added.append(text)
            title = ""; key = false; est = nil; due = nil
            pickingDue = false
            focused = true
        }
    }
}
