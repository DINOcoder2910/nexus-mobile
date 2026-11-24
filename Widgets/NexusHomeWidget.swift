import AppIntents
import SwiftUI
import WidgetKit

// The Home Screen widgets (Nov 23 2026): they live in this extension (the Live Activity's), so they take no App ID or sideload slot of
// their own. The extension can't read the app's files under free signing, so the app writes the day's card into the data folder's
// widgets/<device>.json (Sources/LiveActivity/WidgetShare.swift), sync takes it to the hub on the G14, and the widget reads it from
// there with the widget key pasted once into Edit Widget (Settings › Lock Screen › Home Screen widgets).

/// Edit Widget: the key.
struct NexusWidgetSetup: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Nexus"
    static var description = IntentDescription("Paste the widget key from Nexus › Settings › Home Screen widgets.")

    @Parameter(title: "Widget key")
    var key: String?

    init() {}
}

struct NexusDayEntry: TimelineEntry {
    let date: Date
    let state: NexusLiveState?
    /// Why there is no card ("Paste the widget key…", "Can't reach the hub").
    let problem: String?
    /// When the app wrote the card.
    let updated: Date?
}

struct NexusDayProvider: AppIntentTimelineProvider {
    static let example = NexusLiveState(focus: .next, title: "Redox worksheet Q1–5", detail: "Up next at 16:00 · Chemistry HL", since: Date().addingTimeInterval(3600),
                                        light: "#0F7A49", dark: "#4FD28F", done: 3, total: 7, tracked: 5400, stamp: Date())

    func placeholder(in context: Context) -> NexusDayEntry { NexusDayEntry(date: Date(), state: Self.example, problem: nil, updated: Date()) }

    func snapshot(for configuration: NexusWidgetSetup, in context: Context) async -> NexusDayEntry {
        if context.isPreview { return placeholder(in: context) }
        return await fetch(configuration)
    }

    func timeline(for configuration: NexusWidgetSetup, in context: Context) async -> Timeline<NexusDayEntry> {
        let e = await fetch(configuration)
        // again in a quarter of an hour (iOS spaces widget reloads out; the app asks for one after it writes the card), sooner when the
        // card's line under the big row moves on (the next event or task's time)
        var next = Date().addingTimeInterval(15 * 60)
        if let s = e.state {
            let times = s.lines.map { $0.kind == .event && $0.at <= Date() ? ($0.end ?? $0.at) : $0.at } + (s.ahead(Date()) ? [s.since] : [])
            if let t = times.filter({ $0 > Date() }).min(), t < next { next = t.addingTimeInterval(5) }
        }
        return Timeline(entries: [e], policy: .after(next))
    }

    private func fetch(_ c: NexusWidgetSetup) async -> NexusDayEntry {
        guard let text = c.key, !text.isEmpty else { return NexusDayEntry(date: Date(), state: nil, problem: "Hold this widget › Edit Widget, and paste the widget key from Nexus › Settings.", updated: nil) }
        guard let key = NexusWidgetShare.Key(text), var u = URLComponents(string: key.hub) else {
            return NexusDayEntry(date: Date(), state: nil, problem: "That isn't a Nexus widget key. Copy it again in Nexus › Settings.", updated: nil)
        }
        u.path = "/v1/file"
        u.percentEncodedQuery = "path=" + (NexusWidgetShare.path(device: key.device).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        guard let url = u.url else { return NexusDayEntry(date: Date(), state: nil, problem: "The key's hub address isn't one.", updated: nil) }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        r.setValue("Bearer " + key.token, forHTTPHeaderField: "Authorization")
        r.setValue(key.device + " widget", forHTTPHeaderField: "X-Nexus-Device")
        do {
            let (data, resp) = try await URLSession.shared.data(for: r)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { return NexusDayEntry(date: Date(), state: nil, problem: "Open Nexus on your \(key.device) once: it hasn't sent its day to the hub yet.", updated: nil) }
            if code == 401 { return NexusDayEntry(date: Date(), state: nil, problem: "The hub didn't take the key. Copy it again in Nexus › Settings.", updated: nil) }
            guard (200..<300).contains(code), let f = try? NexusWidgetShare.decoder.decode(NexusWidgetShare.File.self, from: data) else {
                return NexusDayEntry(date: Date(), state: nil, problem: "The hub's answer didn't read (\(code)).", updated: nil)
            }
            return NexusDayEntry(date: Date(), state: f.state, problem: nil, updated: f.updated)
        } catch {
            return NexusDayEntry(date: Date(), state: nil, problem: "Can't reach the hub right now.", updated: nil)
        }
    }
}

struct NexusDayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NexusDay", intent: NexusWidgetSetup.self, provider: NexusDayProvider()) { entry in
            NexusDayWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(entry.state.map(NexusLive.url) ?? NexusLive.todayURL)
        }
        .configurationDisplayName("Nexus")
        .description("Your day: the timer or the task up next, what comes after it, and today's ticks and time.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NexusDayWidgetView: View {
    let entry: NexusDayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.state {
            switch family {
            case .systemMedium: medium(s)
            case .accessoryRectangular: rectangular(s)
            default: small(s)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "square.grid.2x2").font(.system(size: 18, weight: .semibold)).foregroundStyle(.green)
                Text(entry.problem ?? "Nexus").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func small(_ s: NexusLiveState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NexusLiveIcon(state: s, size: 26)
                Spacer(minLength: 0)
                if s.clocks(Date()) {
                    NexusLiveClock(state: s, alignment: .trailing).font(.system(size: 15, weight: .semibold, design: .rounded)).frame(maxWidth: 80, alignment: .trailing)
                }
            }
            Text(s.title).font(.system(size: 15, weight: .semibold)).lineLimit(3).minimumScaleFactor(0.85)
            Text(s.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            NexusLiveDay(state: s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: NexusLiveState) -> some View {
        let line = s.line(at: Date())
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                NexusLiveIcon(state: s, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(.system(size: 16, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(s.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                NexusLiveDay(state: s, trailing: true).fixedSize()
            }
            NexusLiveBig(state: s)
            if let line { NexusLiveLineRow(line: line) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rectangular(_ s: NexusLiveState) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(s.title).font(.headline).lineLimit(1)
            if s.clocks(Date()) { NexusLiveClock(state: s, alignment: .leading).font(.body.monospacedDigit()) }
            else { Text(s.detail).font(.caption).lineLimit(1) }
            Text("\(s.done) of \(s.total) done").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
