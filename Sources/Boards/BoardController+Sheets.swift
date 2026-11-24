import UIKit
import NexusCore

/// A paper's board, as on the laptop (nexus desktop/src/board/Board.tsx): a Markscheme button in the top row puts the paper's
/// markscheme (paired by name, NexusCore WriteOnIt) in the second pane, and a file icon beside page 1 of each printout shows the
/// clean PDF there, with no ink on it.
extension BoardController {
    /// This board's paper: its first printout's PDF, as a data-folder path.
    var paperOfBoard: String? {
        content.items.filter { $0.type == "pdf" }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }.lazy
            .compactMap { BoardLinks.resolve(self.path, $0.src ?? "") }.first
    }

    /// The markscheme beside a PDF (looked up once per board).
    func markschemeOf(_ pdf: String) -> String? {
        if let hit = msLookup[pdf] { return hit }
        let dir = (pdf as NSString).deletingLastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(dir).path)) ?? []
        let ms = WriteOnIt.markschemePath(for: pdf, names: names)
        msLookup[pdf] = .some(ms)
        return ms
    }

    /// The Markscheme button, when this board's paper has one.
    func sheetBarButtons() -> [UIButton] {
        guard !isSidePane, let pdf = paperOfBoard, let ms = markschemeOf(pdf) else { return [] }
        let on = showingInSide(ms)
        let b = extraButton("rectangle.split.2x1", on ? "Hide the markscheme" : "Markscheme", tinted: on) { [weak self] in self?.toggleMarkscheme(ms) }
        b.accessibilityIdentifier = "board-ms"
        b.toolTip = "The markscheme beside it"
        return [b]
    }

    private func showingInSide(_ rel: String) -> Bool {
        guard let nav = split?.side as? UINavigationController, let p = nav.viewControllers.first as? PdfPaneController else { return false }
        return p.url.standardizedFileURL == root.appendingPathComponent(rel).standardizedFileURL
    }

    func toggleMarkscheme(_ ms: String) {
        if showingInSide(ms) { split?.closeSide() } else { showClean(ms, title: "Markscheme") }
        refreshExtraButtons()
    }

    /// A PDF on its own, in the second pane (or over the board where there is none).
    func showClean(_ rel: String, title: String) {
        let url = root.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: url.path) else { toast("\((rel as NSString).lastPathComponent) isn't in the folder"); return }
        if let split {
            split.showPDF(url, title: title)
        } else {
            let pane = PdfPaneController(url: url, title: title, onClose: { [weak self] in self?.dismiss(animated: true) })
            let nav = UINavigationController(rootViewController: pane)
            nav.modalPresentationStyle = .pageSheet
            present(nav, animated: true)
        }
    }

    /// The file icon beside page 1 of each printout (drawn with the links, in screen points).
    func paintPrintoutIcons(_ o: LinkOverlay, visible vis: CGRect) {
        for (id, p) in pdfs {
            guard let first = p.frames.first else { continue }
            let r = screenRect(first)
            guard r.intersects(vis) else { continue }
            // beside page 1's top corner; when that is off the screen (zoomed in, or a pane beside), inside the page's corner
            let x = r.maxX + 8 + 32 <= vis.maxX ? r.maxX + 8 : max(r.minX + 8, vis.maxX - 44)
            let at = CGRect(x: x, y: r.minY, width: 32, height: 32)
            let b = o.button("clean:" + id) {
                var c = UIButton.Configuration.filled()
                c.cornerStyle = .capsule
                c.image = UIImage(systemName: "doc.text", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium))
                c.baseBackgroundColor = .secondarySystemBackground
                c.baseForegroundColor = .secondaryLabel
                let b = UIButton(configuration: c, primaryAction: UIAction { [weak self] _ in self?.openCleanPrintout(id) })
                b.accessibilityLabel = "The PDF on its own"
                b.accessibilityIdentifier = "printout-clean"
                b.toolTip = "The PDF on its own, with no ink"
                b.layer.shadowColor = UIColor.black.cgColor
                b.layer.shadowOpacity = 0.12
                b.layer.shadowRadius = 2
                b.layer.shadowOffset = CGSize(width: 0, height: 1)
                return b
            }
            b.frame = at
        }
    }

    func openCleanPrintout(_ id: String) {
        guard let it = pdfs[id]?.item, let rel = BoardLinks.resolve(path, it.src ?? "") else { return }
        showClean(rel, title: ((rel as NSString).lastPathComponent as NSString).deletingPathExtension)
    }
}
