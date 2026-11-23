import UIKit
import NexusCore

/// The UI check's set-ups for the last iPad and iPhone extras (UITests/ExtrasTests.swift), by launch argument:
/// - `-NexusTestExtras`: sample data, a board "Docs" whose block is linked to a Google Doc, opened, with its Google Docs panel;
/// - `-NexusTestExtrasTask`: sample data, then the Redox worksheet's task panel (its Activity).
/// Both make the hub's answers up (HubAsk.test), so nothing reaches a network.
extension TestHooks {
    nonisolated static var extras: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestExtras") }
    nonisolated static var extrasTask: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestExtrasTask") }

    static func runExtras(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        if extrasTask {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if store.task("smp8") != nil { store.openTaskId = "smp8" }
            }
            return
        }
        let dir = "notebooks/Extras check"
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        let rel: String
        if let b = NotebookActions.names(in: url).first(where: { $0.hasSuffix(".board") }) {
            rel = dir + "/" + b
        } else {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            guard let made = try? NotebookActions().makeBoard("Docs", in: dir, store) else { return }
            rel = made
            let board = store.folder.appendingPathComponent(made, isDirectory: true)
            guard var c = try? BoardFiles.load(board) else { return }
            c.items.append(BoardItem(id: "t1", type: "text", x: 80, y: 80))
            c.texts["t1"] = "## Redox notes\nOxidation is loss, reduction is gain.\n- Fe²⁺ → Fe³⁺ + e⁻"
            guard let saved = try? BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) }),
                  let jsonl = saved.docsOnDisk["t1"] else { return }
            // linked as the hub's bridge leaves it once the Doc is made
            let g = #"{"doc":"1TestDocRedoxNotes00","url":"https://docs.google.com/document/d/1TestDocRedoxNotes00/edit","title":"Redox notes"}"#
            if let linked = RichWords.shared.setHeader(jsonl, key: "google", json: g) {
                try? FolderAccess.write(board.appendingPathComponent(RichWords.docFile("t1")), linked)
            }
        }
        googleTestPath = rel + "/" + RichWords.docFile("t1")
        store.openBoard = .init(path: rel, focus: nil)
        // the block's Google Docs panel, once the board is up
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            NotificationCenter.default.post(name: openGooglePanel, object: "t1")
        }
    }

    /// `-NexusTestExtras`: the open board shows this block's Google Docs panel.
    nonisolated static let openGooglePanel = Notification.Name("nexus.test.openGooglePanel")

    /// The linked block's file, as the hub's status names it.
    nonisolated(unsafe) static var googleTestPath = ""

    /// What the hub would answer, made up for the UI check.
    nonisolated static func hubAnswer(_ method: String, _ route: String, _ query: [(String, String)]) -> JSONValue {
        let now = Date()
        func iso(_ ago: Double) -> String { ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago)) }
        let path = query.first { $0.0 == "path" }?.1 ?? googleTestPath
        switch route {
        case "/v1/google/status":
            return .object([("enabled", .bool(true)), ("connected", .bool(true)), ("label", .string("your Google account")),
                            ("links", .array([.object([("path", .string(path)), ("state", .string("ok")), ("at", .string(iso(120))),
                                                       ("tabs", .number(1)), ("comments", .number(2)), ("suggestions", .number(0))])]))])
        case "/v1/google/sync":
            return .object([("path", .string(path)), ("state", .string("ok")), ("at", .string(iso(0))), ("tabs", .number(1)), ("comments", .number(2))])
        case "/v1/google/revisions":
            return .object([("versions", .array([
                .object([("id", .string("3")), ("at", .string(iso(3600))), ("by", .string("You"))]),
                .object([("id", .string("2")), ("at", .string(iso(86400 * 2))), ("by", .string("Nexus"))]),
            ]))])
        default:
            return .object([])
        }
    }

    /// The Redox worksheet's file a day and three days ago: renamed by Claude since (the Activity's lines).
    nonisolated static func activityAnswer(path: String, current: String?) -> JSONValue {
        guard let now = current else { return .object([("repo", .bool(true)), ("versions", .array([])), ("trail", .array([]))]) }
        let older = now.replacingOccurrences(of: "title: Redox worksheet\n", with: "title: Redox sheet\n")
        let f = ISO8601DateFormatter()
        let d = Date()
        return .object([("repo", .bool(true)), ("versions", .array([
            .object([("hash", .string("b2")), ("at", .string(f.string(from: d.addingTimeInterval(-86400)))), ("author", .string("Claude")), ("path", .string(path)), ("text", .string(now))]),
            .object([("hash", .string("a1")), ("at", .string(f.string(from: d.addingTimeInterval(-3 * 86400)))), ("author", .string("You")), ("path", .string(path)), ("text", .string(older))]),
        ])), ("trail", .array([]))])
    }
}
