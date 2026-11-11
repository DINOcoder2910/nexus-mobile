import UIKit
import PencilKit
import NexusCore

/// Moving what is on the board up or down to make or close space: Make room and Push things below (typing) and Insert space
/// (the Select tool's thread owns this file from here on).
extension BoardController {
    /// Moves every stroke and item whose top is at or below `line` down by `by` (strokes keep their ids). One undo step when named.
    func shift(below line: CGFloat, by: CGFloat, except id: String, name: String?) {
        syncStrokes()
        let beforeStrokes = content.strokes
        let beforeItems = (content.items, content.texts)
        var moved = false
        for i in content.strokes.indices {
            let s = content.strokes[i]
            let top = s.points.map { $0.count >= 2 ? $0[1] : .infinity }.min() ?? .infinity
            guard Double(line) <= top else { continue }
            content.strokes[i].points = s.points.map { p in
                var q = p
                if q.count >= 2 { q[1] = InkConvert.r2(q[1] + Double(by)) }
                return q
            }
            moved = true
        }
        for i in content.items.indices where content.items[i].id != id {
            let it = content.items[i]
            guard box(of: it).minY >= line else { continue }
            content.items[i] = it.with("y", .number((it.y + Double(by)).rounded()))
            moved = true
        }
        guard moved else { return }
        redrawStrokes()
        if let name { registerBoardUndo(strokes: beforeStrokes, items: beforeItems, name) }
        rebuildItems()
        writing?.place()
        changed()
    }
}
