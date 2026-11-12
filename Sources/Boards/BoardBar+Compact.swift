import UIKit
import NexusCore

/// The board's bar when it is narrow: an iPhone, or a narrow pane on the iPad. Three rows instead of two, so nothing is squeezed:
/// - the way back, the board's name, undo, redo and ⋯ (everything else: the Tools panel, the tutor, recording, read aloud,
///   links, the background, zoom, pages, the ruler and the board menu);
/// - the tools and +, across the whole width;
/// - what the current tool needs, and the picked item's actions.
extension BoardBar {
    /// Narrower than this, the bar is compact.
    static let compactWidth: CGFloat = 560

    func refreshCompact(_ b: BoardController) {
        let readOnly = b.readOnly
        HoldTarget.shared.actions.removeAll()
        middleRow.isHidden = false

        // top row: back, name, undo, redo, ⋯
        clear(topRow)
        topRow.addArrangedSubview(icon(b.isSidePane ? "xmark" : "chevron.backward", b.isSidePane ? "Close this pane" : "Close the board") { [weak b] in b?.close() })
        if b.onSidebar != nil, !Device.isPhone { topRow.addArrangedSubview(icon("sidebar.left", "Sidebar") { [weak b] in b?.onSidebar?() }) }
        var tc = UIButton.Configuration.plain()
        tc.title = b.boardName
        tc.subtitle = b.placeName
        tc.titleLineBreakMode = .byTruncatingMiddle
        tc.subtitleLineBreakMode = .byTruncatingHead
        tc.titleAlignment = .leading
        tc.baseForegroundColor = .label
        tc.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        titleButton.configuration = tc
        titleButton.menu = b.titleMenu()
        topRow.addArrangedSubview(titleButton)
        topRow.addArrangedSubview(spacer())
        if !readOnly {
            topRow.addArrangedSubview(icon("arrow.uturn.backward", "Undo") { [weak b] in b?.undo() })
            topRow.addArrangedSubview(icon("arrow.uturn.forward", "Redo") { [weak b] in b?.redo() })
        }
        let more = menuButton("ellipsis.circle", "More", UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak b] done in done(b?.compactMenu() ?? []) },
        ]))
        topRow.addArrangedSubview(more)

        // middle row: the tools and +
        clear(middleRow)
        clear(toolsStack)
        if !readOnly {
            for t in BoardTool.allCases {
                toolsStack.addArrangedSubview(icon(t.symbol, t.title, selected: BoardTools.shared.tool == t) { [weak b] in b?.selectTool(t) })
            }
            toolsStack.addArrangedSubview(menuButton("plus", "Insert", b.insertMenu()))
        } else {
            toolsStack.addArrangedSubview(label("Read only"))
        }
        middleRow.addArrangedSubview(toolsScroll)
        middleRow.addArrangedSubview(spacer())

        // tool row: what the tool needs, then the picked item's actions
        clear(toolRow)
        clear(rowStack)
        clear(rightStack)
        if !readOnly { fillToolRow(b) }
        toolRow.addArrangedSubview(rowScroll)
        toolRow.addArrangedSubview(spacer())
        if let it = b.selectedItem, !readOnly {
            if it.type == "text" {
                rightStack.addArrangedSubview(textButton("Type", "character.cursor.ibeam") { [weak b] in b?.editSelected() })
            }
            if it.type == "tool" { b.toolCardButtons(it).forEach { rightStack.addArrangedSubview($0) } }
            rightStack.addArrangedSubview(textButton("Delete", "trash") { [weak b] in b?.deleteSelected() })
        }
        toolRow.addArrangedSubview(rightStack)
        updatePills()
    }
}

extension BoardController {
    /// ⋯ on a narrow bar: what the wide bar shows as its own buttons, then the board menu.
    func compactMenu() -> [UIMenuElement] {
        let extras = extraBarButtons().compactMap(menuElement(for:))
        var view: [UIMenuElement] = []
        if !readOnly { view.append(backgroundMenu()) }
        view.append(UIMenu(title: "Zoom \(Int((canvas.zoomScale * 100).rounded()))%", image: UIImage(systemName: "plus.magnifyingglass"), children: zoomMenu().children))
        if !pdfs.isEmpty {
            view.append(UIMenu(title: pageLabel.isEmpty ? "Pages" : pageLabel, image: UIImage(systemName: "doc.text"), children: pageMenu().children))
        }
        if !readOnly {
            view.append(UIAction(title: "Ruler", image: UIImage(systemName: "ruler"), state: canvas.isRulerActive ? .on : .off) { [weak self] _ in self?.toggleRuler() })
        }
        return [
            UIMenu(options: .displayInline, children: extras),
            UIMenu(options: .displayInline, children: view),
            UIMenu(options: .displayInline, children: boardMenu().children),
        ]
    }

    /// One of the wide bar's buttons as a menu item: its menu as a submenu, else its action.
    func menuElement(for button: UIButton) -> UIMenuElement? {
        let image = button.configuration?.image
        // the bar's buttons are tinted while on (an open panel, link mode, recording) and label-coloured while off
        let on = button.isSelected || button.tintColor != UIColor.label
        if let t = button as? TutorHoldButton {
            return UIAction(title: "Tutor", image: image) { _ in t.onTap?() }
        }
        let title = button.accessibilityLabel ?? button.toolTip ?? ""
        guard !title.isEmpty else { return nil }
        if let m = button.menu {
            return UIMenu(title: title, image: image, children: m.children)
        }
        return UIAction(title: title, image: image, state: on ? .on : .off) { _ in button.sendActions(for: .primaryActionTriggered) }
    }
}
