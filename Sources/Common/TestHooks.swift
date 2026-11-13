import UIKit
import NexusCore

/// Set-ups only the UI check asks for (UITests/, ui-check.yml), by a launch argument; a normal launch never has one.
@MainActor
enum TestHooks {
    /// `-NexusTestPdfBoard`: sample data, then a notebook "PDF zoom" with a board made from a 3-page PDF of fine print, opened
    /// (UITests/PdfZoomTests: zoomed-in pages must stay drawn).
    static func run(_ store: NexusStore) {
        guard ProcessInfo.processInfo.arguments.contains("-NexusTestPdfBoard") else { return }
        if !store.snapshot.isDataFolder { store.makeSample() }
        let dir = "notebooks/PDF zoom"
        let url = store.folder.appendingPathComponent(dir, isDirectory: true)
        if NotebookActions.names(in: url).contains(where: { $0.hasSuffix(".board") }) { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? NotebookActions().newBoard(pdfData: finePrint(), named: "Zoom test", in: dir, store)
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
