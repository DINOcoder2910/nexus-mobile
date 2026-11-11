import SwiftUI
import UIKit
import GameController
import NexusCore

/// Settings › Shortcuts: every key and gesture that does something in Nexus, on the laptop or the iPad (the switch at the top), in
/// collapsible sections, with search, conflicts in red (and "takes over" notes in grey), a reset beside each changed one and Reset all.
/// Tap a key to change it: press the new keys on the keyboard, or pick them; a key another shortcut has here offers Swap or Replace.
struct ShortcutsView: View {
    typealias Side = ShortcutCenter.Side

    @State private var side: Side = .ipad
    @State private var query = ""
    @State private var conflictsOnly = false
    @AppStorage("shortcuts.closedGroups") private var closedGroups = ""
    @State private var editing: KeyEdit?
    @State private var gestureMove: GestureMove?
    @State private var confirmReset = false

    struct KeyEdit: Identifiable {
        let id = UUID()
        var side: Side
        var shortcut: Shortcut
        /// The binding being changed (nil: a new one is added).
        var replacing: String?
    }

    struct GestureMove: Identifiable {
        let id = UUID()
        var gesture: String
        var to: Shortcut
        var holders: [Shortcut]
    }

    struct Rows: Identifiable {
        var id: String { name }
        let name: String
        let items: [Shortcut]
    }

    var body: some View {
        let center = ShortcutCenter.shared
        let file = center.file(side)
        let issues = file.map { ShortcutConflicts.compute($0) } ?? [:]
        List {
            Section {
                Picker("Device", selection: $side) {
                    Label("Laptop", systemImage: "laptopcomputer").tag(Side.laptop)
                    Label("iPad", systemImage: "ipad.landscape").tag(Side.ipad)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if let note = center.note(side) {
                Section { Label(note, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }

            if let file {
                summary(file, issues)
                let groups = rows(file, issues)
                if groups.isEmpty {
                    Section { Text(conflictsOnly ? "No conflicts\(query.isEmpty ? "" : " match “\(query)”")." : "Nothing matches “\(query)”.").foregroundStyle(.secondary) }
                }
                ForEach(groups) { g in
                    Section {
                        if isOpen(g.name) {
                            ForEach(g.items) { s in
                                ShortcutRow(s: s, file: file, issues: issues[s.id] ?? [],
                                            edit: { editing = KeyEdit(side: side, shortcut: s, replacing: $0) },
                                            remove: { k in change(file) { $0.setKeys(s.id, s.keys.filter { $0 != k }) } },
                                            reset: { change(file) { $0.setKeys(s.id, s.defaults) } },
                                            pickGesture: { pick($0, for: s, in: file) })
                            }
                        }
                    } header: {
                        header(g, issues)
                    }
                }
            } else if side == .laptop {
                Section {
                    ContentUnavailableView("No laptop shortcuts yet", systemImage: "laptopcomputer",
                                           description: Text("The laptop's list appears here once Nexus on the laptop has run with this data folder (it writes shortcuts/laptop.yaml)."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, prompt: "Search names and keys")
        .navigationTitle("Shortcuts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset all") { confirmReset = true }
                    .disabled(!(file?.shortcuts.contains(where: \.isOverridden) ?? false))
            }
        }
        .confirmationDialog("Reset all of the \(side == .ipad ? "iPad" : "laptop")'s shortcuts?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset all", role: .destructive) { resetAll() }
        } message: {
            Text("Every key and gesture on the \(side == .ipad ? "iPad" : "laptop") goes back to its default.")
        }
        .confirmationDialog(gestureMove.map { "\($0.gesture) is on “\($0.holders.map(\.name).joined(separator: "”, “"))”" } ?? "",
                            isPresented: Binding(get: { gestureMove != nil }, set: { if !$0 { gestureMove = nil } }), titleVisibility: .visible) {
            if let m = gestureMove, let f = center.file(.ipad) {
                if m.to.keys.count == 1 {
                    Button("Swap (that one gets \(m.to.keys[0]))") { moveGesture(m, in: f, swap: true) }
                }
                Button("Move it to “\(m.to.name)”") { moveGesture(m, in: f, swap: false) }
                Button("Cancel", role: .cancel) { gestureMove = nil }
            }
        }
        .sheet(item: $editing) { e in KeyEditor(edit: e) }
        .alert("Couldn't do that", isPresented: Binding(get: { center.problem != nil }, set: { if !$0 { center.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(center.problem ?? "") }
    }

    // MARK: parts

    private func summary(_ f: ShortcutFile, _ issues: [String: [ShortcutIssue]]) -> some View {
        let n = ShortcutConflicts.errorCount(issues)
        let changed = f.shortcuts.filter(\.isOverridden).count
        return Section {
            HStack {
                if n > 0 {
                    Label(n == 1 ? "1 shortcut clashes" : "\(n) shortcuts clash", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else {
                    Label("No conflicts", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(f.shortcuts.count) shortcuts · \(changed) changed").font(.callout).foregroundStyle(.secondary)
            }
            Toggle("Conflicts only", isOn: $conflictsOnly)
        } footer: {
            if side == .ipad {
                Text("Tap a key to change it: press the new keys on the keyboard, or pick them. Hold ⌘ anywhere in Nexus to see them. Gestures work on a board; pick one per action.")
            } else {
                Text("The laptop's keys, from shortcuts/laptop.yaml. A change here edits just that shortcut's line, and the laptop picks it up. On this keyboard ⌘ counts as Ctrl; pick Win by hand.")
            }
        }
    }

    private func header(_ g: Rows, _ issues: [String: [ShortcutIssue]]) -> some View {
        let open = isOpen(g.name)
        let bad = g.items.filter { issues[$0.id]?.contains(where: \.isError) ?? false }.count
        return Button {
            toggle(g.name)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Text(g.name)
                Spacer()
                if bad > 0 { Label("\(bad)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                Text("\(g.items.count)").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(g.name), \(g.items.count) shortcuts, \(open ? "open" : "closed")")
    }

    // MARK: filtering and sections

    private func rows(_ f: ShortcutFile, _ issues: [String: [ShortcutIssue]]) -> [Rows] {
        f.groups.compactMap { name in
            let items = f.shortcuts.filter { s in
                s.group == name && matches(s, f) && (!conflictsOnly || (issues[s.id]?.contains(where: \.isError) ?? false))
            }
            return items.isEmpty ? nil : Rows(name: name, items: items)
        }
    }

    private func matches(_ s: Shortcut, _ f: ShortcutFile) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        if s.name.localizedCaseInsensitiveContains(q) || s.group.localizedCaseInsensitiveContains(q) { return true }
        if f.scopeName(s.scope).localizedCaseInsensitiveContains(q) { return true }
        let qk = ShortcutKeys.normalize(q, device: f.device).lowercased()
        return s.keys.contains { k in
            let n = ShortcutKeys.normalize(k, device: f.device).lowercased()
            return n.contains(q.lowercased()) || n.contains(qk) || ShortcutKeys.display(k, device: f.device, kind: s.kind).localizedCaseInsensitiveContains(q)
        }
    }

    private func groupKey(_ name: String) -> String { side.rawValue + ":" + name }

    private func isOpen(_ name: String) -> Bool {
        if !query.isEmpty || conflictsOnly { return true }
        return !closedGroups.split(separator: "|").contains(Substring(groupKey(name)))
    }

    private func toggle(_ name: String) {
        var set = Set(closedGroups.split(separator: "|").map(String.init))
        let k = groupKey(name)
        if set.contains(k) { set.remove(k) } else { set.insert(k) }
        withAnimation(.snappy) { closedGroups = set.sorted().joined(separator: "|") }
    }

    // MARK: changes

    private func change(_ f: ShortcutFile, _ body: (inout ShortcutFile) -> Void) {
        var copy = f
        body(&copy)
        ShortcutCenter.shared.apply(side, copy)
    }

    private func resetAll() {
        guard var f = ShortcutCenter.shared.file(side) else { return }
        for i in f.shortcuts.indices { f.shortcuts[i].keys = f.shortcuts[i].defaults }
        ShortcutCenter.shared.apply(side, f)
    }

    /// A gesture picked from a row's menu: off (nil), taken off this row, or put on it (asking first when another action has it).
    private func pick(_ g: String?, for s: Shortcut, in f: ShortcutFile) {
        guard let g else { change(f) { $0.setKeys(s.id, []) }; return }
        if s.keys.contains(g) { change(f) { $0.setKeys(s.id, s.keys.filter { $0 != g }) }; return }
        let holders = ShortcutConflicts.holders(f, binding: g, scope: s.scope, kind: s.kind, except: s.id)
        if holders.isEmpty { change(f) { $0.setKeys(s.id, s.keys + [g]) } } else { gestureMove = GestureMove(gesture: g, to: s, holders: holders) }
    }

    private func moveGesture(_ m: GestureMove, in f: ShortcutFile, swap: Bool) {
        var copy = f
        ShortcutConflicts.move(&copy, binding: m.gesture, to: m.to.id, replacing: swap ? m.to.keys.first : nil, from: m.holders.map(\.id), swap: swap)
        ShortcutCenter.shared.apply(.ipad, copy)
        gestureMove = nil
    }
}

// MARK: - a row

struct ShortcutRow: View {
    let s: Shortcut
    let file: ShortcutFile
    let issues: [ShortcutIssue]
    /// Change a binding (nil: add one).
    let edit: (String?) -> Void
    let remove: (String) -> Void
    let reset: () -> Void
    /// A gesture picked from the menu (nil: off).
    let pickGesture: (String?) -> Void

    var device: String { file.device }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name)
                if let place = place { Text(place).font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(issues.enumerated()), id: \.offset) { _, i in issueLine(i) }
            }
            Spacer(minLength: 8)
            if s.kind == .gesture { gestureMenu } else { chips }
            if s.isOverridden {
                Button(action: reset) {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reset to \(s.defaults.isEmpty ? "off" : s.defaults.map { ShortcutKeys.display($0, device: device, kind: s.kind) }.joined(separator: ", "))")
            }
        }
        .padding(.vertical, 2)
    }

    /// Where it works, when that isn't everywhere (and isn't already the section's name).
    private var place: String? {
        var parts: [String] = []
        if s.scope != "app", file.scopeName(s.scope) != s.group { parts.append(file.scopeName(s.scope)) }
        if s.kind == .hold { parts.append("Hold") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func bad(_ k: String) -> Bool {
        issues.contains { $0.isError && $0.binding == k }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            if s.keys.isEmpty {
                Button { edit(nil) } label: { KeyChip(text: "Off", muted: true) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(s.name): off. Add a key")
            }
            ForEach(Array(s.keys.enumerated()), id: \.offset) { _, k in
                Button { edit(k) } label: { KeyChip(text: ShortcutKeys.display(k, device: device), bad: bad(k)) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(s.name): \(k). Change it")
                    .contextMenu {
                        Button { edit(k) } label: { Label("Change…", systemImage: "keyboard") }
                        Button { edit(nil) } label: { Label("Add another key…", systemImage: "plus") }
                        Button(role: .destructive) { remove(k) } label: { Label("Remove this key", systemImage: "minus.circle") }
                    }
            }
            if !s.keys.isEmpty {
                Button { edit(nil) } label: { Image(systemName: "plus.circle").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Add another key for \(s.name)")
            }
        }
    }

    private var gestureMenu: some View {
        Menu {
            Button { pickGesture(nil) } label: {
                if s.keys.isEmpty { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(ShortcutRegistry.choices(for: s.id), id: \.self) { g in
                Button { pickGesture(g) } label: {
                    if s.keys.contains(g) {
                        Label(g, systemImage: "checkmark")
                    } else if let other = ShortcutConflicts.holders(file, binding: g, scope: s.scope, kind: .gesture, except: s.id).first {
                        Text("\(g) (now: \(other.name))")
                    } else {
                        Text(g)
                    }
                }
            }
        } label: {
            KeyChip(text: s.keys.isEmpty ? "Off" : s.keys.joined(separator: ", "), muted: s.keys.isEmpty, bad: s.keys.contains(where: bad))
        }
        .accessibilityLabel("\(s.name): \(s.keys.isEmpty ? "off" : s.keys.joined(separator: ", ")). Pick a gesture")
    }

    private func issueLine(_ i: ShortcutIssue) -> some View {
        let other = i.other.flatMap { file[$0]?.name } ?? ""
        let b = ShortcutKeys.display(i.binding, device: device, kind: s.kind)
        let inner = i.scope.map { lowerFirst(file.scopeName($0)) } ?? ""
        let (text, icon, color): (String, String, Color) = {
            switch i.kind {
            case .conflict: return ("\(b) is also “\(other)”", "exclamationmark.triangle.fill", .red)
            case .reserved: return ("\(b) is kept by \(device == "ipad" ? "iPadOS" : "Windows")", "exclamationmark.triangle.fill", .red)
            case .takesOver: return ("\(b) takes over from “\(other)” \(inner)", "arrow.turn.down.right", .secondary)
            case .takenOver: return ("\(b): “\(other)” takes over \(inner)", "arrow.turn.down.right", .secondary)
            case .shadowed:
                let where_ = i.other.flatMap { file[$0]?.scope }.map { file.scopeName($0) } ?? ""
                return ("\(b): “\(other)” (\(where_)) gets it first", "exclamationmark.circle", .orange)
            }
        }()
        return Label(text, systemImage: icon).font(.caption).foregroundStyle(color)
    }

    private func lowerFirst(_ s: String) -> String { s.prefix(1).lowercased() + s.dropFirst() }
}

/// A key or gesture, as a small key cap.
struct KeyChip: View {
    let text: String
    var muted = false
    var bad = false

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(muted ? Color.secondary : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(.tertiarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(bad ? Color.red : Color(.separator), lineWidth: bad ? 1.5 : 0.5))
    }
}

// MARK: - changing a key

/// One key of one shortcut: press it on the keyboard, or pick modifiers and a key. When the shortcut next to it in the same place
/// already has it, Swap or Replace (or Cancel).
struct KeyEditor: View {
    let edit: ShortcutsView.KeyEdit
    @Environment(\.dismiss) private var dismiss
    @State private var mods: Set<String> = []
    @State private var key: String?
    @State private var recorded = false

    init(edit: ShortcutsView.KeyEdit) {
        self.edit = edit
        let device = edit.side == .ipad ? "ipad" : "laptop"
        if let r = edit.replacing {
            let p = ShortcutKeys.parts(r, device: device)
            _mods = State(initialValue: Set(p.mods))
            _key = State(initialValue: p.key)
        }
    }

    var device: String { edit.side == .ipad ? "ipad" : "laptop" }
    var file: ShortcutFile? { ShortcutCenter.shared.file(edit.side) }
    var hasKeyboard: Bool { GCKeyboard.coalesced != nil }

    /// What the chosen keys make, or nil while there is no key (a hold key may be modifiers only).
    var newKey: String? {
        if key == nil && !(edit.shortcut.kind == .hold && !mods.isEmpty) { return nil }
        return ShortcutKeys.make(mods: mods, key: key, device: device)
    }

    var body: some View {
        let nk = newKey
        let holders = nk.flatMap { k in file.map { ShortcutConflicts.holders($0, binding: k, scope: edit.shortcut.scope, kind: edit.shortcut.kind, except: edit.shortcut.id) } } ?? []
        let sameAsBefore = nk != nil && nk == edit.replacing.map { ShortcutKeys.normalize($0, device: device) }
        NavigationStack {
            Form {
                Section {
                    KeyRecorder(device: device) { b in
                        let p = ShortcutKeys.parts(b, device: device)
                        mods = Set(p.mods)
                        key = p.key
                        recorded = true
                    }
                    .frame(height: 70)
                } header: {
                    Text(edit.shortcut.name)
                } footer: {
                    if !hasKeyboard {
                        Text("No keyboard is connected: pick the keys below.")
                    } else if device != "ipad" {
                        Text("On this keyboard ⌘ counts as Ctrl. For Win, pick it below.")
                    } else {
                        Text("iPadOS keeps a few keys for itself (⌘Tab, ⌘Space, ⌘H, Globe keys): those never reach Nexus.")
                    }
                }

                Section("Or pick") {
                    ForEach(ShortcutKeys.modifiers(device: device), id: \.self) { m in
                        Toggle(modifierName(m), isOn: Binding(get: { mods.contains(m) }, set: { on in
                            if on { mods.insert(m) } else { mods.remove(m) }
                        }))
                    }
                    Picker("Key", selection: $key) {
                        Text(edit.shortcut.kind == .hold ? "None (the modifiers only)" : "Choose…").tag(String?.none)
                        ForEach(KeyMap.pickable(device: device), id: \.self) { k in
                            Text(keyName(k)).tag(String?.some(k))
                        }
                    }
                }

                if let nk {
                    Section {
                        HStack {
                            Text(edit.replacing == nil ? "New key" : "Becomes")
                            Spacer()
                            if let old = edit.replacing {
                                KeyChip(text: ShortcutKeys.display(old, device: device), muted: true)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            }
                            KeyChip(text: ShortcutKeys.display(nk, device: device), bad: !holders.isEmpty)
                        }
                        if edit.shortcut.kind != .gesture, ShortcutConflicts.isReserved(nk, device: device),
                           device == "ipad" || edit.shortcut.scope == "system" {
                            Label("\(device == "ipad" ? "iPadOS" : "Windows") keeps this key for itself, so it would never reach Nexus.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                        if !holders.isEmpty && !sameAsBefore {
                            Label("“\(holders.map(\.name).joined(separator: "”, “"))” \(holders.count == 1 ? "has" : "have") this key \(placeText).", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            if let old = edit.replacing {
                                Button("Swap: “\(holders[0].name)” gets \(ShortcutKeys.display(old, device: device))") { save(take: holders, swap: true) }
                            }
                            Button("Replace: take it from “\(holders[0].name)”\(holders.count > 1 ? " and the others" : "")") { save(take: holders, swap: false) }
                            Button("Cancel", role: .cancel) { dismiss() }
                        }
                    }
                }
            }
            .navigationTitle(edit.replacing == nil ? "Add a key" : "Change the key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(take: [], swap: false) }
                        .disabled(nk == nil || (!holders.isEmpty && !sameAsBefore))
                }
            }
        }
    }

    private var placeText: String {
        guard let f = file else { return "here" }
        let name = f.scopeName(edit.shortcut.scope)
        return name.prefix(1).lowercased() + name.dropFirst()
    }

    private func save(take holders: [Shortcut], swap: Bool) {
        guard var f = file, let nk = newKey else { return }
        ShortcutConflicts.move(&f, binding: nk, to: edit.shortcut.id, replacing: edit.replacing, from: holders.map(\.id), swap: swap)
        ShortcutCenter.shared.apply(edit.side, f)
        dismiss()
    }

    private func modifierName(_ m: String) -> String {
        guard device == "ipad" else { return m == "Win" ? "Win (Windows key)" : m }
        switch m {
        case "Cmd": return "⌘ Command"
        case "Ctrl": return "⌃ Control"
        case "Alt": return "⌥ Option"
        case "Shift": return "⇧ Shift"
        default: return m
        }
    }

    private func keyName(_ k: String) -> String {
        let shown = ShortcutKeys.display(k, device: device)
        return shown == k ? k : "\(shown)  \(k)"
    }
}

/// Where a key is pressed to record it: it takes the keyboard while it is on screen (the app's own keys stand aside meanwhile).
struct KeyRecorder: UIViewRepresentable {
    let device: String
    let onKey: (String) -> Void

    func makeUIView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.device = device
        v.onKey = onKey
        return v
    }

    func updateUIView(_ v: RecorderView, context: Context) {
        v.device = device
        v.onKey = onKey
    }

    static func dismantleUIView(_ v: RecorderView, coordinator: ()) {
        ShortcutCenter.shared.capturing = false
    }
}

final class RecorderView: UIView {
    var device = "ipad"
    var onKey: ((String) -> Void)?
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus)))
        isAccessibilityElement = true
        accessibilityTraits = .button
        show()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { DispatchQueue.main.async { [weak self] in _ = self?.becomeFirstResponder() } }
    }

    @objc private func focus() { _ = becomeFirstResponder() }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { ShortcutCenter.shared.capturing = true }
        show()
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        ShortcutCenter.shared.capturing = false
        show()
        return ok
    }

    private func show() {
        label.text = isFirstResponder ? "Press the new keys on the keyboard…" : "Tap here, then press the new keys"
        label.textColor = isFirstResponder ? .label : .secondaryLabel
        accessibilityLabel = label.text
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var took = false
        for p in presses {
            if let k = p.key, let b = KeyMap.binding(k, device: device) {
                onKey?(b)
                took = true
            }
        }
        if took {
            label.text = "Got it. Press another to change it."
        } else {
            super.pressesBegan(presses, with: event)
        }
    }

    // nothing else (Copy, Undo…) runs while a key is being recorded
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}
