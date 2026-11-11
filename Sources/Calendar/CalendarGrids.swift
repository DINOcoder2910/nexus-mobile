import SwiftUI
import NexusCore

/// Day, 3 days and Week: the days side by side on one time grid, midnight to midnight, opened scrolled to the hour before now.
/// All-day events and deadlines sit in a strip above the grid. Overlapping things share the column's width.
struct TimeGridView: View {
    let days: [String]
    let today: String
    let timed: (String) -> [CalThing]
    let allDay: (String) -> [CalThing]
    let tap: (CalThing) -> Void
    let openDay: (String) -> Void
    let newEvent: (String, Int) -> Void
    let dropTask: (String, String, Int) -> Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var targetDay: String?

    private var hourHeight: CGFloat { sizeClass == .compact ? 48 : 56 }
    private let gutter: CGFloat = 48

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        hourLabels
                        ForEach(days, id: \.self) { day in
                            column(day)
                                .frame(maxWidth: .infinity)
                                .overlay(alignment: .leading) { Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5) }
                        }
                    }
                    .frame(height: hourHeight * 24)
                    .padding(.vertical, 10)
                }
                .onAppear {
                    let h = Calendar.current.component(.hour, from: Date())
                    proxy.scrollTo("h\(max(0, h - 1))", anchor: .top)
                }
            }
        }
    }

    // MARK: the header and the all-day strip

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let things = allDay(day)
                let room = days.count == 1 ? 6 : 2
                VStack(spacing: 4) {
                    Button { openDay(day) } label: { dayLabel(day) }
                        .buttonStyle(.plain)
                        .allowsHitTesting(days.count > 1)
                    ForEach(things.prefix(room)) { th in
                        Button { tap(th) } label: { pill(th) }.buttonStyle(.plain)
                    }
                    if things.count > room {
                        Button("+\(things.count - room) more") { openDay(day) }
                            .font(.caption2).buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func dayLabel(_ day: String) -> some View {
        let parts = Days.label(day).split(separator: " ")
        let isToday = day == today
        return HStack(spacing: 5) {
            Text(parts.first.map { String($0) } ?? "").font(.caption.weight(.semibold)).foregroundStyle(isToday ? Theme.accent : .secondary)
            Text(parts.count > 1 ? String(parts[1]) : "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(minWidth: 26, minHeight: 26)
                .background(isToday ? Theme.accent : Color.clear, in: Circle())
        }
    }

    private func pill(_ th: CalThing) -> some View {
        HStack(spacing: 3) {
            if case .deadline = th.kind { Image(systemName: "flag.fill").imageScale(.small) }
            Text(th.title).lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(th.task == nil ? Color.primary : th.color)
        .background(th.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: the grid

    private var hourLabels: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Text(h == 0 ? "" : hourText(h))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    .frame(width: gutter - 6, height: hourHeight, alignment: .topTrailing)
                    .offset(y: -7)
                    .id("h\(h)")
            }
        }
        .frame(width: gutter, alignment: .leading)
    }

    private func hourText(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return d.formatted(.dateTime.hour())
    }

    private func column(_ day: String) -> some View {
        let things = timed(day)
        let placed = DayLayout.place(things.map { DayLayout.Span(id: $0.id, start: $0.start, end: $0.end) })
        let byId = Dictionary(things.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let hh = hourHeight
        return ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
                        Spacer(minLength: 0)
                    }
                    .frame(height: hh)
                }
            }
            if targetDay == day { Theme.accent.opacity(0.06) }
            GeometryReader { g in
                ForEach(placed) { pl in
                    if let th = byId[pl.id] { placedBlock(th, pl, columnWidth: g.size.width) }
                }
                if day == today { nowLine(width: g.size.width) }
            }
        }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture(count: 2).onEnded { v in newEvent(day, snap(v.location.y)) })
        .dropDestination(for: String.self) { ids, location in
            var done = false
            for id in ids where dropTask(id, day, snap(location.y)) { done = true }
            targetDay = nil
            return done
        } isTargeted: { on in
            if on { targetDay = day } else if targetDay == day { targetDay = nil }
        }
    }

    /// A block at its place: its share of the column's width, from its start to its end.
    private func placedBlock(_ th: CalThing, _ pl: DayLayout.Placed, columnWidth: CGFloat) -> some View {
        let cols: CGFloat = CGFloat(max(1, pl.columns))
        let w: CGFloat = columnWidth / cols
        let perMinute: CGFloat = hourHeight / 60
        let length: CGFloat = CGFloat(pl.end - pl.start) * perMinute
        let x: CGFloat = CGFloat(pl.column) * w + 1
        let y: CGFloat = CGFloat(pl.start) * perMinute
        return block(th, tall: pl.end - pl.start >= 45)
            .frame(width: max(0, w - 2), height: max(18, length - 1))
            .offset(x: x, y: y)
    }

    /// A place on the grid to a time, to the quarter hour.
    private func snap(_ y: CGFloat) -> Int {
        let m = Int((y / hourHeight * 60).rounded(.down))
        return max(0, min(23 * 60 + 45, m / 15 * 15))
    }

    @ViewBuilder
    private func block(_ th: CalThing, tall: Bool) -> some View {
        let isTask = th.task != nil
        let base = VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if isTask { Image(systemName: "circle").font(.system(size: 8, weight: .bold)) }
                Text(th.title).font(.caption.weight(.semibold)).lineLimit(tall ? 3 : 1)
            }
            if tall {
                Text(th.timeText).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 3)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(th.color.opacity(isTask ? 0.10 : 0.22))
        .overlay(alignment: .leading) { Rectangle().fill(th.color).frame(width: 3) }
        .overlay {
            if isTask {
                RoundedRectangle(cornerRadius: 5).strokeBorder(th.color.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { tap(th) }
        if let t = th.task, case .task = th.kind {
            base.draggable(t.id) {
                Text(t.text).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        } else {
            base
        }
    }

    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.everyMinute) { ctx in
            let c = Calendar.current
            let m = c.component(.hour, from: ctx.date) * 60 + c.component(.minute, from: ctx.date)
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.late).frame(width: width, height: 1.5)
                Circle().fill(Theme.late).frame(width: 8, height: 8).offset(x: -4)
            }
            .offset(y: CGFloat(m) * (hourHeight / 60) - 0.75)
            .allowsHitTesting(false)
        }
    }
}

/// Month: six weeks from the Monday before the 1st. Each day shows what fits (dots on a phone); tap a day to open it.
struct MonthGridView: View {
    let days: [String]
    let month: String
    let today: String
    let compact: Bool
    let things: (String) -> [CalThing]
    let openDay: (String) -> Void

    private let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { w in
                    Text(compact ? String(w.prefix(1)) : w)
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 6)
            Divider()
            GeometryReader { g in
                let rowH = g.size.height / 6
                let colW = g.size.width / 7
                VStack(spacing: 0) {
                    ForEach(0..<6, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { c in
                                let i = r * 7 + c
                                if i < days.count {
                                    cell(days[i], height: rowH).frame(width: colW, height: rowH)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(_ day: String, height: CGFloat) -> some View {
        let list = things(day)
        let inMonth = day.prefix(7) == month.prefix(7)
        let isToday = day == today
        let room = max(0, Int((height - 30) / 16))
        return VStack(alignment: .leading, spacing: 2) {
            Text(String(Int(day.suffix(2)) ?? 0))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.white : inMonth ? .primary : .secondary)
                .frame(minWidth: 22, minHeight: 22)
                .background(isToday ? Theme.accent : Color.clear, in: Circle())
            if compact {
                HStack(spacing: 2) {
                    ForEach(list.prefix(4)) { th in Circle().fill(th.color).frame(width: 5, height: 5) }
                }
                .padding(.leading, 4)
            } else {
                ForEach(list.prefix(room)) { th in
                    HStack(spacing: 3) {
                        Circle().fill(th.color).frame(width: 6, height: 6)
                        Text(th.title).font(.caption2).lineLimit(1)
                    }
                }
                if list.count > room && room > 0 {
                    Text("+\(list.count - room)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(inMonth ? 1 : 0.55)
        .overlay(alignment: .top) { Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5) }
        .overlay(alignment: .leading) { Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5) }
        .contentShape(Rectangle())
        .onTapGesture { openDay(day) }
    }
}
