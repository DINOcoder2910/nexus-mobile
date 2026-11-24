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
        if extras || extrasTask { runExtras(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestPerson") { person(store) }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestBigBoard") { bigBoard(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestLinksBoard") { linksBoard(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestTime") { timeSessions(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestDayOrder") { dayOrder(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestDayEdges") { dayEdges(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestBank") { questionBank(store); return }
        if ProcessInfo.processInfo.arguments.contains("-NexusTestDrop") { dropFiles(store); return }
        guard ProcessInfo.processInfo.arguments.contains("-NexusTestPdfBoard") else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        sharedPens(store)
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

    /// With `-NexusTestPdfBoard`: `-NexusTestSharedPens` puts a pens file in the data folder as the laptop writes it (the pen red at
    /// Bold, Bold set wider on the laptop, the highlighter at Fine, the eraser on part of a stroke, a part only the laptop knows;
    /// UITests/SharedPensTests); without it, a pens file an earlier test left is taken away, so every other test starts with none.
    static func sharedPens(_ store: NexusStore) {
        let url = store.folder.appendingPathComponent(Pens.file)
        guard BoardTools.testShared else { try? FileManager.default.removeItem(at: url); return }
        let text = """
        {
          "format": "nexus-pens/1",
          "pen": {
            "color": "#D93025FF",
            "step": 4
          },
          "marker": {
            "color": "#9BE7A0FF",
            "step": 1
          },
          "widths": {
            "pen": [1.0, 1.5, 3.0, 4.5, 8.0, 10.0]
          },
          "eraser": "part",
          "ring": {
            "tools": ["pen"]
          }
        }

        """
        try? FolderAccess.write(url, text)
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
    /// `-NexusTestLassoBox`: XCUITest can only drag in straight lines, so with the Select tool a straight drag picks the strokes in
    /// the box it spans, as a lasso round them would (BoardController+PenExtras.swift; UITests/PenExtrasTests). PencilKit's own
    /// lasso holds nothing then, so the pick is the board's own, as after a restyle.
    static var isLassoBoxRun: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestLassoBox") }

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
    /// `-NexusTestDrop` (UITests/DropTests): sample data, then Drop/ as a sync would leave it: a photo and a PDF from the laptop,
    /// notes from the iPhone (or the iPad on an iPhone), a sheet put in the G14's Drop by hand, and a photo sent from here, with
    /// this device's record of who sent what; Drop never looked at, so the sidebar counts the arrivals. Made again at every launch.
    static func dropFiles(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        let fm = FileManager.default
        let dir = store.folder.appendingPathComponent(DropFolder.folder, isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let other = Device.isPhone ? "iPad" : "iPhone"
        func picture(_ top: UIColor, _ bottom: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 640, height: 480)).jpegData(withCompressionQuality: 0.85) { c in
                let colors = [top.cgColor, bottom.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    c.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 480), options: [])
                }
                UIColor.white.withAlphaComponent(0.85).setFill()
                UIBezierPath(ovalIn: CGRect(x: 420, y: 70, width: 120, height: 120)).fill()
                UIColor.black.withAlphaComponent(0.35).setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 360, width: 640, height: 120)).fill()
            }
        }
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { c in
            c.beginPage()
            ("Redox: half-equations" as NSString).draw(at: CGPoint(x: 60, y: 70), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 24)])
            ("Atoms, then O with water, then H with H+, then the charge with electrons." as NSString)
                .draw(in: CGRect(x: 60, y: 120, width: 475, height: 200), withAttributes: [.font: UIFont.systemFont(ofSize: 15)])
        }
        let files: [(String, Data, String, Double, Bool)] = [
            ("IMG_0042.jpg", picture(.systemTeal, .systemIndigo), "Duo", 2, false),
            ("Redox notes.pdf", pdf, "Duo", 50, false),
            ("Essay outline.txt", Data("Intro\nThree points\nConclusion\n".utf8), other, 190, false),
            ("Physics data.csv", Data("t,x\n0,0\n1,4.9\n2,19.6\n".utf8), "G14", 26 * 60, false),
            ("Whiteboard.jpg", picture(.systemOrange, .systemPink), "", 30 * 60, true),
        ]
        let now = Date()
        var items: [DropItem] = []
        for (name, data, from, minutesAgo, here) in files {
            let at = now.addingTimeInterval(-minutesAgo * 60)
            let url = dir.appendingPathComponent(name)
            try? data.write(to: url)
            try? fm.setAttributes([.modificationDate: at], ofItemAtPath: url.path)
            items.append(DropItem(path: DropFolder.folder + "/" + name, from: from, at: DropFolder.stamp(at), here: here))
        }
        // the record as the sync client leaves it (oldest given first, so the newest ends on top)
        try? fm.removeItem(at: store.folder.appendingPathComponent(DropFolder.logPath))
        try? DropLog.note(items.reversed(), in: store.folder)
        UserDefaults.standard.removeObject(forKey: "dropSeen")
        store.reload()
    }

    static func timeSessions(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        guard TimeTracker.shared.entries.isEmpty else {
            // an earlier test on this simulator stopped it (LiveActivityPhoneTests stops it from the Lock Screen): it runs again
            guard TimeTracker.shared.current == nil else { return }
            let now = Date()
            let url = store.folder.appendingPathComponent(TimeLog.file(device: TimeTracker.device, start: now))
            let e = TimeLog.Entry(task: "smp8", title: "Redox worksheet", start: TimeLog.stamp(now.addingTimeInterval(-25 * 60)))
            let before = try? FolderAccess.read(url)
            try? FolderAccess.write(url, TimeLog.append(before, device: TimeTracker.device, e))
            store.reload()
            return
        }
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
    /// `-NexusTestDayEdges`: sample data, then a task tonight at 21:30 for 3 hours (past the day's 10 pm line), five tasks crowded
    /// into tomorrow morning and one alone in the evening, so the day's hours must reach midnight, Tomorrow's strip labels must not
    /// overlap, and a label with room must still show (UITests/TodayEdgesTests).
    static func dayEdges(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        let tomorrow = Days.add(store.today, 1)
        let adds: [(String, String, String, String)] = [
            ("Physics IA lock in", store.today, "21:30", "3h"),
            ("Chemistry practice paper", tomorrow, "08:30", "1h"),
            ("TOK essay draft", tomorrow, "09:30", "1h"),
            ("Advisory form", tomorrow, "11:30", "30m"),
            ("Flex reading", tomorrow, "12:00", "45m"),
            ("MathAA problem set", tomorrow, "13:00", "1h"),
            ("Evening run", tomorrow, "19:00", "1h"),
        ]
        for (title, day, time, est) in adds where !store.snapshot.tasks.values.contains(where: { $0.text == title }) {
            _ = store.add(title: title, workstream: "physics-hl", plan: [PlanEntry(day: day, time: time)], est: est)
        }
    }

    /// `-NexusTestBank`: sample data, then Chemistry HL's question bank as the laptop leaves it (UITests/BankTests, BankPhoneTests): three
    /// sample papers sorted (`study/questions.yaml`, written fresh at each launch), a mark, Review later, a pin and a bookmark
    /// (`study/question-marks.yaml`), and the Acids paper's board in a notebook filed under the subject (notebook.json), with
    /// writing under question 2. The notebook is "Bank check", never a "Chemistry" one (SidebarTreeTests expects none at the top).
    static func questionBank(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        let chem = "classes/chemistry-hl", sheets = chem + "/files/Sheets"
        let acids = sheets + "/08 Reactivity 3 — Acids and bases/Acids — Paper 2 structured, 40 mk [2025]/Acids paper 2.pdf"
        let atomic = sheets + "/01 Structure 1 — Models of matter/Mole & Atomic Structure — HL test, 40 mk, 60 min [pre-2025]/Atomic structure test.pdf"
        let energetics = sheets + "/05 Reactivity 1 — Energetics/Energetics — HL test, 30 mk, no MS [2025]/Energetics test.pdf"
        func j(_ s: String) -> String { JSONValue.string(s).text }
        // where the sample PDFs' lines are (SampleFolder.pdf: 18 pt title at 770, then a line every 26 pt on a 842 pt page)
        let one = #"{"page":0,"y":0.1057}"#, two = #"{"page":0,"y":0.1366}"#, end = #"{"page":0,"y":1.0}"#
        let questions = """
        # Written by Nexus (Study › Question bank): each question of your papers, sorted once per paper.
        # facts = the paper's year, session, paper and level; questions = the sort (by the decision model or Claude, with how sure);
        # mine = what you changed by hand, which a new sort never overwrites.
        papers:
          \(j(acids)):
            facts: {"year":2025,"session":"May","paper":"2","level":"HL","sorted":"2026-11-22","by":"decider+claude"}
            questions:
              "1": {"topics":["R3.1"],"type":"short","difficulty":3.0,"marks":1,"command":"calculate","sure":0.93,"by":"decider","from":\(one),"to":\(two)}
              "2": {"topics":["R3.1"],"type":"structured","difficulty":5.5,"marks":2,"command":"explain","by":"claude","model":{"topics":["R3.2"],"sure":0.41},"from":\(two),"to":\(end)}
          \(j(atomic)):
            facts: {"year":2023,"session":"November","paper":"2","level":"HL","sorted":"2026-11-21","by":"decider"}
            questions:
              "1": {"topics":["S1.4"],"type":"short","difficulty":2.0,"marks":2,"command":"calculate","sure":0.97,"by":"decider","from":\(one),"to":\(two)}
              "2": {"topics":["S1.3"],"type":"short","difficulty":4.0,"marks":1,"command":"state","sure":0.88,"by":"decider","from":\(two),"to":\(end)}
          \(j(energetics)):
            facts: {"level":"HL","sorted":"2026-11-22","by":"decider"}
            questions:
              "1": {"topics":["R1.1"],"type":"short","difficulty":3.5,"marks":2,"command":"define","sure":0.9,"by":"decider","from":\(one),"to":\(two)}
              "2": {"topics":["R1.2"],"type":"data","difficulty":7.0,"marks":4,"command":"draw","sure":0.86,"by":"decider","from":\(two),"to":\(end)}
            mine:
              "2": {"type":"structured"}

        """
        let marks = """
        # Written by Nexus (Study › Question bank): your marks on questions ("<paper>#<question>": done, hard or review),
        # the sheets you pinned as Working on, and where you stopped on each (bookmarks). One line each.
        marks:
          \(j(atomic + "#1")): {"mark":"done","at":"\(Days.add(Days.today(), -1))"}
          \(j(energetics + "#2")): {"mark":"review","at":"\(Days.today())"}
        pins:
          \(j(acids)): "\(Days.today())"
        bookmarks:
          \(j(acids)): "2"

        """
        // the subjects' data booklets (the question page's and the board's Data booklet): chemistry's and physics'
        try? FolderAccess.writeData(store.folder.appendingPathComponent(chem + "/files/IB chemistry data booklet.pdf"), SampleFolder.pdf([
            "Chemistry data booklet", "1. Equations: PV = nRT", "2. Physical constants: R = 8.31 J K-1 mol-1", "9. Periodic table: H 1.01, Fe 55.85, Mn 54.94",
        ]))
        try? FolderAccess.writeData(store.folder.appendingPathComponent("classes/physics-hl/files/IB physics data booklet.pdf"), SampleFolder.pdf([
            "Physics data booklet", "Fundamental constants: g = 9.81 m s-2, c = 3.00 x 10^8 m s-1", "A.1 Kinematics: s = ut + at^2 / 2, v^2 = u^2 + 2as",
        ]))
        try? FolderAccess.write(store.folder.appendingPathComponent(chem + "/study/questions.yaml"), questions)
        try? FolderAccess.write(store.folder.appendingPathComponent(chem + "/study/question-marks.yaml"), marks)
        // the Acids paper's board, as the laptop's Write on it makes it, with an answer written under question 2
        let nb = "notebooks/Bank check"
        let rel = nb + "/Papers/08 Reactivity 3 — Acids and bases/Acids paper 2.board"
        let board = store.folder.appendingPathComponent(rel, isDirectory: true)
        try? FolderAccess.write(store.folder.appendingPathComponent(nb + "/notebook.json"), #"{"format":"nexus-notebook/1","subject":"chemistry-hl"}"# + "\n")
        guard !FileManager.default.fileExists(atPath: board.appendingPathComponent("board.json").path) else { store.didWrite(listChanged: true); return }
        try? FolderAccess.write(board.appendingPathComponent("board.json"), BoardFormat.boardJSON())
        var c = BoardContent()
        c.items = [BoardItem(id: "pdf1", type: "pdf", x: 0, y: 0, fields: [
            ("src", .string(QuestionBank.relTo(board: rel, acids))), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
        ])]
        // three lines of handwriting under question 2 (page y 0.15 to 0.25 of an 820-wide page)
        for (k, y) in [205.0, 245.0, 285.0].enumerated() {
            var pts: [[Double]] = []
            for i in 0..<60 {
                let x = 90 + Double(i) * 7
                pts.append([x, y + sin(Double(i) * 0.9) * 9, 1, 0, Double.pi / 2, Double(i) * 0.01, 2.2, 2.2, 1])
            }
            c.strokes.append(BoardStroke(id: "bank\(k)", ink: "com.apple.ink.pen", color: "#1F3A93FF", points: pts))
        }
        _ = try? BoardFiles.save(c, to: board, write: { u, t in try FolderAccess.write(u, t) })
        store.boardsChanged(listChanged: true)
    }

    /// `-NexusTestPerson`: sample data, then a People group (kind person) with Ms Lee, a counsellor: one session note and a decision
    /// in her notes (UITests/WorkstreamsAndPlannerTests: Sessions and Decisions on a person's page).
    static func person(_ store: NexusStore) {
        if !store.snapshot.isDataFolder { store.makeSample() }
        guard store.workstream("ms-lee") == nil else { return }
        let files: [(String, String)] = [
            ("people/group.yaml", "label: People\nkind: person\n"),
            ("people/ms-lee/workstream.yaml", "id: ms-lee\nname: Ms Lee\nrole: counsellor\ncadence: every two weeks\nstatus: active\n"),
            ("people/ms-lee/\(Days.add(store.today, -9)) College list.md", WorkstreamText.sessionTemplate + "\nTrimmed to twelve schools.\n"),
            ("people/ms-lee/notes.md", "# Ms Lee\n\n## Decisions\n\n- \(Days.add(store.today, -9)) Apply ED to Columbia, not Northwestern: the programme fits.\n"),
        ]
        for (rel, text) in files {
            let url = store.folder.appendingPathComponent(rel)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FolderAccess.write(url, text)
        }
        store.reload()
    }

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
