import UIKit
import NexusCore

/// Tools on the board (nexus docs/data-format.md "Tools on the board"): the Tools panel from the right, live cards and pictures.
/// A card is used in the panel (tap it twice): what you do there is kept on the card without an undo step, as on the laptop, since
/// using a tool is not an edit of the board. Putting, moving, picturing and removing a card are edits, with undo.
extension BoardController {
    @objc func toggleToolPanel() {
        if toolPanel == nil { openToolPanel() } else { closeToolPanel() }
    }

    /// Where the panel sits: on the right, under the bar; widened (its header's expand button), about 70% of the board.
    var toolPanelFrame: CGRect {
        // the whole width when the board is narrow (an iPhone), else a side column, widened to about 70% by its expand button
        let W = view.bounds.width
        let w = W < BoardBar.compactWidth ? W : (toolPanel?.wide == true ? max(320, (W * 0.7).rounded()) : min(520, max(320, W * 0.45)))
        return CGRect(x: W - w, y: topInset, width: w, height: view.bounds.height - topInset)
    }

    /// Puts the open panel where `toolPanelFrame` says (after a turn or a resize, or when it is widened). A wide panel keeps its share
    /// of the width as the board resizes (flexible width); a narrow one keeps its width.
    func placeToolPanel() {
        guard let p = toolPanel else { return }
        p.view.autoresizingMask = p.wide ? [.flexibleLeftMargin, .flexibleWidth, .flexibleHeight] : [.flexibleLeftMargin, .flexibleHeight]
        p.view.frame = toolPanelFrame
        p.view.layoutIfNeeded()
    }

    /// The panel's expand button: about 70% of the board's width, or back to its usual width.
    func toggleToolPanelWide() {
        guard let p = toolPanel else { return }
        p.wide.toggle()
        UIView.animate(withDuration: 0.25) { self.placeToolPanel() }
    }

    /// Shows the panel at its list, or with `src` open in it (bound to `card` when given).
    func openToolPanel(src: String? = nil, state: JSONValue? = nil, card: String? = nil) {
        let p: ToolPanelController
        if let open = toolPanel { p = open } else {
            p = ToolPanelController()
            p.board = self
            addChild(p)
            p.view.frame = toolPanelFrame
            p.view.autoresizingMask = [.flexibleLeftMargin, .flexibleHeight]
            view.addSubview(p.view)
            p.didMove(toParent: self)
            toolPanel = p
            p.view.transform = CGAffineTransform(translationX: p.view.bounds.width, y: 0)
            UIView.animate(withDuration: 0.2) { p.view.transform = .identity }
        }
        if let src { p.open(src, state: state, card: card) } else if p.openSrc == nil { p.showList() }
        updateBar()
    }

    func closeToolPanel() {
        guard let p = toolPanel else { return }
        p.letGo()
        toolPanel = nil
        UIView.animate(withDuration: 0.2, animations: {
            p.view.transform = CGAffineTransform(translationX: p.view.bounds.width, y: 0)
        }, completion: { _ in
            p.willMove(toParent: nil)
            p.view.removeFromSuperview()
            p.removeFromParent()
        })
        updateBar()
        if !readOnly { canvas.becomeFirstResponder() }
    }

    /// Opens a card in the panel, bound to it.
    func useToolCard(_ id: String) {
        guard let it = content.items.first(where: { $0.id == id }), it.type == "tool" else { return }
        if it.string("show") == "picture" { tell("This card is a picture. Show it live first (… on the bar) to use it.", brief: false); return }
        openToolPanel(src: it.src ?? "", state: it.json["state"], card: readOnly ? nil : id)
    }

    /// What the panel's tool handed back, kept on its card (no undo step).
    func keepToolState(_ id: String, _ state: JSONValue) {
        guard !readOnly, let s = ToolCatalog.keepState(state), let i = content.items.firstIndex(where: { $0.id == id }) else { return }
        guard content.items[i].json["state"] != s else { return }
        content.items[i] = content.items[i].with("state", s)
        changed()
    }

    /// While the panel uses a card, the card isn't started again for each state; when it lets go, the card shows where it was left.
    func holdToolCard(_ id: String, _ hold: Bool) {
        guard let v = itemViews[id] as? ToolCardView else { return }
        v.holding = hold
        if !hold { rebuildItems() }
    }

    /// A new card where you look: live, or a picture (`image`, with the picture's size).
    func addToolCard(_ src: String, state: JSONValue?, image: String?, size: CGSize?) {
        guard !readOnly else { tell("This board can't be changed here."); return }
        let id = BoardFormat.newId(taken: allIds)
        let p = insertPoint
        let it = ToolCatalog.item(id: id, src: src, x: Double(p.x), y: Double(p.y),
                                  w: size.map { Double($0.width) }, h: size.map { Double($0.height) }, image: image, state: state)
        changeItems(image == nil ? "Add tool" : "Add picture") { c in
            c.items.append(it)
            let meta = c.meta ?? (try? JSONValue.parse(BoardFormat.boardJSON()))
            if let meta { c.meta = BoardFormat.withFeature(meta, ToolCatalog.feature) }
        }
        selected = id
        toast(image == nil ? "Put on the board: tap it twice to use it" : "A picture of it is on the board")
    }

    /// Saves a picture into the board's files/, as the laptop names it ("<tool> <yyyy-MM-dd HHmm>.png"); its src, or nil.
    func saveToolPicture(_ png: Data, title: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HHmm"
        let filesDir = boardURL.appendingPathComponent("files", isDirectory: true)
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: filesDir.path)) ?? [])
        let name = BoardFormat.freeName(title + " " + f.string(from: Date()), taken: taken, suffix: ".png")
        do { try FolderAccess.writeData(filesDir.appendingPathComponent(name), png) } catch {
            tell("Couldn't save the picture: \(error.localizedDescription)")
            return nil
        }
        return "files/" + name
    }

    func toolCardToPicture(_ id: String, image: String) {
        changeItems("Picture") { c in
            if let i = c.items.firstIndex(where: { $0.id == id }) { c.items[i] = c.items[i].with("show", .string("picture")).with("image", .string(image)) }
        }
    }

    /// The bar's buttons for a picked card: use it, and its menu.
    func toolCardButtons(_ it: BoardItem) -> [UIButton] {
        let id = it.id
        let live = it.string("show") != "picture"
        var actions: [UIMenuElement] = []
        if live {
            actions.append(UIAction(title: "Show as a picture", image: UIImage(systemName: "photo")) { [weak self] _ in self?.pictureOfCard(id) })
        } else {
            actions.append(UIAction(title: "Show it live", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
                self?.changeItems("Show live") { c in
                    if let i = c.items.firstIndex(where: { $0.id == id }) { c.items[i] = c.items[i].with("show", .string("live")) }
                }
            })
        }
        actions.append(UIAction(title: "Open a copy in the Tools panel", image: UIImage(systemName: "sidebar.right")) { [weak self] _ in
            self?.openToolPanel(src: it.src ?? "", state: it.json["state"], card: nil)
        })
        var c = UIButton.Configuration.gray()
        c.image = UIImage(systemName: "ellipsis")
        c.cornerStyle = .capsule
        c.buttonSize = .small
        let more = UIButton(configuration: c)
        more.menu = UIMenu(children: actions)
        more.showsMenuAsPrimaryAction = true
        var out = [more]
        if live {
            var u = UIButton.Configuration.gray()
            u.title = "Use"
            u.cornerStyle = .capsule
            u.buttonSize = .small
            out.append(UIButton(configuration: u, primaryAction: UIAction { [weak self] _ in self?.useToolCard(id) }))
        }
        return out
    }

    /// Turns a live card into a picture of what it shows now.
    func pictureOfCard(_ id: String) {
        guard let v = itemViews[id] as? ToolCardView, let page = v.page,
              let it = content.items.first(where: { $0.id == id }) else { tell("The picture could not be taken."); return }
        page.snapshot { [weak self] img in
            guard let self else { return }
            guard let img, let png = img.pngData() else { self.tell("The picture could not be taken."); return }
            guard let image = self.saveToolPicture(png, title: ToolCatalog.title(it.src)) else { return }
            self.toolCardToPicture(id, image: image)
        }
    }
}
