import SwiftUI
import UIKit
import NexusCore

/// A typed block's Google Doc, as on the laptop (desktop/src/board/gdocs.tsx): Link to a Google Doc… / Make a Google Doc from this block
/// in the block's menu, then Open in Google Docs, choosing a side when both have words, and Unlink. The link is the `google` key of the
/// block's text/<id>.jsonl header (NexusCore GoogleDocLink); this iPad or iPhone only writes that key, and the hub's bridge on the G14
/// makes or opens the Doc, keeps the two in step and writes the Doc's address back (it comes in as any outside change to the .jsonl).
extension BoardController {
    /// The block's link as its .jsonl says it (nil: not linked).
    func googleOf(_ id: String) -> GoogleDocLink? {
        guard let jsonl = content.docsOnDisk[id] else { return nil }
        return GoogleDocLink(RichWords.shared.header(jsonl)?["google"])
    }

    /// The block's .jsonl's path in the data folder: how the hub names it.
    func googlePath(_ id: String) -> String { path + "/" + RichWords.docFile(id) }

    /// Links (`{doc}`), makes (`{create, title}`), chooses a side or unlinks (nil): the header is written now, the words kept.
    func setGoogle(_ id: String, _ g: GoogleDocLink?, said: String) {
        if readOnly { tell("This board can't be changed here."); return }
        commitTyping(id)
        saveNow() // the block's words and its .jsonl on disk first
        guard let base = content.docsOnDisk[id] ?? BoardFiles.docToWrite(content, id: id),
              let jsonl = RichWords.shared.setHeader(base, key: "google", json: g?.json.text) else {
            toast("This block can't be linked now.")
            return
        }
        do {
            try FolderAccess.write(boardURL.appendingPathComponent(RichWords.docFile(id)), jsonl)
        } catch {
            tell("Couldn't write the link: \(error.localizedDescription)")
            return
        }
        content.docsOnDisk[id] = jsonl
        content.docWords[id] = content.texts[id] ?? ""
        stamps = stampsAfterSave(wrote: [RichWords.docFile(id)])
        NotificationCenter.default.post(name: BoardController.savedNote, object: self, userInfo: ["path": path])
        onSaved?(path)
        toast(said)
    }

    /// The block menu's Google Docs rows, for the link as it stands (gdocs.tsx `googleItems`).
    func googleMenu(_ id: String) -> UIMenu {
        let g = googleOf(id)
        let unlink = UIAction(title: "Unlink from Google Docs", image: UIImage(systemName: "xmark")) { [weak self] _ in self?.unlinkGoogle(id) }
        var rows: [UIMenuElement]
        if g == nil {
            rows = [
                UIAction(title: "Link to a Google Doc…", image: UIImage(systemName: "link")) { [weak self] _ in self?.askGoogleLink(id) },
                UIAction(title: "Make a Google Doc from this block", image: UIImage(systemName: "doc.badge.plus")) { [weak self] _ in self?.makeGoogleDoc(id) },
            ]
        } else if let g, g.error != nil {
            rows = [
                UIAction(title: "Keep this block's words", subtitle: "They replace the Doc's", image: UIImage(systemName: "arrow.up.doc")) { [weak self] _ in self?.chooseGoogleSide(id, "push") },
                UIAction(title: "Keep the Doc's words", subtitle: "They replace this block's", image: UIImage(systemName: "arrow.down.doc")) { [weak self] _ in self?.chooseGoogleSide(id, "pull") },
                unlink,
            ]
        } else if let g, let url = g.url.flatMap(URL.init(string:)) {
            rows = [UIAction(title: "Open in Google Docs", subtitle: g.title, image: UIImage(systemName: "globe")) { _ in UIApplication.shared.open(url) }, unlink]
        } else {
            rows = [UIAction(title: g?.create == true ? "Making the Doc…" : "Linking…", attributes: .disabled) { _ in }, unlink]
        }
        rows.append(UIAction(title: "Google Docs panel", image: UIImage(systemName: "sidebar.right")) { [weak self] _ in self?.openGooglePanel(id) })
        return UIMenu(title: "Google Docs", image: UIImage(systemName: "doc.text"), children: rows)
    }

    func askGoogleLink(_ id: String) {
        let a = UIAlertController(title: "Link to a Google Doc",
                                  message: "Paste the Doc's link. If the block or the Doc is empty, the other's words fill it; if both have words, you choose which to keep.",
                                  preferredStyle: .alert)
        a.addTextField { f in
            f.placeholder = "https://docs.google.com/document/d/…"
            f.keyboardType = .URL
            f.autocapitalizationType = .none
            f.autocorrectionType = .no
            f.accessibilityIdentifier = "gdoc-link-field"
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Link", style: .default) { [weak self, weak a] _ in
            guard let self else { return }
            guard let doc = GoogleDocLink.docId(a?.textFields?.first?.text ?? "") else { self.toast("That isn't a Google Doc link."); return }
            self.setGoogle(id, GoogleDocLink(doc: doc), said: "Linking to the Doc. The hub keeps them in step from now on.")
        })
        presentOver(a)
    }

    func makeGoogleDoc(_ id: String) {
        let title = GoogleDocLink.title(from: content.texts[id] ?? "")
        setGoogle(id, GoogleDocLink(create: true, title: title.isEmpty ? "Nexus" : title), said: "Making a Google Doc from this block.")
    }

    func chooseGoogleSide(_ id: String, _ side: String) {
        guard let g = googleOf(id) else { return }
        setGoogle(id, g.choosing(side), said: side == "push" ? "The block's words go to the Doc." : "The Doc's words come into the block.")
    }

    func unlinkGoogle(_ id: String) {
        setGoogle(id, nil, said: "Unlinked. The block and the Doc keep their words.")
    }

    func openGooglePanel(_ id: String) {
        let host = UIHostingController(rootView: GoogleDocsPanelView(model: GoogleDocsPanelModel(board: self, id: id)).tint(Theme.accent))
        host.modalPresentationStyle = .formSheet
        if let s = host.sheetPresentationController {
            s.detents = [.medium(), .large()]
            s.prefersGrabberVisible = true
        }
        var top: UIViewController = self
        while let p = top.presentedViewController { top = p }
        top.present(host, animated: true)
    }
}

/// The Google Docs panel's state for one block: the link (from the board), the hub's status, Sync now and Google's versions.
@MainActor @Observable
final class GoogleDocsPanelModel {
    weak var board: BoardController?
    let id: String
    let path: String
    var link: GoogleDocLink?
    var hub: GoogleHubState?
    var round: GoogleLinkRound?
    var busy = false
    struct Version: Identifiable { let id: String; let when: String; let by: String }
    var versions: [Version]?
    var versionsError: String?
    var more = 0

    init(board: BoardController, id: String) {
        self.board = board
        self.id = id
        path = board.googlePath(id)
        link = board.googleOf(id)
    }

    var panel: GooglePanel { GooglePanel.model(g: link, hub: hub, link: round ?? hub?.link(for: path)) }

    /// The hub's status, again every few seconds while the panel is open.
    func watch() async {
        while !Task.isCancelled {
            link = board?.googleOf(id)
            await look()
            if link?.url != nil, versions == nil, versionsError == nil { await loadVersions() }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    func look() async {
        do { hub = GoogleHubState(status: try await HubAsk.call("GET", "/v1/google/status", timeout: 8)) }
        catch let e as HubAsk.Failure { hub = GoogleHubState(state: e.kind == "nohub" ? "nohub" : "error", error: e.words) }
        catch { hub = GoogleHubState(state: "error", error: error.localizedDescription) }
    }

    func loadVersions() async {
        do {
            let r = try await HubAsk.call("GET", "/v1/google/revisions", query: [("path", path)])
            let all = r["versions"]?.array ?? []
            versions = all.prefix(8).map { v in
                Version(id: v["id"]?.string ?? UUID().uuidString, when: GooglePanel.ago(v["at"]?.string ?? ""), by: v["by"]?.string ?? "")
            }
            more = max(0, all.count - 8)
            versionsError = nil
        } catch {
            versionsError = (error as? HubAsk.Failure)?.kind == "nohub" ? "Sync with the hub is not set up." : error.localizedDescription
        }
    }

    func syncNow() async {
        busy = true
        defer { busy = false }
        do {
            let r = try await HubAsk.call("POST", "/v1/google/sync", query: [("path", path)], timeout: 60)
            round = GoogleLinkRound(r)
            board?.toast(round?.state == "error" ? "Google Docs: \(round?.error ?? "")" : "In step with the Doc.")
        } catch let e as HubAsk.Failure {
            board?.toast(e.kind == "nohub" ? "Set up sync with the hub first: Google Docs runs there." : "Google Docs: \(e.words)")
        } catch {
            board?.toast("Google Docs: \(error.localizedDescription)")
        }
        await look()
        if link?.url != nil { await loadVersions() }
    }

    func run(_ a: GooglePanel.Act, close: () -> Void) {
        guard let b = board else { return }
        switch a {
        case .settings: b.toast("Set up Settings › Sync here; Google Docs is connected from the laptop's Settings › Sync.")
        case .make: b.makeGoogleDoc(id)
        case .link: close(); b.askGoogleLink(id)
        case .push, .pull: b.chooseGoogleSide(id, a.rawValue)
        case .open: if let u = link?.url.flatMap(URL.init(string:)) { UIApplication.shared.open(u) }
        case .sync, .retry: Task { await syncNow() }
        case .unlink: b.unlinkGoogle(id)
        }
        link = b.googleOf(id)
    }
}

/// The Writing view's and the block menu's Google Docs panel (the laptop's GooglePanel in gdocs.tsx, as a sheet).
struct GoogleDocsPanelView: View {
    @State var model: GoogleDocsPanelModel
    @Environment(\.dismiss) private var dismiss

    private static let acts: [GooglePanel.Act: (label: String, symbol: String, main: Bool)] = [
        .settings: ("Settings › Sync", "gearshape", false),
        .make: ("Make a Google Doc from this block", "doc.badge.plus", true),
        .link: ("Link to a Google Doc…", "link", false),
        .push: ("Keep this block's words", "arrow.up.doc", true),
        .pull: ("Keep the Doc's words", "arrow.down.doc", false),
        .open: ("Open in Google Docs", "globe", true),
        .sync: ("Sync now", "arrow.clockwise", false),
        .retry: ("Try again", "arrow.clockwise", true),
        .unlink: ("Unlink", "xmark", false),
    ]

    var body: some View {
        let m = model.panel
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(tone(m.tone)).frame(width: 9, height: 9)
                        Text(m.head).font(.headline).accessibilityIdentifier("gdocs-head")
                    }
                    ForEach(m.lines, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(m.actions, id: \.self) { a in
                        let x = Self.acts[a]!
                        let label = (a == .sync || a == .retry) && model.busy ? (a == .sync ? "Syncing…" : "Trying…") : x.label
                        Button(role: a == .unlink ? .destructive : nil) { model.run(a) { dismiss() } } label: {
                            Label(label, systemImage: x.symbol).fontWeight(x.main ? .semibold : .regular)
                        }
                        .disabled(model.busy && (a == .sync || a == .retry))
                        .accessibilityIdentifier("gdocs-\(a.rawValue)")
                    }
                }
                if let g = model.link, let url = g.url {
                    let st = model.round ?? model.hub?.link(for: model.path)
                    Section("Document") {
                        Text(url.replacingOccurrences(of: "https://", with: "")).font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        LabeledContent("Tabs", value: "\(st?.tabs ?? 1)")
                        LabeledContent("Comments", value: "\(st?.comments ?? 0)")
                        LabeledContent("Suggestions", value: "\(st?.suggestions ?? 0)")
                        if let l = model.hub?.label { Text("The hub syncs it as \(l), even with your devices off.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("Recent edits in the Doc") {
                        if let e = model.versionsError { Text(e).foregroundStyle(.secondary) }
                        else if let v = model.versions {
                            if v.isEmpty { Text("Google has no versions of this Doc yet.").foregroundStyle(.secondary) }
                            ForEach(v) { r in LabeledContent(r.by.isEmpty ? "Someone" : r.by, value: r.when) }
                            if model.more > 0 { Text("\(model.more) earlier.").font(.footnote).foregroundStyle(.secondary) }
                        } else { Text("Asking Google…").foregroundStyle(.secondary) }
                        Text("To go back to one, open the Doc and use File › Version history; the block follows.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Goes both ways") {
                    Text("Words, headings, lists, tables, links and text styles; comments and their replies; suggestions; tabs. The hub checks every few seconds while either side changes, every 30 seconds when quiet.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Google Docs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .accessibilityIdentifier("gdocs-panel")
        .task { await model.watch() }
    }

    private func tone(_ t: GooglePanel.Tone) -> Color {
        switch t {
        case .ok: return .green
        case .warn: return .orange
        case .busy: return .blue
        case .idle, .off: return .gray
        }
    }
}
