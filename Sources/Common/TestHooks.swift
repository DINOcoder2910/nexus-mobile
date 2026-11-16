import UIKit
import NexusCore

/// Set-ups only the UI check asks for (UITests/, ui-check.yml), by a launch argument; a normal launch never has one.
@MainActor
enum TestHooks {
    /// `-NexusTestPdfBoard`: sample data, then a notebook "PDF zoom" with a board made from a 3-page PDF of fine print, opened
    /// (UITests/PdfZoomTests: zoomed-in pages must stay drawn).
    static func run(_ store: NexusStore) {
        if ProcessInfo.processInfo.arguments.contains("-NexusTestBigBoard") { bigBoard(store); return }
        guard ProcessInfo.processInfo.arguments.contains("-NexusTestPdfBoard") else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        let dir = "notebooks/PDF zoom"
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        if NotebookActions.names(in: url).contains(where: { $0.hasSuffix(".board") }) { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? NotebookActions().newBoard(pdfData: finePrint(), named: "Zoom test", in: dir, store)
    }

    /// `-NexusTestBigBoard`: sample data, then a board as full as a long lesson's (4000 handwritten strokes of 60 points over a page
    /// of PDF), opened; the board times its saves (BoardController.saveBench) and UITests/BoardSpeedTests prints the times.
    static var isBigBoardRun: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestBigBoard") }
    /// `-NexusTestSpaceDrag` (with the big board): Insert space is dragged on it, slowly, held for pictures and timed
    /// (BoardController+Bench.swift, UITests/SpaceLiveTests), instead of the save bench.
    static var isSpaceDragRun: Bool { ProcessInfo.processInfo.arguments.contains("-NexusTestSpaceDrag") }

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
