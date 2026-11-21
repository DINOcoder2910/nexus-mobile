import SwiftUI
import WebKit
import NexusCore

/// The laptop's chemistry study tools (the VSEPR chart, Enthalpies, Molecules), each on its own screen here as on the laptop's Study tab.
/// The page is the laptop's own (nexus dist/tools/<name>.html): the data folder's copy in .nexus-tools/ when the laptop has sent one (it
/// keeps it current), else the copy built into the app (Resources/Tools, `tools/study-tools/copy.mjs`), so the tools work before the
/// first sync too. What you leave a tool showing is kept on this device and comes back next time.
enum StudyTools {
    /// The page for a tool: the data folder's copy first, else the app's.
    static func pageURL(_ name: String, root: URL?) -> URL? {
        if let root {
            let u = root.appendingPathComponent(ToolCatalog.builtinFile(name))
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return Bundle.main.url(forResource: name, withExtension: "html", subdirectory: "Tools")
    }

    static func tool(_ name: String) -> ToolCatalog.Tool? { ToolCatalog.tools.first { $0.name == name } }

    static func icon(_ name: String) -> String {
        switch name {
        case "vsepr": return "cube.transparent"
        case "enthalpies": return "flame"
        default: return "atom"
        }
    }

    // MARK: what a tool was left showing

    private static func key(_ name: String) -> String { "studyTool." + name }
    static func state(_ name: String) -> JSONValue? {
        guard let t = UserDefaults.standard.string(forKey: key(name)) else { return nil }
        return try? JSONValue.parse(t)
    }
    static func keep(_ name: String, _ s: JSONValue?) {
        if let s, let kept = ToolCatalog.keepState(s) { UserDefaults.standard.set(kept.text, forKey: key(name)) }
        else { UserDefaults.standard.removeObject(forKey: key(name)) }
    }
}

/// A row for each tool, opening it on its own screen.
struct StudyToolRows: View {
    @Environment(NexusStore.self) private var store

    var body: some View {
        ForEach(ToolCatalog.tools, id: \.name) { t in
            let ready = StudyTools.pageURL(t.name, root: store.folder) != nil
            NavigationLink {
                ChemToolScreen(name: t.name)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: StudyTools.icon(t.name)).foregroundStyle(Theme.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title)
                        Text(ready ? t.desc : "Comes from the laptop: open Nexus there to send it").font(.nx(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!ready)
            .accessibilityIdentifier("study-tool-" + t.name)
        }
    }
}

/// One tool, filling the screen.
struct ChemToolScreen: View {
    @Environment(NexusStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    let name: String
    /// Changed to start the page again from nothing.
    @State private var generation = 0

    var body: some View {
        let t = StudyTools.tool(name)
        Group {
            if let url = StudyTools.pageURL(name, root: store.folder) {
                ToolWebView(name: name, url: url, dark: scheme == .dark)
                    .id("\(generation)|\(scheme == .dark)")
                    .ignoresSafeArea(edges: .bottom)
            } else {
                EmptyNote(title: "\(t?.title ?? "This tool") isn't here yet", detail: "It comes from the laptop: open Nexus there and it sends it with sync.", icon: "atom")
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(t?.title ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { StudyTools.keep(name, nil); generation += 1 } label: { Label("Start again", systemImage: "arrow.counterclockwise") }
                    if let t { Text(t.desc) }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
    }
}

/// The tool's page (ToolViews.swift ToolPage: offline, no file access, talks only through postMessage), started with what it was
/// left showing; each change it reports is kept.
struct ToolWebView: UIViewRepresentable {
    let name: String
    let url: URL
    let dark: Bool

    final class Coordinator { var page: ToolPage? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let p = ToolPage(interactive: true)
        p.dark = dark
        let name = name
        p.onState = { StudyTools.keep(name, $0) }
        let bg: UIColor = dark ? .black : .white
        p.web.backgroundColor = bg
        p.web.scrollView.backgroundColor = bg
        p.web.accessibilityIdentifier = "study-tool-page"
        p.load(url, state: StudyTools.state(name))
        context.coordinator.page = p
        return p.web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
