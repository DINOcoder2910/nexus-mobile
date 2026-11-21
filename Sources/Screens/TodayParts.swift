import SwiftUI
import NexusCore
import UniformTypeIdentifiers

// Today's parts, as the new laptop app draws them (nexus desktop/src/screens/Today.tsx and planning.css): the Key date countdowns,
// From Study, Next up, a row of your list, the day's hours, Slipped and the look at tomorrow.

/// Minutes and times as the new look says them (the laptop's dates.ts).
enum TimeWords {
    /// 90 as "1h 30m", 45 as "45m", 120 as "2h"; 0 as "".
    static func dur(_ min: Int) -> String {
        guard min > 0 else { return "" }
        let h = min / 60, m = min % 60
        return h > 0 ? (m > 0 ? "\(h)h \(m)m" : "\(h)h") : "\(m)m"
    }
    /// Rounded to the quarter hour: "6h 15m".
    static func about(_ min: Int) -> String {
        let r = Int((Double(min) / 15).rounded()) * 15
        return r > 0 ? dur(r) : "0m"
    }
    /// 630 as "10:30", 960 as "4:00": the day's own clock, no am/pm.
    static func clock(_ min: Int) -> String {
        let h = (min / 60) % 12
        return "\(h == 0 ? 12 : h):" + String(format: "%02d", min % 60)
    }
    /// 1170 as "7:30pm", 540 as "9am".
    static func clockAp(_ min: Int) -> String {
        let h24 = (min / 60) % 24, m = min % 60, h = h24 % 12
        return "\(h == 0 ? 12 : h)" + (m > 0 ? ":" + String(format: "%02d", m) : "") + (h24 < 12 ? "am" : "pm")
    }
    /// "HH:MM" for minutes.
    static func hm(_ min: Int) -> String { String(format: "%02d:%02d", (min / 60) % 24, min % 60) }
    /// Hours to the half hour: "4.5h".
    static func hours(_ min: Int) -> String {
        let h = (Double(min) / 30).rounded() / 2
        return (h == h.rounded() ? String(Int(h)) : String(h)) + "h"
    }
    /// "today", "tomorrow", "Sun", or "Thu 26 Nov" further out.
    static func dayName(_ iso: String, today: String) -> String {
        let n = Days.between(today, iso)
        if n == 0 { return "today" }
        if n == 1 { return "tomorrow" }
        if n == -1 { return "yesterday" }
        return n > 1 && n < 7 ? TodayView.weekday(iso, short: true) : Days.label(iso)
    }
    /// A deadline as a list says it: "due Sun", "due today" (near), "2 days late" (late).
    static func due(_ iso: String, today: String) -> (text: String, late: Bool, near: Bool) {
        let n = Days.between(today, iso)
        if n < 0 { return ("\(-n) day\(n == -1 ? "" : "s") late", true, false) }
        return ("due " + dayName(iso, today: today), false, n == 0)
    }
}

/// A part's heading: "Key dates  starred, soonest first".
struct SectionHead: View {
    var title: String
    var note: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.nx(.headline, .semibold)).foregroundStyle(Kit.ink)
            if let note { Text(note).font(.nx(.subheadline)).foregroundStyle(Kit.faint) }
        }
    }
}

/// A quiet sentence on the rest tone, where a part has nothing to show.
struct QuietCard: View {
    var text: String
    var body: some View {
        Text(text).font(.nx(.callout)).foregroundStyle(Kit.faint)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .kitSurface(Kit.rests, radius: 16)
    }
}

/// A subject's colour dot.
struct SubjectDot: View {
    var color: Color
    var size: CGFloat = 7
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: Key dates

/// A starred deadline counting down: its subject, its title, "6 days" and six bars that fill as it comes near.
struct KeyDateCard: View {
    @Environment(NexusStore.self) private var store
    let k: TodayPlan.KeyDate

    var body: some View {
        let n = k.days
        let filled = max(0, min(6, Int(((14 - Double(min(max(n, 0), 14))) / 14 * 6).rounded())))
        let color = store.color(k.task)
        Button { store.open(k.task) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    SubjectDot(color: color)
                    Text(store.workstreamName(k.task)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("★").foregroundStyle(Theme.key)
                }
                .font(.nx(.caption)).foregroundStyle(Kit.muted)
                Text(k.task.text).font(.nx(.subheadline, .medium)).foregroundStyle(Kit.ink).lineLimit(2).multilineTextAlignment(.leading)
                    .padding(.top, 4).padding(.bottom, 6)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(n < 0 ? "\(-n) day\(n == -1 ? "" : "s") late" : n == 0 ? "Today" : n == 1 ? "Tomorrow" : "\(n) days")
                        .font(.nx(size: 22, .bold, display: true))
                        .foregroundStyle(n < 0 ? Theme.late : n <= 3 ? Theme.soon : Kit.ink)
                    Text(Days.label(k.task.due ?? "")).font(.nx(.caption)).foregroundStyle(Kit.faint)
                }
                Spacer(minLength: 10)
                HStack(spacing: 3) {
                    ForEach(0..<6, id: \.self) { i in
                        Capsule().fill(i < filled ? color : Kit.selected).frame(height: 5)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .kitSurface(Kit.rests, radius: 16)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("key-date")
    }
}

// MARK: From Study

struct StudyDue: Identifiable {
    var workstream: Workstream
    var count: Int
    var decks: [String]
    var id: String { workstream.id }
}

/// "12 cards due · Ions, Acids and bases · about 8 min" with Review, which opens the subject's Study.
struct StudyDueCard: View {
    @Environment(NexusStore.self) private var store
    let item: StudyDue
    var open: () -> Void

    var body: some View {
        let color = store.color(workstream: item.workstream.id)
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.count) card\(item.count == 1 ? "" : "s") due").font(.nx(.body, .medium)).foregroundStyle(Kit.ink)
                Text(item.decks.joined(separator: ", ") + " · about \((item.count * 2 + 2) / 3) min")
                    .font(.nx(.caption)).foregroundStyle(Kit.faint).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Review", action: open).buttonStyle(KitButtonStyle(kind: .primary, small: true))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .kitSurface(Kit.rests, radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("study-cards")
    }
}

// MARK: Next up

/// The task on now or next, in its subject's wash: "NEXT UP · 10:30, IN 15 MIN", its title, and Start (a time now and the timer).
struct NextUpCard: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let v: TodayPlan.Day

    var body: some View {
        let color = store.color(task)
        let start = TodayPlan.clock(v.time(task))
        let running = TimeTracker.shared.isRunning(task.id)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { words(color, start); Spacer(minLength: 8); actions(start, running) }
            VStack(alignment: .leading, spacing: 12) { words(color, start); actions(start, running) }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { store.open(task) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("next-up")
    }

    private func words(_ color: Color, _ start: Int?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(when(start)).font(.nx(.caption, .semibold)).tracking(0.3).foregroundStyle(color)
            Text(task.text).font(.nx(size: 22, .semibold, display: true)).foregroundStyle(Kit.ink).lineLimit(2)
            HStack(spacing: 12) {
                HStack(spacing: 5) { SubjectDot(color: color); Text(store.workstreamName(task)) }
                let m = TodayPlan.minutes(task)
                if m > 0 { Text(TimeWords.dur(m)) }
                if let d = task.due {
                    let w = TimeWords.due(d, today: v.today)
                    Text(w.text).foregroundStyle(w.late ? Theme.late : Kit.muted)
                }
            }
            .font(.nx(.footnote)).foregroundStyle(Kit.muted)
        }
    }

    @ViewBuilder
    private func actions(_ start: Int?, _ running: Bool) -> some View {
        if store.canEdit(task) {
            if running {
                Button { TimeTracker.shared.toggle(task, store: store) } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.kit)
            } else if start == nil || start! > v.now {
                Button {
                    // a time now (to the five minutes) and the timer on it
                    store.setTime(task, on: v.today, TimeWords.hm(v.now / 5 * 5))
                    TimeTracker.shared.start(task, store: store)
                } label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(.kitPrimary)
                .accessibilityIdentifier("next-start")
            }
        }
    }

    private func when(_ start: Int?) -> String {
        guard let s = start else { return "NEXT UP" }
        let d = s - v.now
        if d <= 0 { return "NOW · SINCE \(TimeWords.clock(s))" }
        return "NEXT UP · \(TimeWords.clock(s)), IN " + (d < 60 ? "\(d) MIN" : TimeWords.dur(d).uppercased())
    }
}

// MARK: a row of your list

/// One task of Today's list: tick, title and its deadline, then its subject, estimate and time (or Claude's suggested time).
struct TodayRow: View {
    @Environment(NexusStore.self) private var store
    let task: NexusTask
    let v: TodayPlan.Day
    let suggestion: TodayPlan.Suggestion?
    var repeating = false

    var body: some View {
        let color = store.color(task)
        let m = TodayPlan.minutes(task)
        HStack(spacing: 12) {
            TickRing(task: task)
            if Device.isPhone {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    HStack(spacing: 6) {
                        SubjectDot(color: color, size: 6)
                        Text(([store.workstreamName(task), TimeWords.dur(m), note?.text].compactMap { $0 }.filter { !$0.isEmpty }).joined(separator: " · "))
                            .lineLimit(1)
                    }
                    .font(.nx(.caption)).foregroundStyle(Kit.faint)
                }
                Spacer(minLength: 6)
                time.frame(minWidth: 44, alignment: .trailing)
            } else {
                title
                if let n = note {
                    Text(n.text).font(.nx(.footnote)).foregroundStyle(n.late ? Theme.late : n.near ? Theme.soon : Kit.faint).lineLimit(1).fixedSize()
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) { SubjectDot(color: color); Text(store.workstreamName(task)).lineLimit(1) }
                    .font(.nx(.footnote)).foregroundStyle(Kit.faint)
                Text(TimeWords.dur(m)).font(.nx(.footnote)).foregroundStyle(Kit.faint).frame(width: 52, alignment: .trailing)
                time.frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .opacity(task.done ? 0.5 : 1)
        .background(Kit.page)
        .contentShape(Rectangle())
        .onTapGesture { store.open(task) }
        .contextMenu { TaskMenu(task: task, day: v.today) }
        .draggable(task.id) {
            HStack(spacing: 7) { SubjectDot(color: color); Text(task.text).font(.nx(.subheadline, .medium)) }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Kit.page, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var note: (text: String, late: Bool, near: Bool)? {
        if task.done { return ("done", false, false) }
        if repeating, let r = task.every { return (r.text.lowercased(), false, false) }
        return task.due.map { TimeWords.due($0, today: v.today) }
    }

    private var title: some View {
        ((task.key ? Text("★ ").foregroundColor(Theme.key) : Text(""))
            + Text(task.text).foregroundColor(Kit.ink).strikethrough(task.done, color: Kit.muted))
            .font(.nx(size: 15.5, .regular)).lineLimit(1)
    }
}

private extension TodayRow {
    var time: some View {
        Group {
            if let t = TodayPlan.clock(v.time(task)) {
                Text(TimeWords.clock(t)).font(.nx(.subheadline, .medium)).foregroundStyle(Kit.ink)
            } else if let s = suggestion {
                Label(TimeWords.clock(s.span.start), systemImage: "sparkles").labelStyle(.titleAndIcon)
                    .font(.nx(.subheadline, .medium)).foregroundStyle(Theme.claude)
            } else {
                Text("–").font(.nx(.subheadline)).foregroundStyle(.clear)
            }
        }
    }
}

// MARK: The day

/// Today's hours from 8 am to 10 pm: events, timed tasks in their subject's wash, the free stretches hatched, Claude's suggested times
/// (Accept), and the line for now. Drop a task on an hour to give it that time.
struct DayCard: View {
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var cal
    let v: TodayPlan.Day
    @Binding var eventSheet: EventSheet?
    @State private var showEvents = true
    @State private var dropAt: Int?
    @State private var dragging: String?

    static let h0 = 8, h1 = 22
    static let px: CGFloat = 40, inset: CGFloat = 8, labels: CGFloat = 46
    static func y(_ m: Int) -> CGFloat { inset + CGFloat(m - h0 * 60) / 60 * px }
    static func minute(_ y: CGFloat) -> Int {
        let m = Double(h0 * 60) + Double(y - inset) / Double(px) * 60
        return min(max(Int((m / 15).rounded()) * 15, h0 * 60), h1 * 60 - 15)
    }

    private struct Block { var id: String; var start: Int; var end: Int; var kind: Kind }
    private enum Kind { case event(CalEvent), task(NexusTask), suggestion(TodayPlan.Suggestion) }

    var body: some View {
        let allEvents = TodayEvents.spans(cal, v.today)
        let events = showEvents ? allEvents : []
        let allDay = TodayEvents.allDay(cal, v.today)
        let timed: [Block] = (v.list + v.done).compactMap { t in
            guard let s = TodayPlan.clock(v.time(t)) else { return nil }
            let m = TodayPlan.minutes(t)
            return Block(id: "t" + t.id, start: s, end: s + (m > 0 ? m : TodayPlan.defaultBlock), kind: .task(t))
        }
        let blocks: [Block] = events.enumerated().map { Block(id: "e\($0.offset)", start: $0.element.start, end: $0.element.end, kind: .event($0.element.event)) }
            + timed + v.suggestions.map { Block(id: "s" + $0.id, start: $0.span.start, end: $0.span.end, kind: .suggestion($0)) }
        let hit = { (a: Int, b: Int, c: Int, d: Int) in a < d && c < b }
        let free = v.gaps.filter { g in
            g.minutes >= 30 && !blocks.contains { b in
                if case .task(let t) = b.kind, t.done { return false }
                return hit(g.start, g.end, b.start, b.end)
            }
        }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("The day").font(.nx(size: 17, .semibold, display: true)).foregroundStyle(Kit.ink)
                Spacer()
                if !v.suggestions.isEmpty {
                    Button { withAnimation(Kit.spring) { for s in v.suggestions { accept(s) } } } label: {
                        Label("Use these times", systemImage: "sparkles")
                    }
                    .buttonStyle(KitButtonStyle(kind: .claude, small: true))
                    .accessibilityIdentifier("use-times")
                }
                Button { withAnimation(Kit.snap) { showEvents.toggle() } } label: {
                    HStack(spacing: 3) { Text("Events"); if showEvents { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) } }
                }
                .font(.nx(.caption)).foregroundStyle(Kit.faint).buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            (Text("\(allEvents.count) event\(allEvents.count == 1 ? "" : "s")").foregroundColor(Kit.muted).fontWeight(.medium)
                + Text(" · \(timed.count) timed · \(TimeWords.about(v.freeLeft)) free"))
                .font(.nx(.caption)).foregroundStyle(Kit.faint)
                .padding(.horizontal, 8).padding(.top, 2).padding(.bottom, 8)
            if !allDay.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(allDay) { e in
                            Text(e.title).font(.nx(.caption, .medium)).foregroundStyle(Kit.ink)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(e.color.opacity(0.16), in: Capsule())
                                .onTapGesture { eventSheet = .show(e.event) }
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.bottom, 6)
            }
            hours(blocks, free)
        }
        .padding(.top, 16).padding(.bottom, 12).padding(.leading, 6).padding(.trailing, 10)
        .kitSurface(Kit.rests, radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day-card")
    }

    private func hours(_ blocks: [Block], _ free: [TodayPlan.Span]) -> some View {
        let placed = Dictionary(uniqueKeysWithValues: DayLayout.place(blocks.map { DayLayout.Span(id: $0.id, start: $0.start, end: $0.end) }).map { ($0.id, $0) })
        let height = Self.y(Self.h1 * 60) + 8
        return GeometryReader { g in
            let left = Self.labels + 6, width = g.size.width - left - 2
            ZStack(alignment: .topLeading) {
                ForEach(Self.h0...Self.h1, id: \.self) { h in
                    Text("\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "am" : "pm")").font(.nx(size: 11)).foregroundStyle(Kit.faint)
                        .offset(x: 6, y: Self.y(h * 60) - 8)
                    Rectangle().fill(Kit.ink.opacity(0.06)).frame(width: g.size.width - Self.labels, height: 1)
                        .offset(x: Self.labels, y: Self.y(h * 60))
                }
                ForEach(free, id: \.start) { s in
                    Text(TimeWords.about(s.minutes) + " free").font(.nx(size: 11.5)).foregroundStyle(Kit.faint)
                        .padding(.leading, 10)
                        .frame(width: width, height: blockHeight(s.start, s.end), alignment: .leading)
                        .background(Hatch().stroke(Kit.ink.opacity(0.05), lineWidth: 1).clipShape(RoundedRectangle(cornerRadius: 8)))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Kit.ink.opacity(0.05)))
                        .offset(x: left, y: Self.y(s.start) + 1)
                }
                ForEach(blocks, id: \.id) { b in
                    let p = placed[b.id]
                    let cols = CGFloat(max(p?.columns ?? 1, 1)), col = CGFloat(p?.column ?? 0)
                    let w = (width - (cols - 1) * 4) / cols
                    block(b).frame(width: w, height: blockHeight(b.start, b.end), alignment: .topLeading)
                        .offset(x: left + col * (w + 4), y: Self.y(b.start) + 1)
                }
                if let m = dropAt {
                    let t = store.task(dragging)
                    let e = m + max(t.map(TodayPlan.minutes) ?? 0, TodayPlan.defaultBlock)
                    HStack(spacing: 7) {
                        if let t { SubjectDot(color: store.color(t)); Text(t.text).lineLimit(1) } else { Text("Drop here").lineLimit(1) }
                        Spacer(minLength: 4)
                        Text("\(TimeWords.clock(m)) – \(TimeWords.clock(e))").font(.nx(size: 11, .semibold)).foregroundStyle(Theme.accent)
                    }
                    .font(.nx(size: 12.5, .medium)).foregroundStyle(Kit.ink).padding(.horizontal, 9)
                    .frame(width: width, height: blockHeight(m, e))
                    .background(Kit.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .offset(x: left, y: Self.y(m) + 1)
                    .allowsHitTesting(false)
                }
                if v.now >= Self.h0 * 60 && v.now <= Self.h1 * 60 {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.accent).frame(height: 2)
                        Circle().fill(Theme.accent).frame(width: 8, height: 8).offset(x: -4)
                    }
                    .frame(width: g.size.width - 44, height: 8)
                    .offset(x: 44, y: Self.y(v.now) - 4)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: g.size.width, height: height, alignment: .topLeading)
            .contentShape(Rectangle())
            .onDrop(of: [.plainText, .utf8PlainText, .text], delegate: DayDrop(at: $dropAt, dragging: $dragging) { id, m in place(id, at: m) })
        }
        .frame(height: height)
        .animation(Kit.snap, value: dropAt)
    }

    private func blockHeight(_ a: Int, _ b: Int) -> CGFloat { max(18, CGFloat(b - a) / 60 * Self.px - 2) }

    @ViewBuilder
    private func block(_ b: Block) -> some View {
        switch b.kind {
        case .event(let e):
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.nx(size: 12.5, .medium)).foregroundStyle(Kit.ink).lineLimit(1)
                if b.end - b.start >= 40 {
                    Text(e.location ?? "\(TimeWords.clock(b.start)) – \(TimeWords.clock(b.end))").font(.nx(size: 11)).foregroundStyle(Kit.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Kit.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
            .contentShape(Rectangle())
            .onTapGesture { eventSheet = .show(e.event) }
            .accessibilityIdentifier("day-event")
        case .task(let t):
            let color = store.color(t)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.text).font(.nx(size: 12.5, .medium)).foregroundStyle(Kit.ink).lineLimit(b.end - b.start >= 45 ? 2 : 1)
                    .strikethrough(t.done, color: Kit.muted)
                if b.end - b.start >= 45 {
                    let m = TodayPlan.minutes(t)
                    Text(TimeWords.clock(b.start) + (m > 0 ? " · " + TimeWords.dur(m) : "")).font(.nx(size: 11)).foregroundStyle(Kit.muted)
                }
            }
            .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(0.14))
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(t.done ? 0.5 : dragging == t.id ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture { store.open(t) }
            .contextMenu { TaskMenu(task: t, day: v.today) }
            .draggable(t.id) {
                HStack(spacing: 7) { SubjectDot(color: color); Text(t.text).font(.nx(.subheadline, .medium)) }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Kit.page, in: RoundedRectangle(cornerRadius: 10))
                    .onAppear { dragging = t.id }
            }
            .accessibilityIdentifier("day-task")
        case .suggestion(let s):
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.claude)
                Text(s.title).font(.nx(size: 12.5, .medium)).foregroundStyle(Kit.ink).lineLimit(1)
                Spacer(minLength: 4)
                Button("Accept") { withAnimation(Kit.spring) { accept(s) } }
                    .font(.nx(size: 11, .semibold)).foregroundStyle(Theme.claude).buttonStyle(.plain)
                    .accessibilityIdentifier("day-accept")
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.claude.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.claude, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("day-sugg")
        }
    }

    private func accept(_ s: TodayPlan.Suggestion) {
        guard let t = store.task(s.id), store.canEdit(t) else { return }
        store.setTime(t, on: v.today, TimeWords.hm(s.span.start))
    }

    /// A task dropped on an hour: planned today at that time (moved from the day it slipped from, or tomorrow).
    private func place(_ id: String, at m: Int) {
        dragging = nil
        guard let t = store.task(id), store.canEdit(t) else { return }
        withAnimation(Kit.spring) { store.planToday(t, at: TimeWords.hm(m)) }
    }
}

/// Diagonal hatching for a free stretch.
private struct Hatch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        var x = -r.height
        while x < r.width {
            p.move(to: CGPoint(x: x, y: r.height)); p.addLine(to: CGPoint(x: x + r.height, y: 0))
            x += 7
        }
        return p
    }
}

/// The day card's drop: where the finger is, as a quarter hour, and the dropped task's id.
private struct DayDrop: DropDelegate {
    @Binding var at: Int?
    @Binding var dragging: String?
    var drop: (String, Int) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        at = DayCard.minute(info.location.y)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { at = nil }
    func performDrop(info: DropInfo) -> Bool {
        let m = DayCard.minute(info.location.y)
        at = nil
        guard let p = info.itemProviders(for: [.plainText, .utf8PlainText, .text]).first else { dragging = nil; return false }
        _ = p.loadObject(ofClass: NSString.self) { s, _ in
            guard let s = s as? String else { return }
            DispatchQueue.main.async { drop(s, m) }
        }
        return true
    }
}

// MARK: Slipped

/// What slipped from earlier days: tick it, or Today plans it again; Claude says when they would fit later today.
struct SlippedCard: View {
    @Environment(NexusStore.self) private var store
    let v: TodayPlan.Day
    @State private var all = false

    var body: some View {
        let rows = v.slipped.filter { $0.task.hasId }
        let shown = all ? rows : Array(rows.prefix(4))
        let need = shown.reduce(0) { n, r in let m = TodayPlan.minutes(r.task); return n + (m > 0 ? m : 20) }
        let gap = v.gaps.map { TodayPlan.Span(max($0.start, v.now), $0.end) }.filter { need > 0 && $0.end - $0.start >= need }.max { $0.start < $1.start }
        VStack(alignment: .leading, spacing: 10) {
            SectionHead(title: "Slipped", note: rows.isEmpty ? "nothing" : "\(rows.count) from earlier days")
            VStack(spacing: 0) {
                if rows.isEmpty {
                    Text("Nothing slipped. Everything from earlier days is done or planned again.")
                        .font(.nx(.callout)).foregroundStyle(Kit.faint).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12).padding(.horizontal, 6)
                }
                ForEach(Array(shown.enumerated()), id: \.element.task.id) { i, r in
                    if i > 0 { Divider().overlay(Kit.ink.opacity(0.06)) }
                    row(r)
                }
                if rows.count > 4 {
                    Button(all ? "Show fewer" : "\(rows.count - 4) more") { withAnimation(Kit.spring) { all.toggle() } }
                        .font(.nx(.footnote, .medium)).foregroundStyle(Kit.muted).buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10).padding(.horizontal, 6)
                }
                if let gap, !shown.isEmpty {
                    let at = (gap.start + 14) / 15 * 15
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.claude)
                        (Text("Claude: ").fontWeight(.semibold) + Text("\(shown.count == 1 ? "it fits" : shown.count == 2 ? "both fit" : "they fit") in your \(TimeWords.clockAp(at)) gap."))
                            .font(.nx(.footnote)).foregroundStyle(Kit.ink)
                        Spacer(minLength: 6)
                        Button("Put \(shown.count == 1 ? "it" : "them") there") { putThere(shown, at: at) }
                            .buttonStyle(KitButtonStyle(kind: .claude, small: true))
                            .accessibilityIdentifier("slipped-put")
                    }
                    .padding(10)
                    .background(Theme.claude.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .kitSurface(Kit.rests, radius: 18)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("slipped")
        }
    }

    private func row(_ r: TodayPlan.Slip) -> some View {
        let m = TodayPlan.minutes(r.task)
        return HStack(spacing: 12) {
            TickRing(task: r.task)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.task.text).font(.nx(size: 14.5)).foregroundStyle(Kit.ink).lineLimit(1)
                (Text(store.workstreamName(r.task) + " · ")
                    + Text(r.late ? "was due \(TodayView.weekday(r.was, short: true))" : "was \(TodayView.weekday(r.was, short: true))").foregroundColor(Theme.late)
                    + Text(m > 0 ? " · " + TimeWords.dur(m) : ""))
                    .font(.nx(.caption)).foregroundStyle(Kit.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if store.canEdit(r.task) {
                Button("Today") { withAnimation(Kit.spring) { store.move(r.task, from: r.late ? nil : r.was, to: v.today) } }
                    .buttonStyle(KitButtonStyle(kind: .tone, small: true))
                    .accessibilityIdentifier("to-today")
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { store.open(r.task) }
        .draggable(r.task.id)
    }

    private func putThere(_ rows: [TodayPlan.Slip], at start: Int) {
        var at = start
        withAnimation(Kit.spring) {
            for r in rows where store.canEdit(r.task) {
                store.planToday(r.task, at: TimeWords.hm(at), from: r.late ? nil : r.was)
                let m = TodayPlan.minutes(r.task)
                at += m > 0 ? m : 20
            }
        }
    }
}

// MARK: Tomorrow

/// A look at tomorrow: how full it is, in words and a ring, its hours in a strip, its tasks, and one to start tonight.
struct TomorrowCard: View {
    @Environment(NexusStore.self) private var store
    @Environment(CalendarStore.self) private var cal
    let v: TodayPlan.Day

    var body: some View {
        let t = v.tomorrow
        let events = TodayEvents.spans(cal, t.date)
        let ratio = t.free > 0 ? Double(t.planned) / Double(t.free) : t.planned > 0 ? 1 : 0
        let mood = t.planned == 0 && events.isEmpty ? "A clear day." : ratio < 0.5 ? "A lighter day." : ratio < 0.9 ? "A steady day." : "A full day."
        let said = events.prefix(2).map { "\($0.event.title) at \(TimeWords.clockAp($0.start))" }
        let line = (said.isEmpty ? "No events" : said.joined(separator: " and ")) + (t.planned > 0 ? ", with \(TimeWords.about(t.planned)) planned." : ", nothing planned yet.")
        let untimed = t.list.filter { $0.time(on: t.date) == nil && $0.hasId }
        let pick = untimed.first
        VStack(alignment: .leading, spacing: 10) {
            SectionHead(title: "Tomorrow", note: TodayView.weekday(t.date, short: true))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 0) {
                        Text(TodayView.weekday(t.date, short: true).uppercased()).font(.nx(size: 11.5, .semibold)).tracking(0.7).foregroundStyle(Theme.claude)
                        Text(String(Int(t.date.suffix(2)) ?? 0)).font(.nx(size: 28, .bold, display: true)).foregroundStyle(Kit.ink)
                    }
                    .frame(width: 64).padding(.top, 6).padding(.bottom, 8)
                    .background(Kit.page, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                    VStack(alignment: .leading, spacing: 4) {
                        (Text(mood).fontWeight(.semibold) + Text(" " + line)).font(.nx(size: 15)).foregroundStyle(Kit.ink)
                        if let l = t.longest {
                            Text("Your longest free stretch is \(TimeWords.clock(l.start)) to \(TimeWords.clock(l.end))." + (pick.map { " A good time for \($0.text)." } ?? ""))
                                .font(.nx(.footnote)).foregroundStyle(Kit.muted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ring(t, ratio)
                }
                strip(t, events)
                chips(t, pick)
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
            .background {
                ZStack {
                    Kit.rests
                    LinearGradient(stops: [.init(color: Theme.claude.opacity(0.09), location: 0), .init(color: .clear, location: 0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tomorrow")
        }
    }

    private func ring(_ t: TodayPlan.Tomorrow, _ ratio: Double) -> some View {
        ZStack {
            Circle().stroke(Kit.selected, lineWidth: 6)
            Circle().trim(from: 0, to: min(1, ratio)).stroke(ratio >= 0.9 ? Theme.soon : Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(TimeWords.hours(t.planned)).font(.nx(size: 15, .semibold, display: true)).foregroundStyle(Kit.ink)
                Text("of \(TimeWords.hours(t.free))").font(.nx(size: 10)).foregroundStyle(Kit.faint)
            }
        }
        .frame(width: 58, height: 58).padding(3)
        .animation(.easeOut(duration: 0.6), value: ratio)
    }

    private struct Mini: Identifiable { var id: String; var a: Int; var b: Int; var event: Bool; var color: Color; var label: String; var level = 0 }

    private func strip(_ t: TodayPlan.Tomorrow, _ events: [(start: Int, end: Int, event: CalEvent)]) -> some View {
        let span = Double(TodayPlan.dayTo - TodayPlan.dayFrom)
        let x = { (m: Int) -> CGFloat in CGFloat(max(0, min(1, Double(m - TodayPlan.dayFrom) / span))) }
        var blocks: [Mini] = events.enumerated().map { Mini(id: "e\($0.offset)", a: $0.element.start, b: $0.element.end, event: true, color: Kit.selected, label: String($0.element.event.title.split(separator: " ").first ?? "")) }
        for r in t.list {
            if let s = TodayPlan.clock(r.time(on: t.date)) {
                let m = TodayPlan.minutes(r)
                blocks.append(Mini(id: r.id, a: s, b: s + (m > 0 ? m : TodayPlan.defaultBlock), event: false, color: store.color(r), label: r.text.split(separator: " ").prefix(2).joined(separator: " ")))
            }
        }
        blocks.sort { $0.a < $1.a }
        var ends = [-1.0, -1.0]
        for i in blocks.indices {
            let from = Double(x(blocks[i].a)) * 100, to = from + Double(blocks[i].label.count) * 0.75 + 2
            blocks[i].level = from >= ends[0] ? 0 : 1
            ends[blocks[i].level] = to
        }
        let two = blocks.contains { $0.level == 1 }
        return VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width - 4
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Kit.page)
                        .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                    ForEach(blocks) { b in
                        let bx = 2 + x(b.a) * w, bw = max((x(b.b) - x(b.a)) * w, 0.02 * w) - 3
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(b.event ? Kit.selected : b.color.opacity(0.55))
                            .frame(width: bw, height: 22).offset(x: bx, y: 6)
                        Text(b.label).font(.nx(size: 11.5, .medium)).foregroundStyle(b.event ? Kit.muted : Kit.ink).fixedSize()
                            .offset(x: bx, y: b.level == 0 ? -22 : -38)
                    }
                }
            }
            .frame(height: 34)
            .padding(.top, two ? 52 : 34)
            HStack {
                ForEach([8, 10, 12, 14, 16, 18, 20, 22], id: \.self) { h in
                    Text(h == 8 ? "8am" : "\(h % 12 == 0 ? 12 : h % 12)")
                    if h != 22 { Spacer(minLength: 0) }
                }
            }
            .font(.nx(size: 10.5)).foregroundStyle(Kit.faint).padding(.horizontal, 2)
        }
    }

    private func chips(_ t: TodayPlan.Tomorrow, _ pick: NexusTask?) -> some View {
        FlowRow(spacing: 8) {
            ForEach(t.list.prefix(4), id: \.id) { r in
                let tm = TodayPlan.clock(r.time(on: t.date))
                HStack(spacing: 7) {
                    SubjectDot(color: store.color(r))
                    Text(r.text).lineLimit(1)
                    Text(tm.map(TimeWords.clockAp) ?? TimeWords.dur(TodayPlan.minutes(r))).font(.nx(size: 12)).foregroundStyle(Kit.faint)
                }
                .font(.nx(size: 13)).foregroundStyle(Kit.ink)
                .padding(.horizontal, 11).frame(height: 30)
                .background(Kit.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
                .onTapGesture { store.open(r) }
                .draggable(r.id)
            }
            if t.list.count > 4 {
                Text("+\(t.list.count - 4)").font(.nx(size: 13)).foregroundStyle(Kit.muted)
                    .padding(.horizontal, 11).frame(height: 30)
                    .background(Kit.page, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let p = pick, store.canEdit(p) {
                Button { withAnimation(Kit.spring) { store.move(p, from: t.date, to: v.today) } } label: {
                    Label("Start one tonight?", systemImage: "sparkles").font(.nx(size: 13, .medium))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.claude)
                .padding(.horizontal, 11).frame(height: 30)
                .background(Theme.claudeTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("start-tonight")
            }
        }
        .padding(.top, 12)
    }
}
