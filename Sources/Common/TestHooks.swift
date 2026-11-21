import UIKit
import NexusCore

/// Set-ups only the UI check asks for (UITests/, ui-check.yml), by a launch argument; a normal launch never has one.
@MainActor
enum TestHooks {
    /// `-NexusTestPdfBoard`: sample data, then a notebook "PDF zoom" with a board made from a 3-page PDF of fine print, opened
    /// (UITests/PdfZoomTests: zoomed-in pages must stay drawn).
    static func run(_ store: NexusStore) {
        nestedNotebooks(store)
        manyNotebooks(store)
        if ProcessInfo.processInfo.arguments.contains("-NexusTestBigBoard") { bigBoard(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestLinksBoard") { linksBoard(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestTime") { timeSessions(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestDayOrder") { dayOrder(store); return }
        guard ProcessInfo.processInfo.arguments.contains("-NexusTestPdfBoard") else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        let dir = "notebooks/PDF zoom"
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        // made by an earlier test on this simulator: open it again (UITests/PenOptionsTests runs after PdfZoomTests)
        if let made = NotebookActions.names(in: url).first(where: { $0.hasSuffix(".board") }) {
            store.openBoard = .init(path: dir + "/" + made, focus: nil)
            return
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? NotebookActions().newBoard(pdfData: finePrint(), named: "Zoom test", in: dir, store)
    }

    /// `-NexusTestNestedNotebooks`: sample data, then notebooks nested three deep with boards at each level and notebook.json
    /// orders that are not by name, as the laptop's OneNote import writes them, every notebook closed in the sidebar and no Recent
    /// boards (UITests/SidebarTreeTests). `-NexusTestDark` puts the window in dark mode.
    static func nestedNotebooks(_ store: NexusStore) {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-NexusTestDark") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.windows.forEach { $0.overrideUserInterfaceStyle = .dark }
            }
        }
        guard args.contains("-NexusTestNestedNotebooks") else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        // the speed test's 1,440 boards (SidebarSpeedTests, same simulator) would push this tree out of reach
        var removed = false
        for name in NotebookActions.names(in: store.folder.appendingPathComponent(BoardFormat.notebooks)) where name.hasPrefix("G12 Notebook ") {
            try? FileManager.default.removeItem(at: store.folder.appendingPathComponent(BoardFormat.notebooks).appendingPathComponent(name))
            removed = true
        }
        if removed { store.boardsChanged(listChanged: true) }
        UserDefaults.standard.removeObject(forKey: "openNotebooks")
        UserDefaults.standard.removeObject(forKey: "openSubjects") // every subject closed too (NewLookTests opens one)
        UserDefaults.standard.removeObject(forKey: RecentBoards.key)
        let root = store.folder
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent("notebooks/School").path) else { return }
        let boards = [
            "notebooks/School/Chemistry/R3 Energetics/Week 2/Lattice enthalpy.board",
            "notebooks/School/Chemistry/R3 Energetics/Week 2/Born-Haber cycles.board",
            "notebooks/School/Chemistry/R3 Energetics/Week 1/Calorimetry.board",
            "notebooks/School/Chemistry/R3 Energetics/Week 1/Enthalpy of combustion.board",
            "notebooks/School/Chemistry/R3 Energetics/Hess's law.board",
            "notebooks/School/Chemistry/R3 Energetics/Bond enthalpy.board",
            "notebooks/School/Chemistry/R1 Structure/Ions.board",
            "notebooks/School/Chemistry/Syllabus.board",
            "notebooks/School/Biology/Cells.board",
            "notebooks/Spanish/Verbs.board",
            "notebooks/Spanish/Vocab.board",
        ]
        let metas = [
            "notebooks/School": ##"{"format": "nexus-notebook/1", "color": "#007F43", "order": ["Chemistry", "Biology"]}"##,
            "notebooks/School/Chemistry": #"{"order": ["R3 Energetics", "R1 Structure", "Syllabus.board"]}"#,
            "notebooks/School/Chemistry/R3 Energetics": #"{"order": ["Week 2", "Week 1", "Hess's law.board", "Bond enthalpy.board"]}"#,
            "notebooks/School/Chemistry/R3 Energetics/Week 2": #"{"order": ["Lattice enthalpy.board", "Born-Haber cycles.board"]}"#,
            "notebooks/Spanish": ##"{"format": "nexus-notebook/1", "color": "#A14174"}"##,
        ]
        for b in boards {
            try? FolderAccess.write(root.appendingPathComponent(b).appendingPathComponent("board.json"), BoardFormat.boardJSON())
        }
        for (dir, json) in metas {
            try? FolderAccess.write(root.appendingPathComponent(dir).appendingPathComponent(NotebookMeta.file), json + "\n")
        }
        store.boardsChanged(listChanged: true)
    }

    /// `-NexusTestManyNotebooks`: sample data, then a folder the size of the OneNote import (12 notebooks of 10 sections, 12 boards
    /// in each: 1,440 boards, each with a PDF beside it in its section as the import leaves them), every notebook closed
    /// (UITests/SidebarSpeedTests: the sidebar must stay quick).
    static func manyNotebooks(_ store: NexusStore) {
        guard ProcessInfo.processInfo.arguments.contains("-NexusTestManyNotebooks") else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        UserDefaults.standard.removeObject(forKey: "openNotebooks")
        UserDefaults.standard.removeObject(forKey: RecentBoards.key)
        let root = store.folder
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent("notebooks/G12 Notebook 01").path) else { return }
        let board = Data(BoardFormat.boardJSON().utf8), fm = FileManager.default
        for n in 1...12 {
            let nb = String(format: "notebooks/G12 Notebook %02d", n)
            for s in 1...10 {
                let sec = nb + String(format: "/Section %02d", s)
                for b in 1...12 {
                    let dir = root.appendingPathComponent(sec + String(format: "/Page %02d.board", b))
                    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    try? board.write(to: dir.appendingPathComponent("board.json"))
                }
                try? Data("%PDF-1.4\n".utf8).write(to: root.appendingPathComponent(sec + "/Handout.pdf"))
            }
        }
        store.boardsChanged(listChanged: true)
    }

    /// `-NexusTestBigBoard`: sample data, then a board as full as a long lesson's (4000 handwritten strokes of 60 points over a page
    /// of PDF), opened; the board times its saves (BoardController.saveBench) and UITests/BoardSpeedTests prints the times.
    static var isBigBoardRun: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestBigBoard") }
    /// `-NexusTestSpaceDrag` (with the big board): Insert space is dragged on it, slowly, held for pictures and timed
    /// (BoardController+Bench.swift, UITests/SpaceLiveTests), instead of the save bench.
    static var isSpaceDragRun: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestSpaceDrag") }
    /// `-NexusTestPenProbe`: each stroke drawn shows its ink and width in a label (BoardController+Bench.swift penProbe,
    /// UITests/PenOptionsTests), so the check reads the width written instead of guessing it from a picture.
    static var isPenProbeRun: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestPenProbe") }

    static func bigBoard(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        let dir = "notebooks/Speed"
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        if !NotebookActions.names(in: url).contains(where: { $0.hasSuffix(".board") }) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var items: [BoardItem] = []
            let pdf = "Lesson handout.pdf"
            if (try? finePrint().write(to: url.appendingPathComponent(pdf))) != nil {
                items.append(BoardItem(id: "pdf1", type: "pdf", x: 60, y: 60, fields: [
                    ("src", .string("../" + pdf)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
                ]))
            }
            guard let rel = try? NotebookActions().makeBoard("Long lesson", in: dir, store, items: items) else { return }
            let board = store.folder.appendingPathComponent(rel, isDirectory: true)
            // written away from the main thread (seconds in the debug build), so the UI test can read the screen meanwhile
            DispatchQueue.global(qos: .userInitiated).async {
            if var c = try? BoardFiles.load(board) {
                for i in 0..<4000 {
                    // short wavy strokes in lines down the page, like writing
                    let x0 = 80 + Double((i % 40) * 18), y0 = 80 + Double(i / 40) * 26
                    var pts: [[Double]] = []
                    for k in 0..<60 {
                        let t = Double(k) / 59
                        pts.append([x0 + t * 14, y0 + sin(t * 9) * 6, 0.6, 1.2, 1.1, t * 0.4, 2.4, 2.4, 1])
                    }
                    c.strokes.append(BoardStroke(id: String(format: "s%05d", i), ink: "com.apple.ink.pen", color: "#1A1A1AFF", points: pts))
                }
                _ = try? BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
            }
            Task { @MainActor in store.openBoard = .init(path: rel, focus: nil) }
            }
        } else if let b = NotebookActions.names(in: url).first(where: { $0.hasSuffix(".board") }) {
            store.openBoard = .init(path: dir + "/" + b, focus: nil)
        }
    }

    /// `-NexusTestLinksBoard`: sample data, then a board "Redox" with three typed blocks and two links, opened
    /// (UITests/LinksTests: the links' look, light and dark, and the Links list).
    static func linksBoard(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        let dir = "notebooks/Bridge check" // not a name another UI test looks for (SidebarTreeTests expects no top-level Chemistry)
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        if let b = NotebookActions.names(in: url).first(where: { $0.hasSuffix(".board") }) { store.openBoard = .init(path: dir + "/" + b, focus: nil); return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard let rel = try? NotebookActions().makeBoard("Redox", in: dir, store) else { return }
        let board = store.folder.appendingPathComponent(rel, isDirectory: true)
        guard var c = try? BoardFiles.load(board) else { return }
        let texts = [("t1", 80.0, 80.0, "## Oxidation\nLoss of electrons. The oxidation state goes **up**."),
                     ("t2", 80.0, 420.0, "## Reduction\nGain of electrons. The oxidation state goes **down**."),
                     ("t3", 640.0, 600.0, "OIL RIG: Oxidation Is Loss, Reduction Is Gain")]
        for (id, x, y, md) in texts { c.items.append(BoardItem(id: id, type: "text", x: x, y: y)); c.texts[id] = md }
        if let k1 = BoardLinks.make(id: "k1", a: .object([("on", .string("t1"))]), b: .object([("on", .string("t2"))]), x: 80, y: 80) { c.items.append(k1) }
        if let k2 = BoardLinks.make(id: "k2", a: .object([("on", .string("t2"))]), b: .object([("on", .string("t3"))]), color: BoardLinks.colors[1], x: 80, y: 420) { c.items.append(k2) }
        if let meta = c.meta ?? (try? JSONValue.parse(BoardFormat.boardJSON())) { c.meta = BoardFormat.withFeature(meta, BoardLinks.feature) }
        _ = try? BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
        store.openBoard = .init(path: rel, focus: nil)
    }

    /// `-NexusTestTime`: sample data with time tracked this week on this device and on the laptop, and a timer running on
    /// "Redox worksheet" (UITests/TimeTrackingTests: the running timer, the Time screen, the task panel's Time section).
    static func timeSessions(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        guard TimeTracker.shared.entries.isEmpty else { return }
        let now = Date()
        func at(_ minutesAgo: Double) -> String { TimeLog.stamp(now.addingTimeInterval(-minutesAgo * 60)) }
        func put(_ device: String, _ list: [TimeLog.Entry]) {
            var text: String? = nil
            for e in list { text = TimeLog.append(text, device: device, e) }
            guard let text else { return }
            try? FolderAccess.write(store.folder.appendingPathComponent(TimeLog.file(device: device, start: now)), text)
        }
        let day = 24 * 60.0
        put(TimeTracker.device, [
            .init(task: "smp3", title: "Physics HW sheet", start: at(2 * day + 300), end: at(2 * day + 255)),
            .init(task: "smp4", title: "Q1–5", start: at(day + 200), end: at(day + 150)),
            .init(task: "smp4", title: "Q1–5", start: at(180), end: at(140)),
            .init(task: "smp8", title: "Redox worksheet", start: at(25)),
        ])
        put("laptop", [
            .init(task: "smp9", title: "Flashcards for R3.2", start: at(3 * day + 120), end: at(3 * day + 60)),
            .init(task: "smp8", title: "Redox worksheet", start: at(day + 90), end: at(day + 20)),
            .init(task: "smpb", title: "Try the iPad planner", start: at(110), end: at(95)),
        ])
        store.reload()
    }

    /// `-NexusTestDayOrder`: sample data, then today's order as if dragged on the laptop (`nexus-day-order.yaml`): "Try the iPad
    /// planner" before "Redox worksheet", against their file order (UITests/DayOrderTests).
    static func dayOrder(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        let text = DayOrder.text([store.today: ["smpb", "smp8"]], today: store.today)
        try? FolderAccess.write(store.folder.appendingPathComponent(DayOrder.file), text)
        store.reload()
    }

    /// Three letter pages of small numbered lines and a fine grid, so a blurry or missing page shows at any zoom.
    static func finePrint() -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            for p in 1...3 {
                ctx.beginPage()
                let cg = ctx.cgContext
                cg.setStrokeColor(UIColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 0.35).cgColor)
                cg.setLineWidth(0.25)
                for x in stride(from: 36.0, through: 576, by: 6) { cg.move(to: CGPoint(x: x, y: 36)); cg.addLine(to: CGPoint(x: x, y: 756)) }
                for y in stride(from: 36.0, through: 756, by: 6) { cg.move(to: CGPoint(x: 36, y: y)); cg.addLine(to: CGPoint(x: 576, y: y)) }
                cg.strokePath()
                let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 22), .foregroundColor: UIColor.black]
                ("Page \(p): zoom test" as NSString).draw(at: CGPoint(x: 48, y: 44), withAttributes: title)
                let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 5), .foregroundColor: UIColor.black]
                for line in 0..<110 {
                    let s = "Line \(line + 1) of page \(p). The quick brown fox jumps over the lazy dog; ΔH = −393.5 kJ mol⁻¹, 2H₂ + O₂ → 2H₂O."
                    (s as NSString).draw(at: CGPoint(x: 48, y: 80 + Double(line) * 6), withAttributes: small)
                }
            }
        }
    }
}
