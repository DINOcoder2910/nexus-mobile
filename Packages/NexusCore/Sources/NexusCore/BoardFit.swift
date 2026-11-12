import Foundation

/// "Show everything" on a board (the zoom pill's menu, a two-finger double tap): the zoom and the place that put a box (board units)
/// on a screen area (points) with a margin round it. Never past 100%, so a little ink isn't blown up to fill the screen.
public enum BoardFit {
    /// Where to look: the board point at the top left of the screen area, and the zoom.
    public struct View: Equatable {
        public var x, y, zoom: Double
        public init(x: Double, y: Double, zoom: Double) {
            self.x = x; self.y = y; self.zoom = zoom
        }
    }

    /// The box `minX…maxX` × `minY…maxY` in the middle of a `width` × `height` screen area, `margin` points clear of its edges, at the
    /// largest zoom that fits (at most 100%, kept between `minZoom` and `maxZoom`).
    public static func fit(minX: Double, minY: Double, maxX: Double, maxY: Double, width: Double, height: Double,
                           margin: Double = 40, minZoom: Double, maxZoom: Double) -> View {
        let w = max(1, maxX - minX), h = max(1, maxY - minY)
        let room = (max(1, width - 2 * margin), max(1, height - 2 * margin))
        let z = max(minZoom, min(maxZoom, 1, room.0 / w, room.1 / h))
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        return View(x: midX - width / 2 / z, y: midY - height / 2 / z, zoom: z)
    }
}
