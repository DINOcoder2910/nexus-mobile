import UIKit
import NexusCore

/// Set-ups only the UI check asks for (UITests/, ui-check.yml), by a launch argument; a normal launch never has one.
@MainActor
enum TestHooks {
    /// `-NexusTestPdfBoard`: sample data, then a notebook "PDF zoom" with a board made from a 3-page PDF of fine print, opened
    /// (UITests/PdfZoomTests: zoomed-in pages must stay drawn).
    static func run(_ store: NexusStore) {
        nestedNotebooks(store)
        guard ProcessInfo.processInfo.arguments.contains("-NexusTestPdfBoard") else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        let dir = "notebooks/PDF zoom"
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        if NotebookActions.names(in: url).contains(where: { $0.hasSuffix(".board") }) { return }
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
        UserDefaults.standard.removeObject(forKey: "openNotebooks")
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
