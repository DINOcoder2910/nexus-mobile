import SwiftUI
import UIKit
import NexusCore

/// The data booklet on a board, as the laptop's Solve full screen has it (D): a Data booklet button in the bar (in the iPhone's ⋯)
/// of a paper's board, or any board while solving a question full screen, puts a subject's IB data booklet in the second pane
/// (stacked under the board on an iPhone): the question's subject's first, any other subject's from the pane's switch
/// (BookletPane, the same as beside a question).
extension BoardController {
    /// whose booklet comes first: the question being solved's subject, else the subject this board is filed under
    var bookletSubject: String? {
        if solving, let id = BankLibrary.shared.returnTo?.workstream { return id }
        return questionSubject()
    }

    var showingBooklet: Bool {
        guard let nav = split?.side as? UINavigationController else { return false }
        return nav.viewControllers.first is BookletHost
    }

    /// the Data booklet button, on a paper's board or while solving, when a subject has a booklet
    func bookletBarButtons() -> [UIButton] {
        guard !isSidePane, split != nil, solving || paperOfBoard != nil, let store, !BookletShelf.list(store, first: nil).isEmpty else { return [] }
        let on = showingBooklet
        let b = extraButton("book.pages", on ? "Hide the data booklet" : "Data booklet", tinted: on) { [weak self] in self?.toggleBooklet() }
        b.accessibilityIdentifier = "board-booklet"
        b.toolTip = "The data booklet beside the board (D)"
        return [b]
    }

    func toggleBooklet() {
        guard let split, let store else { return }
        if showingBooklet {
            split.closeSide()
        } else {
            let host = BookletHost(rootView: AnyView(BookletPane(subject: bookletSubject ?? "", close: { [weak split, weak self] in
                split?.closeSide()
                self?.refreshExtraButtons()
            }).environment(store)))
            let nav = UINavigationController(rootViewController: host)
            nav.setNavigationBarHidden(true, animated: false) // the pane has its own head
            split.show(nav)
        }
        refreshExtraButtons()
    }
}

/// The booklet pane in Side by side (so the board knows its second pane is the booklet).
final class BookletHost: UIHostingController<AnyView> {}
