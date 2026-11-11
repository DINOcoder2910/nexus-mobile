import SwiftUI
import NexusCore

/// The Planner: put tasks on days. A few days side by side (3 days or a week) that roll with Today and ‹ ›, what slipped in a
/// strip at the top, and the task bank of unplanned tasks below, to drag onto a day.
struct PlannerView: View {
    @Environment(NexusStore.self) private var store
    /// 3 or 7 days.
    @AppStorage("plannerSpan") private var span = 3
    @AppStorage("plannerBankOpen") private var bankOpen = true
    /// The first day shown; nil follows today.
    @State private var start: String?
    /// The day a drag is over, to highlight its column.
    @State private var targetDay: String?
    @State private var bankTargeted = false

    private let pad: CGFloat = 16
    private let gap: CGFloat = 10

    private var first: String { start ?? store.today }
    private var days: [String] { (0..<max(1, span)).map { Days.add(first, $0) } }

    var body: some View {
        let p = store.planning
        let shown = days
        GeometryReader { geo in
            let n = CGFloat(shown.count)
            let fit = (geo.size.width - pad * 2 - gap * (n - 1)) / n
            let colW = max(180, fit)
            let colH = max(380, geo.size.height * 0.6)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    if !p.slipped.isEmpty { slippedStrip(p) }
                    rangeLine(shown)
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: gap) {
                            ForEach(shown, id: \.self) { day in
                                dayColumn(day, p: p, shown: shown, width: colW, height: colH)
                            }
                        }
                        .padding(.horizontal, pad)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    bankSection(p, shown: shown)
                }
                .padding(.vertical, 12)
            }
            .refreshable { store.reload() }
        }
        .navigationTitle("Planner")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Picker("Days", selection: $span) {
                    Text("3 days").tag(3)
                    Text("Week").tag(7)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("One day earlier")
                Button("Today") { start = nil }
                    .disabled(first == store.today)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("One day later")
            }
        }
    }

    private func step(_ n: Int) {
        let next = Days.add(first, n)
        start = next == store.today ? nil : next
    }

    // MARK: the days

    private func rangeLine(_ shown: [String]) -> some View {
        HStack(spacing: 8) {
            Text("\(Days.label(shown.first ?? first)) – \(Days.label(shown.last ?? first))")
                .font(.subheadline.weight(.semibold))
            Text("Drag a task onto a day.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, pad)
    }

    private func dayColumn(_ day: String, p: Planning, shown: [String], width: CGFloat, height: CGFloat) -> some View {
        let isToday = day == store.today
        let tasks = p.planned(on: day)
        let deadlines = p.due(on: day)
        let targeted = targetDay == day
        return VStack(spacing: 0) {
            dayHeader(day, isToday: isToday, load: p.load(on: day))
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(deadlines) { t in deadlineRow(t, day: day) }
                    if !deadlines.isEmpty && !tasks.isEmpty { Divider() }
                    ForEach(tasks) { t in
                        TaskRow(task: t, day: day, showWorkstream: true, showCrumb: true, compact: true)
                    }
                    if tasks.isEmpty {
                        Text("Nothing planned")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, deadlines.isEmpty ? 24 : 8)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: width, height: height)
        .background(targeted ? Theme.accent.opacity(0.08) : Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(targeted ? Theme.accent : (isToday ? Theme.accent.opacity(0.35) : Color.clear), lineWidth: targeted ? 2 : 1)
        )
        .dropDestination(for: String.self) { ids, _ in
            drop(ids, on: day, shown: shown)
        } isTargeted: { on in
            if on { targetDay = day } else if targetDay == day { targetDay = nil }
        }
    }

    private func dayHeader(_ day: String, isToday: Bool, load: Double) -> some View {
        let parts = Days.label(day).split(separator: " ", maxSplits: 1)
        let weekday = parts.first.map { String($0) } ?? day
        let date = parts.count > 1 ? String(parts[1]) : ""
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(weekday)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isToday ? Theme.accent : .secondary)
            Text(date)
                .font(.subheadline.weight(isToday ? .semibold : .regular))
                .foregroundStyle(isToday ? Theme.accent : .primary)
            Spacer(minLength: 4)
            if load > 0 {
                Text(hoursText(load)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Button {
                store.capture = .init(workstream: nil, parent: nil, plan: day)
            } label: {
                Image(systemName: "plus").font(.subheadline)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add a task on \(Days.label(day))")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// A deadline that day: a small flag row, key ones bold with ★. Tap opens the task.
    private func deadlineRow(_ t: NexusTask, day: String) -> some View {
        let late = day < store.today
        return Button { store.open(t) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "flag.fill").imageScale(.small)
                    .foregroundStyle(late ? Theme.late : (t.key ? Theme.key : Theme.soon))
                Text(t.key ? "★ " + t.text : t.text)
                    .font(.caption.weight(t.key ? .bold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Deadline: \(t.text)")
    }

    // MARK: dropping

    /// A task dropped on a day: moved from the day it came from when that can be told, else that day is added.
    private func drop(_ ids: [String], on day: String, shown: [String]) -> Bool {
        var done = false
        for id in ids {
            guard let t = store.task(id), store.canEdit(t) else { continue }
            let from = source(of: t, target: day, shown: shown)
            if from == nil && t.plannedDays.contains(day) { continue }
            withAnimation(.snappy) { store.move(t, from: from, to: day) }
            done = true
        }
        targetDay = nil
        return done
    }

    /// The drag carries only the id, so the day it came from is guessed: another day shown here, else its latest past day
    /// when it only has past days (it slipped), else none.
    private func source(of t: NexusTask, target: String, shown: [String]) -> String? {
        if let d = shown.first(where: { $0 != target && t.plannedDays.contains($0) }) { return d }
        let days = t.plannedDays
        if !days.isEmpty, days.allSatisfy({ $0 < store.today }) { return days.max() }
        return nil
    }

    // MARK: slipped

    private func slippedStrip(_ p: Planning) -> some View {
        let slipped = p.slipped
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionTitle(title: "Slipped", count: slipped.count)
                Text("Planned for an earlier day and not done")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Move all to today") { moveAllToToday(slipped) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, pad)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(slipped) { t in slippedCard(t) }
                }
                .padding(.horizontal, pad)
            }
        }
    }

    private func slippedCard(_ t: NexusTask) -> some View {
        let last = t.plannedDays.filter { $0 < store.today }.max()
        let editable = store.canEdit(t)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(store.color(t)).frame(width: 8, height: 8).padding(.top, 5)
                Text(t.text).font(.subheadline).lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { store.setPlan(t, t.plan.filter { $0.day >= store.today }) }
                } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!editable)
                .accessibilityLabel("Back to the bank")
            }
            HStack {
                if let last {
                    Text("Was \(Days.label(last))").font(.caption).foregroundStyle(Theme.late)
                }
                Spacer(minLength: 0)
                Button("Today") {
                    withAnimation(.snappy) { store.move(t, from: last, to: store.today) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!editable)
            }
        }
        .padding(10)
        .frame(width: 230, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { store.open(t) }
        .draggable(t.id) {
            Text(t.text).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Each edit reloads the folder, so every task is read again before it is moved.
    private func moveAllToToday(_ slipped: [NexusTask]) {
        withAnimation(.snappy) {
            for id in slipped.map(\.id) {
                guard let t = store.task(id), store.canEdit(t) else { continue }
                let last = t.plannedDays.filter { $0 < store.today }.max()
                store.move(t, from: last, to: store.today)
            }
        }
    }

    // MARK: the task bank

    private struct BankGroup: Identifiable {
        let id: String
        let workstream: String?
        let name: String
        var tasks: [NexusTask]
    }

    /// The bank by workstream, in file order (the Inbox is "Inbox").
    private func bankGroups(_ bank: [NexusTask]) -> [BankGroup] {
        var out: [BankGroup] = []
        var index: [String: Int] = [:]
        for t in bank {
            let key = t.workstream ?? ""
            if let i = index[key] {
                out[i].tasks.append(t)
            } else {
                index[key] = out.count
                out.append(BankGroup(id: key.isEmpty ? "inbox" : key, workstream: t.workstream,
                                     name: store.workstream(t.workstream)?.name ?? "Inbox", tasks: [t]))
            }
        }
        return out
    }

    /// How far each bank task is indented: one step under a parent that is in the bank too.
    private func indents(_ bank: [NexusTask]) -> [String: Int] {
        var out: [String: Int] = [:]
        for t in bank {
            if let parent = t.parent, let up = out[parent] { out[t.id] = up + 1 } else { out[t.id] = 0 }
        }
        return out
    }

    private func bankSection(_ p: Planning, shown: [String]) -> some View {
        let bank = p.bank
        let groups = bankGroups(bank)
        let indent = indents(bank)
        let inBank = Set(bank.map(\.id))
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { bankOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(bankOpen ? 90 : 0))
                    SectionTitle(title: "Task bank", count: bank.count)
                    Text("Not planned for today or later")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, pad)

            if bankOpen {
                if bank.isEmpty {
                    EmptyNote(title: "The bank is empty", detail: "Every open task is planned.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)],
                              alignment: .leading, spacing: 14) {
                        ForEach(groups) { g in
                            bankCard(g, indent: indent, inBank: inBank)
                        }
                    }
                    .padding(.horizontal, pad)
                }
            }
        }
        .padding(.vertical, 6)
        .background(bankTargeted ? Theme.accent.opacity(0.06) : Color.clear)
        // Dropping a planned task back on the bank takes it off the day it was shown on.
        .dropDestination(for: String.self) { ids, _ in
            var done = false
            for id in ids {
                guard let t = store.task(id), store.canEdit(t),
                      let day = shown.first(where: { t.plannedDays.contains($0) }) else { continue }
                withAnimation(.snappy) { store.unplan(t, from: day) }
                done = true
            }
            return done
        } isTargeted: { bankTargeted = $0 }
    }

    private func bankCard(_ g: BankGroup, indent: [String: Int], inBank: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(store.color(workstream: g.workstream)).frame(width: 8, height: 8)
                Text(g.name).font(.subheadline.weight(.semibold))
                Text("\(g.tasks.count)").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 2)
            ForEach(g.tasks) { t in
                let level = indent[t.id] ?? 0
                // A subtask whose parent is not in the bank shows its parent's name instead.
                let crumb = t.parent.map { !inBank.contains($0) } ?? false
                TaskRow(task: t, day: nil, showWorkstream: false, showCrumb: crumb, compact: true)
                    .padding(.leading, CGFloat(level) * 18)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
