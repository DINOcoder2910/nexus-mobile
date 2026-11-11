import UIKit
import SwiftUI
import PencilKit
import PhotosUI
import UniformTypeIdentifiers
import NexusCore

/// Fingers on the board (with the Pencil drawing): tap an item to pick it, tap a picked text block to edit it, tap a checkbox to
/// tick it, drag a picked item to move it, drag its corner to resize it, press and hold to pick a PDF printout. The + menu puts
/// typed text, images, PDF printouts and shapes on the board. Item changes join the Pencil's undo.
extension BoardController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    struct Drag {
        var id: String
        var resize: Bool
        var start: BoardItem
        var startSize: CGSize
        var before: ([BoardItem], [String: String])
    }

    static let direct = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

    func setUpGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.allowedTouchTypes = BoardController.direct
        tap.delegate = self
        canvas.addGestureRecognizer(tap)

        let long = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        long.allowedTouchTypes = BoardController.direct
        long.minimumPressDuration = 0.45
        long.delegate = self
        canvas.addGestureRecognizer(long)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.name = "itemPan"
        pan.allowedTouchTypes = BoardController.direct
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        canvas.addGestureRecognizer(pan)
        canvas.panGestureRecognizer.require(toFail: pan)

        hold.delegate = self
        canvas.addGestureRecognizer(hold)
    }

    func boardPoint(_ g: UIGestureRecognizer) -> CGPoint {
        let p = g.location(in: canvas), z = canvas.zoomScale
        return CGPoint(x: p.x / z - offset.x, y: p.y / z - offset.y)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g === hold || other === hold
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g.name == "itemPan", let pan = g as? UIPanGestureRecognizer else { return true }
        guard !readOnly, let id = selected, let it = content.items.first(where: { $0.id == id }) else { return false }
        let z = canvas.zoomScale
        let t = pan.translation(in: canvas)
        let now = boardPoint(pan)
        let start = CGPoint(x: now.x - t.x / z, y: now.y - t.y / z)
        let b = box(of: it)
        if it.type != "pdf", hypot(start.x - (b.maxX + 4 / z), start.y - (b.maxY + 4 / z)) < 24 / z { return true }
        return b.insetBy(dx: -8 / z, dy: -8 / z).contains(start)
    }

    /// The item under a board point, top layer first (typed text, shapes, images, then PDF printouts if asked).
    func hitItem(_ p: CGPoint, pdf: Bool) -> BoardItem? {
        let z = canvas.zoomScale
        let order = ["text": 0, "shape": 1, "image": 2, "pdf": 3]
        let items = content.items.filter { pdf || $0.type != "pdf" }.sorted { (order[$0.type] ?? 9, $1.id) < (order[$1.type] ?? 9, $0.id) }
        return items.first { box(of: $0).insetBy(dx: -6 / z, dy: -6 / z).contains(p) }
    }

    @objc func tapped(_ g: UITapGestureRecognizer) {
        let p = boardPoint(g)
        guard let it = hitItem(p, pdf: false) else { selected = nil; return }
        if it.type == "text", !readOnly {
            if let v = itemViews[it.id] as? TextBlockView,
               let line = v.taskLine(at: CGPoint(x: p.x - it.x, y: p.y - it.y)),
               let md = TextLook.toggleTask(content.texts[it.id] ?? "", line: line) {
                changeItems("Tick") { $0.texts[it.id] = md }
                return
            }
            if selected == it.id { edit(it); return }
        }
        selected = it.id
    }

    @objc func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        if let it = hitItem(boardPoint(g), pdf: true) {
            selected = it.id
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    @objc func panned(_ g: UIPanGestureRecognizer) {
        let z = canvas.zoomScale
        switch g.state {
        case .began:
            guard let id = selected, let it = content.items.first(where: { $0.id == id }) else { return }
            let t = g.translation(in: canvas)
            let now = boardPoint(g)
            let start = CGPoint(x: now.x - t.x / z, y: now.y - t.y / z)
            let b = box(of: it)
            let resize = it.type != "pdf" && hypot(start.x - (b.maxX + 4 / z), start.y - (b.maxY + 4 / z)) < 24 / z
            drag = Drag(id: id, resize: resize, start: it, startSize: textSizes[id] ?? b.size, before: (content.items, content.texts))
        case .changed:
            guard let d = drag, let i = content.items.firstIndex(where: { $0.id == d.id }) else { return }
            let t = g.translation(in: canvas)
            let dx = Double(t.x / z), dy = Double(t.y / z)
            content.items[i] = d.resize ? resized(d, dx, dy) : d.start.with("x", .number(d.start.x + dx)).with("y", .number(d.start.y + dy))
            rebuildItems()
        case .ended, .cancelled, .failed:
            guard let d = drag else { return }
            drag = nil
            if let i = content.items.firstIndex(where: { $0.id == d.id }) {
                // the laptop keeps places to 2 decimals; whole units read better
                let it = content.items[i]
                content.items[i] = it.with("x", .number(it.x.rounded())).with("y", .number(it.y.rounded()))
            }
            registerItemsUndo(d.before, d.resize ? "Resize" : "Move")
            rebuildItems()
            growIfNeeded()
            changed()
        default:
            break
        }
    }

    func resized(_ d: Drag, _ dx: Double, _ dy: Double) -> BoardItem {
        let it = d.start
        switch it.type {
        case "image":
            let w0 = it.w ?? Double(d.startSize.width), h0 = it.h ?? Double(d.startSize.height)
            let w = max(20, (w0 + dx).rounded())
            return it.with("w", .number(w)).with("h", .number((w * h0 / max(w0, 1)).rounded()))
        case "shape":
            let w0 = it.w ?? 100, h0 = it.h ?? 60
            if it.shape == "line" || it.shape == "arrow" {
                return it.with("w", .number((w0 + dx).rounded())).with("h", .number((h0 + dy).rounded()))
            }
            return it.with("w", .number(max(4, (w0 + dx).rounded()))).with("h", .number(max(4, (h0 + dy).rounded())))
        case "text":
            let w0 = it.w ?? Double(d.startSize.width)
            return it.with("w", .number(max(60, (w0 + dx).rounded())))
        default:
            return it
        }
    }

    // MARK: item changes, with undo

    func changeItems(_ name: String, _ body: (inout BoardContent) -> Void) {
        let before = (content.items, content.texts)
        body(&content)
        registerItemsUndo(before, name)
        rebuildItems()
        growIfNeeded()
        changed()
    }

    func registerItemsUndo(_ snap: ([BoardItem], [String: String]), _ name: String) {
        guard let um = canvas.undoManager else { return }
        um.registerUndo(withTarget: self) { me in
            let now = (me.content.items, me.content.texts)
            me.content.items = snap.0
            me.content.texts = snap.1
            if let id = me.selected, !snap.0.contains(where: { $0.id == id }) { me.selected = nil }
            me.registerItemsUndo(now, name)
            me.rebuildItems()
            me.changed()
        }
        um.setActionName(name)
    }

    @objc func deleteSelected() {
        guard let id = selected else { return }
        selected = nil
        changeItems("Delete") { c in
            c.items.removeAll { $0.id == id }
            c.texts[id] = nil
        }
    }

    @objc func editSelected() {
        if let id = selected, let it = content.items.first(where: { $0.id == id }) { edit(it) }
    }

    /// The text block's editor: its markdown, size, colour and background.
    func edit(_ it: BoardItem) {
        guard !readOnly else { return }
        let id = it.id
        // the editor closes itself
        let editor = TextBlockEditor(markdown: content.texts[id] ?? "", item: it, onDone: { [weak self] md, item in
            self?.finishEdit(id, md, item)
        }, onDelete: { [weak self] in
            self?.selected = nil
            self?.changeItems("Delete") { c in c.items.removeAll { $0.id == id }; c.texts[id] = nil }
        })
        let host = UIHostingController(rootView: AnyView(editor.onDisappear { [weak self] in self?.dropIfEmpty(id) }))
        host.modalPresentationStyle = .formSheet
        present(host, animated: true)
    }

    func finishEdit(_ id: String, _ md: String, _ item: BoardItem) {
        guard content.items.contains(where: { $0.id == id }) else { return }
        if md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selected = nil
            changeItems("Delete") { c in c.items.removeAll { $0.id == id }; c.texts[id] = nil }
            return
        }
        changeItems("Edit text") { c in
            if let i = c.items.firstIndex(where: { $0.id == id }) { c.items[i] = item }
            c.texts[id] = md
        }
    }

    /// A new block left empty goes away again (as on the laptop).
    func dropIfEmpty(_ id: String) {
        guard let md = content.texts[id], md.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              content.items.contains(where: { $0.id == id }) else { return }
        if selected == id { selected = nil }
        content.items.removeAll { $0.id == id }
        content.texts[id] = nil
        rebuildItems()
        changed()
    }

    // MARK: inserting

    func insertMenu() -> UIMenu {
        let shapes = UIMenu(title: "Shape", image: UIImage(systemName: "square.on.circle"), children: [
            UIAction(title: "Rectangle", image: UIImage(systemName: "rectangle")) { [weak self] _ in self?.insertShape("rect") },
            UIAction(title: "Ellipse", image: UIImage(systemName: "circle")) { [weak self] _ in self?.insertShape("ellipse") },
            UIAction(title: "Line", image: UIImage(systemName: "line.diagonal")) { [weak self] _ in self?.insertShape("line") },
            UIAction(title: "Arrow", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in self?.insertShape("arrow") },
        ])
        return UIMenu(children: [
            UIAction(title: "Text", image: UIImage(systemName: "textformat")) { [weak self] _ in self?.insertText() },
            UIAction(title: "Image…", image: UIImage(systemName: "photo")) { [weak self] _ in self?.pickImage() },
            UIAction(title: "PDF printout…", image: UIImage(systemName: "doc.richtext")) { [weak self] _ in self?.pickPdf() },
            shapes,
        ])
    }

    var allIds: Set<String> { Set(content.items.map(\.id)).union(content.strokes.map(\.id)) }

    /// A little above and left of the middle of the screen.
    var insertPoint: CGPoint {
        let v = visibleBoard
        return CGPoint(x: (v.minX + v.width * 0.3).rounded(), y: (v.minY + v.height * 0.3).rounded())
    }

    func insertText() {
        let id = BoardFormat.newId(taken: allIds)
        let p = insertPoint
        let it = BoardItem(id: id, type: "text", x: Double(p.x), y: Double(p.y))
        changeItems("Add text") { c in c.items.append(it); c.texts[id] = "" }
        selected = id
        edit(it)
    }

    var currentColor: String {
        if let tool = canvas.tool as? PKInkingTool { return InkConvert.hex(tool.color) }
        return "#1B1B1BFF"
    }

    func insertShape(_ kind: String) {
        let id = BoardFormat.newId(taken: allIds)
        let p = insertPoint
        let size: (Double, Double) = kind == "rect" ? (200, 120) : kind == "ellipse" ? (160, 160) : (200, 0)
        let it = BoardItem(id: id, type: "shape", x: Double(p.x), y: Double(p.y), fields: [
            ("shape", .string(kind)), ("w", .number(size.0)), ("h", .number(size.1)), ("color", .string(currentColor)), ("width", .number(3)),
        ])
        changeItems("Add shape") { c in c.items.append(it) }
        selected = id
    }

    func pickImage() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
            guard let img = obj as? UIImage else { return }
            DispatchQueue.main.async { self?.insertImage(img) }
        }
    }

    func insertImage(_ img: UIImage) {
        let hasAlpha: Bool = {
            guard let a = img.cgImage?.alphaInfo else { return false }
            return a == .first || a == .last || a == .premultipliedFirst || a == .premultipliedLast
        }()
        guard let data = hasAlpha ? img.pngData() : img.jpegData(compressionQuality: 0.85) else { tell("That image couldn't be read."); return }
        let ext = hasAlpha ? ".png" : ".jpg"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        let filesDir = boardURL.appendingPathComponent("files", isDirectory: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: filesDir.path)) ?? [])
        let name = BoardFormat.freeName("image " + f.string(from: Date()), taken: taken, suffix: ext)
        do { try FolderAccess.writeData(filesDir.appendingPathComponent(name), data) } catch { tell("Couldn't add the image: \(error.localizedDescription)"); return }
        let id = BoardFormat.newId(taken: allIds)
        let p = insertPoint
        let w = min(600, Double(img.size.width)), h = (w * Double(img.size.height) / max(Double(img.size.width), 1)).rounded()
        let it = BoardItem(id: id, type: "image", x: Double(p.x), y: Double(p.y), fields: [
            ("src", .string("files/" + name)), ("w", .number(w.rounded())), ("h", .number(h)),
        ])
        changeItems("Add image") { c in c.items.append(it) }
        selected = id
    }

    func pickPdf() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    /// A PDF printout goes beside the board (as on the laptop), and its pages down the board from the insert point.
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let dir = boardURL.deletingLastPathComponent()
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let name = BoardFormat.freeName(url.deletingPathExtension().lastPathComponent, taken: taken, suffix: ".pdf")
        do {
            let data = try Data(contentsOf: url)
            try FolderAccess.writeData(dir.appendingPathComponent(name), data)
        } catch { tell("Couldn't bring the PDF in: \(error.localizedDescription)"); return }
        let id = BoardFormat.newId(taken: allIds)
        let p = insertPoint
        let it = BoardItem(id: id, type: "pdf", x: Double(p.x), y: Double(p.y), fields: [
            ("src", .string("../" + name)), ("w", .number(BoardFormat.pdfWidth)), ("gap", .number(BoardFormat.pdfGap)),
        ])
        changeItems("Add PDF") { c in c.items.append(it) }
    }
}
