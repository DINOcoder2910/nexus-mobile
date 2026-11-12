import UIKit

extension BoardController {
    /// The tutor, recording and read aloud buttons in the board's top row (BoardBar asks through extraBarButtons()).
    func boardExtraButtons() -> [UIButton] {
        var out: [UIButton] = []
        if !readOnly { out.append(tutorButton()) }
        out.append(recordButton())
        out.append(readAloudButton())
        return out
    }

    /// Rebuilds the bar when one of these buttons changes (the bar itself only rebuilds when the board's own state does).
    func refreshExtraButtons() {
        lastBarKey = ""
        updateBar()
    }

    /// A button in the bar's look: an icon, a label for VoiceOver, and an action or a menu.
    func extraButton(_ symbol: String, _ label: String, tinted: Bool = false, menu: UIMenu? = nil, action: (() -> Void)? = nil) -> UIButton {
        var c = tinted ? UIButton.Configuration.tinted() : UIButton.Configuration.plain()
        c.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        c.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)
        c.cornerStyle = .medium
        let b = action.map { a in UIButton(configuration: c, primaryAction: UIAction { _ in a() }) } ?? UIButton(configuration: c)
        if let menu { b.menu = menu; b.showsMenuAsPrimaryAction = true }
        b.accessibilityLabel = label
        b.toolTip = label
        b.tintColor = tinted ? .tintColor : .label
        return b
    }
}
