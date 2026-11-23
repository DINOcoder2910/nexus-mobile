import SwiftUI
import NexusCore

/// "Get class material" on a notebook page (ClassMaterial.swift): asks the hub, which asks Nexus on the G14 to read Schoology and make
/// the new chemistry slide boards and maths lesson folders. They arrive by sync; the page shows one line on how it went. The notebooks
/// it fills come from the G14's answer and are kept, so the button shows offline too. `-NexusTestClassMaterial` answers without a hub.
@MainActor
@Observable
final class ClassMaterialModel {
    static let shared = ClassMaterialModel()
    static let test = ProcessInfo.processInfo.arguments.contains("-NexusTestClassMaterial")
    private static let rootsKey = "classMaterial.roots"

    private(set) var roots: [String] = []
    private(set) var busy = false
    /// The line under the page's title after a press, until it is closed.
    var line: String?

    private init() {
        roots = Self.test ? ["notebooks/Chem class"] : (UserDefaults.standard.stringArray(forKey: Self.rootsKey) ?? [])
    }

    /// The G14's last answer (and the notebooks it fills), quietly.
    func refresh() async {
        if Self.test || busy { return }
        if let s = try? await ask("v1/schoology/status", post: false) { keep(s) }
    }

    func look() async {
        if busy { return }
        busy = true
        line = "Getting class material from Schoology…"
        defer { busy = false }
        if Self.test {
            try? await Task.sleep(for: .seconds(1.5))
            var s = ClassMaterial.Status()
            s.made = ["notebooks/Chem class/R3.2.8.board"]
            line = ClassMaterial.words(s)
            return
        }
        do {
            let started = try await ask("v1/schoology/look", post: true)
            if !started.running && started.error != nil { line = ClassMaterial.words(started); return }
            // a look takes from a few seconds to a few minutes (the PDFs); asked every 3 s, for up to 10 minutes
            for _ in 0..<200 {
                try await Task.sleep(for: .seconds(3))
                let s = try await ask("v1/schoology/status", post: false)
                if !s.running { keep(s); line = ClassMaterial.words(s); AppServices.sync.syncNow(); return }
            }
            line = "Still working on the G14. The boards arrive when it's done."
        } catch {
            line = (error as? ClassMaterialError)?.words ?? "Couldn't reach the hub: \(error.localizedDescription)"
        }
    }

    private func keep(_ s: ClassMaterial.Status) {
        if !s.roots.isEmpty && s.roots != roots { roots = s.roots; UserDefaults.standard.set(s.roots, forKey: Self.rootsKey) }
    }

    private func ask(_ route: String, post: Bool) async throws -> ClassMaterial.Status {
        let d = UserDefaults.standard
        let token = (Keychain.get("hub-token") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hub = HTTPSyncTransport.hubURL(d.string(forKey: "sync.hubAddress") ?? ""), !token.isEmpty else {
            throw ClassMaterialError(words: "Set up sync with the hub first (Settings › Sync).")
        }
        var r = URLRequest(url: hub.appendingPathComponent(route))
        r.httpMethod = post ? "POST" : "GET"
        r.timeoutInterval = 20
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        r.setValue(d.string(forKey: "sync.deviceName") ?? "iPad", forHTTPHeaderField: "X-Nexus-Device")
        let (data, resp) = try await URLSession.shared.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        if code == 404 { throw ClassMaterialError(words: "The hub can't fetch class material yet: update it on the G14.") }
        if code == 401 { throw ClassMaterialError(words: "The hub refused this iPad's token. Check it in Settings › Sync.") }
        if code != 200 {
            let msg = (try? JSONValue.parse(text))?["error"]?.string
            throw ClassMaterialError(words: msg ?? "The hub answered with an error (\(code)).")
        }
        guard let s = ClassMaterial.status(text) else { throw ClassMaterialError(words: "The G14's answer didn't read.") }
        return s
    }
}

struct ClassMaterialError: Error { let words: String }

/// The page's button (in the toolbar) for a notebook the look fills.
struct ClassMaterialToolbarButton: View {
    let path: String
    @State private var model = ClassMaterialModel.shared

    var body: some View {
        if ClassMaterial.shows(on: path, roots: model.roots) {
            Button { Task { await model.look() } } label: {
                if model.busy { ProgressView() } else { Label("Get class material", systemImage: "arrow.down.doc") }
            }
            .disabled(model.busy)
            .accessibilityIdentifier("class-material")
        }
    }
}

/// The line under the page's crumbs after a press.
struct ClassMaterialLine: View {
    let path: String
    @State private var model = ClassMaterialModel.shared

    var body: some View {
        if ClassMaterial.shows(on: path, roots: model.roots), let line = model.line {
            HStack(spacing: 10) {
                if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.doc").foregroundStyle(.secondary) }
                Text(line).font(.nx(.subheadline)).accessibilityIdentifier("class-material-line")
                Spacer(minLength: 0)
                if !model.busy {
                    Button { model.line = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Close")
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
