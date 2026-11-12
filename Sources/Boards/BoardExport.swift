import UIKit
import PDFKit
import NexusCore

/// Share as PDF: the whole board as A4-shaped pages across the width of what is on it, top to bottom. PDF printouts are drawn from
/// the PDF itself (sharp), then the other items as they show on the board, then the ink.
enum BoardExport {
    static func pdf(root: URL, path: String) -> URL? {
        let b = BoardController(root: root, path: path, focus: nil)
        b.replay = true // read-only, nothing logged
        b.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        b.view.layoutIfNeeded()
        b.poll?.invalidate()
        guard let box = b.contentBounds() else { return nil }
        let pad: CGFloat = 40
        let w = box.width + 2 * pad
        let pageW: CGFloat = 595, pageH: CGFloat = 842 // A4 in points
        let span = w * pageH / pageW
        let n = max(1, Int(ceil((box.height + 2 * pad) / span)))
        let k = pageW / w
        let name = String((path as NSString).lastPathComponent.dropLast(6))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(BoardFormat.freeName(name, taken: []) + ".pdf")
        let r = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageW, height: pageH))
        do {
            try r.writePDF(to: out) { ctx in
                for i in 0..<n {
                    ctx.beginPage()
                    let rect = CGRect(x: box.minX - pad, y: box.minY - pad + CGFloat(i) * span, width: w, height: span)
                    draw(b, rect, in: ctx.cgContext, k: k, page: CGRect(x: 0, y: 0, width: pageW, height: pageH))
                }
            }
        } catch { return nil }
        return out
    }

    /// The part `rect` of the board (board units) into `cg`, `k` points per unit.
    static func draw(_ b: BoardController, _ rect: CGRect, in cg: CGContext, k: CGFloat, page: CGRect) {
        UIColor.white.setFill()
        cg.fill(page)
        // printouts
        for p in b.pdfs.values {
            for (i, f) in p.frames.enumerated() where f.intersects(rect) {
                guard let pg = p.doc.page(at: i) else { continue }
                let size = PdfPrintout.displaySize(pg)
                cg.saveGState()
                cg.translateBy(x: (f.minX - rect.minX) * k, y: (f.maxY - rect.minY) * k)
                cg.scaleBy(x: f.width * k / size.width, y: -f.height * k / size.height)
                pg.transform(cg, for: .mediaBox)
                pg.draw(with: .mediaBox, to: cg)
                cg.restoreGState()
            }
        }
        // images, shapes, text (the board's own views, printouts hidden)
        let hidPdf = b.pdfLayer.isHidden, hidSel = b.selection.isHidden
        b.pdfLayer.isHidden = true
        b.selection.isHidden = true
        cg.saveGState()
        cg.scaleBy(x: k, y: k)
        cg.translateBy(x: -(rect.minX + b.offset.x), y: -(rect.minY + b.offset.y))
        b.world.layer.render(in: cg)
        cg.restoreGState()
        b.pdfLayer.isHidden = hidPdf
        b.selection.isHidden = hidSel
        // ink
        let inkRect = rect.offsetBy(dx: b.offset.x, dy: b.offset.y)
        if !b.canvas.drawing.strokes.isEmpty, b.canvas.drawing.bounds.intersects(inkRect) {
            b.canvas.drawing.image(from: inkRect, scale: 2).draw(in: page)
        }
    }
}
