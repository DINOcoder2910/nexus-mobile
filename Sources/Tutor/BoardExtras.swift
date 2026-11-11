import UIKit

extension BoardController {
    /// The tutor, recording and read aloud buttons in the board's bar.
    func boardExtraBarItems() -> [UIBarButtonItem] {
        var out: [UIBarButtonItem] = []
        if !readOnly { out.append(tutorBarItem()) }
        out.append(recordBarItem())
        if let r = readAloudBarItem() { out.append(r) }
        return out
    }
}
