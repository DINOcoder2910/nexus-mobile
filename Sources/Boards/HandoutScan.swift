import UIKit
import CoreText
import Vision
import VisionKit
import NexusCore

/// Scan a handout: the camera's document scanner, then the pages made into one PDF printout. Each page keeps its picture and gets
/// the words read from it (on the iPad or iPhone, offline) laid invisibly over it, so the scan can be searched, selected and read
/// aloud like any other PDF, here and on the laptop. The PDF is named after the handout's title when one can be read.
enum ScanPDF {
    struct Result {
        let data: Data
        /// "Redox reactions worksheet", or "Handout 2026-11-12 1405"
        let name: String
        /// pages that had words on them
        let readPages: Int
    }

    /// Builds the PDF away from the main thread (reading the words takes a moment a page), then hands it back on the main thread.
    static func make(_ pages: [UIImage], done: @escaping (Result?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let r = build(pages)
            DispatchQueue.main.async { done(r) }
        }
    }

    static func build(_ pages: [UIImage]) -> Result? {
        guard !pages.isEmpty else { return nil }
        var firstPage: [Handout.Line] = []
        var readPages = 0
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: "Nexus"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792), format: format)
        let data = renderer.pdfData { ctx in
            for (i, page) in pages.enumerated() {
                autoreleasepool {
                    guard let img = upright(page) else { return }
                    let s = Handout.pageSize(width: Double(img.size.width), height: Double(img.size.height))
                    let size = CGSize(width: s.w, height: s.h)
                    ctx.beginPage(withBounds: CGRect(origin: .zero, size: size), pageInfo: [:])
                    // as a JPEG, so a page is a few hundred KB, not a few MB
                    let pic = img.jpegData(compressionQuality: 0.7).flatMap { UIImage(data: $0) } ?? img
                    pic.draw(in: CGRect(origin: .zero, size: size))
                    let lines = readLines(img)
                    if !lines.isEmpty { readPages += 1 }
                    if i == 0 { firstPage = lines }
                    writeInvisibly(lines, in: ctx.cgContext, size: size)
                }
            }
        }
        return Result(data: data, name: Handout.name(firstPage, at: Date()), readPages: readPages)
    }

    /// The page drawn upright at most `Handout.keepWidth` pixels wide (the scanner's pictures are bigger than a board needs).
    static func upright(_ img: UIImage) -> UIImage? {
        let px = CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale)
        guard px.width > 0, px.height > 0 else { return nil }
        let k = min(1, CGFloat(Handout.keepWidth) / px.width)
        let size = CGSize(width: (px.width * k).rounded(), height: (px.height * k).rounded())
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        f.opaque = true
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// The lines of text on a page (Vision's accurate reader; English and Spanish).
    static func readLines(_ img: UIImage) -> [Handout.Line] {
        guard let cg = img.cgImage else { return [] }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["en-US", "es-ES"]
        do { try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([req]) } catch { return [] }
        return (req.results ?? []).compactMap { o in
            guard let text = o.topCandidates(1).first?.string, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let b = o.boundingBox
            return Handout.Line(text, x: Double(b.minX), y: Double(b.minY), w: Double(b.width), h: Double(b.height))
        }
    }

    /// Each line written over its place on the page in invisible text (as scanners do), stretched to the width it takes there.
    static func writeInvisibly(_ lines: [Handout.Line], in cg: CGContext, size: CGSize) {
        guard !lines.isEmpty else { return }
        cg.saveGState()
        cg.setTextDrawingMode(.invisible)
        for l in lines {
            let r = Handout.rect(l, pageW: Double(size.width), pageH: Double(size.height))
            guard r.w > 2, r.h > 2 else { continue }
            let font = UIFont(name: "Helvetica", size: CGFloat(r.h) * 0.9) ?? UIFont.systemFont(ofSize: CGFloat(r.h) * 0.9)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: l.text, attributes: [.font: font]) as CFAttributedString)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let w = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            guard w > 0 else { continue }
            // the renderer draws from the top left (y down): flip the glyphs back up, and stretch them to the line's width
            cg.textMatrix = CGAffineTransform(scaleX: CGFloat(r.w) / w, y: -1)
            cg.textPosition = CGPoint(x: CGFloat(r.x), y: CGFloat(r.y + r.h) - descent)
            CTLineDraw(line, cg)
        }
        cg.restoreGState()
    }
}

/// The document camera from UIKit: scanned pages, or none when cancelled or it failed.
final class ScanCamera: NSObject, VNDocumentCameraViewControllerDelegate {
    private let done: ([UIImage]) -> Void
    private static var open: ScanCamera?

    private init(done: @escaping ([UIImage]) -> Void) { self.done = done }

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    /// Shows the scanner over `from`; `done` gets the pages once it is dismissed.
    static func present(from: UIViewController, done: @escaping ([UIImage]) -> Void) {
        guard isSupported else { return }
        let me = ScanCamera(done: done)
        open = me // the camera holds its delegate weakly
        let vc = VNDocumentCameraViewController()
        vc.delegate = me
        vc.modalPresentationStyle = .fullScreen
        from.present(vc, animated: true)
    }

    private func finish(_ controller: VNDocumentCameraViewController, _ pages: [UIImage]) {
        let done = self.done
        controller.dismiss(animated: true) { done(pages) }
        ScanCamera.open = nil
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        finish(controller, (0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { finish(controller, []) }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { finish(controller, []) }
}

extension BoardController {
    /// + › Scan a handout: the pages go down the board from where you are looking, as a PDF printout saved beside the board.
    func scanHandout() {
        ScanCamera.present(from: self) { [weak self] pages in
            guard let self, !pages.isEmpty else { return }
            self.toast(pages.count == 1 ? "Reading the handout…" : "Reading the handout's \(pages.count) pages…")
            ScanPDF.make(pages) { [weak self] r in
                guard let self else { return }
                guard let r else { self.tell("Couldn't make a PDF of the scan."); return }
                self.addPdfPrintout(data: r.data, named: r.name, label: "Add scan")
                if r.readPages == 0 { self.toast("No words could be read on the scan, so it can't be searched.") }
            }
        }
    }
}
