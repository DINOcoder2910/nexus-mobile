import SwiftUI
import NexusCore

/// "Check the school's site" (the laptop's appssite.js): the admissions page and up to three linked pages about deadlines and requirements are
/// read here, Claude reports the rounds, deadlines and requirements with a quote for each, and only what the pages really say is kept. You
/// review it against the school's file and Save selected writes it, with Undo.
struct SiteCheckSheet: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let school: School
    var start: String

    enum Phase: Equatable { case ask, working(String), review, failed(String) }
    @State private var url = ""
    @State private var onlyThis = false
    @State private var phase: Phase = .ask
    @State private var items: [SiteFacts.Finding] = []
    @State private var dropped: [SiteFacts.Dropped] = []
    @State private var pages: [String] = []
    @State private var job: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                switch phase {
                case .ask, .failed:
                    Section {
                        TextField("https://admissions…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Toggle("Read only this page", isOn: $onlyThis)
                    } footer: {
                        Text("Nexus reads the page and up to \(SiteFacts.maxLinks) linked pages about deadlines and requirements, then Claude reports what they say. Only sentences really on the pages are kept, and nothing is saved until you choose.")
                    }
                    if case .failed(let why) = phase { Section { Label(why, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.late) } }
                case .working(let what):
                    Section { HStack(spacing: 10) { ProgressView(); Text(what) } }
                case .review:
                    Section {
                        ForEach($items) { $f in findingRow($f) }
                    } header: { Text("Found on \(pages.count) page\(pages.count == 1 ? "" : "s")") } footer: {
                        Text(items.contains { $0.on } ? "The ticked items are saved." : "Everything found is already in the file.")
                    }
                    if !dropped.isEmpty {
                        Section("Left out") {
                            ForEach(dropped, id: \.label) { d in
                                HStack { Text(d.label); Spacer(); Text(d.why).foregroundStyle(.secondary) }.font(.nx(.caption))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Check \(school.short)'s site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { job?.cancel(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    switch phase {
                    case .review:
                        Button("Save selected") { save() }.disabled(!items.contains { $0.on && $0.status != "same" && $0.kind != .none })
                    case .working: EmptyView()
                    default:
                        Button("Check") { run() }.disabled(URL(string: url.trimmingCharacters(in: .whitespaces))?.host == nil)
                    }
                }
            }
            .onAppear { if url.isEmpty { url = start } }
        }
    }

    private func findingRow(_ f: Binding<SiteFacts.Finding>) -> some View {
        let x = f.wrappedValue
        return HStack(alignment: .top, spacing: 10) {
            if x.kind != .none && x.status != "same" {
                Button { f.wrappedValue.on.toggle() } label: {
                    Image(systemName: x.on ? "checkmark.square.fill" : "square").foregroundStyle(x.on ? Theme.accent : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: x.kind == .none ? "info.circle" : "equal.circle").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(x.label).font(.nx(.subheadline, .semibold))
                    if !x.display.isEmpty { Text(x.display).font(.nx(.subheadline)) }
                    Spacer()
                    if !x.status.isEmpty { Text(x.status == "changed" ? "was \(x.was.map { SiteFacts.fmtDate($0) } ?? "")" : x.status).font(.nx(.caption)).foregroundStyle(x.status == "same" ? Color.secondary : Theme.accent) }
                }
                if !x.quote.isEmpty { Text("“\(x.quote)”").font(.nx(.caption)).foregroundStyle(.secondary).lineLimit(4) }
                if !x.url.isEmpty, let u = URL(string: x.url) { Button(SiteFacts.hostOf(x.url)) { openURL(u) }.font(.nx(.caption2)) }
            }
        }
    }

    // MARK: the check

    private func run() {
        let first = url.trimmingCharacters(in: .whitespaces)
        let only = onlyThis
        let today = store.today
        let s = school
        job = Task {
            do {
                phase = .working("Reading the page…")
                var got: [SiteFacts.Page] = []
                let (html, final) = try await Self.fetch(first)
                got.append(.init(url: final, text: SiteFacts.htmlToText(html)))
                if !only {
                    let links = SiteFacts.pickLinks(html, base: final)
                    if !links.isEmpty { phase = .working("Reading \(links.map(\.name).joined(separator: ", "))…") }
                    for l in links {
                        if let r = try? await Self.fetch(l.url) { got.append(.init(url: r.1, text: SiteFacts.htmlToText(r.0))) }
                    }
                }
                guard got.contains(where: { $0.text.filter { !$0.isWhitespace }.count >= 80 }) else {
                    throw AppsEditor.Failure.cannot("The page has almost no text: it is probably built with scripts. Paste a more specific page.")
                }
                phase = .working("Claude is reading the pages…")
                let req = ClaudeRequest(model: "sonnet", system: SiteFacts.system, messages: [.user(SiteFacts.prompt(pages: got, name: s.name, today: today))], maxTokens: 8000)
                let reply = try await ClaudeClient.shared.stream(req) { _ in }
                guard let found = SiteFacts.parse(reply.text) else { throw AppsEditor.Failure.cannot("Claude's answer was not in the expected form.") }
                phase = .working("Checking each item against the pages…")
                let kept = SiteFacts.verify(found, pages: got, cycle: SiteFacts.cycleOf(today))
                if kept.rounds.isEmpty && kept.requirements.isEmpty && kept.testing == nil {
                    throw AppsEditor.Failure.cannot(kept.dropped.isEmpty ? "The pages list no deadlines or requirements for this cycle."
                                                    : "Nothing Claude found could be checked against the page text (\(kept.dropped.count) left out).")
                }
                items = SiteFacts.diff(kept, school: s)
                dropped = kept.dropped
                pages = got.map(\.url)
                phase = .review
            } catch is CancellationError {
            } catch {
                phase = .failed("\(error)")
            }
        }
    }

    private func save() {
        let take = items, host = SiteFacts.hostOf(pages.first ?? url)
        AppsData.shared.edit(store) { e, _ in try e.saveFindings(school, take: take, host: host, today: store.today) }
        dismiss()
    }

    /// A page's HTML and its address after redirects.
    static func fetch(_ address: String) async throws -> (String, String) {
        guard let u = URL(string: address) else { throw AppsEditor.Failure.cannot("That is not a web address.") }
        var r = URLRequest(url: u, timeoutInterval: 25)
        r.setValue("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: r)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw AppsEditor.Failure.cannot("The page answered \(h.statusCode).") }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (text, resp.url?.absoluteString ?? address)
    }
}
