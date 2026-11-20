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

/// The document camera from UIKit: scanned pages, or none when cancelled or it failed. Every scan in the app opens it here (a board's
/// Insert › Scan a handout…, a notebook's New › From a scan…, Study's Upload › Scan pages).
final class ScanCamera: NSObject, VNDocumentCameraViewControllerDelegate {
    private let done: ([UIImage]) -> Void
    private static var open: ScanCamera?

    private init(done: @escaping ([UIImage]) -> Void) { self.done = done }

    /// `-NexusTestFakeScanner` (UITests/ScanTests): a stand-in camera that hands back one made-up page, as the simulator has none.
    static let fake = ProcessInfo.processInfo.arguments.contains("-NexusTestFakeScanner")

    static var isSupported: Bool { fake || VNDocumentCameraViewController.isSupported }

    /// The topmost screen of the key window, for a SwiftUI screen that has no controller of its own.
    static func topOfKeyWindow() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?.keyWindow ?? scenes.compactMap(\.keyWindow).first
        return window?.rootViewController
    }

    /// Shows the scanner over what is showing at `from` (nil: the key window); `done` gets the pages once it is dismissed.
    /// UIKit refuses to present without a word over a controller that is still opening or closing something (the last scan's camera
    /// on its way out), over a popover, or from a controller no longer on screen: then the camera simply never came (the second scan
    /// that wouldn't start). So it waits for what is moving, closes a popover or alert first, presents over a sheet or the Writing
    /// view instead of closing it, and checks the camera really came up: once more from the window's top, then it says so.
    static func present(from: UIViewController?, tries: Int = 0, last: Bool = false, done: @escaping ([UIImage]) -> Void) {
        guard isSupported else { return }
        HangWatch.note("scan: camera asked" + (tries > 0 ? " (try \(tries + 1))" : ""))
        let again = { (from: UIViewController?, last: Bool) in present(from: from, tries: tries + 1, last: last, done: done) }
        guard var top = (from?.viewIfLoaded?.window != nil ? from : nil) ?? topOfKeyWindow() else { didNotOpen(done); return }
        while let shown = top.presentedViewController {
            if shown.isBeingDismissed || shown.isBeingPresented {
                if tries < 12 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { again(from, last) }; return }
                break
            }
            if (shown.modalPresentationStyle == .popover || shown is UIAlertController), tries < 12 {
                top.dismiss(animated: false) { again(from, last) }
                return
            }
            top = shown
        }
        let me = ScanCamera(done: done)
        open = me // the camera holds its delegate weakly
        let vc: UIViewController
        if fake {
            vc = FakeScanner(camera: me)
        } else {
            let cam = VNDocumentCameraViewController()
            cam.delegate = me
            vc = cam
        }
        vc.modalPresentationStyle = .fullScreen
        top.present(vc, animated: true) { HangWatch.note("scan: camera up") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard ScanCamera.open === me, vc.presentingViewController == nil else { return }
            ScanCamera.open = nil
            HangWatch.note("scan: the camera didn't open over \(type(of: top))")
            if last { didNotOpen(done) } else { present(from: nil, tries: 0, last: true, done: done) }
        }
    }

    private static func didNotOpen(_ done: @escaping ([UIImage]) -> Void) {
        HangWatch.note("scan: gave up")
        done([])
        guard var top = topOfKeyWindow() else { return }
        while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
        let a = UIAlertController(title: "The camera didn't open", message: "Try scanning again in a moment.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        top.present(a, animated: true)
    }

    fileprivate func finish(_ controller: UIViewController, _ pages: [UIImage]) {
        HangWatch.note("scan: camera closed, \(pages.count) pages")
        let done = self.done
        ScanCamera.open = nil
        controller.dismiss(animated: true) { done(pages) }
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        finish(controller, (0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { finish(controller, []) }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { finish(controller, []) }
}

/// The UI check's camera (`-NexusTestFakeScanner`): "Finish fake scan" hands back one page with a title printed on it.
private final class FakeScanner: UIViewController {
    private let camera: ScanCamera
    init(camera: ScanCamera) { self.camera = camera; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let finish = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Finish fake scan") { [weak self] _ in
            guard let self else { return }
            self.camera.finish(self, [Self.page()])
        })
        let cancel = UIButton(configuration: .gray(), primaryAction: UIAction(title: "Cancel fake scan") { [weak self] _ in
            guard let self else { return }
            self.camera.finish(self, [])
        })
        let stack = UIStackView(arrangedSubviews: [finish, cancel])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: view.centerXAnchor), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
    }

    static func page() -> UIImage {
        let size = CGSize(width: 1240, height: 1754)
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let title = NSAttributedString(string: "Redox worksheet", attributes: [.font: UIFont.boldSystemFont(ofSize: 72), .foregroundColor: UIColor.black])
            title.draw(at: CGPoint(x: 120, y: 160))
            let body = NSAttributedString(string: "Balance each half equation.", attributes: [.font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor.black])
            body.draw(at: CGPoint(x: 120, y: 320))
        }
    }
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
